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
      final normalized = host.toLowerCase();
      if (normalized.endsWith('.ts.net') || normalized == 'localhost') {
        return true;
      }
      return false;
    };
    return client;
  }
}
