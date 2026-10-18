// ★ 2026-10-15 對話紀錄：AI 照護秘書本機對話紀錄的序列化／還原純函式測試。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/screens/family/family_copilot_history.dart';
import 'package:flutter_application_1/screens/family/family_question_draft.dart';
import 'package:flutter_application_1/screens/family/family_share_draft.dart';

void main() {
  const elderName = '王媽媽';

  Map<String, dynamic> serialize(Map<String, dynamic> m) =>
      serializeCopilotMessage(m, elderName: elderName)!;

  group('copilotHistoryKey', () {
    test('依家屬帳號與長輩分開', () {
      expect(copilotHistoryKey(9, 'e7'), 'copilot_history_v1_9_e7');
      expect(copilotHistoryKey(9, 'e7'), isNot(copilotHistoryKey(9, 'e8')));
      expect(copilotHistoryKey(9, 'e7'), isNot(copilotHistoryKey(10, 'e7')));
    });
  });

  group('serializeCopilotMessage', () {
    test('歡迎詞（ephemeral）不存', () {
      expect(
        serializeCopilotMessage({'isUser': false, 'text': '您好', 'ephemeral': true},
            elderName: elderName),
        isNull,
      );
    });

    test('一般訊息：保留 isUser／text／ts；沒有 ts 時補現在', () {
      final a = serialize({'isUser': true, 'text': '哈囉', 'ts': '2026-10-15T08:00:00.000'});
      expect(a['isUser'], true);
      expect(a['text'], '哈囉');
      expect(a['ts'], '2026-10-15T08:00:00.000');
      final b = serialize({'isUser': false, 'text': '嗨'});
      expect(DateTime.tryParse(b['ts'] as String), isNotNull);
    });

    test('本機 File 不存，只存上傳後網址', () {
      final s = serialize({
        'isUser': true,
        'text': '（照片）',
        'localImage': File('C:/tmp/secret.jpg'),
        'imageUrl': 'http://x/a.jpg',
      });
      expect(s.containsKey('localImage'), isFalse);
      expect(s['imageUrl'], 'http://x/a.jpg');
      expect(jsonEncode(s), isNot(contains('secret.jpg')));
    });

    test('statusSummary 與 relayAudioUrl 原樣保留', () {
      final s = serialize({
        'isUser': false,
        'text': '近況',
        'statusSummary': {'mood_status': '開心', 'recent_topics': ['散步']},
        'relayAudioUrl': 'http://x/a.mp3',
      });
      expect((s['statusSummary'] as Map)['mood_status'], '開心');
      expect(s['relayAudioUrl'], 'http://x/a.mp3');
    });

    test('已同步的提醒草稿：存草稿與 isApplied', () {
      final s = serialize({
        'isUser': false,
        'text': '好',
        'scheduleDrafts': [
          {'time_str': '08:00', 'repeat_days': '每天', 'title': '吃藥'}
        ],
        'isApplied': true,
      });
      expect(s['isApplied'], true);
      expect((s['scheduleDrafts'] as List).length, 1);
      expect(s.containsKey('archivedLines'), isFalse);
    });

    test('未確認的提醒草稿：不存草稿，改成文字（缺欄位用預設）', () {
      final s = serialize({
        'isUser': false,
        'text': '好',
        'scheduleDrafts': [
          {'time_str': '08:00', 'repeat_days': '每天', 'title': '吃降血壓藥'},
          {'time_str': '20:00'},
        ],
      });
      expect(s.containsKey('scheduleDrafts'), isFalse);
      expect(s.containsKey('isApplied'), isFalse);
      expect(s['archivedLines'], [
        '未確認的提醒草稿：08:00（每天）吃降血壓藥',
        '未確認的提醒草稿：20:00（每天）排程',
      ]);
    });

    test('分享卡：已送出 -> 結果文字＋照片網址', () {
      final s = serialize({
        'isUser': false,
        'text': '幫您擬了草稿',
        'sharePhase': ShareCardPhase.sent,
        'shareController': TextEditingController(text: '孫子考 100 分'),
        'shareImageUrl': 'http://x/p.jpg',
      });
      expect(s['archivedLines'], ['✓ 已分享到時光牆：孫子考 100 分']);
      expect(s['archivedImageUrl'], 'http://x/p.jpg');
    });

    test('分享卡：已送出、只有照片 -> （照片）', () {
      final s = serialize({
        'isUser': false,
        'text': 'x',
        'sharePhase': ShareCardPhase.sent,
        'shareController': TextEditingController(text: '  '),
        'shareImageUrl': 'http://x/p.jpg',
      });
      expect(s['archivedLines'], ['✓ 已分享到時光牆：（照片）']);
    });

    test('分享卡：草稿／送出中／已取消 -> 未送出的分享草稿，不存照片', () {
      for (final phase in [
        ShareCardPhase.draft,
        ShareCardPhase.sending,
        ShareCardPhase.cancelled
      ]) {
        final s = serialize({
          'isUser': false,
          'text': 'x',
          'sharePhase': phase,
          'shareController': TextEditingController(text: '今天去公園'),
          'shareImageUrl': 'http://x/p.jpg',
        });
        expect(s['archivedLines'], ['未送出的分享草稿：今天去公園'], reason: '$phase');
        expect(s.containsKey('archivedImageUrl'), isFalse, reason: '$phase');
      }
    });

    test('出題卡：已送出 vs 未送出', () {
      final sent = serialize({
        'isUser': false,
        'text': 'x',
        'questionPhase': QuestionCardPhase.sent,
        'questionController': TextEditingController(text: '小時候住哪裡'),
      });
      expect(sent['archivedLines'], ['✓ 已出題給$elderName：小時候住哪裡']);
      for (final phase in [
        QuestionCardPhase.draft,
        QuestionCardPhase.sending,
        QuestionCardPhase.cancelled
      ]) {
        final s = serialize({
          'isUser': false,
          'text': 'x',
          'questionPhase': phase,
          'questionController': TextEditingController(text: '小時候住哪裡'),
        });
        expect(s['archivedLines'], ['未送出的出題草稿：小時候住哪裡'], reason: '$phase');
      }
    });

    test('已還原的訊息再存一次：封存文字與照片不遺失', () {
      final restored = deserializeCopilotMessage({
        'isUser': false,
        'text': 'x',
        'archivedLines': ['✓ 已分享到時光牆：A'],
        'archivedImageUrl': 'http://x/p.jpg',
      });
      final s = serialize(restored);
      expect(s['archivedLines'], ['✓ 已分享到時光牆：A']);
      expect(s['archivedImageUrl'], 'http://x/p.jpg');
    });
  });

  group('deserializeCopilotMessage', () {
    test('標記 restored、帶回欄位；未套用草稿不還原', () {
      final m = deserializeCopilotMessage({
        'isUser': false,
        'text': '你好',
        'ts': '2026-10-15T08:00:00.000',
        'statusSummary': {'mood_status': '開心'},
        'scheduleDrafts': [
          {'time_str': '08:00'}
        ],
        'isApplied': false,
        'archivedLines': ['a', 'b'],
      });
      expect(m['restored'], true);
      expect(m['isUser'], false);
      expect(m['text'], '你好');
      expect(m['ts'], '2026-10-15T08:00:00.000');
      expect(m['scheduleDrafts'], isNull);
      expect(m['isApplied'], false);
      expect(m['archivedLines'], ['a', 'b']);
      expect((m['statusSummary'] as Map)['mood_status'], '開心');
    });

    test('已套用草稿會還原', () {
      final m = deserializeCopilotMessage({
        'isUser': false,
        'text': 'x',
        'scheduleDrafts': [
          {'time_str': '08:00', 'title': '吃藥'}
        ],
        'isApplied': true,
      });
      expect(m['isApplied'], true);
      expect((m['scheduleDrafts'] as List).first['title'], '吃藥');
    });

    test('欄位缺漏或型別錯誤不丟例外', () {
      final bad = <Map<String, dynamic>>[
        {},
        {'isUser': 'yes', 'text': 123, 'ts': 5},
        {'text': null, 'statusSummary': 'oops', 'scheduleDrafts': 'x', 'isApplied': true},
        {'archivedLines': [1, null, 'ok'], 'archivedImageUrl': 3, 'imageUrl': []},
        {
          'statusSummary': {'recent_topics': 'abc', 'next_appointment': 5},
          'scheduleDrafts': [1, 'a', null],
          'isApplied': true,
        },
      ];
      for (final j in bad) {
        late Map<String, dynamic> m;
        expect(() => m = deserializeCopilotMessage(j), returnsNormally);
        expect(m['restored'], true);
        expect(m['text'], isA<String>());
        expect(m['archivedLines'], isA<List<String>>());
        expect(m['isUser'], isA<bool>());
      }
      final m = deserializeCopilotMessage(bad[3]);
      expect(m['archivedLines'], ['ok']);
      expect(m['archivedImageUrl'], isNull);
      final m2 = deserializeCopilotMessage(bad[4]);
      expect(m2['scheduleDrafts'], isNull);
      expect(m2['isApplied'], false);
      expect((m2['statusSummary'] as Map).containsKey('recent_topics'), isFalse);
      expect((m2['statusSummary'] as Map).containsKey('next_appointment'), isFalse);
    });
  });

  group('decodeCopilotHistory', () {
    test('null、空字串、亂碼、非陣列 -> []', () {
      expect(decodeCopilotHistory(null), isEmpty);
      expect(decodeCopilotHistory(''), isEmpty);
      expect(decodeCopilotHistory('not json{'), isEmpty);
      expect(decodeCopilotHistory('{"a":1}'), isEmpty);
      expect(decodeCopilotHistory('"str"'), isEmpty);
    });

    test('陣列內非物件的項目略過', () {
      final r = decodeCopilotHistory('[1, "x", null, {"text":"a"}]');
      expect(r.length, 1);
      expect(r.first['text'], 'a');
    });
  });

  group('encodeCopilotHistory', () {
    test('丟掉歡迎詞，其餘來回一致', () {
      final raw = encodeCopilotHistory([
        {'isUser': false, 'text': '您好', 'ephemeral': true},
        {'isUser': true, 'text': '問題', 'ts': '2026-10-15T08:00:00.000'},
        {'isUser': false, 'text': '答案', 'ts': '2026-10-15T08:00:05.000'},
      ], elderName: elderName);
      final back = decodeCopilotHistory(raw).map(deserializeCopilotMessage).toList();
      expect(back.map((m) => m['text']), ['問題', '答案']);
      expect(back.map((m) => m['isUser']), [true, false]);
    });

    test('只留最後 $kCopilotHistoryLimit 則', () {
      final msgs = [
        for (var i = 0; i < kCopilotHistoryLimit + 30; i++)
          {'isUser': i.isEven, 'text': 'm$i', 'ts': '2026-10-15T08:00:00.000'},
      ];
      final back = decodeCopilotHistory(encodeCopilotHistory(msgs, elderName: elderName));
      expect(back.length, kCopilotHistoryLimit);
      expect(back.first['text'], 'm30');
      expect(back.last['text'], 'm${kCopilotHistoryLimit + 29}');
    });

    test('歡迎詞不佔用 100 則額度', () {
      final msgs = [
        {'isUser': false, 'text': 'welcome', 'ephemeral': true},
        for (var i = 0; i < kCopilotHistoryLimit; i++) {'isUser': true, 'text': 'm$i'},
      ];
      final back = decodeCopilotHistory(encodeCopilotHistory(msgs, elderName: elderName));
      expect(back.length, kCopilotHistoryLimit);
      expect(back.first['text'], 'm0');
    });

    test('只有歡迎詞 -> "[]"', () {
      expect(
        encodeCopilotHistory([
          {'isUser': false, 'text': 'welcome', 'ephemeral': true}
        ], elderName: elderName),
        '[]',
      );
    });
  });
}
