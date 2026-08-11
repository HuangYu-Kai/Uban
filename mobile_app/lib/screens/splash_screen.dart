import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import 'dart:convert'; // ★ 2026-07-22：備援讀取 pendingAcceptedCall JSON
import 'dart:async'; // ★ 2026-08-05 第十八輪：衝刺通道背景角色校正需要 unawaited
import '../services/api_service.dart';
import 'identification_screen.dart';
import 'family_onboarding_screen.dart';
import 'elder_home_screen.dart';
import 'family_main_screen.dart';
import '../globals.dart'; // ★ 新增
import 'elder_screen.dart'; // ★ 新增
import 'video_call_screen.dart'; // ★ 2026-07-19：家屬冷啟動待接聽來電直接進視訊房
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart'; // ★ 2026-07-23：splash activeCalls 輪詢

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const bool _devBypassLogin = bool.fromEnvironment(
    'DEV_BYPASS_LOGIN',
    defaultValue: false,
  );
  static const String _devBypassRole = String.fromEnvironment(
    'DEV_BYPASS_ROLE',
    defaultValue: '',
  );
  static const int _devBypassUserId = int.fromEnvironment(
    'DEV_BYPASS_USER_ID',
    defaultValue: 0,
  );
  static const String _devBypassUserName = String.fromEnvironment(
    'DEV_BYPASS_USER_NAME',
    defaultValue: '測試使用者',
  );

  bool _fadedOut = false;

  /// ★ 2026-08-11 第二十一輪（需求 4）：導航看門狗。
  ///
  /// `_navigateToNext()` 整條路徑上有多個 platform channel / 網路 await，
  /// 任何一個「不回來」（不是丟例外，是卡住）都會讓 Splash 永遠停在原地——
  /// 而 `_fadedOut` 一旦被設為 true，畫面就是一片近乎純白、沒有動畫、
  /// 也沒有任何可操作元件，正是使用者回報的症狀。
  /// `_navigated` 讓所有導航點彼此互斥（看門狗與標準流程可能同時抵達），
  /// `_navWatchdog` 則保證「無論如何」都會離開 Splash。
  bool _navigated = false;
  Timer? _navWatchdog;

  /// ★ 2026-08-11 第二十一輪（需求 4）：開機比預期慢時，讓畫面「看得出來還活著」。
  /// 開場動畫在 3.2s 淡出，但後面的 getStatus／activeCalls 輪詢最長可能再花數秒，
  /// 這段空窗期原本是一片什麼都沒有的淺色底——正是使用者說的「白屏」。
  bool _slowBoot = false;
  Timer? _slowBootTimer;

  @override
  void initState() {
    super.initState();
    splashActive = true; // ★ 2026-07-19：宣告冷啟動導航由 Splash 擁有
    _playAnimations();
    _navigateToNext();

    // ★ 2026-08-11 第二十一輪（需求 4）：15 秒是「標準流程最慢也該走完」的上限
    //   （getStatus 逾時 6s + activeCalls 輪詢 4s + 動畫 4s 都在其內）。
    _navWatchdog = Timer(const Duration(seconds: 15), () {
      if (!mounted || _navigated) return;
      debugPrint('⏰ [Splash] 15 秒仍停在開場畫面，看門狗強制決定去向');
      _goNextOrRestoreElder();
    });

    // 5 秒後仍在 Splash 就顯示載入指示（正常路徑約 4 秒就導航完，看不到）
    _slowBootTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _navigated) return;
      setState(() => _slowBoot = true);
    });
  }

  @override
  void dispose() {
    _navWatchdog?.cancel();
    _slowBootTimer?.cancel();
    splashActive = false;
    super.dispose();
  }

  /// ★ 2026-08-11 第二十一輪（需求 4）：離開 Splash 的統一入口。
  /// 回傳 true 表示本次呼叫確實完成了導航；false 表示已經有人先導航過了
  /// （或 widget 已卸載），呼叫端不需要再做任何事。
  bool _replaceWith(Widget page) {
    if (!mounted || _navigated) return false;
    _navigated = true;
    _navWatchdog?.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
    return true;
  }

  /// ★ 2026-08-11 第二十一輪（需求 4）：待接聽來電被「記憶體」接手後，
  /// 清掉 prefs 裡的那份副本。
  ///
  /// main.dart 刻意保留這三個鍵給 Splash 備援重讀（見該處註解「保留給
  /// splash_screen 備援讀取」），但通話結束時**沒有任何路徑**會移除它們——
  /// 只有拒接／取消會清。於是一通正常接起、正常結束的通話會在 prefs 裡
  /// 留下殘骸，之後每一次冷啟動都被重新載入 → 每次都跳過開場動畫、
  /// 每次都被導向一通早就不存在的通話。
  Future<void> _clearPendingCallPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      await prefs.remove('pendingAcceptedCall');
      await prefs.remove('pendingRingCallData');
      await prefs.remove('pendingRingCall');
    } catch (e) {
      debugPrint('⚠️ [Splash] 清除待接聽來電 prefs 失敗: $e');
    }
  }

  Future<void> _playAnimations() async {
    // 整個液態擴散動畫放慢至 3.2s
    await Future.delayed(const Duration(milliseconds: 3200));
    
    // 3.2s 開始全局淡出 (歷時 0.8s)
    if (mounted) setState(() => _fadedOut = true);
  }

  Future<void> _navigateToNext() async {
    try {
      // ★ 2026-08-05 第十八輪（需求 2）：冷啟動衝刺通道。
      //   被殺死後從 CallKit 接聽時，main() 已在 runApp 前把 pendingAcceptedCall
      //   填好；此時再等 `ApiService.getStatus`（無逾時的網路往返）與
      //   `_pollActiveCallsForAccepted`（含 500ms 延遲的輪詢）純屬浪費，
      //   使用者實測「跳回視訊房間過久」就是卡在這兩段。
      //   這裡改用本機 prefs（第十六輪起 user_role/saved_role 已由 splash 寫回，
      //   是可信來源）直接導航，角色校正改為背景不阻塞執行。
      if (pendingAcceptedCall.value != null) {
        // ★ 2026-08-11 第二十一輪（需求 4）：記憶體已經拿到這通待接聽來電了，
        //   prefs 的副本就完成任務了，在此清掉（理由見 _clearPendingCallPrefs）。
        unawaited(_clearPendingCallPrefs());
        // ★ 2026-08-11 第二十一輪（需求 4）：**不再**在這裡就把動畫關掉。
        //   `_sprintToPendingCall()` 成功時會立刻 pushReplacement，Splash 本來
        //   就會被換掉，先淡出沒有意義；失敗時（本機 session 不完整）卻會留下
        //   一個全白、不會動的畫面陪使用者走完後面整段標準流程。
        final bool sprinted = await _sprintToPendingCall();
        if (sprinted) return;
        debugPrint('⚠️ [Splash] 衝刺通道條件不足，回退標準流程');
      }

      // 若有待接聽的緊急通話，直接跳過開機動畫以加速進入視訊房間
      if (pendingAcceptedCall.value == null) {
        await Future.delayed(const Duration(milliseconds: 4000));
      } else {
        debugPrint("🚨 [Splash] 檢測到待接聽來電，跳過開機動畫延遲");
        // ★ 2026-08-11 第二十一輪（需求 4）：同樣移除這裡的強制淡出。
        //   要加速的是「不要再等 4 秒」（上面的 if 已經做到），不是「把畫面清空」。
        //   底下還有 getStatus（最長 6s）與 activeCalls 輪詢（最長 4s），
        //   先淡出只會讓這段期間變成一片空白。動畫留著，導航一到就自然被取代。
      }
      if (!mounted) return;

      // 嘗試獲取登入狀態（已移除 2 秒 .timeout，避免冷啟動 SharedPreferences
      // 初始化 + 磁碟讀取超過 2 秒 → 拋例外 → 誤跳身分頁，讓已登入長輩看似 session 遺失）
      // ★ 2026-08-11 第二十一輪（需求 4）：加逾時。刻意**不**改變原本「不因逾時
      //   誤跳身分頁」的設計——逾時會落到最外層 catch，由 `_goNextOrRestoreElder`
      //   重讀 prefs 決定去向。
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;

      final int? userId = prefs.getInt('caregiver_id');
      final String? userName = prefs.getString('caregiver_name');

      // 開發便捷模式：若本機登入資料遺失，可由 dart-define 自動回填，避免每次重跑都要重新配對
      if (_devBypassLogin && (userId == null || userName == null)) {
        if (_devBypassUserId > 0 && _devBypassRole.isNotEmpty) {
          await prefs.setInt('caregiver_id', _devBypassUserId);
          await prefs.setString('caregiver_name', _devBypassUserName);
          await prefs.setString('user_role', _devBypassRole);
          if (!mounted) return;
        }
      }

      final int? effectiveUserId = prefs.getInt('caregiver_id');
      final String? effectiveUserName = prefs.getString('caregiver_name');
      final String? effectiveLocalRole = prefs.getString('user_role');

      // ★ Issue 3 診斷 log：記錄本機 session 三個關鍵欄位，用於區分「session 真的遺失」
      //   還是「短暫讀取異常造成的假性遺失」。
      debugPrint(
          '🔎 [Splash] _navigateToNext prefs 快照: caregiver_id=$effectiveUserId, caregiver_name=$effectiveUserName, user_role=$effectiveLocalRole');

      // ★ issue 2：先以本機紀錄的角色預先設置全域 appRole，
      //   避免在等待 API 回應期間（例如冷啟動時 CallKit 的接聽事件搶先觸發），
      //   main.dart 的 _navigateToVideoCall 因 appRole 仍是 null 而誤判為家屬端，
      //   導致長輩端被推到錯誤的 VideoCallScreen。下方 API 成功後會再次校正。
      if (effectiveLocalRole != null) {
        appRole = effectiveLocalRole;
      }

      if (effectiveUserId != null && effectiveUserName != null) {
        // 先嘗試獲取當前使用者資訊，以驗證連線與角色
        try {
          // ★ 2026-08-05 第十八輪（需求 2）：加上逾時上限。
          //   逾時會落入下方既有的 catch，由本機 prefs 決定去向（見下方
          //   catch 區塊與 _goNextOrRestoreElder），不會把已登入長輩丟回身分頁。
          //   6 秒遠高於正常延遲，僅用於封住「網路半死」時無限等待導致的
          //   冷啟動卡頓。
          final userProfile = await ApiService.getStatus(effectiveUserId)
              .timeout(const Duration(seconds: 6));
          if (!mounted) return;
          
          final profileData = userProfile['data'] as Map<String, dynamic>? ?? {};
          final role = profileData['role'] ?? effectiveLocalRole ?? 'family';
          appRole = role; // ★ 新增：同步到全域變數，確保啟動後通話偵聽正常

          // ★ 2026-08-05 第十六輪：校正結果必須**寫回 prefs**，不能只改記憶體全域。
          //   `_firebaseMessagingBackgroundHandler` 是獨立 isolate，看不到 appRole，
          //   只能讀 prefs 的 `user_role ?? saved_role`（main.dart:164）來決定
          //   走長輩的 CallKit 分支（`role == 'elder'`）還是家屬分支。
          //   在此之前，splash 每次冷啟動都只把前景的 appRole 修好，prefs 內的
          //   殘留角色（例如這台手機曾登入過家屬帳號留下的 user_role='family'）
          //   永遠沒被更新 → 長輩端在**背景／被殺死**時整條來電分支不成立，
          //   來電無聲消失；而長輩撥出時 role 是明確傳入的，不讀此鍵，
          //   所以長輩→家屬照常 —— 正是回報的「不對稱失效」。
          //   API 的 role 是權威來源，兩個鍵一起寫以免再次分歧。
          final String roleStr = role.toString();
          if (roleStr.isNotEmpty && roleStr != effectiveLocalRole) {
            await prefs.setString('user_role', roleStr);
            await prefs.setString('saved_role', roleStr);
            debugPrint('🧭 [Splash] 角色校正並寫回 prefs: $effectiveLocalRole → $role'
                '（背景 isolate 之後才能正確判斷來電分支）');
          }

          if (role == 'elder') {
            final String? apiElderId = profileData['elder_id']?.toString();
            if (apiElderId != null) {
              await prefs.setString('elder_room_id', apiElderId);
              if (!mounted) return;
            }

            final bool isCCTV = prefs.getBool('saved_is_cctv') ?? false;
            final String deviceName = prefs.getString('saved_device_name') ?? effectiveUserName;
            final String elderRoomId = apiElderId ?? prefs.getString('elder_room_id') ?? effectiveUserId.toString();

            // ★ 2026-07-23 Splash 主動輪詢：在動畫播放期間（約 4 秒），每隔 500ms
            //   檢查 FlutterCallkitIncoming.activeCalls() 是否有 isAccepted=true
            //   的通話。這是「冷啟動時 BG isolate 已死、CallKit accept 事件遺失」
            //   情境下的唯一可行偵測手段——foreground service 在 BG handler 死後
            //   仍存活，且使用者接聽後會更新內部狀態。
            //   先於 SharedPreferences 備援執行（若 service 存活，比 prefs 更快捕捉）。
            final bool foundByActiveCallsPoll = await _pollActiveCallsForAccepted(
              elderRoomId, deviceName, effectiveUserId, effectiveUserName, isCCTV);
            if (foundByActiveCallsPoll) return; // 已導航至 ElderScreen，中止後續流程

            // ★ 2026-07-22 最終防線：若 pendingAcceptedCall.value 仍為 null，
            //   直接重讀 SharedPreferences（此時 API 呼叫已給足時間讓 BG isolate
            //   的寫入完成），重建 pendingAcceptedCall。
            if (pendingAcceptedCall.value == null) {
              // ★ 強制從磁碟重新載入，確保讀到 BG isolate 在冷啟動期間的延遲寫入
              await prefs.reload();
              final String? rawPending = prefs.getString('pendingAcceptedCall');
              if (rawPending != null) {
                try {
                  final Map<String, dynamic> decoded = jsonDecode(rawPending);
                  final int? ts = int.tryParse('${decoded['timestamp'] ?? ''}');
                  if (ts == null || (DateTime.now().millisecondsSinceEpoch - ts) <= 120000) {
                    pendingAcceptedCall.value = decoded.map(
                      (key, value) => MapEntry(key, value?.toString()),
                    );
                    debugPrint('🚨 [Splash] 最後防線：從 SharedPreferences 重建 pendingAcceptedCall');
                  }
                } catch (_) {}
              }
              if (pendingAcceptedCall.value == null) {
                final String? rawRing = prefs.getString('pendingRingCallData');
                if (rawRing != null) {
                  try {
                    final Map<String, dynamic> data = jsonDecode(rawRing);
                    if (data['isAccepted'] == true) {
                      final int? ts = int.tryParse('${data['timestamp'] ?? ''}');
                      if (ts == null || (DateTime.now().millisecondsSinceEpoch - ts) <= 120000) {
                        pendingAcceptedCall.value = data.map(
                          (key, value) => MapEntry(key, value?.toString()),
                        );
                        debugPrint('🚨 [Splash] 最後防線 II：從 pendingRingCallData (isAccepted:true) 重建 pending');
                      }
                    }
                  } catch (_) {}
                }
              }
              // 清除以避免下次冷啟動誤判
              await prefs.remove('pendingAcceptedCall');
              await prefs.remove('pendingRingCallData');
              await prefs.remove('pendingRingCall');
            }

            _replaceWith(_resolveElderDestination(
              isCCTV: isCCTV,
              deviceName: deviceName,
              elderRoomId: elderRoomId,
              effectiveUserId: effectiveUserId,
              effectiveUserName: effectiveUserName,
            ));
            return;
          }

          // 子女端邏輯：直接進入主要儀表板容器
          // ★ 2026-08-11 第二十一輪（需求 4）：這是家屬端開機路徑上**唯一**沒有
          //   逾時的網路往返。後端半死（TCP 連上但不回應）時它會永遠不回來，
          //   而下方的 catch 攔得到例外、攔不到卡住 → 家屬端永久停在開場畫面。
          //   逾時後落入 catch → `_goNextOrRestoreElder()` 依本機 session 還原。
          final elders = await ApiService.getPairedElders(effectiveUserId)
              .timeout(const Duration(seconds: 6));
          if (!mounted) return;

          if (elders.isNotEmpty) {
            // 已有長輩，進入主介面
            _navigateFamilyHome(effectiveUserId, effectiveUserName);
          } else {
            // 未綁定任何長輩，進入引導頁
            _replaceWith(FamilyOnboardingScreen(
              userId: effectiveUserId,
              userName: effectiveUserName,
            ));
          }
        } catch (e) {
          // 若 API 失敗，使用本地紀錄決定跳轉
          if (mounted) {
            if (effectiveLocalRole == 'elder') {
              final bool isCCTV = prefs.getBool('saved_is_cctv') ?? false;
              final String deviceName = prefs.getString('saved_device_name') ?? effectiveUserName;
              final String elderRoomId = prefs.getString('elder_room_id') ?? effectiveUserId.toString();

              _replaceWith(_resolveElderDestination(
                isCCTV: isCCTV,
                deviceName: deviceName,
                elderRoomId: elderRoomId,
                effectiveUserId: effectiveUserId,
                effectiveUserName: effectiveUserName,
              ));
            } else {
              // ★ Issue 3 硬化：effectiveLocalRole 只是進入本函式當下的快照，
              //   API 失敗不代表本機真的不是長輩帳號；改由 _goNextOrRestoreElder
              //   重讀 prefs 二次確認，避免暫時性失敗把已登入長輩丟到身分頁。
              await _goNextOrRestoreElder();
            }
          }
        }
      } else {
        // 未登入，進入身分辨識頁
        // ★ Issue 3 硬化：effectiveUserId/effectiveUserName 可能只是短暫讀取異常
        //   造成的假性 null，先由 _goNextOrRestoreElder 重讀一次 prefs 再決定。
        await _goNextOrRestoreElder();
      }
    } catch (e) {
      // 若發生任何錯誤 (如 SharedPreferences 失敗)，確保能進入身分選擇頁
      debugPrint('Splash error: $e');
      // ★ Issue 3 硬化：任何例外都先嘗試重讀 prefs 判斷是否為已登入長輩，
      //   絕不能因為一次例外就把已登入長輩導回身分辨識頁。
      if (mounted) await _goNextOrRestoreElder();
    }
  }

  /// ★ 2026-08-05 第十八輪（需求 2）：已知使用者接聽時的最短路徑導航。
  ///
  /// 回傳 true 表示已導航（呼叫端必須立即 return）；回傳 false 表示本機資料
  /// 不足以判斷去向，交還給標準流程處理。
  ///
  /// 刻意**不呼叫任何 API**：此路徑的唯一目標是把使用者用最短時間送進通話畫面。
  /// 角色校正（第十六輪的 prefs 寫回）改以背景工作進行，不阻塞導航。
  Future<bool> _sprintToPendingCall() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      final int? uid = prefs.getInt('caregiver_id');
      final String? uname = prefs.getString('caregiver_name');
      final String? localRole =
          prefs.getString('user_role') ?? prefs.getString('saved_role');

      if (uid == null || uname == null || localRole == null || localRole.isEmpty) {
        return false; // 本機 session 不完整，交回標準流程（它有多層兜底）
      }

      appRole = localRole;

      // 背景校正角色（不 await，不影響導航速度）
      _refreshRoleInBackground(uid, localRole);

      if (!mounted) return false;

      if (localRole == 'elder') {
        final bool isCCTV = prefs.getBool('saved_is_cctv') ?? false;
        final String deviceName = prefs.getString('saved_device_name') ?? uname;
        final String elderRoomId =
            prefs.getString('elder_room_id') ?? uid.toString();

        debugPrint(
            '🚀 [Splash] 衝刺通道：長輩端直接進入通話畫面 (room=$elderRoomId, cctv=$isCCTV)');
        _replaceWith(_resolveElderDestination(
          isCCTV: isCCTV,
          deviceName: deviceName,
          elderRoomId: elderRoomId,
          effectiveUserId: uid,
          effectiveUserName: uname,
        ));
        return true;
      }

      // 家屬端：_navigateFamilyHome 內部會自行檢查 pendingAcceptedCall，
      // 在疊上主畫面後直接 push VideoCallScreen，不需要額外處理。
      debugPrint('🚀 [Splash] 衝刺通道：家屬端直接進入主畫面並疊上待接聽通話');
      _navigateFamilyHome(uid, uname);
      return true;
    } catch (e) {
      debugPrint('⚠️ [Splash] 衝刺通道失敗，回退標準流程: $e');
      return false;
    }
  }

  /// ★ 2026-08-05 第十八輪：衝刺通道用的背景角色校正。
  /// 維持第十六輪護欄「API 的 role 是權威來源，user_role 與 saved_role 必須一起寫回」，
  /// 只是把它從導航關鍵路徑移到背景，避免拖慢進房。
  void _refreshRoleInBackground(int userId, String localRole) {
    unawaited(() async {
      try {
        final profile = await ApiService.getStatus(userId);
        final data = profile['data'] as Map<String, dynamic>? ?? {};
        final String roleStr = (data['role'] ?? '').toString();
        if (roleStr.isEmpty || roleStr == localRole) return;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_role', roleStr);
        await prefs.setString('saved_role', roleStr);
        debugPrint('🧭 [Splash] 背景角色校正並寫回 prefs: $localRole → $roleStr');
      } catch (e) {
        debugPrint('⚠️ [Splash] 背景角色校正失敗（不影響本次導航）: $e');
      }
    }());
  }

  void _goNext() {
    _replaceWith(const IdentificationScreen());
  }

  /// ★ Issue 3 硬化：在導向身分辨識頁（_goNext）之前的最後防線。
  /// API 失敗或 prefs 短暫讀取異常，不代表本機真的沒有已登入的長輩 session。
  /// 這裡「重新」讀一次 SharedPreferences（不沿用外層可能已經是舊快照的區域變數），
  /// 只要看起來像長輩 session（user_role 直接是 'elder'；或 user_role 欄位本身缺漏
  /// 但 caregiver_id/caregiver_name 都還在，視為寫入未完成的邊界情況也保守當作長輩），
  /// 就一律導向長輩主畫面，絕不因暫時性失敗把已登入長輩丟回身分頁。
  /// ★ 2026-08-10 第二十輪：家屬 session（user_role == 'family' 且 caregiver_id 尚在）
  /// 同樣還原，理由見函式內註解——身分頁現在會主動釋放 session。
  Future<void> _goNextOrRestoreElder() async {
    try {
      // ★ 2026-08-11 第二十一輪（需求 4）：這是看門狗最後的落腳處，
      //   絕不能自己也卡住——逾時就往下走到 `_goNext()`（身分辨識頁）。
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      final int? uid = prefs.getInt('caregiver_id');
      final String? uname = prefs.getString('caregiver_name');
      final String? role = prefs.getString('user_role');

      debugPrint(
          '🛟 [Splash] _goNextOrRestoreElder 重讀 prefs: caregiver_id=$uid, caregiver_name=$uname, user_role=$role');

      // ★ 2026-08-10 第二十輪（需求 1）：移除 role == null 的推測性分支。
      //   使用者若已登出，prefs 只剩殘值時不該被猜成長輩 session 而跳過身分選擇頁。
      final bool looksLikeElderSession = role == 'elder';

      if (looksLikeElderSession && mounted) {
        final bool isCCTV = prefs.getBool('saved_is_cctv') ?? false;
        final String deviceName =
            prefs.getString('saved_device_name') ?? uname ?? '長輩';
        final String elderRoomId =
            prefs.getString('elder_room_id') ?? uid?.toString() ?? '0';

        debugPrint('🛡️ [Splash] 偵測到本機長輩 session，改導向長輩主畫面而非身分頁');

        _replaceWith(_resolveElderDestination(
          isCCTV: isCCTV,
          deviceName: deviceName,
          elderRoomId: elderRoomId,
          effectiveUserId: uid ?? 0,
          effectiveUserName: uname ?? deviceName,
        ));
        return;
      }

      // ★ 2026-08-10 第二十輪（需求 1 的必要配套）：家屬 session 也要還原。
      //   需求 1 讓身分選擇頁一進去就釋放 session（IdentificationScreen.initState
      //   → SessionManager.releaseIfBound()），這對「使用者主動回到身分頁」是對的，
      //   但本函式是**暫時性失敗**的兜底路徑——`getPairedElders()` 一噴錯（斷網、
      //   後端重啟、Funnel 抖動）家屬就會被送到這裡，過去只是看到身分頁、重登即可，
      //   現在卻會連帶把有效的家屬 session 一併清掉。
      //   對稱補上家屬分支：暫時性失敗一律還原既有 session，只有使用者**自己**
      //   走到身分頁才算真正要換身分。
      final bool looksLikeFamilySession = role == 'family' && uid != null;
      if (looksLikeFamilySession && mounted) {
        debugPrint('🛡️ [Splash] 偵測到本機家屬 session，改導向家屬主畫面而非身分頁');
        _navigateFamilyHome(uid, uname ?? '家屬');
        return;
      }
    } catch (e) {
      debugPrint('⚠️ [Splash] _goNextOrRestoreElder 重讀 prefs 失敗: $e');
    }
    if (mounted) _goNext();
  }

  /// ★ issue 2/10：決定長輩端啟動後要進入哪個畫面。
  /// 在等待 SharedPreferences/API 期間，若收到待接聽的來電（一般或緊急），
  /// `pendingAcceptedCall` 會被填入。此處在「導航當下」重新檢查一次，
  /// 若有待接聽來電則直接跳過長輩主畫面，進入 ElderScreen 並帶上通話資料，
  /// 模擬「像緊急來電一樣直接進入視訊房間」的需求。
  /// ★ 2026-07-19 修復：家屬端冷啟動接聽後，先 pushReplacement 到主畫面，
  /// 若有待接聽來電再「疊上」VideoCallScreen。
  ///
  /// 原本 Splash 家屬分支不消費 pendingAcceptedCall，導致：
  ///   1) main.dart 在 350ms 把 VideoCallScreen push 到 Splash 之上；
  ///   2) Splash 動畫結束 pushReplacement(FamilyMainScreen) 取代「最上層」，
  ///      正好把那個 VideoCallScreen 洗掉 → 使用者只看到家屬主畫面。
  /// 這裡改為由 Splash 確定性地先建主畫面、再疊 VideoCallScreen，杜絕競態。
  void _navigateFamilyHome(int effectiveUserId, String effectiveUserName) {
    // ★ 2026-08-11 第二十一輪（需求 4）：與 `_replaceWith` 共用同一把互斥鎖。
    //   本函式是「pushReplacement + 視情況再 push」的組合，不能走 _replaceWith，
    //   但同樣必須確保只會發生一次（看門狗與標準流程可能同時抵達）。
    if (!mounted || _navigated) return;
    _navigated = true;
    _navWatchdog?.cancel();
    Map<String, String?>? pending = pendingAcceptedCall.value;
    // ★ 2026-07-22 第八輪 Fix 3：角色反轉來電視為無效，直接丟棄。
    if (pending != null && _isPendingRoleReversed(pending)) {
      debugPrint("🚫 [Splash] 家屬冷啟動忽略角色反轉來電 (senderRole=${pending['senderRole']})");
      pendingAcceptedCall.value = null;
      pending = null;
    }
    final bool hasPending = pending != null &&
        (pending['roomId']?.isNotEmpty ?? false) &&
        (pending['senderId']?.isNotEmpty ?? false) &&
        !_isPendingExpired(pending);

    // 取用 NavigatorState（跨 route 置換仍穩定），避免 pushReplacement 後
    // 使用已失效的 Splash context 再 push 而拋例外。
    final navigator = Navigator.of(context);

    // 先確定性地把主畫面設為堆疊底部（取代 Splash）
    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (context) => FamilyMainScreen(
          userId: effectiveUserId,
          userName: effectiveUserName,
        ),
      ),
    );

    if (hasPending) {
      pendingAcceptedCall.value = null; // 消費，避免 FamilyMainScreen 再處理一次
      debugPrint("🚨 [Splash] 家屬冷啟動偵測到待接聽來電，疊上 VideoCallScreen");
      navigator.push(
        MaterialPageRoute(
          builder: (context) => VideoCallScreen(
            roomId: pending!['roomId']!,
            targetSocketId: pending['senderId']!,
            isIncomingCall: true,
            callId: pending['callId'],
            isVideoCall: parseIsVideoCall(pending['isVideoCall']), // ★ 2026-08-02 第十四輪修正
          ),
        ),
      );
    }
  }

  bool _isPendingExpired(Map<String, String?> pending) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int? expiresAt = int.tryParse('${pending['expiresAt'] ?? ''}');
    if (expiresAt != null && now > expiresAt) return true;
    final int? issuedAt = int.tryParse('${pending['issuedAt'] ?? ''}');
    if (issuedAt != null && (now - issuedAt) > kCallValidityMs) return true;
    return false;
  }

  /// ★ 2026-07-22 第八輪 Fix 3：防角色反轉。senderRole 為發起方角色，
  /// 本機只應接聽「對方角色」發起的來電。若 senderRole == appRole，
  /// 代表這是自身角色發出、經 stale state 回流的假來電 → 視為無效。
  bool _isPendingRoleReversed(Map<String, String?> pending) {
    final String? senderRole = pending['senderRole'];
    return senderRole != null &&
        senderRole.isNotEmpty &&
        appRole != null &&
        senderRole == appRole;
  }

  /// ★ 2026-07-23 Splash 動畫期間輪詢 FlutterCallkitIncoming.activeCalls()。
  /// 約 4 秒內每 500ms 檢查一次（最多 8 次），尋找 isAccepted=true 的通話。
  /// 找到後直接 pushReplacement 到 ElderScreen 並回傳 true。
  /// 注意：依賴 native foreground service 在 BG handler 死後仍存活。
  Future<bool> _pollActiveCallsForAccepted(
    String elderRoomId,
    String deviceName,
    int effectiveUserId,
    String effectiveUserName,
    bool isCCTV,
  ) async {
    const int maxPolls = 8; // 8 × 500ms = 4s
    for (int i = 0; i < maxPolls; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return false;
      // 若 pending 已被其他路徑（如 SharedPreferences 備援、_setupCallKitListener）
      // 設定，停止輪詢以免覆蓋正確資料。
      if (pendingAcceptedCall.value != null) return false;
      try {
        // ★ 2026-08-11 第二十一輪（需求 4）：加逾時。輪詢次數雖有上限，
        //   但單次 `activeCalls()` 是 platform channel，原生層卡住就整個流程停擺
        //   （外層 `catch (_)` 攔得到例外、攔不到卡住）。
        final activeCalls = await FlutterCallkitIncoming.activeCalls()
            .timeout(const Duration(seconds: 2));
        if (activeCalls is! List || activeCalls.isEmpty) continue;
        for (final call in activeCalls) {
          if (call is! Map) continue;
          if (call['isAccepted'] != true) continue;
          final extra = call['extra'];
          if (extra is! Map) continue;
          final String roomId = (extra['roomId'] ?? '').toString();
          final String senderId = (extra['senderId'] ?? '').toString();
          final String? callId = extra['callId']?.toString();
          final String? issuedAt = extra['issuedAt']?.toString();
          final String? expiresAt = extra['expiresAt']?.toString();
          final String? senderRole = extra['senderRole']?.toString();
          if (roomId.isEmpty || senderId.isEmpty) continue;

          // 過期驗證
          final int now = DateTime.now().millisecondsSinceEpoch;
          final int? exp = int.tryParse(expiresAt ?? '');
          final int? issued = int.tryParse(issuedAt ?? '');
          if ((exp != null && now > exp) ||
              (issued != null && (now - issued) > kCallValidityMs)) {
            debugPrint("⏰ [SplashPoll] activeCalls 找到已接聽但過期，忽略");
            FlutterCallkitIncoming.endAllCalls();
            continue;
          }

          // 防角色反轉
          if (senderRole != null &&
              senderRole.isNotEmpty &&
              senderRole == appRole) {
            debugPrint(
                "🚫 [SplashPoll] 忽略角色反轉來電 (senderRole=$senderRole)");
            continue;
          }

          debugPrint(
              "🚨 [SplashPoll] activeCalls 偵測到已接聽 (callId=$callId)，直接導向 ElderScreen");
          pendingAcceptedCall.value = <String, String?>{
            'roomId': roomId,
            'senderId': senderId,
            'callId': callId,
            'issuedAt': issuedAt,
            'expiresAt': expiresAt,
            'senderRole': senderRole,
          };
          // 直接導航（不等待 4s 動畫）
          _replaceWith(ElderScreen(
            roomId: roomId,
            deviceName: deviceName,
            initialCallData: pendingAcceptedCall.value,
          ));
          return true;
        }
      } catch (_) {
        // activeCalls() 偶發失敗（native channel 尚未就緒），繼續重試
      }
    }
    return false;
  }

  Widget _resolveElderDestination({
    required bool isCCTV,
    required String deviceName,
    required String elderRoomId,
    required int effectiveUserId,
    required String effectiveUserName,
  }) {
    final pending = pendingAcceptedCall.value;
    if (pending != null && !isCCTV && _isPendingRoleReversed(pending)) {
      debugPrint("🚫 [Splash] 長輩冷啟動忽略角色反轉來電 (senderRole=${pending['senderRole']})");
      pendingAcceptedCall.value = null;
    } else if (pending != null && !isCCTV) {
      pendingAcceptedCall.value = null; // 消費掉，避免主畫面重複處理
      debugPrint("🚨 [Splash] 偵測到待接聽來電，直接進入 ElderScreen");
      return ElderScreen(
        roomId: pending['roomId'] ?? elderRoomId,
        deviceName: deviceName,
        initialCallData: pending,
      );
    }

    if (isCCTV) {
      return ElderScreen(
        roomId: elderRoomId,
        isCCTVMode: true,
        deviceName: deviceName,
      );
    }

    return ElderHomeScreen(
      userId: effectiveUserId,
      userName: effectiveUserName,
      roomId: elderRoomId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // 介面的預設淺色底
      body: Stack(
        children: [
          // ★ 2026-08-11 第二十一輪（需求 4）：開機異常緩慢時的「還活著」指示。
          //   刻意放在動畫**下層**（Stack 先畫者在底），動畫還不透明時完全看不到，
          //   只有在 `_fadedOut` 之後、導航卻還沒發生的那段空窗才會露出來——
          //   這正是使用者回報「白屏、既無動畫也不跳轉」時看到的畫面。
          //   正常路徑（動畫結束即導航）根本不會顯示。
          if (_slowBoot)
            const Center(
              child: SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF59B294)),
                ),
              ),
            ),
          _buildIntroAnimation(),
        ],
      ),
    );
  }

  Widget _buildIntroAnimation() {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _fadedOut ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 1000), // 圖標和背景平滑淡出的歷時
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 3200), // 總時長放慢
          curve: Curves.linear,
          builder: (context, time, child) {
            // 前 800 毫秒(約 time 0.0~0.25)安靜停頓，隨後開啟 2.4 秒的極柔和緩慢擴散
            double fillProgress = ((time - 0.25) / 0.75).clamp(0.0, 1.0);
            
            // 使用 easeOutQuart 讓一開始有平滑的加速推力，然後悠長地滑行至邊界，不會有瞬間爆炸的急促感
            double easedProgress = Curves.easeOutQuart.transform(fillProgress);

            final textStyle = GoogleFonts.poppins(
              fontSize: 78,
              fontWeight: FontWeight.w600, // 溫潤、乾淨的科技新創字體
              letterSpacing: 2.0,
            );

            return Stack(
              children: [
                // 底層：原本的白底綠字 (靜止狀態等待水花漫過)
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.white,
                  child: Center(
                    child: Text(
                      'Uban',
                      style: textStyle.copyWith(color: const Color(0xFF59B294)),
                    ),
                  ),
                ),
                
                // 頂層：水花漫過的有機擴散綠底白字
                ClipPath(
                  clipper: BlobRevealClipper(easedProgress),
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: const Color(0xFF59B294),
                    child: Center(
                      child: Text(
                        'Uban',
                        style: textStyle.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
        ),
      ),
    );
  }
}

// 產生「水滴擴散」帶有非對稱、有機流體邊緣的自定義波紋
class BlobRevealClipper extends CustomClipper<Path> {
  final double progress; // 0.0 到 1.0 的液體擴散進度
  BlobRevealClipper(this.progress);

  @override
  Path getClip(Size size) {
    if (progress <= 0) return Path();

    final center = Offset(size.width / 2, size.height / 2);
    // 預設最大半徑為對角線長度
    final maxRadius = math.sqrt(size.width * size.width + size.height * size.height);
    // 放大擴散圈倍率 (1.2)，確保算上不規則波動的「波谷」時，也能完全覆蓋到長方形螢幕的最角落
    final currentRadius = maxRadius * progress * 1.2;
    
    Path path = Path();
    int points = 180; // 高密度描點確保液態邊緣極其圓滑
    
    // 波動振幅：擴散越大，水波的起伏感越自然，但適度收斂
    double amplitude = maxRadius * 0.08 * progress; 

    for (int i = 0; i <= points; i++) {
      double angle = (i / points) * 2 * math.pi;
      
      // 使用三層傅立葉干涉 (Sin/Cos) 創造有機、隨機的液滴邊緣
      // 其中動態加入 progress 的相位偏移，讓「水波在向外推的過程中，邊緣形狀也在流動改變」
      double noise = math.sin(angle * 3) * amplitude * 0.7 +
                     math.cos(angle * 5 - progress * 6.0) * amplitude * 0.5 +
                     math.sin(angle * 7 + progress * 4.0) * amplitude * 0.3;
                     
      double r = currentRadius + noise;
      if (r < 0) r = 0; // 防呆
      
      double x = center.dx + r * math.cos(angle);
      double y = center.dy + r * math.sin(angle);
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    
    return path;
  }

  @override
  bool shouldReclip(covariant BlobRevealClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}


