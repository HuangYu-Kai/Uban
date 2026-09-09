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

  /// 取得特定房間的通話紀錄（對應後端 GET /api/call_history）
  static Future<Map<String, dynamic>> getCallHistory(String roomId) async {
    try {
      final response = await http
          .get(Uri.parse(
              '${ApiClient.baseUrl.replaceAll('/api', '')}/api/call_history?room_id=$roomId'))
          .timeout(const Duration(seconds: 10));
      return ApiClient.safeDecode(response);
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }
}
