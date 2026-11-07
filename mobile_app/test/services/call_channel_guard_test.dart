import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/call_channel_guard.dart';
import 'package:flutter_application_1/services/firebase_bg_handler.dart'
    show deriveMyRoleFromCall;

void main() {
  group('shouldIgnoreCallForDeviceChannel', () {
    test('通訊機：comm 房不忽略、monitor 房忽略', () {
      expect(shouldIgnoreCallForDeviceChannel(isMonitorDevice: false, roomId: 'comm_elder_0001'), isFalse);
      expect(shouldIgnoreCallForDeviceChannel(isMonitorDevice: false, roomId: 'monitor_elder_0001'), isTrue);
    });
    test('監控機：monitor 房不忽略、comm 房與非標準房忽略', () {
      expect(shouldIgnoreCallForDeviceChannel(isMonitorDevice: true, roomId: 'monitor_elder_0001'), isFalse);
      expect(shouldIgnoreCallForDeviceChannel(isMonitorDevice: true, roomId: 'comm_elder_0001'), isTrue);
      expect(shouldIgnoreCallForDeviceChannel(isMonitorDevice: true, roomId: '77'), isTrue);
    });
    test('房號空白或 null 不忽略（維持舊行為）', () {
      expect(shouldIgnoreCallForDeviceChannel(isMonitorDevice: true, roomId: null), isFalse);
      expect(shouldIgnoreCallForDeviceChannel(isMonitorDevice: false, roomId: '  '), isFalse);
    });
  });

  group('resolveCallSenderRole', () {
    test('emergency-call 缺角色視為 family，長輩機即使 prefs 角色漂移也推導為 elder', () {
      final r = resolveCallSenderRole(type: 'emergency-call', roleRaw: null);
      expect(r, 'family');
      expect(deriveMyRoleFromCall(r, 'family'), 'elder');
      expect(resolveCallSenderRole(type: 'emergency-call', roleRaw: '  '), 'family');
    });
    test('有角色就以 payload 為準；一般來電缺角色維持原值', () {
      expect(resolveCallSenderRole(type: 'emergency-call', roleRaw: 'elder'), 'elder');
      expect(resolveCallSenderRole(type: 'call-request', roleRaw: null), isNull);
      expect(resolveCallSenderRole(type: 'call-request', roleRaw: 'family'), 'family');
    });
  });
}
