import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 添加觸覺反饋
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'family_v2/ai_hub_screen.dart';
import 'family_v2/health_trends_screen.dart';
import 'family_v2/family_collaboration_screen.dart';
import '../services/elder_manager.dart';
import '../services/signaling.dart';
import '../services/api_service.dart';
import 'video_call_screen.dart';

class FamilyMainScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const FamilyMainScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<FamilyMainScreen> createState() => _FamilyMainScreenState();
}

class _FamilyMainScreenState extends State<FamilyMainScreen> {
  int _selectedIndex = 0;
  late final List<Widget> _views;
  final Signaling _signaling = Signaling();
  bool _isIncomingCallDialogOpen = false;
  String? _elderName;
  String? _elderRoomId;

  @override
  void initState() {
    super.initState();
    
    print('🔍 FamilyMainScreen initialized:');
    print('   userId: ${widget.userId}');
    print('   userName: ${widget.userName}');
    
    // 初始化 ElderManager with 真實 userId（不需要 await，在背景執行）
    _initializeElderManager();
    _loadElderAndConnect();
    
    _views = [
      AiHubScreen(
        currentUserId: widget.userId,
        currentUserName: widget.userName,
      ),
      HealthTrendsScreen(
        elderName: '長輩', // ElderManager 會在 AiHubScreen 載入真實資料
        elderId: null,
      ),
      FamilyCollaborationScreen(
        elderName: '長輩', // ElderManager 會在 AiHubScreen 載入真實資料
        elderId: null,
      ),
    ];
    
    print('🔍 Created AiHubScreen with:');
    print('   currentUserId: ${widget.userId}');
    print('   currentUserName: ${widget.userName}');
  }
  
  Future<void> _initializeElderManager() async {
    // 使用從登入系統傳入的真實 userId
    print('🔄 FamilyMainScreen: Starting ElderManager initialization');
    final success = await ElderManager().initialize(userId: widget.userId);
    print('🔄 FamilyMainScreen: ElderManager initialization ${success ? "succeeded" : "failed"}');
  }

  Future<void> _loadElderAndConnect() async {
    debugPrint('📡📡📡 [FamilyMainScreen] ===== 開始載入長輩並連線 =====');
    final prefs = await SharedPreferences.getInstance();
    _elderName = prefs.getString('selected_elder_name');
    final elderId = prefs.getInt('selected_elder_id'); // user_id，作為房間號
    
    debugPrint('📡 [FamilyMainScreen] SharedPreferences 讀取:');
    debugPrint('   - selected_elder_name: $_elderName');
    debugPrint('   - selected_elder_id (user_id): $elderId');
    
    // 如果沒有 elderId，從 API 獲取
    int? roomUserId = elderId;
    if (roomUserId == null) {
      debugPrint('📡 [FamilyMainScreen] 沒有已選長輩，從 API 獲取...');
      try {
        final elders = await ApiService.getPairedElders(widget.userId);
        debugPrint('📡 [FamilyMainScreen] API 返回 ${elders.length} 個長輩');
        
        if (elders.isNotEmpty) {
          final targetElder = elders.first;
          debugPrint('📡 [FamilyMainScreen] 使用第一個長輩: id=${targetElder['id']}, name=${targetElder['user_name']}');
          
          roomUserId = targetElder['id'] as int?;
          _elderName = targetElder['user_name'];
          
          // 儲存以便下次使用
          if (roomUserId != null) {
            await prefs.setInt('selected_elder_id', roomUserId);
            if (_elderName != null) {
              await prefs.setString('selected_elder_name', _elderName!);
            }
            debugPrint('📡 [FamilyMainScreen] ✅ 自動儲存: roomUserId=$roomUserId, name=$_elderName');
          }
        } else {
          debugPrint('⚠️ [FamilyMainScreen] API 返回空列表，沒有配對的長輩');
        }
      } catch (e) {
        debugPrint('⚠️ [FamilyMainScreen] 獲取長輩資料失敗: $e');
      }
    }
    
    // ★ 重要：使用 user_id 作為房間號（與長輩端一致）
    final roomId = roomUserId?.toString();
    _elderRoomId = roomId;
    
    if (roomId != null) {
      debugPrint('📡📡📡 [FamilyMainScreen] ===== 連線到房間: $roomId =====');
      debugPrint('📡 [FamilyMainScreen] elderName: $_elderName');
      debugPrint('📡 [FamilyMainScreen] deviceName: ${widget.userName}的App');
      _signaling.connect(roomId, 'family', deviceName: '${widget.userName}的App');
      _setupSignalingCallbacks();
      debugPrint('📡 [FamilyMainScreen] ✅ 回調已設置');
    } else {
      debugPrint('⚠️⚠️⚠️ [FamilyMainScreen] 無法連線：未選擇長輩或無法獲取房間號');
    }
  }

  void _setupSignalingCallbacks() {
    // 監聽來電（長輩打給家屬）
    _signaling.onCallRequest = (roomId, senderId, callId) {
      if (!mounted) return;
      debugPrint('📞 [FamilyMainScreen] 收到來電: room=$roomId, sender=$senderId, callId=$callId');
      _showIncomingCallDialog(roomId, senderId, callId);
    };

    // 監聯緊急來電
    _signaling.onEmergencyCall = (roomId, senderId, callId) {
      if (!mounted) return;
      debugPrint('🚨 [FamilyMainScreen] 緊急來電: room=$roomId');
      _showIncomingCallDialog(roomId, senderId, callId, isEmergency: true);
    };

    // 監聽取消呼叫
    _signaling.onCancelCall = (roomId, senderId, callId) {
      if (!mounted) return;
      debugPrint('🔕 [FamilyMainScreen] 來電取消: room=$roomId');
      if (_isIncomingCallDialogOpen && Navigator.canPop(context)) {
        Navigator.of(context).pop();
        _isIncomingCallDialogOpen = false;
      }
    };
  }

  void _showIncomingCallDialog(String roomId, String senderId, String? callId, {bool isEmergency = false}) {
    if (_isIncomingCallDialogOpen) return; // 防止重複彈窗
    _isIncomingCallDialogOpen = true;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isEmergency ? Colors.red.shade100 : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isEmergency ? Icons.warning : Icons.phone_callback,
                  color: isEmergency ? Colors.red : Colors.green,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Text(isEmergency ? '🚨 緊急來電' : '📞 長輩來電'),
            ],
          ),
          content: Text(
            '${_elderName ?? "長輩"} 正在呼叫您！',
            style: const TextStyle(fontSize: 18),
          ),
          backgroundColor: isEmergency ? Colors.red.shade50 : Colors.green.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            TextButton(
              onPressed: () {
                _signaling.sendCallBusy(roomId);
                Navigator.of(dialogContext).pop();
                _isIncomingCallDialogOpen = false;
              },
              child: const Text('拒接', style: TextStyle(color: Colors.red, fontSize: 16)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _isIncomingCallDialogOpen = false;
                // 先發送接聽信號
                _signaling.sendCallAccept(senderId, callId: callId);
                // 跳轉到視訊通話頁面
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => VideoCallScreen(
                      roomId: roomId,
                      targetSocketId: senderId,
                      isIncomingCall: true,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.videocam),
              label: const Text('接聽', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      _isIncomingCallDialogOpen = false;
    });
  }

  @override
  void dispose() {
    _signaling.onCallRequest = null;
    _signaling.onEmergencyCall = null;
    _signaling.onCancelCall = null;
    super.dispose();
  }

  void _onItemTapped(int index) {
    HapticFeedback.lightImpact(); // 添加觸覺反饋
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: _views),
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(0, Icons.auto_awesome_rounded, 'AI中樞'),
                    _buildNavItem(1, Icons.show_chart_rounded, '健康趨勢'),
                    _buildNavItem(2, Icons.people_rounded, '家庭協作'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    final color = isSelected
        ? const Color(0xFF2563EB) // Primary Blue
        : const Color(0xFF64748B); // Slate Gray

    return Expanded(
      child: GestureDetector(
        onTap: () => _onItemTapped(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: isSelected ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.notoSansTc(
                  color: color,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  height: 1.1,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
