import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 基礎 API 通訊客戶端，負責處理伺服器端點解析、共同 Header 與底層 HTTP 請求
class ApiClient {
  // --- 動態伺服器 IP 設置 ---
  static const String serverIp = String.fromEnvironment(
    'SERVER_IP',
    defaultValue: 'localhost-0.tail5abf5e.ts.net',
  );

  // 依據環境動態切換 API 基礎網址
  static String get baseUrl {
    if (serverIp.startsWith('http://') || serverIp.startsWith('https://')) {
      return serverIp.endsWith('/api') ? serverIp : '$serverIp/api';
    }
    if (serverIp.contains('ts.net') || serverIp.contains('ngrok')) {
      return 'https://$serverIp/api';
    }
    return 'http://$serverIp:8000/api';
  }

  static String get serverRootUrl {
    return serverIp.contains('ngrok') || serverIp.contains('ts.net')
        ? 'https://$serverIp'
        : 'http://$serverIp:8000';
  }

  // ★ 第五十一輪：原本這裡有一組獨立的本機 AI Server（Ollama，`boyo-desktop.
  // tail531c8a.ts.net`）位址設定（`localAiServerIp` / `localAiBaseUrl`）。
  // 該主機是 Tailscale MagicDNS 名稱，不在公開 DNS 上，任何未加入該 tailnet
  // 的手機呼叫它一律得到 `OS Error: No address associated with host name,
  // errno = 7`；而 `run.ps1`／`run.sh` 也從未帶過 `--dart-define=LOCAL_AI_IP`，
  // 所以這組設定實質上永遠指向一台真機連不到的主機。所有 AI 呼叫（對話、
  // 串流、ASR、TTS）已全部改走主後端（`baseUrl`／`serverRootUrl`），故整組
  // 移除；不要再加回獨立的 AI 主機設定。

  // 統一超時時間
  static const Duration timeout = Duration(seconds: 15);

  /// ★ 2026-08-05 第十七輪（安全）：監視機推流／跌倒測試端點的共用密鑰
  static const String cctvIngestToken =
      String.fromEnvironment('CCTV_INGEST_TOKEN', defaultValue: '');

  static Map<String, String> get deviceTokenHeader =>
      cctvIngestToken.isEmpty ? {} : {'X-Uban-Device-Token': cctvIngestToken};

  static String fullUrl(String path) {
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

  static Map<String, dynamic> safeDecode(http.Response response) {
    try {
      return jsonDecode(response.body);
    } catch (_) {
      return {'status': 'error', 'message': '伺服器回應格式錯誤: ${response.statusCode}'};
    }
  }

  static Future<Map<String, dynamic>?> get(String path) async {
    try {
      final url = fullUrl(path);
      debugPrint('📡 [ApiService.get] -> $url');
      final response = await http.get(Uri.parse(url)).timeout(timeout);
      debugPrint('📡 [ApiService.get] <- status: ${response.statusCode}, body: ${response.body}');
      if (response.statusCode == 200) {
        final decoded = safeDecode(response);
        if (decoded['status'] == 'success') {
          return decoded;
        }
      }
      return safeDecode(response);
    } catch (e) {
      debugPrint('⚠️ ApiService.get error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> post(String path, Map<String, dynamic> body) async {
    try {
      final url = fullUrl(path);
      debugPrint('📡 [ApiService.post] -> $url body: $body');
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
      debugPrint('📡 [ApiService.post] <- status: ${response.statusCode}, body: ${response.body}');
      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = safeDecode(response);
        if (decoded['status'] == 'success') {
          return decoded;
        }
      }
      return safeDecode(response);
    } catch (e) {
      debugPrint('⚠️ ApiService.post error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> put(String path, Map<String, dynamic> body) async {
    try {
      final url = fullUrl(path);
      debugPrint('📡 [ApiService.put] -> $url body: $body');
      final response = await http
          .put(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
      debugPrint('📡 [ApiService.put] <- status: ${response.statusCode}, body: ${response.body}');
      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = safeDecode(response);
        if (decoded['status'] == 'success') {
          return decoded;
        }
      }
      // ★ 第五十一輪：這裡原本在失敗／404／405 時會退而求其次打
      // `http://10.0.2.2:8000`。`10.0.2.2` 只在 Android 模擬器裡有意義
      // （指向宿主機的 loopback），實機上是死位址，只會多等好幾秒逾時才
      // 讓真正的錯誤浮現。`signaling.dart` 的 `onConnectError`（見該檔
      // 約 347-358 行）早就記錄過同一個結論並移除了對應的備援，這裡
      // 一併移除，不要再加回來。
      return safeDecode(response);
    } catch (e) {
      debugPrint('⚠️ ApiService.put error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> delete(String path) async {
    try {
      final url = fullUrl(path);
      debugPrint('📡 [ApiService.delete] -> $url');
      final response = await http.delete(Uri.parse(url)).timeout(timeout);
      debugPrint('📡 [ApiService.delete] <- status: ${response.statusCode}, body: ${response.body}');
      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = safeDecode(response);
        if (decoded['status'] == 'success') {
          return decoded;
        }
      }
      // ★ 第五十一輪：同 put() 上方註解——移除只在 Android 模擬器有意義的
      // `http://10.0.2.2:8000` 備援，理由與 signaling.dart:350-355 的既有
      // 說明一致，不要再加回來。
      return safeDecode(response);
    } catch (e) {
      debugPrint('⚠️ ApiService.delete error: $e');
      return null;
    }
  }
}
