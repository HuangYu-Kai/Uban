import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../globals.dart';
import 'api/api_client.dart';
import 'api/checkin_cheer_api.dart';

/// 🎉 家屬打卡加油（長輩端）。
class CheckinCheer {
  final int cheerId;
  final String familyName;
  final String? text;
  final String? audioUrl; // 相對路徑（/uploads/cheers/x.m4a）
  final String? reminderTitle;

  /// ★ 2026-10-07 每日一問：有值代表這則加油是「對長輩每日一問回答的回覆」。
  final String? questionText;

  const CheckinCheer({
    required this.cheerId,
    required this.familyName,
    this.text,
    this.audioUrl,
    this.reminderTitle,
    this.questionText,
  });

  bool get hasAudio => audioUrl != null && audioUrl!.isNotEmpty;
  bool get hasText => text != null && text!.isNotEmpty;

  static String? _nz(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  /// 格式不合（沒有 id、或文字與語音皆空）回傳 null。
  static CheckinCheer? tryParse(dynamic data) {
    if (data is! Map) return null;
    final id =
        int.tryParse((data['cheerId'] ?? data['cheer_id'] ?? '').toString());
    if (id == null) return null;
    final c = CheckinCheer(
      cheerId: id,
      familyName: _nz(data['familyName'] ?? data['family_name']) ?? '家人',
      text: _nz(data['text']),
      audioUrl: _nz(data['audioUrl'] ?? data['audio_url']),
      reminderTitle: _nz(data['reminderTitle'] ?? data['reminder_title']),
      questionText: _nz(data['questionText'] ?? data['question_text']),
    );
    return (c.hasText || c.hasAudio) ? c : null;
  }

  /// 留存／顯示用的關懷訊息文字。
  String get displayText {
    // ★ 每日一問的回覆：「璿OwO 回覆了您的回答：好棒！（「您小時候最喜歡吃的…」）」。
    final q = questionText;
    if (q != null) {
      final short = q.length > 12 ? '${q.substring(0, 12)}…' : q;
      final reply = hasText ? '回覆了您的回答：$text' : '回覆了您的回答，傳了一段語音給您';
      return '$familyName $reply（「$short」）';
    }
    final base = hasText ? '$familyName：$text' : '$familyName 傳了一段語音給您';
    final ctx = reminderTitle == null ? '' : '（為您完成「$reminderTitle」加油）';
    return '$base$ctx';
  }

  /// 小嘎要唸的內容（只在「純文字、無語音」時使用）。
  String get speakText => displayText;
}

/// 純邏輯佇列：依序處理、同一個 cheerId 只處理一次（Socket 推播與 unread 撈取可能重複）。
class CheerQueue {
  final List<CheckinCheer> _pending = [];
  final Set<int> _seen = {};

  int get length => _pending.length;
  bool get isEmpty => _pending.isEmpty;

  /// 回傳是否真的加入（重複則 false）。
  bool enqueue(CheckinCheer c) {
    if (!_seen.add(c.cheerId)) return false;
    _pending.add(c);
    return true;
  }

  CheckinCheer? peek() => _pending.isEmpty ? null : _pending.first;
  CheckinCheer? removeFirst() => _pending.isEmpty ? null : _pending.removeAt(0);
}

/// 長輩端加油的取得、佇列與播放。畫面相關動作（留存、對話框、TTS）由呼叫端注入。
class CheckinCheerService {
  CheckinCheerService({
    required this.resolveElderId,
    required this.canPresent,
    required this.isInCall,
    required this.present,
    required this.speak,
  });

  /// ★ 2026-10-07 交接 C/D（長輩端）：後端以 4 碼 elder_id 比對，
  /// 不可傳 userId；由呼叫端解析（解析不到回 null → 本次略過，下次再試）。
  final Future<String?> Function() resolveElderId;

  /// 開始處理前檢查：首頁是否在最上層（非 ElderScreen 等）。
  final bool Function() canPresent;
  final bool Function() isInCall;

  /// 留存並顯示（CareMessageStore + HeartbeatOverlay）。不含任何語音。
  final Future<void> Function(CheckinCheer c) present;

  /// 小嘎朗讀（沿用首頁既有 TTS）。
  final Future<void> Function(String text) speak;

  final CheerQueue _queue = CheerQueue();
  bool _draining = false;
  AudioPlayer? _player;

  /// 新推播進來（Socket）。
  void onPush(dynamic data) {
    final c = CheckinCheer.tryParse(data);
    if (c != null && _queue.enqueue(c)) unawaited(drain());
  }

  /// 啟動與回前景：撈未讀。網路錯誤靜默，下次回前景再試。
  Future<void> fetchUnread() async {
    final elderId = await resolveElderId();
    if (elderId == null || elderId.isEmpty) return;
    final raw = await CheckinCheerApi.listUnreadForElder(elderId);
    for (final m in raw) {
      final c = CheckinCheer.tryParse(m);
      if (c != null) _queue.enqueue(c);
    }
    await drain();
  }

  Future<void> drain() async {
    if (_draining || _queue.isEmpty) return;
    // 通話中或長輩在通話／監控畫面：只排隊不播放，待回到首頁再 drain。
    if (isInCall() || !canPresent()) return;
    _draining = true;
    try {
      while (!_queue.isEmpty) {
        if (isInCall()) break;
        final c = _queue.peek()!;
        try {
          await present(c);
          if (c.hasAudio) {
            await _playAudio(c.audioUrl!);
          } else if (c.hasText) {
            await speak(c.speakText);
          }
        } catch (e) {
          debugPrint('⚠️ [CheckinCheer] 呈現失敗（不顯示給長輩）: $e');
        }
        _queue.removeFirst();
        unawaited(() async {
          final id = await resolveElderId();
          if (id != null && id.isNotEmpty) {
            await CheckinCheerApi.markRead(c.cheerId, id);
          }
        }());
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _playAudio(String relativeUrl) async {
    final url = relativeUrl.startsWith('http')
        ? relativeUrl
        : '${ApiClient.serverRootUrl}$relativeUrl';
    // 只在「是我設的」才還原，避免蓋掉其他媒體（同 elder_chat_screen）。
    final paused = !isMediaPlayingNotifier.value;
    if (paused) isMediaPlayingNotifier.value = true;
    final player = AudioPlayer();
    _player = player;
    try {
      final done = Completer<void>();
      final sub = player.onPlayerComplete.listen((_) {
        if (!done.isCompleted) done.complete();
      });
      try {
        await player.play(UrlSource(url));
        await done.future
            .timeout(const Duration(minutes: 2), onTimeout: () {});
      } finally {
        await sub.cancel();
      }
    } catch (e) {
      debugPrint('⚠️ [CheckinCheer] 語音播放失敗: $e');
    } finally {
      _player = null;
      try {
        await player.dispose();
      } catch (_) {}
      if (paused) isMediaPlayingNotifier.value = false;
    }
  }

  Future<void> dispose() async {
    final p = _player;
    _player = null;
    try {
      await p?.stop();
    } catch (_) {}
  }
}
