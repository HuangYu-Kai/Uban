import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/elder.dart';
import '../../services/api_service.dart';
import '../elder_profile_edit_screen.dart';
import '../caregiver_pairing_screen.dart';
import '../identification_screen.dart';

class FamilyDataTab extends StatefulWidget {
  final Elder? currentElder;
  final int userId;
  final String userName;
  final VoidCallback? onElderUpdated;

  const FamilyDataTab({
    super.key,
    required this.currentElder,
    required this.userId,
    required this.userName,
    this.onElderUpdated,
  });

  @override
  State<FamilyDataTab> createState() => _FamilyDataTabState();
}

class _FamilyDataTabState extends State<FamilyDataTab> {
  String _caregiverName = '';
  bool _isEmergencyOn = true;
  bool _isDailySummaryOn = true;
  bool _isAiInsightOn = true;
  bool _isGeneratingRecovery = false;
  
  // AI assistant profile summary (loaded from API if currentElder is available)
  bool _isLoadingAiProfile = false;
  Map<String, dynamic>? _elderProfileData;

  @override
  void initState() {
    super.initState();
    _caregiverName = widget.userName;
    _loadCaregiverName();
    _loadAiProfile();
  }

  @override
  void didUpdateWidget(FamilyDataTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentElder?.id != oldWidget.currentElder?.id) {
      _loadAiProfile();
    }
  }

  Future<void> _loadCaregiverName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('caregiver_name');
    if (name != null && mounted) {
      setState(() {
        _caregiverName = name;
      });
    }
  }

  Future<void> _loadAiProfile() async {
    if (widget.currentElder == null) return;
    setState(() => _isLoadingAiProfile = true);
    try {
      final profile = await ApiService.getElderProfile(widget.currentElder!.id);
      if (mounted) {
        setState(() {
          _elderProfileData = profile;
          _isLoadingAiProfile = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAiProfile = false);
      }
    }
  }

  void _handleEditProfile() {
    final TextEditingController controller = TextEditingController(text: _caregiverName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '編輯我的資料',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '我的顯示名稱',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('caregiver_name', newName);
                setState(() {
                  _caregiverName = newName;
                });
              }
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '登出',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        content: const Text('確定要登出並回到身分選擇頁面嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('caregiver_id');
              await prefs.remove('caregiver_name');
              await prefs.remove('selected_elder_id');
              await prefs.remove('selected_elder_name');
              
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const IdentificationScreen()),
                (route) => false,
              );
            },
            child: const Text('登出', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _navigateToElderEdit() {
    if (widget.currentElder == null) return;

    // Construct elderData map compatible with ElderProfileEditScreen
    final elderData = {
      'id': widget.currentElder!.id,
      'user_id': widget.currentElder!.id,
      'user_name': widget.currentElder!.name,
      'gender': widget.currentElder!.gender ?? 'M',
      'age': widget.currentElder!.age,
      'location': widget.currentElder!.location,
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ElderProfileEditScreen(
          elderData: elderData,
          familyId: widget.userId,
          onUnbind: () {
            // ★ issue 13：先關閉編輯頁，回到 FamilyDataTab 後再顯示解除綁定確認對話框
            Navigator.pop(context);
            _showUnbindConfirmDialog();
          },
        ),
      ),
    ).then((_) {
      _loadAiProfile();
      if (widget.onElderUpdated != null) {
        widget.onElderUpdated!();
      }
    });
  }

  // ★ issue 13：解除綁定確認對話框，呼叫後端 unbind API 並在成功後刷新長輩列表
  void _showUnbindConfirmDialog() {
    if (widget.currentElder == null) return;
    final elder = widget.currentElder!;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('解除綁定', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold)),
        content: Text(
          '確定要解除與「${elder.name}」的綁定嗎？\n\n警告：這將會永久刪除該長輩的所有資料與對話紀錄，無法復原。',
          style: GoogleFonts.notoSansTc(color: Colors.redAccent, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: GoogleFonts.notoSansTc()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final result = await ApiService.unbindElder(widget.userId, elder.id);
              if (!mounted) return;
              if (result['status'] == 'success') {
                navigator.pop();
                if (widget.onElderUpdated != null) {
                  widget.onElderUpdated!();
                }
                messenger.showSnackBar(
                  const SnackBar(content: Text('已刪除並解除綁定'), backgroundColor: Colors.redAccent),
                );
              } else {
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text('刪除失敗: ${result['error']}'), backgroundColor: Colors.redAccent),
                );
              }
            },
            child: Text('確定刪除', style: GoogleFonts.notoSansTc(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRecoveryAssistantDialog() {
    if (widget.currentElder == null) return;
    
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFF0EB),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.phonelink_setup_rounded,
                      color: Color(0xFFFF7043),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '長輩移機與重裝助手',
                      style: GoogleFonts.notoSansTc(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '如果長輩（${widget.currentElder!.displayName}）更換了新手機，或是不小心解除安裝了 Uban App，您可以在這裡為長輩產生一個具有時效性（15分鐘內有效）的快速登入連結，並傳送給長輩。',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 15,
                      color: const Color(0xFF475569),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '⚠️ 注意：連結僅於 15 分鐘內有效，點擊後長輩設備即可自動登入回原本的帳號。',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFEF4444),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isGeneratingRecovery ? null : () => Navigator.pop(dialogContext),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                        ),
                        child: Text(
                          '取消',
                          style: GoogleFonts.notoSansTc(
                            color: const Color(0xFF94A3B8),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isGeneratingRecovery
                            ? null
                            : () async {
                                final shortId = _elderProfileData?['elder_id'] ?? widget.currentElder?.elderId;
                                final familyId = widget.userId;

                                if (shortId == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('無法產生連結：缺少長輩的配對身分資訊')),
                                  );
                                  return;
                                }

                                setDialogState(() => _isGeneratingRecovery = true);
                                setState(() => _isGeneratingRecovery = true);

                                try {
                                  final result = await ApiService.generateRecoveryLink(
                                    familyId: familyId,
                                    elderId: shortId.toString(),
                                  );

                                  if (result['status'] == 'success' && result['data'] != null) {
                                    final recoveryUrl = result['data']['recovery_url'];
                                    final shareText = '【Uban 長輩快速登入】\n'
                                        '哈囉，這是您的專屬登入連結。請在新手機點擊此連結，即可自動登入回原本的帳號喔！\n\n'
                                        '$recoveryUrl\n\n'
                                        '⚠️ 注意：連結僅於 15 分鐘內有效。';

                                    await SharePlus.instance.share(
                                      ShareParams(
                                        text: shareText,
                                        subject: 'Uban 快速移機連結',
                                      ),
                                    );
                                    if (mounted) Navigator.pop(dialogContext);
                                  } else {
                                    final errorMsg = result['error'] ?? result['message'] ?? result['detail'] ?? '產生連結失敗';
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(errorMsg)),
                                      );
                                    }
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('連線失敗: $e')),
                                    );
                                  }
                                } finally {
                                  setDialogState(() => _isGeneratingRecovery = false);
                                  if (mounted) {
                                    setState(() => _isGeneratingRecovery = false);
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF7043),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: _isGeneratingRecovery
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                '產生並分享',
                                style: GoogleFonts.notoSansTc(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
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
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // 1. 家屬個人卡片
              _buildCaregiverCard(),
              const SizedBox(height: 20),

              // 2. 長輩基本資料編輯入口
              if (widget.currentElder != null) ...[
                _buildElderSummaryCard(),
                const SizedBox(height: 20),

                // 📖 亮點三：長輩人生故事膠囊 (Memoirs & Family Legacy)
                _buildMemoirsCard(),
                const SizedBox(height: 20),
                // 3. AI 輔助資料概覽 (長輩喜好、習慣、健康注意事項)
                _buildAiHelperCard(),
                const SizedBox(height: 20),
              ] else ...[
                // 當未選擇長輩時顯示引導訊息
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '尚未選擇長輩',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '請在「首頁」或「互動」分頁選擇要關照的長輩，或點擊下方按鈕配對新的長輩裝置',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 14,
                          color: const Color(0xFF94A3B8),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            // 跳轉到配對頁面
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CaregiverPairingScreen(
                                  familyId: widget.userId,
                                  familyName: _caregiverName,
                                ),
                              ),
                            ).then((_) {
                              if (widget.onElderUpdated != null) {
                                widget.onElderUpdated!();
                              }
                            });
                          },
                          icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                          label: const Text('配對新長輩裝置'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 400.ms),
              ],

              // 4. 設定項目 (開關)
              _buildSettingsGroup('健康與安全通知', [
                _buildSwitchItem(
                  Icons.emergency_rounded,
                  '緊急廣播與來電通知',
                  '長輩端發起緊急求救時，優先響鈴並強制喚醒',
                  _isEmergencyOn,
                  (val) => setState(() => _isEmergencyOn = val),
                  const Color(0xFFEF4444),
                ),
                _buildSwitchItem(
                  Icons.summarize_rounded,
                  '每日健康日誌摘要',
                  '每日傍晚推播長輩今日的健康活動與心情摘要',
                  _isDailySummaryOn,
                  (val) => setState(() => _isDailySummaryOn = val),
                  const Color(0xFFF59E0B),
                ),
                _buildSwitchItem(
                  Icons.psychology_rounded,
                  'AI 平安智能防護',
                  '異常生活作業或情緒警示的主動通知',
                  _isAiInsightOn,
                  (val) => setState(() => _isAiInsightOn = val),
                  const Color(0xFF8B5CF6),
                ),
              ]),
              const SizedBox(height: 20),

              // 5. 配對與移機設定
              _buildSettingsGroup('裝置與配對', [
                _buildActionItem(
                  Icons.add_circle_outline_rounded,
                  '配對新長輩裝置',
                  '掃描或輸入配對碼，連結其他長輩裝置',
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CaregiverPairingScreen(
                          familyId: widget.userId,
                          familyName: _caregiverName,
                        ),
                      ),
                    ).then((_) {
                      if (widget.onElderUpdated != null) {
                        widget.onElderUpdated!();
                      }
                    });
                  },
                  const Color(0xFF3B82F6),
                ),
                if (widget.currentElder != null) ...[
                  const Divider(height: 16, color: Color(0xFFF1F5F9)),
                  _buildActionItem(
                    Icons.phonelink_setup_rounded,
                    '長輩移機與重裝助手',
                    '產生時效性登入連結，協助長輩在更換手機或重裝時快速登入',
                    () {
                      _showRecoveryAssistantDialog();
                    },
                    const Color(0xFFFF7043),
                  ),
                ],
              ]),
              const SizedBox(height: 32),

              // 6. 登出按鈕
              OutlinedButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout_rounded, size: 20),
                label: Text(
                  '登出目前帳號',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ).animate().fadeIn(delay: 300.ms),
            ]),
          ),
        ),
      ],
    );
  }

  // ─── 📖 亮點三：長輩人生故事膠囊 (Memoirs & Family Legacy) ───

  Widget _buildMemoirsCard() {
    final name = widget.currentElder?.displayName ?? '長輩';

    final List<Map<String, String>> stories = [
      {
        'title': '大稻埕布莊歲月 (1975年)',
        'tag': '經典記憶',
        'preview': '年輕時在迪化街經營布料批發，最驕傲的是堅持選用頂級棉麻，結交了許多一輩子的摯友...',
      },
      {
        'title': '給孫子的一封信',
        'tag': '溫馨寄語',
        'preview': '希望孩子們快快長大，阿公一直都記得你們第一次學會騎腳踏車時，全家在公園歡笑的模樣...',
      },
      {
        'title': '最懷念的柴燒紅豆湯',
        'tag': '美食記憶',
        'preview': '媽媽當年手作的柴燒紅豆湯，慢火熬煮出綿密甜味，那是童年記憶中最溫暖的冬日滋味...',
      },
    ];

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF261C05), Color(0xFF1F1703)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.6), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_stories_rounded, color: Color(0xFFFCD34D), size: 24),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '📖 $name的人生故事膠囊',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFFDE68A),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '珍藏集',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF451A03),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),
          Text(
            '由 AI 小嘎口述對話整理紀錄，保留家族珍貴記憶與生命智慧',
            style: GoogleFonts.notoSansTc(
              fontSize: 13,
              color: const Color(0xFFFDE68A).withValues(alpha: 0.8),
            ),
          ),

          const SizedBox(height: 16),

          ...stories.map((st) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF140F04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      st['title']!,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFFEF3C7),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        st['tag']!,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFFCD34D),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  st['preview']!,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 13,
                    color: const Color(0xFFFDE68A).withValues(alpha: 0.9),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    ).animate().fadeIn(delay: 250.ms, duration: 400.ms);
  }

  Widget _buildCaregiverCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF0284C7).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Text(
                _caregiverName.isNotEmpty ? _caregiverName[0].toUpperCase() : 'U',
                style: GoogleFonts.notoSansTc(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _caregiverName.isNotEmpty ? _caregiverName : '家屬帳號',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '家屬帳號',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 11,
                          color: const Color(0xFF38BDF8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ID: ${widget.userId}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _handleEditProfile,
            icon: const Icon(Icons.edit_outlined, color: Color(0xFF94A3B8)),
            tooltip: '編輯資料',
          ),
          IconButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const IdentificationScreen()),
                (route) => false,
              );
            },
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444)),
            tooltip: '登出帳號',
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildElderSummaryCard() {
    if (widget.currentElder == null) return const SizedBox.shrink();
    final elder = widget.currentElder!;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
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
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.elderly_rounded,
                  color: Color(0xFF34D399),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '受關照長輩資料',
                style: GoogleFonts.notoSansTc(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _navigateToElderEdit,
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: Text(
                  '編輯',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF38BDF8),
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.2),
                child: Text(
                  elder.genderEmoji,
                  style: const TextStyle(fontSize: 32),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      elder.displayName,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${elder.age != null ? "${elder.age} 歲" : "年齡未填"} • ${elder.gender == "F" ? "女性" : "男性"} • 居住於 ${(elder.location != null && elder.location!.isNotEmpty) ? elder.location : "台北市大安區"}',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 14,
                        color: const Color(0xFFCBD5E1),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 50.ms, duration: 400.ms);
  }

  Widget _buildAiHelperCard() {
    if (widget.currentElder == null) return const SizedBox.shrink();
    if (_isLoadingAiProfile) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final appellation = _elderProfileData?['appellation'] ?? '未設定';
    final tone = _elderProfileData?['ai_emotion_tone'] ?? 50;
    final verbosity = _elderProfileData?['ai_text_verbosity'] ?? 50;
    final interests = _elderProfileData?['interests'] ?? '未填寫';
    final chronicDiseases = _elderProfileData?['chronic_diseases'] ?? '無備註';
    final medicationNotes = _elderProfileData?['medication_notes'] ?? '無備註';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
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
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFFA78BFA),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'AI 陪伴助理設定狀態',
                style: GoogleFonts.notoSansTc(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow('長輩稱呼', appellation),
          _buildInfoRow('陪伴語氣', tone > 60 ? '親切活潑' : tone < 40 ? '沉穩客觀' : '溫和適中'),
          _buildInfoRow('話匣子開關', verbosity > 60 ? '滔滔不絕' : verbosity < 40 ? '簡潔回覆' : '適度互動'),
          _buildInfoRow('興趣與回憶素材', interests),
          _buildInfoRow('健康注意事項', chronicDiseases),
          _buildInfoRow('用藥與照護提醒', medicationNotes),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _navigateToElderEdit,
              icon: const Icon(Icons.settings_suggest_rounded, size: 20),
              label: const Text('調整 AI 對話偏好與背景資料'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                foregroundColor: const Color(0xFFC4B5FD),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFF8B5CF6)),
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms);
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: GoogleFonts.notoSansTc(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFA5B4FC),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.notoSansTc(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup(String groupTitle, List<Widget> items) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.25), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            groupTitle,
            style: GoogleFonts.notoSansTc(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF38BDF8),
            ),
          ),
          const SizedBox(height: 12),
          ...items,
        ],
      ),
    ).animate().fadeIn(delay: 150.ms, duration: 400.ms);
  }

  Widget _buildSwitchItem(
    IconData icon,
    String title,
    String description,
    bool value,
    ValueChanged<bool> onChanged,
    Color activeColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: activeColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 13,
                    color: const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: activeColor.withValues(alpha: 0.4),
            activeColor: activeColor,
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem(
    IconData icon,
    String title,
    String description,
    VoidCallback onTap,
    Color themeColor,
  ) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: themeColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 13,
                      color: const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF94A3B8), size: 18),
          ],
        ),
      ),
    );
  }
}
