import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/elder_tabs/greeting/greeting_quotes.dart';

/// 「換句好話」排列組合：組合數、字數上限、不連續重複、主題吉祥話。
void main() {
  int len(String s) => s.replaceAll(' ', '').length;

  test('每個欄位至少 15 個選項，且各時段純排列組合 >= 3000', () {
    expect(GreetingQuoteGenerator.blessings.length, greaterThanOrEqualTo(15));
    expect(GreetingQuoteGenerator.closings.length, greaterThanOrEqualTo(15));
    for (final band in GreetingTimeBand.values) {
      expect(GreetingQuoteGenerator.greetings[band]!.length,
          greaterThanOrEqualTo(15));
      final all = GreetingQuoteGenerator.allPlainCombos(band).toSet();
      expect(all.length, GreetingQuoteGenerator.plainComboCount(band));
      expect(all.length, greaterThanOrEqualTo(3000));
    }
  });

  test('每個欄位的字數都在上限內（不含空格）', () {
    for (final list in GreetingQuoteGenerator.greetings.values) {
      for (final g in list) {
        expect(len(g), lessThanOrEqualTo(GreetingQuoteGenerator.maxGreetingChars),
            reason: g);
      }
    }
    for (final b in GreetingQuoteGenerator.blessings) {
      expect(len(b), lessThanOrEqualTo(GreetingQuoteGenerator.maxBlessingChars),
          reason: b);
    }
    for (final c in GreetingQuoteGenerator.closings) {
      expect(len(c), lessThanOrEqualTo(GreetingQuoteGenerator.maxClosingChars),
          reason: c);
    }
  });

  test('每個主題分類：主祝福 >=15 句且剛好 4 字、結尾 >=10 句且 <=8 字、無重複', () {
    final cats = GreetingQuoteGenerator.themedMains.keys.toSet();
    expect(GreetingQuoteGenerator.themedClosings.keys.toSet(), cats);
    expect(cats, containsAll([
      'lotus', 'koi', 'sunrise', 'bamboo', 'mountain', 'tea', 'flower', 'lake',
      'festival', 'solar_term', 'scenery',
    ]));
    for (final c in cats) {
      final mains = GreetingQuoteGenerator.themedMains[c]!;
      final ends = GreetingQuoteGenerator.themedClosings[c]!;
      expect(mains.length, greaterThanOrEqualTo(15), reason: c);
      expect(ends.length, greaterThanOrEqualTo(10), reason: c);
      expect(mains.toSet().length, mains.length, reason: '$c 主祝福重複');
      expect(ends.toSet().length, ends.length, reason: '$c 結尾重複');
      for (final m in mains) {
        expect(m.length, GreetingQuoteGenerator.maxBlessingChars, reason: '$c $m');
      }
      for (final e in ends) {
        expect(e.length, lessThanOrEqualTo(GreetingQuoteGenerator.maxClosingChars),
            reason: '$c $e');
      }
      for (final band in GreetingTimeBand.values) {
        expect(GreetingQuoteGenerator.themedComboCount(c, band),
            greaterThanOrEqualTo(2000), reason: c);
      }
    }
  });

  test('結尾語不含任何主祝福詞（避免同一句話重複）', () {
    final allMains = [
      ...GreetingQuoteGenerator.blessings,
      for (final l in GreetingQuoteGenerator.themedMains.values) ...l,
    ];
    final allEnds = [
      ...GreetingQuoteGenerator.closings,
      for (final l in GreetingQuoteGenerator.themedClosings.values) ...l,
    ];
    for (final c in allEnds) {
      for (final b in allMains) {
        expect(c.contains(b), isFalse, reason: '$c 含 $b');
      }
    }
  });

  test('產生的句子不超過 3 行、每行不超過上限，且沒有表情符號', () {
    final gen = GreetingQuoteGenerator(random: math.Random(1));
    final themes = [null, ...GreetingQuoteGenerator.themedMains.keys];
    final emoji = RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true);
    for (var i = 0; i < 3000; i++) {
      final q = gen.next(
        now: DateTime(2026, 10, 6, (i % 3) * 8 + 6),
        themeCategory: themes[i % themes.length],
      );
      final lines = q.main.split('\n');
      expect(lines.length, lessThanOrEqualTo(GreetingQuoteGenerator.maxLines));
      for (final l in lines) {
        expect(len(l), lessThanOrEqualTo(GreetingQuoteGenerator.maxThemeChars),
            reason: q.main);
      }
      expect(emoji.hasMatch(q.main + q.sub), isFalse, reason: q.main);
      expect(q.sub.trim(), isNotEmpty);
    }
  });

  test('連續兩次不會產生同一句（含固定亂數與換範本預設句）', () {
    final gen = GreetingQuoteGenerator(random: math.Random(7));
    String? prev;
    for (var i = 0; i < 2000; i++) {
      final q = gen.next(now: DateTime(2026, 10, 6, 8), themeCategory: 'koi');
      expect(q.main, isNot(prev));
      prev = q.main;
    }
    gen.markShown('早安\n身體健康\n祝您一天順利');
    for (var i = 0; i < 200; i++) {
      final q = gen.next(now: DateTime(2026, 10, 6, 8));
      expect(q.main, isNot('早安\n身體健康\n祝您一天順利'));
      gen.markShown('早安\n身體健康\n祝您一天順利');
    }
  });

  test('依時段換問候語', () {
    expect(GreetingQuoteGenerator.bandOf(DateTime(2026, 1, 1, 8)),
        GreetingTimeBand.morning);
    expect(GreetingQuoteGenerator.bandOf(DateTime(2026, 1, 1, 14)),
        GreetingTimeBand.afternoon);
    expect(GreetingQuoteGenerator.bandOf(DateTime(2026, 1, 1, 21)),
        GreetingTimeBand.evening);
    final gen = GreetingQuoteGenerator(random: math.Random(3));
    for (var i = 0; i < 300; i++) {
      final q = gen.next(now: DateTime(2026, 1, 1, 21), themeCategory: 'koi');
      expect(q.main.startsWith('晚安') || q.main.startsWith('夜晚'), isTrue);
    }
  });

  test('每個分類連按 200 次：每一句都含該分類的主題主祝福與主題結尾', () {
    for (final c in GreetingQuoteGenerator.themedMains.keys) {
      final gen = GreetingQuoteGenerator(random: math.Random(c.hashCode));
      final mains = GreetingQuoteGenerator.themedMains[c]!;
      final ends = GreetingQuoteGenerator.themedClosings[c]!;
      String? prev;
      for (var i = 0; i < 200; i++) {
        final q = gen.next(
            now: DateTime(2026, 10, 6, 8 + (i % 3) * 6), themeCategory: c);
        final lines = q.main.split('\n');
        expect(lines.length, 3, reason: c);
        expect(mains.contains(lines[1]), isTrue, reason: '$c ${q.main}');
        expect(ends.contains(lines[2]), isTrue, reason: '$c ${q.main}');
        expect(q.main, isNot(prev));
        prev = q.main;
      }
    }
  });

  test('時令節氣：結尾有時帶入節氣名稱，主祝福仍取自主題池', () {
    final gen = GreetingQuoteGenerator(random: math.Random(5));
    var withTerm = 0;
    for (var i = 0; i < 100; i++) {
      final q = gen.next(
          now: DateTime(2026, 10, 6, 8), themeCategory: 'solar_term', termName: '白露');
      final lines = q.main.split('\n');
      expect(GreetingQuoteGenerator.themedMains['solar_term']!.contains(lines[1]),
          isTrue);
      expect(len(lines[2]), lessThanOrEqualTo(GreetingQuoteGenerator.maxClosingChars));
      if (lines[2] == '白露時節保重') withTerm++;
    }
    expect(withTerm, greaterThan(20));
  });

  test('themedDefault：同 id 穩定、符合分類、字數上限內', () {
    final a = GreetingQuoteGenerator.themedDefault('bamboo', 'bamboo_01',
        now: DateTime(2026, 1, 1, 8));
    final b = GreetingQuoteGenerator.themedDefault('bamboo', 'bamboo_01',
        now: DateTime(2026, 1, 1, 8));
    expect(a, b);
    expect(a.split('\n').length, 3);
    expect(GreetingQuoteGenerator.themedMains['bamboo']!.any(a.contains), isTrue);
    expect(GreetingQuoteGenerator.themedClosings['bamboo']!.any(a.contains), isTrue);
  });
}
