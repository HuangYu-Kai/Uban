import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'elder_tabs/elder_home_tab.dart';
import 'elder_tabs/elder_chat_tab.dart';
import 'elder_tabs/elder_profile_tab.dart';
import '../globals.dart';
import 'elder_screen.dart';
import '../services/signaling.dart'; // ★ 新增

class ElderHomeScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const ElderHomeScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<ElderHomeScreen> createState() => _ElderHomeScreenState();
}

class _ElderHomeScreenState extends State<ElderHomeScreen> {
  int _selectedIndex = 0; // 0: Home/Calendar, 1: Chat, 2: Profile/Settings

  @override
  void initState() {
    super.initState();
    isAppReady = true;

    // ★ 長輩端進入主畫面後，自動連入信號伺服器 (上線)
    Signaling().connect(
      widget.userId.toString(), 
      'elder', 
      userId: widget.userId, 
      deviceName: widget.userName
    );

    // ★ 處理來電監聽 (前景)
    Signaling().onIncomingCall = (senderId, type) async {
      return await _showCallDialog(senderId, type);
    };

    Signaling().onCallRequest = (roomId, senderId, callId) {
      _showCallDialog(senderId, 'normal', callId: callId);
    };

    pendingAcceptedCall.addListener(_onPendingCallChanged);
  }

  Future<bool> _showCallDialog(String senderId, String type, {String? callId}) async {
    if (!mounted) return false;
    
    bool isEmergency = (type == 'emergency');
    
    // 如果是緊急通話，可以直接導航或播放聲音
    if (isEmergency) {
      _navigateToElderScreen(isCCTV: false); // 或根據需求自動接聽
      return true;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('家人來電'),
        content: const Text('您的家人正在呼叫，是否接聽？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('拒絕', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('接聽'),
          ),
        ],
      ),
    );

    if (result == true) {
      // ★ 重要：在回傳 true (接聽) 之前，必須先打開媒體串流，否則傳出去的 Answer 會沒有畫面
      final tempRenderer = RTCVideoRenderer();
      await tempRenderer.initialize();
      await Signaling().openUserMedia(tempRenderer);
      
      _navigateToElderScreen(isCCTV: false);
      
      // 延遲清理暫時的 renderer (實際畫面會由 ElderScreen 的渲染器接手)
      Future.delayed(const Duration(seconds: 1), () => tempRenderer.dispose());
      
      return true;
    }
    return false;
  }

  void _navigateToElderScreen({bool isCCTV = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ElderScreen(
          roomId: widget.userId.toString(),
          deviceName: widget.userName,
          isCCTVMode: isCCTV,
        ),
      ),
    );
  }

  @override
  void dispose() {
    isAppReady = false;
    pendingAcceptedCall.removeListener(_onPendingCallChanged);
    super.dispose();
  }

  void _onPendingCallChanged() {
    final call = pendingAcceptedCall.value;
    if (call != null) {
      debugPrint("📱 ElderHomeScreen: Incoming call detected! Navigating to ElderScreen...");
      // 一定要清空，否則之後返回主頁會再次觸發
      pendingAcceptedCall.value = null;

      if (!mounted) return;
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ElderScreen(
            roomId: call['roomId']!,
            deviceName: widget.userName,
            // isIncoming: true, // 如果有的話
          ),
        ),
      );
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
              const ElderHomeTab(),
              ElderChatTab(
                userId: widget.userId,
                onBackToHome: () => setState(() => _selectedIndex = 0),
              ),
              ElderProfileTab(
                userId: widget.userId,
                userName: widget.userName,
              ),
            ],
          ),
          // 自定義浮動導覽列
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
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
          _buildNavItem(0, Icons.home_rounded),
          _buildNavItem(1, Icons.chat_bubble_rounded),
          _buildNavItem(2, Icons.person_rounded),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, isSelected ? -15 : 0, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF59B294) : Colors.transparent,
          shape: BoxShape.circle,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF59B294).withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ]
              : [],
        ),
        child: Icon(
          icon,
          size: 32,
          color: isSelected ? Colors.white : Colors.grey[400],
        ),
      ),
    );
  }
}
