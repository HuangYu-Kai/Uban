import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../theme/family_theme.dart';
import '../../widgets/ui/ui.dart';
import 'widgets/fam_ui.dart';

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

  // 家屬主題之下的 context（State 自己的 context 在 FamilyThemeScope 之上）：
  // 用它開 sheet／dialog／時間選擇器，才會吃到家屬色票；每次 build 更新。
  BuildContext? _themed;
  BuildContext get _themeCtx => _themed ?? context;
  UbanColors get _c => UbanColors.of(_themeCtx);

  /// 提醒類型（key 為後端欄位值，label 只是顯示文字）。
  static const List<(String, String)> _categories = [
    ('medication', '用藥提醒'),
    ('hospital', '看診回診'),
    ('water', '飲水補水'),
    ('exercise', '運動散步'),
    ('custom', '日常叮嚀'),
  ];

  /// 重複頻率（值直接送後端，維持原字串）。
  static const List<String> _repeatOptions = ['每天', '每週一三五', '每週二四', '每週六日', '單次提醒'];

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    setState(() => _isLoading = true);
    List<dynamic> list = _reminders;
    try {
      list = await ApiService.getElderReminders(widget.elderId);
    } catch (_) {
      // 讀取失敗：維持原本清單（getElderReminders 現在失敗會丟例外）。
    }
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
    final confirm = await showUbanDialog<bool>(
      _themeCtx,
      (c) {
        final col = UbanColors.of(c);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('刪除排程提醒', style: famText(col.text, 19, weight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text('確定要刪除「$title」排程提醒嗎？', style: famText(col.text2, 15, height: 1.5)),
            const SizedBox(height: 20),
            FamButton(
              label: '確定刪除',
              kind: FamButtonKind.danger,
              onPressed: () => Navigator.pop(c, true),
            ),
            const SizedBox(height: 8),
            FamButton(
              label: '取消',
              kind: FamButtonKind.ghost,
              onPressed: () => Navigator.pop(c, false),
            ),
          ],
        );
      },
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
    if (isEditing && existingReminder['time_str'] != null) {
      try {
        final parts = existingReminder['time_str'].toString().split(':');
        if (parts.length >= 2) {
          selectedTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
      } catch (_) {}
    }
    String selectedRepeat = existingReminder?['repeat_days'] ?? '每天';
    DateTime selectedStartDate = DateTime.now();
    if (isEditing && existingReminder['start_date'] != null && existingReminder['start_date'].toString().isNotEmpty) {
      try {
        selectedStartDate = DateTime.parse(existingReminder['start_date']);
      } catch (_) {}
    }

    showUbanSheet<void>(
      _themeCtx,
      (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final c = UbanColors.of(context);
            // SnackBar 沿用主題預設底色（inverseSurface），字色取對應的 onInverseSurface。
            final snackFg = Theme.of(context).colorScheme.onInverseSurface;

            Widget fieldLabel(String text) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(text, style: famText(c.text2, 15, weight: FontWeight.w700)),
                );

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? '編輯遠端排程提醒' : '新增遠端排程提醒',
                  style: famText(c.text, 19, weight: FontWeight.w900),
                ),
                const SizedBox(height: 18),

                // 1. 提醒標題
                UbanTextField(
                  label: '提醒標題 / 事項',
                  controller: titleCtrl,
                  hintText: '例如：服用降壓藥乙顆、台大回診',
                ),
                const SizedBox(height: 18),

                // 2. 提醒分類
                fieldLabel('提醒類型'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final cat in _categories)
                      FamFilterChip(
                        label: cat.$2,
                        selected: selectedCategory == cat.$1,
                        onTap: () => setModalState(() => selectedCategory = cat.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 18),

                // 3. 時間選擇
                fieldLabel('時間'),
                PressableScale(
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
                    constraints: const BoxConstraints(minHeight: 58),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.line, width: 1.5),
                    ),
                    child: Text(
                      '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                      style: famText(c.text, 18, weight: FontWeight.w700, tabular: true),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // 4. 重複頻率
                fieldLabel('重複頻率'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final opt in _repeatOptions)
                      FamFilterChip(
                        label: opt,
                        selected: selectedRepeat == opt,
                        onTap: () => setModalState(() => selectedRepeat = opt),
                      ),
                  ],
                ),
                const SizedBox(height: 18),

                // 5. 備註叮嚀
                UbanTextField(
                  label: '備註叮嚀（選填）',
                  controller: noteCtrl,
                  hintText: '例如：記得飯後服用、帶隨身健保卡',
                ),
                const SizedBox(height: 22),

                // 6. 確定新增按鈕
                FamButton(
                  label: isEditing ? '儲存變更' : '確認新增提醒',
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('請輸入提醒標題', style: famText(snackFg, 15))),
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
                            content: Text(
                              isEditing ? '已儲存提醒修訂' : '已成功建立「$title」排程提醒！',
                              style: famText(snackFg, 15, weight: FontWeight.w700),
                            ),
                          ),
                        );
                        _loadReminders();
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 2026-10：push 出來的家屬頁要自己掛家屬主題。
    return FamilyThemeScope(
      child: Builder(builder: _buildScreen),
    );
  }

  Widget _buildScreen(BuildContext context) {
    _themed = context;
    final c = _c;
    final activeCount = _reminders.where((r) => r['is_active'] == true || r['is_active'] == 1).length;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: famSubBar(
        context,
        title: '${widget.elderName} 遠端排程提醒',
        trailing: [
          FamIconButton(
            icon: Icons.refresh_rounded,
            tooltip: '重新整理',
            onTap: _loadReminders,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadReminders,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  // 1. 頂部狀態摘要
                  FamCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '目前共有 $activeCount 項目在線啟用中',
                          style: famText(c.text, 16, weight: FontWeight.w900, height: 1.35),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '排程時間到達時，將自動於長輩終端觸發語音與卡片提醒',
                          style: famText(c.text2, 13.5, height: 1.45),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  const FamSecHead(title: '預設行程與排程列表'),
                  const SizedBox(height: 2),
                  Text('共 ${_reminders.length} 筆設定', style: famText(c.text3, 12.5)),

                  const SizedBox(height: 12),

                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_reminders.isEmpty)
                    FamCard(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          children: [
                            Text(
                              '目前尚未建立任何排程提醒',
                              textAlign: TextAlign.center,
                              style: famText(c.text, 16, weight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '點擊下方「新增提醒」開始設定',
                              textAlign: TextAlign.center,
                              style: famText(c.text2, 13.5),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    for (final r in _reminders) _buildReminderCard(r),
                ],
              ),
            ),
          ),
          // 底部固定的新增鈕（取代原本右下角的浮動按鈕，不再遮住清單最後一筆）。
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FamButton(label: '新增提醒', onPressed: _showAddReminderDialog),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderCard(dynamic r) {
    final c = _c;
    final reminderId = r['id'] as int;
    final title = r['title']?.toString() ?? '未命名提醒';
    final category = r['category']?.toString() ?? 'custom';
    final timeStr = r['time_str']?.toString() ?? '00:00';
    final repeatDays = r['repeat_days']?.toString() ?? '每天';
    final note = r['note']?.toString() ?? '';
    final isActive = r['is_active'] == true || r['is_active'] == 1;

    String catName = '叮嚀';
    if (category == 'medication') {
      catName = '用藥';
    } else if (category == 'hospital') {
      catName = '看診';
    } else if (category == 'water') {
      catName = '飲水';
    } else if (category == 'exercise') {
      catName = '運動';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FamCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 內容與頻率
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            timeStr,
                            style: famText(
                              isActive ? c.text : c.text3,
                              20,
                              weight: FontWeight.w900,
                              tabular: true,
                            ),
                          ),
                          FamChip(
                            label: '$catName・$repeatDays',
                            tone: isActive ? FamTone.brand : FamTone.neutral,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        style: famText(
                          isActive ? c.text : c.text3,
                          15.5,
                          weight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(note, style: famText(c.text3, 13, height: 1.4)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // 開關
                UbanSwitch(
                  value: isActive,
                  onChanged: (val) => _handleToggle(reminderId),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                children: [
                  FamButton(
                    label: '編輯',
                    kind: FamButtonKind.ghost,
                    height: 40,
                    expand: false,
                    onPressed: () => _showAddReminderDialog(existingReminder: r as Map<String, dynamic>),
                  ),
                  FamButton(
                    label: '刪除',
                    kind: FamButtonKind.ghost,
                    height: 40,
                    expand: false,
                    onPressed: () => _handleDelete(reminderId, title),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
