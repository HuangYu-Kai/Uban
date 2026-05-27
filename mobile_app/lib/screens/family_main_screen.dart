import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 添加觸覺反饋
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'package:flutter_animate/flutter_animate.dart';
import 'family/family_home_tab.dart';
import 'family/family_interaction_tab.dart';
import 'family/family_data_tab.dart';
import 'family/alert_center_screen.dart';
import '../models/elder.dart';
import '../services/elder_manager.dart';
import '../services/signaling.dart';
import 'video_call_screen.dart';
import 'caregiver_pairing_screen.dart';
import 'package:flutter_application_1/utils/app_logger.dart';

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
  final Signaling _signaling = Signaling();
  bool _isIncomingCallDialogOpen = false;
  
  Elder? _currentElder;
  List<Elder> _elders = [];
  bool _isElderOnline = false;
  String? _elderSocketId;

  @override
  void initState() {
    super.initState();
    
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
    }
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
    
    _signaling.connect(
      roomId,
      'family',
      deviceName: '${widget.userName}的App',
      userId: widget.userId,
    );
    
    // 請求取得長輩設備在線狀態
    _signaling.sendGetElderDevices(roomId);
  }

  void _setupSignalingCallbacks() {
    // 監聽來電（長輩打給家屬）
    _signaling.onCallRequest = (roomId, senderId, callId) {
      if (!mounted) return;
      debugPrint('📞 [FamilyMainScreen] 收到來電: room=$roomId, sender=$senderId, callId=$callId');
      _showIncomingCallDialog(roomId, senderId, callId);
    };

    // 監聽緊急來電
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

    // 監聽長輩設備狀態更新
    _signaling.onElderDevicesUpdate = (devices) {
      if (!mounted) return;
      debugPrint('📡 [FamilyMainScreen] 收到長輩設備狀態更新: $devices');
      final online = devices.any((d) => d['isOnline'] == true);
      setState(() {
        _isElderOnline = online;
        if (online) {
          final onlineDevice = devices.firstWhere((d) => d['isOnline'] == true);
          _elderSocketId = onlineDevice['id'];
        } else {
          _elderSocketId = null;
        }
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
      _elderSocketId = null;
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
            '${_currentElder?.displayName ?? "長輩"} 正在呼叫您！',
            style: const TextStyle(fontSize: 18),
          ),
          backgroundColor: isEmergency ? Colors.red.shade50 : Colors.green.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            TextButton(
              onPressed: () {
                _signaling.sendCallBusy(senderId, callId: callId);
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
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 16,
      title: _currentElder == null
          ? Text(
              'Uban 照護中樞',
              style: GoogleFonts.notoSansTc(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            )
          : InkWell(
              onTap: _showElderSelector,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: _currentElder!.gender == 'F'
                          ? const Color(0xFFFDF2F8)
                          : const Color(0xFFF0FDF4),
                      child: Text(
                        _currentElder!.genderEmoji,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _currentElder!.displayName,
                      style: GoogleFonts.notoSansTc(
                        color: const Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF64748B),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    _PulseDot(
                      color: _isElderOnline
                          ? const Color(0xFF10B981)
                          : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isElderOnline ? '在線' : '離線',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 12,
                        color: _isElderOnline
                            ? const Color(0xFF065F46)
                            : const Color(0xFF64748B),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      actions: [
        IconButton(
          icon: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF3B82F6)),
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
          color: const Color(0xFFF1F5F9),
          height: 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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

class _PulseDot extends StatelessWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
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
