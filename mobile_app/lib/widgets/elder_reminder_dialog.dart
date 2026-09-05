// lib/widgets/elder_reminder_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/api_service.dart';

/// ⏰ 長輩端專用：高對比、大字體、暖心繪本風的排程提醒彈窗
class ElderReminderDialog extends StatefulWidget {
  final int reminderId;
  final String title;
  final String timeStr;
  final String category;
  final String note;
  final String elderName;
  final VoidCallback? onCompleted;

  const ElderReminderDialog({
    super.key,
    required this.reminderId,
    required this.title,
    required this.timeStr,
    this.category = 'custom',
    this.note = '',
    this.elderName = '長輩',
    this.onCompleted,
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
    _playVoicePrompt();
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

  Future<void> _handleComplete() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    HapticFeedback.heavyImpact();

    try {
      if (widget.reminderId > 0) {
        await ApiService.completeElderReminder(widget.reminderId);
      }
    } catch (e) {
      debugPrint("⚠️ Complete reminder error: $e");
    }

    if (mounted) {
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
