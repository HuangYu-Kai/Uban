import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 添加觸覺反饋支持
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import 'redesigned_ai_chat_screen.dart';
import 'family_call_history_screen.dart'; // 新增
import 'elder_selection_screen.dart';
import 'elder_profile_edit_screen.dart';
import '../services/signaling.dart'; // 新增
import 'video_call_screen.dart'; // 新增

class FamilyDashboardView extends StatefulWidget {
final int userId;
final String userName;

const FamilyDashboardView({
super.key,
required this.userId,
required this.userName,
});

@override
State<FamilyDashboardView> createState() => _FamilyDashboardViewState();
}

class _FamilyDashboardViewState extends State<FamilyDashboardView> {
  String? _elderName; // 改為可空，預設 null
  int? _elderId;
  String? _elderRoomId; // ★ 新增：房間號（= elder_id，如 "1142"）
  String? _elderSocketId;
  final Signaling _signaling = Signaling();
  


  @override
  void initState() {
    super.initState();
    _loadSelectedElder();
    _initSignaling();
  }



  void _initSignaling() {
    // 監聽長輩裝置更新，找出在線的 Socket ID
    _signaling.onElderDevicesUpdate = (devices) {
      if (devices.isNotEmpty && mounted) {
        setState(() {
          // 優先找在線的 (isOnline: true)
          final online = devices.where((d) => d['isOnline'] == true);
          if (online.isNotEmpty) {
            _elderSocketId = online.first['id'];
            debugPrint('Found online elder device: $_elderSocketId');
          } else {
            _elderSocketId = devices.first['id']; // 至少抓一個
          }
        });
      }
    };

    // ★ 監聽來電（長輩打給家屬）
    _signaling.onCallRequest = (roomId, senderId, callId) {
      if (!mounted) return;
      debugPrint('📞 [FamilyDashboardView] 收到來電: room=$roomId, sender=$senderId, callId=$callId');
      _showIncomingCallDialog(roomId, senderId, callId);
    };

    // 監聽取消呼叫
    _signaling.onCancelCall = (roomId, senderId, callId) {
      if (!mounted) return;
      debugPrint('🔕 [FamilyDashboardView] 來電取消: room=$roomId');
      // 如果有來電對話框正在顯示，關閉它
      if (_isIncomingCallDialogOpen && Navigator.canPop(context)) {
        Navigator.of(context).pop();
        _isIncomingCallDialogOpen = false;
      }
    };
  }

  bool _isIncomingCallDialogOpen = false;

  void _showIncomingCallDialog(String roomId, String senderId, String? callId) {
    _isIncomingCallDialogOpen = true;
    
    // ★ 新增：通知時手機振動（長振動 + 中振動）
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 200), () {
      HapticFeedback.mediumImpact();
    });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 16,
          backgroundColor: Colors.white,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.green.shade50, Colors.blue.shade50],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ★ 頂部裝飾條
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    gradient: LinearGradient(
                      colors: [Colors.green.shade400, Colors.green.shade600],
                    ),
                  ),
                ),
                
                SizedBox(height: 32),
                
                // ★ 大頭貼
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.shade400.withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    backgroundColor: Colors.green.shade400,
                    child: Text(
                      (_elderName ?? "長輩").characters.first.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                
                SizedBox(height: 20),
                
                // ★ 來電者名稱
                Text(
                  _elderName ?? "長輩",
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                
                SizedBox(height: 12),
                
                // ★ 來電狀態
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withValues(alpha: 0.6),
                            blurRadius: 4,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '正在來電...',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: 36),
                
                // ★ 按鈕區域
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      // 拒接按鈕
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.shade200,
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () {
                              _signaling.sendCallBusy(roomId);
                              Navigator.of(dialogContext).pop();
                              _isIncomingCallDialogOpen = false;
                            },
                            icon: const Icon(Icons.call_end, size: 20),
                            label: const Text('拒接'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade400,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 12),
                      
                      // 接聽按鈕
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.shade300,
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              _isIncomingCallDialogOpen = false;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => VideoCallScreen(
                                    roomId: roomId,
                                    isIncomingCall: true,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.videocam, size: 20),
                            label: const Text('接聽'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade500,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

Future<void> _loadSelectedElder() async {
  final prefs = await SharedPreferences.getInstance();
  setState(() {
    _elderName = prefs.getString('selected_elder_name'); // 移除預設值
    _elderId = prefs.getInt('selected_elder_id');
    _elderRoomId = prefs.getString('selected_elder_room_id'); // ★ 讀取房間號
  });

  // 讀到房間號後立刻加入 Signaling 房間監聽
  // ★ 重要：使用 elder_id（如 "1142"）作為房間號，與長輩端一致
  final roomId = _elderRoomId ?? _elderId?.toString();
  if (roomId != null) {
    debugPrint('📡 [FamilyDashboardView] 加入房間: $roomId (elderName: $_elderName)');
    _signaling.connect(roomId, 'family', deviceName: '${widget.userName}的儀表板');
  }
}

  @override
  void dispose() {
    // _signaling.dispose(); // Singleton 不建議隨便完全 dispose，但可以清掉回撥
    _signaling.onElderDevicesUpdate = null;
    _signaling.onCallRequest = null;
    _signaling.onCancelCall = null;
    super.dispose();
  }

@override
Widget build(BuildContext context) {
  // 如果沒有選擇長輩，顯示引導頁面
  if (_elderName == null || _elderId == null) {
    return _buildNoElderSelectedView(context);
  }

  return Scaffold(
    backgroundColor: const Color(0xFFF8FAFC),
    body: RefreshIndicator(
      onRefresh: () async => await _loadSelectedElder(),
      color: const Color(0xFF2563EB),
      backgroundColor: Colors.white,
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 簡潔頭部
              _buildHeader(),
              const SizedBox(height: 24),
              
              // 2. 快速操作卡片（重新設計）
              _buildQuickActionsCard(context),
              const SizedBox(height: 20),
              
              // 3. AI 每日總結
              _buildStatusReport(context),
              const SizedBox(height: 20),
              
              // 4. 健康數據概覽（重新設計）
              _buildHealthOverview(),
              const SizedBox(height: 20),
              
              // 5. 活動趨勢
              _buildActivityInsight(context),
              const SizedBox(height: 140),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.userName} 您好',
              style: GoogleFonts.notoSansTc(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.2, end: 0),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '正在關照：',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _elderName ?? '未知',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    color: const Color(0xFF2563EB),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                // 在線狀態指示器（新增）
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _elderSocketId != null 
                        ? const Color(0xFF10B981).withValues(alpha: 0.1)
                        : const Color(0xFF94A3B8).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _elderSocketId != null 
                              ? const Color(0xFF10B981)
                              : const Color(0xFF94A3B8),
                          shape: BoxShape.circle,
                        ),
                      ).animate(onPlay: (controller) => controller.repeat())
                        .fade(duration: 1500.ms, begin: 1.0, end: 0.3)
                        .then()
                        .fade(duration: 1500.ms, begin: 0.3, end: 1.0),
                      const SizedBox(width: 6),
                      Text(
                        _elderSocketId != null ? '在線' : '離線',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 11,
                          color: _elderSocketId != null 
                              ? const Color(0xFF10B981)
                              : const Color(0xFF94A3B8),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ).animate().fadeIn(delay: 200.ms),
          ],
        ),
        // 右側操作列
        Row(
          children: [
            // 編輯資料按鈕
            GestureDetector(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (c) => ElderProfileEditScreen(
                      // 此處暫時帶入靜態版模擬數據，後續可從 API 載入真實長輩資料
                      elderData: {
                        'name': _elderName,
                        'age': 75,
                        'location': '台北市士林區',
                        'phone': '0912-345-678',
                      },
                    ),
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: Color(0xFF475569),
                  size: 22,
                ),
              ),
            ),
            // 切換長輩按鈕
            GestureDetector(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (c) => ElderSelectionScreen(
                      userId: widget.userId,
                      userName: widget.userName,
                    ),
                  ),
                );
                _loadSelectedElder(); // 返回後重新整理
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFDBEAFE)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.sync_rounded,
                      color: Color(0xFF2563EB),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '切換',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 15,
                        color: const Color(0xFF2563EB),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

/// 🎯 快速問候消息對話框
  void _showQuickMessageDialog(BuildContext context) {
    HapticFeedback.lightImpact();
    
    final messages = [
      {'text': '🌞 早安！今天過得好嗎？', 'icon': '🌞'},
      {'text': '💝 想你了，有空聊聊嗎？', 'icon': '💝'},
      {'text': '🍚 記得吃飯哦！', 'icon': '🍚'},
      {'text': '😊 今天心情如何？', 'icon': '😊'},
      {'text': '🌙 晚安，好好休息！', 'icon': '🌙'},
    ];
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.favorite, color: Color(0xFFEF4444), size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              '快速問候',
              style: GoogleFonts.notoSansTc(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: messages.map((msg) => 
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已發送：${msg['text']}'),
                        backgroundColor: const Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                    // TODO: 實際發送消息到長輩端
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      msg['text']!,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '取消',
              style: GoogleFonts.notoSansTc(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusReport(BuildContext context) {
return GestureDetector(
onTap: () => Navigator.push(
context,
MaterialPageRoute(builder: (c) => const RedesignedAiChatScreen()),
),
child: Container(
padding: const EdgeInsets.all(24),
decoration: BoxDecoration(
color: Colors.white,
borderRadius: BorderRadius.circular(24),
border: Border.all(color: const Color(0xFFF1F5F9)),
boxShadow: [
BoxShadow(
color: Colors.black.withValues(alpha: 0.03),
blurRadius: 20,
offset: const Offset(0, 10),
),
],
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
Container(
padding: const EdgeInsets.all(10),
decoration: BoxDecoration(
color: const Color(0xFFEFF6FF), // Blue 50
borderRadius: BorderRadius.circular(12),
),
child: const Icon(
Icons.auto_awesome_rounded,
color: Color(0xFF2563EB),
size: 20,
),
),
const SizedBox(width: 16),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
'AI 每日總結',
style: GoogleFonts.notoSansTc(
fontSize: 16,
fontWeight: FontWeight.w800,
color: const Color(0xFF0F172A),
),
),
Text(
'今天 10:30 AM 更新',
style: GoogleFonts.inter(
fontSize: 12,
color: const Color(0xFF94A3B8),
fontWeight: FontWeight.w500,
),
),
],
),
),
const Icon(
Icons.chevron_right_rounded,
color: Color(0xFF94A3B8),
),
],
),
const SizedBox(height: 20),
Text(
'媽媽今天在練習書法時展現了極佳的專注力，提到以前在小學當老師的故事。體感活動達標。',
style: GoogleFonts.notoSansTc(
fontSize: 15,
color: const Color(0xFF475569),
height: 1.6,
fontWeight: FontWeight.w500,
),
),
const SizedBox(height: 20),
Row(
children: [
_buildStatusChip('專注', const Color(0xFF10B981)),
const SizedBox(width: 8),
_buildStatusChip('心情愉快', const Color(0xFF2563EB)),
const Spacer(),
Text(
'立即提問',
style: GoogleFonts.notoSansTc(
fontSize: 13,
fontWeight: FontWeight.w700,
color: const Color(0xFF2563EB),
),
),
],
),
],
),
),
);
}

Widget _buildActivityInsight(BuildContext context) {
return Container(
padding: const EdgeInsets.all(24),
decoration: BoxDecoration(
color: Colors.white,
borderRadius: BorderRadius.circular(24),
border: Border.all(color: const Color(0xFFE2E8F0)),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
'活動趨勢分析',
style: GoogleFonts.notoSansTc(
fontSize: 16,
fontWeight: FontWeight.w800,
color: const Color(0xFF0F172A),
),
),
const SizedBox(height: 24),
SizedBox(
height: 130, // 增加高度以容納 X 軸標籤
child: BarChart(
BarChartData(
alignment: BarChartAlignment.spaceEvenly,
maxY: 10,
barTouchData: BarTouchData(enabled: false),
titlesData: FlTitlesData(
show: true,
bottomTitles: AxisTitles(
sideTitles: SideTitles(
showTitles: true,
getTitlesWidget: (value, meta) {
const days = ['一', '二', '三', '四', '五', '六', '日'];
return Padding(
padding: const EdgeInsets.only(top: 8.0),
child: Text(
days[value.toInt() % 7],
style: GoogleFonts.notoSansTc(
color: const Color(0xFF94A3B8),
fontSize: 12,
fontWeight: FontWeight.w600,
),
),
);
},
),
),
leftTitles: const AxisTitles(
sideTitles: SideTitles(showTitles: false),
),
topTitles: const AxisTitles(
sideTitles: SideTitles(showTitles: false),
),
rightTitles: const AxisTitles(
sideTitles: SideTitles(showTitles: false),
),
),
gridData: const FlGridData(show: false),
borderData: FlBorderData(show: false),
barGroups: [
_makeBar(0, 5, const Color(0xFFCBD5E1)),
_makeBar(1, 8, const Color(0xFFCBD5E1)),
_makeBar(2, 4, const Color(0xFFCBD5E1)),
_makeBar(3, 9, const Color(0xFF2563EB)), // Today
_makeBar(4, 3, const Color(0xFFCBD5E1)),
_makeBar(5, 7, const Color(0xFFCBD5E1)),
_makeBar(6, 6, const Color(0xFFCBD5E1)),
],
),
),
),
],
),
);
}

BarChartGroupData _makeBar(int x, double y, Color color) {
return BarChartGroupData(
x: x,
barRods: [
BarChartRodData(
toY: y,
color: color,
width: 16,
borderRadius: BorderRadius.circular(4),
backDrawRodData: BackgroundBarChartRodData(
show: true,
toY: 10,
color: const Color(0xFFF1F5F9),
),
),
],
);
}

Widget _buildStatusChip(String label, Color color) {
return Container(
padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
decoration: BoxDecoration(
color: color.withValues(alpha: 0.1),
borderRadius: BorderRadius.circular(8),
),
child: Text(
label,
style: GoogleFonts.notoSansTc(
fontSize: 12,
fontWeight: FontWeight.w700,
color: color,
),
),
);
}



  /// 沒有選擇長輩時的引導頁面
  Widget _buildNoElderSelectedView(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 圖標
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_add_rounded,
                    size: 60,
                    color: Color(0xFF2563EB),
                  ),
                ).animate()
                  .scale(duration: 600.ms, curve: Curves.easeOut),
                
                const SizedBox(height: 32),
                
                // 標題
                Text(
                  '尚未選擇長輩',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ).animate().fadeIn(delay: 200.ms),
                
                const SizedBox(height: 12),
                
                // 描述
                Text(
                  '請先選擇或配對一位長輩\n開始您的關懷之旅',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    color: const Color(0xFF64748B),
                    height: 1.6,
                  ),
                ).animate().fadeIn(delay: 400.ms),
                
                const SizedBox(height: 48),
                
                // 選擇長輩按鈕
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      HapticFeedback.mediumImpact();
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => ElderSelectionScreen(
                            userId: widget.userId,
                            userName: widget.userName,
                          ),
                        ),
                      );
                      _loadSelectedElder();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.person_search_rounded, size: 24),
                        const SizedBox(width: 12),
                        Text(
                          '選擇長輩',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.3, end: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 重新設計的快速操作卡片
  Widget _buildQuickActionsCard(BuildContext context) {
    final isOnline = _elderSocketId != null;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isOnline 
              ? [const Color(0xFF2563EB), const Color(0xFF3B82F6)]
              : [const Color(0xFF64748B), const Color(0xFF94A3B8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (isOnline ? const Color(0xFF2563EB) : const Color(0xFF64748B))
                .withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // 主要呼叫按鈕
          GestureDetector(
            onTap: () {
              HapticFeedback.heavyImpact();
              if (_elderId == null) return;
              
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (c) => VideoCallScreen(
                    roomId: _elderId.toString(),
                    targetSocketId: _elderSocketId,
                    autoStart: true,
                  ),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.videocam_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isOnline ? '立即視訊通話' : '嘗試呼叫',
                    style: GoogleFonts.notoSansTc(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isOnline ? '$_elderName 在線中' : '$_elderName 目前離線',
                    style: GoogleFonts.notoSansTc(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 次要操作按鈕
          Row(
            children: [
              Expanded(
                child: _buildQuickActionButton(
                  icon: Icons.favorite_rounded,
                  label: '快速問候',
                  onTap: () => _showQuickMessageDialog(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionButton(
                  icon: Icons.history_rounded,
                  label: '通話紀錄',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (_elderId == null) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) => FamilyCallHistoryScreen(
                          roomId: _elderId.toString(),
                          elderName: _elderName!,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate()
      .fadeIn(duration: 500.ms)
      .scale(begin: const Offset(0.95, 0.95), curve: Curves.easeOut);
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.notoSansTc(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 重新設計的健康數據概覽
  Widget _buildHealthOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '健康數據',
          style: GoogleFonts.notoSansTc(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildHealthMetric(
                icon: Icons.favorite_rounded,
                label: '心率',
                value: '72',
                unit: 'BPM',
                color: const Color(0xFFEF4444),
                status: '正常',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildHealthMetric(
                icon: Icons.directions_walk_rounded,
                label: '步數',
                value: '4250',
                unit: '步',
                color: const Color(0xFF10B981),
                status: '良好',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildHealthMetric(
                icon: Icons.local_fire_department_rounded,
                label: '卡路里',
                value: '320',
                unit: 'kcal',
                color: const Color(0xFFF59E0B),
                status: '正常',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildHealthMetric(
                icon: Icons.nightlight_rounded,
                label: '睡眠',
                value: '82',
                unit: '%',
                color: const Color(0xFF8B5CF6),
                status: '優良',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHealthMetric({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
    required String status,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.notoSansTc(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  unit,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12,
                    color: const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}


