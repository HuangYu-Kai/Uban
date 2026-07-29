import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 添加觸覺反饋
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter_animate/flutter_animate.dart';
import 'family/family_home_tab.dart';
import 'family/family_interaction_tab.dart';
import 'family/family_data_tab.dart';
import 'family/alert_center_screen.dart';
import 'family/subscription_test_screen.dart';
import '../models/elder.dart';
import '../services/elder_manager.dart';
import '../services/signaling.dart';
import 'video_call_screen.dart';
import 'caregiver_pairing_screen.dart';
import 'package:flutter_application_1/utils/app_logger.dart';
import '../globals.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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

class _FamilyMainScreenState extends State<FamilyMainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final Signaling _signaling = Signaling();
  bool _isIncomingCallDialogOpen = false;
  
  Elder? _currentElder;
  List<Elder> _elders = [];
  bool _isElderOnline = false;
  Timer? _deviceRefreshTimer;
  Timer? _onlineStateDebounceTimer;
  bool? _pendingOnlineState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    pendingAcceptedCall.addListener(_onPendingCallChanged);
    
    appLogger.d('🔍 FamilyMainScreen initialized:');
    appLogger.d('   userId: ${widget.userId}');
    appLogger.d('   userName: ${widget.userName}');
    
    _initializeElderManagerAndConnect();
  }
  
  Future<void> _initializeElderManagerAndConnect() async {
    appLogger.d('🔄 FamilyMainScreen: Starting ElderManager initialization');
    await ElderManager().initialize(userId: widget.userId);
    
    if (mounted) {
      setState(() {
        _elders = ElderManager().pairedElders;
        _currentElder = ElderManager().currentElder;
      });
      _setupSignalingCallbacks();
      await _loadElderAndConnect();
      _startDeviceRefreshTimer();
      
      // 在初始化連線後，檢查是否有從背景進來的待處理來電
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _checkPendingAcceptedCall();
      });
    }
  }

  void _startDeviceRefreshTimer() {
    _deviceRefreshTimer?.cancel();
    // 調整為 2.5 秒取樣，避免裝置快速上下線時誤判。
    _deviceRefreshTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      final elder = _currentElder;
      if (elder == null || _signaling.socket?.connected != true) return;
      final elderIdStr = elder.elderId ?? elder.id.toString();
      _signaling.sendGetElderDevices('comm_elder_$elderIdStr');
      debugPrint('🔄 [Device Refresh] 輪詢長輩設備狀態 (elder_id=$elderIdStr)');
    });
  }

  Future<void> _loadElderAndConnect() async {
    debugPrint('📡📡📡 [FamilyMainScreen] ===== 開始載入長輩並連線 =====');

    if (_currentElder == null) {
      debugPrint('⚠️ [FamilyMainScreen] 沒有已選長輩，嘗試重新整理...');
      return;
    }

    // ★ 修復：使用正確的房間格式 comm_elder_{elder_id}
    //    elderId 是 elder_profile.elder_id（如 '0343'），而非數字 id
    final elderIdStr = _currentElder!.elderId ?? _currentElder!.id.toString();
    final roomId = 'comm_elder_$elderIdStr';

    debugPrint('📡📡📡 [FamilyMainScreen] ===== 連線到房間: $roomId =====');

    final String? fcmToken = await FirebaseMessaging.instance.getToken();

    _signaling.connect(
      roomId,
      'family',
      deviceName: '${widget.userName}的App',
      userId: widget.userId,
      fcmToken: fcmToken,
    );

    // 請求取得長輩設備在線狀態
    _signaling.sendGetElderDevices(roomId);
  }

  void _setupSignalingCallbacks() {
    // 監聽來電（長輩打給家屬）
    _signaling.onCallRequest = (roomId, senderId, callId, [senderName]) {
      if (!mounted) return;
      debugPrint('📞 [FamilyMainScreen] 收到來電: room=$roomId, sender=$senderId, callId=$callId, senderName=$senderName');
      _showIncomingCallDialog(roomId, senderId, callId, callerName: senderName);
    };

    // 監聽緊急來電
    _signaling.onEmergencyCall = (roomId, senderId, callId, [senderName]) {
      if (!mounted) return;
      debugPrint('🚨 [FamilyMainScreen] 緊急來電: room=$roomId, senderName=$senderName');
      _showIncomingCallDialog(roomId, senderId, callId, isEmergency: true, callerName: senderName);
    };

    // 監聽取消呼叫
    _signaling.onCancelCall = (roomId, senderId, callId, [senderName]) {
      if (!mounted) return;
      debugPrint('🔕 [FamilyMainScreen] 來電取消: room=$roomId');
      if (_isIncomingCallDialogOpen && Navigator.canPop(context)) {
        Navigator.of(context).pop();
        _isIncomingCallDialogOpen = false;
      }
    };

    // 監聽長輩設備狀態更新
    _signaling.onElderDevicesUpdate = (devices) {
      if (!mounted) return;
      debugPrint('📡 [FamilyMainScreen] 收到長輩設備狀態更新: $devices');
      final online = devices.any((d) => d['isOnline'] == true);
      _pendingOnlineState = online;
      _onlineStateDebounceTimer?.cancel();
      _onlineStateDebounceTimer = Timer(const Duration(milliseconds: 2500), () {
        if (!mounted || _pendingOnlineState == null) return;
        final bool stableOnline = _pendingOnlineState!;
        setState(() {
          _isElderOnline = stableOnline;
          if (stableOnline) {
            final onlineDevice = devices.firstWhere((d) => d['isOnline'] == true, orElse: () => {});
          } else {
          }
        });
      });
    };
  }

  Future<void> _switchElder(Elder elder) async {
    if (elder.id == _currentElder?.id) return;
    
    debugPrint('🔄 切換關照長輩至: ${elder.displayName} (ID: ${elder.id})');
    
    // 1. 掛斷當前通話/釋放連線
    _signaling.hangUp(disposeLocalStream: true);
    
    // 2. 更新選中的長輩
    await ElderManager().setCurrentElder(elder);
    
    // 3. 更新本地狀態並重新連線
    setState(() {
      _currentElder = elder;
      _isElderOnline = false;
    });
    
    await _loadElderAndConnect();
  }

  Future<void> _refreshElders() async {
    await ElderManager().refresh();
    if (mounted) {
      setState(() {
        _elders = ElderManager().pairedElders;
        _currentElder = ElderManager().currentElder;
      });
      await _loadElderAndConnect();
    }
  }

  void _onPendingCallChanged() {
    _checkPendingAcceptedCall();
  }

  void _checkPendingAcceptedCall() {
    if (pendingAcceptedCall.value != null) {
      final args = pendingAcceptedCall.value!;
      pendingAcceptedCall.value = null; // 處理後清空
      
      final senderId = args['senderId']!;
      final roomId = args['roomId']!;
      final callId = args['callId'];
      // ★ 2026-07-22 第八輪 Fix 3：防角色反轉。senderRole 為發起方角色，
      //   家屬端只應接聽「長輩」發起的來電。若 senderRole == 'family'（自身角色），
      //   代表這是自己這方發出、經 stale state 回流的假來電 → 拒絕並清除，
      //   否則會誤發 sendCallAccept 讓對端反被叫（接收方變發起方）。
      final String? senderRole = args['senderRole'];
      if (senderRole != null && senderRole.isNotEmpty && senderRole == appRole) {
        debugPrint("🚫 [FamilyMainScreen] 忽略角色反轉來電 (senderRole=$senderRole == appRole=$appRole, callId=$callId)");
        return;
      }
      final int now = DateTime.now().millisecondsSinceEpoch;
      final int? expiresAt = int.tryParse('${args['expiresAt'] ?? ''}');
      final int? issuedAt = int.tryParse('${args['issuedAt'] ?? ''}');
      final bool isExpired = (expiresAt != null && now > expiresAt) || (issuedAt != null && (now - issuedAt) > kCallValidityMs);
      if (isExpired) {
        debugPrint("⏰ [FamilyMainScreen] 忽略過期待接聽來電 (callId=$callId)");
        return;
      }
      
      debugPrint("🔔 [FamilyMainScreen] 偵測到背景 CallKit 接聽 (Sender: $senderId, Room: $roomId)");
      
      // 確保視窗已關閉
      if (_isIncomingCallDialogOpen && Navigator.canPop(context)) {
        Navigator.pop(context);
        _isIncomingCallDialogOpen = false;
      }
      
      // 發送接聽信號
      _signaling.sendCallAccept(senderId, callId: callId);
      
      // 跳轉通話畫面
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoCallScreen(
            roomId: roomId,
            targetSocketId: senderId,
            isIncomingCall: true,
            callId: callId,
            sendAcceptOnOpen: false,
          ),
        ),
      ).then((_) {
        if (mounted) _setupSignalingCallbacks();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingAcceptedCall();
    }
  }

  void _showIncomingCallDialog(String roomId, String senderId, String? callId, {bool isEmergency = false, String? callerName}) {
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
            // ★ issue 11：優先使用後端解析出的實際來電者名稱，
            //   避免在切換關照長輩後，來電通知仍顯示先前選擇的長輩名稱
            '${callerName ?? _currentElder?.displayName ?? "長輩"} 正在呼叫您！',
            style: const TextStyle(fontSize: 18),
          ),
          backgroundColor: isEmergency ? Colors.red.shade50 : Colors.green.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            ElevatedButton.icon(
              onPressed: () {
                _signaling.sendCallBusy(senderId, callId: callId);
                Navigator.of(dialogContext).pop();
                _isIncomingCallDialogOpen = false;
              },
              icon: const Icon(Icons.call_end),
              label: const Text('拒接', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
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
                      callId: callId,
                      sendAcceptOnOpen: false,
                    ),
                  ),
                ).then((_) {
                  if (mounted) _setupSignalingCallbacks();
                });
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

  void _showElderSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Text(
                    '切換關照對象',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_elders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Text(
                      '目前沒有配對的長輩裝置',
                      style: GoogleFonts.notoSansTc(color: const Color(0xFF64748B)),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _elders.length,
                      itemBuilder: (context, index) {
                        final elder = _elders[index];
                        final isSelected = elder.id == _currentElder?.id;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: elder.gender == 'F'
                                ? const Color(0xFFFDF2F8)
                                : const Color(0xFFF0FDF4),
                            child: Text(
                              elder.genderEmoji,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                          title: Text(
                            elder.displayName,
                            style: GoogleFonts.notoSansTc(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF0F172A),
                            ),
                          ),
                          subtitle: Text(
                            'ID: ${elder.id} • ${elder.age ?? "?"}歲',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle_rounded, color: Color(0xFF3B82F6))
                              : null,
                          onTap: () {
                            Navigator.pop(context);
                            _switchElder(elder);
                          },
                        );
                      },
                    ),
                  ),
                const Divider(height: 24, color: Color(0xFFF1F5F9)),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEFF6FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF3B82F6), size: 20),
                  ),
                  title: Text(
                    '配對新的長輩裝置',
                    style: GoogleFonts.notoSansTc(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CaregiverPairingScreen(
                          familyId: widget.userId,
                          familyName: widget.userName,
                        ),
                      ),
                    ).then((_) => _refreshElders());
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deviceRefreshTimer?.cancel();
    _onlineStateDebounceTimer?.cancel();
    pendingAcceptedCall.removeListener(_onPendingCallChanged);
    _signaling.onCallRequest = null;
    _signaling.onEmergencyCall = null;
    _signaling.onCancelCall = null;
    _signaling.onElderDevicesUpdate = null;
    super.dispose();
  }

  void _onItemTapped(int index) {
    HapticFeedback.lightImpact(); // 添加觸覺反饋
    setState(() {
      _selectedIndex = index;
    });
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0F172A),
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 16,
      title: _currentElder == null
          ? Text(
              'Uban 照護中樞',
              style: GoogleFonts.notoSansTc(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 24,
              ),
            )
          : InkWell(
              onTap: _showElderSelector,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF1E293B),
                      child: Text(
                        _currentElder?.genderEmoji ?? '',
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _currentElder?.displayName ?? '',
                      style: GoogleFonts.notoSansTc(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF38BDF8),
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    _PulseDot(
                      color: _isElderOnline
                          ? const Color(0xFF10B981)
                          : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isElderOnline ? '在線' : '離線',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 14,
                        color: _isElderOnline
                            ? const Color(0xFF34D399)
                            : const Color(0xFF94A3B8),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      actions: [
        IconButton(
          icon: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFF5C451), size: 26),
          tooltip: '訂閱測試（為長輩開通）',
          onPressed: () {
            final elder = _currentElder;
            Navigator.push(
              context,
              MaterialPageRoute(
                // 帶入 elder_id → RevenueCat App User ID 綁成 elder_<id>，
                // 購買才會落到這位長輩身上（見 SubscriptionTestScreen 說明）。
                builder: (context) => SubscriptionTestScreen(
                  elderId: elder?.elderId ?? elder?.id.toString(),
                  elderName: elder?.displayName,
                ),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF38BDF8), size: 28),
          tooltip: '配對新長輩',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CaregiverPairingScreen(
                  familyId: widget.userId,
                  familyName: widget.userName,
                ),
              ),
            ).then((_) => _refreshElders());
          },
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          color: Colors.white.withValues(alpha: 0.08),
          height: 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      extendBody: true,
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          FamilyHomeTab(
            currentElder: _currentElder,
            isElderOnline: _isElderOnline,
            onNavigateToAlerts: () {
              if (_currentElder != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (c) => AlertCenterScreen(
                      elderName: _currentElder!.displayName,
                      elderId: _currentElder!.id,
                    ),
                  ),
                );
              }
            },
          ),
          FamilyInteractionTab(
            currentElder: _currentElder,
            signaling: _signaling,
          ),
          FamilyDataTab(
            currentElder: _currentElder,
            userId: widget.userId,
            userName: widget.userName,
            onElderUpdated: () {
              _refreshElders();
            },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          height: 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 24,
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
                  color: const Color(0xFF1E293B).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(0, Icons.home_rounded, '首頁'),
                    _buildNavItem(1, Icons.chat_bubble_rounded, '互動'),
                    _buildNavItem(2, Icons.settings_rounded, '資料'),
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
        ? const Color(0xFF38BDF8) // Neon Cyan Glow
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
                child: Icon(icon, color: color, size: 29),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: GoogleFonts.notoSansTc(
                  color: color,
                  fontSize: 13,
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

class _PulseDot extends StatelessWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .fade(duration: 1200.ms, begin: 1.0, end: 0.3)
        .then()
        .fade(duration: 1200.ms, begin: 0.3, end: 1.0);
  }
}
