import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// AI 對話、串流 SSE、語音 ASR/TTS、心情分析與每日建議 API
class AiChatApi {
  // AI 相關功能（統一走主後端，見下方第五十一輪說明）
  static Future<Map<String, dynamic>> aiChat(
    int userId,
    String message, {
    String? imageUrl,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/ai/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': userId,
              'message': message,
              if (imageUrl != null) 'image_url': imageUrl,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return ApiClient.safeDecode(response);
      }
      return {'status': 'error', 'message': '伺服器錯誤: ${response.statusCode}'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  /// AI 串流聊天（SSE）- 逐 token 回傳，支援自訂長輩稱謂 (appellation)
  ///
  /// ★ 第五十一輪：移除原本的多候選主機降級清單。`boyo-desktop.tail531c8a.ts.net`
  /// 是 Tailscale MagicDNS 名稱，未加入該 tailnet 的手機在公開 DNS 上解析不到
  /// （`OS Error: No address associated with host name, errno = 7`），而
  /// `run.ps1`／`run.sh` 從未帶過 `--dart-define=LOCAL_AI_IP`，所以這台候選主機
  /// 在真機上永遠連不上、每次都要先等它逾時才會輪到下一候選。AI 對話端點其實
  /// 已同時掛在主後端（`ApiClient.baseUrl`），故直接改走主後端；路徑同步修正為
  /// 後端實際註冊的 `/ai/chat_stream`（底線）——原本用的 `/ai/chat/stream`
  /// （斜線）從未被註冊過，打中主後端也只會拿到 404。
  static Stream<String> aiChatStream(
    int userId,
    String message, {
    String? appellation,
    String? userName,
  }) async* {
    final targetUrl = '${ApiClient.baseUrl}/ai/chat_stream';
    final client = http.Client();
    try {
      debugPrint('📡 [aiChatStream] -> $targetUrl');
      final request = http.Request('POST', Uri.parse(targetUrl));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'user_id': userId,
        'message': message,
        if (appellation != null && appellation.isNotEmpty) 'appellation': appellation,
        if (userName != null && userName.isNotEmpty) 'user_name': userName,
      });

      final streamedResponse = await client.send(request).timeout(const Duration(seconds: 15));

      if (streamedResponse.statusCode != 200) {
        client.close();
        yield '[ERROR] 伺服器錯誤: ${streamedResponse.statusCode}';
        return;
      }

      yield* parseChatStreamBytes(streamedResponse.stream);
      client.close();
    } catch (e) {
      debugPrint('⚠️ [aiChatStream Fail] $targetUrl error: $e');
      client.close();
      yield '[ERROR] $e';
    }
  }

  /// 解析 `/ai/chat_stream` 的 SSE 位元組串，逐行取出 `data: ` payload、轉為
  /// 乾淨文字 token 並 yield 出去。
  ///
  /// ★ 第五十三輪抽成獨立函式：一是讓解析邏輯能在不真的打 HTTP 的情況下
  /// 做單元測試（見 test/services/api/ai_chat_api_test.dart），二是修正原本
  /// 的解析錯誤——後端 `routers/ai.py::ai_chat_stream()` 實際送出的每一行
  /// `data:` 都是 JSON **物件**（`{"chunk": "..."}` / `{"audio_ready": true}`
  /// / `{"done": true}`），不是裸字串，舊版 `jsonDecode(payload) as String`
  /// 對物件必定拋型別例外，落到 `catch` 又把整段 JSON 原文 `yield` 出去，
  /// 使用者因此在畫面上看到 `{"chunk": "..."}` 字樣。解析語意對齊
  /// `elder_chat_tab.dart` 既有的 SSE 處理（約第 787–805 行），讓語音助理
  /// 與聊天分頁的行為一致。
  @visibleForTesting
  static Stream<String> parseChatStreamBytes(Stream<List<int>> byteStream) async* {
    final StringBuffer lineBuf = StringBuffer();

    await for (final chunk in byteStream) {
      final decoded = utf8.decode(chunk, allowMalformed: true);
      for (int i = 0; i < decoded.length; i++) {
        final ch = decoded[i];
        if (ch == '\n') {
          final line = lineBuf.toString().trimRight();
          lineBuf.clear();
          if (line.startsWith('data: ')) {
            final payload = line.substring(6).trim();
            if (payload.isEmpty) {
              // 空白 data 行（心跳／邊界雜訊），略過。
            } else if (payload.startsWith('[ERROR]')) {
              // 目前後端 /chat_stream 從不送這種裸字串前綴（真正的後端錯誤
              // 是走下面的 JSON 例外分支），保留純字串防呆是因為呼叫端
              // （elder_chat_screen.dart）有在判斷 token.startsWith('[ERROR]')。
              yield payload;
              return;
            } else {
              // ⚠️ 這裡不再有 "[DONE]" 裸字串判斷——grep 過 ai.py 全檔，
              // 後端從未送過這個值，是從寫下那天就沒生效過的死碼；結束一律
              // 靠下面的 JSON {"done": true}。
              try {
                final decodedJson = jsonDecode(payload);
                if (decodedJson is Map) {
                  if (decodedJson['done'] == true) {
                    return;
                  } else if (decodedJson['audio_ready'] == true) {
                    // 這支函式只負責文字串流；伺服器端合成音訊走 WebRTC
                    // 另一條路徑，語音助理用的是裝置端 TTS，安靜略過即可，
                    // 不能當成文字 yield 出去。
                  } else if (decodedJson['chunk'] is String) {
                    final chunkText = decodedJson['chunk'] as String;
                    if (chunkText.isNotEmpty) yield chunkText;
                  } else {
                    debugPrint('⚠️ [aiChatStream] 無法辨識的 SSE 訊框: $payload');
                  }
                } else {
                  debugPrint('⚠️ [aiChatStream] SSE payload 不是 JSON 物件: $payload');
                }
              } catch (e) {
                // ⚠️ 第五十三輪修正的核心：不再 `yield payload` 把解析失敗
                // 的原始 JSON 文字丟給使用者看（那正是本輪要修的 bug），
                // 改成記錄到 debug log 後略過這一行。
                debugPrint('⚠️ [aiChatStream] SSE JSON parse error: $e, payload=$payload');
              }
            }
          }
        } else {
          lineBuf.write(ch);
        }
      }
    }
  }

  /// 語音轉文字 (ASR/STT) - 上傳本地錄音檔至主後端
  static Future<String?> transcribeAudio(String filePath) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiClient.baseUrl}/voice/transcribe'),
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
            Uri.parse('${ApiClient.baseUrl}/ai/pet_greeting'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId, 'message': context}),
          )
          .timeout(const Duration(seconds: 120));
      return ApiClient.safeDecode(response);
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<List<dynamic>> getPersonaTemplates() async {
    try {
      final response = await http
          .get(Uri.parse('${ApiClient.baseUrl}/ai/persona_templates'))
          .timeout(ApiClient.timeout);
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
          .get(Uri.parse('${ApiClient.baseUrl}/user/elder/$elderId'))
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  /// 獲取長輩的今日智能建議
  static Future<Map<String, dynamic>> getDailySuggestions(int elderId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiClient.baseUrl}/ai/daily-suggestions/$elderId'))
          .timeout(const Duration(seconds: 60));
      return ApiClient.safeDecode(response);
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

      final uri = Uri.parse('${ApiClient.baseUrl}/news').replace(queryParameters: queryParameters);
      final response = await http.get(uri).timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
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
      final uri = Uri.parse('${ApiClient.baseUrl}/voice/tts/test')
          .replace(queryParameters: queryParameters);
      final response = await http.post(uri).timeout(const Duration(seconds: 120));
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '語音合成逾時，請稍後再試'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  /// 根據長期記憶 (RAG) 生成一片對話落葉話題
  static Future<Map<String, dynamic>?> getElderMoodInsight(String elderId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiClient.baseUrl}/ai/elder_mood_insight/$elderId'))
          .timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(response);
      if (data['status'] == 'success') {
        return data['data'];
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ getElderMoodInsight error: $e');
      return null;
    }
  }
}
