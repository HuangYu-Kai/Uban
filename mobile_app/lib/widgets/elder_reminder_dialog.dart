// lib/widgets/elder_reminder_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

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
      final speakContent = "${widget.elderName}您好，現在是${widget.timeStr}，提醒您「${widget.title}」喔！${widget.note.isNotEmpty ? widget.note : ''}";
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

  _CategoryConfig _getConfig(String category) {
    switch (category) {
      case 'medication':
        return _CategoryConfig(
          label: '用藥提醒',
          emoji: '💊',
          color: const Color(0xFF10B981),
          lightBg: const Color(0xFFECFDF5),
        );
      case 'water':
        return _CategoryConfig(
          label: '喝水提醒',
          emoji: '💧',
          color: const Color(0xFF0284C7),
          lightBg: const Color(0xFFF0F9FF),
        );
      case 'exercise':
        return _CategoryConfig(
          label: '活力運動',
          emoji: '🚶',
          color: const Color(0xFFD97706),
          lightBg: const Color(0xFFFFFBEB),
        );
      case 'hospital':
        return _CategoryConfig(
          label: '門診回診',
          emoji: '🏥',
          color: const Color(0xFFE11D48),
          lightBg: const Color(0xFFFFF1F2),
        );
      default:
        return _CategoryConfig(
          label: '生活提醒',
          emoji: '⏰',
          color: const Color(0xFFD97706),
          lightBg: const Color(0xFFFEF3C7),
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '太棒了！已完成「${widget.title}」打卡記錄 ✨',
            style: GoogleFonts.notoSansTc(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF10B981),
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
            style: GoogleFonts.notoSansTc(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFFB91C1C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.all(20),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _getConfig(widget.category);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      backgroundColor: const Color(0xFFFFFDF8),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 540),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF8),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0xFFFDE68A), width: 1.8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF78350F).withValues(alpha: 0.12),
              blurRadius: 36,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 頂部徽章與關閉按鈕
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: cfg.lightBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cfg.color.withValues(alpha: 0.3), width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(cfg.emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      Text(
                        cfg.label,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: cfg.color,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF9CA3AF), size: 28),
                  tooltip: '關閉',
                ),
              ],
            ),

            const SizedBox(height: 18),

            // 大字體主標題
            Text(
              widget.title,
              style: GoogleFonts.notoSansTc(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF451A03),
                letterSpacing: -0.5,
              ),
            ),

            const SizedBox(height: 10),

            // 時段標籤
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFFB45309)),
                      const SizedBox(width: 6),
                      Text(
                        '今日 ${widget.timeStr}',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (widget.note.isNotEmpty) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF7F2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFEADBCE), width: 1.2),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('💬', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '子女關懷叮嚀：',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF8C6D58),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.note,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF451A03),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // 按鈕區域
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Color(0xFFD1D5DB), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Text(
                      '稍後提醒',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleComplete,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : Text(
                            '我做好了！打卡 ✨',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryConfig {
  final String label;
  final String emoji;
  final Color color;
  final Color lightBg;

  _CategoryConfig({
    required this.label,
    required this.emoji,
    required this.color,
    required this.lightBg,
  });
}
