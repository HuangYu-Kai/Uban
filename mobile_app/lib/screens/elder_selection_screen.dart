import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'family_main_screen.dart';
import 'caregiver_pairing_screen.dart';

class ElderSelectionScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const ElderSelectionScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<ElderSelectionScreen> createState() => _ElderSelectionScreenState();
}

class _ElderSelectionScreenState extends State<ElderSelectionScreen> {
  List<dynamic> _elders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchElders();
  }

  Future<void> _fetchElders() async {
    try {
      final elders = await ApiService.getPairedElders(widget.userId);
      if (mounted) {
        setState(() {
          _elders = elders;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectElder(dynamic elder) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selected_elder_id', elder['id']);
    await prefs.setString('selected_elder_name', elder['user_name']);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) =>
            FamilyMainScreen(userId: widget.userId, userName: widget.userName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF0), // 米黃色背景
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 32),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(height: 10),
              Text(
                '選擇陪伴對象',
                style: GoogleFonts.notoSansTc(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '點擊頭像進入儀表板，或新增家人',
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 40),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 0.85,
                            ),
                        itemCount: _elders.length + 1,
                        itemBuilder: (context, index) {
                          if (index < _elders.length) {
                            return _buildElderCard(_elders[index]);
                          } else {
                            return _buildAddCard();
                          }
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildElderCard(dynamic elder) {
    final bool isOnline = elder['is_online'] ?? false;
    final String gender = elder['gender'] ?? 'M';

    return GestureDetector(
      onTap: () => _selectElder(elder),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 45,
                  backgroundColor: gender == 'M'
                      ? const Color(0xFFE0F2FE)
                      : const Color(0xFFFFF7ED),
                  child: Icon(
                    gender == 'M' ? Icons.face : Icons.face_3,
                    size: 56,
                    color: gender == 'M'
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFFF97316),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green : Colors.grey[400],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              elder['user_name'] ?? '未知',
              style: GoogleFonts.notoSansTc(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isOnline ? '守護中' : '休息中',
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                color: isOnline ? Colors.green[600] : Colors.grey[500],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddCard() {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CaregiverPairingScreen(
              familyId: widget.userId,
              familyName: widget.userName,
            ),
          ),
        );
        _fetchElders(); // 返回後刷新列表
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.grey[300]!,
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_circle_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              '綁定新裝置',
              style: GoogleFonts.notoSansTc(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
