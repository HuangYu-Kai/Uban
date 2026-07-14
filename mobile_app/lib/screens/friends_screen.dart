import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'elder_screen.dart';

/// 長輩端「朋友列表」全畫面（撥號為主）。
///
/// 只負責 UI 呈現：讀取已配對家屬（沿用 `ApiService.getPairedFamily`），
/// 以長輩友善的大卡片列出，點擊即可語音 / 視訊通話（沿用既有 `ElderScreen` 通話入口）。
/// 不涉及任何 WebRTC / 信令 / GPS 等功能邏輯的修改。
class FriendsScreen extends StatefulWidget {
  final int userId;
  final String userName;
  final String? roomId;

  const FriendsScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.roomId,
  });

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  List<dynamic> _familyList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFamily();
  }

  Future<void> _fetchFamily() async {
    try {
      final family = await ApiService.getPairedFamily(widget.userId);
      if (mounted) {
        setState(() {
          _familyList = family;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 沿用長輩端既有通話入口（ElderScreen），不修改通話邏輯。
  void _startCall(String friendName, {required bool isVideo}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ElderScreen(
          roomId: widget.roomId ?? widget.userId.toString(),
          deviceName: widget.userName,
          autoCall: true,
          isVideoCall: isVideo,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          '我的朋友',
          style: GoogleFonts.notoSansTc(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        toolbarHeight: 80,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _familyList.isEmpty
                ? _buildEmptyState()
                : _buildFriendList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group_outlined, size: 96, color: AppColors.textHint),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '目前還沒有朋友',
            style: GoogleFonts.notoSansTc(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '請家人先完成配對',
            style: GoogleFonts.notoSansTc(
              fontSize: 18,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendList() {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _familyList.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final map = _familyList[index] is Map
            ? _familyList[index] as Map
            : <String, dynamic>{};
        final name = (map['user_name'] ?? '家人').toString();
        return _buildFriendCard(name);
      },
    );
  }

  Widget _buildFriendCard(String name) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgAll,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 38,
                backgroundColor: AppColors.primaryLight,
                child: Text(
                  name.isNotEmpty ? name.substring(0, 1) : '家',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '家人',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 18,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _buildCallButton(
                  icon: Icons.call_rounded,
                  label: '語音',
                  color: AppColors.primary,
                  onTap: () => _startCall(name, isVideo: false),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildCallButton(
                  icon: Icons.videocam_rounded,
                  label: '視訊',
                  color: AppColors.primaryDark,
                  onTap: () => _startCall(name, isVideo: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCallButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mdAll,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: color,
          borderRadius: AppRadius.mdAll,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 30),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: GoogleFonts.notoSansTc(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
