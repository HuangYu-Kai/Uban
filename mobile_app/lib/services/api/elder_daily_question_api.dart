import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

/// ★ 2026-10-07 每日一問（長輩端）：今天要問長輩的問題（題庫或家人出的）。
///
/// ⚠️ 家屬端的對應檔是 `daily_question_api.dart`（`DailyQuestionApi`／`DailyQuestionItem`），
/// 長輩端刻意獨立成本檔、類別加 Elder 前綴，避免兩端同名衝突。
class DailyQuestion {
  final int id;
  final String question;
  final String? category;
  final String? tag;

  /// 'bank'（題庫）或 'family'（家人出題）。
  final String source;
  final String? askedByName;
  final String? assignedDate;
  final bool answered;
  final String? answerText;
  final String? answerAudioUrl;
  final String? answeredAt;

  const DailyQuestion({
    required this.id,
    required this.question,
    this.category,
    this.tag,
    this.source = 'bank',
    this.askedByName,
    this.assignedDate,
    this.answered = false,
    this.answerText,
    this.answerAudioUrl,
    this.answeredAt,
  });

  bool get isFromFamily => source == 'family';
  bool get hasAnswerAudio => answerAudioUrl != null && answerAudioUrl!.isNotEmpty;

  static String? _nz(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  /// 格式不合（沒有 id 或題目空白）回傳 null。
  static DailyQuestion? tryParse(dynamic m) {
    if (m is! Map) return null;
    final id = int.tryParse((m['id'] ?? '').toString());
    final q = _nz(m['question']);
    if (id == null || q == null) return null;
    final ans = m['answered'];
    return DailyQuestion(
      id: id,
      question: q,
      category: _nz(m['category']),
      tag: _nz(m['tag']),
      source: _nz(m['source']) ?? 'bank',
      askedByName: _nz(m['askedByName'] ?? m['asked_by_name']),
      assignedDate: _nz(m['assignedDate'] ?? m['assigned_date']),
      answered: ans == true || ans == 1 || ans == '1' || ans == 'true',
      answerText: _nz(m['answerText'] ?? m['answer_text']),
      answerAudioUrl: _nz(m['answerAudioUrl'] ?? m['answer_audio_url']),
      answeredAt: _nz(m['answeredAt'] ?? m['answered_at']),
    );
  }
}

/// 送出回答的結果。
class DailyAnswerResult {
  final bool ok;
  final String message;
  const DailyAnswerResult(this.ok, this.message);
}

/// ★ 2026-10-07 每日一問（長輩端）API 層。
class ElderDailyQuestionApi {
  static const String networkErrorMessage = '目前連不上伺服器，請稍後再試一次';

  /// 長輩端 App 內刷新訊號：Socket `daily-question-new`、回答成功後遞增，
  /// 外殼（elder_home_screen）監聽後重讀並更新 [hasUnanswered]
  /// （不放進 Signaling，避免顯示狀態旗標，見護欄）。
  static final ValueNotifier<int> refreshSignal = ValueNotifier<int>(0);

  /// ★ 2026-10-07 每日一問改留聊天：今天的題目存在且尚未回答 → true，
  /// 底部導覽「聊天」分頁顯示小紅點。只有回答後才會變 false（切到聊天分頁不清除）。
  static final ValueNotifier<bool> hasUnanswered = ValueNotifier<bool>(false);

  /// 讀 GET /daily_question/today 更新 [hasUnanswered]。
  /// 失敗（網路／非 success）保留前一個值，避免紅點閃爍；成功但沒有題目 → false。
  static Future<void> refreshBadge(Object elderId) async {
    try {
      final res = await ApiClient.get('/daily_question/today?elder_id=$elderId');
      if (res == null || res['status'] != 'success') return;
      final data = res['data'];
      final q = data is Map ? DailyQuestion.tryParse(data['question']) : null;
      hasUnanswered.value = q != null && !q.answered;
    } catch (e) {
      debugPrint('⚠️ ElderDailyQuestionApi.refreshBadge error: $e');
    }
  }

  /// 讀取今天的問題；沒有題目或失敗一律回 null（不打擾長輩）。
  static Future<DailyQuestion?> getToday(Object elderId) async {
    try {
      final res = await ApiClient.get('/daily_question/today?elder_id=$elderId');
      if (res != null && res['status'] == 'success') {
        final data = res['data'];
        if (data is Map) return DailyQuestion.tryParse(data['question']);
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ ElderDailyQuestionApi.getToday error: $e');
      return null;
    }
  }

  /// 送出回答（文字與／或錄音）。回答最多 500 字、錄音最大 5MB。
  static Future<DailyAnswerResult> submitAnswer({
    required int questionId,
    required Object elderId,
    String? text,
    String? audioPath,
  }) async {
    try {
      final clean = (text ?? '').trim();
      if (clean.isEmpty && audioPath == null) {
        return const DailyAnswerResult(false, '請先說一說、打字，或錄一段聲音');
      }
      if (clean.length > 500) {
        return const DailyAnswerResult(false, '文字最多 500 字，請再精簡一下');
      }
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiClient.baseUrl}/daily_question/$questionId/answer'),
      );
      request.fields['elder_id'] = elderId.toString();
      if (clean.isNotEmpty) request.fields['text'] = clean;
      if (audioPath != null) {
        final file = File(audioPath);
        if (await file.length() > 5 * 1024 * 1024) {
          return const DailyAnswerResult(false, '錄音檔太大了，請錄短一點再送');
        }
        request.files.add(await http.MultipartFile.fromPath('audio', audioPath));
      }
      final streamed = await request.send().timeout(const Duration(seconds: 45));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['status'] == 'success') {
          return const DailyAnswerResult(true, '已送出');
        }
      }
      debugPrint('⚠️ submitAnswer 非預期狀態: ${response.statusCode}');
      return const DailyAnswerResult(false, networkErrorMessage);
    } catch (e) {
      debugPrint('⚠️ ElderDailyQuestionApi.submitAnswer error: $e');
      return const DailyAnswerResult(false, networkErrorMessage);
    }
  }
}
