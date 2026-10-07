import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

/// ★ 2026-10-07 打卡雙向互動：送出鼓勵的結果。[message] 一律是可直接給家屬看的
/// 繁體中文（不含例外字串、堆疊或 HTTP 狀態碼）。
class CheerResult {
  final bool ok;
  final String message;
  final String? audioUrl;
  const CheerResult(this.ok, this.message, {this.audioUrl});
}

/// ★ 2026-10-07 打卡雙向互動：家屬鼓勵（文字／語音）與近 7 天打卡歷史的 API 層。
class CheckinApi {
  static const String networkErrorMessage = '目前連不上伺服器，請確認網路後再試一次';

  /// 送出鼓勵（multipart）。[text] 最多 100 字、[audioPath] 檔案最多 3MB，
  /// 超過會在本機先擋下，不浪費流量。
  static Future<CheerResult> sendCheer({
    required int familyId,
    required String elderId,
    int? reminderId,
    String? localDate,
    String? text,
    String? audioPath,
  }) async {
    try {
      final cleanText = (text ?? '').trim();
      if (cleanText.isEmpty && audioPath == null) {
        return const CheerResult(false, '請先選一句話、輸入文字或錄一段語音');
      }
      if (cleanText.length > 100) {
        return const CheerResult(false, '文字最多 100 字，請再精簡一下');
      }
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiClient.baseUrl}/checkin_cheer'),
      );
      request.fields['family_id'] = familyId.toString();
      request.fields['elder_id'] = elderId;
      if (reminderId != null) request.fields['reminder_id'] = reminderId.toString();
      if (localDate != null && localDate.isNotEmpty) {
        request.fields['local_date'] = localDate;
      }
      if (cleanText.isNotEmpty) request.fields['text'] = cleanText;
      if (audioPath != null) {
        final file = File(audioPath);
        if (await file.length() > 3 * 1024 * 1024) {
          return const CheerResult(false, '錄音檔太大了，請錄短一點再送');
        }
        request.files.add(await http.MultipartFile.fromPath('audio', audioPath));
      }
      final streamed = await request.send().timeout(const Duration(seconds: 45));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 404) {
        return const CheerResult(false, '這位長輩目前沒有和您綁定，無法送出');
      }
      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        final data = decoded is Map ? decoded['data'] : null;
        return CheerResult(
          true,
          '已送出',
          audioUrl: data is Map ? data['audio_url']?.toString() : null,
        );
      }
      debugPrint('⚠️ sendCheer 非預期狀態: ${response.statusCode}');
      return const CheerResult(false, '送出沒有成功，請稍後再試一次');
    } catch (e) {
      debugPrint('⚠️ sendCheer error: $e');
      return const CheerResult(false, networkErrorMessage);
    }
  }

  /// 今天已送過鼓勵的 reminder id 集合；失敗回傳 null（呼叫端當成「不知道」，不要硬標已鼓勵）。
  static Future<Set<int>?> getSentReminderIds({
    required int familyId,
    required String elderId,
    required String localDate,
  }) async {
    try {
      final res = await ApiClient.get(
          '/checkin_cheer/sent?family_id=$familyId&elder_id=$elderId&local_date=$localDate');
      final ids = res?['data'] is Map ? (res!['data'] as Map)['reminder_ids'] : null;
      if (res != null && res['status'] == 'success' && ids is List) {
        return {
          for (final e in ids)
            if (int.tryParse(e.toString()) != null) int.parse(e.toString()),
        };
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ getSentReminderIds error: $e');
      return null;
    }
  }

  /// 近 N 天打卡歷史（舊→新）：`[{date, done, total}]`；失敗回傳 null。
  static Future<List<Map<String, dynamic>>?> getHistory({
    required String elderId,
    int? familyId,
    int days = 7,
  }) async {
    try {
      final q = familyId == null ? 'days=$days' : 'days=$days&family_id=$familyId';
      final res = await ApiClient.get('/reminder/elder/$elderId/history?$q');
      final list = res?['data'] is Map ? (res!['data'] as Map)['days'] : null;
      if (res != null && res['status'] == 'success' && list is List) {
        return [
          for (final e in list)
            if (e is Map) Map<String, dynamic>.from(e),
        ];
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ getHistory error: $e');
      return null;
    }
  }
}
