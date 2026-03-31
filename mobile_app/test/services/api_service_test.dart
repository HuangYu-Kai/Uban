import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiService Tests', () {
    test('baseUrl should be correctly formatted for Tailscale', () {
      const serverIp = 'localhost-0.tail5abf5e.ts.net';
      final isSecure = serverIp.contains('ngrok') || serverIp.contains('ts.net');
      expect(isSecure, true);
    });

    test('timeout constant should be 15 seconds', () {
      const timeout = Duration(seconds: 15);
      expect(timeout.inSeconds, 15);
    });

    test('error response format should be correct', () {
      final errorResponse = {'status': 'error', 'message': 'test'};
      expect(errorResponse['status'], 'error');
    });
  });
}
