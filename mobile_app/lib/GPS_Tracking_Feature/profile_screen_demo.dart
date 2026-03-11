import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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

  // ── 步數動畫 ──────────────────────────────────────────────
  late AnimationController _ctrl;
  late Animation<double> _greenSlide;
  late Animation<double> _numScale;
  late Animation<double> _numOpacity;

  // ── GPS 追蹤 ──────────────────────────────────────────────
  bool _isTracking = false;
  final List<LatLng> _routePoints = [];
  StreamSubscription<Position>? _positionStream;
  final MapController _mapController = MapController();
  double _totalDistance = 0.0; // 公里
  LatLng? _currentPosition;
  // 台北 101 作為預設中心點
  static const LatLng _defaultCenter = LatLng(25.0339, 121.5645);

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

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _ctrl.forward();
    });

    _autoStartTracking();
  }

  // ── 自動啟動追蹤與持久化初始化 ──────────────────────────────
  Future<void> _autoStartTracking() async {
    await _loadPersistedRoute();
    await _startTracking();
  }

  // ── 載入持久化路徑 ──────────────────────────────────────────
  Future<void> _loadPersistedRoute() async {
    final prefs = await SharedPreferences.getInstance();
    
    // [清除舊資料] 強制清除先前儲存的美國位置以便能顯示最新狀況
    await prefs.remove('route_points');
    await prefs.remove('total_distance');

    final dateStr = prefs.getString('last_track_date') ?? '';
    final today = DateTime.now().toIso8601String().substring(0, 10);

    if (dateStr != today) {
      // 跨日，清空數據
      await prefs.remove('route_points');
      await prefs.setDouble('total_distance', 0.0);
      await prefs.setString('last_track_date', today);
      return;
    }

    // 載入當日已有點位
    final pointsJson = prefs.getString('route_points');
    if (pointsJson != null) {
      final List<dynamic> decoded = jsonDecode(pointsJson);
      setState(() {
        _routePoints.addAll(
          decoded.map((p) => LatLng(p['lat'], p['lng'])).toList(),
        );
        _totalDistance = prefs.getDouble('total_distance') ?? 0.0;
      });
    }

    // [測試用] 強制載入中正紀念堂到台北商業大學的假路徑（供展示用）
    // 放於最後確保能夠蓋過所有先前的錯誤歷史紀錄。
    _loadMockDemoRoute();
  }

  // ── 儲存當前點位與里程 ──────────────────────────────────────
  Future<void> _persistRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final pointsJson = jsonEncode(
      _routePoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
    );
    await prefs.setString('route_points', pointsJson);
    await prefs.setDouble('total_distance', _totalDistance);
  }

  // ── [展示用] 載入中正紀念堂到北商的假路徑 ───────────────────
  void _loadMockDemoRoute() {
    // 中正紀念堂 (25.0346, 121.5218) 到 台北商業大學 (25.0423, 121.5249) 的大致路段
    final mockPoints = [
      const LatLng(25.0346, 121.5218), // 中正紀念堂
      const LatLng(25.0355, 121.5218), // 中山南路往北
      const LatLng(25.0368, 121.5219), // 靠近仁愛路路口
      const LatLng(25.0375, 121.5222), // 轉向林森南路
      const LatLng(25.0390, 121.5225), // 沿著林森南路往北
      const LatLng(25.0405, 121.5230), // 濟南路交叉口
      const LatLng(25.0423, 121.5249), // 抵達北商附近
    ];
    setState(() {
      _routePoints.clear();
      _routePoints.addAll(mockPoints);
      _currentPosition = mockPoints.last;
      _totalDistance = 1.25; // 假裝走了 1.25 km
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _positionStream?.cancel();
    super.dispose();
  }

  // ── 請求位置權限 ────────────────────────────────────────
  Future<bool> _requestPermission() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  // ── 開始 GPS 追蹤（自動前景服務版） ────────────────────────
  Future<void> _startTracking() async {
    if (_isTracking) return;

    final granted = await _requestPermission();
    if (!granted) {
      return;
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position pos) {
      final newPoint = LatLng(pos.latitude, pos.longitude);

      if (_routePoints.isNotEmpty) {
        final lastPoint = _routePoints.last;
        final distM = Geolocator.distanceBetween(
          lastPoint.latitude,
          lastPoint.longitude,
          newPoint.latitude,
          newPoint.longitude,
        );
        // 過濾雜訊：若移動距離太小或跳動過大則忽略
        if (distM > 2.0) {
          _totalDistance += distM / 1000.0;
          setState(() {
            _routePoints.add(newPoint);
            _persistRoute(); // 持久化
          });
        }
      } else {
        setState(() => _routePoints.add(newPoint));
      }

      setState(() => _currentPosition = newPoint);

      // ── 自動自適應視角 (Auto-Fit Bounds) ─────────────────────
      if (_routePoints.length > 1) {
        // 算出所有點的邊界
        final bounds = LatLngBounds.fromPoints(_routePoints);
        // 如果地圖還沒準備好會報錯，所以加個 try-catch 或檢查
        try {
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(40.0), // 留出邊界空間
            ),
          );
        } catch (_) {}
      } else {
        // 只有一個點時，直接切到該點並拉近
        if (_mapController.camera.zoom != 0) {
          _mapController.move(newPoint, 18.0);
        }
      }
    });

    setState(() {
      _isTracking = true;
    });
  }

  // ── 登出對話框 ──────────────────────────────────────────────
  void _showLogoutDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black26,
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
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '確認登出?',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ── 步數動畫卡片 ────────────────────────────────────────────
  Widget _buildAnimatedStepCard() {
    const double darkCardH = 200.0;
    const double greenPeek = 32.0;
    const double greenCardH = 56.0;

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
              // ① 綠卡
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Transform.rotate(
                  angle: -0.0611, // -3.5 度，約等於 -3.5 * pi / 180
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
              // ② 黑卡
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
                      const Positioned(
                        top: 0,
                        left: 0,
                        child: Text(
                          '步數',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
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

  Widget _buildBarToday(String day, double ratio, String steps) {
    const double barH = 90.0;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              bottom: barH + 6 + 15 + 8,
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
                          horizontal: 8,
                          vertical: 4,
                        ),
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
                            fontWeight: FontWeight.bold,
                          ),
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
                Text(
                  day,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // ── ✨ 真實 OpenStreetMap 地圖 + GPS 追蹤 ────────────────────
  Widget _buildRealMap() {
    return Container(
      height: 380,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // ── FlutterMap ──────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _routePoints.isNotEmpty
                  ? _routePoints.last
                  : (_currentPosition ?? _defaultCenter),
              initialZoom: 18.0,
              initialCameraFit: _routePoints.length > 1
                  ? CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(_routePoints),
                      padding: const EdgeInsets.all(40.0),
                    )
                  : null,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none, // 依然禁止手動拖動/縮放
              ),
            ),
            children: [
              // CartoDB Positron：極簡淡色底圖（類 Nike Run 風格）
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                retinaMode: true,
                userAgentPackageName: 'com.uban.app',
                maxZoom: 20,
              ),
              // 追蹤路線（黑色粗線，Nike Run 風格）
              if (_routePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5.5,
                      color: const Color(0xFF111111),
                      borderStrokeWidth: 1.5,
                      borderColor: const Color(0xFF444444),
                      strokeJoin: StrokeJoin.round,
                      strokeCap: StrokeCap.round,
                    ),
                  ],
                ),
              // ── 起點標記（綠色實心圓）──────────────────────────
              if (_routePoints.isNotEmpty)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _routePoints.first,
                      width: 22,
                      height: 22,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF4CAF50),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              // ── 目前位置：大頭貼地圖釘 ────────────────────────
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition!,
                      width: 54,
                      height: 66,
                      alignment: Alignment.bottomCenter,
                      child: const _AvatarPin(),
                    ),
                  ],
                ),
            ],
          ),

          // ── OSM 標示（右下角極小化） ───────────────────────────
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                '© CartoDB',
                style: TextStyle(fontSize: 8, color: Colors.black38),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 主 build ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ScrollConfiguration(
          behavior: const ScrollBehavior().copyWith(overscroll: false), // 停用 Android 12+ 果凍拉伸特效
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(), // 停用 iOS/Android 的拉伸回彈效果
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
                      shape: BoxShape.circle,
                      color: Colors.grey,
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 40,
                      color: Colors.white,
                    ),
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
                    const Icon(
                      Icons.directions_walk,
                      size: 40,
                      color: Colors.black54,
                    ),
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

              // 步數動畫卡片
              _buildAnimatedStepCard(),
              const SizedBox(height: 20),

              // ✨ 真實 OpenStreetMap 地圖 + GPS 追蹤
              _buildRealMap(),
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
      ),
      bottomNavigationBar: BottomNavigationBar(
        showSelectedLabels: false,
        showUnselectedLabels: false,
        backgroundColor: Colors.white,
        elevation: 10,
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
}

// ── 追蹤中紅點動畫 ───────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _a = Tween<double>(begin: 0.4, end: 1.0).animate(_c);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, __) => Opacity(
        opacity: _a.value,
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// ── 大頭貼地圖釘（目前位置） ────────────────────────────────
class _AvatarPin extends StatelessWidget {
  const _AvatarPin();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 圓形大頭貼
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFE0E0E0),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const ClipOval(
            child: Icon(Icons.person, size: 30, color: Color(0xFF757575)),
          ),
        ),
        // 三角形針腳
        CustomPaint(
          size: const Size(16, 10),
          painter: _PinNeedlePainter(),
        ),
      ],
    );
  }
}

// 地圖釘下方三角形（白色邊框，黑色實心）
class _PinNeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 陰影
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final shadowPath = Path()
      ..moveTo(size.width / 2 - 1, 2)
      ..lineTo(size.width / 2, size.height + 1)
      ..lineTo(size.width / 2 + 1, 2)
      ..close();
    canvas.drawPath(shadowPath, shadowPaint);

    // 白色外框
    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(2, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width - 2, 0);
    canvas.drawPath(path, borderPaint);

    // 實心黑色針腳
    final fillPaint = Paint()..color = const Color(0xFFE0E0E0);
    final fillPath = Path()
      ..moveTo(3, 0)
      ..lineTo(size.width / 2, size.height - 1)
      ..lineTo(size.width - 3, 0)
      ..close();
    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

// ── 步數泡泡下方小三角 ──────────────────────────────────────
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
