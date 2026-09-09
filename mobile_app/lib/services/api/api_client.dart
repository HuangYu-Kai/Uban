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

  // 本機 AI Server（Ollama）
  static const String localAiServerIp = String.fromEnvironment(
    'LOCAL_AI_IP',
    defaultValue: 'boyo-desktop.tail531c8a.ts.net',
  );

  static String get localAiBaseUrl {
    if (localAiServerIp.startsWith('http://') || localAiServerIp.startsWith('https://')) {
      return localAiServerIp.endsWith('/api') ? localAiServerIp : '$localAiServerIp/api';
    }
    if (localAiServerIp.contains('ts.net')) {
      return 'https://$localAiServerIp/api';
    }
    return 'http://$localAiServerIp:8000/api';
  }

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
      if (url.contains('ts.net') || response.statusCode == 404 || response.statusCode == 405) {
        final cleanPath = path.startsWith('/api') ? path.substring(4) : path;
        final fallbackUrl = 'http://10.0.2.2:8000/api$cleanPath';
        debugPrint('🔄 [ApiService.put Fallback] -> $fallbackUrl');
        final fbRes = await http.put(
          Uri.parse(fallbackUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 4));
        if (fbRes.statusCode == 200 || fbRes.statusCode == 201) {
          return safeDecode(fbRes);
        }
      }
      return safeDecode(response);
    } catch (e) {
      debugPrint('⚠️ ApiService.put error: $e');
      try {
        final cleanPath = path.startsWith('/api') ? path.substring(4) : path;
        final fallbackUrl = 'http://10.0.2.2:8000/api$cleanPath';
        final fbRes = await http.put(
          Uri.parse(fallbackUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 4));
        if (fbRes.statusCode == 200 || fbRes.statusCode == 201) {
          return safeDecode(fbRes);
        }
      } catch (_) {}
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
      if (url.contains('ts.net') || response.statusCode == 404) {
        final cleanPath = path.startsWith('/api') ? path.substring(4) : path;
        final fallbackUrl = 'http://10.0.2.2:8000/api$cleanPath';
        debugPrint('🔄 [ApiService.delete Fallback] -> $fallbackUrl');
        final fbRes = await http.delete(Uri.parse(fallbackUrl)).timeout(const Duration(seconds: 4));
        if (fbRes.statusCode == 200 || fbRes.statusCode == 201) {
          return safeDecode(fbRes);
        }
      }
      return safeDecode(response);
    } catch (e) {
      debugPrint('⚠️ ApiService.delete error: $e');
      try {
        final cleanPath = path.startsWith('/api') ? path.substring(4) : path;
        final fallbackUrl = 'http://10.0.2.2:8000/api$cleanPath';
        final fbRes = await http.delete(Uri.parse(fallbackUrl)).timeout(const Duration(seconds: 4));
        if (fbRes.statusCode == 200 || fbRes.statusCode == 201) {
          return safeDecode(fbRes);
        }
      } catch (_) {}
      return null;
    }
  }
}
