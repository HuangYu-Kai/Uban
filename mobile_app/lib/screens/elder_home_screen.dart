import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'elder_tabs/elder_home_tab.dart';
import 'friends_screen.dart';
import 'elder_chat_screen.dart';
import 'elder_tabs/elder_profile_tab.dart';
import '../globals.dart';
import 'elder_screen.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:convert';
import '../services/signaling.dart';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

class ElderHomeScreen extends StatefulWidget {
  final int userId;
  final String userName;
  final String? roomId;

  const ElderHomeScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.roomId,
  });

  @override
  State<ElderHomeScreen> createState() => _ElderHomeScreenState();
}

class _ElderHomeScreenState extends State<ElderHomeScreen> {
  int _selectedIndex = 0; // 0:首頁 1:電話 2:聊天 3:我的

  bool _isNavigatingToCall = false;

  Future<void> _requestPermissions() async {
    try {
      await [
        Permission.systemAlertWindow,
        Permission.notification,
      ].request();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    isAppReady = true;
    _requestPermissions();

    // ★ 核心修復：強制使用長輩的專屬配對房間號 (elder_id)，且帶有 comm_elder_ 字首，確保與後端格式及權限匹配
    final String rawRoomId = widget.roomId ?? widget.userId.toString();
    final String roomToJoin = rawRoomId.startsWith('comm_elder_') || rawRoomId.startsWith('monitor_elder_')
        ? rawRoomId
        : 'comm_elder_$rawRoomId';
    _connectSocket(roomToJoin);

    pendingAcceptedCall.addListener(_onPendingCallChanged);
    
    // 檢查是否有在背景接聽的通話初始化前就傳入的待接聽電話
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _onPendingCallChanged();
    });

    // 監聽來自親人的呼叫與推播留言
    _restoreSignalingCallbacks();
  }

  void _restoreSignalingCallbacks() {
    debugPrint("🔄 [ElderHomeScreen] 重新綁定 Signaling Callbacks");
    // 監聽來自家屬的來電請求
    Signaling().onCallRequest = (roomId, senderId, callId, [senderName]) {
      if (!mounted) return;
      _showIncomingCallDialog(roomId, senderId, callId);
    };

    // 監聽家屬發送的主動關心留言 (Heartbeat)
    Signaling().onHeartbeatMessage = (message) {
      if (mounted) {
        _handleProactiveMessage(message);
      }
    };
  }

  bool _isIncomingCallDialogOpen = false;

  Future<void> _connectSocket(String roomToJoin) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint("Error getting FCM token: $e");
    }
    
    Signaling().connect(
      roomToJoin, 
      'elder',
      userId: widget.userId, 
      deviceName: widget.userName,
      fcmToken: fcmToken,
    );
  }

  void _showIncomingCallDialog(String roomId, String senderId, String? callId) {
    if (_isIncomingCallDialogOpen) return;
    _isIncomingCallDialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.phone_in_talk, color: Colors.green, size: 28),
              SizedBox(width: 12),
              Text('家屬來電'),
            ],
          ),
          content: const Text('您的家人正在呼叫您！', style: TextStyle(fontSize: 18)),
          backgroundColor: Colors.green.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            TextButton(
              onPressed: () {
                Signaling().sendCallBusy(senderId, callId: callId);
                Navigator.of(dialogContext).pop();
                _isIncomingCallDialogOpen = false;
              },
              child: const Text('拒接', style: TextStyle(color: Colors.red, fontSize: 16)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _isIncomingCallDialogOpen = false;
                
                // 接聽後跳轉到通話畫面
                Signaling().sendCallAccept(senderId, callId: callId);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ElderScreen(
                      roomId: widget.roomId ?? widget.userId.toString(),
                      deviceName: widget.userName,
                    ),
                  ),
                ).then((_) {
                  // ★ 從 ElderScreen 退出時重新綁定 callbacks
                  if (mounted) {
                    _restoreSignalingCallbacks();
                  }
                });
              },
              icon: const Icon(Icons.videocam),
              label: const Text('接聽', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    ).then((_) => _isIncomingCallDialogOpen = false);
  }

  final FlutterTts _flutterTts = FlutterTts();

  Future<void> _handleProactiveMessage(String message) async {
    String displayText = message;
    try {
      final data = jsonDecode(message);
      if (data is Map && data.containsKey('reply')) {
        displayText = data['reply'];
        // 檢查是否為禮物
        if (data['type'] == 'family_gift') {
          displayText = "嘎挖！大驚喜！🎁 子女給您送禮物來了：\n$displayText";
        }
      }
    } catch (e) {
      debugPrint("Home Heartbeat is plain text.");
    }

    // 1. 發出「豬叫」音效 (oink!) - 暫時用 TTS 模擬高頻短促音
    await _flutterTts.setLanguage("zh-TW");
    await _flutterTts.setPitch(2.0); // 極高音
    await _flutterTts.setSpeechRate(0.8);
    await _flutterTts.speak("喔！");

    // 5. 正式的語音朗讀
    await _flutterTts.setPitch(1.0); // 恢復正常音調
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.speak(displayText);
  }

  @override
  void dispose() {
    isAppReady = false;
    pendingAcceptedCall.removeListener(_onPendingCallChanged);
    Signaling().onHeartbeatMessage = null;
    Signaling().onCallRequest = null;
    super.dispose();
  }

  void _onPendingCallChanged() {
    final call = pendingAcceptedCall.value;
    if (call != null && !_isNavigatingToCall) {
      _isNavigatingToCall = true; // ★ Issue 3：防止重複導航
      debugPrint(
          "📱 ElderHomeScreen: Incoming call detected! Navigating to ElderScreen...");
      // 一定要清空，否則之後返回主頁會再次觸發
      pendingAcceptedCall.value = null;

      if (!mounted) {
        _isNavigatingToCall = false;
        return;
      }

      final currentContext = context;
      Navigator.push(
        currentContext,
        MaterialPageRoute(
          builder: (context) => ElderScreen(
            roomId: call['roomId']!,
            deviceName: widget.userName,
            initialCallData: call, // ★ 傳遞通話資料
          ),
        ),
      ).then((_) {
        _isNavigatingToCall = false; // ★ 導航結束，允許下次
        // ★ 當從 ElderScreen 退出時，重新綁定首頁的 callbacks
        if (mounted) {
          _restoreSignalingCallbacks();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Stack(
        children: [
          // 頁面內容切換
          IndexedStack(
            index: _selectedIndex,
            children: [
              // 0 首頁
              ElderHomeTab(
                userId: widget.userId,
                userName: widget.userName,
                roomId: widget.roomId,
              ),
              // 1 電話（好友列表）
              FriendsScreen(
                userId: widget.userId,
                userName: widget.userName,
                roomId: widget.roomId,
              ),
              // 2 聊天（小雲 AI 聊天）
              ElderChatScreen(
                userId: widget.userId,
                userName: widget.userName,
              ),
              // 3 我的
              ElderProfileTab(
                userId: widget.userId,
                userName: widget.userName,
              ),
            ],
          ),
          // 浮動導覽列（永遠顯示）
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildFloatingNavBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingNavBar() {
    return Container(
      height: 104,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, Icons.home_rounded, '首頁'),
          _buildNavItem(1, Icons.phone_rounded, '電話'),
          _buildNavItem(2, Icons.chat_bubble_rounded, '聊天'),
          _buildNavItem(3, Icons.person_rounded, '我的'),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    final Color activeColor = const Color(0xFF59B294);
    final Color inactiveColor = const Color(0xFF94A3B8);
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 34,
              color: isSelected ? activeColor : inactiveColor,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.notoSansTc(
                fontSize: 18,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                color: isSelected ? activeColor : inactiveColor,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
