import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  // --- 動態伺服器 IP 設置 ---
  static const String _serverIp = String.fromEnvironment('SERVER_IP',
      defaultValue: 'localhost-0.tail5abf5e.ts.net');

  // 依據環境動態切換 API 基礎網址（預設 Android 模擬器連線本機: 10.0.2.2:8000）
  static String get baseUrl {
    if (_serverIp.startsWith('http://') || _serverIp.startsWith('https://')) {
      return _serverIp.endsWith('/api') ? _serverIp : '$_serverIp/api';
    }
    if (_serverIp.contains('ts.net') || _serverIp.contains('ngrok')) {
      return 'https://$_serverIp/api';
    }
    return 'http://$_serverIp:8000/api';
  }

  // 本機 AI Server（Ollama 在這台電腦，遠端主後台沒有 Ollama）
  // Android 模擬器/實體裝置用 LAN IP 存取 Host
  static const String _localAiServerIp = String.fromEnvironment(
    'LOCAL_AI_IP',
    defaultValue: 'boyo-desktop.tail531c8a.ts.net', // AI Hub 專屬 Tailscale 網域
  );
  static String get localAiBaseUrl {
    if (_localAiServerIp.startsWith('http://') || _localAiServerIp.startsWith('https://')) {
      return _localAiServerIp.endsWith('/api') ? _localAiServerIp : '$_localAiServerIp/api';
    }
    if (_localAiServerIp.contains('ts.net')) {
      return 'https://$_localAiServerIp/api';
    }
    return 'http://$_localAiServerIp:8000/api';
  }

  // 統一超時時間
  static const Duration _timeout = Duration(seconds: 15);

  static String _fullUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    String cleanPath = path;
    if (baseUrl.endsWith('/api') && cleanPath.startsWith('/api/')) {
      cleanPath = cleanPath.substring(4);
    }
    if (!cleanPath.startsWith('/')) {
      cleanPath = '/$cleanPath';
    }
    return '$baseUrl$cleanPath';
  }

  static Future<Map<String, dynamic>?> get(String path) async {
    try {
      final url = _fullUrl(path);
      debugPrint('📡 [ApiService.get] -> $url');
      final response = await http
          .get(Uri.parse(url))
          .timeout(_timeout);
      debugPrint('📡 [ApiService.get] <- status: ${response.statusCode}, body: ${response.body}');
      if (response.statusCode == 200) {
        final decoded = _safeDecode(response);
        if (decoded != null && decoded['status'] == 'success') {
          return decoded;
        }
      }
      // 如果遠端回傳 404 或非 success，降級嘗試本機伺服器
      if (url.contains('ts.net') || response.statusCode == 404) {
        final cleanPath = path.startsWith('/api') ? path.substring(4) : path;
        final fallbackUrl = 'http://10.0.2.2:8000/api$cleanPath';
        debugPrint('🔄 [ApiService.get Fallback 404/Non-Success] -> $fallbackUrl');
        final fbRes = await http.get(Uri.parse(fallbackUrl)).timeout(const Duration(seconds: 4));
        if (fbRes.statusCode == 200) {
          return _safeDecode(fbRes);
        }
      }
      return _safeDecode(response);
    } catch (e) {
      debugPrint('⚠️ ApiService.get error: $e');
      try {
        final cleanPath = path.startsWith('/api') ? path.substring(4) : path;
        final fallbackUrl = 'http://10.0.2.2:8000/api$cleanPath';
        debugPrint('🔄 [ApiService.get Fallback Exception] -> $fallbackUrl');
        final fbRes = await http.get(Uri.parse(fallbackUrl)).timeout(const Duration(seconds: 4));
        if (fbRes.statusCode == 200) {
          return _safeDecode(fbRes);
        }
      } catch (_) {}
      return null;
    }
  }

  static Future<Map<String, dynamic>?> post(String path, Map<String, dynamic> body) async {
    try {
      final url = _fullUrl(path);
      debugPrint('📡 [ApiService.post] -> $url body: $body');
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      debugPrint('📡 [ApiService.post] <- status: ${response.statusCode}, body: ${response.body}');
      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = _safeDecode(response);
        if (decoded != null && decoded['status'] == 'success') {
          return decoded;
        }
      }
      if (url.contains('ts.net') || response.statusCode == 404) {
        final cleanPath = path.startsWith('/api') ? path.substring(4) : path;
        final fallbackUrl = 'http://10.0.2.2:8000/api$cleanPath';
        debugPrint('🔄 [ApiService.post Fallback 404/Non-Success] -> $fallbackUrl');
        final fbRes = await http.post(
          Uri.parse(fallbackUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 4));
        if (fbRes.statusCode == 200 || fbRes.statusCode == 201) {
          return _safeDecode(fbRes);
        }
      }
      return _safeDecode(response);
    } catch (e) {
      debugPrint('⚠️ ApiService.post error: $e');
      try {
        final cleanPath = path.startsWith('/api') ? path.substring(4) : path;
        final fallbackUrl = 'http://10.0.2.2:8000/api$cleanPath';
        final fbRes = await http.post(
          Uri.parse(fallbackUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 4));
        if (fbRes.statusCode == 200 || fbRes.statusCode == 201) {
          return _safeDecode(fbRes);
        }
      } catch (_) {}
      return null;
    }
  }

  static Future<Map<String, dynamic>?> put(String path, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse(_fullUrl(path)),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      return _safeDecode(response);
    } catch (e) {
      debugPrint('⚠️ ApiService.put error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> delete(String path) async {
    try {
      final response = await http
          .delete(Uri.parse(_fullUrl(path)))
          .timeout(_timeout);
      return _safeDecode(response);
    } catch (e) {
      debugPrint('⚠️ ApiService.delete error: $e');
      return null;
    }
  }
  /// ★ 2026-08-05 第十七輪（安全）：監視機推流／跌倒測試端點的共用密鑰。
  ///
  /// 後端 `POST /api/cctv/frame` 的下游就是「偽造跌倒 → 對家屬強制點亮螢幕」，
  /// 原本無任何驗證。後端在 `.env` 設定 `CCTV_INGEST_TOKEN` 後即要求此標頭；
  /// **未設定時後端完全維持舊行為**，故這裡留空也不會打斷現有部署。
  ///
  /// 注入方式比照 `SERVER_IP` / `TURN_PASS`，絕不寫死在程式碼內：
  ///   flutter run --dart-define=CCTV_INGEST_TOKEN=<與後端 .env 相同的字串>
  static const String _cctvIngestToken =
      String.fromEnvironment('CCTV_INGEST_TOKEN', defaultValue: '');

  /// 空字串時回傳空 Map，讓呼叫端可無條件展開（`...`）而不需分支。
  static Map<String, String> get _deviceTokenHeader =>
      _cctvIngestToken.isEmpty ? {} : {'X-Uban-Device-Token': _cctvIngestToken};

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

  /// ★ 2026-07-18：無狀態拒接／取消 HTTP 備援。
  ///   背景/被殺死狀態下沒有 Socket 連線，或 Socket 剛好斷線時，改走此 REST
  ///   端點通知後端廣播 call-busy/cancel-call（含 FCM），確保雙端同步終止。
  static Future<void> declineCall({
    required String roomId,
    required String senderId,
    String? callId,
  }) async {
    try {
      await http
          .post(
            Uri.parse('$baseUrl/call/decline'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'roomId': roomId,
              'senderId': senderId,
              'callId': callId,
            }),
          )
          .timeout(const Duration(seconds: 8));
      debugPrint('✅ [ApiService] declineCall sent (room=$roomId, call=$callId)');
    } catch (e) {
      debugPrint('⚠️ [ApiService] declineCall failed: $e');
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
  // ⚠️ 使用本機 AI Server (localAiBaseUrl) 與自動降級連線備援
  static Future<Map<String, dynamic>> aiChat(int userId, String message, {String? imageUrl}) async {
    final List<String> candidateUrls = [
      'https://boyo-desktop.tail531c8a.ts.net/api/ai/chat',
      '$localAiBaseUrl/ai/chat',
      'http://192.168.31.209:8000/api/ai/chat',
      'http://10.0.2.2:8000/api/ai/chat',
      '${baseUrl.replaceFirst('/api', '')}/api/ai/chat',
    ];
    final uniqueUrls = candidateUrls.toSet().toList();

    for (final url in uniqueUrls) {
      try {
        final response = await http
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'user_id': userId,
                'message': message,
                if (imageUrl != null) 'image_url': imageUrl,
              }),
            )
            .timeout(const Duration(seconds: 30));
        if (response.statusCode == 200) {
          return _safeDecode(response);
        }
      } catch (_) {}
    }
    return {'status': 'error', 'message': '網路連線失敗，請檢查 AI Server 是否開啟'};
  }

  /// AI 串流聊天（SSE）- 逐 token 回傳，支援多候選 IP 自動降級連線
  static Stream<String> aiChatStream(int userId, String message) async* {
    final List<String> candidateUrls = [
      'https://boyo-desktop.tail531c8a.ts.net/api/ai/chat/stream',
      '$localAiBaseUrl/ai/chat/stream',
      'http://192.168.31.209:8000/api/ai/chat/stream',
      'http://10.0.2.2:8000/api/ai/chat/stream',
      '${baseUrl.replaceFirst('/api', '')}/api/ai/chat/stream',
    ];
    final uniqueUrls = candidateUrls.toSet().toList();

    for (int idx = 0; idx < uniqueUrls.length; idx++) {
      final targetUrl = uniqueUrls[idx];
      final client = http.Client();
      try {
        debugPrint('📡 [aiChatStream Attempt ${idx + 1}] -> $targetUrl');
        final request = http.Request('POST', Uri.parse(targetUrl));
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode({'user_id': userId, 'message': message});

        final streamedResponse = await client.send(request).timeout(const Duration(seconds: 15));

        if (streamedResponse.statusCode != 200) {
          client.close();
          if (idx < uniqueUrls.length - 1) continue;
          yield '[ERROR] 伺服器錯誤: ${streamedResponse.statusCode}';
          return;
        }

        final StringBuffer lineBuf = StringBuffer();
        bool receivedData = false;

        await for (final chunk in streamedResponse.stream) {
          receivedData = true;
          final decoded = utf8.decode(chunk, allowMalformed: true);
          for (int i = 0; i < decoded.length; i++) {
            final ch = decoded[i];
            if (ch == '\n') {
              final line = lineBuf.toString().trimRight();
              lineBuf.clear();
              if (line.startsWith('data: ')) {
                final payload = line.substring(6).trim();
                if (payload == '[DONE]') {
                  client.close();
                  return;
                }
                if (payload.startsWith('[ERROR]')) {
                  client.close();
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
        client.close();
        if (receivedData) return;
      } catch (e) {
        debugPrint('⚠️ [aiChatStream Fail] $targetUrl error: $e');
        client.close();
        if (idx < uniqueUrls.length - 1) continue;
        yield '[ERROR] $e';
      }
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

  /// ★ 2026-08-10 第二十輪：resolveMonitorSetup 失敗時的可讀錯誤訊息，
  ///   供 monitor_pairing_screen 顯示具體原因（綁定碼不存在／已過期／連線失敗）。
  ///   成功時會重置為 null；每次呼叫都會覆寫上一次的值。
  static String? lastResolveError;

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
        lastResolveError = null;
        return data['data'];
      }

      // ★ 2026-08-10 第二十輪：取出後端 HTTPException 的 detail（例如「綁定碼不存在」
      //   或「綁定碼已過期」），讓 UI 能顯示具體原因而非統一的模糊訊息。
      final dynamic msg = data['detail'] ?? data['message'];
      lastResolveError =
          msg != null ? msg.toString() : '伺服器錯誤（HTTP ${response.statusCode}）';
      return null;
    } catch (e) {
      debugPrint('⚠️ resolveMonitorSetup error: $e');
      lastResolveError = '無法連線到後端，請確認網路狀態';
      return null;
    }
  }

  /// ★ 2026-08-10 第二十輪（需求 1、5）：通知後端釋放目前 session，
  ///   後端會據此註銷 FCM token，避免登出後仍收到上一個帳號的來電推播。
  /// 對應後端 POST /api/pairing/session/release。
  /// 任何網路例外都吞掉並回傳 false —— 絕不能讓後端呼叫失敗擋住本機登出流程。
  static Future<bool> releaseSession({
    required String fcmToken,
    int? userId,
    String? roomId,
  }) async {
    try {
      final Map<String, dynamic> body = {'fcm_token': fcmToken};
      if (userId != null) body['user_id'] = userId;
      if (roomId != null) body['room_id'] = roomId;

      final response = await http
          .post(
            Uri.parse('$baseUrl/pairing/session/release'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('⚠️ [ApiService] releaseSession error: $e');
      return false;
    }
  }

  /// ★ Task 6：取得使用者目前訂閱層級與設備上限
  /// GET /api/subscription/tier/{user_id}
  static Future<Map<String, dynamic>> getSubscriptionTier(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/subscription/tier/$userId'))
          .timeout(_timeout);
      return _safeDecode(response);
    } catch (e) {
      debugPrint('⚠️ getSubscriptionTier error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  /// ★ Task 6：取得使用者訂閱歷史明細列表
  /// GET /api/subscription/records/{user_id}
  static Future<Map<String, dynamic>> getSubscriptionRecords(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/subscription/records/$userId'))
          .timeout(_timeout);
      return _safeDecode(response);
    } catch (e) {
      debugPrint('⚠️ getSubscriptionRecords error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  /// ★ 2026-08-04 第 7 項：CCTV 監視機推送單一影格給後端做 YOLO 跌倒偵測。
  /// POST /api/cctv/frame（multipart/form-data）；任何失敗都吞掉只回 false，
  /// 避免影格推送迴圈因單次網路錯誤而中斷。
  ///
  /// 檔名為 .png 是因為 flutter_webrtc 1.3.1 的 `captureFrame()` 產出的就是 PNG
  /// （它把畫面寫成暫存 png 再讀回）。後端用 cv2.imdecode 靠魔術位元組判別格式，
  /// 副檔名只是給人看的，但不要改成 .jpg 以免誤導後續維護者。
  static Future<bool> pushCctvFrame({
    required String elderId,
    required String deviceName,
    required Uint8List frameBytes,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/cctv/frame'),
      );
      request.headers.addAll(_deviceTokenHeader);
      request.fields['elder_id'] = elderId;
      request.fields['device_name'] = deviceName;
      request.files.add(
        http.MultipartFile.fromBytes('frame', frameBytes, filename: 'frame.png'),
      );
      final streamed = await request.send().timeout(_timeout);
      // ★ 2026-08-17 第二十五輪（需求 2）：package:http 的 BaseRequest.send() 內部會建立
      //   一個 http.Client，只有在 response.stream 被消費完畢時才會呼叫 client.close()
      //   （send() 回傳前掛的是 onDone(response.stream, client.close)）。這裡原本從未讀取
      //   streamed.stream，client 與其底層 socket 就永遠不會被釋放——CCTV 推幀迴圈每
      //   2 秒呼叫一次本方法（見 elder_screen.dart:183），約每分鐘洩漏 30 條連線，直到
      //   耗盡連線上限後**所有**後續 HTTP 呼叫都會拋錯，也就是「退出監控後登入變成
      //   『網路連線失敗』，只有砍掉整個 App 才會恢復」的根因。本檔其餘每一處
      //   request.send() 都有接 http.Response.fromStream(...)（見 :514-515、:756-757、
      //   :777-778），這裡補齊，不要為了「省一行」把它精簡掉。
      final response = await http.Response.fromStream(streamed);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('⚠️ pushCctvFrame error: $e');
      return false;
    }
  }

  /// ★ 2026-08-05 第十七輪：POST /api/cctv/test-fall，觸發與 YOLO 相同的跌倒警報派送路徑。
  /// 暫時性測試入口，YOLO 可實測後即可移除。後端該端點是 `Form(...)`，故用
  /// application/x-www-form-urlencoded（body 傳 Map，http 套件會自動編碼並設定
  /// Content-Type），欄位名沿用後端的 snake_case（elder_id / device_name）。
  /// ★ 2026-08-05 第十七輪（安全）：後端此端點**預設關閉**，且回傳的
  /// `detail` 會明講關閉／無密鑰／查無監視機三種原因。若這裡照舊只回 bool，
  /// 使用者按下測試鍵只會看到「送出失敗」而無從得知要去 .env 開開關，
  /// 因此改回傳 **錯誤訊息字串**：`null` 代表成功，非 null 就是可直接顯示的原因。
  static Future<String?> triggerTestFall({
    required String elderId,
    required String deviceName,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/cctv/test-fall'),
            headers: _deviceTokenHeader,
            body: {'elder_id': elderId, 'device_name': deviceName},
          )
          .timeout(_timeout);
      if (response.statusCode == 200) return null;
      // FastAPI 的 HTTPException 一律以 {"detail": "..."} 回傳
      String detail = '送出失敗（HTTP ${response.statusCode}）';
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map && decoded['detail'] != null) {
          detail = decoded['detail'].toString();
        }
      } catch (_) {
        // body 不是 JSON 就沿用上面的預設訊息
      }
      debugPrint('⚠️ triggerTestFall 被拒: ${response.statusCode} $detail');
      return detail;
    } catch (e) {
      debugPrint('⚠️ triggerTestFall error: $e');
      return '無法連線到後端，請確認網路狀態';
    }
  }

  /// ★ 2026-08-04 第 7 項：移除一台監視機設備（含其 FCM token）。
  /// DELETE /api/pairing/monitor_device?elder_id=...&device_name=...&user_id=...
  ///
  /// ★ 2026-08-10 第十九輪（D2）：後端補上授權，`user_id` 必須帶（呼叫端須為該
  ///   長輩本人或已配對家屬），不符一律回 404。舊版沒有這個參數時後端零驗證，
  ///   任何人知道 elder_id + device_name 就能刪別人家的監視機。
  static Future<bool> deleteMonitorDevice({
    required String elderId,
    required String deviceName,
    int? userId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/pairing/monitor_device').replace(
        queryParameters: {
          'elder_id': elderId,
          'device_name': deviceName,
          if (userId != null) 'user_id': userId.toString(),
        },
      );
      final response = await http.delete(uri).timeout(_timeout);
      final data = _safeDecode(response);
      return data['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ deleteMonitorDevice error: $e');
      return false;
    }
  }

  /// ★ 2026-08-10 第十九輪（A4）：以 HTTP 交叉驗證長輩名下的監視設備清單。
  /// GET /api/pairing/monitor_devices?elder_id=...&user_id=...
  ///
  /// 回傳形狀與 Socket `elder-devices-update` **完全相同**（後端直接呼叫同一支
  /// `_get_elder_devices_list`），每筆為 `{id, deviceName, deviceMode, isOnline,
  /// appState, deviceId}`。比 Socket 事件多的好處：裝置只要完成過配對碼兌換
  /// （後端 A2 已寫入 `monitor_device_binding`），即使從未成功 join 過，
  /// 這裡也會回一筆 `isOnline: false` 的紀錄。
  ///
  /// 任何錯誤（含 404 無權）一律回**空陣列**，而呼叫端
  /// （`family_main_screen.dart::_refreshMonitorDevicesViaHttp`）對空陣列直接
  /// return——絕不因單次 HTTP 失敗就把既有的 Socket 清單清空。
  ///
  /// ⚠️ 非空時呼叫端是「後到者為準」整批覆蓋，**不是聯集**：需求 3 的
  /// 「刪除監視機」與「監視機主動退出即移除」都需要清單能夠**變短**，
  /// 聯集會讓已刪除的裝置永遠留在畫面上。
  static Future<List<dynamic>> fetchMonitorDevices({
    required String elderId,
    required int userId,
  }) async =>
      await fetchMonitorDevicesOrNull(elderId: elderId, userId: userId) ??
      const [];

  /// ★ 2026-08-11 第二十二輪（需求 6）：與 [fetchMonitorDevices] 相同的查詢，
  /// 但**區分「查詢失敗」與「查到了、清單是空的」**——失敗回 `null`、成功回清單
  /// （可能為空陣列）。
  ///
  /// 為什麼需要這個變體：`elder_screen.dart` 的監控機在斷線時要判斷
  /// 「是網路斷了」還是「這台已被家屬端刪除」。若沿用會把錯誤吞成 `[]` 的舊方法，
  /// 空陣列同時代表「請求失敗」與「名下已無任何監控設備（正是被刪除的樣子）」，
  /// 兩種相反結論無從區分，一定會誤報其中一種。
  ///
  /// [fetchMonitorDevices] 現在直接轉呼叫本方法並把 `null` 攤平成 `[]`，
  /// 既有呼叫端（`family_main_screen.dart::_refreshMonitorDevicesViaHttp`）
  /// 的行為完全不變。
  static Future<List<dynamic>?> fetchMonitorDevicesOrNull({
    required String elderId,
    required int userId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/pairing/monitor_devices').replace(
        queryParameters: {
          'elder_id': elderId,
          'user_id': userId.toString(),
        },
      );
      final response = await http.get(uri).timeout(_timeout);
      final data = _safeDecode(response);
      if (data['status'] != 'success') return null;
      final devices = (data['data'] ?? const {})['devices'];
      return devices is List ? devices : const [];
    } catch (e) {
      debugPrint('⚠️ fetchMonitorDevices error: $e');
      return null;
    }
  }

  /// ★ 2026-08-10 第十九輪（D3）：重新命名一台監視設備。
  /// PATCH /api/pairing/monitor_device
  ///
  /// 後端的 `device_id = crc32("elder_id|device_name")`，**改名即改身分**，
  /// 因此後端會在同一次請求內同步更新 `monitor_device_binding`、
  /// `user_fcm_token.device_name`、`cctv_feed_status.device_id` 與兩個記憶體字典，
  /// 並對該裝置推 `monitor-renamed` 事件。
  ///
  /// 回傳後端的 data（含 `device_id`）；失敗回 null。
  /// 撞名時後端回 **409**，此處一併吞成 null——呼叫端只需知道「沒成功」。
  static Future<Map<String, dynamic>?> renameMonitorDevice({
    required String elderId,
    required int userId,
    required String oldDeviceName,
    required String newDeviceName,
  }) async {
    try {
      final response = await http
          .patch(
            Uri.parse('$baseUrl/pairing/monitor_device'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'elder_id': elderId,
              'user_id': userId,
              'old_device_name': oldDeviceName,
              'new_device_name': newDeviceName,
            }),
          )
          .timeout(_timeout);
      final data = _safeDecode(response);
      if (data['status'] != 'success') {
        debugPrint('⚠️ renameMonitorDevice 被拒: ${response.statusCode} $data');
        return null;
      }
      final payload = data['data'];
      return payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{};
    } catch (e) {
      debugPrint('⚠️ renameMonitorDevice error: $e');
      return null;
    }
  }

  /// ★ 2026-08-04 第 7 項：開通／延長警報的音頻橋（30 分鐘單向音頻）。
  /// POST /api/alerts/{alert_id}/audio-bridge
  static Future<Map<String, dynamic>?> openAudioBridge({
    required int alertId,
    required int fromId,
    required int toDeviceId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/alerts/$alertId/audio-bridge'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'from_id': fromId,
              'to_device_id': toDeviceId,
            }),
          )
          .timeout(_timeout);
      final data = _safeDecode(response);
      if (data['status'] == 'success') {
        final payload = data['data'];
        return payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{};
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ openAudioBridge error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getElderMoodInsight(String elderId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/ai/elder_mood_insight/$elderId'))
          .timeout(_timeout);
      final data = _safeDecode(response);
      if (data['status'] == 'success') {
        return data['data'];
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ getElderMoodInsight error: $e');
      return null;
    }
  }

  static Future<List<dynamic>> getElderActivityLogs(String elderId, {int limit = 10}) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/activity/elder/$elderId?limit=$limit'))
          .timeout(_timeout);
      final data = _safeDecode(response);
      if (data['status'] == 'success' && data['data'] is List) {
        return data['data'];
      }
      return [];
    } catch (e) {
      debugPrint('⚠️ getElderActivityLogs error: $e');
      return [];
    }
  }

  /// ★ 2026-08-17 第二十五輪（需求 3）：長輩跌倒／緊急警報的**持久歷史記錄**。
  /// GET /api/alerts/{elder_id}?user_id=...&status=...&limit=...
  /// （對應後端 `uban-api/routers/alert.py:47`）
  ///
  /// 這支端點在今天之前於全專案**零消費者**——Flutter 端從未呼叫過。首頁「最新警示」
  /// 過去只能靠 [getElderActivityLogs] 讀取完全不同的 `activity_log` 表（一般活動流水
  /// 記錄），沒有任何管道能取得 `emergency_alerts` 表裡持久化的跌倒／爬行警報
  /// （含 snapshot_url 快照、acknowledged_by/acknowledged_at 等稽核欄位）。本方法補上
  /// 這條路徑，讓首頁能顯示**真正的**警示歷史，而不是把一般活動誤當警示呈現。
  ///
  /// `user_id` 為後端**必填**參數（用於 `call_security.is_user_linked_to_elder` 關係
  /// 驗證，非本人或未配對家屬一律回 404 不回 403，避免被拿來列舉），呼叫端務必帶上
  /// 目前登入者的 user_id。任何失敗（含 404／逾時／解析錯誤）一律吞掉回傳空陣列，
  /// 絕不拋出——首頁必須照常渲染，警示區塊只是少一筆資料而已。
  ///
  /// `elderId` 沿用 [getElderActivityLogs] 的簽章慣例採**位置參數**，`userId` 因為是
  /// 後端必填、呼叫端不應遺漏，改用具名 `required` 更凸顯它不是可選項。
  static Future<List<dynamic>> getEmergencyAlerts(
    String elderId, {
    required int userId,
    String? status,
    int limit = 20,
  }) async {
    try {
      final queryParameters = <String, String>{
        'user_id': userId.toString(),
        'limit': limit.toString(),
      };
      if (status != null && status.isNotEmpty) {
        queryParameters['status'] = status;
      }
      final uri = Uri.parse('$baseUrl/alerts/$elderId')
          .replace(queryParameters: queryParameters);
      final response = await http.get(uri).timeout(_timeout);
      final data = _safeDecode(response);
      if (data['status'] == 'success' && data['data'] is Map) {
        final alerts = data['data']['alerts'];
        if (alerts is List) return alerts;
      }
      return [];
    } catch (e) {
      debugPrint('⚠️ getEmergencyAlerts error: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // IPS（室內定位）— 2026-08-18 新增
  // 後端完整邏輯見 uban-api/routers/ips.py、uban-api/services/indoor_position.py。
  // 三支端點皆要求 user_id（家屬的 caregiver_id）與 device_id（監視機
  // device_id），無配對關係一律回 404（比照本檔其餘校準／監控類端點，不回
  // 403，避免被用來列舉 elder_id）。
  // ═══════════════════════════════════════════════════════════

  /// ★ IPS：讀取家屬為某監視機校準過的樓層區域（zone）多邊形設定。
  /// GET /api/ips/zones/{elder_id}?user_id=&device_id=
  ///
  /// 回傳的每筆元素為 `{name, polygon:[[x,y],...]}`，座標為正規化 [0,1]、
  /// 原點在畫面左上角（見後端 indoor_position.py::validate_zones）。尚未
  /// 校準過、或任何失敗（含 404 無權）一律回傳空陣列，不拋出——呼叫端
  /// （校準畫面）看到 `[]` 只會顯示「尚未校準」，不是錯誤畫面。
  static Future<List<dynamic>> getZoneConfig(
    String elderId, {
    required int userId,
    required int deviceId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/ips/zones/$elderId').replace(
        queryParameters: {
          'user_id': userId.toString(),
          'device_id': deviceId.toString(),
        },
      );
      final response = await http.get(uri).timeout(_timeout);
      final data = _safeDecode(response);
      if (data['status'] == 'success' && data['data'] is Map) {
        final zones = data['data']['zones'];
        if (zones is List) return zones;
      }
      return [];
    } catch (e) {
      debugPrint('⚠️ getZoneConfig error: $e');
      return [];
    }
  }

  /// ★ IPS：全量覆寫某監視機的樓層區域（zone）多邊形設定（家屬端「校準」
  /// 流程的落地點）。
  /// PUT /api/ips/zones/{elder_id}?user_id=&device_id=  body: `{"zones":[...]}`
  ///
  /// 全量覆寫、不做局部合併——校準是一次性動作，呼叫端每次都要送出完整
  /// 清單。範圍較小／較精確的 zone（例如「浴室」）必須排在陣列前面：後端
  /// `classify_zone` 是 first-match-wins，順序決定歸屬。
  ///
  /// 回傳 `null` 代表成功；非 null 為可直接顯示的錯誤原因。做法比照
  /// [triggerTestFall]：FastAPI 的 HTTPException 一律以 `{"detail": "..."}`
  /// 回傳，400（座標格式錯誤）與 404（無權）都在這裡被轉成看得懂的中文。
  static Future<String?> saveZoneConfig(
    String elderId, {
    required int userId,
    required int deviceId,
    required List<Map<String, dynamic>> zones,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/ips/zones/$elderId').replace(
        queryParameters: {
          'user_id': userId.toString(),
          'device_id': deviceId.toString(),
        },
      );
      final response = await http
          .put(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'zones': zones}),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) return null;
      // FastAPI 的 HTTPException 一律以 {"detail": "..."} 回傳
      String detail = '儲存失敗（HTTP ${response.statusCode}）';
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map && decoded['detail'] != null) {
          detail = decoded['detail'].toString();
        }
      } catch (_) {
        // body 不是 JSON 就沿用上面的預設訊息
      }
      debugPrint('⚠️ saveZoneConfig 被拒: ${response.statusCode} $detail');
      return detail;
    } catch (e) {
      debugPrint('⚠️ saveZoneConfig error: $e');
      return '無法連線到後端，請確認網路狀態';
    }
  }

  /// ★ IPS：查詢長輩目前所在的樓層區域（zone）與已停留秒數。
  /// GET /api/ips/current/{elder_id}?user_id=&device_id=
  ///
  /// 尚無任何 YOLO 推論資料時（IPS_ENABLED=false、或這台監視機從未被推論
  /// 過）後端回傳 `zone:'unknown', dwell_seconds:0, last_seen:null`——這是
  /// 合法的「尚無資料」狀態，此處原樣透傳，呼叫端自行判斷 `zone` 是否為
  /// `'unknown'`。任何失敗（含 404 無權）一律回傳空 Map，呼叫端請將 `{}`
  /// 視同「尚無資料」。
  static Future<Map<String, dynamic>> getCurrentZone(
    String elderId, {
    required int userId,
    required int deviceId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/ips/current/$elderId').replace(
        queryParameters: {
          'user_id': userId.toString(),
          'device_id': deviceId.toString(),
        },
      );
      final response = await http.get(uri).timeout(_timeout);
      final data = _safeDecode(response);
      if (data['status'] == 'success' && data['data'] is Map) {
        return Map<String, dynamic>.from(data['data']);
      }
      return {};
    } catch (e) {
      debugPrint('⚠️ getCurrentZone error: $e');
      return {};
    }
  }

  /// ★ IPS：組出監視機最近一次快照畫面的 URL，供校準畫面用 `Image.network`
  /// （或共用同一個 `ImageProvider`）直接載入，藉此拿到內建的快取與載入
  /// 進度，不必自己抓 bytes 再轉 `Image.memory`。
  /// GET /api/ips/snapshot/{elder_id}?user_id=&device_id=
  ///
  /// 純字串組裝、不發送請求，因此不需要 try/catch 或 timeout；請求本身
  /// 何時發生、失敗如何呈現由呼叫端的 `Image` widget 決定。尚無快取影格時
  /// 後端回 404，呼叫端須自行處理（見 zone_calibration_screen.dart 的
  /// 空狀態設計）。
  static String zoneSnapshotUrl(
    String elderId, {
    required int userId,
    required int deviceId,
  }) {
    final uri = Uri.parse('$baseUrl/ips/snapshot/$elderId').replace(
      queryParameters: {
        'user_id': userId.toString(),
        'device_id': deviceId.toString(),
      },
    );
    return uri.toString();
  }

  /// ★ 2026-08-04 第 7 項：查詢某警報目前是否有有效的音頻橋。
  /// GET /api/alerts/audio/{alert_id}
  ///
  /// ★ 2026-08-05 第十七輪（安全）：新增選填 `userId`。後端有帶就驗證
  /// 「此人是否為該警報長輩的本人或已配對家屬」，並在通過後才回傳
  /// `from_id` / `to_device_id`；未帶則只回布林狀態與到期時間。
  /// 呼叫端請一律帶上，讓它走完整驗證分支。
  static Future<Map<String, dynamic>?> checkAudioBridge(
    int alertId, {
    int? userId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/alerts/audio/$alertId').replace(
        queryParameters: userId == null ? null : {'user_id': '$userId'},
      );
      final response = await http.get(uri).timeout(_timeout);
      final data = _safeDecode(response);
      if (data['status'] == 'success') {
        return data['data'];
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ checkAudioBridge error: $e');
      return null;
    }
  }
}
