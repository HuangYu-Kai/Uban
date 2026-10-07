/// 動態時光牆的分組與說明文字（純函式，方便單元測試）。
///
/// ★ 2026-10-07：原本用內容關鍵字把紀錄猜進「健康運動」「溫情陪伴」等主題，
/// 說明小字則是寫死的評語（「AI 對話 N 次，互動狀況良好」的 N 只是卡片放了幾筆，
/// 實際那筆是伸展打卡；每筆打卡原文都含「用藥」，於是全部被算成用藥）。
/// 而且「全部」篩選下不同天的紀錄混在同一張卡。
/// 現在改成：先依台灣日期分天，再依後端 `event_type` 分卡，說明只講實際筆數。
library;

enum FeedKind { checkin, chat, news, media, mood, family, other }

class FeedGroup {
  final FeedKind kind;
  final List<Map<String, dynamic>> items;
  const FeedGroup(this.kind, this.items);

  String get title => FeedGrouping.title(kind);
  String get tagline => FeedGrouping.tagline(kind, items.length);
}

class FeedDay {
  /// `yyyy-MM-dd`（台灣日期）。
  final String date;
  final List<FeedGroup> groups;
  const FeedDay(this.date, this.groups);
}

class FeedGrouping {
  FeedGrouping._();

  /// 依後端 `event_type` 歸類；舊紀錄沒有 event_type 時才看前端算好的 badge。
  static FeedKind kindOf(String eventType, String badge) {
    switch (eventType) {
      case 'medication':
        return FeedKind.checkin;
      case 'chat':
      case 'ai_chat':
      case 'voice_dialogue':
      case 'voice':
        return FeedKind.chat;
      case 'news_view':
      case 'news_query':
        return FeedKind.news;
      case 'youtube_query':
      case 'media':
        return FeedKind.media;
      case 'mood':
        return FeedKind.mood;
      case 'interaction':
      case 'call_request':
        return FeedKind.family;
    }
    if (eventType.isEmpty) {
      switch (badge) {
        case 'MEDICINE':
        case 'WALK':
          return FeedKind.checkin;
        case 'AI CHAT':
          return FeedKind.chat;
        case 'NEWS':
          return FeedKind.news;
        case 'MEDIA':
          return FeedKind.media;
      }
    }
    return FeedKind.other;
  }

  static String title(FeedKind k) {
    switch (k) {
      case FeedKind.checkin:
        return '打卡紀錄';
      case FeedKind.chat:
        return '和小嘎聊天';
      case FeedKind.news:
        return '看新聞';
      case FeedKind.media:
        return '音樂影音';
      case FeedKind.mood:
        return '心情紀錄';
      case FeedKind.family:
        return '家人互動';
      case FeedKind.other:
        return '其他紀錄';
    }
  }

  /// 只講實際筆數，不加評語。
  static String tagline(FeedKind k, int n) {
    switch (k) {
      case FeedKind.checkin:
        return '完成 $n 項打卡';
      case FeedKind.chat:
        return '和小嘎聊了 $n 次';
      case FeedKind.news:
        return '看了 $n 則新聞';
      case FeedKind.media:
        return '點播了 $n 次音樂或影片';
      case FeedKind.mood:
        return '$n 筆心情紀錄';
      case FeedKind.family:
        return '$n 次家人互動';
      case FeedKind.other:
        return '$n 筆紀錄';
    }
  }

  /// 依日期（新到舊）分天，每天再依 [FeedKind] 分組；組的順序依該組最新一筆的時間（新到舊）。
  /// [items] 需帶 `date`（yyyy-MM-dd）、`sortTs`（DateTime?）、`eventType`、`badge`。
  static List<FeedDay> group(List<Map<String, dynamic>> items) {
    final byDate = <String, List<Map<String, dynamic>>>{};
    for (final i in items) {
      byDate.putIfAbsent(i['date']?.toString() ?? '', () => []).add(i);
    }
    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
    final days = <FeedDay>[];
    for (final date in dates) {
      final dayItems = [...byDate[date]!]..sort(_newestFirst);
      final byKind = <FeedKind, List<Map<String, dynamic>>>{};
      for (final i in dayItems) {
        final k = kindOf(
            i['eventType']?.toString() ?? '', i['badge']?.toString() ?? '');
        byKind.putIfAbsent(k, () => []).add(i);
      }
      // dayItems 已新到舊排序，Map 依插入順序 → 組的順序就是各組最新一筆的先後。
      days.add(FeedDay(
          date, [for (final e in byKind.entries) FeedGroup(e.key, e.value)]));
    }
    return days;
  }

  static int _newestFirst(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ta = a['sortTs'] as DateTime?;
    final tb = b['sortTs'] as DateTime?;
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return tb.compareTo(ta);
  }
}
