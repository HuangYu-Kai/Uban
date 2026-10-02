import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// 💬 長輩提問轉交家屬（數位助理升級機制）的 API 層。
///
/// 小嘎遇到沒把握的問題時不硬猜，改為把問題連同「長輩當下在哪一頁」一起
/// 轉交子女；子女回覆後即時推回長輩端。
class ElderQuestionApi {
  /// 家屬端：讀取名下所有長輩的提問（預設只取尚未回覆的）。
  static Future<List<Map<String, dynamic>>> listForFamily(
    int familyId, {
    bool pendingOnly = true,
  }) async {
    try {
      final res = await ApiClient.get(
        '/elder_question/family/$familyId?pending_only=$pendingOnly',
      );
      if (res != null && res['status'] == 'success') {
        final list = res['data']?['questions'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('⚠️ listForFamily error: $e');
      return [];
    }
  }

  /// 家屬端：回覆某一則提問。回傳是否成功——呼叫端必須據實顯示結果，
  /// 不要在送出失敗時仍告訴家屬「已回覆」。
  static Future<bool> answer({
    required int questionId,
    required int familyId,
    required String answer,
  }) async {
    try {
      final res = await ApiClient.post(
        '/elder_question/$questionId/answer',
        {'family_id': familyId, 'answer': answer},
      );
      return res != null && res['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ answerQuestion error: $e');
      return false;
    }
  }

  /// 長輩端：讀取已被子女回覆的提問，供小嘎主動轉達。
  static Future<List<Map<String, dynamic>>> listAnsweredForElder(
    String elderId, {
    int limit = 10,
  }) async {
    try {
      final res =
          await ApiClient.get('/elder_question/elder/$elderId/answered?limit=$limit');
      if (res != null && res['status'] == 'success') {
        final list = res['data']?['questions'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('⚠️ listAnsweredForElder error: $e');
      return [];
    }
  }
}
