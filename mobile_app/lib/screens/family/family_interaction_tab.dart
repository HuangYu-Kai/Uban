import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/elder.dart';
import '../../services/signaling.dart';
import '../../services/api_service.dart';
import '../video_call_screen.dart';
import '../camera_screen.dart';

class FamilyInteractionTab extends StatefulWidget {
  final Elder? currentElder;
  final Signaling signaling;

  const FamilyInteractionTab({
    super.key,
    required this.currentElder,
    required this.signaling,
  });

  @override
  State<FamilyInteractionTab> createState() => _FamilyInteractionTabState();
}

class _FamilyInteractionTabState extends State<FamilyInteractionTab> {
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;
  List<Map<String, dynamic>> _reminders = [];
  bool _isLoadingReminders = false;

  @override
  void initState() {
    super.initState();
    _fetchReminders();
  }

  @override
  void didUpdateWidget(covariant FamilyInteractionTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentElder?.id != oldWidget.currentElder?.id ||
        widget.currentElder?.elderId != oldWidget.currentElder?.elderId) {
      _fetchReminders();
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
      await widget.signaling.sendHeartbeat(
        widget.currentElder!.id,
        "⏰ 遠端提醒廣播：$title$note",
        playSound: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已即時推送廣播「$title」至長輩端平板 🔔'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      debugPrint("❌ Broadcast error: $e");
    }
  }

  Future<void> _showAddReminderDialog() async {
    if (widget.currentElder == null) return;
    final prefs = await SharedPreferences.getInstance();
    final familyId = prefs.getInt('caregiver_id');
    if (familyId == null) return;

    final String elderIdStr = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();
    final TextEditingController titleCtrl = TextEditingController();
    final TextEditingController noteCtrl = TextEditingController();
    TimeOfDay selectedTime = TimeOfDay.now();
    DateTime? selectedDate = DateTime.now();
    String selectedCategory = 'medication';
    String selectedRepeat = '每天';

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
                    child: const Icon(Icons.add_alarm_rounded, color: Color(0xFF38BDF8)),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '新增遠端提醒',
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
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
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
                    if (ctx.mounted) {
                      if (res != null && res['status'] == 'success') {
                        Navigator.pop(ctx, true);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('新增提醒失敗: ${res?['message'] ?? '連線失敗'}'),
                            backgroundColor: const Color(0xFFEF4444),
                          ),
                        );
                      }
                    }
                  },
                  child: Text('確認新增', style: GoogleFonts.notoSansTc(color: Colors.white, fontWeight: FontWeight.bold)),
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

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _showAddMonitorDialog() async {
    if (widget.currentElder == null) return;
    final prefs = await SharedPreferences.getInstance();
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
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
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
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('完成'),
            ),
          ],
        ),
      );
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '選擇通話方式',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 24),
                // 一般通話按鈕
                _buildCallOptionButton(
                  title: '一般視訊通話',
                  subtitle: '長輩需手動接聽後建立連線',
                  icon: Icons.video_call_rounded,
                  color: const Color(0xFF3B82F6),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VideoCallScreen(
                          roomId: 'comm_elder_$rawId',
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
                          autoStart: true,
                          isEmergency: true,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                // 單向視訊監控
                _buildCallOptionButton(
                  title: '單向視訊監控',
                  subtitle: '不打擾長輩，靜音查看即時畫面',
                  icon: Icons.visibility_rounded,
                  color: const Color(0xFF8B5CF6),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CameraScreen(
                          roomId: 'monitor_elder_$rawId',
                        ),
                      ),
                    );
                  },
                ),
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
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.7), size: 24),
          ],
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
      await widget.signaling.sendHeartbeat(
        widget.currentElder!.id,
        messageText,
        playSound: true,
      );

      if (mounted) {
        _messageController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已傳送留言給 ${widget.currentElder!.displayName} ✨'),
            backgroundColor: const Color(0xFF10B981),
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

              // 2. 留言發送區（快速短句 + 自訂輸入）
              _buildMessageSection(),
              const SizedBox(height: 20),

              // 3. 遠端監控區（方案 B：未連接獨立攝影機設備預留）
              _buildMonitorSection(),
            ]),
          ),
        ),
      ],
    );
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
                      Row(
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
                          const SizedBox(width: 8),
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
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 21),
                            tooltip: '刪除提醒',
                            onPressed: () => _deleteReminder(r['id']),
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
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
                    ),
                    child: const Icon(
                      Icons.videocam_off_rounded,
                      color: Color(0xFF34D399),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '遠端視訊監控',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            // 仿真監控鏡頭畫面佔位符
            Container(
              height: 220,
              width: double.infinity,
              color: const Color(0xFF0F172A),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 網格底紋模擬數位相機
                  Opacity(
                    opacity: 0.1,
                    child: GridPaper(
                      color: Colors.white,
                      divisions: 1,
                      subdivisions: 1,
                      interval: 40,
                      child: Container(),
                    ),
                  ),
                  // REC 圖示
                  Positioned(
                    top: 14,
                    left: 18,
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'STANDBY',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 中間佔位文字
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.videocam_off_rounded,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 50,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '尚未連接獨立攝影機設備',
                        style: GoogleFonts.notoSansTc(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '請至「設定」配對家庭監控裝置',
                        style: GoogleFonts.notoSansTc(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _showAddMonitorDialog();
                  },
                  icon: const Icon(Icons.add_a_photo_rounded, size: 20),
                  label: const Text('新增並連接監控設備'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F5F9),
                    foregroundColor: const Color(0xFF475569),
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
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }
}
