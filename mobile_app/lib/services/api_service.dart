import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  // --- 動態伺服器 IP 設置 ---
  static const String _serverIp = String.fromEnvironment('SERVER_IP',
      defaultValue: 'localhost-0.tail5abf5e.ts.net');

  // 依據是否為 ngrok 自動切換 http/https 與 埠號
  static String get baseUrl {
    debugPrint('🔍 Current _serverIp: "$_serverIp"');
    final url = _serverIp.contains('ngrok') || _serverIp.contains('ts.net')
        ? 'https://$_serverIp/api'
        : 'http://$_serverIp:8000/api';
    return url;
  }

  // 本機 AI Server（Ollama 在這台電腦，遠端主後台沒有 Ollama）
  // Android 模擬器用 10.0.2.2 存取 Host，實體裝置用 Tailscale IP
  static const String _localAiServerIp = String.fromEnvironment(
    'LOCAL_AI_IP',
    defaultValue: '100.123.111.120', // 這台電腦的 Tailscale IP
  );
  static String get localAiBaseUrl => 'http://$_localAiServerIp:8000/api';

  // 統一超時時間
  static const Duration _timeout = Duration(seconds: 15);

  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String role,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'email': email,
              'password': password,
              'role': role,
            }),
          )
          .timeout(_timeout);
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(_timeout);
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Map<String, dynamic> _safeDecode(http.Response response) {
    try {
      return jsonDecode(response.body);
    } catch (e) {
      final String snippet = response.body.length > 100
          ? response.body.substring(0, 100)
          : response.body;
      return {
        'status': 'error',
        'message': '伺服器回傳格式錯誤 [HTTP ${response.statusCode}]: $snippet',
        'details': response.body
      };
    }
  }

  static Future<Map<String, dynamic>> requestPairingCode() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/pairing/request_code'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      return _safeDecode(response);
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> checkPairingStatus(String code) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/pairing/check_status/$code'),
          )
          .timeout(const Duration(seconds: 10));
      return _safeDecode(response);
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> confirmPairing({
    required int familyId,
    required String code,
    required String elderName,
    required String gender,
    required int age,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/pairing/confirm'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'family_id': familyId,
              'code': code,
              'elder_name': elderName,
              'gender': gender,
              'age': age,
            }),
          )
          .timeout(_timeout);
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> ensureYuxuanDemoElder() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/pairing/dev/ensure-yuxuan-demo'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(_timeout);
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> ensureGawaDemoElder() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/pairing/dev/ensure-gawa-demo'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(_timeout);
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

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
            Uri.parse('$baseUrl/user/profile/$elderId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              if (userName != null) 'user_name': userName,
              if (age != null) 'age': age,
              if (gender != null) 'gender': gender,
            }),
          )
          .timeout(_timeout);
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> getStatus(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/user/status/$userId'))
          .timeout(_timeout);
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  // AI 相關功能
  // ⚠️ 使用本機 AI Server (localAiBaseUrl)，因遠端主後台無 Ollama 服務
  static Future<Map<String, dynamic>> aiChat(int userId, String message, {String? imageUrl}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$localAiBaseUrl/ai/chat'), // 打本機 AI Server
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': userId,
              'message': message,
              if (imageUrl != null) 'image_url': imageUrl,
            }),
          )
          .timeout(const Duration(seconds: 120));
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': 'AI 回應逾時，請稍後再試'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  /// AI 串流聊天（SSE）- 逐 token 回傳，不需等待完整回應
  static Stream<String> aiChatStream(int userId, String message) async* {
    final client = http.Client();
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$localAiBaseUrl/ai/chat/stream'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({'user_id': userId, 'message': message});

      final streamedResponse = await client.send(request).timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) {
        yield '[ERROR] 伺服器錯誤: ${streamedResponse.statusCode}';
        return;
      }

      // 累積 buffer 處理跨 chunk 的不完整行
      final StringBuffer lineBuf = StringBuffer();

      await for (final chunk in streamedResponse.stream) {
        final decoded = utf8.decode(chunk, allowMalformed: true);

        for (int i = 0; i < decoded.length; i++) {
          final ch = decoded[i];
          if (ch == '\n') {
            final line = lineBuf.toString().trimRight();
            lineBuf.clear();
            if (line.startsWith('data: ')) {
              final payload = line.substring(6).trim();
              if (payload == '[DONE]') return;
              if (payload.startsWith('[ERROR]')) {
                yield payload;
                return;
              }
              try {
                final token = jsonDecode(payload) as String;
                if (token.isNotEmpty) yield token;
              } catch (_) {
                if (payload.isNotEmpty) yield payload;
              }
            }
          } else {
            lineBuf.write(ch);
          }
        }
      }
    } catch (e) {
      yield '[ERROR] $e';
    } finally {
      client.close();
    }
  }

  /// 語音轉文字 (ASR/STT) - 上傳本地錄音檔至 AI Server
  static Future<String?> transcribeAudio(String filePath) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$localAiBaseUrl/voice/transcribe'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      request.fields['language'] = 'zh';

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['transcription']?.toString().trim();
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ [transcribeAudio] 錯誤: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> petGreeting(int userId, String context) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/ai/pet_greeting'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId, 'message': context}),
          )
          .timeout(const Duration(seconds: 120)); // 增加超時時間至 120 秒
      return _safeDecode(response);
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
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
            Uri.parse('$baseUrl/ai/log_activity'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': userId,
              'event_type': type,
              'content': content,
              'extra_data': extraData != null ? jsonEncode(extraData) : null,
            }),
          )
          .timeout(_timeout);
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  // 已棄用：請使用 getPairedElders(int userId) 替代
  @Deprecated('Use getPairedElders instead')
  static Future<List<dynamic>> getElderData(String userId) async {
    return getPairedElders(int.tryParse(userId) ?? 0);
  }

  static Future<List<dynamic>> getPairedElders(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/user/$userId/elders'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        // 後端直接返回 list，不是 {status, data} 格式
        if (decoded is List) {
          return decoded;
        }
        // 兼容舊格式
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

  /// 查詢某長輩是否已存在「通話機」設備。
  /// 用於長輩設備首次登入時自動決定角色：
  /// 已有通話機 → 新設備自動成為監控機（不需資料庫欄位）。
  /// 查詢失敗時保守回傳 false（讓設備預設為通話機）。
  static Future<bool> hasCommDevice(String elderId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/user/elder/$elderId/has-comm-device'))
          .timeout(_timeout);
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
          .get(Uri.parse('$baseUrl/user/$userId/family'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['status'] == 'success') {
          return decoded['data'] as List<dynamic>;
        }
      }
    } catch (e) {
      // Error fetching paired family
    }
    return [];
  }

  static Future<Map<String, dynamic>> getElderProfile(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/user/profile/$userId'))
          .timeout(_timeout);
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
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
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/user/profile/$userId'),
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
            }),
          )
          .timeout(_timeout);
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<List<dynamic>> getPersonaTemplates() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/ai/persona_templates'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['status'] == 'success') {
          return decoded['data'] as List<dynamic>;
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> getElderAgentProfile(int elderId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/user/elder/$elderId'))
          .timeout(_timeout);
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> unbindElder(
    int familyId,
    Object elderId,
  ) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/pairing/$familyId/$elderId'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {'error': 'Failed to unbind elder: ${response.statusCode}'};
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> uploadAvatar(
    int userId,
    String filePath,
  ) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/user/$userId/avatar'),
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
        Uri.parse('$baseUrl/ai/upload_image'),
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

  static Future<Map<String, dynamic>> checkHealth() async {
    try {
      final rootUrl = baseUrl.replaceAll('/api', '');
      final response = await http
          .get(Uri.parse(rootUrl))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return {'status': 'ok'};
      }
      return {'error': '伺服器狀態異常: ${response.statusCode}'};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> testOidc({
    required String provider,
    required String email,
    required String uid,
    required String token,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/test_oidc'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'provider': provider,
              'email': email,
              'uid': uid,
              'token': token,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return _safeDecode(response);
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  /// 取得特定房間的通話紀錄（對應後端 GET /api/call_history）
  static Future<Map<String, dynamic>> getCallHistory(String roomId) async {
    try {
      final response = await http
          .get(Uri.parse(
              '${baseUrl.replaceAll('/api', '')}/api/call_history?room_id=$roomId'))
          .timeout(const Duration(seconds: 10));
      return _safeDecode(response);
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  /// 獲取長輩的今日智能建議
  static Future<Map<String, dynamic>> getDailySuggestions(int elderId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/ai/daily-suggestions/$elderId'))
          .timeout(const Duration(seconds: 60)); // 設為 60 秒以容納模型生成時間
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '獲取建議逾時，請稍後再試'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> getNews({
    String category = 'politics',
    int limit = 3,
    String? dataDate,
  }) async {
    try {
      final queryParameters = <String, String>{
        'category': category,
        'limit': limit.toString(),
      };
      if (dataDate != null && dataDate.isNotEmpty) {
        queryParameters['data_date'] = dataDate;
      }

      final uri =
          Uri.parse('$baseUrl/news').replace(queryParameters: queryParameters);
      final response = await http.get(uri).timeout(_timeout);
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '新聞讀取逾時，請稍後再試'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> synthesizeTts({
    required String text,
    String? emotion,
    String engine = 'edge',
  }) async {
    try {
      final queryParameters = <String, String>{
        'text': text,
        'engine': engine,
      };
      if (emotion != null && emotion.isNotEmpty) {
        queryParameters['emotion'] = emotion;
      }
      final uri = Uri.parse('$baseUrl/voice/tts/test')
          .replace(queryParameters: queryParameters);
      final response =
          await http.post(uri).timeout(const Duration(seconds: 120));
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '語音合成逾時，請稍後再試'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  /// 根據長期記憶 (RAG) 生成一片對話落葉話題
  static Future<Map<String, dynamic>> generatePondLeaf(int userId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/ai/generate_pond_leaf?user_id=$userId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 45));
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '話題生成逾時，請稍後再試'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> generateRecoveryLink({
    required int familyId,
    required String elderId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/pairing/generate_recovery'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'family_id': familyId,
              'elder_id': elderId,
            }),
          )
          .timeout(_timeout);
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> verifyRecoveryCode(String code) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/pairing/verify_recovery'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
            }),
          )
          .timeout(_timeout);
      return _safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  // ==========================================
  // Monitor Setup
  // ==========================================

  static Future<Map<String, dynamic>?> createMonitorSetup(int familyId, String elderId, String deviceName) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/pairing/monitor_setup'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'family_id': familyId,
              'elder_id': elderId,
              'device_name': deviceName,
            }),
          )
          .timeout(_timeout);
      
      final data = _safeDecode(response);
      if (data['status'] == 'success') {
        return data['data']; // should contain 'code'
      }
      return null;
    } catch (e) {
      debugPrint('📞 createMonitorSetup error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> resolveMonitorSetup(String code) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/pairing/monitor_setup/resolve'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
            }),
          )
          .timeout(_timeout);
      
      final data = _safeDecode(response);
      if (data['status'] == 'success') {
        return data['data'];
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ resolveMonitorSetup error: $e');
      return null;
    }
  }


}
