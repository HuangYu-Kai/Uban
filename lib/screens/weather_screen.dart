import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';

class WeatherScreen extends StatelessWidget {
  const WeatherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE0F7FA), // 清爽藍底
      appBar: AppBar(
        title: Text(
          '天氣預報',
          style: GoogleFonts.notoSansTc(
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0,
        toolbarHeight: 80,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // 1. 今日天氣大卡片
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 32,
                  horizontal: 24,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4FC3F7), Color(0xFF0288D1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // 地區
                    Text(
                      '台北市',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 32,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 圖示 + 溫度
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const FaIcon(
                          FontAwesomeIcons.cloudSun,
                          size: 80,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 24),
                        Text(
                          '24°C',
                          style: GoogleFonts.inter(
                            fontSize: 80,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '多雲時晴',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 詳細資訊 (降雨/濕度)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildDetailItem(
                          FontAwesomeIcons.umbrella,
                          '降雨機率',
                          '10%',
                        ),
                        _buildDetailItem(FontAwesomeIcons.droplet, '濕度', '65%'),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.1, end: 0),

              const SizedBox(height: 32),

              // 2. 未來預報標題
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '未來天氣',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 3. 預報列表
              _buildForecastItem('明天早上', FontAwesomeIcons.sun, '晴天', '26°C'),
              const SizedBox(height: 16),
              _buildForecastItem(
                '明天下午',
                FontAwesomeIcons.cloudSun,
                '多雲',
                '25°C',
              ),
              const SizedBox(height: 16),
              _buildForecastItem(
                '明天晚上',
                FontAwesomeIcons.cloudMoon,
                '涼爽',
                '22°C',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Column(
      children: [
        FaIcon(icon, color: Colors.white.withOpacity(0.8), size: 30),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.notoSansTc(
            fontSize: 20,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildForecastItem(
    String time,
    IconData icon,
    String status,
    String temp,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 20,
        horizontal: 16,
      ), // 減少左右內距
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 時間 (左)
          Expanded(
            flex: 4,
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                time,
                style: GoogleFonts.notoSansTc(
                  fontSize: 28, // 大字
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ),
          ),
          // 資訊 (右)
          Expanded(
            flex: 6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FaIcon(icon, size: 40, color: Colors.orange), // 大圖
                const SizedBox(width: 8), // 縮小間距
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      status,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 24,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8), // 縮小間距
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      temp,
                      style: GoogleFonts.inter(
                        fontSize: 32, // 大數字
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideX();
  }
}
