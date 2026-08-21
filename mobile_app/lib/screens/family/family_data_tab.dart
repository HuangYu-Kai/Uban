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

/// ⚙️ 子女端「資料與設定」Tab (FamilyDataTab)
/// 包含：照顧者資訊、關照長輩完整檔案、AI 陪伴偏好、人生故事膠囊、安全通知設定、裝置與訂閱管理
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

  @override
  void initState() {
    super.initState();
    _caregiverName = widget.userName;
    _loadCaregiverName();
    _loadSubscriptionInfo();
    _loadAiProfile();
  }

  @override
  void didUpdateWidget(FamilyDataTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentElder?.id != oldWidget.currentElder?.id ||
        widget.currentElder?.elderId != oldWidget.currentElder?.elderId) {
      _loadAiProfile();
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
    final TextEditingController controller = TextEditingController(text: _caregiverName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: Color(0xFF38BDF8), size: 24),
            const SizedBox(width: 8),
            Text(
              '編輯我的顯示名稱',
              style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: TextField(
          controller: controller,
          style: GoogleFonts.notoSansTc(color: Colors.white),
          decoration: InputDecoration(
            hintText: '輸入您的稱呼 (例: 大兒子、小女兒)',
            hintStyle: GoogleFonts.notoSansTc(color: const Color(0xFF64748B)),
            filled: true,
            fillColor: const Color(0xFF1E293B),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF334155)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF334155)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF38BDF8)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: GoogleFonts.notoSansTc(color: const Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: const Color(0xFF0F172A),
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
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 24),
            const SizedBox(width: 8),
            Text(
              '安全登出',
              style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          '確定要登出當前帳號並回到身分選擇頁面嗎？',
          style: GoogleFonts.notoSansTc(color: const Color(0xFFCBD5E1), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('取消', style: GoogleFonts.notoSansTc(color: const Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.link_off_rounded, color: Color(0xFFEF4444), size: 24),
            const SizedBox(width: 8),
            Text('解除綁定確認', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Text(
          '確定要解除與「${elder.name}」的照護配對嗎？\n\n⚠️ 解除後您將無法再接收該長輩的健康警報與即時狀態。',
          style: GoogleFonts.notoSansTc(color: const Color(0xFFEF4444), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: GoogleFonts.notoSansTc(color: const Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
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
    
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
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
                      fontSize: 14,
                      color: const Color(0xFFCBD5E1),
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
                              color: const Color(0xFFFCA5A5),
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
                          side: const BorderSide(color: Color(0xFF475569), width: 1.2),
                        ),
                        child: Text(
                          '取消',
                          style: GoogleFonts.notoSansTc(
                            color: const Color(0xFF94A3B8),
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

              // 2. 當前受關照長輩詳細健康資料 (Elder Profile Summary)
              if (widget.currentElder != null) ...[
                _buildElderSummaryCard(),
                const SizedBox(height: 18),

                // 3. 長輩人生故事膠囊 (Memoirs & Family Legacy)
                _buildMemoirsCard(),
                const SizedBox(height: 18),

                // 4. AI 陪伴助理設定狀態與偏好 (AI Companion Persona)
                _buildAiHelperCard(),
                const SizedBox(height: 18),
              ] else ...[
                // 未選擇長輩引導卡片
                _buildNoElderSelectedCard(),
                const SizedBox(height: 18),
              ],

              // 5. 智慧照護與即時通知設定 (Smart Care & Notification)
              _buildSettingsGroup('🔔 智慧安全防護與推播設定', [
                _buildSwitchItem(
                  Icons.emergency_rounded,
                  '緊急廣播與跌倒求救通知',
                  '長輩端觸發緊急警報時，第一時間彈窗並強制響鈴提醒',
                  _isEmergencyOn,
                  (val) => setState(() => _isEmergencyOn = val),
                  const Color(0xFFEF4444),
                ),
                _buildSwitchItem(
                  Icons.medication_rounded,
                  '服藥打卡與關懷排程提醒',
                  '長輩完成吃藥打卡或未按時服藥時，即時推播回報',
                  _isMedicationPushOn,
                  (val) => setState(() => _isMedicationPushOn = val),
                  const Color(0xFF10B981),
                ),
                _buildSwitchItem(
                  Icons.summarize_rounded,
                  '每日傍晚健康日誌摘要',
                  '每日 18:00 推播長輩今日活動紀錄與心情氣象速報',
                  _isDailySummaryOn,
                  (val) => setState(() => _isDailySummaryOn = val),
                  const Color(0xFFF59E0B),
                ),
                _buildSwitchItem(
                  Icons.psychology_rounded,
                  'AI 異常情緒主動預警',
                  '長輩生活作息不規律或情緒低落時的主動關懷建議',
                  _isAiInsightOn,
                  (val) => setState(() => _isAiInsightOn = val),
                  const Color(0xFF8B5CF6),
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
                  const Color(0xFF38BDF8),
                  trailingBadge: _subscriptionDisplay,
                ),
                const Divider(height: 16, color: Color(0xFF334155)),
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
                  const Color(0xFF10B981),
                ),
                if (widget.currentElder != null) ...[
                  const Divider(height: 16, color: Color(0xFF334155)),
                  _buildActionItem(
                    Icons.phonelink_setup_rounded,
                    '長輩移機與免密重裝助手',
                    '產生 15 分鐘專屬登入連結，長輩換手機或重裝時一鍵復原',
                    _showRecoveryAssistantDialog,
                    const Color(0xFFFF7043),
                  ),
                ],
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
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B132B), Color(0xFF1E293B)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 6),
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
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    _caregiverName.isNotEmpty ? _caregiverName[0].toUpperCase() : 'U',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 26,
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _caregiverName.isNotEmpty ? _caregiverName : '主要照護家屬',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _handleEditProfile,
                          icon: const Icon(Icons.edit_outlined, color: Color(0xFF38BDF8), size: 18),
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
                            color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '家屬管理員',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 11,
                              color: const Color(0xFF38BDF8),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '帳號 ID: ${widget.userId}',
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
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: Color(0xFF38BDF8), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '方案等級：',
                    style: GoogleFonts.notoSansTc(fontSize: 13, color: const Color(0xFF94A3B8)),
                  ),
                  Text(
                    _subscriptionDisplay,
                    style: GoogleFonts.notoSansTc(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF38BDF8)),
                  ),
                  const Spacer(),
                  Text(
                    '管理方案',
                    style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 16),
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
    
    final chronicDiseases = _elderProfileData?['chronic_diseases'] ?? '無特別記載';
    final medicationNotes = _elderProfileData?['medication_notes'] ?? '照護提醒正常';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF064E3B), Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.15),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.elderly_rounded, color: Color(0xFF34D399), size: 22),
              ),
              const SizedBox(width: 10),
              Text(
                '受關照長輩檔案',
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
                  '編輯資料',
                  style: GoogleFonts.notoSansTc(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF34D399),
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.2),
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
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '長輩端: ${elder.elderId ?? "E00${elder.id}"}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF34D399),
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
                        color: const Color(0xFFCBD5E1),
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
              color: const Color(0xFF0B132B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.favorite_rounded, color: Color(0xFFEF4444), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '慢性病與健康注意：',
                      style: GoogleFonts.notoSansTc(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)),
                    ),
                    Expanded(
                      child: Text(
                        chronicDiseases,
                        style: GoogleFonts.notoSansTc(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.medication_liquid_rounded, color: Color(0xFF38BDF8), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '用藥備註：',
                      style: GoogleFonts.notoSansTc(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)),
                    ),
                    Expanded(
                      child: Text(
                        medicationNotes,
                        style: GoogleFonts.notoSansTc(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
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

    final List<Map<String, String>> stories = [
      {
        'title': '大稻埕布莊歲月 (1975年)',
        'tag': '經典回憶',
        'preview': '年輕時在迪化街經營布料批發，堅持選用頂級棉麻，結交了許多一輩子的摯友與商界老搭檔...',
      },
      {
        'title': '給兒女與孫子的一封信',
        'tag': '溫馨寄語',
        'preview': '希望孩子們健康平安，阿公永遠記得你們第一次學會騎腳踏車時，全家在河濱公園歡笑的模樣...',
      },
      {
        'title': '最懷念的柴燒紅豆湯滋味',
        'tag': '美食記憶',
        'preview': '媽媽當年手作的柴燒紅豆湯，慢火熬煮出綿密甘甜，那是童年記憶中最溫暖的冬日滋味...',
      },
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF261C05), Color(0xFF1F1703)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5), width: 1.2),
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
              Expanded(
                child: Row(
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
                    Flexible(
                      child: Text(
                        '📖 $name的人生故事膠囊',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFFDE68A),
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
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '珍藏 3 篇',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF451A03),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '由 AI 陪伴對話口述整理紀錄，珍藏長輩的人生智慧與家族回憶',
            style: GoogleFonts.notoSansTc(
              fontSize: 12,
              color: const Color(0xFFFDE68A).withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 14),
          ...stories.map((st) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF140F04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        st['title']!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFFEF3C7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        st['tag']!,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFFCD34D),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  st['preview']!,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12,
                    color: const Color(0xFFFDE68A).withValues(alpha: 0.85),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 350.ms);
  }

  // ─── 4. AI 陪伴助理設定狀態與偏好 ───

  Widget _buildAiHelperCard() {
    if (widget.currentElder == null) return const SizedBox.shrink();
    if (_isLoadingAiProfile) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6))),
      );
    }

    final appellation = _elderProfileData?['appellation'] ?? widget.currentElder?.appellation ?? '金水阿公';
    final tone = _elderProfileData?['ai_emotion_tone'] ?? 75;
    final verbosity = _elderProfileData?['ai_text_verbosity'] ?? 65;
    final interests = _elderProfileData?['interests'] ?? '懷舊老歌, 台股動態, 泡茶, 散步';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E1065), Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFA78BFA), size: 22),
              ),
              const SizedBox(width: 10),
              Text(
                'AI 陪伴助理個性偏好',
                style: GoogleFonts.notoSansTc(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow('AI 稱呼長輩', appellation),
          _buildInfoRow('陪伴語氣風格', tone > 60 ? '活潑熱情 (85%)' : tone < 40 ? '沉穩客觀' : '溫和適中'),
          _buildInfoRow('對話回覆篇幅', verbosity > 60 ? '詳細會聊天 (70%)' : verbosity < 40 ? '簡潔扼要' : '適度互動'),
          _buildInfoRow('記憶與話題偏好', interests),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _navigateToElderEdit,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(
                '調整 AI 陪伴設定',
                style: GoogleFonts.notoSansTc(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 150.ms, duration: 350.ms);
  }

  Widget _buildInfoRow(String label, String value) {
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
                color: const Color(0xFFA5B4FC),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
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

  // ─── 5. 設定項目群組 ───

  Widget _buildSettingsGroup(String groupTitle, List<Widget> items) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B132B), Color(0xFF1E293B)],
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
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF38BDF8),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
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
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12,
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
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 12,
                      color: const Color(0xFF94A3B8),
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
                  color: themeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: themeColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  trailingBadge,
                  style: GoogleFonts.notoSansTc(fontSize: 11, fontWeight: FontWeight.bold, color: themeColor),
                ),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF64748B), size: 16),
          ],
        ),
      ),
    );
  }

  // ─── 6. 未選擇長輩引導卡片 ───

  Widget _buildNoElderSelectedCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_outline, size: 48, color: Colors.grey[500]),
          const SizedBox(height: 14),
          Text(
            '尚未選擇要關照的長輩',
            style: GoogleFonts.notoSansTc(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            '請在上方切換長輩，或點擊下方按鈕配對新的長輩端設備',
            style: GoogleFonts.notoSansTc(fontSize: 13, color: const Color(0xFF94A3B8)),
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
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 7. 系統資訊卡片 ───

  Widget _buildSystemInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B132B).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Uban 智慧伴老照護系統',
            style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
          ),
          Text(
            'v2.4.0 (Build 2026.08)',
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}
