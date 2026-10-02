import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// 📈 家屬端「情緒／健康趨勢」真實資料 API（第四十九輪）
///
/// 對應後端 `routers/family_insight.py`。取代
/// `emotion_timeline_screen.dart`／`health_trends_screen.dart` 原本的
/// `_generateMockData()` 假資料。
///
/// 三支 GET 都回傳完整的伺服器信封（`status`/`data`/`error`），呼叫端要
/// 自己判斷 `status`：
/// - `'success'` 且 `data['available'] == false` → 該資料來源查詢失敗
///   （例如本機 SQLite 開發環境沒有對應的表），要顯示「查詢失敗，可重試」，
///   **不要**當成「沒有資料」。
/// - `'success'` 且 `data['available'] != false` 但清單/序列是空的 →
///   才是真正的「目前沒有資料」。
/// - 非 `'success'`（例如逾時、HTTP 層失敗、403/404）→ 顯示可重試的錯誤。
/// 這三種狀態在畫面上必須長得不一樣，不能都合併成同一種「沒資料」的樣子。
class FamilyInsightApi {
  /// 步數趨勢（真實資料：`elder_daily_step`）
  static Future<Map<String, dynamic>> getStepsTrend(
    String elderId, {
    int? familyId,
    int days = 30,
  }) async {
    try {
      final qs = <String>['days=$days'];
      if (familyId != null) qs.add('family_id=$familyId');
      final response = await http
          .get(Uri.parse(
              '${ApiClient.baseUrl}/family_insight/steps/$elderId?${qs.join('&')}'))
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路後重試'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  /// 近期負面情緒關注事件（真實資料：`activity_log` 的 `event_type='mood'`）
  ///
  /// ⚠️ 這不是「一整天的情緒曲線」，只有 sad/angry 且信心度夠高時才會有紀錄，
  /// 開心／平靜的時刻不會出現在這裡——不要把回傳的 events 硬湊成百分比分佈。
  static Future<Map<String, dynamic>> getEmotionEvents(
    String elderId, {
    int? familyId,
    int days = 30,
    int limit = 50,
  }) async {
    try {
      final qs = <String>['days=$days', 'limit=$limit'];
      if (familyId != null) qs.add('family_id=$familyId');
      final response = await http
          .get(Uri.parse(
              '${ApiClient.baseUrl}/family_insight/emotion_events/$elderId?${qs.join('&')}'))
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路後重試'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  /// 體重／身高趨勢（真實資料：新表 `elder_body_metrics`，家屬手動輸入）
  static Future<Map<String, dynamic>> getBodyMetricsTrend(
    String elderId, {
    int? familyId,
    int days = 365,
  }) async {
    try {
      final qs = <String>['days=$days'];
      if (familyId != null) qs.add('family_id=$familyId');
      final response = await http
          .get(Uri.parse(
              '${ApiClient.baseUrl}/family_insight/body_metrics/$elderId?${qs.join('&')}'))
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路後重試'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  /// 新增／更新一筆體重身高紀錄。
  ///
  /// `familyId` 為必填——這是會真的寫入資料庫的操作，後端要求一定要能驗證
  /// 是哪位家屬、綁定哪位長輩。`metricDate` 也是必填，且**呼叫端必須自己算
  /// 好裝置本地日期字串（YYYY-MM-DD）再傳進來**——後端刻意不接受省略、也
  /// 不會用伺服器時間補預設值：後端統一存 UTC，若讓伺服器自己補「今天」，
  /// 台灣時間 00:00–08:00 送出的紀錄會被錯記成前一天。
  static Future<Map<String, dynamic>> submitBodyMetrics({
    required String elderId,
    required int familyId,
    required String metricDate,
    double? weightKg,
    double? heightCm,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/family_insight/body_metrics/$elderId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'family_id': familyId,
              'metric_date': metricDate,
              if (weightKg != null) 'weight_kg': weightKg,
              if (heightCm != null) 'height_cm': heightCm,
            }),
          )
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路後重試'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }
}
