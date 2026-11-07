// ★ 2026-11-07：已取消 callId 持久清單與拒接決策的純函式測試。
import 'package:flutter_application_1/services/call_surface_dismiss.dart';
import 'package:flutter_application_1/services/cancelled_call_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const int now = 1000000000;

  group('parse / add / contains', () {
    test('空字串、壞 JSON、非物件一律回空 Map', () {
      expect(parseCancelledCalls(null, now), isEmpty);
      expect(parseCancelledCalls('', now), isEmpty);
      expect(parseCancelledCalls('not json', now), isEmpty);
      expect(parseCancelledCalls('[1,2]', now), isEmpty);
    });

    test('加入後可查到；空 callId 不加入也查不到', () {
      final m = addCancelledCall(<String, int>{}, 'c1', now);
      expect(isCallIdCancelled(m, 'c1', now), isTrue);
      expect(isCallIdCancelled(m, 'c2', now), isFalse);
      expect(addCancelledCall(m, '  ', now), equals(m));
      expect(isCallIdCancelled(m, '', now), isFalse);
      expect(isCallIdCancelled(m, null, now), isFalse);
    });

    test('TTL：5 分鐘內有效，超過即失效並於 parse 時剔除', () {
      final m = addCancelledCall(<String, int>{}, 'c1', now);
      expect(isCallIdCancelled(m, 'c1', now + kCancelledCallTtlMs), isTrue);
      expect(isCallIdCancelled(m, 'c1', now + kCancelledCallTtlMs + 1), isFalse);
      final raw = encodeCancelledCalls(m);
      expect(parseCancelledCalls(raw, now + 1000).containsKey('c1'), isTrue);
      expect(parseCancelledCalls(raw, now + kCancelledCallTtlMs + 1), isEmpty);
    });

    test('TTL 必須大於來電有效期 60 秒（才擋得住取消後才抵達的延遲來電）', () {
      expect(kCancelledCallTtlMs, greaterThan(60000));
    });

    test('超過上限時丟最舊的', () {
      var m = <String, int>{};
      for (int i = 0; i < kCancelledCallMax + 5; i++) {
        m = addCancelledCall(m, 'id$i', now + i);
      }
      expect(m.length, kCancelledCallMax);
      expect(m.containsKey('id0'), isFalse);
      expect(m.containsKey('id${kCancelledCallMax + 4}'), isTrue);
    });

    test('不改動傳入的 Map', () {
      final base = <String, int>{'a': now};
      addCancelledCall(base, 'b', now);
      expect(base.keys, ['a']);
    });
  });

  group('拒接決策', () {
    test('發起端已取消就不送拒接；否則送', () {
      expect(shouldSendDeclineToServer(alreadyEnded: true), isFalse);
      expect(shouldSendDeclineToServer(alreadyEnded: false), isTrue);
    });

    test('已取消時回饋文案永遠是「已結束」，不得顯示拒接失敗', () {
      final a = declineFeedbackText(alreadyEnded: true, success: false);
      expect(a.title, '來電已結束');
      final b = declineFeedbackText(alreadyEnded: false, success: true);
      expect(b.title, '已拒接來電');
      final c = declineFeedbackText(alreadyEnded: false, success: false);
      expect(c.title, '拒接時發生問題');
    });
  });

  group('shouldClearPendingForCancel', () {
    test('取消事件沒 callId 或 pending 沒 callId → 清', () {
      expect(shouldClearPendingForCancel(pendingCallId: 'a', cancelledCallId: ''), isTrue);
      expect(shouldClearPendingForCancel(pendingCallId: null, cancelledCallId: 'a'), isTrue);
      expect(shouldClearPendingForCancel(pendingCallId: '', cancelledCallId: 'a'), isTrue);
    });
    test('兩邊都有 callId → 只有相同才清（不誤殺另一通合法 pending）', () {
      expect(shouldClearPendingForCancel(pendingCallId: 'a', cancelledCallId: 'a'), isTrue);
      expect(shouldClearPendingForCancel(pendingCallId: 'a', cancelledCallId: 'b'), isFalse);
    });
  });

  group('CancelledCallStore（SharedPreferences mock）', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('mark 後 isCancelled 為 true，未標記為 false，空 id 安全', () async {
      expect(await CancelledCallStore.isCancelled('x'), isFalse);
      await CancelledCallStore.mark('x');
      expect(await CancelledCallStore.isCancelled('x'), isTrue);
      expect(await CancelledCallStore.isCancelled('y'), isFalse);
      await CancelledCallStore.mark('');
      await CancelledCallStore.mark(null);
      expect(await CancelledCallStore.allCancelled(), {'x'});
    });

    test('clearPendingCallPrefs 只清 callId 相符的 pending，四個鍵都處理', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'pendingAcceptedCall': '{"callId":"a","timestamp":1}',
        'pendingRingCallData': '{"callId":"a","timestamp":1}',
        'pendingRingCall': '{"callId":"a"}',
        'pendingLocalRingCall': '{"callId":"b","timestamp":1}',
      });
      await CallSurfaceDismisser.clearPendingCallPrefs(cancelledCallId: 'a');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pendingAcceptedCall'), isNull);
      expect(prefs.getString('pendingRingCallData'), isNull);
      expect(prefs.getString('pendingRingCall'), isNull);
      expect(prefs.getString('pendingLocalRingCall'), isNotNull,
          reason: '另一通 (callId=b) 的 pending 不可被 a 的取消抹掉');
    });
  });
}
