import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
          onUnbind: () async {
            // unbind confirmation is handled in ElderProfileEditScreen
            Navigator.pop(context);
            if (widget.onElderUpdated != null) {
              widget.onElderUpdated!();
            }
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
                
                // 3. AI 輔助資料概覽 (長輩喜好、習慣、健康注意事項)
                _buildAiHelperCard(),
                const SizedBox(height: 20),
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
                  '異常生活作息或情緒警示的主動通知',
                  _isAiInsightOn,
                  (val) => setState(() => _isAiInsightOn = val),
                  const Color(0xFF8B5CF6),
                ),
              ]),
              const SizedBox(height: 20),

              // 5. 配對設定
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
              ]),
              const SizedBox(height: 32),

              // 6. 登出按鈕
              OutlinedButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout_rounded),
                label: Text(
                  '登出目前帳號',
                  style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
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

  Widget _buildCaregiverCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: const Color(0xFFEFF6FF),
            child: Text(
              _caregiverName.isNotEmpty ? _caregiverName[0] : 'U',
              style: GoogleFonts.notoSansTc(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF3B82F6),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _caregiverName,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '家屬帳號 (ID: ${widget.userId})',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _handleEditProfile,
            icon: const Icon(Icons.edit_outlined, color: Color(0xFF64748B)),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildElderSummaryCard() {
    final elder = widget.currentElder!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.elderly_rounded,
                  color: Color(0xFF10B981),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '受關照長輩資料',
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _navigateToElderEdit,
                icon: const Icon(Icons.edit_rounded, size: 14),
                label: Text(
                  '編輯',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF3B82F6),
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
                radius: 28,
                backgroundColor: elder.gender == 'F' ? const Color(0xFFFDF2F8) : const Color(0xFFF0FDF4),
                child: Text(
                  elder.genderEmoji,
                  style: const TextStyle(fontSize: 28),
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
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${elder.age != null ? "${elder.age} 歲" : "年齡未填"} • ${elder.gender == "F" ? "女性" : "男性"} • 居住於 ${elder.location ?? "未設定"}',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFF8B5CF6),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'AI 陪伴助理設定狀態',
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
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
              icon: const Icon(Icons.settings_suggest_rounded, size: 16),
              label: const Text('調整 AI 對話偏好與背景資料'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5F3FF),
                foregroundColor: const Color(0xFF8B5CF6),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E293B),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
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
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF475569),
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
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: activeColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  description,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 11,
                    color: const Color(0xFF64748B),
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
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: themeColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    description,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 11,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF94A3B8), size: 14),
          ],
        ),
      ),
    );
  }
}
