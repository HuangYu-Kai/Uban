import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/api_service.dart';

class HealthReminderScreen extends StatefulWidget {
  final String elderId;
  final String elderName;
  final int familyId;

  const HealthReminderScreen({
    super.key,
    required this.elderId,
    this.elderName = '長輩',
    this.familyId = 1,
  });

  @override
  State<HealthReminderScreen> createState() => _HealthReminderScreenState();
}

class _HealthReminderScreenState extends State<HealthReminderScreen> {
  bool _isLoading = true;
  List<dynamic> _reminders = [];

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    setState(() => _isLoading = true);
    final list = await ApiService.getElderReminders(widget.elderId);
    if (mounted) {
      setState(() {
        _reminders = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleToggle(int reminderId) async {
    HapticFeedback.lightImpact();
    final success = await ApiService.toggleElderReminder(reminderId);
    if (success) {
      _loadReminders();
    }
  }

  Future<void> _handleDelete(int reminderId, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
            const SizedBox(width: 8),
            Text('刪除排程提醒', style: GoogleFonts.notoSansTc(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('確定要刪除「$title」排程提醒嗎？', style: GoogleFonts.notoSansTc(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('取消', style: GoogleFonts.notoSansTc(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(c, true),
            child: Text('確定刪除', style: GoogleFonts.notoSansTc(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await ApiService.deleteElderReminder(reminderId);
      if (success) {
        _loadReminders();
      }
    }
  }

  void _showAddReminderDialog({Map<String, dynamic>? existingReminder}) {
    final bool isEditing = existingReminder != null;
    final titleCtrl = TextEditingController(text: existingReminder?['title'] ?? '');
    final noteCtrl = TextEditingController(text: existingReminder?['note'] ?? '');
    String selectedCategory = existingReminder?['category'] ?? 'medication';
    TimeOfDay selectedTime = const TimeOfDay(hour: 8, minute: 0);
    if (isEditing && existingReminder!['time_str'] != null) {
      try {
        final parts = existingReminder['time_str'].toString().split(':');
        if (parts.length >= 2) {
          selectedTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
      } catch (_) {}
    }
    String selectedRepeat = existingReminder?['repeat_days'] ?? '每天';
    DateTime selectedStartDate = DateTime.now();
    if (isEditing && existingReminder!['start_date'] != null && existingReminder['start_date'].toString().isNotEmpty) {
      try {
        selectedStartDate = DateTime.parse(existingReminder['start_date']);
      } catch (_) {}
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(isEditing ? Icons.edit_calendar_rounded : Icons.alarm_add_rounded, color: const Color(0xFF38BDF8), size: 24),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              isEditing ? '編輯遠端排程提醒' : '新增遠端排程提醒',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white54),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 1. 提醒標題
                    Text('提醒標題 / 事項', style: GoogleFonts.notoSansTc(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleCtrl,
                      style: GoogleFonts.notoSansTc(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '例如：服用降壓藥乙顆、台大回診',
                        hintStyle: GoogleFonts.notoSansTc(color: Colors.white30),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 2. 提醒分類
                    Text('提醒類型', style: GoogleFonts.notoSansTc(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildCategoryChip('用藥提醒 💊', 'medication', selectedCategory, (val) => setModalState(() => selectedCategory = val)),
                        _buildCategoryChip('看診回診 🏥', 'hospital', selectedCategory, (val) => setModalState(() => selectedCategory = val)),
                        _buildCategoryChip('飲水補水 🥤', 'water', selectedCategory, (val) => setModalState(() => selectedCategory = val)),
                        _buildCategoryChip('運動散步 🏃‍♂️', 'exercise', selectedCategory, (val) => setModalState(() => selectedCategory = val)),
                        _buildCategoryChip('日常叮嚀 💌', 'custom', selectedCategory, (val) => setModalState(() => selectedCategory = val)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 3. 時間選擇
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('時間', style: GoogleFonts.notoSansTc(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: () async {
                                  final t = await showTimePicker(
                                    context: context,
                                    initialTime: selectedTime,
                                  );
                                  if (t != null) {
                                    setModalState(() => selectedTime = t);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                                        style: GoogleFonts.notoSansTc(color: const Color(0xFF38BDF8), fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                      const Icon(Icons.access_time_rounded, color: Color(0xFF38BDF8), size: 20),
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
                              Text('重複頻率', style: GoogleFonts.notoSansTc(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: selectedRepeat,
                                    dropdownColor: const Color(0xFF1E293B),
                                    style: GoogleFonts.notoSansTc(color: Colors.white, fontSize: 14),
                                    items: ['每天', '每週一三五', '每週二四', '每週六日', '單次提醒']
                                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) setModalState(() => selectedRepeat = val);
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

                    // 4. 備註叮嚀
                    Text('備註叮嚀（選填）', style: GoogleFonts.notoSansTc(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: noteCtrl,
                      style: GoogleFonts.notoSansTc(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '例如：記得飯後服用、帶隨身健保卡',
                        hintStyle: GoogleFonts.notoSansTc(color: Colors.white30),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 5. 確定新增按鈕
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF38BDF8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () async {
                          final title = titleCtrl.text.trim();
                          if (title.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('請輸入提醒標題', style: GoogleFonts.notoSansTc())),
                            );
                            return;
                          }

                          final timeStr = '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
                          final startDateStr = '${selectedStartDate.year}-${selectedStartDate.month.toString().padLeft(2, '0')}-${selectedStartDate.day.toString().padLeft(2, '0')}';

                          bool success = false;
                          if (isEditing) {
                            success = await ApiService.updateElderReminder(existingReminder['id'], {
                              'title': title,
                              'category': selectedCategory,
                              'time_str': timeStr,
                              'repeat_days': selectedRepeat,
                              'start_date': startDateStr,
                              'note': noteCtrl.text.trim(),
                            });
                          } else {
                            final body = {
                              'family_id': widget.familyId,
                              'elder_id': widget.elderId,
                              'title': title,
                              'category': selectedCategory,
                              'time_str': timeStr,
                              'repeat_days': selectedRepeat,
                              'start_date': startDateStr,
                              'note': noteCtrl.text.trim(),
                            };
                            success = await ApiService.createElderReminder(body);
                          }

                          if (context.mounted) {
                            Navigator.pop(context);
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isEditing ? '已儲存提醒修訂 ✨' : '已成功建立「$title」排程提醒！✨', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold)),
                                  backgroundColor: const Color(0xFF10B981),
                                ),
                              );
                              _loadReminders();
                            }
                          }
                        },
                        child: Text(
                          isEditing ? '儲存變更' : '確認新增提醒',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCategoryChip(String label, String catKey, String currentCat, ValueChanged<String> onSelect) {
    final isSel = currentCat == catKey;
    return GestureDetector(
      onTap: () => onSelect(catKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF38BDF8).withValues(alpha: 0.25) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSel ? const Color(0xFF38BDF8) : Colors.white12,
            width: isSel ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansTc(
            fontSize: 12.5,
            fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
            color: isSel ? const Color(0xFF38BDF8) : Colors.white70,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _reminders.where((r) => r['is_active'] == true || r['is_active'] == 1).length;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Text(
          '⏰ ${widget.elderName} 遠端排程提醒',
          style: GoogleFonts.notoSansTc(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8)),
            onPressed: _loadReminders,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF38BDF8),
        onPressed: _showAddReminderDialog,
        icon: const Icon(Icons.add_alarm_rounded, color: Colors.white),
        label: Text('新增提醒', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF38BDF8),
        backgroundColor: const Color(0xFF1E293B),
        onRefresh: _loadReminders,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 頂部狀態摘要卡片
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.schedule_rounded, color: Color(0xFF38BDF8), size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '目前共有 $activeCount 項目在線啟用中',
                            style: GoogleFonts.notoSansTc(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '排程時間到達時，將自動於長輩終端觸發語音與卡片提醒',
                            style: GoogleFonts.notoSansTc(fontSize: 12, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms),

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '預設行程與排程列表',
                    style: GoogleFonts.notoSansTc(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    '共 ${_reminders.length} 筆設定',
                    style: GoogleFonts.notoSansTc(fontSize: 12, color: Colors.white38),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8))),
                )
              else if (_reminders.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      const Icon(Icons.alarm_off_rounded, size: 56, color: Colors.white24),
                      const SizedBox(height: 12),
                      Text('目前尚未建立任何排程提醒 ⏰', style: GoogleFonts.notoSansTc(color: Colors.white54, fontSize: 14)),
                      const SizedBox(height: 6),
                      Text('點擊右下角「新增提醒」開始設定', style: GoogleFonts.notoSansTc(fontSize: 12, color: Colors.white38)),
                    ],
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _reminders.length,
                  itemBuilder: (context, index) {
                    final r = _reminders[index];
                    final reminderId = r['id'] as int;
                    final title = r['title']?.toString() ?? '未命名提醒';
                    final category = r['category']?.toString() ?? 'custom';
                    final timeStr = r['time_str']?.toString() ?? '00:00';
                    final repeatDays = r['repeat_days']?.toString() ?? '每天';
                    final note = r['note']?.toString() ?? '';
                    final isActive = r['is_active'] == true || r['is_active'] == 1;

                    Color catColor = const Color(0xFF38BDF8);
                    IconData catIcon = Icons.notifications_active_rounded;
                    String catName = '叮嚀';

                    if (category == 'medication') {
                      catColor = const Color(0xFFA78BFA);
                      catIcon = Icons.medication_rounded;
                      catName = '用藥';
                    } else if (category == 'hospital') {
                      catColor = const Color(0xFFEF4444);
                      catIcon = Icons.local_hospital_rounded;
                      catName = '看診';
                    } else if (category == 'water') {
                      catColor = const Color(0xFF38BDF8);
                      catIcon = Icons.water_drop_rounded;
                      catName = '飲水';
                    } else if (category == 'exercise') {
                      catColor = const Color(0xFF34D399);
                      catIcon = Icons.directions_run_rounded;
                      catName = '運動';
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isActive ? catColor.withValues(alpha: 0.4) : Colors.white12,
                          width: isActive ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          // 時間與圖示
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(catIcon, color: catColor, size: 26),
                          ),
                          const SizedBox(width: 14),

                          // 內容與頻率
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      timeStr,
                                      style: GoogleFonts.notoSansTc(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: isActive ? Colors.white : Colors.white38,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: catColor.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '$catName • $repeatDays',
                                        style: GoogleFonts.notoSansTc(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: catColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  title,
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: isActive ? Colors.white.withValues(alpha: 0.9) : Colors.white38,
                                  ),
                                ),
                                if (note.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    note,
                                    style: GoogleFonts.notoSansTc(
                                      fontSize: 12,
                                      color: Colors.white38,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // 開關與刪除按鈕
                          Row(
                            children: [
                              Switch(
                                value: isActive,
                                activeThumbColor: catColor,
                                onChanged: (val) => _handleToggle(reminderId),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: Color(0xFF38BDF8), size: 20),
                                onPressed: () => _showAddReminderDialog(existingReminder: r as Map<String, dynamic>),
                                tooltip: '編輯提醒',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                                onPressed: () => _handleDelete(reminderId, title),
                                tooltip: '刪除提醒',
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}
