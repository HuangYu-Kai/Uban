import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/elder.dart';
import '../../services/signaling.dart';
import '../../services/api_service.dart';
import '../video_call_screen.dart';
import 'family_ai_copilot_screen.dart';
import 'family_subscription_screen.dart';
import '../elder_community_screen.dart';

class FamilyInteractionTab extends StatefulWidget {
  final Elder? currentElder;
  final Signaling signaling;
  final List<dynamic> monitorDevices;
  final List<Map<String, dynamic>> activeAlerts;

  /// ★ 2026-08-24 Feature A（監控清單「目前長輩所在此處」高亮）：與傳給
  /// `FamilyHomeTab` 的是同一份正規化狀態 `{zone, enteredAt, updatedAt,
  /// present, deviceId}`，由 `FamilyMainScreen._elderZone` 提供，本分頁
  /// 不自行呼叫任何 API。`deviceId` 為 null、`present` 不是 `true`，或找不到
  /// 相符的監視機卡片時，單純不顯示「目前所在」高亮，不影響既有的跌倒警報
  /// 高亮（`hasActiveAlert`，見 `_buildMonitorDeviceCard`；警報優先權更高）。
  /// `present` 才是「長輩在此」的唯一依據（見
  /// `family_main_screen.dart::_elderZone` 欄位宣告處的完整說明）——不能只
  /// 比對 `deviceId`，`_elderZone` 有可能因為過期（長輩早已離開鏡頭）而
  /// `present == false`，此時即使 `deviceId` 還留著上一次的值也不可以繼續
  /// 高亮。
  final Map<String, dynamic>? elderZone;

  final int devicesMax;
  final String tierDisplayName;
  final String tierLevel;
  final int? userId;

  /// ★ 2026-08-10 第十九輪（需求 4）：長輩通訊機的 socket id，由
  /// `FamilyMainScreen._elderSocketId` 維護。撥打一般／緊急通話時必須帶上，
  /// 否則後端只能靠房間廣播猜目標，與舊版 `family_dashboard_view` 行為不一致。
  final String? elderSocketId;

  /// ★ 2026-08-10 第十九輪（需求 3）：卡片上刪除／改名成功後通知父層重新整理
  /// 設備清單與訂閱用量。
  final VoidCallback? onDevicesChanged;
  final Function(dynamic deviceId)? onAlertDismissed;

  // ★ 第四十一輪 item 2（第二階段）：新手指引用的高光目標 GlobalKey。全部
  //   選填、預設 null——GlobalKey 必須由上層 FamilyMainScreen 持有並傳入，
  //   理由與傳遞方式比照 family_home_tab.dart 同名欄位群組的說明。不傳就
  //   等同沒有目標，`SpotlightTutorial` 會自動退化為無挖洞的置中卡片。
  final GlobalKey? callSectionKey;
  final GlobalKey? aiCopilotKey;
  final GlobalKey? communityKey;
  final GlobalKey? monitorSectionKey;

  const FamilyInteractionTab({
    super.key,
    required this.currentElder,
    required this.signaling,
    this.monitorDevices = const [],
    this.activeAlerts = const [],
    this.elderZone,
    this.devicesMax = 2,
    this.tierDisplayName = '一般會員',
    this.tierLevel = 'free',
    this.userId,
    this.elderSocketId,
    this.onDevicesChanged,
    this.onAlertDismissed,
    this.callSectionKey,
    this.aiCopilotKey,
    this.communityKey,
    this.monitorSectionKey,
  });

  @override
  State<FamilyInteractionTab> createState() => _FamilyInteractionTabState();
}

class _FamilyInteractionTabState extends State<FamilyInteractionTab> {
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;
  List<Map<String, dynamic>> _reminders = [];
  bool _isLoadingReminders = false;

  final Set<int> _audioBridgeChecked = {};
  final Set<int> _audioBridgePending = {};
  final Map<int, String> _audioBridgeExpire = {};
  Timer? _monitorBindPollTimer;
  @override
  void initState() {
    super.initState();
    _fetchReminders();
    _syncAudioBridgeForAlerts();
  }

  @override
  void didUpdateWidget(covariant FamilyInteractionTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentElder?.id != oldWidget.currentElder?.id ||
        widget.currentElder?.elderId != oldWidget.currentElder?.elderId) {
      _fetchReminders();
    }
    // 新警報進來時才查一次語音橋狀態（_audioBridgeChecked 保證同一 alert 只查一次）
    if (widget.activeAlerts.length != oldWidget.activeAlerts.length) {
      _syncAudioBridgeForAlerts();
    }
  }

  Future<void> _fetchReminders() async {
    if (widget.currentElder == null) return;
    final elderId = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();
    final elderIdInt = widget.currentElder!.id.toString();
    setState(() => _isLoadingReminders = true);
    try {
      var data = await ApiService.get("/api/reminder/elder/$elderId");
      if ((data == null || data['data'] == null || (data['data'] as List).isEmpty) && elderId != elderIdInt) {
        data = await ApiService.get("/api/reminder/elder/$elderIdInt");
      }
      if (mounted && data != null && data['status'] == 'success') {
        setState(() {
          _reminders = List<Map<String, dynamic>>.from(data!['data'] ?? []);
        });
      }
    } catch (e) {
      debugPrint("❌ Failed to fetch reminders: $e");
    } finally {
      if (mounted) setState(() => _isLoadingReminders = false);
    }
  }

  Future<void> _toggleReminder(int index) async {
    final reminder = _reminders[index];
    final id = reminder['id'];
    HapticFeedback.lightImpact();
    setState(() {
      _reminders[index]['is_active'] = !_reminders[index]['is_active'];
    });
    try {
      await ApiService.put("/api/reminder/$id/toggle", {});
    } catch (e) {
      debugPrint("❌ Failed to toggle reminder: $e");
      _fetchReminders(); // Rollback on error
    }
  }

  Future<void> _deleteReminder(int id) async {
    HapticFeedback.mediumImpact();
    try {
      await ApiService.delete("/api/reminder/$id");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已刪除該筆提醒卡片'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        _fetchReminders();
      }
    } catch (e) {
      debugPrint("❌ Failed to delete reminder: $e");
    }
  }

  Future<void> _broadcastReminder(Map<String, dynamic> r) async {
    if (widget.currentElder == null) return;
    HapticFeedback.heavyImpact();
    final title = r['title'] ?? '提醒事項';
    final note = r['note'] != null && r['note'].toString().isNotEmpty ? "（${r['note']}）" : "";
    try {
      final bool sent = await widget.signaling.sendHeartbeat(
        widget.currentElder!.id,
        "⏰ 遠端提醒廣播：$title$note",
        playSound: true,
      );
      if (!mounted) return;
      if (sent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已即時推送廣播「$title」至長輩端平板 🔔'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      } else {
        // ★ 2026-08-31 第三十八輪：sendHeartbeat 在 socket 未連線時回傳 false，
        //   之前無條件顯示成功提示（謊報成功），改為顯示失敗提示。
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('目前未連線，請稍後再試'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      debugPrint("❌ Broadcast error: $e");
    }
  }

  Future<void> _showAddReminderDialog({Map<String, dynamic>? existingReminder}) async {
    if (widget.currentElder == null) return;
    final prefs = await SharedPreferences.getInstance();
    final familyId = prefs.getInt('caregiver_id') ?? 1;

    final bool isEditing = existingReminder != null;
    final String elderIdStr = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();
    final TextEditingController titleCtrl = TextEditingController(text: existingReminder?['title'] ?? '');
    final TextEditingController noteCtrl = TextEditingController(text: existingReminder?['note'] ?? '');
    
    TimeOfDay selectedTime = TimeOfDay.now();
    if (isEditing && existingReminder!['time_str'] != null) {
      try {
        final parts = existingReminder['time_str'].toString().split(':');
        if (parts.length >= 2) {
          selectedTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
      } catch (_) {}
    }

    DateTime? selectedDate = DateTime.now();
    if (isEditing && existingReminder!['start_date'] != null && existingReminder['start_date'].toString().isNotEmpty) {
      try {
        selectedDate = DateTime.parse(existingReminder['start_date']);
      } catch (_) {}
    } else if (isEditing && (existingReminder!['start_date'] == null || existingReminder['start_date'].toString().isEmpty)) {
      selectedDate = null;
    }

    String selectedCategory = existingReminder?['category'] ?? 'medication';
    String selectedRepeat = existingReminder?['repeat_days'] ?? '每天';

    final bool? created = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final now = DateTime.now();
            final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
            final tomorrow = now.add(const Duration(days: 1));
            final tomorrowStr = "${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";

            String dateText;
            if (selectedDate == null) {
              dateText = '不限日期';
            } else {
              final dStr = "${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}";
              if (dStr == todayStr) {
                dateText = '今天 ($dStr)';
              } else if (dStr == tomorrowStr) {
                dateText = '明天 ($dStr)';
              } else {
                dateText = dStr;
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(isEditing ? Icons.edit_calendar_rounded : Icons.add_alarm_rounded, color: const Color(0xFF38BDF8)),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEditing ? '編輯遠端提醒' : '新增遠端提醒',
                    style: GoogleFonts.notoSansTc(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('提醒類別', style: GoogleFonts.notoSansTc(color: const Color(0xFF94A3B8), fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildCatChip('medication', '💊 用藥', selectedCategory, (val) => setDialogState(() => selectedCategory = val)),
                        _buildCatChip('hospital', '🏥 看診', selectedCategory, (val) => setDialogState(() => selectedCategory = val)),
                        _buildCatChip('water', '🥤 飲水', selectedCategory, (val) => setDialogState(() => selectedCategory = val)),
                        _buildCatChip('exercise', '🧘‍♂️ 運動', selectedCategory, (val) => setDialogState(() => selectedCategory = val)),
                        _buildCatChip('custom', '⏰ 叮嚀', selectedCategory, (val) => setDialogState(() => selectedCategory = val)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('提醒標題', style: GoogleFonts.notoSansTc(color: const Color(0xFF94A3B8), fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleCtrl,
                      style: GoogleFonts.notoSansTc(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '例如: 吃高血壓藥、台大看診',
                        hintStyle: GoogleFonts.notoSansTc(color: const Color(0xFF64748B)),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('提醒日期', style: GoogleFonts.notoSansTc(color: const Color(0xFF94A3B8), fontSize: 13)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate ?? DateTime.now(),
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setDialogState(() => selectedDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                dateText,
                                style: GoogleFonts.notoSansTc(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF94A3B8)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('提醒時間', style: GoogleFonts.notoSansTc(color: const Color(0xFF94A3B8), fontSize: 13)),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () async {
                                  final tod = await showTimePicker(context: context, initialTime: selectedTime);
                                  if (tod != null) setDialogState(() => selectedTime = tod);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.access_time_rounded, color: Color(0xFF38BDF8), size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        "${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}",
                                        style: GoogleFonts.notoSansTc(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('重複頻率', style: GoogleFonts.notoSansTc(color: const Color(0xFF94A3B8), fontSize: 13)),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: selectedRepeat,
                                    dropdownColor: const Color(0xFF0F172A),
                                    style: GoogleFonts.notoSansTc(color: Colors.white, fontWeight: FontWeight.w600),
                                    isExpanded: true,
                                    items: ['每天', '週一至週五', '每週三', '單次'].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                                    onChanged: (val) {
                                      if (val != null) setDialogState(() => selectedRepeat = val);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('備註說明（選填）', style: GoogleFonts.notoSansTc(color: const Color(0xFF94A3B8), fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: noteCtrl,
                      style: GoogleFonts.notoSansTc(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '例如: 飯後溫開水服用一顆',
                        hintStyle: GoogleFonts.notoSansTc(color: const Color(0xFF64748B)),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('取消', style: GoogleFonts.notoSansTc(color: const Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty) return;
                    final timeStr = "${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}";
                    final dateStr = selectedDate != null ? "${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}" : null;
                    
                    bool success = false;
                    if (isEditing) {
                      success = await ApiService.updateElderReminder(existingReminder['id'], {
                        "title": titleCtrl.text.trim(),
                        "category": selectedCategory,
                        "time_str": timeStr,
                        "repeat_days": selectedRepeat,
                        "start_date": dateStr,
                        "note": noteCtrl.text.trim(),
                      });
                    } else {
                      final res = await ApiService.post("/api/reminder/", {
                        "family_id": familyId,
                        "elder_id": elderIdStr,
                        "title": titleCtrl.text.trim(),
                        "category": selectedCategory,
                        "time_str": timeStr,
                        "repeat_days": selectedRepeat,
                        "start_date": dateStr,
                        "note": noteCtrl.text.trim(),
                      });
                      success = res != null && res['status'] == 'success';
                    }

                    if (ctx.mounted) {
                      if (success) {
                        Navigator.pop(ctx, true);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(isEditing ? '儲存提醒失敗' : '新增提醒失敗'),
                            backgroundColor: const Color(0xFFEF4444),
                          ),
                        );
                      }
                    }
                  },
                  child: Text(isEditing ? '確認儲存' : '確認新增', style: GoogleFonts.notoSansTc(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );

    if (created == true) {
      _fetchReminders();
    }
  }

  Widget _buildCatChip(String catKey, String label, String currentCat, Function(String) onSelect) {
    final bool isSel = currentCat == catKey;
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.notoSansTc(fontSize: 12, color: isSel ? Colors.white : const Color(0xFF94A3B8))),
      selected: isSel,
      selectedColor: const Color(0xFF0284C7),
      backgroundColor: const Color(0xFF0F172A),
      onSelected: (_) => onSelect(catKey),
    );
  }

  /// ★ 2026-08-04 第 7 項：為尚未查過的警報查詢語音橋狀態。
  /// 任何一筆查詢失敗都只略過該筆，不影響其餘警報，也不彈任何錯誤給使用者——
  /// 語音權限是輔助功能，不能讓它的網路問題干擾警報本身的顯示。
  Future<void> _syncAudioBridgeForAlerts() async {
    for (final alert in widget.activeAlerts) {
      final alertId = int.tryParse(
        (alert['alert_id'] ?? alert['alertId'])?.toString() ?? '',
      );
      if (alertId == null || _audioBridgeChecked.contains(alertId)) continue;
      _audioBridgeChecked.add(alertId);
      try {
        // ★ 2026-08-05 第十七輪（安全）：帶上 userId，讓後端走完整關係驗證分支
        final data = await ApiService.checkAudioBridge(
          alertId,
          userId: widget.userId,
        );
        if (!mounted) return;
        if (data != null && data['has_audio_bridge'] == true) {
          setState(() {
            _audioBridgeExpire[alertId] = (data['expire_at'] ?? '').toString();
          });
        }
      } catch (_) {
        // 略過此筆，下次有新警報時不會重試（已記入 _audioBridgeChecked），
        // 家屬仍可手動按下按鈕主動開通。
      }
    }
  }

  /// ★ 2026-08-04 第 7 項：開通／延長 30 分鐘單向語音（家屬 → 監視機）。
  Future<void> _openAudioBridge(int alertId, int deviceId) async {
    final userId = widget.userId;
    if (userId == null || _audioBridgePending.contains(alertId)) return;

    setState(() => _audioBridgePending.add(alertId));
    try {
      final data = await ApiService.openAudioBridge(
        alertId: alertId,
        fromId: userId,
        toDeviceId: deviceId,
      );
      if (!mounted) return;
      if (data != null) {
        setState(() {
          _audioBridgeExpire[alertId] = (data['expire_at'] ?? '').toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已開啟語音通道，30 分鐘內可對該監視機說話'),
            backgroundColor: Color(0xFF59B294),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('開啟語音通道失敗，請稍後再試')),
        );
      }
    } finally {
      if (mounted) setState(() => _audioBridgePending.remove(alertId));
    }
  }

  /// 把後端回傳的 expire_at（ISO 字串）轉成「剩 N 分鐘」。解析失敗就不顯示時間。
  String? _audioBridgeRemainText(String? expireAt) {
    if (expireAt == null || expireAt.isEmpty) return null;
    final expire = DateTime.tryParse(expireAt);
    if (expire == null) return null;
    final remain = expire.difference(DateTime.now()).inMinutes;
    if (remain <= 0) return null;
    return '剩 $remain 分鐘';
  }

  /// ★ 2026-08-04 第 7 項：警報卡片上的語音通道按鈕。
  Widget _buildAudioBridgeButton(int alertId, int deviceId) {
    final isPending = _audioBridgePending.contains(alertId);
    final remainText = _audioBridgeRemainText(_audioBridgeExpire[alertId]);
    final isOpen = remainText != null;

    return SizedBox(
      height: 32,
      child: OutlinedButton.icon(
        onPressed: isPending ? null : () => _openAudioBridge(alertId, deviceId),
        icon: Icon(
          isOpen ? Icons.volume_up_rounded : Icons.mic_none_rounded,
          size: 16,
        ),
        label: Text(
          isPending
              ? '開啟中…'
              : isOpen
                  ? '語音通道已開啟（$remainText）'
                  : '開啟語音通道 30 分鐘',
          style: GoogleFonts.notoSansTc(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        // ★ 2026-08-11 第二十二輪（需求 5）：這顆按鈕長在監視機卡片內，
        //   卡片轉深色後原本的 `Colors.red.shade700` 幾乎看不見，改用亮一階的紅／綠。
        style: OutlinedButton.styleFrom(
          foregroundColor:
              isOpen ? const Color(0xFF34D399) : const Color(0xFFF87171),
          side: BorderSide(
            color: isOpen ? const Color(0xFF34D399) : const Color(0xFFEF4444),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
  @override
  void dispose() {
    // ★ 2026-08-11 第二十二輪（需求 1）：離開分頁時務必停掉配對輪詢，
    //   否則計時器會在 State 已銷毀後繼續打 HTTP 並碰 context。
    _monitorBindPollTimer?.cancel();
    _monitorBindPollTimer = null;
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _showAddMonitorDialog() async {
    if (widget.currentElder == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final familyId = prefs.getInt('caregiver_id');
    if (familyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('無法取得您的帳號 ID')));
      return;
    }

    final String rawId = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();
    final TextEditingController nameCtrl = TextEditingController(text: '客廳攝影機');
    
    if (!mounted) return;
    
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增監控設備'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('請輸入此監控設備的名稱：'),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '例如: 客廳、臥室',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('產生代碼'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final data = await ApiService.createMonitorSetup(familyId, rawId, nameCtrl.text);
    if (!mounted) return;
    Navigator.pop(context); // close loading

    // ★ issue 6：後端 /api/pairing/monitor_setup 回傳的欄位名為 'code'，非 'pairing_code'
    if (data != null && data['code'] != null) {
      final code = data['code'];
      final String targetDeviceName = nameCtrl.text.trim();

      // ★ 2026-08-19 修正（監控綁定碼假成功 bug）：舊版靠 isBoundIn() 檢查
      //   「裝置清單裡有沒有出現同名／新裝置」當完成信號，但這個信號是錯的——
      //   monitor_device_binding 是永久紀錄，且監控設備名稱預設固定為
      //   「客廳攝影機」，只要長輩之前綁過同名裝置，_get_elder_devices_list
      //   階段 0 一定會重新吐出那筆舊紀錄，導致彈窗一開、第一個 2 秒輪詢
      //   tick 就誤判成功並自動關閉，但監控機端其實什麼都還沒輸入。
      //   正確信號是後端 `monitor_setup_code.used_at`（僅由監控機實際兌換
      //   配對碼時寫入，見 pairing.py::resolve_monitor_setup），因此改為輪詢
      //   新端點 GET /api/pairing/monitor_setup/status，不再用裝置清單猜測。
      bool dialogClosed = false;
      BuildContext? codeDialogContext;

      void stopPolling() {
        _monitorBindPollTimer?.cancel();
        _monitorBindPollTimer = null;
      }

      void closeCodeDialogOnBound() {
        if (dialogClosed) return;
        dialogClosed = true;
        stopPolling();
        final ctx = codeDialogContext;
        if (ctx != null && ctx.mounted && Navigator.of(ctx).canPop()) {
          Navigator.of(ctx).pop();
        }
        if (!mounted) return;
        _toast('監控設備「$targetDeviceName」已完成綁定');
        widget.onDevicesChanged?.call();
      }

      // 綁定碼在監控機兌換之前就過期：停止輪詢並明確告知需要重新產生代碼，
      // 否則使用者只會看著彈窗空等到 5 分鐘輪詢上限，不知道該做什麼。
      void closeCodeDialogOnExpired() {
        if (dialogClosed) return;
        dialogClosed = true;
        stopPolling();
        final ctx = codeDialogContext;
        if (ctx != null && ctx.mounted && Navigator.of(ctx).canPop()) {
          Navigator.of(ctx).pop();
        }
        if (!mounted) return;
        _toast('此綁定碼已過期，請重新產生配對碼');
      }

      stopPolling();
      int ticks = 0;
      _monitorBindPollTimer =
          Timer.periodic(const Duration(seconds: 2), (timer) async {
        // 硬上限 5 分鐘（150 次）：逾時只停止輪詢，彈窗與配對碼仍然有效
        //（後端配對碼壽命是 15 分鐘），使用者可繼續手動按「完成」。
        if (dialogClosed || !mounted || ++ticks > 150) {
          if (ticks > 150) stopPolling();
          return;
        }

        final userIdForQuery = widget.userId ?? familyId;
        final status = await ApiService.getMonitorSetupStatus(
          code.toString(),
          userId: userIdForQuery,
        );
        if (status == null) return; // 查詢失敗：不知道結果，下一輪再試
        if (dialogClosed || !mounted) return;

        if (status['used'] == true) {
          // 完成信號 = monitor_setup_code.used_at 已寫入，不再依賴裝置清單。
          closeCodeDialogOnBound();
        } else if (status['expired'] == true) {
          closeCodeDialogOnExpired();
        }
      });

      showDialog(
        context: context,
        builder: (ctx) {
          codeDialogContext = ctx;
          return AlertDialog(
            title: const Text('設備配對碼已產生'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('請在要作為攝影機的備用手機上，安裝 Uban 長輩版並選擇「作為監控設備登入」，然後輸入以下 6 位數代碼：'),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    code,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '此代碼將在 15 分鐘後失效。',
                  style: TextStyle(color: Colors.red.shade400, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  '對方輸入完成後，本視窗會自動關閉。',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('完成'),
              ),
            ],
          );
        },
      ).then((_) {
        // 使用者自己按「完成」或點掉彈窗 → 一併停掉輪詢，
        // 並標記為已關閉，避免之後又去 pop 到底下的頁面。
        dialogClosed = true;
        stopPolling();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('產生配對碼失敗，請稍後再試')),
      );
    }
  }

  void _makeVideoCall() {
    if (widget.currentElder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先在頂部選擇要關照的長輩')),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: const Color(0xFF0284C7).withValues(alpha: 0.4), width: 1.5),
      ),
      builder: (context) {
        final String rawId = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '選擇通話方式',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                // 一般通話按鈕
                _buildCallOptionButton(
                  title: '一般視訊通話',
                  subtitle: '長輩需手動接聽後建立連線',
                  icon: Icons.video_call_rounded,
                  color: const Color(0xFF38BDF8),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VideoCallScreen(
                          roomId: 'comm_elder_$rawId',
                          targetSocketId: null, // ★ 不綁死單一 socket ID，由後端完整廣播給線上長輩 Socket 與所有長輩 FCM Token
                          autoStart: true,
                          isEmergency: false,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                // 緊急強制通話按鈕
                _buildCallOptionButton(
                  title: '緊急強制通話',
                  subtitle: '強制喚醒長輩設備並自動接聽',
                  icon: Icons.warning_rounded,
                  color: const Color(0xFFEF4444),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VideoCallScreen(
                          roomId: 'comm_elder_$rawId',
                          targetSocketId: null, // ★ 不綁死單一 socket ID，由後端完整廣播給線上長輩 Socket 與所有長輩 FCM Token
                          autoStart: true,
                          isEmergency: true,
                        ),
                      ),
                    );
                  },
                ),
                // ★ 第四十輪（item 1b）：移除「單向視訊監控」選項（原本呼叫
                //   CameraScreen，roomId: 'monitor_elder_$rawId'，只取房內第一台
                //   monitor 裝置，無法選擇特定裝置）。監控檢視能力並未消失——
                //   互動分頁監控卡片的「觀看 CCTV」（_buildMonitorDeviceCard →
                //   VideoCallScreen(monitorViewOnly: true)，見 CLAUDE_call-monitor.md
                //   G55／G138）走的是同一份 elder-devices-update 設備清單，且能精準
                //   指定裝置，功能完整覆蓋此處移除的項目。
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCallOptionButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 13,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.7), size: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _sendMessage(String text) async {
    if (widget.currentElder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先在頂部選擇要關照的長輩')),
      );
      return;
    }

    final messageText = text.trim();
    if (messageText.isEmpty) return;

    setState(() => _isSending = true);
    HapticFeedback.lightImpact();

    try {
      final bool sent = await widget.signaling.sendHeartbeat(
        widget.currentElder!.id,
        messageText,
        playSound: true,
      );

      if (!mounted) return;
      if (sent) {
        _messageController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已傳送留言給 ${widget.currentElder!.displayName} ✨'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      } else {
        // ★ 2026-08-31 第三十八輪：sendHeartbeat 在 socket 未連線時回傳 false，
        //   之前無條件顯示成功提示（謊報成功），改為顯示失敗提示；訊息保留在輸入框，不清空。
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('目前未連線，請稍後再試'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('傳送失敗: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentElder == null) {
      return _buildNoElderPlaceholder();
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // 1. 視訊呼叫區（大按鈕，顯眼）
              _buildCallSection(),
              const SizedBox(height: 20),

              // 2. 🤖 AI 照護共創助理（對話建立排程與近況速報）
              _buildAiCopilotSection(),
              const SizedBox(height: 20),

              // 3. 家庭生活社群時光牆（雙向動態互動）
              _buildCommunitySection(),
              const SizedBox(height: 20),

              // 4. 留言發送區（快速短句 + 自訂輸入）
              _buildMessageSection(),
              const SizedBox(height: 20),

              // 5. 遠端監控區（方案 B：未連接獨立攝影機設備預留）
              _buildMonitorSection(),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildAiCopilotSection() {
    final elderName = widget.currentElder?.displayName ?? '長輩';

    return Container(
      key: widget.aiCopilotKey,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF38BDF8),
            Color(0xFF8B5CF6),
            Color(0xFF10B981),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(1.5),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(26.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0284C7), Color(0xFF6366F1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // ★ 第四十輪（item 1a）：與「家庭生活時光牆」同型的溢位風險——
                          //   同列有 ≥18pt 標題 + 徽章即需可收縮，字面字串不是安全的判準。
                          Flexible(
                            child: Text(
                              'AI 照護共創助理',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.notoSansTc(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '就緒',
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF10B981),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '對話建立排程與近況速報摘要',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 12,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '與 AI 照護助理對話，可快速獲取 $elderName 的最新動態速報，或直接以自然語言語音建立吃藥與運動排程！',
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                color: const Color(0xFFCBD5E1),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildAuroraBadge(Icons.wb_sunny_rounded, '近況速報', const Color(0xFF38BDF8)),
                const SizedBox(width: 8),
                _buildAuroraBadge(Icons.edit_calendar_rounded, '對話建立排程', const Color(0xFF10B981)),
                const SizedBox(width: 8),
                _buildAuroraBadge(Icons.forum_rounded, '照護諮詢', const Color(0xFFF59E0B)),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0284C7), Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FamilyAiCopilotScreen(currentElder: widget.currentElder),
                      ),
                    ).then((_) {
                      _fetchReminders();
                    });
                  },
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '開啟 AI 照護對話助理',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_rounded, color: Colors.white70, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuroraBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.notoSansTc(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunitySection() {
    return Container(
      key: widget.communityKey,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF047857)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            HapticFeedback.lightImpact();
            final prefs = await SharedPreferences.getInstance();
            if (!mounted) return;
            final familyId = prefs.getInt('caregiver_id') ?? 2;
            final userName = prefs.getString('caregiver_name') ?? prefs.getString('user_name') ?? '家人';

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ElderCommunityScreen(
                  userId: familyId,
                  userName: userName,
                  familyId: familyId,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.groups_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // ★ 第四十輪（item 1a）：字面字串不等於安全——'家庭生活時光牆'
                          //   七個中文字在 22pt / w900 下，加上同列的「雙向交流」徽章與
                          //   外層固定寬度的箭頭圖示，在 360dp 寬手機上就會右側溢位。
                          //   字級與同列元素數量才是判準，不是字串是否為動態內容。
                          Flexible(
                            child: Text(
                              '家庭生活時光牆',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.notoSansTc(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              '雙向交流',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '瀏覽長輩心情、分享生活照片與留言關心',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05);
  }

  Widget _buildNoElderPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_alt_rounded, size: 64, color: Color(0xFF94A3B8)),
            const SizedBox(height: 16),
            Text(
              '尚未選擇長輩',
              style: GoogleFonts.notoSansTc(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '請點擊頂部長輩選單來載入長輩的互動功能',
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                color: const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms),
    );
  }

  Widget _buildCallSection() {
    return Container(
      key: widget.callSectionKey,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF1E40AF), Color(0xFF0284C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _makeVideoCall,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.6), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.videocam_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ★ 2026-08-11 第二十一輪（需求 3）：原本這裡是 Row，兩個子項
                      //   （fontSize 24 的「視訊通話」標題 + 「即時連線」徽章）都是
                      //   **非彈性**的，卻放在外層 Row 的 Expanded 裡——可用寬度是
                      //   螢幕寬扣掉 SliverPadding 32、卡片 padding 48、左側圓形圖示
                      //   約 71、間距 18、右側箭頭約 36 之後的剩餘量，在一般手機上
                      //   小於這兩項的自然寬度總和，因此必然 RIGHT OVERFLOW（實測 13px），
                      //   黃黑斜紋警示條就疊在「視訊通話」按鈕上。
                      //   改用 Wrap：寬螢幕的排版與原本逐像素相同（同一列、間距 8），
                      //   窄螢幕則讓徽章自動換行，永遠不會溢位，也不必截斷標題文字。
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            '視訊通話',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF34D399),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '即時連線',
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF34D399),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '與長輩開啟高清雙向視訊與音訊對話',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFFBAE6FD),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05);
  }

    Widget _buildMessageSection() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                ),
                child: const Icon(
                  Icons.alarm_rounded,
                  color: Color(0xFF38BDF8),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '遠端提醒與用藥行程',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: _showAddReminderDialog,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        '新增提醒',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          if (_isLoadingReminders)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
              ),
            )
          else if (_reminders.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.notifications_none_rounded, color: Color(0xFF64748B), size: 40),
                  const SizedBox(height: 8),
                  Text(
                    '目前尚無排程提醒',
                    style: GoogleFonts.notoSansTc(color: const Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '點擊右上角「新增提醒」為長輩設定用藥或看診時間',
                    style: GoogleFonts.notoSansTc(color: const Color(0xFF64748B), fontSize: 12),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _reminders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final r = _reminders[index];
                final bool isActive = r['is_active'] == true || r['is_active'] == 1;
                final cat = r['category'] ?? 'custom';
                
                String catName = '叮嚀';
                Color iconColor = const Color(0xFF38BDF8);
                IconData catIcon = Icons.notifications_active_rounded;
                if (cat == 'medication') {
                  catName = '用藥';
                  iconColor = const Color(0xFFF43F5E);
                  catIcon = Icons.medication_rounded;
                } else if (cat == 'hospital') {
                  catName = '看診';
                  iconColor = const Color(0xFF3B82F6);
                  catIcon = Icons.local_hospital_rounded;
                } else if (cat == 'water') {
                  catName = '飲水';
                  iconColor = const Color(0xFF06B6D4);
                  catIcon = Icons.water_drop_rounded;
                } else if (cat == 'exercise') {
                  catName = '運動';
                  iconColor = const Color(0xFF10B981);
                  catIcon = Icons.fitness_center_rounded;
                }

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFF1E293B) : const Color(0xFF0F172A).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isActive ? iconColor.withValues(alpha: 0.4) : const Color(0xFF334155),
                      width: isActive ? 1.5 : 1.0,
                    ),
                    boxShadow: isActive ? [
                      BoxShadow(
                        color: iconColor.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ] : null,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 左欄：類別Icon + 時間 + 標籤 + 標題與備註
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: iconColor.withValues(alpha: isActive ? 0.2 : 0.08),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Icon(catIcon, color: isActive ? iconColor : const Color(0xFF64748B), size: 16),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  r['time_str'] ?? '00:00',
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    color: isActive ? Colors.white : const Color(0xFF64748B),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (r['start_date'] != null && r['start_date'].toString().isNotEmpty) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      r['start_date'].toString().replaceAll('-', '/'),
                                      style: GoogleFonts.notoSansTc(
                                        fontSize: 10,
                                        color: const Color(0xFF38BDF8),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF334155),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      r['repeat_days'] ?? '每天',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.notoSansTc(
                                        fontSize: 10.5,
                                        color: const Color(0xFFCBD5E1),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              r['title'] ?? '',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isActive ? const Color(0xFFF8FAFC) : const Color(0xFF64748B),
                              ),
                            ),
                            if (r['note'] != null && r['note'].toString().isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                r['note'],
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 13,
                                  color: const Color(0xFF94A3B8),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 右欄：垂直居中且放大的操作區塊 (Switch & 刪除按鈕)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Transform.scale(
                            scale: 1.2,
                            child: Switch(
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              value: isActive,
                              activeColor: const Color(0xFF38BDF8),
                              activeTrackColor: const Color(0xFF0284C7).withValues(alpha: 0.5),
                              inactiveThumbColor: const Color(0xFF64748B),
                              inactiveTrackColor: const Color(0xFF1E293B),
                              onChanged: (_) => _toggleReminder(index),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                                icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF38BDF8), size: 24),
                                tooltip: '編輯提醒',
                                onPressed: () => _showAddReminderDialog(existingReminder: r),
                              ),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                                icon: const Icon(Icons.volume_up_rounded, color: Color(0xFF10B981), size: 21),
                                tooltip: '立即廣播',
                                onPressed: () => _broadcastReminder(r),
                              ),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 21),
                                tooltip: '刪除提醒',
                                onPressed: () => _deleteReminder(r['id']),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms);
  }

  Widget _buildMonitorSection() {
    final reachedLimit = widget.monitorDevices.length >= widget.devicesMax;
    final String rawId = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();
    final String monitorRoomId = 'monitor_elder_$rawId';
    // ★ 2026-08-11 第二十二輪（需求 5）：ICON 依會員層級變色。
    final Color accent = _tierAccentColor();

    return Column(
      key: widget.monitorSectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ★ Task B4：訂閱層級徽章（點擊進入訂閱頁）
        _buildTierBadge(),
        const SizedBox(height: 12),
        Container(
          // ★ 2026-08-11 第二十二輪（需求 5）：改用家屬端暗色系。
          //   `family_main_screen.dart` 的 Scaffold 底色是 `0xFF0F172A`、卡片是 `0xFF1E293B`，
          //   這張白卡在深色底上像貼錯的浮水印，故整段（含子元件）一併改深。
          //   ⚠️ 純配色調整：版面結構、Expanded/Spacer、按鈕行為與跳轉全部不動。
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF334155)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      // ★ 2026-08-11 第二十二輪（需求 5）：這就是使用者指名要
                      //   「依會員等級變色」的遠端視訊監控 ICON。
                      child: Icon(
                        Icons.videocam_off_rounded,
                        color: accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // ★ 2026-08-10 第二十輪（需求 2）：原本是 Text + Spacer，
                    //   標題不可壓縮；一旦出現「N 警報」徽章，
                    //   標題 + 兩個徽章的總寬就超過卡片內寬 → 整條往右溢位。
                    //   改成 Expanded 後視覺位置完全相同（Text 在 Expanded 內靠左），
                    //   但空間不足時會自行縮短而非溢出。
                    Expanded(
                      child: Text(
                        '遠端視訊監控',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFE2E8F0),
                        ),
                      ),
                    ),
                    // ★ 移植自 family_dashboard_view.dart 第 1280-1303 行：活躍警報計數 badge
                    if (widget.activeAlerts.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade500,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.activeAlerts.length} 警報',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // 設備計數 badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: reachedLimit
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.18)
                            : const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${widget.monitorDevices.length} / ${widget.devicesMax}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: reachedLimit
                              ? const Color(0xFFFBBF24)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // ── 設備列表 or 空狀態 ──
                if (widget.monitorDevices.isEmpty)
                  _buildNoMonitorDevice()
                else ...[
                  ...widget.monitorDevices.map(
                    (device) => _buildMonitorDeviceCard(device, monitorRoomId: monitorRoomId),
                  ),
                  // 達到上限提示
                  if (reachedLimit)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildDeviceLimitWarning(),
                    ),
                ],
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _showAddMonitorDialog();
                    },
                    icon: const Icon(Icons.add_a_photo_rounded, size: 20),
                    label: const Text('新增並連接監控設備'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: const Color(0xFFE2E8F0),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: GoogleFonts.notoSansTc(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }

  /// 空狀態：尚未連接任何監視機設備（移植自 family_dashboard_view.dart 第 1345 行 _buildNoMonitorDevice）
  Widget _buildNoMonitorDevice() {
    // ★ 2026-08-11 第二十二輪（需求 5）：空狀態同樣改暗色系，ICON 依會員層級著色。
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.videocam_off_rounded,
            color: _tierAccentColor().withValues(alpha: 0.55),
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            '尚未連接任何監視機設備',
            style: GoogleFonts.notoSansTc(
              color: const Color(0xFFCBD5E1),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '請至「設定」配對家庭監控裝置',
            style: GoogleFonts.notoSansTc(
              color: const Color(0xFF64748B),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// 單一監視機裝置卡片（移植自 family_dashboard_view.dart 第 1382 行 _buildMonitorDeviceCard，
  /// 含依 hasActiveAlert 判定的紅框跌倒警報高亮樣式）
  Widget _buildMonitorDeviceCard(Map device, {required String monitorRoomId}) {
    final name = device['deviceName'] ?? 'Unnamed';
    final socketId = device['id'] as String? ?? '';
    final isOnline = device['isOnline'] == true;
    final deviceId = device['deviceId'] ?? device['id'];

    // ★ 是否有作用中警報
    final deviceAlerts = widget.activeAlerts
        .where((a) => (a['device_id'] ?? a['deviceId'])?.toString() == deviceId.toString())
        .toList();
    final hasActiveAlert = deviceAlerts.isNotEmpty;
    final mostSevereAlert = hasActiveAlert ? deviceAlerts.first : null;

    // ★ 2026-08-24 Feature A：長輩目前所在此處的高亮。deviceId 比對邏輯與
    //   上面的 hasActiveAlert 同款（轉字串比對）。🚨 緊急優先：hasActiveAlert
    //   時一律顯示跌倒警報樣式，不疊加這個高亮（decoration／徽章／副標題
    //   三處都先判斷 `!hasActiveAlert`）。
    //   ⚠️ 「設定區域」校準功能移除後新增 `present` 判斷：只比對 deviceId
    //   不夠——`_elderZone` 過期（長輩早已離開鏡頭）時 `deviceId` 可能還留著
    //   上一次的值，`present` 才是後端過期判定後的權威結果，見
    //   `elderZone` 欄位宣告處的說明。
    final String? presentDeviceId = widget.elderZone?['deviceId']?.toString();
    final bool isElderPresent = !hasActiveAlert &&
        widget.elderZone?['present'] == true &&
        presentDeviceId != null &&
        presentDeviceId == deviceId.toString();
    // ⚠️ 括號是必要的：三元運算子的 `?` 緊接著 null-aware index `?[` 會被
    //   解析器誤判成巢狀三元運算式的開頭（`widget.elderZone` 被當成內層
    //   condition），拆成獨立的括號表達式即可消歧義。
    final String? presentZoneName =
        isElderPresent ? (widget.elderZone?['zone'])?.toString() : null;
    final bool showZoneName = presentZoneName != null && presentZoneName != 'unknown';

    // ★ 2026-08-04 第 7 項：語音通道按鈕所需的兩個數值。
    //   任一個解析不出來就不顯示按鈕——寧可少一個功能鍵，也不能送出錯誤的
    //   alert_id / device_id 而把語音權限開到別台監視機上。
    final int? alertId = hasActiveAlert
        ? int.tryParse(
            (mostSevereAlert?['alert_id'] ?? mostSevereAlert?['alertId'])?.toString() ?? '')
        : null;
    final int? numericDeviceId = int.tryParse(deviceId.toString());
    // ★ 2026-08-11 第二十二輪（需求 5）：卡片內的操作主色同樣依會員層級。
    final Color accent = _tierAccentColor();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      // ★ 2026-08-11 第二十二輪（需求 5）：暗色系。跌倒警報的紅色高亮**必須保留**
      //   （§7 護欄：警報視覺不可被弱化），只是把淺紅底換成深紅底、邊框轉亮，
      //   在深色卡片上維持同等的「一眼看到」強度。
      // ★ 2026-08-24 Feature A：新增「長輩目前所在此處」的青色高亮
      //   （isElderPresent），刻意選跟警報紅、線上綠點都明顯不同的色相；
      //   三態優先序＝警報 > 目前所在 > 一般（isElderPresent 本身已內建
      //   `!hasActiveAlert`，這裡的三元判斷只是讓顏色選擇同樣顯式對齊）。
      decoration: BoxDecoration(
        color: hasActiveAlert
            ? const Color(0xFF3F1D1D)
            : (isElderPresent ? const Color(0xFF083344) : const Color(0xFF0F172A)),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasActiveAlert
              ? const Color(0xFFF87171)
              : (isElderPresent ? const Color(0xFF38BDF8) : const Color(0xFF334155)),
          width: (hasActiveAlert || isElderPresent) ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: hasActiveAlert
                ? Colors.red.withValues(alpha: 0.22)
                : (isElderPresent
                    ? const Color(0xFF38BDF8).withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.25)),
            blurRadius: (hasActiveAlert || isElderPresent) ? 12 : 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 設備狀態指示燈
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isOnline ? const Color(0xFF34D399) : const Color(0xFF475569),
              shape: BoxShape.circle,
              boxShadow: isOnline
                  ? [
                      BoxShadow(
                        color: const Color(0xFF34D399).withValues(alpha: 0.5),
                        blurRadius: 6,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 14),
          // 設備名稱
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isOnline ? name : '(離線) $name',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isOnline
                              ? const Color(0xFFE2E8F0)
                              : const Color(0xFF64748B),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (hasActiveAlert) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade500,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _alertTypeLabel(mostSevereAlert?['alert_type'] ?? 'fall'),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ] else if (isElderPresent) ...[
                      // ★ 2026-08-24 Feature A：「長輩在此」徽章，僅在沒有作用中
                      //   警報時顯示——警報優先權比照上面 hasActiveAlert 分支。
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF06B6D4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          '長輩在此',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  hasActiveAlert
                      ? '⚠️ ${_alertTypeLabel(mostSevereAlert?['alert_type'] ?? '')}（信心: ${((mostSevereAlert?['confidence'] ?? 0) * 100).toStringAsFixed(0)}%）'
                      : (isElderPresent
                          ? '📍 目前長輩所在此處${showZoneName ? ' · $presentZoneName' : ''}'
                          : '監視機模式'),
                  style: TextStyle(
                    fontSize: 12,
                    color: hasActiveAlert
                        ? const Color(0xFFFCA5A5)
                        : (isElderPresent
                            ? const Color(0xFF7DD3FC)
                            : const Color(0xFF94A3B8)),
                    fontWeight: (hasActiveAlert || isElderPresent)
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          // 觀看 CCTV 按鈕
          ElevatedButton.icon(
            onPressed: isOnline
                ? () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoCallScreen(
                          roomId: monitorRoomId,
                          targetSocketId: socketId,
                          isEmergency: true,
                          autoStart: true,
                          // ★ 2026-08-05 第十七輪：CCTV 監控檢視改用 pop() 返回本頁
                          //   （互動分頁），不再整個重建 FamilyMainScreen。
                          returnByPop: true,
                          // ★ 2026-08-10 第十九輪（需求 2）：單向監控——不開自己的
                          //   鏡頭、不顯示本地預覽、不給鏡頭類按鈕，只留麥克風。
                          //   全專案唯一可以傳 true 的地方（見 §7 G55）。
                          monitorViewOnly: true,
                          // ★ 2026-08-26：補上 `monitorDeviceName`，讓
                          //   [Signaling.onMonitorRemoved] 能精準比對「被移除的是不是
                          //   我正在看的這一台」。`name` 就是這張卡片本身的
                          //   `device['deviceName']`——與下方 PopupMenuButton 呼叫
                          //   `_showDeleteMonitorDeviceDialog(name.toString())` 用的是
                          //   同一個字串，而後端刪除時會把收到的 `device_name`
                          //   查詢參數（僅 `.strip()`）原樣寫回 `monitor-removed` 的
                          //   `deviceName` 欄位（見 `routers/pairing.py::delete_monitor_device`），
                          //   故兩者保證一致。未傳入前，比對退回只認 elderId（見該欄位
                          //   宣告處），會讓刪除同一長輩底下的「另一台」也誤關本畫面。
                          monitorDeviceName: name.toString(),
                        ),
                      ),
                    ).then((_) {
                      // ★ 2026-08-16（需求 2）：查看完監視畫面返回後，通知父層清除該設備的警報狀態，還原介面樣式與動畫
                      widget.onAlertDismissed?.call(deviceId);
                    });
                  }
                : null,
            icon: const Icon(Icons.videocam_rounded, size: 18),
            label: const Text('觀看 CCTV'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isOnline
                  ? accent.withValues(alpha: 0.16)
                  : const Color(0xFF334155),
              foregroundColor: isOnline ? accent : const Color(0xFF64748B),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // ★ 2026-08-10 第十九輪（需求 3）：家屬端也能刪除監視機與改名。
          //   離線裝置同樣要能操作（離線殘影正是最需要被刪掉的情況）。
          PopupMenuButton<String>(
            tooltip: '管理監視機',
            // ★ 2026-08-11 第二十二輪（需求 5）：選單本身預設是亮底，
            //   在暗色卡片上點開會整片刺眼，一併轉深。
            color: const Color(0xFF1E293B),
            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8)),
            onSelected: (value) {
              if (value == 'rename') {
                _showRenameMonitorDeviceDialog(name.toString());
              } else if (value == 'delete') {
                _showDeleteMonitorDeviceDialog(name.toString());
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'rename',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.drive_file_rename_outline_rounded,
                      color: Color(0xFFCBD5E1)),
                  title: Text('重新命名',
                      style: TextStyle(color: Color(0xFFE2E8F0))),
                ),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded, color: Color(0xFFF87171)),
                  title: Text('刪除監視機', style: TextStyle(color: Color(0xFFF87171))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ★ 2026-08-10 第十九輪（需求 3）：取得目前長輩的原始 elder_id。
  /// 與 `_buildMonitorDeviceCard` 產生 `monitorRoomId` 的來源一致。
  String? get _rawElderId {
    final elder = widget.currentElder;
    if (elder == null) return null;
    return elder.elderId ?? elder.id.toString();
  }

  /// ★ 2026-08-10 第十九輪（需求 3）：從卡片直接刪除監視機。
  Future<void> _showDeleteMonitorDeviceDialog(String deviceName) async {
    final elderId = _rawElderId;
    final userId = widget.userId;
    if (elderId == null || userId == null) {
      _toast('缺少長輩或使用者資訊，無法刪除');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('確認刪除'),
        content: Text('確定要移除監視機「$deviceName」嗎？\n該設備將被登出並停止推送畫面。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await ApiService.deleteMonitorDevice(
      elderId: elderId,
      deviceName: deviceName,
      userId: userId,
    );
    if (!mounted) return;
    if (ok) {
      _toast('已刪除監視機「$deviceName」');
      // 後端刪除後會廣播 elder-devices-update；這裡再請父層主動刷新一次，
      // 避免監視機已離線（收不到踢除）時清單留著殘影。
      widget.onDevicesChanged?.call();
    } else {
      _toast('刪除失敗，請稍後再試');
    }
  }

  /// ★ 2026-08-10 第十九輪（需求 3）：從卡片重新命名監視機。
  /// 後端的 device_id 由名稱 crc32 導出（`services/monitor_identity.py`），
  /// 改名即改身分，所以一律走 `PATCH /api/pairing/monitor_device` 由後端
  /// 一次更新所有以名稱／id 為鍵的儲存（見 §7 G57），不要在前端自行拼湊。
  Future<void> _showRenameMonitorDeviceDialog(String oldName) async {
    final elderId = _rawElderId;
    final userId = widget.userId;
    if (elderId == null || userId == null) {
      _toast('缺少長輩或使用者資訊，無法重新命名');
      return;
    }

    final controller = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('重新命名監視機'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: '監視機名稱',
            hintText: '例如：客廳、房間',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF59B294),
              foregroundColor: Colors.white,
            ),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (!mounted) return;
    if (newName == null || newName.isEmpty || newName == oldName) return;

    final result = await ApiService.renameMonitorDevice(
      elderId: elderId,
      userId: userId,
      oldDeviceName: oldName,
      newDeviceName: newName,
    );
    if (!mounted) return;
    if (result != null) {
      _toast('已將「$oldName」改名為「$newName」');
      widget.onDevicesChanged?.call();
    } else {
      _toast('重新命名失敗，名稱可能已被使用');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// ★ 警報類型中文標籤（移植自 family_dashboard_view.dart 第 1526 行 _alertTypeLabel）
  String _alertTypeLabel(String type) {
    const map = {
      'fall': '跌倒',
      'prolonged_inactivity': '久未活動',
      'lying_down': '倒地',
      'crawl': '爬行',
    };
    return map[type] ?? type;
  }

  /// 設備數量達上限時的警告卡片（移植自 family_dashboard_view.dart 第 1537 行 _buildDeviceLimitWarning）
  Widget _buildDeviceLimitWarning() {
    // ★ 2026-08-11 第二十二輪（需求 5）：與監視機卡片同一張深色卡內，一併轉深底暖黃。
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2A0B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF92400E)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFBBF24), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已達 ${widget.tierDisplayName} 設備上限 (${widget.devicesMax} 台)',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFCD34D),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '升級方案以新增更多監視機',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12,
                    color: const Color(0xFFFDE68A),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => FamilySubscriptionScreen()),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFBBF24),
            ),
            child: Text(
              '升級',
              style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  /// ★ 2026-08-11 第二十二輪（需求 5）：會員層級主色——**全分頁唯一來源**。
  ///
  /// 使用者指定：一般會員綠色、黃金會員金黃色、鑽石會員亮藍色。
  /// 這裡刻意比 2026-08-04 第 6 項的原色（`0xFFC9911B` / `0xFF4A7FD9` / `0xFF59B294`）
  /// 更亮一階——那組是為**白底卡片**挑的，遠端視訊監控改成 `0xFF1E293B` 深底之後
  /// 對比度不足（尤其黃金的暗金會糊在深底上）。鑽石的 `0xFF38BDF8` 同時也是
  /// `family_main_screen.dart` 底部導覽列選中態的主色，兩處一致。
  ///
  /// ⚠️ 未知層級一律退回一般會員的綠色，**不可拋例外**——`tierLevel` 來自後端訂閱
  ///   查詢，查詢失敗時是 `'free'` 以外的任意字串，不能因此讓整個分頁白畫面。
  Color _tierAccentColor() {
    return switch (widget.tierLevel) {
      'gold' => const Color(0xFFF5C451),    // 黃金會員 — 金黃
      'diamond' => const Color(0xFF38BDF8), // 鑽石會員 — 亮藍
      _ => const Color(0xFF10B981),         // 一般會員（免費）— 綠
    };
  }

  /// ★ Task B4：訂閱層級徽章 — 點擊導向訂閱頁（參考 family_dashboard_view.dart
  /// 第 649 行 _buildTierBadge 與第 1578 行 _buildDeviceLimitWarning 的既有導航寫法）。
  /// 顏色與遠端視訊監控的 ICON 共用 [_tierAccentColor]，避免同一畫面出現兩種「黃金色」。
  Widget _buildTierBadge() {
    final Color color = _tierAccentColor();
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FamilySubscriptionScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspace_premium_rounded, size: 16, color: color),
            const SizedBox(width: 6),
            // ★ 2026-09-01 第三十九輪（RenderFlex 溢位修復）：tierDisplayName 是
            // 會員層級顯示名稱，長度不可控（一般／黃金／鑽石之外，未知層級或未來
            // 新增的層級名稱長度無法保證），包 Flexible 可收縮。此 Row 位於
            // Column 之下（非另一個 Row 的非 flex 手足），寬度約束是有界的，
            // 包 Flexible 不會有 G63 所警告的無界寬度 assertion 風險。
            Flexible(
              child: Text(
                widget.tierDisplayName,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansTc(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }
}
