// lib/widgets/elder_reminder_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../utils/display_text.dart';
import '../screens/elder_tabs/streak/streak_service.dart';
import 'elder_overlay_button.dart';
import 'ui/pressable_scale.dart';
import 'ui/uban_dialog.dart';
import 'ui/uban_text.dart';

/// ⏰ 長輩端專用：高對比、大字體、暖心繪本風的排程提醒彈窗
class ElderReminderDialog extends StatefulWidget {
  final int reminderId;
  final String title;
  final String timeStr;
  final String category;
  final String note;
  final String elderName;
  final VoidCallback? onCompleted;
  // ★ 第四十九輪（item 1）：是否由本彈窗自己朗讀提醒內容。
  //   `ElderReminderManager` 現在有兩條會一起觸發本彈窗的路徑——
  //   本機看門狗（`_checkSchedule`）額外會同步發一則 `LocalReminderNotification`
  //   系統通知，該通知現在也會自己朗讀一次；若彈窗這裡不受控制地永遠朗讀，
  //   同一次提醒就會出現兩段語音同時播放、互相蓋過。因此改由呼叫端決定：
  //   看門狗路徑傳 `speak: false`（改由通知端朗讀，理由是通知路徑同時涵蓋
  //   「畫面顯示不出來（App 在背景／被殺死收到 FCM）」的情境，見
  //   `local_reminder_notification.dart`）；其餘沒有搭配系統通知的路徑
  //   （Socket／FCM 前景推播、點擊通知冷啟動）維持預設 `true`，本彈窗仍是
  //   唯一的朗讀來源。
  final bool speak;

  const ElderReminderDialog({
    super.key,
    required this.reminderId,
    required this.title,
    required this.timeStr,
    this.category = 'custom',
    this.note = '',
    this.elderName = '長輩',
    this.onCompleted,
    this.speak = true,
  });

  static Future<void> show(
    BuildContext context, {
    required int reminderId,
    required String title,
    required String timeStr,
    String category = 'custom',
    String note = '',
    String elderName = '長輩',
    VoidCallback? onCompleted,
    bool speak = true,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => ElderReminderDialog(
        reminderId: reminderId,
        title: title,
        timeStr: timeStr,
        category: category,
        note: note,
        elderName: elderName,
        onCompleted: onCompleted,
        speak: speak,
      ),
    );
  }

  @override
  State<ElderReminderDialog> createState() => _ElderReminderDialogState();
}

class _ElderReminderDialogState extends State<ElderReminderDialog> {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.speak) {
      _playVoicePrompt();
    }
  }

  Future<void> _playVoicePrompt() async {
    try {
      await _flutterTts.setLanguage("zh-TW");
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.5);
      final speakContent = "${widget.elderName}您好，現在是${widget.timeStr}，提醒您「${stripEmoji(widget.title)}」喔！${widget.note.isNotEmpty ? widget.note : ''}";
      await _flutterTts.speak(speakContent);
    } catch (e) {
      debugPrint("⚠️ TTS speak error: $e");
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  /// 類別 → 徽章文字與圖示（徽章配色一律用設計稿 `.badge` 的暖色）。
  _CategoryConfig _getConfig(String category) {
    switch (category) {
      case 'medication':
        return const _CategoryConfig(
            label: '用藥提醒', icon: Icons.medication_rounded);
      case 'water':
        return const _CategoryConfig(
            label: '喝水提醒', icon: Icons.water_drop_rounded);
      case 'exercise':
        return const _CategoryConfig(
            label: '活力運動', icon: Icons.directions_walk_rounded);
      case 'hospital':
        return const _CategoryConfig(
            label: '門診回診', icon: Icons.local_hospital_rounded);
      default:
        return const _CategoryConfig(
            label: '生活提醒', icon: Icons.alarm_rounded);
    }
  }

  /// 把完成狀態寫進本機當日清單，與「我的」分頁的 _toggleTaskCompletion
  /// 使用同一個鍵（`completed_tasks_<yyyy-MM-dd>`），確保三個入口看到同一個狀態。
  Future<void> _markCompletedLocally(int reminderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final key = 'completed_tasks_$today';
      final done = prefs.getStringList(key) ?? <String>[];
      final id = reminderId.toString();
      if (!done.contains(id)) {
        done.add(id);
        await prefs.setStringList(key, done);
      }
    } catch (e) {
      debugPrint('⚠️ [ElderReminderDialog] 寫入本機完成清單失敗: $e');
    }
  }

  /// ★ 第四十九輪：修「不管後端成不成功，一律顯示打卡成功」的誠實性問題。
  ///
  /// 根因（team-lead 複驗過）：`ApiService.completeElderReminder` 一路委派到
  /// `ReminderApi.completeElderReminder`，後者自己把逾時／連線失敗／後端錯誤
  /// 全部吞成 `return false`、**從不對外拋例外**。原本包在外面的 `try/catch`
  /// 因此是死碼，`bool` 回傳值又沒被讀，導致「後端記錄成功」與「後端記錄失敗」
  /// 在畫面上長得一模一樣，長輩以為藥已記錄、家屬端資料庫其實沒有這筆。
  /// 合併自上游的 `_markCompletedLocally()` 方向正確（三個入口該看到同一狀態），
  /// 但原本無條件呼叫，等於把「未經驗證的完成」也同步寫進本機清單，讓「我的」
  /// 分頁與首頁卡片一起說謊——現在改成只有 API 真的回 `true` 才寫。
  Future<void> _handleComplete() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    HapticFeedback.heavyImpact();

    bool success;
    if (widget.reminderId > 0) {
      try {
        success = await ApiService.completeElderReminder(widget.reminderId);
      } catch (e) {
        // completeElderReminder 目前不會走到這裡（它自己吞例外回傳 false），
        // 保留這層只是防禦未來改版又開始對外拋例外，不能取代讀 bool。
        debugPrint('⚠️ [ElderReminderDialog] completeElderReminder 例外: $e');
        success = false;
      }
      if (success) {
        // 只有後端真的記錄成功才寫本機當日完成清單——這份清單同時餵給
        // 「我的」分頁與首頁卡片，寫錯了三個畫面會一起說謊。
        await _markCompletedLocally(widget.reminderId);
        // 讓「我的」分頁的連勝卡重讀（後端打卡當下已寫好當天快照）。
        StreakService.changes.value++;
      }
    } else {
      // reminderId <= 0：呼叫端（ElderReminderManager）在解析不出後端給的 id
      // 時一律退回 0（`int.tryParse(...) ?? 0`），代表這筆提醒本身的 id 資料
      // 缺漏，不是「打卡失敗」——沒有合法 id 可回報後端，重試同一個假 id 也
      // 不會有幫助。長輩實際上已完成這件事的動作，這裡選擇仍視為完成（不寫
      // 本機清單、不打 API，兩者都沒有合法 id 可用），而不是讓長輩對著一個他
      // 無從理解、重試也沒用的「失敗」反覆重按。
      debugPrint(
          '⚠️ [ElderReminderDialog] reminderId=${widget.reminderId} 缺乏有效 id，略過後端與本機打卡記錄');
      success = true;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      widget.onCompleted?.call();
      Navigator.of(context).pop();
      final c = UbanColors.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '太棒了！已完成「${stripEmoji(widget.title)}」打卡記錄',
            style: ubanText(18, FontWeight.w700, Colors.white),
          ),
          backgroundColor: c.brandStrong,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.all(20),
        ),
      );
    } else {
      // ★ 不 pop()——彈窗留著讓長輩可以再按一次「我做好了」重試；一旦關掉，
      //   長輩會以為流程結束，不會知道還要重新找回這筆提醒才能再打卡。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '打卡沒有送出成功，請確認網路後再按一次「我做好了」',
            style: ubanText(18, FontWeight.w700, Colors.white),
          ),
          backgroundColor: UbanColors.of(context).danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.all(20),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final cfg = _getConfig(widget.category);

    // 設計稿 `#dl-reminder`：圓角 32、padding 22、surface 底，不帶色光暈陰影。
    return UbanDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 頂部徽章與關閉按鈕
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.warmContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(cfg.icon, size: 18, color: c.warm),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          cfg.label,
                          overflow: TextOverflow.ellipsis,
                          style: ubanText(16, FontWeight.w700, c.warm),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: '關閉',
                excludeSemantics: true,
                child: PressableScale(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: c.surface2, shape: BoxShape.circle),
                    child: Icon(Icons.close_rounded, color: c.text, size: 24),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 大字體主標題
          Text(
            stripEmoji(widget.title),
            style: ubanText(30, FontWeight.w900, c.text, height: 1.25),
          ),

          const SizedBox(height: 8),

          // 時段標籤（設計稿 .tag）
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '今日 ${widget.timeStr}',
                style: ubanText(16, FontWeight.w700, c.text2),
              ),
            ),
          ),

          if (widget.note.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '子女叮嚀：',
                      style: ubanText(18, FontWeight.w800, c.brandStrong,
                          height: 1.55),
                    ),
                    TextSpan(
                      text: widget.note,
                      style:
                          ubanText(18, FontWeight.w500, c.text, height: 1.55),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 18),

          // 按鈕區域：「稍後提醒」:「我做好了！打卡」= 2:3（設計稿 2fr 3fr）。
          Row(
            children: [
              Expanded(
                flex: 2,
                child: OverlayButton(
                  label: '稍後提醒',
                  filled: false,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: OverlayButton(
                  label: '我做好了！打卡',
                  loading: _isSubmitting,
                  onPressed: _isSubmitting ? null : _handleComplete,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryConfig {
  final String label;
  final IconData icon;

  const _CategoryConfig({required this.label, required this.icon});
}
