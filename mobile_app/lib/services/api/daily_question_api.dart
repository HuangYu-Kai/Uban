import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

/// ★ 2026-10-07 每日一問（家屬端）：一題「每日一問」＋長輩的回答。
///
/// 今日題目（`/today`）與歷史（`/history`）共用同一個形狀；歷史多一個 [cheeredByMe]。
class DailyQuestionItem {
  final int id;
  final String question;
  final String category;
  final String tag;

  /// `ai`／`family` 等來源；家屬出的題 [askedByName] 有名字。
  final String source;
  final String askedByName;
  final String assignedDate;
  final bool answered;
  final String answerText;

  /// 已補上伺服器網域的絕對網址（後端回相對路徑 `/uploads/...`）；沒有語音為 null。
  final String? answerAudioUrl;
  final String answeredAt;
  final bool cheeredByMe;

  const DailyQuestionItem({
    required this.id,
    required this.question,
    this.category = '',
    this.tag = '',
    this.source = '',
    this.askedByName = '',
    this.assignedDate = '',
    this.answered = false,
    this.answerText = '',
    this.answerAudioUrl,
    this.answeredAt = '',
    this.cheeredByMe = false,
  });

  bool get hasAudio => answerAudioUrl != null && answerAudioUrl!.isNotEmpty;

  /// 通知／卡片用的回答摘要；只有語音時回「（語音回答）」。
  String get answerSnippet {
    final t = answerText.trim();
    if (t.isNotEmpty) return t;
    return hasAudio ? '（語音回答）' : '';
  }

  DailyQuestionItem copyWith({bool? cheeredByMe}) => DailyQuestionItem(
        id: id,
        question: question,
        category: category,
        tag: tag,
        source: source,
        askedByName: askedByName,
        assignedDate: assignedDate,
        answered: answered,
        answerText: answerText,
        answerAudioUrl: answerAudioUrl,
        answeredAt: answeredAt,
        cheeredByMe: cheeredByMe ?? this.cheeredByMe,
      );

  /// 相對路徑補上 [ApiClient.serverRootUrl]；已是完整網址則原樣回傳。
  static String? resolveAudioUrl(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return '${ApiClient.serverRootUrl}${s.startsWith('/') ? '' : '/'}$s';
  }

  factory DailyQuestionItem.fromJson(Map<dynamic, dynamic> j) {
    String s(String k) => (j[k] ?? '').toString();
    final audio = resolveAudioUrl(j['answerAudioUrl'] ?? j['answer_audio_url']);
    return DailyQuestionItem(
      id: int.tryParse(s('id')) ?? 0,
      question: s('question'),
      category: s('category'),
      tag: s('tag'),
      source: s('source'),
      askedByName: s('askedByName'),
      assignedDate: s('assignedDate'),
      answered: j['answered'] == true || j['answered'] == 1,
      answerText: s('answerText'),
      answerAudioUrl: audio,
      answeredAt: s('answeredAt'),
      cheeredByMe: j['cheeredByMe'] == true || j['cheeredByMe'] == 1,
    );
  }
}

/// 出題結果。[message] 一律是可直接給家屬看的繁體中文。
class DailyAskResult {
  final bool ok;
  final String message;

  /// `today`／`later`（成功時）。
  final String scheduledFor;
  const DailyAskResult(this.ok, this.message, {this.scheduledFor = ''});
}

/// ★ 2026-10-07 每日一問：家屬端 API 層（長輩端方法若由另一位作者加入，請加在同檔，勿重複建檔）。
class DailyQuestionApi {
  static const String networkErrorMessage = '目前連不上伺服器，請確認網路後再試一次';
  static const int minQuestionLength = 4;
  static const int maxQuestionLength = 80;

  /// 出題成功後給家屬的提示。
  static String askSuccessMessage(String scheduledFor) =>
      scheduledFor == 'later' ? '已排入，長輩明天會看到' : '已送出，長輩今天就會看到';

  /// 今日題目；讀取失敗或今天沒有題目回傳 null。
  static Future<DailyQuestionItem?> getToday({required String elderId}) async {
    try {
      final res = await ApiClient.get(
          '/daily_question/today?elder_id=${Uri.encodeQueryComponent(elderId)}');
      final data = res?['data'];
      final q = data is Map ? data['question'] : null;
      if (res != null && res['status'] == 'success' && q is Map) {
        return DailyQuestionItem.fromJson(q);
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ [DailyQuestionApi] getToday error: $e');
      return null;
    }
  }

  /// 歷史（新→舊，含已回答與家屬出的待答題）；失敗回傳 null（呼叫端顯示友善錯誤）。
  static Future<List<DailyQuestionItem>?> getHistory({
    required String elderId,
    required int familyId,
    int limit = 30,
  }) async {
    try {
      final res = await ApiClient.get(
          '/daily_question/history?elder_id=${Uri.encodeQueryComponent(elderId)}'
          '&family_id=$familyId&limit=$limit');
      final data = res?['data'];
      final items = data is Map ? data['items'] : null;
      if (res != null && res['status'] == 'success' && items is List) {
        return [
          for (final e in items)
            if (e is Map) DailyQuestionItem.fromJson(e),
        ];
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ [DailyQuestionApi] getHistory error: $e');
      return null;
    }
  }

  /// 家屬出一題給長輩。題目 4–80 字，不合格在本機先擋下。
  /// 400（例如待答題太多）後端會回友善中文，直接採用；其他狀況一律用固定中文。
  static Future<DailyAskResult> ask({
    required int familyId,
    required String elderId,
    required String question,
    String? category,
  }) async {
    final q = question.trim();
    if (q.length < minQuestionLength) {
      return const DailyAskResult(false, '題目至少要 4 個字喔');
    }
    if (q.length > maxQuestionLength) {
      return const DailyAskResult(false, '題目最多 80 個字，請再精簡一下');
    }
    try {
      final body = <String, dynamic>{
        'family_id': familyId,
        'elder_id': elderId,
        'question': q,
        if (category != null && category.trim().isNotEmpty)
          'category': category.trim(),
      };
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/daily_question/ask'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 404) {
        return const DailyAskResult(false, '這位長輩目前沒有和您綁定，無法出題');
      }
      Map<String, dynamic>? decoded;
      try {
        final d = jsonDecode(utf8.decode(response.bodyBytes));
        if (d is Map<String, dynamic>) decoded = d;
      } catch (_) {}
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = decoded?['data'];
        final when = data is Map ? (data['scheduled_for'] ?? '').toString() : '';
        return DailyAskResult(true, askSuccessMessage(when), scheduledFor: when);
      }
      if (response.statusCode == 400) {
        final m = (decoded?['message'] ?? decoded?['detail'] ?? '').toString().trim();
        // 只採用含中文的訊息，避免把英文技術字串顯示給家屬。
        if (m.isNotEmpty && RegExp(r'[一-鿿]').hasMatch(m)) {
          return DailyAskResult(false, m);
        }
        return const DailyAskResult(false, '題目沒有送出，請檢查內容後再試一次');
      }
      debugPrint('⚠️ [DailyQuestionApi] ask 非預期狀態: ${response.statusCode}');
      return const DailyAskResult(false, '送出沒有成功，請稍後再試一次');
    } catch (e) {
      debugPrint('⚠️ [DailyQuestionApi] ask error: $e');
      return const DailyAskResult(false, networkErrorMessage);
    }
  }
}
