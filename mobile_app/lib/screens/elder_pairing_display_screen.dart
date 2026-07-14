import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'elder_home_screen.dart';
import 'elder_screen.dart'; // ★ 監控機模式導向
import 'dart:async';

class ElderPairingDisplayScreen extends StatefulWidget {
  const ElderPairingDisplayScreen({super.key});

  @override
  State<ElderPairingDisplayScreen> createState() =>
      _ElderPairingDisplayScreenState();
}

class _ElderPairingDisplayScreenState extends State<ElderPairingDisplayScreen> {
  static const bool _devBypassLogin = bool.fromEnvironment(
    'DEV_BYPASS_LOGIN',
    defaultValue: false,
  );
  static const int _devBypassUserId = int.fromEnvironment(
    'DEV_BYPASS_USER_ID',
    defaultValue: 1,
  );
  static const String _devBypassUserName = String.fromEnvironment(
    'DEV_BYPASS_USER_NAME',
    defaultValue: 'TestElder',
  );

  String? _pairingCode;
  int _secondsLeft = 0;
  bool _isLoading = true;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _requestNewCode();
  }

  // ★ 自動決定設備角色（不需資料庫欄位、不需手動選擇）：
  //   詢問後端該長輩是否已存在「通話機」。
  //   - 尚無通話機 → 本設備成為「通話機」(comm)，進入長輩首頁。
  //   - 已有通話機 → 本設備自動成為「監控機」(monitor / CCTV 守護)。
  //   角色會存進 SharedPreferences，之後重開機沿用，不會角色互換。
  Future<void> _promptModeAndNavigate(int elderId, String elderName, String? elderRoomId) async {
    final String elderRoom = elderRoomId ?? elderId.toString();
    final prefs = await SharedPreferences.getInstance();

    // ★ Issue 2 修復：本裝置對「這個長輩」的角色（通話機/監控機）只在首次決定，
    //   之後（含快速登入、重開機）一律沿用，不再重新呼叫 hasCommDevice，
    //   避免同一台裝置重新登入時，因後端殘留的舊 FCM token 被誤判為「已有通話機」
    //   而被錯誤指派為監控機（CCTV）。
    final String deviceRoleKey = 'device_role_$elderRoom';
    final String? savedRole = prefs.getString(deviceRoleKey);

    bool isMonitor;
    if (savedRole != null) {
      isMonitor = savedRole == 'monitor';
      debugPrint(
          '🔁 [ElderPairingDisplay] 沿用已記住的裝置角色 ($deviceRoleKey=$savedRole)，不重查 hasCommDevice');
    } else {
      isMonitor = await ApiService.hasCommDevice(elderRoom);
      await prefs.setString(deviceRoleKey, isMonitor ? 'monitor' : 'comm');
      debugPrint(
          '🆕 [ElderPairingDisplay] 首次判定裝置角色 ($deviceRoleKey=${isMonitor ? 'monitor' : 'comm'})');
    }

    await prefs.setBool('saved_is_cctv', isMonitor);

    // 自動產生裝置名稱，免除中文輸入問題；監控機用不同名稱避免與通話機衝突
    final deviceName = isMonitor ? '$elderName的監控機' : '$elderName的設備';
    await prefs.setString('saved_device_name', deviceName);

    if (!mounted) return;

    if (isMonitor) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ElderScreen(
            roomId: elderRoom,
            isCCTVMode: true,
            deviceName: deviceName,
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ElderHomeScreen(
            userId: elderId,
            userName: elderName,
            roomId: elderRoom,
          ),
        ),
      );
    }
  }


  Future<void> _requestNewCode() async {
    setState(() => _isLoading = true);
    try {
      final result = await ApiService.requestPairingCode();
      if (!mounted) return;

// 檢查 API 是否回傳錯誤
      if (result['status'] == 'error') {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'API 錯誤：${result['message'] ?? result['error'] ?? '未知錯誤'}')),
        );
        return;
      }

// 從 API Response 的 data 欄位取得配對碼
      final data = result['data'] as Map<String, dynamic>?;

      setState(() {
        _pairingCode = data?['pairing_code'];
        _secondsLeft = data?['expires_in_seconds'] ?? 600;
        _isLoading = false;
      });

      if (_pairingCode != null) {
        _startStatusPolling();
      } else {
        // 顯示更詳細的錯誤資訊
        final errorDetail = result.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法取得配對碼：$errorDetail')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('申請代碼失敗：$e')));
    }
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_pairingCode == null) return;
      try {
        final result = await ApiService.checkPairingStatus(_pairingCode!);
        if (!mounted) return;

// 從 API Response 的 data 欄位取得配對狀態
        final status = result['data'] as Map<String, dynamic>?;
        if (status == null) return;

        if (status['status'] == 'paired') {
          timer.cancel();

          // 核心修復：持久化儲存長輩 ID、姓名與角色
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('caregiver_id', status['elder_id']);
          await prefs.setString('caregiver_name', status['elder_name'] ?? '長輩');
          await prefs.setString('user_role', 'elder');
          
          final String? elderRoomId = status['room_id']?.toString() ?? status['elder_profile_id']?.toString() ?? status['elder_id']?.toString();
          if (elderRoomId != null) {
            await prefs.setString('elder_room_id', elderRoomId);
          }

          if (!mounted) return;

          // ★ 呼叫提示選擇模式
          await _promptModeAndNavigate(status['elder_id'], status['elder_name'] ?? '長輩', elderRoomId);
        }
      } catch (e) {
// 靜默處理
      }
    });
  }

  Future<void> _quickLoginSameElder() async {
    final prefs = await SharedPreferences.getInstance();

    // ★ Issue 3 診斷 log：記錄呼叫當下 prefs 內既有的三個關鍵欄位（尚未套用開發模式覆寫）。
    debugPrint(
        '🔎 [ElderPairingDisplay] _quickLoginSameElder 開頭 prefs 快照: caregiver_id=${prefs.getInt('caregiver_id')}, caregiver_name=${prefs.getString('caregiver_name')}, user_role=${prefs.getString('user_role')}');

    int? elderId;
    String? elderName;
    String? role;

    // 開發模式：固定使用同一個測試長輩帳號（不依賴 SharedPreferences 是否被清空）
    if (_devBypassLogin) {
      elderId = _devBypassUserId > 0 ? _devBypassUserId : 1;
      elderName =
          _devBypassUserName.isNotEmpty ? _devBypassUserName : 'TestElder';
      await prefs.setInt('caregiver_id', elderId);
      await prefs.setString('caregiver_name', elderName);
      await prefs.setString('user_role', 'elder');
      role = 'elder';
    } else {
      elderId = prefs.getInt('caregiver_id');
      elderName = prefs.getString('caregiver_name');
      role = prefs.getString('user_role');
    }

    if (!mounted) return;

    if (elderId == null || elderName == null || role != 'elder') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('尚未找到可快速登入的長輩帳號，請先完成一次配對')),
      );
      return;
    }

    final String? elderRoomId = prefs.getString('elder_room_id');
    // ★ 呼叫提示選擇模式
    await _promptModeAndNavigate(elderId!, elderName!, elderRoomId);
  }

  Future<void> loginAndPersist({required int elderId, required String elderName, String? elderRoomId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('caregiver_id', elderId);
    await prefs.setString('caregiver_name', elderName);
    await prefs.setString('user_role', 'elder');
    if (elderRoomId != null) {
      await prefs.setString('elder_room_id', elderRoomId);
    }

    if (!mounted) return;

    // ★ 呼叫提示選擇模式
    await _promptModeAndNavigate(elderId, elderName, elderRoomId);
  }

  Future<void> _quickLoginGawaDemo() async {
    try {
      final result = await ApiService.ensureGawaDemoElder();
      if (!mounted) return;

      print('🔍 Gawa API Response: $result');

      if (result['status'] == 'error') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(result['message'] ?? result['error'] ?? 'gawa帳號建立失敗')),
        );
        return;
      }

      final data = result['data'] as Map<String, dynamic>?;
      print('🔍 Gawa Data: $data');
      final rawElderId = data?['elder_user_id'];
      print('🔍 rawElderId: $rawElderId (type: ${rawElderId.runtimeType})');
      final elderId =
          rawElderId is int ? rawElderId : int.tryParse('${rawElderId ?? ''}');
      print('🔍 elderId after parse: $elderId');
      final elderName = (data?['elder_name'] ?? 'gawa').toString();
      final elderRoomId = data?['elder_id']?.toString();
      if (elderId == null || elderId <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('gawa帳號建立成功，但登入資料不完整')),
        );
        return;
      }

      await loginAndPersist(elderId: elderId, elderName: elderName, elderRoomId: elderRoomId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登入gawa失敗：$e')),
      );
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 100,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 40),
                  Text(
                    '等待家人配對',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '請子女開啟手機上的 UBan App\n並輸入下方的 4 位數配對碼',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 48),
                  if (_isLoading)
                    const CircularProgressIndicator()
                  else if (_pairingCode != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          FittedBox(
                            child: Text(
                              _pairingCode!,
                              style: GoogleFonts.inter(
                                fontSize: 72,
                                fontWeight: FontWeight.w900,
                                color: Colors.orange,
                                letterSpacing: 8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          QrImageView(
                            data: _pairingCode!,
                            version: QrVersions.auto,
                            size: 160.0,
                            backgroundColor: Colors.white,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '倒數: $_secondsLeft 秒',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 48),
                  TextButton(
                    onPressed: _requestNewCode,
                    child: const Text('更換代碼', style: TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _quickLoginSameElder,
                    icon: const Icon(Icons.login_rounded),
                    label: Text(_devBypassLogin ? '快速登入固定測試長輩' : '快速登入同一長輩'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF59B294),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _quickLoginGawaDemo,
                    icon: const Icon(Icons.elderly_rounded),
                    label: const Text('登入gawa'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D78),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
