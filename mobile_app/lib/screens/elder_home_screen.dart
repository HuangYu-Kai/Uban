import 'package:flutter/material.dart';
import 'elder_tabs/elder_home_tab.dart';
import 'elder_tabs/elder_chat_tab.dart';
import 'elder_tabs/elder_profile_tab.dart';
import '../globals.dart';
import 'elder_screen.dart';
import 'package:flutter_tts/flutter_tts.dart';
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
  final GlobalKey<ElderChatTabState> _chatTabKey = GlobalKey<ElderChatTabState>();

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

    pendingAcceptedCall.addListener(_onPendingCallChanged);

    // ★ 核心：監聽主動式心跳 (Heartbeat)
    Signaling().onHeartbeatMessage = (message) {
      if (mounted) {
        _handleProactiveMessage(message);
      }
    };
  }

  final FlutterTts _flutterTts = FlutterTts();

  Future<void> _handleProactiveMessage(String message) async {
    // 1. 播放語音 (TTS)
    await _flutterTts.setLanguage("zh-TW");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.speak(message);

    // 2. 如果目前不在聊天頁，顯示提示
    if (_selectedIndex != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('小優：$message', style: const TextStyle(fontSize: 18)),
          backgroundColor: const Color(0xFF59B294),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '回覆部',
            textColor: Colors.white,
            onPressed: () => setState(() => _selectedIndex = 1),
          ),
        ),
      );
    }
    
    // 3. 通知 ChatTab 更新
    _chatTabKey.currentState?.addAIMessage(message);
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
      
      final currentContext = context;
      Navigator.push(
        currentContext,
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
              ElderHomeTab(
                userId: widget.userId,
                userName: widget.userName,
              ),
              ElderChatTab(
                key: _chatTabKey,
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
