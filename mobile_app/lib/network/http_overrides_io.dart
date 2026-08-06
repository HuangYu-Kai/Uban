import 'dart:io';

void configureHttpOverrides() {
  HttpOverrides.global = _UbanHttpOverrides();
}

class _UbanHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
      return true; // 允許所有 SSL/TLS 憑證（含 Tailscale、ngrok、自簽憑證），避免 HandshakeException
    };
    return client;
  }
}
