import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';

/// App 內建 BUG 回報服務。
///
/// 對應後端 `uban-api/routers/admin.py::submit_bug_report`
/// （`POST /api/bug-report`，成功回 201，**未認證**——比照全專案其餘 App API，
/// 見該檔檔頭說明）。刻意不透過 `ApiService.post()` 門面：那支門面只在
/// 200/201 時回傳解碼後的 body，其餘狀態碼一律吞掉、呼叫端拿不到
/// `response.statusCode`，而這支端點的 404／429／422 三種錯誤需要分開顯示
/// 不同文案，因此改用 `http.post()` 直接呼叫並自行讀取狀態碼——寫法比照
/// `family_friend_service.dart`（同一種未認證、需要細分錯誤碼的端點）。
///
/// 錯誤處理慣例：已知狀態碼（404／429／422）一律顯示**寫死的白話文案**，不
/// 直接轉述後端 `detail`——422 尤其不能轉述，因為 Pydantic 驗證錯誤的
/// `detail` 是一份欄位錯誤清單（`List<dynamic>`），不是字串，直接顯示會讓
/// 使用者看到一坨 `[{loc: ..., msg: ...}]`。前端呼叫端在送出前已經做過標題
/// ／內容長度檢查，理論上不會撞到 422。
///
/// 每次呼叫的失敗原因記在 [lastError]，成功時重置為 null，供呼叫端顯示訊息。
class BugReportService {
  static const Duration _timeout = Duration(seconds: 15);

  static Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// 上一次 [submit] 失敗的白話原因；成功時重置為 null。
  static String? lastError;

  /// 送出一份 BUG 回報。成功回傳後端配發的回報編號（`bug_report.id`），
  /// 失敗回傳 null（原因見 [lastError]）。
  ///
  /// [reporterType] 對應後端 `Literal["family", "elder"]`；本輪只有家屬端
  /// 呼叫，固定傳 `'family'`，但服務本身不假設呼叫端一定是家屬，留給日後
  /// 長輩端要接同一支端點時直接復用。
  static Future<int?> submit({
    required String reporterType,
    required String reporterId,
    required String title,
    required String content,
    String? deviceInfo,
    String? appVersion,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/bug-report'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'reporter_type': reporterType,
              'reporter_id': reporterId,
              'title': title,
              'content': content,
              if (deviceInfo != null) 'device_info': deviceInfo,
              if (appVersion != null) 'app_version': appVersion,
            }),
          )
          .timeout(_timeout);
      final data = _decode(response);

      if (response.statusCode == 201 && data['status'] == 'success') {
        lastError = null;
        final id = data['data']?['id'];
        return id is int ? id : int.tryParse('$id');
      }

      if (response.statusCode == 429) {
        // 對應 admin.py::_check_bug_report_rate_limit（60 秒內 5 次）。
        lastError = '回報太頻繁，請稍後再試';
      } else if (response.statusCode == 404) {
        // 對應 admin.py::_validate_reporter——查無這個 reporter_id。正常情況
        // 下不會發生（reporter_id 來自已登入家屬自己的 caregiver_id），會撞到
        // 多半是帳號資料異常，引導重新登入比單純說「失敗」更有幫助。
        lastError = '目前無法辨識您的帳號，請重新登入後再試';
      } else if (response.statusCode == 422) {
        lastError = '內容格式不符，請檢查標題與內容長度後再試';
      } else {
        final dynamic detail = data['detail'] ?? data['message'];
        lastError = (detail is String && detail.isNotEmpty) ? detail : '送出失敗，請稍後再試';
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ [BugReportService] submit error: $e');
      lastError = '無法連線到伺服器，請確認網路狀態後再試';
      return null;
    }
  }
}
