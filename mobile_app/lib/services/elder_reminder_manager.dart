// lib/services/elder_reminder_manager.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show navigatorKey;
import 'api_service.dart';
import 'local_reminder_notification.dart';
import '../widgets/elder_reminder_dialog.dart';

/// ⏰ 長輩端全域排程守護服務（Singleton）
///
/// 核心職責：
/// 1. 快取子女端建立的排程清單，支援斷線/離線本地比對。
/// 2. 接收即時 Socket 信令（`remote-reminder` / `reminder-sync`）與 FCM 前景訊息。
/// 3. 前景 20 秒定時看門狗比對當前時間，到達時準時彈出 `ElderReminderDialog` 與語音播報。
/// 4. 去重機制避免同日同分重複彈窗。
class ElderReminderManager {
  static final ElderReminderManager _instance = ElderReminderManager._internal();
  static ElderReminderManager get instance => _instance;
  ElderReminderManager._internal();

  Timer? _watchdogTimer;
  List<Map<String, dynamic>> _reminders = [];
  final Set<String> _triggeredKeys = {};
  int? _userId;
  String _elderName = '長輩';
  bool _isStarted = false;
  bool _isDialogOpen = false;
  int _tickCount = 0;
  BuildContext? Function()? _contextGetter;

  /// 設定 UI 前景的 BuildContext 取得器，避免全域 navigatorKey 在切換或 isolate 遺失
  void setContextGetter(BuildContext? Function()? getter) {
    _contextGetter = getter;
  }

  /// 全域監聽回呼：供長輩「我的」Tab 清單即時刷新
  final List<VoidCallback> _listeners = [];
  void addListener(VoidCallback cb) => _listeners.add(cb);
  void removeListener(VoidCallback cb) => _listeners.remove(cb);
  void _notifyListeners() {
    for (final cb in List.of(_listeners)) {
      try {
        cb();
      } catch (_) {}
    }
  }

  /// 啟動長輩端排程管理器
  void start({required int userId, String userName = '長輩'}) {
    _userId = userId;
    _elderName = userName.isNotEmpty ? userName : '長輩';
    if (_isStarted) return;
    _isStarted = true;

    debugPrint('⏰ [ElderReminderManager] 啟動排程守護服務 (userId=$userId, name=$_elderName)');
    _loadCache();
    syncReminders();

    // 啟動 20 秒看門狗定時比對
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _checkSchedule();
    });
  }

  /// 停止排程管理器
  void stop() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _isStarted = false;
    _listeners.clear();
    debugPrint('⏰ [ElderReminderManager] 停止排程守護服務');
  }

  /// 從後端同步最新排程清單
  Future<void> syncReminders() async {
    if (_userId == null) return;
    try {
      final list = await ApiService.getElderReminders(_userId.toString());
      _reminders = List<Map<String, dynamic>>.from(list);
      await _saveCache();
      _notifyListeners();
      debugPrint('⏰ [ElderReminderManager] 成功同步 ${_reminders.length} 筆排程提醒');
    } catch (e) {
      debugPrint('⚠️ [ElderReminderManager] syncReminders 失敗（使用本地快取）: $e');
    }
  }

  /// 處理外部接收到的提醒（來自 Socket.IO remote-reminder、FCM 或點擊通知）
  void handleIncomingReminder(Map<String, dynamic> data, {bool force = false}) {
    try {
      final id = int.tryParse(data['id']?.toString() ?? '') ?? 0;
      final title = data['title']?.toString() ?? '提醒事項';
      final category = data['category']?.toString() ?? 'custom';
      final timeStr = data['time_str']?.toString() ??
          DateFormat('HH:mm').format(DateTime.now());
      final note = data['note']?.toString() ?? '';

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final dedupKey = '${id}_${today}_$timeStr';

      if (!force && _triggeredKeys.contains(dedupKey)) {
        debugPrint('⏰ [ElderReminderManager] 略過重複提醒: $dedupKey');
        return;
      }
      _triggeredKeys.add(dedupKey);

      debugPrint('⏰ [ElderReminderManager] 觸發排程提醒彈窗: $title ($timeStr)');
      _showDialog(
        reminderId: id,
        title: title,
        category: category,
        timeStr: timeStr,
        note: note,
      );
    } catch (e) {
      debugPrint('⚠️ [ElderReminderManager] handleIncomingReminder 失敗: $e');
    }
  }

  /// 本機 20 秒定時看門狗比對
  void _checkSchedule() {
    _tickCount++;
    // 每 6 次看門狗（6 * 20s = 120s / 2分鐘）自動從後端校驗最新排程
    if (_tickCount % 6 == 0) {
      syncReminders();
    }

    if (_reminders.isEmpty) return;
    final now = DateTime.now();
    final currentTimeStr = DateFormat('HH:mm').format(now);
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final weekdayMap = {1: '週一', 2: '週二', 3: '週三', 4: '週四', 5: '週五', 6: '週六', 7: '週日'};
    final currentWeekday = weekdayMap[now.weekday] ?? '';

    for (final r in _reminders) {
      final isActive = r['is_active'] == true || r['is_active'] == 1;
      if (!isActive) continue;

      final String reminderTime = r['time_str']?.toString().trim() ?? '';
      if (reminderTime.isEmpty || reminderTime != currentTimeStr) continue;

      final id = int.tryParse(r['id']?.toString() ?? '') ?? 0;
      final dedupKey = '${id}_${todayStr}_$currentTimeStr';
      if (_triggeredKeys.contains(dedupKey)) continue;

      // 檢查重複模式
      final repeatDays = r['repeat_days']?.toString() ?? '每天';
      final startDate = r['start_date']?.toString();
      bool shouldTrigger = false;

      if (repeatDays == '每天' || repeatDays == '常規') {
        shouldTrigger = true;
      } else if (repeatDays == '單次' || repeatDays == '單次提醒') {
        if (startDate == null || startDate.isEmpty || startDate == todayStr) {
          shouldTrigger = true;
        }
      } else if (repeatDays == '週一至週五') {
        if (now.weekday <= 5) shouldTrigger = true;
      } else if (repeatDays.contains(currentWeekday)) {
        shouldTrigger = true;
      } else {
        shouldTrigger = true;
      }

      if (shouldTrigger) {
        _triggeredKeys.add(dedupKey);
        final title = r['title']?.toString() ?? '生活提醒';
        final category = r['category']?.toString() ?? 'custom';
        final note = r['note']?.toString() ?? '';

        debugPrint('⏰ [ElderReminderManager] 本地看門狗命中排程: $title ($reminderTime)');
        _showDialog(
          reminderId: id,
          title: title,
          category: category,
          timeStr: reminderTime,
          note: note,
        );

        // 同步發送本機系統通知備援
        LocalReminderNotification.showReminderNotification(
          id: id,
          title: title,
          timeStr: reminderTime,
          note: note,
          category: category,
        );
      }
    }
  }

  /// 彈出長輩專屬醒目對話框
  void _showDialog({
    required int reminderId,
    required String title,
    required String category,
    required String timeStr,
    required String note,
    int retryCount = 0,
  }) {
    if (_isDialogOpen) {
      debugPrint('⏰ [ElderReminderManager] 目前已有彈窗開啟中，延遲顯示');
      return;
    }

    BuildContext? context = _contextGetter?.call();
    if (context == null || !context.mounted) {
      context = navigatorKey.currentContext;
    }

    if (context == null || !context.mounted) {
      debugPrint('⚠️ [ElderReminderManager] 暫時無法取得有效 context (retry=$retryCount)');
      if (retryCount < 5) {
        Future.delayed(const Duration(seconds: 1), () {
          _showDialog(
            reminderId: reminderId,
            title: title,
            category: category,
            timeStr: timeStr,
            note: note,
            retryCount: retryCount + 1,
          );
        });
      }
      return;
    }

    _isDialogOpen = true;
    ElderReminderDialog.show(
      context,
      reminderId: reminderId,
      title: title,
      timeStr: timeStr,
      category: category,
      note: note,
      elderName: _elderName,
      onCompleted: () {
        syncReminders();
      },
    ).then((_) {
      _isDialogOpen = false;
    });
  }

  // ── 本地快取支援 ──
  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_elder_reminders', jsonEncode(_reminders));
    } catch (_) {}
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('cached_elder_reminders');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _reminders = List<Map<String, dynamic>>.from(decoded);
          debugPrint('⏰ [ElderReminderManager] 從快取讀取 ${_reminders.length} 筆排程');
        }
      }
    } catch (_) {}
  }
}
