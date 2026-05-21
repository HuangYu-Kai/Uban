import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../controllers/zen_pond_controller.dart'; // 引入 KoiStyle 與 KoiPattern

// 真正會「扭動身軀」且具備豐富細節的漂亮錦鯉 CustomPainter (已支援隨機品種花色)
class PremiumKoiPainter extends CustomPainter {
  final double animationValue; // 0.0 到 1.0 的週期值
  final KoiStyle style;        // 錦鯉品種樣式資料

  PremiumKoiPainter({required this.animationValue, required this.style});

  @override
  void paint(Canvas canvas, Size size) {
    final length = size.height * 0.8; 
    
    // 【使用者回饋調整】將扭動幅度減小，使擺尾動作更為溫和、自然
    final maxWiggle = size.width * 0.11; 

    // 1. 計算魚骨架 (脊椎)
    List<Offset> spine = [];
    final int segments = 20;
    for (int i = 0; i <= segments; i++) {
      double t = i / segments; // 0.0 (頭) 到 1.0 (尾)
      
      // 扭動公式：頭部(t=0)幾乎不動，尾部(t=1)擺動最大
      double wiggle = math.sin(t * math.pi * 2 - animationValue * math.pi * 2) * maxWiggle * math.pow(t, 1.8);
      
      spine.add(Offset(size.width * 0.5 + wiggle, t * length + size.height * 0.1));
    }

    // 計算每個骨架節點的角度與法向量
    List<double> angles = [];
    List<Offset> leftSide = [];
    List<Offset> rightSide = [];

    for (int i = 0; i <= segments; i++) {
      double t = i / segments;
      Offset p = spine[i];
      
      double width;
      if (t < 0.15) {
        width = math.sin(t / 0.15 * math.pi * 0.5) * (size.width * 0.28); 
      } else {
        width = math.cos((t - 0.15) / 0.85 * math.pi * 0.5) * (size.width * 0.28);
      }

      double dx = 1.0;
      double dy = 0.0;
      if (i < segments - 1) {
        double dirX = spine[i+1].dx - p.dx;
        double dirY = spine[i+1].dy - p.dy;
        double len = math.sqrt(dirX * dirX + dirY * dirY);
        if (len > 0) {
          dx = -dirY / len;
          dy = dirX / len;
          angles.add(math.atan2(dirY, dirX));
        } else {
          angles.add(i > 0 ? angles[i-1] : math.pi / 2);
        }
      } else {
        angles.add(angles.isNotEmpty ? angles.last : math.pi / 2);
        if (i > 0) {
          double dirX = p.dx - spine[i-1].dx;
          double dirY = p.dy - spine[i-1].dy;
          double len = math.sqrt(dirX * dirX + dirY * dirY);
          if (len > 0) {
            dx = -dirY / len;
            dy = dirX / len;
          }
        }
      }

      leftSide.add(Offset(p.dx + dx * width, p.dy + dy * width));
      rightSide.add(Offset(p.dx - dx * width, p.dy - dy * width));
    }

    // 使用專屬魚鰭顏色
    final finPaint = Paint()
      ..color = style.finColor
      ..style = PaintingStyle.fill;

    // 2. 畫胸鰭 (Pectoral Fins)
    int finBase = 4;
    int finEnd = 8;
    
    // 左胸鰭
    double leftFinAngle = angles[finBase] + math.pi * 0.35 + math.sin(animationValue * math.pi * 2) * 0.1;
    Path leftFin = Path()
      ..moveTo(leftSide[finBase].dx, leftSide[finBase].dy)
      ..quadraticBezierTo(
        leftSide[finBase].dx + math.cos(leftFinAngle) * size.width * 0.7,
        leftSide[finBase].dy + math.sin(leftFinAngle) * size.width * 0.7,
        leftSide[finEnd].dx, leftSide[finEnd].dy,
      );
    canvas.drawPath(leftFin, finPaint);

    // 右胸鰭
    double rightFinAngle = angles[finBase] - math.pi * 0.35 - math.sin(animationValue * math.pi * 2) * 0.1;
    Path rightFin = Path()
      ..moveTo(rightSide[finBase].dx, rightSide[finBase].dy)
      ..quadraticBezierTo(
        rightSide[finBase].dx + math.cos(rightFinAngle) * size.width * 0.7,
        rightSide[finBase].dy + math.sin(rightFinAngle) * size.width * 0.7,
        rightSide[finEnd].dx, rightSide[finEnd].dy,
      );
    canvas.drawPath(rightFin, finPaint);

    // 3. 畫魚身 (Body)
    final Path bodyPath = Path();
    bodyPath.moveTo(leftSide[0].dx, leftSide[0].dy);
    for (var p in leftSide) {
      bodyPath.lineTo(p.dx, p.dy);
    }
    for (var p in rightSide.reversed) {
      bodyPath.lineTo(p.dx, p.dy);
    }
    bodyPath.close();

    // 使用專屬魚身顏色漸層
    final Rect bounds = bodyPath.getBounds();
    final Paint bodyPaint = Paint()
      ..shader = LinearGradient(
        colors: style.bodyColors,
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(bounds)
      ..style = PaintingStyle.fill;
    
    canvas.drawShadow(bodyPath, Colors.black12, 4.0, false);
    canvas.drawPath(bodyPath, bodyPaint);

    // 4. 畫尾鰭 (Tail Fin)
    canvas.save();
    canvas.translate(spine.last.dx, spine.last.dy);
    canvas.rotate(angles.last - math.pi / 2);
    
    Path tailFin = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(-size.width * 0.4, size.height * 0.1, -size.width * 0.3, size.height * 0.2)
      ..quadraticBezierTo(0, size.height * 0.15, size.width * 0.3, size.height * 0.2)
      ..quadraticBezierTo(size.width * 0.4, size.height * 0.1, 0, 0);
      
    canvas.drawPath(tailFin, finPaint);
    canvas.restore();

    // 5. 繪製花紋 (Markings) - 依據品種模式繪製各異的精細斑紋
    if (style.pattern == KoiPattern.benigoi) {
      // 紅鯉：深紅身軀，背部點綴低調奢華的金沙波光
      final Paint goldSpotPaint = Paint()..color = style.spotColors[0].withOpacity(0.5);
      canvas.drawCircle(spine[3], size.width * 0.15, goldSpotPaint);
      canvas.drawCircle(spine[10], size.width * 0.12, goldSpotPaint);
    } 
    else if (style.pattern == KoiPattern.yamabuki) {
      // 山吹黃金：通體黃金，背部繪製輕微的亮金波光點綴
      final Paint goldSpotPaint = Paint()..color = style.spotColors[0].withOpacity(0.4);
      canvas.drawCircle(spine[3], size.width * 0.15, goldSpotPaint);
      canvas.drawCircle(spine[10], size.width * 0.12, goldSpotPaint);
    } 
    else if (style.pattern == KoiPattern.showa) {
      // 昭和三色：深邃黑底上，點綴交織的大塊純白斑與亮紅斑 (對比極強、霸氣十足)
      final Paint redPaint = Paint()..color = style.spotColors[0].withOpacity(0.95);
      final Paint whitePaint = Paint()..color = style.spotColors[1].withOpacity(0.9);
      
      // 白斑 1
      Path whiteSpot = Path()
        ..moveTo(spine[3].dx, spine[3].dy)
        ..quadraticBezierTo(leftSide[3].dx, leftSide[3].dy, leftSide[6].dx, leftSide[6].dy)
        ..quadraticBezierTo(spine[7].dx, spine[7].dy, rightSide[5].dx, rightSide[5].dy)
        ..close();
      canvas.drawPath(whiteSpot, whitePaint);

      // 紅斑 1
      Path redSpot = Path()
        ..moveTo(spine[11].dx, spine[11].dy)
        ..quadraticBezierTo(leftSide[10].dx, leftSide[10].dy, leftSide[14].dx, leftSide[14].dy)
        ..quadraticBezierTo(spine[15].dx, spine[15].dy, rightSide[13].dx, rightSide[13].dy)
        ..close();
      canvas.drawPath(redSpot, redPaint);

      // 追加白斑 2 (點綴在尾部)
      canvas.drawCircle(Offset(spine[16].dx - 2, spine[16].dy), size.width * 0.08, whitePaint);
    } 
    else {
      // 經典紅白：紅橘底色，搭配大塊流線型雪白塊斑
      final spotPaint = Paint()..color = style.spotColors[0].withOpacity(0.9);
      
      // 頭部白斑
      Path spot1 = Path()
        ..moveTo(spine[2].dx, spine[2].dy)
        ..quadraticBezierTo(leftSide[2].dx, leftSide[2].dy, leftSide[5].dx, leftSide[5].dy)
        ..quadraticBezierTo(spine[6].dx, spine[6].dy, rightSide[3].dx, rightSide[3].dy)
        ..close();
      canvas.drawPath(spot1, spotPaint);
      
      // 背部大白斑
      Path spot2 = Path()
        ..moveTo(spine[9].dx, spine[9].dy)
        ..quadraticBezierTo(leftSide[8].dx, leftSide[8].dy, leftSide[12].dx, leftSide[12].dy)
        ..quadraticBezierTo(spine[14].dx, spine[14].dy, rightSide[13].dx, rightSide[13].dy)
        ..quadraticBezierTo(rightSide[10].dx, rightSide[10].dy, spine[9].dx, spine[9].dy)
        ..close();
      canvas.drawPath(spot2, spotPaint);
    }

    // 6. 畫眼睛 (Eyes)
    final Paint eyePaint = Paint()..color = Colors.black87;
    final Paint eyeWhite = Paint()..color = Colors.white;
    
    Offset leftEye = Offset(leftSide[2].dx * 0.7 + spine[2].dx * 0.3, leftSide[2].dy * 0.7 + spine[2].dy * 0.3);
    Offset rightEye = Offset(rightSide[2].dx * 0.7 + spine[2].dx * 0.3, rightSide[2].dy * 0.7 + spine[2].dy * 0.3);
    
    canvas.drawCircle(leftEye, 3.0, eyePaint);
    canvas.drawCircle(leftEye, 1.0, eyeWhite);
    
    canvas.drawCircle(rightEye, 3.0, eyePaint);
    canvas.drawCircle(rightEye, 1.0, eyeWhite);
  }

  @override
  bool shouldRepaint(covariant PremiumKoiPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue || oldDelegate.style != style;
  }
}

class KoiFishNotification extends StatefulWidget {
  final VoidCallback onTap;
  final KoiStyle koiStyle; // 外部傳入該錦鯉專屬的樣式

  const KoiFishNotification({
    super.key,
    required this.onTap,
    required this.koiStyle,
  });

  @override
  State<KoiFishNotification> createState() => _KoiFishNotificationState();
}

class _KoiFishNotificationState extends State<KoiFishNotification> with SingleTickerProviderStateMixin {
  late AnimationController _swimController;

  // 魚在二維空間中的運動狀態
  late double posX;
  late double posY;
  late double targetX;
  late double targetY;
  late double currentAngle; // 當前游動朝向弧度

  double _screenWidth = 400.0;
  double _screenHeight = 800.0;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    
    // 將擺尾的週期拉長到 1500ms，配合調小的扭動幅度，使運動極其悠閒沉靜
    _swimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // 初始朝向設為左上角
    currentAngle = -math.pi / 4;

    // 監聽動畫幀，執行每幀物理算圖
    _swimController.addListener(_updatePhysics);
  }

  // 隨機選取下一個池塘中的目標點
  void _chooseNewTarget(double width, double height) {
    final random = math.Random();
    double padding = 80.0;
    targetX = padding + random.nextDouble() * (width - 2 * padding);
    targetY = padding + random.nextDouble() * (height - 2 * padding);
  }

  // 每幀物理運算邏輯
  void _updatePhysics() {
    if (!mounted || !_initialized) return;

    final double width = _screenWidth;
    final double height = _screenHeight;

    // 1. 計算與目標點的距離
    double dx = targetX - posX;
    double dy = targetY - posY;
    double distance = math.sqrt(dx * dx + dy * dy);

    // 2. 距離夠近時，選取下一個新隨機目標
    if (distance < 50.0) {
      _chooseNewTarget(width, height);
      return;
    }

    // 3. 計算目標轉向角度
    double targetAngle = math.atan2(dy, dx);

    // 4. 尋求最短旋轉路徑進行平滑轉向 (Steering)
    double angleDifference = targetAngle - currentAngle;
    while (angleDifference < -math.pi) angleDifference += 2 * math.pi;
    while (angleDifference > math.pi) angleDifference -= 2 * math.pi;

    // 設定非常緩慢且優雅的最大轉彎角速度，使轉向呈滑動圓弧狀
    double maxTurnSpeed = 0.012; 
    double turn = angleDifference.clamp(-maxTurnSpeed, maxTurnSpeed);
    currentAngle += turn;

    // 5. 優雅的速度變化邏輯 (轉向大時稍微減速，直線前進時輕微加速)
    double baseSpeed = 0.85; // 悠閒緩慢的基礎速度
    double currentSpeed = baseSpeed;
    if (angleDifference.abs() > 0.4) {
      currentSpeed = baseSpeed * 0.65; // 轉向時慢速
    } else {
      // 直線時給予一個極為緩慢的餘弦呼吸速度波動，模擬真實魚類一下一下划水前進的動態
      currentSpeed = baseSpeed * (1.0 + 0.3 * math.cos(DateTime.now().millisecondsSinceEpoch / 1200));
    }

    // 6. 更新位置並限制於邊界內
    posX += math.cos(currentAngle) * currentSpeed;
    posY += math.sin(currentAngle) * currentSpeed;

    double margin = 40.0;
    posX = posX.clamp(margin, width - margin);
    posY = posY.clamp(margin, height - margin);

    setState(() {});
  }

  @override
  void dispose() {
    _swimController.removeListener(_updatePhysics);
    _swimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    _screenWidth = size.width > 0 ? size.width : 400.0;
    _screenHeight = size.height > 0 ? size.height : 800.0;

    // 首幀在此處進行安全初始化
    if (!_initialized) {
      posX = _screenWidth * 0.8;  // 起始於右下偏上
      posY = _screenHeight * 0.7;
      _chooseNewTarget(_screenWidth, _screenHeight);
      _initialized = true;
    }

    // 依據魚的縮放比例計算尺寸 (基礎大小為 50x100，支援隨機體型變化)
    final double fishWidth = 50 * widget.koiStyle.scale;
    final double fishHeight = 100 * widget.koiStyle.scale;

    return Positioned(
      // posX, posY 代表魚的物理中心，偏移使其置中於座標點 (並考量縮放尺寸)
      left: posX - (fishWidth * 0.9), 
      top: posY - (fishHeight * 0.75),  
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) {}, // 攔截並消耗 tap down 事件，防止觸發背景漣漪與語音對話
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _swimController,
          builder: (context, child) {
            return Transform.rotate(
              angle: currentAngle + math.pi / 2,
              child: Container(
                // 【長輩友善無障礙點擊區】透明的 Padding，大幅擴張觸控面積
                padding: const EdgeInsets.all(20.0),
                color: Colors.transparent,
                child: CustomPaint(
                  size: Size(fishWidth, fishHeight), 
                  painter: PremiumKoiPainter(
                    animationValue: _swimController.value,
                    style: widget.koiStyle,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
