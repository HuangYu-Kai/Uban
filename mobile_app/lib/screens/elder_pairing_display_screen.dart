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
  String? _pairingCode;
  int _secondsLeft = 0;
  bool _isLoading = true;
  bool isMonitor = false;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _requestNewCode();
  }

  /// ★ 2026-07-27 第十三輪：記住「上次登入的長輩」，供登出後的快速登入使用。
  ///
  /// 這組 `last_elder_*` 鍵刻意與 session 鍵（`caregiver_id` / `caregiver_name` /
  /// `user_role`）分離：使用者在長輩端按「切換身分／登出」時會清掉 session 鍵
  /// （見 `elder_tabs/elder_profile_tab.dart::_handleLogout`），而
  /// `_quickLoginSameElder` 正是讀那三個 session 鍵 —— 於是登出後快速登入必定失敗。
  /// 這組鍵登出時不清除，只有家屬端遠端 `force-logout`（強制解綁）才會一併清掉。
  static Future<void> _rememberLastElder(
    SharedPreferences prefs, {
    required int elderId,
    required String elderName,
    String? elderRoomId,
  }) async {
    await prefs.setInt('last_elder_id', elderId);
    await prefs.setString('last_elder_name', elderName);
    if (elderRoomId != null && elderRoomId.isNotEmpty) {
      await prefs.setString('last_elder_room_id', elderRoomId);
    }
    debugPrint(
        '💾 [ElderPairingDisplay] 已記住上次登入長輩 (id=$elderId, name=$elderName, room=$elderRoomId)');
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

    // ⚠️ 這行宣告在分支整合時遺失（HEAD 上 isMonitor 有 10 處使用卻無宣告，
    //    整個檔案無法編譯），2026-08-10 第十九輪補回。
    //    刻意維持**區域變數**：裝置角色的權威來源是 prefs 的 device_role_$room，
    //    存成 State 欄位反而會讓兩者有機會分歧。
    bool isMonitor;

    if (savedRole != null) {
      isMonitor = savedRole == 'monitor';
      debugPrint(
          '🔁 [ElderPairingDisplay] 沿用已記住的裝置角色 ($deviceRoleKey=$savedRole)，不重查 hasCommDevice');
    } else {
      isMonitor = await ApiService.hasCommDevice(elderRoom);
      if (isMonitor) {
        if (!mounted) return;
        final bool? chooseMonitor = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            title: Row(
              children: [
                const Text('👵 ', style: TextStyle(fontSize: 26)),
                Expanded(
                  child: Text(
                    '這台手機平常怎麼用呢？',
                    style: GoogleFonts.notoSansTc(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '請選擇您打算如何使用這台手機：\n（完全免費安心使用，之後隨時可以在設定更換喔！）',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 15,
                    color: const Color(0xFF475569),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                // 選項 1：隨身拿著用（打電話、看日曆、養小豬）
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, false), // 隨身通話機
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D78),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 2,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_iphone_rounded, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '📱 我隨身拿著用',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '打電話、看日曆、養小豬',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 13,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.white70),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 選項 2：放在客廳插著電（守護全家平安）
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, true), // 定點守護機
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF334155),
                    side: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.home_rounded, size: 28, color: Color(0xFF0284C7)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🏠 放在客廳插著電',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                            Text(
                              '定點守護、全家遠端平安連線',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 13,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFF94A3B8)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
        if (chooseMonitor != null) {
          isMonitor = chooseMonitor;
        }
      }
      await prefs.setString(deviceRoleKey, isMonitor ? 'monitor' : 'comm');
      debugPrint(
          '🆕 [ElderPairingDisplay] 首次判定裝置角色 ($deviceRoleKey=${isMonitor ? 'monitor' : 'comm'})');
    }

    await prefs.setBool('saved_is_cctv', isMonitor);
    await _rememberLastElder(
      prefs,
      elderId: elderId,
      elderName: elderName,
      elderRoomId: elderRoom,
    );
    // ★ 2026-07-27 第十三輪：把裝置角色一併存進「登出不清除」的記憶鍵，
    //   讓快速登入能原封不動還原角色，不必重新呼叫 hasCommDevice 重判。
    await prefs.setString(
        'last_elder_device_role', isMonitor ? 'monitor' : 'comm');

    // 自動產生裝置名稱，免除中文輸入問題；監控機用不同名稱避免與通話機衝突
    final deviceName = isMonitor ? '$elderName的監控機' : '$elderName的設備';
    await prefs.setString('saved_device_name', deviceName);

    if (!mounted) return;

    if (isMonitor) {
      // ★ 必須用 pushAndRemoveUntil 清空堆疊，理由同 role_selection_screen.dart
      //   的說明：本畫面是從 IdentificationScreen 用 Navigator.push 進來的，
      //   若在此僅 pushReplacement，IdentificationScreen 會留在 ElderScreen
      //   底下；監控機模式的長輩在通話畫面內掛斷時，
      //   globals.dart::safeNavigateBack 會 pop 優先而誤降落在身分選擇頁。
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => ElderScreen(
            roomId: elderRoom,
            isCCTVMode: true,
            deviceName: deviceName,
          ),
        ),
        (route) => false,
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

          // ★ 2026-07-27 第十三輪：同步寫入登出不清除的快速登入記憶鍵
          await _rememberLastElder(
            prefs,
            elderId: status['elder_id'],
            elderName: status['elder_name'] ?? '長輩',
            elderRoomId: elderRoomId,
          );

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

    // ★ Issue 3 診斷 log：記錄呼叫當下 prefs 內既有的三個關鍵欄位。
    debugPrint(
        '🔎 [ElderPairingDisplay] _quickLoginSameElder 開頭 prefs 快照: caregiver_id=${prefs.getInt('caregiver_id')}, caregiver_name=${prefs.getString('caregiver_name')}, user_role=${prefs.getString('user_role')}');

    int? elderId = prefs.getInt('caregiver_id');
    String? elderName = prefs.getString('caregiver_name');
    String? role = prefs.getString('user_role');

    // ★ 2026-07-27 第十三輪：登出後 session 鍵已被清除（elder_profile_tab
    //   的 _handleLogout 會 remove caregiver_id / caregiver_name），
    //   此時改讀登出不清除的 last_elder_* 記憶鍵並還原 session。
    if (elderId == null || elderName == null || role != 'elder') {
      final int? lastId = prefs.getInt('last_elder_id');
      final String? lastName = prefs.getString('last_elder_name');
      if (lastId != null && lastName != null) {
        debugPrint(
            '♻️ [ElderPairingDisplay] session 鍵已被登出清除，改用 last_elder_* 還原 (id=$lastId)');
        elderId = lastId;
        elderName = lastName;
        role = 'elder';
        await prefs.setInt('caregiver_id', lastId);
        await prefs.setString('caregiver_name', lastName);
        await prefs.setString('user_role', 'elder');
        final String? lastRoom = prefs.getString('last_elder_room_id');
        if (lastRoom != null && lastRoom.isNotEmpty) {
          await prefs.setString('elder_room_id', lastRoom);
        }

        // ★ 一併還原裝置角色（通話機／監控機）。
        //   登出時 saved_is_cctv 與 device_role_* 都被清掉，若不還原，
        //   _promptModeAndNavigate 會重新呼叫 hasCommDevice 重判；一旦被判成
        //   monitor，就會觸發「通訊機被記成 monitor → FCM 送成 monitor-wakeup
        //   → 被 App 丟棄 → 長輩被殺死收不到來電」那條 bug 鏈（護欄 #18/#19）。
        //   本裝置對這個長輩的角色本就該沿用（見 _promptModeAndNavigate 註解）。
        final String? lastDeviceRole =
            prefs.getString('last_elder_device_role');
        if (lastDeviceRole != null && lastDeviceRole.isNotEmpty) {
          final String room = (lastRoom != null && lastRoom.isNotEmpty)
              ? lastRoom
              : lastId.toString();
          await prefs.setString('device_role_$room', lastDeviceRole);
          await prefs.setBool('saved_is_cctv', lastDeviceRole == 'monitor');
          debugPrint(
              '♻️ [ElderPairingDisplay] 已還原裝置角色 (device_role_$room=$lastDeviceRole)');
        }
      }
    }

    if (!mounted) return;

    if (elderId == null || elderName == null || role != 'elder') {
      // ★ 第四十九輪 item 2：本機沒有任何可還原的長輩帳號時，不再靜默備援
      //   登入寫死的「宇璿」測試帳號——那顆備援本身就是幽靈帳號問題的一部分
      //   （會把 caregiver_id / last_elder_* 一併寫死成 user_id=2，讓這台裝置
      //   從此被誤認成宇璿）。留在目前這個配對等待畫面即可：使用者仍可掃碼
      //   配對，或點下方「🌟 我自己使用」進入自主模式（會另外詢問稱呼再建立
      //   帳號，不會用任何佔位字串頂替）。
      debugPrint('ℹ️ [ElderPairingDisplay] 無本機長輩記憶，維持在配對等待畫面');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('這台裝置還沒有登入過的長輩帳號，請掃描配對碼，或點下方「我自己使用」立即體驗'),
        ),
      );
      return;
    }

    final String? elderRoomId = prefs.getString('elder_room_id');
    // ★ 呼叫提示選擇模式
    await _promptModeAndNavigate(elderId, elderName, elderRoomId);
  }

  Future<void> loginAndPersist({required int elderId, required String elderName, String? elderRoomId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('caregiver_id', elderId);
    await prefs.setString('caregiver_name', elderName);
    await prefs.setString('user_role', 'elder');
    if (elderRoomId != null) {
      await prefs.setString('elder_room_id', elderRoomId);
    }
    // ★ 2026-07-27 第十三輪：同步寫入登出不清除的快速登入記憶鍵
    await _rememberLastElder(
      prefs,
      elderId: elderId,
      elderName: elderName,
      elderRoomId: elderRoomId,
    );

    if (!mounted) return;

    // ★ 呼叫提示選擇模式
    await _promptModeAndNavigate(elderId, elderName, elderRoomId);
  }

  /// 詢問長輩想怎麼被稱呼，用於自主模式建立帳號前。
  ///
  /// ⚠️ 第四十九輪 item 2：杜絕無名長輩幽靈帳號——建帳號前必須先問清楚真正的
  /// 稱呼，取消或留白就不送出任何建立帳號的請求，也不會用預設字串頂替。
  /// 樣式比照本檔案 [_promptModeAndNavigate] 既有的長輩端對話框（圓角卡片、
  /// 大字體、GoogleFonts.notoSansTc），不另外發明新樣式。
  Future<String?> _promptElderName() {
    final controller = TextEditingController();
    String? errorText;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            void submit() {
              final trimmed = controller.text.trim();
              if (trimmed.isEmpty) {
                setDialogState(() => errorText = '請輸入姓名或稱呼喔');
                return;
              }
              Navigator.pop(dialogContext, trimmed);
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              title: Row(
                children: [
                  const Text('😊 ', style: TextStyle(fontSize: 26)),
                  Expanded(
                    child: Text(
                      '怎麼稱呼您呢？',
                      style: GoogleFonts.notoSansTc(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '請輸入您的姓名或平常的稱呼，小嘎才知道怎麼親切地叫您喔！',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 15,
                      color: const Color(0xFF475569),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 20,
                    textInputAction: TextInputAction.done,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                    decoration: InputDecoration(
                      hintText: '例如：陳大明',
                      hintStyle: GoogleFonts.notoSansTc(fontSize: 18, color: const Color(0xFF94A3B8)),
                      errorText: errorText,
                      errorStyle: GoogleFonts.notoSansTc(fontSize: 14),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFF59B294), width: 2),
                      ),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF59B294),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 2,
                      ),
                      child: Text(
                        '確定',
                        style: GoogleFonts.notoSansTc(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, null),
                    child: Text(
                      '先不用了',
                      style: GoogleFonts.notoSansTc(fontSize: 15, color: const Color(0xFF64748B)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 🌟 方案 A：長者自主陪伴模式（單人即用，全新長者向雲端動態申領唯一獨立帳號）
  Future<void> _startAutonomousMode() async {
    final prefs = await SharedPreferences.getInstance();
    int? elderId = prefs.getInt('last_elder_id');
    String elderName = (prefs.getString('last_elder_name') ?? '').trim();
    String? elderRoomId = prefs.getString('last_elder_room_id');

    // ★ 第四十九輪 item 2：不論是全新建立帳號、或沿用本機既有的自主模式帳號，
    //   都必須先有一個長輩真正輸入過的稱呼，不可以用佔位字串頂替。過去這裡
    //   讀不到 last_elder_name 就退回寫死的「長輩朋友」，而呼叫
    //   createAutonomousElder() 時又從未把任何名字傳給後端，於是這個佔位
    //   字串被當成真正的姓名寫進 elder_profile——正是正式庫「長輩朋友」
    //   幽靈帳號的成因。
    if (elderName.isEmpty) {
      if (!mounted) return;
      final inputName = await _promptElderName();
      if (!mounted) return;
      if (inputName == null || inputName.trim().isEmpty) {
        // 長輩選擇不輸入，尊重選擇：留在原畫面，不建立任何帳號。
        return;
      }
      elderName = inputName.trim();
    }

    setState(() => _isLoading = true);
    try {
      // 若全新安裝無帳號，向後端申請專屬唯一的獨立長者帳號與房號（杜絕 ID 衝突）
      if (elderId == null) {
        final result = await ApiService.createAutonomousElder(elderName: elderName);
        if (result['status'] == 'success' && result['data'] != null) {
          final data = result['data'];
          elderId = data['user_id'] as int?;
          elderName = (data['elder_name'] as String?) ?? elderName;
          elderRoomId = (data['room_id']?.toString()) ?? (data['elder_profile_id']?.toString());
        } else {
          final err = result['detail'] ?? result['message'] ?? result['error'] ?? '建立帳號失敗';
          throw Exception(err);
        }
      }

      if (elderId == null) {
        throw Exception('無法獲取長輩帳號識別碼');
      }

      elderRoomId ??= 'room_$elderId';

      await prefs.setBool('is_autonomous_mode', true);
      await prefs.setInt('caregiver_id', elderId);
      await prefs.setString('caregiver_name', elderName);
      await prefs.setString('user_role', 'elder');
      await prefs.setString('saved_role', 'elder');
      await prefs.setString('elder_room_id', elderRoomId);
      await prefs.setBool('saved_is_cctv', false);
      await prefs.setString('saved_device_name', '$elderName的設備');
      await prefs.setString('device_role_$elderRoomId', 'comm');
      await _rememberLastElder(
        prefs,
        elderId: elderId,
        elderName: elderName,
        elderRoomId: elderRoomId,
      );
      await prefs.setString('last_elder_device_role', 'comm');

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ElderHomeScreen(
            userId: elderId!,
            userName: elderName,
            roomId: elderRoomId!,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('進入自主模式失敗：$e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
                    size: 80,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '等待家人配對',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '請子女開啟手機上的 Uban App\n並掃描下方 QR Code 或輸入配對碼',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 32),
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
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          FittedBox(
                            child: Text(
                              _pairingCode!,
                              style: GoogleFonts.inter(
                                fontSize: 64,
                                fontWeight: FontWeight.w900,
                                color: Colors.orange,
                                letterSpacing: 8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          QrImageView(
                            data: _pairingCode!,
                            version: QrVersions.auto,
                            size: 150.0,
                            backgroundColor: Colors.white,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '配對倒數: $_secondsLeft 秒',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 32),

                  // 🌟 方案 A：長者自主模式按鈕（極致醒目、長輩友善）
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: ElevatedButton.icon(
                      onPressed: _startAutonomousMode,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 24),
                      label: Text(
                        '🌟 我自己使用（直接進入體驗）',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF59B294),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '無須等待家人，點此先享受 AI 伴侶、農民曆與小豬養成（日後隨時可補綁家人）',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 13,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 次要操作區
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _requestNewCode,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('更換代碼', style: TextStyle(fontSize: 16)),
                      ),
                      const SizedBox(width: 16),
                      TextButton.icon(
                        onPressed: _quickLoginSameElder,
                        icon: const Icon(Icons.history_rounded, size: 18),
                        label: const Text(
                          '登入上次長輩',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
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
