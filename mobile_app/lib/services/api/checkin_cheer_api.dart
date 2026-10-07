import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// 🎉 打卡加油（家屬在長輩完成打卡後傳的文字／語音鼓勵）的長輩端 API 層。
class CheckinCheerApi {
  /// 長輩端：讀取尚未讀取的加油。失敗一律回空清單（下次回前景再試，不打擾長輩）。
  static Future<List<Map<String, dynamic>>> listUnreadForElder(
      Object elderId) async {
    try {
      final res = await ApiClient.get('/checkin_cheer/elder/$elderId/unread');
      if (res != null && res['status'] == 'success') {
        final list = res['data']?['items'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('⚠️ CheckinCheerApi.listUnreadForElder error: $e');
      return [];
    }
  }

  /// 長輩端：標記某則加油已讀。回傳是否成功。
  static Future<bool> markRead(int cheerId, Object elderId) async {
    try {
      final res = await ApiClient.post(
        '/checkin_cheer/$cheerId/read',
        {'elder_id': elderId},
      );
      return res != null && res['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ CheckinCheerApi.markRead error: $e');
      return false;
    }
  }
}
