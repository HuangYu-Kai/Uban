import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../identification_screen.dart';
import '../leaderboard_screen.dart';

class ElderProfileTab extends StatefulWidget {
  final int userId;
  final String userName;

  const ElderProfileTab({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<ElderProfileTab> createState() => _ElderProfileTabState();
}

class _ElderProfileTabState extends State<ElderProfileTab>
    with TickerProviderStateMixin {
  // ── 數據 ───────────────────────────────────────────────
  final int dailyStepGoal = 8000;
  int currentSteps = 0; // Will be calculated from distance or fetched


  // ── 步數動畫 ──────────────────────────────────────────────
  late AnimationController _ctrl;

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


    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _ctrl.forward();
    });

    _autoStartTracking();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _positionStream?.cancel();
    super.dispose();
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
      await prefs.remove('route_points');
      await prefs.setDouble('total_distance', 0.0);
      await prefs.setString('last_track_date', today);
      return;
    }

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
    final mockPoints = [
      const LatLng(25.0346, 121.5218), // 中正紀念堂
      const LatLng(25.0355, 121.5218),
      const LatLng(25.0368, 121.5219),
      const LatLng(25.0375, 121.5222),
      const LatLng(25.0390, 121.5225),
      const LatLng(25.0405, 121.5230),
      const LatLng(25.0423, 121.5249), // 抵達北商
    ];
    setState(() {
      _routePoints.clear();
      _routePoints.addAll(mockPoints);
      _currentPosition = mockPoints.last;
      _totalDistance = 1.25; 
    });
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

  // ── 開始 GPS 追蹤 ───────────────────────────
  Future<void> _startTracking() async {
    if (_isTracking) return;
    final granted = await _requestPermission();
    if (!granted) return;

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
        if (distM > 2.0) {
          _totalDistance += distM / 1000.0;
          setState(() {
            _routePoints.add(newPoint);
            _persistRoute();
          });
        }
      } else {
        setState(() => _routePoints.add(newPoint));
      }
      setState(() {
        _currentPosition = newPoint;
      });
      if (_routePoints.length > 1) {
        final bounds = LatLngBounds.fromPoints(_routePoints);
        try {
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(40.0),
            ),
          );
        } catch (_) {}
      } else {
        if (_mapController.camera.zoom != 0) {
          _mapController.move(newPoint, 18.0);
        }
      }
    });

    setState(() {
      _isTracking = true;
    });
  }

  // ── 🆕 今日目標圓環 (取代舊的週報表) ──────────────────────
  Widget _buildDailyGoalRing() {
    final double progress = (currentSteps / dailyStepGoal).clamp(0.0, 1.0);
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF59B294).withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 200,
                height: 200,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 16,
                  backgroundColor: const Color(0xFFF1F5F9),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF59B294)),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '今日步數',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 22, // Increased from 18
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    NumberFormat('#,###').format(currentSteps),
                    style: GoogleFonts.inter(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    '目標 $dailyStepGoal 步',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 20, // Increased from 16
                      color: const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSimpleStat('步行距離', '${_totalDistance.toStringAsFixed(2)} 公里'),
              _buildSimpleStat('消耗熱量', '${(_totalDistance * 60).toInt()} 千卡'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleStat(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.notoSansTc(
            fontSize: 20, // Increased from 16
            color: const Color(0xFF94A3B8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.notoSansTc(
            fontSize: 24, // Increased from 20
            fontWeight: FontWeight.bold,
            color: const Color(0xFF334155),
          ),
        ),
      ],
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
                flags: InteractiveFlag.none,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                retinaMode: true,
                userAgentPackageName: 'com.uban.app',
                maxZoom: 20,
              ),
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
                          color: const Color(0xFF59B294),
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
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition!,
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      child: const _AvatarPin(),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            top: 16,
            right: 16,
            child: FloatingActionButton.small(
              onPressed: () {
                if (_currentPosition != null) {
                  _mapController.move(_currentPosition!, 18.0);
                }
              },
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF59B294),
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.my_location_rounded, size: 32),
            ),
          ),
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


  void _handleLogout() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '切換身分',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        content: Text('確定要登出並回到身分辨識頁面嗎？', style: GoogleFonts.notoSansTc()),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              '取消',
              style: GoogleFonts.notoSansTc(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('caregiver_id');
              await prefs.remove('caregiver_name');

              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const IdentificationScreen()),
                (route) => false,
              );
            },
            child: Text(
              '登出',
              style: GoogleFonts.notoSansTc(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    currentSteps = (_totalDistance * 1450).toInt();
    final hour = DateTime.now().hour;
    String greetingTitle = '早安';
    if (hour >= 12 && hour < 18) greetingTitle = '午安';
    if (hour >= 18 || hour < 5) greetingTitle = '晚安';

    return Container(
      color: const Color(0xFFFDFCF9),
      width: double.infinity,
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 溫馨標頭 (Header) ───────────────────────────
              Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF59B294).withValues(alpha: 0.1),
                      border: Border.all(color: const Color(0xFF59B294), width: 2),
                    ),
                    child: const Icon(Icons.person_rounded, size: 40, color: Color(0xFF59B294)),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$greetingTitle，${widget.userName}',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          '今天也要開心地活動身體喔！',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 18,
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // ── 今日成就圓環 ───────────────────────────
              _buildDailyGoalRing(),
              const SizedBox(height: 24),

              // ── 冒險護照 (遊戲入口) ───────────────────────────
              _buildGameEntryCard(),
              const SizedBox(height: 24),

              // ── 移動軌跡地圖 ───────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 12),
                    child: Text(
                      '今日步行軌跡',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF334155),
                      ),
                    ),
                  ),
                  _buildRealMap(),
                ],
              ),
              const SizedBox(height: 40),

              // ── 系統設定選單 ───────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildSettingsTile(
                      icon: Icons.logout_rounded,
                      title: '切換身分 / 登出',
                      color: Colors.redAccent,
                      onTap: _handleLogout,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 20),
            Text(
              title,
              style: GoogleFonts.notoSansTc(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const Spacer(),
            Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey.shade300, size: 18),
          ],
        ),
      ),
    );
  }
  Widget _buildGameEntryCard() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                LeaderboardScreen(elderId: widget.userId.toString()),
          ),
        );
      },
      borderRadius: BorderRadius.circular(32),
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF1F2), Color(0xFFFFE4E6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.pink.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              bottom: -20,
              child: Opacity(
                opacity: 0.2,
                child: Image.asset(
                  'assets/images/pig_2d_idle_v4.png',
                  width: 150,
                  errorBuilder: (context, _, __) => const Icon(Icons.pets, size: 100),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.stars_rounded,
                      color: Colors.pinkAccent,
                      size: 40,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '我的冒險護照',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFE11D48),
                          ),
                        ),
                        Text(
                          '點擊進入小豬遊戲',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 22, // Increased from 18
                            color: const Color(0xFFF43F5E),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 大頭貼位置點（目前位置） ────────────────────────────────
class _AvatarPin extends StatelessWidget {
  const _AvatarPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFE0E0E0),
        border: Border.all(color: Colors.white, width: 3.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const ClipOval(
        child: Icon(Icons.person, size: 28, color: Color(0xFF757575)),
      ),
    );
  }
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
