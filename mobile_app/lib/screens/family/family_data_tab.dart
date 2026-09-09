import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/elder.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../elder_profile_edit_screen.dart';
import '../caregiver_pairing_screen.dart';
import '../identification_screen.dart';
import 'family_subscription_screen.dart';
import 'family_bug_report_screen.dart';
import '../../models/memoir_story.dart';
import '../../services/memoir_service.dart';
import '../../widgets/memoir_detail_sheet.dart';
import 'memoirs_gallery_screen.dart';

/// ⚙️ 子女端「資料與設定」Tab (FamilyDataTab)
/// 包含：照顧者資訊、關照長輩完整檔案、AI 陪伴偏好、人生故事膠囊、安全通知設定、裝置與訂閱管理
class FamilyDataTab extends StatefulWidget {
  final Elder? currentElder;
  final int userId;
  final String userName;
  final VoidCallback? onElderUpdated;
  final bool isDarkMode;
  final ValueChanged<bool>? onToggleDarkMode;

  // ★ 第四十一輪 item 2（第二階段）：新手指引用的高光目標 GlobalKey。全部
  //   選填、預設 null——GlobalKey 必須由上層 FamilyMainScreen 持有並傳入，
  //   理由與傳遞方式比照 family_home_tab.dart 同名欄位群組的說明。不傳就
  //   等同沒有目標，`SpotlightTutorial` 會自動退化為無挖洞的置中卡片。
  final GlobalKey? caregiverCardKey;
  final GlobalKey? elderSummaryKey;
  final GlobalKey? memoirsKey;
  final GlobalKey? aiHelperKey;

  const FamilyDataTab({
    super.key,
    required this.currentElder,
    required this.userId,
    required this.userName,
    this.onElderUpdated,
    this.isDarkMode = false,
    this.onToggleDarkMode,
    this.caregiverCardKey,
    this.elderSummaryKey,
    this.memoirsKey,
    this.aiHelperKey,
  });

  @override
  State<FamilyDataTab> createState() => _FamilyDataTabState();
}

class _FamilyDataTabState extends State<FamilyDataTab> {
  String _caregiverName = '';
  String _subscriptionDisplay = '一般會員';
  
  // 智慧防護與通知開關
  bool _isEmergencyOn = true;
  bool _isDailySummaryOn = true;
  bool _isAiInsightOn = true;
  bool _isMedicationPushOn = true;
  bool _isGeneratingRecovery = false;

  // AI 與長輩資料狀態
  bool _isLoadingAiProfile = false;
  Map<String, dynamic>? _elderProfileData;

  // 📖 人生故事膠囊資料狀態
  List<MemoirStory> _memoirStories = [];
  bool _isLoadingMemoirs = true;

  @override
  void initState() {
    super.initState();
    _caregiverName = widget.userName;
    _loadCaregiverName();
    _loadSubscriptionInfo();
    _loadAiProfile();
    MemoirService.instance.addListener(_onMemoirsChanged);
    _loadMemoirs();
  }

  @override
  void dispose() {
    MemoirService.instance.removeListener(_onMemoirsChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(FamilyDataTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentElder?.id != oldWidget.currentElder?.id ||
        widget.currentElder?.elderId != oldWidget.currentElder?.elderId) {
      _loadAiProfile();
      _loadMemoirs();
    }
  }

  void _onMemoirsChanged() {
    if (mounted) _loadMemoirs();
  }

  Future<void> _loadMemoirs() async {
    final elderId = widget.currentElder?.elderId ?? widget.currentElder?.id.toString() ?? 'default_elder';
    final stories = await MemoirService.instance.getMemoirs(elderId);
    if (mounted) {
      setState(() {
        _memoirStories = stories;
        _isLoadingMemoirs = false;
      });
    }
  }

  Future<void> _loadCaregiverName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('caregiver_name');
    if (name != null && name.isNotEmpty && mounted) {
      setState(() {
        _caregiverName = name;
      });
    }
  }

  Future<void> _loadSubscriptionInfo() async {
    try {
      final res = await ApiService.getSubscriptionTier(widget.userId);
      if (mounted && (res['status'] == 'success' || res['tier_level'] != null)) {
        final tier = (res['tier_level'] ?? 'free').toString();
        setState(() {
          if (tier == 'diamond') {
            _subscriptionDisplay = '💎 鑽石守護版';
          } else if (tier == 'gold') {
            _subscriptionDisplay = '👑 黃金尊榮版';
          } else {
            _subscriptionDisplay = '🛡️ 一般會員';
          }
        });
      }
    } catch (_) {}
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
    final cs = Theme.of(context).colorScheme;
    final TextEditingController controller = TextEditingController(text: _caregiverName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: cs.primary.withValues(alpha: 0.5), width: 1.2),
        ),
        title: Row(
          children: [
            Icon(Icons.edit_note_rounded, color: cs.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              '編輯我的顯示名稱',
              style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold, color: cs.onSurface, fontSize: 18),
            ),
          ],
        ),
        content: TextField(
          controller: controller,
          style: GoogleFonts.notoSansTc(color: cs.onSurface),
          decoration: InputDecoration(
            hintText: '輸入您的稱呼 (例: 大兒子、小女兒)',
            hintStyle: GoogleFonts.notoSansTc(color: cs.outline),
            filled: true,
            fillColor: cs.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.primary, width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: GoogleFonts.notoSansTc(color: cs.outline)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('caregiver_name', newName);
                if (mounted) {
                  setState(() {
                    _caregiverName = newName;
                  });
                }
              }
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: Text('儲存', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _handleLogout() {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: cs.error.withValues(alpha: 0.6), width: 1.2),
        ),
        title: Row(
          children: [
            Icon(Icons.logout_rounded, color: cs.error, size: 24),
            const SizedBox(width: 8),
            Text(
              '安全登出',
              style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold, color: cs.onSurface, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          '確定要登出當前帳號並回到身分選擇頁面嗎？',
          style: GoogleFonts.notoSansTc(color: cs.onSurfaceVariant, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('取消', style: GoogleFonts.notoSansTc(color: cs.outline)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await SessionManager.releaseSession();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const IdentificationScreen()),
                (route) => false,
              );
            },
            child: Text('確認登出', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _navigateToElderEdit() {
    if (widget.currentElder == null) return;

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

  void _showUnbindConfirmDialog() {
    if (widget.currentElder == null) return;
    final elder = widget.currentElder!;
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: cs.error.withValues(alpha: 0.6), width: 1.5),
        ),
        title: Row(
          children: [
            Icon(Icons.link_off_rounded, color: cs.error, size: 24),
            const SizedBox(width: 8),
            Text('解除綁定確認', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold, color: cs.onSurface, fontSize: 18)),
          ],
        ),
        content: Text(
          '確定要解除與「${elder.name}」的照護配對嗎？\n\n⚠️ 解除後您將無法再接收該長輩的健康警報與即時狀態。',
          style: GoogleFonts.notoSansTc(color: cs.error, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: GoogleFonts.notoSansTc(color: cs.outline)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
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
                  const SnackBar(content: Text('✅ 已成功解除與該長輩的綁定'), backgroundColor: Color(0xFFEF4444)),
                );
              } else {
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text('⚠️ 解除失敗: ${result['error']}'), backgroundColor: const Color(0xFFEF4444)),
                );
              }
            },
            child: Text('確定解除', style: GoogleFonts.notoSansTc(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showRecoveryAssistantDialog() {
    if (widget.currentElder == null) return;
    final cs = Theme.of(context).colorScheme;
    
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: cs.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Color(0xFFFF7043), width: 1.2),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF7043).withValues(alpha: 0.2),
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
                        fontSize: 18,
                        color: cs.onSurface,
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
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Color(0xFFEF4444), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '注意：連結於 15 分鐘內有效，點擊後長輩設備即可自動免密登入回原本帳號。',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFEF4444),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
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
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: BorderSide(color: cs.outlineVariant, width: 1.2),
                        ),
                        child: Text(
                          '取消',
                          style: GoogleFonts.notoSansTc(
                            color: cs.outline,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
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
                                    const SnackBar(content: Text('⚠️ 無法產生連結：缺少長輩的配對身分資訊')),
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
                                    if (dialogContext.mounted) Navigator.pop(dialogContext);
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
                          padding: const EdgeInsets.symmetric(vertical: 12),
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
                                  fontSize: 14,
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
              // 1. 家屬個人卡片 (Caregiver Identity)
              _buildCaregiverCard(),
              const SizedBox(height: 18),

              // 🎨 介面主題風格設定（資料 Tab 切換淺色/深色模式，預設為淺色）
              _buildSettingsGroup('🎨 外觀風格與色彩主題', [
                _buildSwitchItem(
                  widget.isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  '深色主題模式 (Dark Theme)',
                  widget.isDarkMode ? '目前使用深色模式（墨藍底色搭配薄荷綠線條）' : '目前使用淺色模式（象牙白底色搭配墨藍線條，預設）',
                  widget.isDarkMode,
                  (val) => widget.onToggleDarkMode?.call(val),
                  Theme.of(context).colorScheme.primary,
                ),
              ]),
              const SizedBox(height: 18),

              // 2. 當前受關照長輩詳細健康資料 (Elder Profile Summary)
              if (widget.currentElder != null) ...[
                _buildElderSummaryCard(),
                const SizedBox(height: 18),

                // 3. 長輩人生故事膠囊 (Memoirs & Family Legacy)
                _buildMemoirsCard(),
                const SizedBox(height: 18),

                // 4. 長輩互動與對話偏好 (Companion Preferences)
                _buildAiHelperCard(),
                const SizedBox(height: 18),
              ] else ...[
                // 未選擇長輩引導卡片
                _buildNoElderSelectedCard(),
                const SizedBox(height: 18),
              ],

              // 5. 智慧照護與即時通知設定 (Care & Notification)
              _buildSettingsGroup('🔔 安全防護與日常通知設定', [
                _buildSwitchItem(
                  Icons.emergency_rounded,
                  '緊急廣播與跌倒求救通知',
                  '長輩端觸發緊急警報時，第一時間彈窗並強制響鈴提醒',
                  _isEmergencyOn,
                  (val) => setState(() => _isEmergencyOn = val),
                  Theme.of(context).colorScheme.secondary,
                ),
                _buildSwitchItem(
                  Icons.medication_rounded,
                  '服藥打卡與關懷排程提醒',
                  '長輩完成吃藥打卡或未按時服藥時，即時推播回報',
                  _isMedicationPushOn,
                  (val) => setState(() => _isMedicationPushOn = val),
                  Theme.of(context).colorScheme.primary,
                ),
                _buildSwitchItem(
                  Icons.summarize_rounded,
                  '每日傍晚健康日誌摘要',
                  '每日 18:00 推播長輩今日活動紀錄與心情簡報',
                  _isDailySummaryOn,
                  (val) => setState(() => _isDailySummaryOn = val),
                  Theme.of(context).colorScheme.tertiary,
                ),
                _buildSwitchItem(
                  Icons.psychology_rounded,
                  '長輩作息與情緒預警',
                  '長輩生活作息不規律或情緒低落時的主動關懷建議',
                  _isAiInsightOn,
                  (val) => setState(() => _isAiInsightOn = val),
                  Theme.of(context).colorScheme.secondary,
                ),
              ]),
              const SizedBox(height: 18),

              // 6. 裝置配對、移機與訂閱管理 (Devices & Subscriptions)
              _buildSettingsGroup('📱 裝置配對與加值服務', [
                _buildActionItem(
                  Icons.diamond_rounded,
                  '訂閱方案與設備上限管理',
                  '當前方案：$_subscriptionDisplay，管理監視設備數量與雲端功能',
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FamilySubscriptionScreen(),
                      ),
                    ).then((_) => _loadSubscriptionInfo());
                  },
                  Theme.of(context).colorScheme.primary,
                  trailingBadge: _subscriptionDisplay,
                ),
                Divider(height: 16, color: Theme.of(context).colorScheme.outlineVariant),
                _buildActionItem(
                  Icons.add_circle_outline_rounded,
                  '配對新長輩裝置',
                  '掃描 QR Code 或輸入配對碼，連結其他長輩平板或手機',
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
                  Theme.of(context).colorScheme.primary,
                ),
                if (widget.currentElder != null) ...[
                  Divider(height: 16, color: Theme.of(context).colorScheme.outlineVariant),
                  _buildActionItem(
                    Icons.phonelink_setup_rounded,
                    '長輩移機與免密重裝助手',
                    '產生 15 分鐘專屬登入連結，長輩換手機或重裝時一鍵復原',
                    _showRecoveryAssistantDialog,
                    Theme.of(context).colorScheme.secondary,
                  ),
                ],
              ]),
              const SizedBox(height: 18),

              // 6.5 支援與意見回饋 (Support & Feedback)
              // ★ BUG 回報功能：低頻但重要，刻意不放頂層分頁、不放首頁／互動
              //   這種高頻畫面，比照裝置配對／訂閱等次級設定放在「資料」分頁。
              _buildSettingsGroup('🛟 支援與意見回饋', [
                _buildActionItem(
                  Icons.bug_report_rounded,
                  '回報問題 / 意見反饋',
                  '遇到問題或有建議？點此回報，我們會盡快處理',
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FamilyBugReportScreen(familyId: widget.userId),
                      ),
                    );
                  },
                  Theme.of(context).colorScheme.tertiary,
                ),
              ]),
              const SizedBox(height: 18),

              // 7. 系統資訊 (System Info)
              _buildSystemInfoCard(),
              const SizedBox(height: 24),

              // 8. 登出按鈕
              OutlinedButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout_rounded, size: 20),
                label: Text(
                  '登出目前帳號',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.secondary,
                  side: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1.5),
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

  // ─── 1. 家屬個人卡片 (Caregiver Card) ───

  Widget _buildCaregiverCard() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      key: widget.caregiverCardKey,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cs.outline,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : cs.outline).withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary,
                  border: Border.all(color: cs.outline, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    _caregiverName.isNotEmpty ? _caregiverName[0].toUpperCase() : 'U',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: cs.onPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _caregiverName.isNotEmpty ? _caregiverName : '主要照護家屬',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _handleEditProfile,
                          icon: Icon(Icons.edit_outlined, color: cs.primary, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: '編輯名稱',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: cs.outline,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '家屬管理員',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 11,
                              color: cs.onPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '帳號 ID: ${widget.userId}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 快速方案狀態
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FamilySubscriptionScreen()),
              ).then((_) => _loadSubscriptionInfo());
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? cs.surfaceContainer : const Color(0xFFFFFFFE),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outline, width: 1.2),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user_rounded, color: cs.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '方案等級：',
                    style: GoogleFonts.notoSansTc(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                  Text(
                    _subscriptionDisplay,
                    style: GoogleFonts.notoSansTc(fontSize: 13, fontWeight: FontWeight.bold, color: cs.primary),
                  ),
                  const Spacer(),
                  Text(
                    '管理方案',
                    style: GoogleFonts.notoSansTc(fontSize: 12, color: cs.outline, fontWeight: FontWeight.w600),
                  ),
                  Icon(Icons.chevron_right_rounded, color: cs.outline, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms);
  }

  // ─── 2. 長輩基本資料與健康摘要卡 ───

  Widget _buildElderSummaryCard() {
    if (widget.currentElder == null) return const SizedBox.shrink();
    final elder = widget.currentElder!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final chronicDiseases = _elderProfileData?['chronic_diseases'] ?? '無特別記載';
    final medicationNotes = _elderProfileData?['medication_notes'] ?? '照護提醒正常';

    return Container(
      key: widget.elderSummaryKey,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cs.outline,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : cs.outline).withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outline, width: 1.2),
                ),
                child: Icon(Icons.elderly_rounded, color: cs.onPrimary, size: 22),
              ),
              const SizedBox(width: 10),
              Text(
                '受關照長輩檔案',
                style: GoogleFonts.notoSansTc(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _navigateToElderEdit,
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: Text(
                  '編輯資料',
                  style: GoogleFonts.notoSansTc(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: cs.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary,
                  border: Border.all(color: cs.outline, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  elder.genderEmoji,
                  style: const TextStyle(fontSize: 30),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          elder.displayName,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: cs.outline, width: 1.0),
                          ),
                          child: Text(
                            '長輩端: ${elder.elderId ?? "E00${elder.id}"}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${elder.age != null ? "${elder.age} 歲" : "年齡未填"} • ${elder.gender == "F" ? "女性" : "男性"} • 居於 ${(elder.location != null && elder.location!.isNotEmpty) ? elder.location : "台北市"}',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 健康摘要標籤
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? cs.surfaceContainer : const Color(0xFFFFFFFE),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.favorite_rounded, color: cs.secondary, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '慢性病與健康注意：',
                      style: GoogleFonts.notoSansTc(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant),
                    ),
                    Expanded(
                      child: Text(
                        chronicDiseases,
                        style: GoogleFonts.notoSansTc(fontSize: 13, color: cs.onSurface, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.medication_liquid_rounded, color: cs.primary, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '用藥備註：',
                      style: GoogleFonts.notoSansTc(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant),
                    ),
                    Expanded(
                      child: Text(
                        medicationNotes,
                        style: GoogleFonts.notoSansTc(fontSize: 13, color: cs.onSurface, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 50.ms, duration: 350.ms);
  }

  // ─── 3. 人生故事膠囊 (Memoirs & Family Legacy) ───

  Widget _buildMemoirsCard() {
    final name = widget.currentElder?.displayName ?? '長輩';
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final stories = _memoirStories;
    final elderId = widget.currentElder?.elderId ?? widget.currentElder?.id.toString() ?? 'default_elder';

    return Container(
      key: widget.memoirsKey,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cs.outline,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : cs.outline).withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 卡片頂部標題列（點擊可進入完整回憶錄畫廊）
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MemoirsGalleryScreen(
                    elderId: elderId,
                    elderName: name,
                    familyUserName: widget.userName,
                  ),
                ),
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.tertiary,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.outline, width: 1.2),
                        ),
                        child: Icon(Icons.auto_stories_rounded, color: cs.outline, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          '📖 $name的人生故事膠囊',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.tertiary,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cs.outline, width: 1.2),
                  ),
                  child: Text(
                    '珍藏 ${stories.length} 篇',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cs.outline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '由日常對話口述整理紀錄，珍藏長輩的人生智慧與家族回憶',
            style: GoogleFonts.notoSansTc(
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),

          // 故事列表（最多展示前 3 篇，點擊可開啟原聲聆聽詳情彈窗）
          if (_isLoadingMemoirs)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (stories.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? cs.surfaceContainer : const Color(0xFFFFFFFE),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outline, width: 1.2),
              ),
              child: Text(
                '長輩尚未與小豬分享故事，點擊下方「委託小豬提問」讓小豬主動發問吧！',
                style: GoogleFonts.notoSansTc(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            )
          else
            ...stories.take(3).map((st) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: isDark ? cs.surfaceContainer : const Color(0xFFFFFFFE),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outline, width: 1.2),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => MemoirDetailSheet.show(
                  context,
                  story: st,
                  elderName: name,
                  familyUserName: widget.userName,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              st.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.notoSansTc(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.tertiary.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: cs.outline, width: 1.0),
                            ),
                            child: Text(
                              st.tag,
                              style: GoogleFonts.notoSansTc(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: cs.outline,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        st.preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.volume_up_rounded, size: 13, color: Color(0xFF3B82F6)),
                          const SizedBox(width: 3),
                          Text(
                            '原聲錄音',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF3B82F6),
                            ),
                          ),
                          if (st.familyNotes.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Icon(Icons.favorite_rounded, size: 12, color: cs.error),
                            const SizedBox(width: 2),
                            Text(
                              '${st.familyNotes.length} 則筆記',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            '點擊聆聽全文 >',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )),

          const SizedBox(height: 6),

          // 底部快捷按鈕：進入回憶錄畫廊與委託小豬提問
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MemoirsGalleryScreen(
                          elderId: elderId,
                          elderName: name,
                          familyUserName: widget.userName,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.menu_book_rounded, size: 16),
                  label: Text(
                    '翻閱自傳畫廊 (${stories.length})',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurface,
                    side: BorderSide(color: cs.outline, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MemoirsGalleryScreen(
                          elderId: elderId,
                          elderName: name,
                          familyUserName: widget.userName,
                        ),
                      ),
                    );
                  },
                  icon: const Text('🐷', style: TextStyle(fontSize: 14)),
                  label: Text(
                    '委託小豬提問',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF97316),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 350.ms);
  }

  // ─── 4. AI 陪伴助理設定狀態與偏好 ───

  Widget _buildAiHelperCard() {
    if (widget.currentElder == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoadingAiProfile) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Center(child: CircularProgressIndicator(color: cs.primary)),
      );
    }

    final appellation = _elderProfileData?['appellation'] ?? widget.currentElder?.appellation ?? '金水阿公';
    final tone = _elderProfileData?['ai_emotion_tone'] ?? 75;
    final verbosity = _elderProfileData?['ai_text_verbosity'] ?? 65;
    final interests = _elderProfileData?['interests'] ?? '懷舊老歌, 台股動態, 泡茶, 散步';

    return Container(
      key: widget.aiHelperKey,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outline, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : cs.outline).withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outline, width: 1.2),
                ),
                child: Icon(Icons.tune_rounded, color: cs.onPrimary, size: 22),
              ),
              const SizedBox(width: 10),
              Text(
                '長輩互動與對話偏好',
                style: GoogleFonts.notoSansTc(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow('互動稱呼長輩', appellation),
          _buildInfoRow('陪伴語氣風格', tone > 60 ? '活潑熱情 (85%)' : tone < 40 ? '沉穩客觀' : '溫和適中'),
          _buildInfoRow('對話回覆篇幅', verbosity > 60 ? '詳細會聊天 (70%)' : verbosity < 40 ? '簡潔扼要' : '適度互動'),
          _buildInfoRow('記憶與話題偏好', interests),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _navigateToElderEdit,
              icon: Icon(Icons.tune_rounded, size: 18, color: cs.onPrimary),
              label: Text(
                '調整互動對話設定',
                style: GoogleFonts.notoSansTc(fontSize: 14, fontWeight: FontWeight.bold, color: cs.onPrimary),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 1,
                shadowColor: cs.primary.withValues(alpha: 0.35),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 150.ms, duration: 350.ms);
  }

  Widget _buildInfoRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 5. 設定項目群組 ───

  Widget _buildSettingsGroup(String groupTitle, List<Widget> items) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outline, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : cs.outline).withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            groupTitle,
            style: GoogleFonts.notoSansTc(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          ...items,
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 350.ms);
  }

  Widget _buildSwitchItem(
    IconData icon,
    String title,
    String description,
    bool value,
    ValueChanged<bool> onChanged,
    Color activeColor,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: cs.outline, width: 1.2),
            ),
            child: Icon(icon, color: activeColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
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
            activeThumbColor: activeColor,
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
    Color themeColor, {
    String? trailingBadge,
  }) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: cs.outline, width: 1.2),
              ),
              child: Icon(icon, color: themeColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (trailingBadge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.outline, width: 1.2),
                ),
                child: Text(
                  trailingBadge,
                  style: GoogleFonts.notoSansTc(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onPrimary),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(Icons.arrow_forward_ios_rounded, color: cs.outline, size: 16),
          ],
        ),
      ),
    );
  }

  // ─── 6. 未選擇長輩引導卡片 ───

  Widget _buildNoElderSelectedCard() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outline, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : cs.outline).withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_outline, size: 48, color: cs.outline),
          const SizedBox(height: 14),
          Text(
            '尚未選擇要關照的長輩',
            style: GoogleFonts.notoSansTc(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            '請在上方切換長輩，或點擊下方按鈕配對新的長輩端設備',
            style: GoogleFonts.notoSansTc(fontSize: 13, color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
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
              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
              label: const Text('配對新長輩裝置'),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 1,
                shadowColor: cs.primary.withValues(alpha: 0.35),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 7. 系統資訊卡片 ───

  Widget _buildSystemInfoCard() {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Uban 智慧伴老照護系統',
            style: GoogleFonts.notoSansTc(fontSize: 12, color: cs.outline, fontWeight: FontWeight.w600),
          ),
          Text(
            'v2.4.0 (Build 2026.08)',
            style: GoogleFonts.inter(fontSize: 12, color: cs.outline),
          ),
        ],
      ),
    );
  }
}
