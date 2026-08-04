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
import 'family/family_subscription_screen.dart';
import '../models/elder.dart';
import '../services/elder_manager.dart';
import '../services/signaling.dart';
import '../services/api_service.dart';
import 'video_call_screen.dart';
import 'caregiver_pairing_screen.dart';
import 'family_onboarding_screen.dart';
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
  String? _elderSocketId;
  Timer? _deviceRefreshTimer;
  Timer? _onlineStateDebounceTimer;
  bool? _pendingOnlineState;

  // ★ 移植自 family_dashboard_view.dart：監控裝置清單、CCTV 警報、訂閱層級
  //   （型別對齊該檔實際宣告：_monitorDevices 為 List<dynamic>、_tierLevel 為 String）
  List<dynamic> _monitorDevices = [];
  final List<Map<String, dynamic>> _activeAlerts = [];
  final Set<int> _knownAlertIds = {};
  String _tierLevel = 'free';
  String _tierDisplayName = '一般會員';
  int _devicesMax = 2;

  /// ★ 2026-08-04 第 4 項：訂閱到期／設備超量彈窗只在每次進入本畫面時提示一次，
  /// 避免每次 `_loadSubscriptionTier()` 重新整理都再彈一次而干擾使用者。
  bool _overLimitDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    pendingAcceptedCall.addListener(_onPendingCallChanged);

    appLogger.d('🔍 FamilyMainScreen initialized:');
    appLogger.d('   userId: ${widget.userId}');
    appLogger.d('   userName: ${widget.userName}');

    _initializeElderManagerAndConnect();
    _loadSubscriptionTier();
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
      // ★ B2 修復（2026-08-04）：原本這裡只印 log 就直接 return，完全沒有重試，
      //   導致家屬端永遠不會 join 任何房間 → 後端 rooms_manager/user_fcm_token
      //   查無此房 → 長輩來電時後端記「無任何轉發目標」，通話 100% 遺失且前端毫無提示。
      //   改為有限次數（最多 2 次、間隔 2 秒）重新初始化 ElderManager 後再檢查一次；
      //   若仍失敗則印出顯眼錯誤並中止，不進入無窮迴圈、不阻塞 initState。
      const maxRetries = 2;
      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        if (attempt > 1) {
          await Future.delayed(const Duration(seconds: 2));
          if (!mounted) return;
        }
        debugPrint('🔁 [FamilyMainScreen] 第 $attempt/$maxRetries 次嘗試重新取得配對長輩...');
        await ElderManager().initialize(userId: widget.userId);
        if (!mounted) return;
        final refreshedElder = ElderManager().currentElder;
        if (refreshedElder != null) {
          setState(() {
            _elders = ElderManager().pairedElders;
            _currentElder = refreshedElder;
          });
          debugPrint('✅ [FamilyMainScreen] 第 $attempt 次重試成功取得配對長輩: ${refreshedElder.displayName}');
          break;
        }
      }

      if (_currentElder == null) {
        debugPrint('❌❌❌ [FamilyMainScreen] 無法取得配對長輩，家屬端將不會加入任何房間 → 長輩來電必然收不到！請檢查 family_elder_relationship 配對資料。');
        return;
      }
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

    // ★ B3（2026-08-04）：連線後印出 join 參數，供真機除錯比對家屬端與長輩端房號是否一致
    //   （房號漂移會導致長輩端 join-failed 而被後端斷線）。純 log，不影響邏輯。
    debugPrint('🔑 [FamilyMainScreen] join 參數：room=$roomId, role=family, userId=${widget.userId}, fcmToken=${fcmToken == null ? "null" : "${fcmToken.substring(0, fcmToken.length < 12 ? fcmToken.length : 12)}..."}');

    // ★ B1（2026-08-04）：此處 socket 必定已由上面的 _signaling.connect(...) 建立完成，
    //   再呼叫一次以保證 elder-unbound 監聽器確實掛上
    //   （_setupSignalingCallbacks() 那次呼叫發生在 connect() 之前，socket 當時可能仍是 null）。
    _registerElderUnboundListener();
    _registerCctvAlertListener();

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

    // ★ 2026-07-30 Task 2：監聽長輩被解綁事件，即時更新 UI，避免黑屏。
    // ★ B1 修復（2026-08-04）：原本用 _signaling.socket?.on(...) 直接掛在這裡，
    //   但 initState → _initializeElderManagerAndConnect() 呼叫本方法時 socket 還沒建立
    //   （socket 要到稍後的 _loadElderAndConnect() → _signaling.connect() 才建立），
    //   `?.` 短路導致這個監聽器從未掛上。改為呼叫可重試、冪等的註冊方法；
    //   真正確保掛得上的第二次呼叫點在 _loadElderAndConnect() 內 connect() 之後。
    _registerElderUnboundListener();
    _registerCctvAlertListener();

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
            _elderSocketId = onlineDevice.isNotEmpty ? onlineDevice['id'] : null;
          } else {
            _elderSocketId = null;
          }
          // ★ 移植自 family_dashboard_view.dart 第 119-121 行：過濾出監視機設備
          _monitorDevices = devices.where((d) => d['deviceMode'] == 'monitor').toList();
        });
      });
    };
  }

  /// ★ B1（2026-08-04）：'elder-unbound' 事件的實際處理邏輯，從原本直接掛在
  /// `_signaling.socket?.on(...)` 的 inline callback 原封不動抽出，供
  /// `_registerElderUnboundListener()` 在 socket 確定存在時掛上。
  void _handleElderUnbound(dynamic data) {
    if (!mounted) return;
    try {
      final unboundElderId = data is Map ? (data['elderId'] ?? data['elder_id'])?.toString() : null;
      debugPrint('🔓 [FamilyMainScreen] 收到 elder-unbound: elderId=$unboundElderId');
      if (unboundElderId == null) return;

      // 比對當前選中的長輩
      final currentElderId = _currentElder?.elderId ?? _currentElder?.id?.toString();
      final isCurrentElder = unboundElderId == currentElderId;

      // 從列表中移除
      setState(() {
        _elders.removeWhere((e) {
          final eId = e.elderId ?? e.id.toString();
          return eId == unboundElderId;
        });
        if (isCurrentElder) {
          _currentElder = null;
          _isElderOnline = false;
          _elderSocketId = null;
        }
      });

      // 同步 ElderManager
      ElderManager().removeElderLocally(unboundElderId);

      // 若列表為空 → 導航至 Onboarding；否則若目前長輩被解綁 → 自動選第一個
      if (_elders.isEmpty) {
        debugPrint('🔓 [FamilyMainScreen] 所有長輩已解綁，導航至 Onboarding');
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => FamilyOnboardingScreen(userId: widget.userId, userName: widget.userName)),
            (route) => false,
          );
        }
      } else if (isCurrentElder) {
        debugPrint('🔓 [FamilyMainScreen] 當前長輩被解綁，自動切換至第一個');
        _switchElder(_elders.first);
      }
    } catch (e) {
      debugPrint('❌ [FamilyMainScreen] elder-unbound 處理失敗: $e');
    }
  }

  /// ★ B1（2026-08-04）：冪等註冊 'elder-unbound' 監聽器。socket 尚未建立時安全跳過，
  /// 呼叫端（_setupSignalingCallbacks / _loadElderAndConnect）需在 socket 建立後再呼叫一次，
  /// 才能保證監聽器實際掛上（見上方兩處呼叫點的註解）。
  void _registerElderUnboundListener() {
    final s = _signaling.socket;
    if (s == null) {
      debugPrint('⚠️ [FamilyMainScreen] socket 尚未建立，elder-unbound 監聽器延後註冊');
      return;
    }
    s.off('elder-unbound'); // 冪等：避免重連時重複註冊造成同一事件觸發多次
    s.on('elder-unbound', _handleElderUnbound);
    debugPrint('✅ [FamilyMainScreen] elder-unbound 監聽器已註冊');
  }

  /// ★ 移植自 family_dashboard_view.dart 第 145-160 行：處理 CCTV 跌倒警報（YOLO）。
  /// 從原本直接掛在 `_signaling.socket?.on(...)` 的 inline callback 抽出，
  /// 供 `_registerCctvAlertListener()` 在 socket 確定存在時掛上（比照 `_handleElderUnbound`）。
  void _handleCctvAlert(dynamic data) {
    if (!mounted) return;
    try {
      final alertId = data is Map ? int.tryParse((data['alert_id'] ?? data['alertId'])?.toString() ?? '') : null;
      if (alertId == null || _knownAlertIds.contains(alertId)) return;
      _knownAlertIds.add(alertId);
      final newAlert = Map<String, dynamic>.from(data is Map ? data : {});
      setState(() {
        _activeAlerts.insert(0, newAlert);
        if (_activeAlerts.length > 20) _activeAlerts.removeLast();
      });
      debugPrint('🚨 [FamilyMainScreen] 收到 CCTV 警報: ${newAlert['alert_type']} elder=${newAlert['elder_id']}');
    } catch (e) {
      debugPrint('❌ [FamilyMainScreen] cctv-alert 處理失敗: $e');
    }
  }

  /// ★ 冪等註冊 'cctv-alert' 監聽器。socket 尚未建立時安全跳過，
  /// 呼叫端（_setupSignalingCallbacks / _loadElderAndConnect）需在 socket 建立後再呼叫一次，
  /// 註冊方式完全比照 `_registerElderUnboundListener()`。
  void _registerCctvAlertListener() {
    final s = _signaling.socket;
    if (s == null) {
      debugPrint('⚠️ [FamilyMainScreen] socket 尚未建立，cctv-alert 監聽器延後註冊');
      return;
    }
    s.off('cctv-alert'); // 冪等：避免重連時重複註冊造成同一事件觸發多次
    s.on('cctv-alert', _handleCctvAlert);
    debugPrint('✅ [FamilyMainScreen] cctv-alert 監聽器已註冊');
  }

  /// ★ 移植自 family_dashboard_view.dart 第 396-409 行（原名 _loadTier）：
  /// 載入使用者目前訂閱層級，供監控區塊的訂閱徽章與設備上限顯示。
  Future<void> _loadSubscriptionTier() async {
    try {
      final data = await ApiService.getSubscriptionTier(widget.userId);
      if (data['tier_level'] != null && mounted) {
        setState(() {
          _tierLevel = (data['tier_level'] ?? 'free').toString();
          _tierDisplayName = (data['tier_display_name'] ?? '一般會員').toString();
          _devicesMax = (data['devices_max'] ?? 2) as int;
        });

        // ★ 2026-08-04 第 4 項：訂閱到期後方案會退回免費層（上限 2 台），
        //   原本合法的 3～5 台監視機就變成超量。此時必須讓使用者二選一：
        //   繼續訂閱，或刪掉多出來的監視機。
        //   後端 `over_limit` 已是「逐位長輩比對 devices_in_use > devices_max」的結果，
        //   前端不重算，避免兩邊判準不一致。
        final overLimit = data['over_limit'] == true;
        if (overLimit && !_overLimitDialogShown) {
          _overLimitDialogShown = true;
          // 用 postFrameCallback：此時仍在 setState 的建置流程中，直接 showDialog 會拋例外。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showSubscriptionOverLimitDialog(
              elders: (data['elders'] as List?) ?? const [],
              endDate: data['end_date']?.toString(),
              totalDevicesInUse: (data['total_devices_in_use'] ?? 0) is int
                  ? data['total_devices_in_use'] as int
                  : int.tryParse('${data['total_devices_in_use']}') ?? 0,
            );
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ [FamilyMainScreen] 載入訂閱層級失敗: $e');
    }
  }

  /// ★ 2026-08-04 第 4 項：監視機超過方案上限時的二選一彈窗。
  /// `barrierDismissible: false` —— 這是需要使用者做決定的狀態，
  /// 但仍保留「稍後再說」出口，不可把人鎖死在彈窗裡。
  void _showSubscriptionOverLimitDialog({
    required List<dynamic> elders,
    String? endDate,
    required int totalDevicesInUse,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
            const SizedBox(width: 10),
            const Expanded(child: Text('監視機數量超過方案上限')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('目前方案：$_tierDisplayName（每位長輩上限 $_devicesMax 台）'),
            if (endDate != null && endDate.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('訂閱到期日：$endDate',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            ],
            const SizedBox(height: 4),
            Text('目前使用中：共 $totalDevicesInUse 台',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            // 逐位長輩列出超量狀況，讓使用者知道要從哪一位長輩底下刪除
            ...elders.where((e) => e['over_limit'] == true).map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${e['elder_name'] ?? e['elder_id']}：'
                      '${e['devices_in_use']} / ${e['devices_max']} 台',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            const SizedBox(height: 12),
            const Text(
              '請選擇繼續訂閱以保留全部監視機，或刪除部分監視機以符合目前方案。',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('稍後再說', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _showDeleteMonitorDeviceDialog();
            },
            child: Text('刪除部分監視機',
                style: TextStyle(color: Colors.red.shade700)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const FamilySubscriptionScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF59B294),
              foregroundColor: Colors.white,
            ),
            child: const Text('繼續訂閱'),
          ),
        ],
      ),
    );
  }

  /// ★ 2026-08-04 第 4 項：刪除監視機的挑選介面。
  /// 只列出「目前關照中的這位長輩」底下的監視機——Socket 的
  /// `elder-devices-update` 本來就只推送當前長輩的設備清單，
  /// 硬要跨長輩列出會需要另一支 API，且使用者也必須先切換長輩才看得到畫面。
  void _showDeleteMonitorDeviceDialog() {
    final elder = _currentElder;
    if (elder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇要管理的長輩')),
      );
      return;
    }
    final String rawElderId = elder.elderId ?? elder.id.toString();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('刪除監視機（${elder.displayName}）'),
          content: SizedBox(
            width: double.maxFinite,
            child: _monitorDevices.isEmpty
                ? const Text('這位長輩目前沒有連接任何監視機設備')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _monitorDevices.length,
                    itemBuilder: (_, index) {
                      final device = _monitorDevices[index];
                      final name =
                          (device['deviceName'] ?? 'Unnamed').toString();
                      final isOnline = device['isOnline'] == true;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.videocam_rounded,
                          color: isOnline ? const Color(0xFF59B294) : Colors.grey,
                        ),
                        title: Text(name, style: const TextStyle(fontSize: 15)),
                        subtitle: Text(isOnline ? '線上' : '離線',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600)),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline,
                              color: Colors.red.shade600),
                          onPressed: () async {
                            final confirmed = await _confirmDeleteDevice(name);
                            if (confirmed != true) return;
                            final ok = await ApiService.deleteMonitorDevice(
                              elderId: rawElderId,
                              deviceName: name,
                            );
                            if (!mounted) return;
                            if (ok) {
                              // 後端刪除後會廣播 elder-devices-update，
                              // _monitorDevices 會自動更新；這裡同步移除以便彈窗即時反映。
                              setState(() => _monitorDevices.removeWhere(
                                  (d) => d['deviceName'] == name));
                              setDialogState(() {});
                              await _loadSubscriptionTier();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('刪除失敗，請稍後再試')),
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmDeleteDevice(String deviceName) {
    return showDialog<bool>(
      context: context,
      builder: (confirmContext) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('確定要移除監視機「$deviceName」嗎？\n該設備將被登出並停止推送畫面。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(confirmContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
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
            isVideoCall: parseIsVideoCall(args['isVideoCall']), // ★ 2026-08-02 第十四輪修正
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
                      isVideoCall: _signaling.isVideoCallFor(callId), // ★ Fix E
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
      centerTitle: false,
      titleSpacing: 16,
      title: _currentElder == null
          ? Text(
              'Uban 照護中樞',
              style: GoogleFonts.notoSansTc(
                color: const Color(0xFF0F172A),
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
                      backgroundColor: _currentElder?.gender == 'F'
                          ? const Color(0xFFFDF2F8)
                          : const Color(0xFFF0FDF4),
                      child: Text(
                        _currentElder?.genderEmoji ?? '',
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _currentElder?.displayName ?? '',
                      style: GoogleFonts.notoSansTc(
                        color: const Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF64748B),
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
          icon: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF3B82F6), size: 28),
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
            monitorDevices: _monitorDevices,
            activeAlerts: _activeAlerts,
            devicesMax: _devicesMax,
            tierDisplayName: _tierDisplayName,
            tierLevel: _tierLevel,
            userId: widget.userId,
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
          height: 82,
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
        ? const Color(0xFF59B294) // Primary Teal
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
