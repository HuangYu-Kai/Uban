import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// 長輩資料、個人檔案、家庭留言、生活足跡與活動日誌 API
class ElderDataApi {
  static Future<Map<String, dynamic>> updateElderInfo({
    required int familyId,
    required int elderId,
    String? userName,
    int? age,
    String? gender,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/user/profile/$elderId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              if (userName != null) 'user_name': userName,
              if (age != null) 'age': age,
              if (gender != null) 'gender': gender,
            }),
          )
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      debugPrint('⚠️ [ElderDataApi] 網路錯誤: $e');
      return {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
  }

  static Future<Map<String, dynamic>> getStatus(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiClient.baseUrl}/user/status/$userId'))
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      debugPrint('⚠️ [ElderDataApi] 網路錯誤: $e');
      return {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
  }

  static Future<Map<String, dynamic>> logActivity(
    int userId,
    String type,
    String content, {
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/ai/log_activity'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': userId,
              'event_type': type,
              'content': content,
              'extra_data': extraData != null ? jsonEncode(extraData) : null,
            }),
          )
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      debugPrint('⚠️ [ElderDataApi] 網路錯誤: $e');
      return {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
  }

  static Future<Map<String, dynamic>> sendFamilyMessage({
    required int familyId,
    required int elderId,
    required String content,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/family_message'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'family_id': familyId,
              'elder_id': elderId,
              'content': content,
            }),
          )
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      debugPrint('⚠️ [ElderDataApi] 網路錯誤: $e');
      return {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
  }

  @Deprecated('Use getPairedElders instead')
  static Future<List<dynamic>> getElderData(String userId) async {
    return getPairedElders(int.tryParse(userId) ?? 0);
  }

  /// ★ 2026-10-06 登入流程審查：區分「讀取失敗」與「真的沒有長輩」。
  /// 回傳 null＝請求失敗（逾時／斷網／伺服器錯誤）；回傳 []＝確定沒有配對長輩。
  /// 舊的 [getPairedElders] 簽章不變（失敗仍回 []），給不在乎差異的呼叫端用。
  static Future<List<dynamic>?> getPairedEldersOrNull(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiClient.baseUrl}/user/$userId/elders'))
          .timeout(ApiClient.timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          return decoded;
        }
        if (decoded is Map &&
            decoded['status'] == 'success' &&
            decoded['data'] is List) {
          return decoded['data'] as List<dynamic>;
        }
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ getPairedEldersOrNull error: $e');
      return null;
    }
  }

  static Future<List<dynamic>> getPairedElders(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiClient.baseUrl}/user/$userId/elders'))
          .timeout(ApiClient.timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          return decoded;
        }
        if (decoded is Map && decoded['status'] == 'success') {
          return decoded['data'] as List<dynamic>;
        }
      }
      return [];
    } catch (e) {
      debugPrint('⚠️ getPairedElders error: $e');
      return [];
    }
  }

  /// 查詢某長輩是否已存在「通話機」設備
  static Future<bool> hasCommDevice(String elderId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiClient.baseUrl}/user/elder/$elderId/has-comm-device'))
          .timeout(ApiClient.timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['has_comm_device'] == true) {
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('⚠️ hasCommDevice error: $e');
      return false;
    }
  }

  static Future<List<dynamic>> getPairedFamily(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiClient.baseUrl}/user/$userId/family'))
          .timeout(ApiClient.timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['status'] == 'success') {
          return decoded['data'] as List<dynamic>;
        }
      }
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>> getElderProfile(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiClient.baseUrl}/user/profile/$userId'))
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      debugPrint('⚠️ [ElderDataApi] 網路錯誤: $e');
      return {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
  }

  static Future<Map<String, dynamic>> updateElderProfile({
    required int userId,
    String? phone,
    String? location,
    String? appellation,
    int? aiEmotionTone,
    int? aiTextVerbosity,
    String? chronicDiseases,
    String? medicationNotes,
    String? interests,
    String? aiPersona,
    String? lifeStory,
    int? heartbeatFrequency,
    // ★ 2026-09-11 第四十五輪第三項：年齡／結構化居住地（縣市／鄉鎮市區）。
    //   與既有的 location 自由文字並存、僅供統計使用、選填。後端依 user_id
    //   是否有 elder_profile 列自動分流寫入 elder_profile 或 user_account_data。
    int? age,
    String? residenceCity,
    String? residenceDistrict,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/user/profile/$userId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              if (phone != null) 'phone': phone,
              if (location != null) 'location': location,
              if (appellation != null) 'appellation': appellation,
              if (aiEmotionTone != null) 'ai_emotion_tone': aiEmotionTone,
              if (aiTextVerbosity != null) 'ai_text_verbosity': aiTextVerbosity,
              if (chronicDiseases != null) 'chronic_diseases': chronicDiseases,
              if (medicationNotes != null) 'medication_notes': medicationNotes,
              if (interests != null) 'interests': interests,
              if (aiPersona != null) 'ai_persona': aiPersona,
              if (lifeStory != null) 'life_story': lifeStory,
              if (heartbeatFrequency != null)
                'heartbeat_frequency': heartbeatFrequency,
              if (age != null) 'age': age,
              if (residenceCity != null) 'residence_city': residenceCity,
              if (residenceDistrict != null)
                'residence_district': residenceDistrict,
            }),
          )
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      debugPrint('⚠️ [ElderDataApi] 網路錯誤: $e');
      return {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
  }

  /// ★ 2026-10-07 交接 B1／E：把 FastAPI／自訂回應轉成人看得懂的失敗原因。
  /// 優先序：`detail`（字串，或 422 的 `[{msg: ...}]` 清單）→ `message` → `error` → [fallback]。
  static String failureMessageOf(Map<String, dynamic>? r, {String fallback = '儲存失敗，請稍後再試'}) {
    if (r == null) return fallback;
    final d = r['detail'];
    if (d is String && d.trim().isNotEmpty) return d.trim();
    if (d is List && d.isNotEmpty) {
      final msgs = d
          .map((e) => e is Map ? (e['msg'] ?? '').toString() : e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (msgs.isNotEmpty) return msgs.join('；');
    }
    for (final k in const ['message', 'error']) {
      final v = r[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return fallback;
  }

  /// ★ 2026-10-07 交接 B1：部分更新長輩／個人檔案（PUT `/user/profile/{id}`）。
  /// 只送呼叫端傳進來的欄位；HTTP 非 2xx 或 `status != success` 一律回
  /// `{status: 'error', message: <真實原因>}`，不會假成功。
  static Future<Map<String, dynamic>> putProfileFields(
    int userId,
    Map<String, dynamic> fields,
  ) async {
    try {
      final response = await http
          .put(
            Uri.parse('${ApiClient.baseUrl}/user/profile/$userId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(fields),
          )
          .timeout(ApiClient.timeout);
      return _normalizeResult(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      debugPrint('⚠️ [ElderDataApi] putProfileFields 網路錯誤: $e');
      return {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
  }

  static Map<String, dynamic> _normalizeResult(http.Response response) {
    final decoded = ApiClient.safeDecode(response);
    final ok = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        decoded['status'] == 'success';
    if (ok) return decoded;
    return {
      ...decoded,
      'status': 'error',
      'message': failureMessageOf(decoded),
    };
  }

  /// 話題偏好（`elder_talk_topics`）。後端 GET `/ai/topics` 不分長輩全部回傳，
  /// 這裡依 `elder_id` 在前端過濾，回傳 `{status, data: List<Map>}`。
  static Future<Map<String, dynamic>> getTalkTopics(String elderId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiClient.baseUrl}/ai/topics'))
          .timeout(ApiClient.timeout);
      final r = _normalizeResult(response);
      if (r['status'] != 'success') return r;
      final all = r['data'] is List ? r['data'] as List : const [];
      final mine = all
          .whereType<Map>()
          .where((t) => '${t['elder_id']}' == elderId)
          .map((t) => Map<String, dynamic>.from(t))
          .toList();
      return {'status': 'success', 'data': mine};
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      debugPrint('⚠️ [ElderDataApi] getTalkTopics 網路錯誤: $e');
      return {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
  }

  /// [topicType]：`priority`（想多聊）／`avoid`（避免）／`forbidden`（禁忌）。
  static Future<Map<String, dynamic>> createTalkTopic(
    String elderId,
    String keyword,
    String topicType,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/ai/topics'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'elder_id': elderId,
              'keyword': keyword,
              'topic_type': topicType,
            }),
          )
          .timeout(ApiClient.timeout);
      return _normalizeResult(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      debugPrint('⚠️ [ElderDataApi] createTalkTopic 網路錯誤: $e');
      return {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
  }

  static Future<Map<String, dynamic>> deleteTalkTopic(int topicId) async {
    try {
      final response = await http
          .delete(Uri.parse('${ApiClient.baseUrl}/ai/topics/$topicId'))
          .timeout(ApiClient.timeout);
      return _normalizeResult(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      debugPrint('⚠️ [ElderDataApi] deleteTalkTopic 網路錯誤: $e');
      return {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
  }

  static Future<Map<String, dynamic>> uploadAvatar(
    int userId,
    String filePath,
  ) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiClient.baseUrl}/user/$userId/avatar'),
      );
      request.files.add(await http.MultipartFile.fromPath('avatar', filePath));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {'error': 'Failed to upload avatar: ${response.statusCode}'};
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> uploadImage(String filePath) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiClient.baseUrl}/ai/upload_image'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {'error': 'Failed to upload image: ${response.statusCode}'};
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// ★ 2026-10-07 交接 E：帶 [familyId] 讓後端驗證家屬與長輩的關係（後端參數選填）。
  static Future<List<dynamic>> getElderActivityLogs(String elderId, {int limit = 10, int? familyId}) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiClient.baseUrl}/activity/elder/$elderId?limit=$limit${familyId != null ? '&family_id=$familyId' : ''}'))
          .timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(response);
      if (data['status'] == 'success' && data['data'] is List) {
        return List<dynamic>.from(data['data']);
      }
      return [];
    } catch (e) {
      debugPrint('⚠️ getElderActivityLogs error: $e');
      return [];
    }
  }
}
