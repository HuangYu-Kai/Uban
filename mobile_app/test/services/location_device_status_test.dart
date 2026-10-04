import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_application_1/services/location_device_status.dart';

void main() {
  group('LocationDeviceStatus.fromDevice', () {
    String map(LocationPermission p, {bool service = true}) =>
        LocationDeviceStatus.fromDevice(serviceEnabled: service, permission: p);

    test('定位服務關閉優先於任何權限', () {
      for (final p in LocationPermission.values) {
        expect(map(p, service: false), 'service_disabled');
      }
    });

    test('權限對照', () {
      expect(map(LocationPermission.deniedForever), 'permission_denied_forever');
      expect(map(LocationPermission.denied), 'permission_denied');
      expect(map(LocationPermission.whileInUse), 'foreground_only');
      expect(map(LocationPermission.always), 'ok');
      expect(map(LocationPermission.unableToDetermine), 'ok');
    });
  });

  group('文案與判斷', () {
    test('isProblem：只有四種問題狀態為 true，null／ok／未知為 false', () {
      expect(LocationDeviceStatus.isProblem('service_disabled'), isTrue);
      expect(LocationDeviceStatus.isProblem('permission_denied'), isTrue);
      expect(LocationDeviceStatus.isProblem('permission_denied_forever'), isTrue);
      expect(LocationDeviceStatus.isProblem('foreground_only'), isTrue);
      expect(LocationDeviceStatus.isProblem('ok'), isFalse);
      expect(LocationDeviceStatus.isProblem(null), isFalse);
      expect(LocationDeviceStatus.isProblem('something_new'), isFalse);
    });

    test('shortLabel／familyMessage：問題狀態有文字，其餘為 null', () {
      for (final s in ['service_disabled', 'permission_denied', 'permission_denied_forever', 'foreground_only']) {
        expect(LocationDeviceStatus.shortLabel(s), isNotNull);
        expect(LocationDeviceStatus.familyMessage(s), isNotNull);
      }
      expect(LocationDeviceStatus.shortLabel('permission_denied'), '⚠️ 長輩手機未允許定位');
      expect(LocationDeviceStatus.shortLabel('ok'), isNull);
      expect(LocationDeviceStatus.familyMessage(null), isNull);
    });

    test('reportedAgoText 分級', () {
      final now = DateTime(2026, 10, 3, 12);
      expect(LocationDeviceStatus.reportedAgoText(null, now: now), '');
      expect(LocationDeviceStatus.reportedAgoText(now, now: now), '（剛剛回報）');
      expect(LocationDeviceStatus.reportedAgoText(now.subtract(const Duration(minutes: 7)), now: now),
          '（7 分鐘前回報）');
      expect(LocationDeviceStatus.reportedAgoText(now.subtract(const Duration(hours: 3)), now: now),
          '（3 小時前回報）');
      expect(LocationDeviceStatus.reportedAgoText(now.subtract(const Duration(days: 2)), now: now),
          '（2 天前回報）');
    });
  });
}
