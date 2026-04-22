import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/desktop_pet.dart';

class PetProfileScreen extends StatelessWidget {
  final int userId;
  final int steps;
  final int level;
  final PetMood mood;
  final String assetPath;

  const PetProfileScreen({
    super.key,
    required this.userId,
    required this.steps,
    required this.level,
    required this.mood,
    required this.assetPath,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.pink.shade100,
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              // 小豬大圖與光暈
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 背景光環
                    Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.pink.withValues(alpha: 0.2),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                    ).animate(onPlay: (c) => c.repeat(reverse: true))
                     .scaleXY(begin: 0.95, end: 1.05, duration: 2.seconds),
                    
                    // 小豬本體
                    Hero(
                      tag: 'desktop_pet',
                      child: Image.asset(
                        assetPath,
                        height: 180,
                        fit: BoxFit.contain,
                      ),
                    ).animate()
                     .moveY(begin: 0, end: -10, duration: 1500.ms, curve: Curves.easeInOutSine)
                     .then()
                     .moveY(begin: -10, end: 0, duration: 1500.ms, curve: Curves.easeInOutSine),
                  ],
                ),
              ),
              
              const SizedBox(height: 30),
              
              // 資訊區塊
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(40),
                      topRight: Radius.circular(40),
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5)),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "小豬皮皮",
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF1E293B),
                                  ),
                                ),
                                Text(
                                  "今天的心情：${_getMoodText(mood)}",
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: 16,
                                    color: Colors.pinkAccent,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            _buildLevelBadge(level),
                          ],
                        ),
                        
                        const SizedBox(height: 32),
                        
                        // 數據卡片
                        Row(
                          children: [
                            _buildStatCard("今日步數", steps.toString(), Icons.directions_walk, Colors.blue),
                            const SizedBox(width: 16),
                            _buildStatCard("結識天數", "12 天", Icons.favorite, Colors.red),
                          ],
                        ),
                        
                        const SizedBox(height: 32),
                        
                        Text(
                          "餵食互動",
                          style: GoogleFonts.notoSansTc(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // 餵食按鈕區域
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.orange.shade100, width: 2),
                          ),
                          child: Row(
                            children: [
                              Image.asset('assets/images/pig_2d_happy_v4.png', height: 60), // 暫用 happy 當圖標
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "獲得幸運蘋果",
                                      style: GoogleFonts.notoSansTc(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade800,
                                      ),
                                    ),
                                    Text(
                                      "今日步數已達標，快餵小豬吃蘋果吧！",
                                      style: GoogleFonts.notoSansTc(
                                        fontSize: 14,
                                        color: Colors.orange.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  // 餵食邏輯
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  shape: const CircleBorder(),
                                  padding: const EdgeInsets.all(12),
                                ),
                                child: const Icon(Icons.restaurant, color: Colors.white),
                              ),
                            ],
                          ),
                        ).animate().fadeIn(delay: 400.ms).slideX(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLevelBadge(int level) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.pink,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Text(
        "等級 $level",
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.1), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
            Text(
              value,
              style: GoogleFonts.rubik(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getMoodText(PetMood mood) {
    switch (mood) {
      case PetMood.energetic: return "活力百倍 ✨";
      case PetMood.lazy: return "懶洋洋 👣";
      case PetMood.tired: return "累呼呼 💤";
      case PetMood.normal: return "平靜安穩 😊";
    }
  }
}
