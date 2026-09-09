import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// AI 對話、串流 SSE、語音 ASR/TTS、心情分析與每日建議 API
class AiChatApi {
  // AI 相關功能（使用本機 AI Server 與自動降級連線備援）
  static Future<Map<String, dynamic>> aiChat(
    int userId,
    String message, {
    String? imageUrl,
  }) async {
    final List<String> candidateUrls = [
      'https://boyo-desktop.tail531c8a.ts.net/api/ai/chat',
      '${ApiClient.localAiBaseUrl}/ai/chat',
      '${ApiClient.baseUrl.replaceFirst('/api', '')}/api/ai/chat',
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
          return ApiClient.safeDecode(response);
        }
      } catch (_) {}
    }
    return {'status': 'error', 'message': '網路連線失敗，請檢查 AI Server 是否開啟'};
  }

  /// AI 串流聊天（SSE）- 逐 token 回傳，支援多候選 IP 自動降級連線，支援自訂長輩稱謂 (appellation)
  static Stream<String> aiChatStream(
    int userId,
    String message, {
    String? appellation,
    String? userName,
  }) async* {
    final List<String> candidateUrls = [
      'https://boyo-desktop.tail531c8a.ts.net/api/ai/chat/stream',
      '${ApiClient.localAiBaseUrl}/ai/chat/stream',
      '${ApiClient.baseUrl.replaceFirst('/api', '')}/api/ai/chat/stream',
    ];
    final uniqueUrls = candidateUrls.toSet().toList();

    for (int idx = 0; idx < uniqueUrls.length; idx++) {
      final targetUrl = uniqueUrls[idx];
      final client = http.Client();
      try {
        debugPrint('📡 [aiChatStream Attempt ${idx + 1}] -> $targetUrl');
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
        Uri.parse('${ApiClient.localAiBaseUrl}/voice/transcribe'),
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
  static Future<Map<String, dynamic>> generatePondLeaf(int userId) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/ai/generate_pond_leaf?user_id=$userId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 45));
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '話題生成逾時，請稍後再試'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

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
