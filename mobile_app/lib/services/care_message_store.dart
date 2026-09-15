import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 💚 主動關懷訊息的留存與通知（小嘎主動說的話）
///
/// 為什麼需要這個檔案：
/// 後端 `heartbeat_job` 每分鐘評估一次要不要主動關心長輩，訊息經由 Socket
/// `heartbeat-message` 送達。但前端原本的處理是**只有聲音、畫面什麼都不留**：
///
/// - `elder_home_screen.dart::_handleProactiveMessage` 只做 TTS 朗讀，
///   而且把 `type` 與 `emotion` 直接丟掉。
/// - 精美的 `HeartbeatOverlay`（毛玻璃、帶情緒）只掛在 `elder_screen.dart`
///   的通話／監控畫面——那是長輩最少待的地方。
///
/// 結果：對重聽的長輩、手機靜音、或人不在旁邊的情況，關懷訊息**完全遺失
/// 且無法回溯**，沒有任何地方查得到「今天小嘎跟我說過什麼」。
///
/// 本服務把每則關懷訊息留下來，並即時通知有興趣的畫面。
/// ⚠️ 刻意不放進 `Signaling` singleton：該類別已有多個回呼互相覆寫的歷史
/// 問題，護欄明文禁止在其中新增顯示狀態旗標。
class CareMessage {
  final String text;

  /// greeting / medication / family / weather / chat（沿用 HeartbeatOverlay 的分類）
  final String type;

  /// happy / caring / neutral
  final String emotion;

  final DateTime receivedAt;

  const CareMessage({
    required this.text,
    required this.type,
    required this.emotion,
    required this.receivedAt,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'type': type,
        'emotion': emotion,
        'receivedAt': receivedAt.toIso8601String(),
      };

  static CareMessage? fromJson(Map<String, dynamic> json) {
    final text = (json['text'] ?? '').toString();
    if (text.trim().isEmpty) return null;
    return CareMessage(
      text: text,
      type: (json['type'] ?? 'chat').toString(),
      emotion: (json['emotion'] ?? 'caring').toString(),
      receivedAt:
          DateTime.tryParse((json['receivedAt'] ?? '').toString()) ??
              DateTime.now(),
    );
  }
}

class CareMessageStore {
  CareMessageStore._internal();
  static final CareMessageStore instance = CareMessageStore._internal();

  /// 最多留存幾則。關懷訊息每分鐘可能產生一則，不設上限會無限膨脹；
  /// 長輩實際會回顧的也只有最近幾則。
  static const int _maxKept = 30;

  static const String _keyPrefix = 'care_messages_';

  /// 新訊息抵達時通知訂閱者（例如聊天分頁把它接成一則小嘎的訊息）。
  /// 用 ValueNotifier 而非回呼欄位，才不會像 Signaling 的單一欄位那樣
  /// 被後掛載的畫面覆寫掉——多個畫面可以同時監聽。
  final ValueNotifier<CareMessage?> latest = ValueNotifier<CareMessage?>(null);

  final List<CareMessage> _messages = [];
  int? _userId;

  List<CareMessage> get messages => List.unmodifiable(_messages);

  String _key(int userId) => '$_keyPrefix$userId';

  /// 載入某位長輩既有的關懷訊息。切換帳號時重新呼叫即可。
  Future<void> load(int userId) async {
    _userId = userId;
    _messages.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final m = CareMessage.fromJson(item);
          if (m != null) _messages.add(m);
        }
      }
    } catch (e) {
      // 留存失敗不該影響關懷訊息本身的顯示與朗讀，吞掉即可。
      debugPrint('⚠️ [CareMessageStore] 載入失敗: $e');
    }
  }

  /// 收到一則新的主動關懷訊息：留存 + 通知訂閱者。
  Future<void> add({
    required String text,
    String type = 'chat',
    String emotion = 'caring',
  }) async {
    if (text.trim().isEmpty) return;
    final msg = CareMessage(
      text: text.trim(),
      type: type,
      emotion: emotion,
      receivedAt: DateTime.now(),
    );

    _messages.insert(0, msg);
    if (_messages.length > _maxKept) {
      _messages.removeRange(_maxKept, _messages.length);
    }

    // 先通知畫面，再寫入磁碟——長輩看到的即時性優先於留存。
    latest.value = msg;

    final uid = _userId;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(uid),
        jsonEncode(_messages.map((m) => m.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('⚠️ [CareMessageStore] 寫入失敗: $e');
    }
  }
}
