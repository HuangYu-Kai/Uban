import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// 視訊/語音通話控制與通話紀錄 API
class CallApi {
  /// ★ 2026-07-18：無狀態拒接／取消 HTTP 備援。
  ///   背景/被殺死狀態下沒有 Socket 連線，或 Socket 剛好斷線時，改走此 REST
  ///   端點通知後端廣播 call-busy/cancel-call（含 FCM），確保雙端同步終止。
  static Future<bool> declineCall({
    required String roomId,
    required String senderId,
    String? callId,
  }) async {
    try {
      await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/call/decline'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'roomId': roomId,
              'senderId': senderId,
              'callId': callId,
            }),
          )
          .timeout(const Duration(seconds: 8));
      debugPrint('✅ [CallApi] declineCall sent (room=$roomId, call=$callId)');
      return true;
    } catch (e) {
      debugPrint('⚠️ [CallApi] declineCall failed: $e');
      return false;
    }
  }

  /// ★ 2026-11-07：查詢伺服器上這通來電是否已被發起端取消／掛斷（`GET /call/status`）。
  ///   供背景 isolate 在「保活等待使用者決定」期間主動偵測取消——取消的 FCM 在 Android 是序列處理的，
  ///   會排在保活後面，等不到。回傳 true＝已取消／結束；false＝仍有效；null＝查不到（舊後端 404、
  ///   網路錯誤、逾時）——呼叫端一律當「未取消」，寧可多響也不能因查詢失敗而吞掉來電。
  static Future<bool?> isCallCancelled(String callId) async {
    if (callId.isEmpty) return null;
    try {
      final response = await http
          .get(Uri.parse('${ApiClient.baseUrl}/call/status?callId=${Uri.encodeQueryComponent(callId)}'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['cancelled'] is bool) {
        return decoded['cancelled'] as bool;
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ [CallApi] isCallCancelled 失敗（視為未取消）: $e');
      return null;
    }
  }

  /// 取得特定房間的通話紀錄（對應後端 GET /api/call_history）
  static Future<Map<String, dynamic>> getCallHistory(String roomId) async {
    try {
      final response = await http
          .get(Uri.parse(
              '${ApiClient.baseUrl.replaceAll('/api', '')}/api/call_history?room_id=$roomId'))
          .timeout(const Duration(seconds: 10));
      return ApiClient.safeDecode(response);
    } catch (e) {
      debugPrint('⚠️ [call_api] 網路錯誤: $e');
      return {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
  }
}
