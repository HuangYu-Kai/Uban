import 'package:flutter/material.dart';

// 此檔案為展示用的單頁面 UI，包含畫面的刻板與所有的主要元件（長條圖、地圖框架、登出對話框）。
// 之後在專案中實際開發，可把 Mock 資料換成從 State (像是 Provider, Riverpod, Geolocator 等) 拿真實數據。
void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const ProfileScreen(),
      theme: ThemeData(
        fontFamily: 'Roboto', // 想換字體可以在這邊調整
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

class _ProfileScreenState extends State<ProfileScreen> {
  // Mock data (假資料)
  final String userName = '金大聲';
  final String greetingText = '今天一共走了';
  final String kilometers = '3.5 公里';

  // 顯示登出對話框
  void _showLogoutDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black26, // 讓背景些微暗下
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min, // 高度貼齊內容
              children: [
                const Text(
                  '確認登出?',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 30),
                // 登出按鈕
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      // TODO: 填入真的登出邏輯 (清除token、轉回登入頁等)
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF05161),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      '登出',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 取消按鈕
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC7C7C7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      '取消',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 標頭區 - 頭貼與歡迎詞
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey,
                      // TODO: 如果有圖片，打開這段並放入圖檔
                      // image: DecorationImage(image: AssetImage('assets/avatar.png'), fit: BoxFit.cover),
                    ),
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
                                  color: Colors.black87,
                                ),
                              ),
                              const TextSpan(
                                text: ' 您好！',
                                style: TextStyle(
                                  fontSize: 22,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '飯後記得出門散散步有助於消化喔',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
              const SizedBox(height: 30),

              // 今日公里數卡片
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    // 可以換成圖片 Image.asset()
                    const Icon(Icons.directions_walk,
                        size: 40, color: Colors.black54),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greetingText,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          kilometers,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 黑底步數長條圖區塊
              Container(
                height: 200,
                decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(20),
                    // 下方綠色的陰影裝飾
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF67B99A).withOpacity(0.8),
                        offset: const Offset(4, 9),
                        blurRadius: 0,
                        spreadRadius: -10,
                      ),
                    ]),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '步數',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    // 模擬的圖表 (實際開發請替換成 fl_chart 套件畫出的 BarChart)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildBar('日', 0.6, false),
                        _buildBar('一', 0.4, false),
                        _buildBar('二', 0.5, false),
                        _buildBar('三', 0.8, false),
                        _buildBar('四', 1.0, true, steps: '8,406'),
                        _buildBar('五', 0.3, false),
                        _buildBar('六', 0.2, false),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // GPS 軌跡地圖區塊
              Container(
                height: 350,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // TODO: 在這邊放入 GoogleMap() // google_maps_flutter 套件
                    // 並傳入 polylines 來畫出黑線
                    Center(
                      child: Text(
                        '地圖與軌跡視圖\n(需安裝並放入 google_maps_flutter 與 geolocator)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // 底部大登出按鈕
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _showLogoutDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF05161),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '登出',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      // App底部的導覽列
      bottomNavigationBar: BottomNavigationBar(
        showSelectedLabels: false,
        showUnselectedLabels: false,
        backgroundColor: Colors.white,
        elevation: 10, // 給上方加一點陰影
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined, color: Colors.grey),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline, color: Colors.grey),
            label: 'Chat',
          ),
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

  // 繪製單根長條與提示框的工具 Function
  Widget _buildBar(String day, double heightRatio, bool isToday,
      {String? steps}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isToday && steps != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              steps,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          CustomPaint(
            size: const Size(10, 5),
            painter: TrianglePainter(),
          ),
          const SizedBox(height: 4),
        ],
        Container(
          width: 6,
          height: 100 * heightRatio, // 最高設為 100
          decoration: BoxDecoration(
            color: isToday ? Colors.white : Colors.grey.shade600,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          day,
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

// 用來畫白色提示框下方小三角形的自定義 Painter
class TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()..color = Colors.white;
    var path = Path();
    path.lineTo(size.width / 2, size.height);
    path.lineTo(size.width, 0);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
