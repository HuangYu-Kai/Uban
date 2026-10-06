import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/recovery_code_entry.dart';
import 'elder_home_screen.dart';
import 'elder_screen.dart'; // ★ 監控機模式導向
import 'elder_profile_onboarding_screen.dart'; // ★ 第五十三輪 onboard53：長 9 強制補填
import '../utils/profile_completeness.dart';
import '../widgets/login_flow_parts.dart';
import '../widgets/ui/ui.dart';
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

  // ★ 2026-10-06 登入流程審查：真正會走的配對碼倒數（後端碼 10 分鐘過期）。
  Timer? _countdownTimer;
  // 防止「更換代碼」連點／倒數歸零自動換碼同時打出兩個請求。
  bool _requestingCode = false;
  // 配對成功後正在寫入／導航：暫停倒數與輪詢，避免重複處理。
  bool _handlingPaired = false;
  // 同一時間只允許一個「大動作」（我自己使用／更換代碼／登入上次長輩／輸入代碼），
  // 同步設旗標（在任何 await 之前），避免連點建立兩個帳號。
  String? _busyAction;

  static const String _kNetworkFriendly = '目前連不上伺服器，請確認網路後再試一次';

  @override
  void initState() {
    super.initState();
    _requestNewCode();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  /// ★ 2026-10-06：把任何錯誤轉成長輩看得懂的中文，原始內容只進 debugPrint。
  /// 後端 detail 現為中文，沒有明顯英文技術字樣時直接採用，其餘一律用友善預設。
  String _friendlyError(Object? raw) {
    debugPrint('⚠️ [ElderPairingDisplay] 原始錯誤: $raw');
    if (raw is String) {
      final text = raw.trim();
      final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
      final looksTechnical = RegExp(
              r'exception|error|socket|timeout|failed|null|trace|http|status|\b[45]\d\d\b|<|\{',
              caseSensitive: false)
          .hasMatch(text);
      if (hasCjk && !looksTechnical && !text.contains('網路連線失敗')) return text;
    }
    return _kNetworkFriendly;
  }

  /// 「大動作」互斥執行：旗標在第一個 await 之前同步設定。
  Future<void> _runExclusive(String key, Future<void> Function() body) async {
    if (_busyAction != null) return;
    _busyAction = key;
    if (mounted) setState(() {});
    try {
      await body();
    } catch (e) {
      debugPrint('⚠️ [ElderPairingDisplay] $key 失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendlyError(e))));
      }
    } finally {
      _busyAction = null;
      if (mounted) setState(() {});
    }
  }

  /// 每秒遞減；歸零時自動換新碼並重新倒數。
  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _handlingPaired) {
        timer.cancel();
        return;
      }
      if (_secondsLeft > 1) {
        setState(() => _secondsLeft--);
        return;
      }
      timer.cancel();
      setState(() => _secondsLeft = 0);
      _requestNewCode();
    });
  }

  String _countdownLabel() {
    if (_secondsLeft <= 0) return '正在更新配對碼…';
    final m = _secondsLeft ~/ 60;
    final sec = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '配對碼 $m:$sec 後更新';
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
      // ★ 第五十三輪 onboard53b（長 9）：導向通話機首頁前先檢查年齡／居住地
      //   是否已補齊，見下方 [_goToElderHome] 說明。
      await _goToElderHome(elderId, elderName, elderRoom);
    }
  }

  /// ★ 第五十三輪 onboard53b（長 9）：長輩帳號「年齡／居住地」完整度檢查後
  /// 導向通話機首頁。呼叫點：本檔案 [_promptModeAndNavigate] 的 comm 分支、
  /// [_startAutonomousMode]（涵蓋 [loginAndPersist] 間接呼叫 [_promptModeAndNavigate]
  /// 的情況，故共三條文件記載的長輩端入口都會經過這裡）。
  ///
  /// ⚠️ 刻意只覆蓋這裡，不覆蓋 [_promptModeAndNavigate] 的 isMonitor 分支——
  /// 監控機／CCTV 路徑維持直接導向 [ElderScreen]，理由見
  /// `elder_profile_onboarding_screen.dart` 檔頭：`ElderScreen` 是通話／CCTV
  /// 生命週期最複雜、風險最高的畫面，本輪任務明確劃出的紅線，不在其前面插入
  /// 任何新邏輯，以免干擾它自己對背景來電狀態的處理。
  ///
  /// ⚠️ fail-open，不是 fail-closed：只有在「讀得到資料、且資料確定是空的」
  /// 才會導去補填畫面；讀取失敗（逾時、離線、伺服器錯誤）一律視為「已完整」
  /// 直接放行——長輩連不上網路時被卡在補填畫面外面進不了 App，比資料晚一點
  /// 補嚴重得多。判斷邏輯抽到 `utils/profile_completeness.dart`（與
  /// `login_screen.dart::_handleLogin` 的家屬端檢查共用同一份定義），
  /// `ApiService.getElderProfile()` 內部已經 try/catch 過，逾時或
  /// 例外都回傳 `{'status': 'error', ...}` 而不是丟例外。
  ///
  /// ⚠️ 已知範圍限制（已回報任務協調者，需要另行決定是否派工）：只覆蓋本檔案
  /// 內的入口，不覆蓋冷啟動流程——`splash_screen.dart` 偵測到既有 session
  /// 時會直接 `ElderHomeScreen`／`ElderScreen`，不經過這裡。該檔是通話／監控
  /// 子系統最高風險檔案之一，本輪任務明確劃入不得更動的範圍，故「一直沒登出
  /// 過」的既有長輩使用者重開 App 時暫時不會被攔下來補填。
  Future<void> _goToElderHome(
      int elderId, String elderName, String elderRoom) async {
    bool profileConfirmedIncomplete = false;
    try {
      final profileResult = await ApiService.getElderProfile(elderId);
      profileConfirmedIncomplete = isProfileConfirmedIncomplete(profileResult);
    } catch (_) {
      // 理論上 ApiService.getElderProfile 不會丟到這裡，多一層保險維持 fail-open。
      profileConfirmedIncomplete = false;
    }

    if (!mounted) return;

    if (profileConfirmedIncomplete) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ElderProfileOnboardingScreen(
            userId: elderId,
            userName: elderName,
            roomId: elderRoom,
            nextScreenBuilder: (context) => ElderHomeScreen(
              userId: elderId,
              userName: elderName,
              roomId: elderRoom,
            ),
          ),
        ),
      );
      return;
    }

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


  Future<void> _requestNewCode() async {
    if (_requestingCode || _handlingPaired) return;
    _requestingCode = true;
    // 換碼期間先停掉舊碼的倒數，避免回應回來前又觸發一次自動換碼。
    _countdownTimer?.cancel();
    setState(() => _isLoading = true);
    try {
      // ★ 第五十輪任務 D：本畫面是「我是長者」首次上手（尚無帳號，由家屬
      //   掃碼時建立），是唯一該送 newElder 的呼叫點。改成顯式宣告後，
      //   其他流程若漏傳 elderId 會被後端擋下，不會再誤走這條註冊分支。
      final result = await ApiService.requestPairingCode(null, newElder: true);
      if (!mounted) return;

      // 檢查 API 是否回傳錯誤
      if (result['status'] == 'error') {
        _onCodeRequestFailed(result['detail'] ?? result['message'] ?? result['error']);
        return;
      }

      // 從 API Response 的 data 欄位取得配對碼
      final data = result['data'] as Map<String, dynamic>?;
      final code = data?['pairing_code']?.toString();
      if (code == null || code.isEmpty) {
        _onCodeRequestFailed(result.toString());
        return;
      }

      setState(() {
        _pairingCode = code;
        _secondsLeft = (data?['expires_in_seconds'] as num?)?.toInt() ?? 600;
        _isLoading = false;
      });
      _startCountdown();
      _startStatusPolling();
    } catch (e) {
      if (!mounted) return;
      _onCodeRequestFailed(e);
    } finally {
      _requestingCode = false;
    }
  }

  void _onCodeRequestFailed(Object? raw) {
    // 舊碼若已過期就不要繼續顯示一組失效的號碼。
    final expired = _secondsLeft <= 0;
    setState(() {
      _isLoading = false;
      if (expired) {
        _pairingCode = null;
        _statusTimer?.cancel();
      }
    });
    if (!expired) _startCountdown(); // 舊碼還有效：恢復倒數
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('沒辦法取得配對碼。${_friendlyError(raw)}')),
    );
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      // ★ 2026-10-06：離開畫面就收掉 timer（原本先 return 不 cancel，會一直空轉）。
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_pairingCode == null || _handlingPaired) return;
      try {
        final result = await ApiService.checkPairingStatus(_pairingCode!);
        if (!mounted) {
          timer.cancel();
          return;
        }

        // 從 API Response 的 data 欄位取得配對狀態
        final status = result['data'] as Map<String, dynamic>?;
        if (status == null) return;

        if (status['status'] == 'paired') {
          _handlingPaired = true;
          timer.cancel();
          _countdownTimer?.cancel();

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
        // ★ 2026-10-06：原本空 catch 靜默吞掉例外，但 timer 已 cancel，
        //   長輩會永遠卡在「等待配對」。配對成功後才出錯 → 重新啟動輪詢重試
        //   （後端碼仍是 paired 狀態，下一輪會再走一次寫入與導航）。
        debugPrint('⚠️ [ElderPairingDisplay] 輪詢／配對後處理失敗: $e');
        if (_handlingPaired) {
          _handlingPaired = false;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('連線有點問題，正在重試…')),
          );
          _startStatusPolling();
        }
      }
    });
  }

  /// ★ 2026-10-06 登入流程改善：手動輸入家人用「移機助手」傳來的數字登入代碼。
  /// 關閉輸入框後交給 main.dart 註冊的 [recoveryCodeHandler]，沿用 Deep Link
  /// 的復原確認對話框；掛鉤尚未註冊時提示稍後再試。
  Future<void> _enterRecoveryCode() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _RecoveryCodeDialog(),
    );
    if (!mounted || code == null || code.isEmpty) return;
    final handler = recoveryCodeHandler;
    if (handler == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暫時無法使用，請稍後再試')),
      );
      return;
    }
    handler(code);
    // handler 是同步 void：確認對話框由 main.dart 接手彈出。多撐一秒的忙碌狀態，
    // 避免在對話框出現前又連點開出第二個。
    await Future<void>.delayed(const Duration(seconds: 1));
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
    // ★ 2026-10-06：旗標在第一個 await 之前同步設定，防止連點建出兩個帳號。
    return _runExclusive('autonomous', _startAutonomousModeImpl);
  }

  Future<void> _startAutonomousModeImpl() async {
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
          throw _FriendlyFailure(_friendlyError(err));
        }
      }

      if (elderId == null) {
        throw const _FriendlyFailure('帳號建立沒有成功，請再試一次');
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

      // ★ 第五十三輪 onboard53b（長 9）：自主模式新建帳號同樣要經過完整度
      //   檢查（見 [_goToElderHome]）——新帳號多半缺年齡／居住地，正是本輪
      //   要攔的情況；讀取失敗仍 fail-open 直接放行，不卡住剛建立帳號的長輩。
      await _goToElderHome(elderId, elderName, elderRoomId);
    } catch (e) {
      if (!mounted) return;
      // ★ 2026-10-06：不再把「Exception: …」原文丟給長輩；原始錯誤只進 log。
      final msg = e is _FriendlyFailure ? e.message : _friendlyError(e);
      if (e is _FriendlyFailure) debugPrint('⚠️ [ElderPairingDisplay] 自主模式失敗: ${e.message}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('暫時無法開始使用。$msg'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 標題區：閃爍小點＋狀態＋主標
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _LiveDot(),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '正在等家人配對',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: ubanText(18, FontWeight.w700, c.brandStrong),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '請家人輸入這組號碼',
                    textAlign: TextAlign.center,
                    style: ubanH1(context),
                  ),
                  const SizedBox(height: 20),

                  // 配對碼卡片
                  UbanCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
                    child: _isLoading
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : (_pairingCode != null
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  _PairingCodeBoxes(code: _pairingCode!),
                                  const SizedBox(height: 16),
                                  // QR 碼底色固定白色，確保深色模式下仍可掃描。
                                  Container(
                                    width: 160,
                                    height: 160,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: QrImageView(
                                      data: _pairingCode!,
                                      version: QrVersions.auto,
                                      size: 140.0,
                                      backgroundColor: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    '或讓家人用手機掃這個條碼',
                                    textAlign: TextAlign.center,
                                    style: ubanBody(context),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _countdownLabel(),
                                    textAlign: TextAlign.center,
                                    style: ubanText(
                                        18,
                                        FontWeight.w700,
                                        _secondsLeft < 60 ? c.danger : c.text2),
                                  ),
                                ],
                              )
                            : Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 24),
                                child: Text(
                                  '目前沒有配對碼，請點下方「更換代碼」重試',
                                  textAlign: TextAlign.center,
                                  style: ubanBody(context),
                                ),
                              )),
                  ),
                  const SizedBox(height: 20),

                  // 🌟 方案 A：長者自主模式按鈕（極致醒目、長輩友善）
                  UbanButton(
                    label: '我自己使用',
                    size: UbanButtonSize.xl,
                    loading: _busyAction == 'autonomous',
                    onPressed: _busyAction != null ? null : _startAutonomousMode,
                  ),
                  const SizedBox(height: 12),

                  // 次要操作區（長輩端維持 60 高以上的點擊區）
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: UbanButton(
                          label: '更換代碼',
                          variant: UbanButtonVariant.tonal,
                          loading: _busyAction == 'code',
                          onPressed: (_busyAction != null || _isLoading)
                              ? null
                              : () => _runExclusive('code', _requestNewCode),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: UbanButton(
                          label: '登入上次長輩',
                          variant: UbanButtonVariant.tonal,
                          loading: _busyAction == 'quick',
                          onPressed: _busyAction != null
                              ? null
                              : () => _runExclusive('quick', _quickLoginSameElder),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // ★ 2026-10-06：家人傳來的移機連結打不開時，改手動輸入數字代碼
                  UbanButton(
                    label: '輸入家人給的登入代碼',
                    variant: UbanButtonVariant.outline,
                    loading: _busyAction == 'recovery',
                    onPressed: _busyAction != null
                        ? null
                        : () => _runExclusive('recovery', _enterRecoveryCode),
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

/// 已轉成友善中文的失敗（避免再經過一次 [_friendlyError] 的技術字樣判斷）。
class _FriendlyFailure implements Exception {
  final String message;
  const _FriendlyFailure(this.message);
  @override
  String toString() => message;
}

/// 手動輸入移機登入代碼的對話框（長輩尺規：大字、純數字、最多 10 位）。
/// 確定時以 `Navigator.pop(code)` 回傳代碼；取消回傳 null。
class _RecoveryCodeDialog extends StatefulWidget {
  const _RecoveryCodeDialog();

  @override
  State<_RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

class _RecoveryCodeDialogState extends State<_RecoveryCodeDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text('輸入登入代碼',
          style: ubanText(24, FontWeight.w800, c.text)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('家人用「移機助手」傳給您的連結裡，會有一組數字代碼',
                style: ubanText(18, FontWeight.w500, c.text2, height: 1.4)),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              style: ubanText(32, FontWeight.w700, c.text),
              decoration: const InputDecoration(hintText: '請輸入數字'),
              onSubmitted: (_) => _confirm(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: ubanText(20, FontWeight.w700, c.text2)),
        ),
        TextButton(
          onPressed: _confirm,
          child:
              Text('確定', style: ubanText(20, FontWeight.w700, c.brandStrong)),
        ),
      ],
    );
  }

  void _confirm() {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    Navigator.of(context).pop(code);
  }
}

/// 設計稿 `.livedot`：10 圓、1.6 秒呼吸閃爍。系統「移除動畫」時不閃。
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = reduceMotion(context);
    if (reduce && _started) {
      _ctrl.stop();
      _ctrl.value = 0;
      _started = false;
    } else if (!reduce && !_started) {
      _ctrl.repeat();
      _started = true;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        // blink：50% 時 opacity .3，頭尾 1。
        final t = _ctrl.value;
        final opacity = 1 - 0.7 * (1 - (t - .5).abs() * 2);
        return Opacity(
          opacity: opacity,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
          ),
        );
      },
    );
  }
}

/// 設計稿 `.code`：每碼一格（44×60、圓角 14、brandSoft 底、Poppins 34）。
/// 格寬依可用寬度縮小，6 碼在 360 寬也排得下。
class _PairingCodeBoxes extends StatelessWidget {
  final String code;
  const _PairingCodeBoxes({required this.code});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final chars = code.split('');
    return Semantics(
      label: '配對碼 ${chars.join(' ')}',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 6.0;
          final n = chars.isEmpty ? 1 : chars.length;
          final avail = constraints.maxWidth.isFinite ? constraints.maxWidth : 300.0;
          final w = ((avail - gap * (n - 1)) / n).clamp(20.0, 44.0);
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < chars.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Container(
                  width: w,
                  height: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.brandSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      chars[i],
                      maxLines: 1,
                      textScaler: TextScaler.noScaling,
                      style: ubanBrandText(34, FontWeight.w600, c.brandStrong),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
