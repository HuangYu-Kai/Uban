import 'package:flutter/material.dart';
import 'elder_tabs/elder_home_tab.dart';
import 'zen_pond/zen_pond_screen.dart';
import 'elder_tabs/elder_profile_tab.dart';
import '../globals.dart';
import 'elder_screen.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:convert';
import '../services/signaling.dart';
import '../widgets/desktop_pet.dart';
import 'dart:async';

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
  int _selectedIndex = 1; // 0: Home/Calendar, 1: Chat, 2: Profile/Settings
  final GlobalKey<ZenPondScreenState> _zenPondKey = GlobalKey<ZenPondScreenState>();
  // ★ 新增：用於控制小豬
  final GlobalKey<DesktopPetState> _petKey = GlobalKey<DesktopPetState>();

  // ★ 新增：對話 Overlay 顯示狀態，用以動態隱藏導覽列防止重合
  bool _isZenPondOverlayVisible = false;

  // ★ 新增：投餵動畫列表
  
  // ★ 新增：遠征系統步數監控
  int _lastDiscoveredSteps = 0;

  @override
  void initState() {
    super.initState();
    isAppReady = true;

    // ★ 長輩端進入主畫面後，自動連入信號伺服器 (上線)
    Signaling().connect(widget.userId.toString(), 'elder',
        userId: widget.userId, deviceName: widget.userName);

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

    if (mounted) {
      // 2. 讓小豬頭上的氣泡顯示內容，並進入開心狀態 (取代原本的大對話框)
      if (_selectedIndex == 0) {
        _petKey.currentState?.say(displayText, state: PetState.happy);
      }
    }

    // 4. 通知 ZenPond 更新，觸發錦鯉游入動畫
    _zenPondKey.currentState?.addNotification(displayText);

    // 5. 正式的語音朗讀
    await _flutterTts.setPitch(1.0); // 恢復正常音調
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.speak(displayText);
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
      debugPrint(
          "📱 ElderHomeScreen: Incoming call detected! Navigating to ElderScreen...");
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
              ZenPondScreen(
                key: _zenPondKey,
                onOverlayStateChanged: (isVisible) {
                  setState(() {
                    _isZenPondOverlayVisible = isVisible;
                  });
                },
              ),
              ElderProfileTab(
                userId: widget.userId,
                userName: widget.userName,
              ),
            ],
          ),
          // 小豬桌寵 (僅在首頁顯示，擁有全螢幕的定位權)
          if (_selectedIndex == 0)
            DesktopPet(
              key: _petKey,
              userId: widget.userId,
              bottomBarHeight: 110,
              onStepsChanged: (steps) => checkExpeditionDiscovery(steps),
            ),
          // 自定義浮動導覽列 (長輩對話與落葉木牌開啟時，平滑滑落隱藏以防遮擋)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            left: 0,
            right: 0,
            bottom: (_selectedIndex == 1 && _isZenPondOverlayVisible) ? -100 : 0,
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

  // --- 遠征系統核心邏輯 ---

  // 遠征系統：檢查是否撿到東西
  void checkExpeditionDiscovery(int currentSteps) {
    // 每 500 步有機率撿到東西
    if (currentSteps - _lastDiscoveredSteps >= 500) {
      _lastDiscoveredSteps = currentSteps;
      final items = ["神秘種子", "閃亮石頭", "古老硬幣", "小紅花"];
      final foundItem = items[DateTime.now().second % items.length];
      
      Timer(const Duration(seconds: 3), () {
        if (mounted && _selectedIndex == 0) {
          _petKey.currentState?.say("嘎挖！我在路邊撿到了【$foundItem】！送給您！🎁", state: PetState.happy);
        }
      });
    }
  }
}
