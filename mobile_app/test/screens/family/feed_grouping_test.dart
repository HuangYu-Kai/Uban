// 動態時光牆分組（FeedGrouping）與最新警示滑掉紀錄合併（FamilyAlertDismissalApi.reconcile）。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/family/home/models/feed_grouping.dart';
import 'package:flutter_application_1/services/api/family_alert_dismissal_api.dart';

Map<String, dynamic> _item(String date, int hour, String eventType, {String badge = 'LOG'}) => {
      'date': date,
      'sortTs': DateTime.parse('${date}T${hour.toString().padLeft(2, '0')}:00:00'),
      'eventType': eventType,
      'badge': badge,
    };

void main() {
  group('FeedGrouping', () {
    test('先分天（新到舊），不同天不會混在同一組', () {
      final days = FeedGrouping.group([
        _item('2026-10-06', 16, 'medication'),
        _item('2026-10-07', 9, 'medication'),
        _item('2026-10-07', 10, 'medication'),
      ]);
      expect(days.map((d) => d.date), ['2026-10-07', '2026-10-06']);
      expect(days.first.groups.single.items.length, 2);
      expect(days.last.groups.single.items.length, 1);
    });

    test('依 event_type 分組，說明只講筆數', () {
      final days = FeedGrouping.group([
        _item('2026-10-07', 9, 'medication'),
        _item('2026-10-07', 11, 'chat'),
        _item('2026-10-07', 8, 'medication'),
        _item('2026-10-07', 7, 'news_view'),
      ]);
      final groups = days.single.groups;
      expect(groups.map((g) => g.kind), [FeedKind.chat, FeedKind.checkin, FeedKind.news],
          reason: '組的順序依各組最新一筆');
      expect(groups[1].tagline, '完成 2 項打卡');
      expect(groups[0].tagline, '和小嘎聊了 1 次');
      expect(groups[2].tagline, '看了 1 則新聞');
    });

    test('伸展、散步之類的打卡一律算打卡，不會被當成 AI 對話或運動', () {
      expect(FeedGrouping.kindOf('medication', 'WALK'), FeedKind.checkin);
    });

    test('沒有 event_type 才看 badge；未知類型歸其他', () {
      expect(FeedGrouping.kindOf('', 'AI CHAT'), FeedKind.chat);
      expect(FeedGrouping.kindOf('location', 'LOG'), FeedKind.other);
    });
  });

  group('FamilyAlertDismissalApi.reconcile', () {
    test('後端有本機沒有 → 補進本機；本機有後端沒有 → 補送後端', () {
      final r = FamilyAlertDismissalApi.reconcile(
          ['alert:1', 'log:2'], ['log:2', 'alert:3']);
      expect(r.toAddLocally, {'alert:3'});
      expect(r.toUpload, ['alert:1']);
    });

    test('不穩定的鍵不上傳', () {
      final r = FamilyAlertDismissalApi.reconcile(
          ['live:fall:x:1', 'log-fallback:1:2'], []);
      expect(r.toUpload, isEmpty);
    });

    test('補送上限', () {
      final r = FamilyAlertDismissalApi.reconcile(
          [for (var i = 0; i < 80; i++) 'log:$i'], [], maxUpload: 50);
      expect(r.toUpload.length, 50);
    });
  });
}
