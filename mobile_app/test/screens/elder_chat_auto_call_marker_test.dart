import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/elder_chat_screen.dart';

void main() {
  test('家人撥號標記可解析並剝除', () {
    const t = '好的，我幫您打視訊電話！[AUTO_CALL:video]';
    final r = parseAutoCallMarker(t);
    expect(r?.isVideo, true);
    expect(r?.friendElderId, isNull);
    expect(stripAutoCallMarkers(t), '好的，我幫您打視訊電話！');
  });

  test('好友撥號標記優先、語音通話', () {
    const t = '打給老王[AUTO_CALL_FRIEND:audio:abc123]';
    final r = parseAutoCallMarker(t);
    expect(r?.isVideo, false);
    expect(r?.friendElderId, 'abc123');
    expect(stripAutoCallMarkers(t), '打給老王');
  });

  test('無標記回 null；串流中未收完的標記前綴不外露', () {
    expect(parseAutoCallMarker('你好'), isNull);
    expect(stripAutoCallMarkers('請稍等[AUTO_CA'), '請稍等[AUTO_CA');
    expect(stripAutoCallMarkers('請稍等[AUTO_CALL:vid'), '請稍等');
  });

  group('waitFirstEventOrTimeout', () {
    // 重現原 bug：宣告為 Stream<void>，執行期實際是 Stream<int>
    Stream<void> runtimeGeneric(StreamController<int> c) => c.stream;

    test('事件到達時完成', () async {
      final c = StreamController<int>();
      final f = waitFirstEventOrTimeout(
          runtimeGeneric(c), const Duration(seconds: 5));
      c.add(1);
      await f; // 不逾時即返回
      await c.close();
    });

    test('沒有事件時逾時後正常完成、不丟例外', () async {
      final c = StreamController<int>();
      final sw = Stopwatch()..start();
      await waitFirstEventOrTimeout(
          runtimeGeneric(c), const Duration(milliseconds: 50));
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(40));
      await c.close();
    });

    test('完成後訂閱已取消', () async {
      final c = StreamController<int>();
      await waitFirstEventOrTimeout(
          runtimeGeneric(c), const Duration(milliseconds: 50));
      expect(c.hasListener, isFalse);
      await c.close();
    });

    test('串流出錯或結束也視為完成', () async {
      final c1 = StreamController<int>();
      final f1 = waitFirstEventOrTimeout(
          runtimeGeneric(c1), const Duration(seconds: 5));
      c1.addError(StateError('x'));
      await f1;
      await c1.close();

      final c2 = StreamController<int>();
      final f2 = waitFirstEventOrTimeout(
          runtimeGeneric(c2), const Duration(seconds: 5));
      await c2.close();
      await f2;
    });
  });

  group('FirstEventWaiter', () {
    test('先訂閱：wait 之前到的事件不會漏接', () async {
      final c = StreamController<int>.broadcast();
      final w = FirstEventWaiter(c.stream);
      c.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(w.fired, isTrue);
      final sw = Stopwatch()..start();
      await w.wait(const Duration(seconds: 5));
      expect(sw.elapsedMilliseconds, lessThan(1000));
      await w.dispose();
      expect(c.hasListener, isFalse);
      await c.close();
    });

    test('逾時從 wait 才起算', () async {
      final c = StreamController<int>();
      final w = FirstEventWaiter(c.stream);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(w.fired, isFalse);
      final sw = Stopwatch()..start();
      await w.wait(const Duration(milliseconds: 50));
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(40));
      await w.dispose();
      await c.close();
    });
  });
}
