import 'dart:math' show pi;
import 'package:flutter/material.dart';

// GPS 功能 Demo 頁面
// 已安裝套件：geolocator + google_maps_flutter（見 pubspec.yaml）
// 要顯示真實地圖，請：
//   1. 至 Google Cloud Console 取得 Maps API Key
//   2. 貼到 android/app/src/main/AndroidManifest.xml 的 YOUR_GOOGLE_MAPS_API_KEY_HERE
//   3. 將 _buildMapPlaceholder 換成真正的 GoogleMap() widget
void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const ProfileScreen(),
      theme: ThemeData(
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFF7F7F7),
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  // ── Mock data ───────────────────────────────────────────────
  final String userName = '金大聲';
  final String greetingText = '今天一共走了';
  final String kilometers = '3.5 公里';

  // ── Animation ──────────────────────────────────────────────
  late AnimationController _ctrl;
  late Animation<double> _greenSlide; // 綠卡往下滑出
  late Animation<double> _numScale; // 數字史萊姆縮放
  late Animation<double> _numOpacity; // 數字淡入

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    );

    _greenSlide = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.10, 0.62, curve: Curves.elasticOut),
      ),
    );

    _numScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.60, 1.0, curve: Curves.elasticOut),
      ),
    );

    _numOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.60, 0.75, curve: Curves.easeIn),
      ),
    );

    // 0.2 秒後開始動畫
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ── 登出對話框 ──────────────────────────────────────────────
  void _showLogoutDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (BuildContext context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('確認登出?',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 30),
                _dialogBtn('登出', const Color(0xFFF05161), () {
                  Navigator.of(context).pop();
                }),
                const SizedBox(height: 12),
                _dialogBtn('取消', const Color(0xFFC7C7C7), () {
                  Navigator.of(context).pop();
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dialogBtn(String label, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ── 步數動畫卡片 ────────────────────────────────────────────
  Widget _buildAnimatedStepCard() {
    const double darkCardH = 200.0; // 黑卡高度
    const double greenPeek = 32.0; // 綠卡最終露出高度
    const double greenCardH = 56.0; // 綠卡總高度

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final slide = _greenSlide.value;
        final totalH = darkCardH + greenPeek * slide;

        return SizedBox(
          height: totalH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ① 綠卡（斜的，從黑卡下方彈出）
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Transform.rotate(
                  angle: -3.5 * pi / 180, // 往左傾斜約 3.5 度
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: greenCardH,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF67B99A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),

              // ② 黑卡（上層，靜止）
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: darkCardH,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 標題
                      const Positioned(
                        top: 0,
                        left: 0,
                        child: Text(
                          '步數',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      // 長條圖（對齊底部）
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(child: _buildBar('日', 0.6)),
                            Expanded(child: _buildBar('一', 0.4)),
                            Expanded(child: _buildBar('二', 0.5)),
                            Expanded(child: _buildBar('三', 0.8)),
                            Expanded(child: _buildBarToday('四', 1.0, '8,406')),
                            Expanded(child: _buildBar('五', 0.3)),
                            Expanded(child: _buildBar('六', 0.2)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 一般長條 ────────────────────────────────────────────────
  Widget _buildBar(String day, double ratio) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 90 * ratio,
          decoration: BoxDecoration(
            color: Colors.grey.shade600,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 6),
        Text(day, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
      ],
    );
  }

  // ── 今天長條（泡泡用 Stack 絕對定位，完全擺脫寬度限制）────────
  Widget _buildBarToday(String day, double ratio, String steps) {
    const double barH = 90.0 * 1.0; // ratio = 1.0
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // 泡泡：Positioned 完全脫離 layout flow
            Positioned(
              bottom: barH + 6 + 15 + 8, // bar + SizedBox + dayText高度 + 間距
              child: Opacity(
                opacity: _numOpacity.value,
                child: Transform.scale(
                  scale: _numScale.value,
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          steps,
                          softWrap: false,
                          maxLines: 1,
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      CustomPaint(
                        size: const Size(10, 5),
                        painter: TrianglePainter(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 長條 + 日期文字（決定這個格子的實際高度）
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 6,
                  height: barH,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 6),
                Text(day,
                    style:
                        TextStyle(color: Colors.grey.shade500, fontSize: 11)),
              ],
            ),
          ],
        );
      },
    );
  }

  // ── 地圖佔位（換成真實 GoogleMap widget）──────────────────
  Widget _buildMapPlaceholder() {
    return Container(
      height: 350,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              'GPS 地圖（已安裝 google_maps_flutter）\n取得 API Key 後替換此區塊',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── 主 build ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 標頭
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Colors.grey),
                    child:
                        const Icon(Icons.person, size: 40, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: userName,
                                style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87),
                              ),
                              const TextSpan(
                                text: ' 您好！',
                                style: TextStyle(
                                    fontSize: 22, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '飯後記得出門散散步有助於消化喔',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),

              // 今日公里數
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.directions_walk,
                        size: 40, color: Colors.black54),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(greetingText,
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey.shade600)),
                        const SizedBox(height: 4),
                        Text(kilometers,
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ✨ 步數動畫卡片（黑卡 + 斜綠卡 + 史萊姆數字）
              _buildAnimatedStepCard(),
              const SizedBox(height: 20),

              // 地圖佔位
              _buildMapPlaceholder(),
              const SizedBox(height: 30),

              // 登出按鈕
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _showLogoutDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF05161),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('登出',
                      style: TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        showSelectedLabels: false,
        showUnselectedLabels: false,
        backgroundColor: Colors.white,
        elevation: 10,
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined, color: Colors.grey),
              label: 'Home'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline, color: Colors.grey),
              label: 'Chat'),
          BottomNavigationBarItem(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF67B99A),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_outline, color: Colors.white),
            ),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// 提示框下方小三角
class TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path()
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
