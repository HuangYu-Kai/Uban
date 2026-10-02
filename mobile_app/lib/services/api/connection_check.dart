import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// 連線自檢分類結果。
///
/// ★ 第五十一輪：在此之前，DNS 解析失敗（例如誤打到 Tailscale MagicDNS
/// 名稱、或裝置沒有網路）只會讓使用者看到一句原始的
/// `OS Error: No address associated with host name, errno = 7`，完全看不出
/// 是哪一台主機、也不知道該怎麼辦。這裡把常見的失敗型態分類，並固定把
/// 「嘗試的主機名稱」帶進訊息裡，方便使用者回報或自行判斷（例如發現連到
/// 的是內網主機名稱，代表裝置沒連上正確網路）。
enum ConnectionCheckStatus {
  ok,
  dnsFailure,
  timeout,
  serverError,
}

class ConnectionCheckResult {
  final ConnectionCheckStatus status;
  final String host;
  final String? detail;

  const ConnectionCheckResult({
    required this.status,
    required this.host,
    this.detail,
  });

  bool get isOk => status == ConnectionCheckStatus.ok;

  /// 給長輩／家屬看的繁體中文訊息，一律帶出嘗試連線的主機名稱。
  String get userMessage {
    switch (status) {
      case ConnectionCheckStatus.ok:
        return '連線正常';
      case ConnectionCheckStatus.dnsFailure:
        return 'DNS 解析失敗（找不到伺服器「$host」），請確認裝置網路設定，或聯絡系統管理者確認伺服器位址';
      case ConnectionCheckStatus.timeout:
        return '連線逾時（伺服器「$host」沒有回應），請檢查網路狀態後再試一次';
      case ConnectionCheckStatus.serverError:
        return '伺服器回應異常（「$host」${detail != null ? '：$detail' : ''}），請稍後再試';
    }
  }
}

/// 連線自檢工具：呼叫 `<serverRootUrl>/health`（見 `uban-api/main.py`）確認
/// 主後端是否可連上，並把失敗原因分類成使用者看得懂的訊息。
///
/// 刻意獨立成一個小工具而非塞進 `ApiClient.get()`：這是「主動檢查」用途
/// （呼叫端想先知道連不連得上，再決定要不要往下做有副作用的操作，例如撥打
/// 視訊通話），語意上與既有的被動請求方法不同。
class ConnectionChecker {
  static Future<ConnectionCheckResult> check({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final rootUrl = ApiClient.serverRootUrl;
    final host = Uri.tryParse(rootUrl)?.host ?? rootUrl;
    final uri = Uri.parse('$rootUrl/health');
    try {
      final response = await http.get(uri).timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ConnectionCheckResult(status: ConnectionCheckStatus.ok, host: host);
      }
      return ConnectionCheckResult(
        status: ConnectionCheckStatus.serverError,
        host: host,
        detail: 'HTTP ${response.statusCode}',
      );
    } on SocketException catch (e) {
      // errno 7 = EAI_NONAME（DNS 解析失敗）；不同平台的錯誤文字不盡相同，
      // 訊息裡常見的關鍵字一併比對，避免只靠 errorCode 漏判。
      final msg = e.message.toLowerCase();
      final isDnsFailure = e.osError?.errorCode == 7 ||
          msg.contains('no address associated with hostname') ||
          msg.contains('failed host lookup') ||
          msg.contains('nodename nor servname');
      return ConnectionCheckResult(
        status: isDnsFailure ? ConnectionCheckStatus.dnsFailure : ConnectionCheckStatus.serverError,
        host: host,
        detail: e.message,
      );
    } on TimeoutException {
      return ConnectionCheckResult(status: ConnectionCheckStatus.timeout, host: host);
    } catch (e) {
      return ConnectionCheckResult(
        status: ConnectionCheckStatus.serverError,
        host: host,
        detail: e.toString(),
      );
    }
  }
}
