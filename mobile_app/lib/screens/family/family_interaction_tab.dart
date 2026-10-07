import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/elder.dart';
import '../../services/signaling.dart';
import '../../services/api_service.dart';
import '../../theme/family_theme.dart';
import '../../widgets/ui/ui.dart';
import '../video_call_screen.dart';
import 'family_ai_copilot_screen.dart';
import 'family_subscription_screen.dart';
import '../elder_community_screen.dart';
import 'family_friend_feed_body.dart';
import 'widgets/daily_question_card.dart';
import 'widgets/fam_interaction_ui.dart';
import 'widgets/fam_ui.dart';
import '../../utils/display_text.dart';

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

  /// ★ 2026-10-07 每日一問：父層收到 `daily-answer` 時遞增，推給每日一問卡片重讀。
  final int dailyRefreshToken;

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
    this.dailyRefreshToken = 0,
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

class _FamilyInteractionTabState extends State<FamilyInteractionTab>
    with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;
  /// 本次開啟分頁期間已送出的留言（僅畫面顯示用，不持久化、不打 API）。
  final List<({String text, String time})> _sentMessages = [];
  List<Map<String, dynamic>> _reminders = [];
  bool _isLoadingReminders = false;

  final Set<int> _audioBridgeChecked = {};
  final Set<int> _audioBridgePending = {};
  final Map<int, String> _audioBridgeExpire = {};
  Timer? _monitorBindPollTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchReminders();
    _syncAudioBridgeForAlerts();
  }

  // ── 重新整理三種觸發（下拉／切回此分頁／App 回前景）共用 ──
  // 本分頁在家屬主畫面的 IndexedStack 底下被保活，initState 只跑一次；
  // IndexedStack 會讓離屏的子樹 TickerMode 關閉，因此用它判斷「目前是否可見」。
  /// 上一次記錄的可見狀態；null 代表第一次 didChangeDependencies（initState 已載入，不重複載）。
  bool? _wasVisible;
  bool _visible = true;
  bool _isRefreshing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    final was = _wasVisible;
    _wasVisible = _visible;
    // 不可見 → 可見：切回此分頁就重讀（不節流，由 _isRefreshing 擋同時重複請求）
    if (was == false && _visible) _refreshAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回前景時只刷新目前可見的分頁，離屏的分頁等切回來時再刷
    if (state == AppLifecycleState.resumed && _visible && mounted) {
      _refreshAll();
    }
  }

  /// 統一的重新整理入口：只呼叫本分頁既有的載入函式。
  /// 監控裝置清單由父層持有，經 [FamilyInteractionTab.onDevicesChanged]
  /// 請父層重讀（沿用刪除／改名後既有的同一個回呼）。
  Future<void> _refreshAll() async {
    if (_isRefreshing || !mounted) return;
    _isRefreshing = true;
    try {
      widget.onDevicesChanged?.call();
      await Future.wait([
        _fetchReminders(),
        _syncAudioBridgeForAlerts(),
      ]);
    } finally {
      _isRefreshing = false;
    }
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
        _toast('已刪除該筆提醒卡片', error: true);
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
        _toast('已即時推送廣播「$title」至長輩端平板', success: true);
      } else {
        // ★ 2026-08-31 第三十八輪：sendHeartbeat 在 socket 未連線時回傳 false，
        //   之前無條件顯示成功提示（謊報成功），改為顯示失敗提示。
        _toast('目前未連線，請稍後再試', error: true);
      }
    } catch (e) {
      debugPrint("❌ Broadcast error: $e");
    }
  }

  Future<void> _showAddReminderDialog({Map<String, dynamic>? existingReminder}) async {
    if (widget.currentElder == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    // ★ 第五項需求（家屬好友系統）順手修復：原本讀不到 caregiver_id 時會
    // 兜底成寫死的 family_id 1，導致新增的提醒被歸屬到別人的帳號。讀不到就
    // 顯示明確錯誤並不開對話框，不得用猜測值兜底（比照下方 _buildCommunitySection
    // 已修過的同型別寫法）。
    final familyId = prefs.getInt('caregiver_id');
    if (familyId == null) {
      _toast('無法取得您的帳號 ID，請重新登入後再試');
      return;
    }

    final bool isEditing = existingReminder != null;
    final String elderIdStr = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();
    final TextEditingController titleCtrl = TextEditingController(text: existingReminder?['title'] ?? '');
    final TextEditingController noteCtrl = TextEditingController(text: existingReminder?['note'] ?? '');

    TimeOfDay selectedTime = TimeOfDay.now();
    if (isEditing && existingReminder['time_str'] != null) {
      try {
        final parts = existingReminder['time_str'].toString().split(':');
        if (parts.length >= 2) {
          selectedTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
      } catch (_) {}
    }

    DateTime? selectedDate = DateTime.now();
    if (isEditing && existingReminder['start_date'] != null && existingReminder['start_date'].toString().isNotEmpty) {
      try {
        selectedDate = DateTime.parse(existingReminder['start_date']);
      } catch (_) {}
    } else if (isEditing && (existingReminder['start_date'] == null || existingReminder['start_date'].toString().isEmpty)) {
      selectedDate = null;
    }

    String selectedCategory = existingReminder?['category'] ?? 'medication';
    String selectedRepeat = existingReminder?['repeat_days'] ?? '每天';

    // 2026-10 新設計：改用 UbanDialog（表單欄位與送出內容與改版前完全相同；
    // 類別／重複頻率由下拉與圖示膠囊改成純文字膠囊，選項集合不變）。
    final bool? created = await showUbanDialog<bool>(
      context,
      (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final c = UbanColors.of(context);
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

            const categories = <(String, String)>[
              ('medication', '用藥'),
              ('hospital', '看診'),
              ('water', '飲水'),
              ('exercise', '運動'),
              ('custom', '叮嚀'),
            ];
            const repeats = ['每天', '週一至週五', '每週三', '單次'];

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                famDialogTitle(c, isEditing ? '編輯遠端提醒' : '新增遠端提醒'),
                const SizedBox(height: 16),
                _fieldLabel(c, '提醒類別'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (key, label) in categories)
                      FamFilterChip(
                        label: label,
                        selected: selectedCategory == key,
                        onTap: () => setDialogState(() => selectedCategory = key),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                UbanTextField(
                  label: '提醒標題',
                  controller: titleCtrl,
                  hintText: '例如: 吃高血壓藥、台大看診',
                ),
                const SizedBox(height: 16),
                _fieldLabel(c, '提醒日期'),
                _pickerField(
                  c,
                  dateText,
                  () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setDialogState(() => selectedDate = picked);
                  },
                ),
                const SizedBox(height: 16),
                _fieldLabel(c, '提醒時間'),
                _pickerField(
                  c,
                  "${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}",
                  () async {
                    final tod = await showTimePicker(context: context, initialTime: selectedTime);
                    if (tod != null) setDialogState(() => selectedTime = tod);
                  },
                ),
                const SizedBox(height: 16),
                _fieldLabel(c, '重複頻率'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in repeats)
                      FamFilterChip(
                        label: r,
                        selected: selectedRepeat == r,
                        onTap: () => setDialogState(() => selectedRepeat = r),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                UbanTextField(
                  label: '備註說明（選填）',
                  controller: noteCtrl,
                  hintText: '例如: 飯後溫開水服用一顆',
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: FamButton(
                        label: '取消',
                        kind: FamButtonKind.ghost,
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FamButton(
                        label: isEditing ? '確認儲存' : '確認新增',
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
                                famSnackBar(context, isEditing ? '儲存提醒失敗' : '新增提醒失敗', error: true),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ],
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

  /// 對話框內的欄位小標（對應 UbanTextField 的 label 樣式）。
  Widget _fieldLabel(UbanColors c, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: famText(c.text2, 15, weight: FontWeight.w700)),
      );

  /// 日期／時間的點選欄位（外觀比照 UbanTextField：surface 底、1.5px line 邊框、圓角 18）。
  Widget _pickerField(UbanColors c, String text, VoidCallback onTap) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line, width: 1.5),
        ),
        child: Text(text, style: famText(c.text, 16, weight: FontWeight.w700)),
      ),
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
        _toast('已開啟語音通道，30 分鐘內可對該監視機說話', success: true);
      } else {
        _toast('開啟語音通道失敗，請稍後再試');
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

    return FamButton(
      label: isPending
          ? '開啟中…'
          : isOpen
              ? '語音通道已開啟（$remainText）'
              : '開啟語音通道 30 分鐘',
      kind: isOpen ? FamButtonKind.tonal : FamButtonKind.outline,
      height: 38,
      expand: false,
      onPressed: isPending ? null : () => _openAudioBridge(alertId, deviceId),
    );
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      _toast('無法取得您的帳號 ID');
      return;
    }

    final String rawId = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();
    final TextEditingController nameCtrl = TextEditingController(text: '客廳攝影機');
    
    if (!mounted) return;
    
    final bool? confirm = await showUbanDialog<bool>(
      context,
      (ctx) {
        final c = UbanColors.of(ctx);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            famDialogTitle(c, '新增監控設備'),
            const SizedBox(height: 8),
            Text('請輸入此監控設備的名稱：', style: famText(c.text2, 15, height: 1.5)),
            const SizedBox(height: 14),
            UbanTextField(
              controller: nameCtrl,
              hintText: '例如: 客廳、臥室',
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: FamButton(
                    label: '取消',
                    kind: FamButtonKind.ghost,
                    onPressed: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FamButton(
                    label: '產生代碼',
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        );
      },
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

      showUbanDialog<void>(
        context,
        (ctx) {
          codeDialogContext = ctx;
          final c = UbanColors.of(ctx);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              famDialogTitle(c, '設備配對碼已產生'),
              const SizedBox(height: 10),
              Text(
                '請在要作為攝影機的備用手機上，安裝 Uban 長輩版並選擇「作為監控設備登入」，然後輸入以下 6 位數代碼：',
                style: famText(c.text2, 15, height: 1.5),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(18),
                ),
                // 6 碼定長代碼：用 FittedBox 縮放而非省略號——被截斷會誤導使用者。
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    code,
                    style: famText(c.brandStrong, 32,
                        weight: FontWeight.w900, letterSpacing: 8, tabular: true),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '此代碼將在 15 分鐘後失效。',
                style: famText(c.warm, 13, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '對方輸入完成後，本視窗會自動關閉。',
                style: famText(c.text2, 13, height: 1.4),
              ),
              const SizedBox(height: 20),
              FamButton(
                label: '完成',
                onPressed: () => Navigator.pop(ctx),
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
      _toast('產生配對碼失敗，請稍後再試', error: true);
    }
  }

  void _makeVideoCall() {
    if (widget.currentElder == null) {
      _toast('請先在頂部選擇要關照的長輩');
      return;
    }

    HapticFeedback.mediumImpact();

    final String rawId = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();
    // 2026-10 新設計：選擇通話方式改用 UbanSheet（設計稿 #sh-callpick）。
    // 兩個選項的行為與改版前逐項相同：先 pop 面板、再 push VideoCallScreen，
    // 建構參數（roomId／targetSocketId／autoStart／isEmergency）不變。
    // useRootNavigator:false 沿用原本 showModalBottomSheet 的預設（非 root）。
    showUbanSheet<void>(
      context,
      (context) {
        final c = UbanColors.of(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('選擇通話方式', style: famText(c.text, 20, weight: FontWeight.w900)),
            const SizedBox(height: 12),
            // 一般通話按鈕
            _buildCallOptionButton(
              title: '一般視訊通話',
              subtitle: '長輩需手動接聽後建立連線',
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
            const SizedBox(height: 8),
            // 緊急強制通話按鈕
            _buildCallOptionButton(
              title: '緊急強制通話',
              subtitle: '強制喚醒長輩設備並自動接聽。只在聯絡不到、擔心出事時使用。',
              titleColor: c.danger,
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
          ],
        );
      },
      useRootNavigator: false,
    );
  }

  /// 2026-10 新增：`.callhero` 的「語音通話」大卡。建構參數比照 ui-map §5.5 配方
  /// （一般通話、autoStart、`isVideoCall: false`＝純語音）。
  void _makeVoiceCall() {
    if (widget.currentElder == null) {
      _toast('請先在頂部選擇要關照的長輩');
      return;
    }

    HapticFeedback.mediumImpact();
    final String rawId = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoCallScreen(
          roomId: 'comm_elder_$rawId',
          targetSocketId: null,
          autoStart: true,
          isEmergency: false,
          isVideoCall: false,
        ),
      ),
    );
  }

  /// `#sh-callpick` 的 `.action` 列（無圖示）；點擊先觸覺回饋再執行 [onTap]。
  Widget _buildCallOptionButton({
    required String title,
    required String subtitle,
    Color? titleColor,
    required VoidCallback onTap,
  }) {
    return FamAction(
      flat: true,
      title: title,
      subtitle: subtitle,
      titleColor: titleColor,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
    );
  }

  void _sendMessage(String text) async {
    if (widget.currentElder == null) {
      _toast('請先在頂部選擇要關照的長輩');
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
        final now = DateTime.now();
        setState(() {
          _sentMessages.add((
            text: messageText,
            time:
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
          ));
          if (_sentMessages.length > 3) _sentMessages.removeAt(0);
        });
        _messageController.clear();
        _toast('已傳送留言給 ${widget.currentElder!.displayName}', success: true);
      } else {
        // ★ 2026-08-31 第三十八輪：sendHeartbeat 在 socket 未連線時回傳 false，
        //   之前無條件顯示成功提示（謊報成功），改為顯示失敗提示；訊息保留在輸入框，不清空。
        _toast('目前未連線，請稍後再試', error: true);
      }
    } catch (e) {
      if (mounted) {
        _toast('傳送失敗: $e', error: true);
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

    // 2026-10 新設計（design_prototype/family.html #tabInteract）：
    // 通話大卡 → AI 照護秘書 → 留言 → 時光牆 → 遠端監控 → 遠端提醒，區塊間距 14。
    final refreshColors = UbanColors.of(context);
    return RefreshIndicator(
      color: refreshColors.brandFill,
      backgroundColor: refreshColors.surface,
      onRefresh: _refreshAll,
      child: CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
              16, 8, 16, UbanGlassNavBar.totalHeight + MediaQuery.paddingOf(context).bottom + 16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // 1. 視訊／語音通話大卡
              _buildCallSection(),
              const SizedBox(height: 14),

              // 2. AI 照護秘書入口（對話建立排程與近況速報）
              _buildAiCopilotSection(),
              const SizedBox(height: 14),

              // 2b. ★ 2026-10-07 每日一問：今日題目、長輩回答與出題入口
              DailyQuestionCard(
                currentElder: widget.currentElder,
                userId: widget.userId,
                refreshToken: widget.dailyRefreshToken,
              ),
              const SizedBox(height: 14),

              // 3. 留言給長輩（單行輸入＋送出）
              _buildMessageSection(),
              const SizedBox(height: 14),

              // 4. 家庭生活社群時光牆（雙向動態互動）
              _buildCommunitySection(),
              const SizedBox(height: 14),

              // 5. 遠端監控區
              _buildMonitorSection(),
              const SizedBox(height: 14),

              // 6. 遠端提醒與用藥行程
              _buildReminderSection(),
            ]),
          ),
        ),
      ],
      ),
    );
  }

  Widget _buildAiCopilotSection() {
    final elderName = widget.currentElder?.displayName ?? '長輩';

    return FamAction(
      key: widget.aiCopilotKey,
      title: 'AI 照護秘書',
      subtitle: '問$elderName今天過得怎樣、用一句話排吃藥提醒',
      trailing: FamAction.chevron(context),
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
    );
  }

  /// `.msgs`＋`.msgbox`：留言給長輩。送出走 [_sendMessage]（signaling.sendHeartbeat，
  /// 行為與原版相同；原版此函式沒有任何 UI 入口，2026-10 依設計稿補上）。
  Widget _buildMessageSection() {
    final c = UbanColors.of(context);
    final name = widget.currentElder?.displayName ?? '長輩';
    return FamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FamSecHead(title: '留言給$name'),
          if (_sentMessages.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final m in _sentMessages)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FamChatBubble(
                  mine: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.text,
                          style: famText(c.brandStrong, 14.5, height: 1.5)),
                      Text('您・${m.time}', style: famText(c.text3, 11.5)),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FamInput(
                  controller: _messageController,
                  hintText: '寫點什麼給$name',
                  textInputAction: TextInputAction.send,
                  onSubmitted: _isSending ? null : _sendMessage,
                ),
              ),
              const SizedBox(width: 8),
              FamRoundBtn(
                icon: Icons.send_rounded,
                tooltip: '送出',
                onTap: _isSending
                    ? null
                    : () => _sendMessage(_messageController.text),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommunitySection() {
    return FamAction(
      key: widget.communityKey,
      title: '家庭生活時光牆',
      subtitle: '瀏覽長輩心情、分享生活照片與留言關心',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FamChip(label: '雙向交流', tone: FamTone.brand),
          const SizedBox(width: 4),
          FamAction.chevron(context),
        ],
      ),
      onTap: () async {
        HapticFeedback.lightImpact();
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        // ★ 第五項需求（家屬好友系統）順手修復：原本讀不到 caregiver_id
        // 時會兜底成寫死的 family_id 2，導致使用者用別人的家庭身分發文
        // 到別人的家庭留言板。讀不到就顯示明確錯誤並不開畫面，不得用
        // 猜測值兜底。
        final familyId = prefs.getInt('caregiver_id');
        if (familyId == null) {
          _toast('無法取得您的帳號 ID，請重新登入後再試');
          return;
        }
        final userName = prefs.getString('caregiver_name') ?? prefs.getString('user_name') ?? '家人';

        Navigator.push(
          context,
          MaterialPageRoute(
            // 2026-10：ElderCommunityScreen 長輩／家屬共用、內部不動；家屬端 push
            // 時在外層掛 FamilyThemeScope，讓「朋友」標籤內的 FamilyFriendFeedBody
            // 與其開出的 sheet／加好友頁都吃得到家屬主題。
            builder: (context) => FamilyThemeScope(
              child: ElderCommunityScreen(
                userId: familyId,
                userName: userName,
                familyId: familyId,
                // ★ 第五項需求（家屬好友系統）：家屬跟進長輩端的「家庭／朋友」
                // 頂部標籤——第一個標籤文字改成「家庭」（長輩端維持「家人」不變，
                // 見 ElderCommunityScreen.familyTabLabel 預設值），朋友標籤內容
                // 換成家屬自己的 FamilyFriendFeedBody，與長輩朋友圈資料互不相通。
                showFriendTab: true,
                familyTabLabel: '家庭',
                friendTabContent: FamilyFriendFeedBody(
                  familyId: familyId,
                  familyName: userName,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoElderPlaceholder() {
    final c = UbanColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '尚未選擇長輩',
              style: famText(c.text, 18, weight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              '請點擊頂部長輩選單來載入長輩的互動功能',
              style: famText(c.text2, 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// `.callhero`：兩張通話大卡（視訊 filled／語音 tonal）。
  /// 視訊仍開「選擇通話方式」面板（一般視訊／緊急強制通話）。
  Widget _buildCallSection() {
    return IntrinsicHeight(
      key: widget.callSectionKey,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: FamCallBig(
              title: '視訊通話',
              subtitle: '長輩接聽後才會接通',
              icon: Icons.videocam_rounded,
              onTap: _makeVideoCall,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FamCallBig(
              title: '語音通話',
              subtitle: '不開鏡頭，省流量',
              icon: Icons.call_rounded,
              filled: false,
              onTap: _makeVoiceCall,
            ),
          ),
        ],
      ),
    );
  }

  /// 遠端提醒與用藥行程（原 `_buildMessageSection`，名稱與內容不符，改名）。
  Widget _buildReminderSection() {
    final c = UbanColors.of(context);

    return FamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FamSecHead(
            title: '遠端提醒',
            trailing: FamMore(label: '新增', onTap: _showAddReminderDialog),
          ),
          const SizedBox(height: 6),
          if (_isLoadingReminders)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: CircularProgressIndicator(color: c.brand, strokeWidth: 2.5),
              ),
            )
          else if (_reminders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  Text(
                    '目前尚無排程提醒',
                    textAlign: TextAlign.center,
                    style: famText(c.text, 15, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '點擊右上角「新增」為長輩設定用藥或看診時間',
                    textAlign: TextAlign.center,
                    style: famText(c.text2, 13, height: 1.5),
                  ),
                ],
              ),
            )
          else
            for (var index = 0; index < _reminders.length; index++)
              _buildReminderRow(_reminders[index], index),
        ],
      ),
    );
  }

  /// `.devrow`：類別色點｜標題＋時間／重複／備註｜開關；下方是編輯／廣播／刪除三個文字小鈕。
  Widget _buildReminderRow(Map<String, dynamic> r, int index) {
    final c = UbanColors.of(context);
    final bool isActive = r['is_active'] == true || r['is_active'] == 1;
    final cat = r['category'] ?? 'custom';

    // 暖色只給「待處理」：用藥＝warm（待確認打卡）、看診＝info、其餘＝brand；停用＝text3。
    final Color dot = !isActive
        ? c.text3
        : cat == 'medication'
            ? c.warm
            : cat == 'hospital'
                ? c.info
                : c.brandFill;

    final String time = (r['time_str'] ?? '00:00').toString();
    final String repeat = (r['repeat_days'] ?? '每天').toString();
    final String date = (r['start_date'] != null && r['start_date'].toString().isNotEmpty)
        ? _formatReminderDate(r['start_date'])
        : '';
    final String note = (r['note'] != null && r['note'].toString().isNotEmpty) ? r['note'].toString() : '';
    final String meta = [time, repeat, if (date.isNotEmpty) date].join('・');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: index == 0 ? null : Border(top: BorderSide(color: c.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FamDot(color: dot),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stripEmoji((r['title'] ?? '').toString()),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: famText(isActive ? c.text : c.text3, 15.5, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: famText(isActive ? c.text2 : c.text3, 12.5, tabular: true),
                    ),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        note,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: famText(c.text3, 12.5, height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              UbanSwitch(value: isActive, onChanged: (_) => _toggleReminder(index)),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FamSmallBtn(
                  label: '編輯',
                  onTap: () => _showAddReminderDialog(existingReminder: r),
                ),
                FamSmallBtn(
                  label: '立即廣播',
                  onTap: () => _broadcastReminder(r),
                ),
                FamSmallBtn(
                  label: '刪除',
                  danger: true,
                  onTap: () => _deleteReminder(r['id']),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatReminderDate(dynamic rawDate) {
    if (rawDate == null) return '';
    final str = rawDate.toString().trim();
    if (str.isEmpty) return '';
    // 若為 YYYY-MM-DD 或 YYYY/MM/DD，格式化為 MM/DD 精簡顯示防溢出
    final match = RegExp(r'^\d{4}[-/](\d{1,2}[-/]\d{1,2})').firstMatch(str);
    if (match != null) {
      return match.group(1)!.replaceAll('-', '/');
    }
    return str.replaceAll('-', '/');
  }

  /// 遠端監控卡（設計稿：sec-head＋層級徽章、`.devrow` 設備列、`.quota` 方案上限）。
  Widget _buildMonitorSection() {
    final c = UbanColors.of(context);
    final reachedLimit = widget.monitorDevices.length >= widget.devicesMax;
    final String rawId = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();
    final String monitorRoomId = 'monitor_elder_$rawId';
    final int count = widget.monitorDevices.length;

    return FamCard(
      key: widget.monitorSectionKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FamSecHead(
            title: '遠端視訊監控',
            // ★ Task B4：訂閱層級徽章（點擊進入訂閱頁）。tierDisplayName 長度不可控，
            //   限寬並在徽章內省略（鐵律 #14）。
            trailing: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: FamTier(
                label: widget.tierDisplayName,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => FamilySubscriptionScreen()),
                  );
                },
              ),
            ),
          ),
          // 活躍警報計數（待處理 → 警示色）
          if (widget.activeAlerts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FamChip(
                label: '${widget.activeAlerts.length} 警報',
                tone: FamTone.danger,
                dot: true,
              ),
            ),
          ],
          const SizedBox(height: 6),
          // ── 設備列表 or 空狀態 ──
          if (widget.monitorDevices.isEmpty)
            _buildNoMonitorDevice()
          else ...[
            for (var i = 0; i < widget.monitorDevices.length; i++)
              _buildMonitorDeviceCard(
                widget.monitorDevices[i],
                monitorRoomId: monitorRoomId,
                first: i == 0,
              ),
            // 達到上限提示
            if (reachedLimit)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _buildDeviceLimitWarning(),
              ),
          ],
          const SizedBox(height: 10),
          FamQuota(
            label: '設備 $count/${widget.devicesMax}',
            value: widget.devicesMax > 0 ? count / widget.devicesMax : 0,
            // 達上限＝等待升級的待處理狀態，才用暖色。
            color: reachedLimit ? c.warm : c.brand,
            trailing: FamMore(
              label: '新增設備',
              onTap: () {
                HapticFeedback.lightImpact();
                _showAddMonitorDialog();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 空狀態：尚未連接任何監視機設備（移植自 family_dashboard_view.dart 第 1345 行 _buildNoMonitorDevice）
  Widget _buildNoMonitorDevice() {
    final c = UbanColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '尚未連接任何監視機設備',
            textAlign: TextAlign.center,
            style: famText(c.text, 15, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '請至「設定」配對家庭監控裝置',
            textAlign: TextAlign.center,
            style: famText(c.text2, 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  /// 單一監視機裝置列（移植自 family_dashboard_view.dart 第 1382 行 _buildMonitorDeviceCard，
  /// 含依 hasActiveAlert 判定的跌倒警報高亮；2026-10 起改 `.devrow` 外觀）。
  Widget _buildMonitorDeviceCard(Map device, {required String monitorRoomId, bool first = false}) {
    final c = UbanColors.of(context);

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

    final String? presentDeviceId = widget.elderZone?['deviceId']?.toString();
    final bool isElderPresent = !hasActiveAlert &&
        widget.elderZone?['present'] == true &&
        presentDeviceId != null &&
        presentDeviceId == deviceId.toString();
    final String? presentZoneName =
        isElderPresent ? (widget.elderZone?['zone'])?.toString() : null;
    final bool showZoneName = presentZoneName != null && presentZoneName != 'unknown';

    final String status = hasActiveAlert
        ? '${_alertTypeLabel(mostSevereAlert?['alert_type'] ?? '')}（信心: ${((mostSevereAlert?['confidence'] ?? 0) * 100).toStringAsFixed(0)}%）'
        : (isElderPresent
            ? '目前長輩所在此處${showZoneName ? ' · $presentZoneName' : ''}'
            : '監視機模式');

    // 語音通道（`.smallbtn 對講`）：只在該監視機有作用中警報時出現，
    // alertId 取法與 _syncAudioBridgeForAlerts 一致；行為＝開啟 30 分鐘。
    final int? bridgeAlertId = int.tryParse(
      (mostSevereAlert?['alert_id'] ?? mostSevereAlert?['alertId'])?.toString() ?? '',
    );
    final int? bridgeDeviceId = int.tryParse(deviceId.toString());
    final Widget? bridgeBtn = (hasActiveAlert &&
            bridgeAlertId != null &&
            bridgeDeviceId != null &&
            widget.userId != null)
        ? _buildAudioBridgeButton(bridgeAlertId, bridgeDeviceId)
        : null;

    final row = FamDevRow(
      first: first,
      dot: hasActiveAlert ? c.danger : (isOnline ? c.brandFill : c.text3),
      highlight: hasActiveAlert
          ? c.dangerContainer
          : (isElderPresent ? c.brandContainer : null),
      title: isOnline ? name.toString() : '(離線) $name',
      titleColor: isOnline ? c.text : c.text3,
      subtitle: status,
      subtitleColor: hasActiveAlert
          ? c.danger
          : (isElderPresent ? c.brandStrong : c.text2),
      subtitleWeight: (hasActiveAlert || isElderPresent) ? FontWeight.w700 : FontWeight.w500,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 觀看 CCTV 按鈕（`.smallbtn`）。
          // ★ 第四十八輪（item 2）：同列有名稱欄與管理選單，名稱欄是 Expanded、按鈕
          //   本身可收縮（FamSmallBtn 文字 ellipsis），避免 360dp＋大字級時溢位
          //   （見 CLAUDE_call-monitor-guardrails.md G159）。
          FamSmallBtn(
            label: '監看',
            onTap: isOnline
                ? () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoCallScreen(
                          roomId: monitorRoomId,
                          targetSocketId: socketId,
                          isEmergency: true,
                          autoStart: true,
                          returnByPop: true,
                          monitorViewOnly: true,
                          monitorDeviceName: name.toString(),
                        ),
                      ),
                    ).then((_) {
                      widget.onAlertDismissed?.call(deviceId);
                    });
                  }
                : null,
          ),
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            tooltip: '管理監視機',
            color: c.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (value) {
              if (value == 'rename') {
                _showRenameMonitorDeviceDialog(name.toString());
              } else if (value == 'delete') {
                _showDeleteMonitorDeviceDialog(name.toString());
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                value: 'rename',
                child: Text('重新命名',
                    style: famText(c.text, 15, weight: FontWeight.w600)),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                child: Text('刪除監視機',
                    style: famText(c.danger, 15, weight: FontWeight.w600)),
              ),
            ],
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: c.surface2, shape: BoxShape.circle),
              child: Icon(Icons.more_horiz_rounded, size: 20, color: c.text2),
            ),
          ),
        ],
      ),
    );
    if (bridgeBtn == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        Padding(
          padding: const EdgeInsets.only(left: 22, bottom: 8),
          child: Align(alignment: Alignment.centerLeft, child: bridgeBtn),
        ),
      ],
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

    final confirmed = await showUbanDialog<bool>(
      context,
      (dialogContext) {
        final c = UbanColors.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            famDialogTitle(c, '確認刪除'),
            const SizedBox(height: 10),
            Text(
              '確定要移除監視機「$deviceName」嗎？\n該設備將被登出並停止推送畫面。',
              style: famText(c.text2, 15, height: 1.5),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: FamButton(
                    label: '取消',
                    kind: FamButtonKind.ghost,
                    onPressed: () => Navigator.pop(dialogContext, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FamButton(
                    label: '刪除',
                    kind: FamButtonKind.danger,
                    onPressed: () => Navigator.pop(dialogContext, true),
                  ),
                ),
              ],
            ),
          ],
        );
      },
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
    final newName = await showUbanDialog<String>(
      context,
      (dialogContext) {
        final c = UbanColors.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            famDialogTitle(c, '重新命名監視機'),
            const SizedBox(height: 14),
            UbanTextField(
              label: '監視機名稱',
              controller: controller,
              autofocus: true,
              maxLength: 40,
              hintText: '例如：客廳、房間',
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: FamButton(
                    label: '取消',
                    kind: FamButtonKind.ghost,
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FamButton(
                    label: '儲存',
                    onPressed: () =>
                        Navigator.pop(dialogContext, controller.text.trim()),
                  ),
                ),
              ],
            ),
          ],
        );
      },
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

  void _toast(String message, {bool error = false, bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      famSnackBar(context, message, error: error, success: success),
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

  /// 設備數量達上限時的提示（移植自 family_dashboard_view.dart 第 1537 行 _buildDeviceLimitWarning）。
  /// 「等待升級」屬待處理，所以是唯一用暖色的地方。
  Widget _buildDeviceLimitWarning() {
    final c = UbanColors.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: c.warmContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已達 ${widget.tierDisplayName} 設備上限 (${widget.devicesMax} 台)',
                  style: famText(c.warm, 14, weight: FontWeight.w700, height: 1.35),
                ),
                const SizedBox(height: 2),
                Text(
                  '升級方案以新增更多監視機',
                  style: famText(c.text2, 12.5, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FamSmallBtn(
            label: '升級',
            filled: true,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => FamilySubscriptionScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
