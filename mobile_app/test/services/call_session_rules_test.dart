import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/call_session_rules.dart';

void main() {
  group('parseConnCheckAck', () {
    test('null（逾時）與例外 → noResponse', () {
      expect(parseConnCheckAck(null), ConnCheckVerdict.noResponse);
      expect(parseConnCheckAck(Exception('timeout')), ConnCheckVerdict.noResponse);
    });
    test('joined true / false', () {
      expect(parseConnCheckAck({'ok': true, 'joined': true}), ConnCheckVerdict.joined);
      expect(parseConnCheckAck({'ok': true, 'joined': false}), ConnCheckVerdict.notJoined);
    });
    test('List 包裝（socket_io_client 多參數 ack）取第一個', () {
      expect(parseConnCheckAck([{'ok': true, 'joined': true}]), ConnCheckVerdict.joined);
      expect(parseConnCheckAck([]), ConnCheckVerdict.notJoined);
    });
    test('有回應但格式怪 → 視為活著但不在房內', () {
      expect(parseConnCheckAck(<String, dynamic>{}), ConnCheckVerdict.notJoined);
      expect(parseConnCheckAck('ok'), ConnCheckVerdict.notJoined);
      expect(parseConnCheckAck({'joined': 'true'}), ConnCheckVerdict.notJoined);
    });
  });

  group('decideConnCheckAction', () {
    ConnCheckAction decide(ConnCheckVerdict v, {bool inCall = false, int? since}) =>
        decideConnCheckAction(verdict: v, inCall: inCall, secondsSinceLastRebuild: since);

    test('joined → none（通話中與否皆同）', () {
      expect(decide(ConnCheckVerdict.joined), ConnCheckAction.none);
      expect(decide(ConnCheckVerdict.joined, inCall: true), ConnCheckAction.none);
    });
    test('notJoined → rejoin（通話中也只是重送 join）', () {
      expect(decide(ConnCheckVerdict.notJoined), ConnCheckAction.rejoin);
      expect(decide(ConnCheckVerdict.notJoined, inCall: true), ConnCheckAction.rejoin);
    });
    test('noResponse + 通話中 → 只記 log，不重建（即使從未重建過）', () {
      expect(decide(ConnCheckVerdict.noResponse, inCall: true), ConnCheckAction.logOnlyInCall);
      expect(decide(ConnCheckVerdict.noResponse, inCall: true, since: 999), ConnCheckAction.logOnlyInCall);
    });
    test('noResponse + 非通話 + 從未重建 → rebuild', () {
      expect(decide(ConnCheckVerdict.noResponse), ConnCheckAction.rebuild);
    });
    test('noResponse + 冷卻內 → skipRebuildCooldown；邊界 59 秒仍在冷卻、60 秒可重建', () {
      expect(decide(ConnCheckVerdict.noResponse, since: 0), ConnCheckAction.skipRebuildCooldown);
      expect(decide(ConnCheckVerdict.noResponse, since: 59), ConnCheckAction.skipRebuildCooldown);
      expect(decide(ConnCheckVerdict.noResponse, since: 60), ConnCheckAction.rebuild);
      expect(decide(ConnCheckVerdict.noResponse, since: 3600), ConnCheckAction.rebuild);
    });
  });

  group('shouldRunPeriodicConnCheck', () {
    test('只有 前景 + 非通話 + 已連線 才跑', () {
      expect(shouldRunPeriodicConnCheck(isForeground: true, inCall: false, socketConnected: true), isTrue);
      expect(shouldRunPeriodicConnCheck(isForeground: false, inCall: false, socketConnected: true), isFalse);
      expect(shouldRunPeriodicConnCheck(isForeground: true, inCall: true, socketConnected: true), isFalse);
      expect(shouldRunPeriodicConnCheck(isForeground: true, inCall: false, socketConnected: false), isFalse);
    });
  });

  group('shouldResendAfterRebuild', () {
    test('世代未變 → 不重送', () {
      expect(shouldResendAfterRebuild(generationAtEmit: 2, generationNow: 2, socketConnected: true), isFalse);
    });
    test('世代已變且新連線已連上 → 重送', () {
      expect(shouldResendAfterRebuild(generationAtEmit: 2, generationNow: 4, socketConnected: true), isTrue);
    });
    test('世代已變但新連線沒連上 → 不重送', () {
      expect(shouldResendAfterRebuild(generationAtEmit: 2, generationNow: 4, socketConnected: false), isFalse);
    });
  });

  group('remainingBudget', () {
    test('扣掉已用時間', () {
      expect(remainingBudget(total: const Duration(seconds: 10), elapsed: const Duration(seconds: 4)),
          const Duration(seconds: 6));
    });
    test('剩餘不足 300ms 或已超時 → zero', () {
      expect(remainingBudget(total: const Duration(seconds: 10), elapsed: const Duration(milliseconds: 9800)),
          Duration.zero);
      expect(remainingBudget(total: const Duration(seconds: 1), elapsed: const Duration(seconds: 5)),
          Duration.zero);
    });
  });
}
