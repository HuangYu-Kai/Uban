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

  @override
  void initState() {
    super.initState();
    splashActive = true; // ★ 2026-07-19：宣告冷啟動導航由 Splash 擁有
    _playAnimations();
    _navigateToNext();
  }

  @override
  void dispose() {
    splashActive = false;
    super.dispose();
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
        if (mounted) setState(() => _fadedOut = true);
        final bool sprinted = await _sprintToPendingCall();
        if (sprinted) return;
        debugPrint('⚠️ [Splash] 衝刺通道條件不足，回退標準流程');
      }

      // 若有待接聽的緊急通話，直接跳過開機動畫以加速進入視訊房間
      if (pendingAcceptedCall.value == null) {
        await Future.delayed(const Duration(milliseconds: 4000));
      } else {
        debugPrint("🚨 [Splash] 檢測到待接聽來電，跳過開機動畫延遲");
        // 強制淡出
        if (mounted) setState(() => _fadedOut = true);
      }
      if (!mounted) return;

      // 嘗試獲取登入狀態（已移除 2 秒 .timeout，避免冷啟動 SharedPreferences
      // 初始化 + 磁碟讀取超過 2 秒 → 拋例外 → 誤跳身分頁，讓已登入長輩看似 session 遺失）
      final prefs = await SharedPreferences.getInstance();
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

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => _resolveElderDestination(
                  isCCTV: isCCTV,
                  deviceName: deviceName,
                  elderRoomId: elderRoomId,
                  effectiveUserId: effectiveUserId,
                  effectiveUserName: effectiveUserName,
                ),
              ),
            );
            return;
          }

          // 子女端邏輯：直接進入主要儀表板容器
          final elders = await ApiService.getPairedElders(effectiveUserId);
          if (!mounted) return;

          if (elders.isNotEmpty) {
            // 已有長輩，進入主介面
            _navigateFamilyHome(effectiveUserId, effectiveUserName);
          } else {
            // 未綁定任何長輩，進入引導頁
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    FamilyOnboardingScreen(
                      userId: effectiveUserId,
                      userName: effectiveUserName,
                    ),
              ),
            );
          }
        } catch (e) {
          // 若 API 失敗，使用本地紀錄決定跳轉
          if (mounted) {
            if (effectiveLocalRole == 'elder') {
              final bool isCCTV = prefs.getBool('saved_is_cctv') ?? false;
              final String deviceName = prefs.getString('saved_device_name') ?? effectiveUserName;
              final String elderRoomId = prefs.getString('elder_room_id') ?? effectiveUserId.toString();

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => _resolveElderDestination(
                    isCCTV: isCCTV,
                    deviceName: deviceName,
                    elderRoomId: elderRoomId,
                    effectiveUserId: effectiveUserId,
                    effectiveUserName: effectiveUserName,
                  ),
                ),
              );
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
      final prefs = await SharedPreferences.getInstance();
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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => _resolveElderDestination(
              isCCTV: isCCTV,
              deviceName: deviceName,
              elderRoomId: elderRoomId,
              effectiveUserId: uid,
              effectiveUserName: uname,
            ),
          ),
        );
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
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const IdentificationScreen()),
    );
  }

  /// ★ Issue 3 硬化：在導向身分辨識頁（_goNext）之前的最後防線。
  /// API 失敗或 prefs 短暫讀取異常，不代表本機真的沒有已登入的長輩 session。
  /// 這裡「重新」讀一次 SharedPreferences（不沿用外層可能已經是舊快照的區域變數），
  /// 只要看起來像長輩 session（user_role 直接是 'elder'；或 user_role 欄位本身缺漏
  /// 但 caregiver_id/caregiver_name 都還在，視為寫入未完成的邊界情況也保守當作長輩），
  /// 就一律導向長輩主畫面，絕不因暫時性失敗把已登入長輩丟回身分頁。
  Future<void> _goNextOrRestoreElder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final int? uid = prefs.getInt('caregiver_id');
      final String? uname = prefs.getString('caregiver_name');
      final String? role = prefs.getString('user_role');

      debugPrint(
          '🛟 [Splash] _goNextOrRestoreElder 重讀 prefs: caregiver_id=$uid, caregiver_name=$uname, user_role=$role');

      final bool looksLikeElderSession =
          role == 'elder' || (role == null && uid != null && uname != null);

      if (looksLikeElderSession && mounted) {
        final bool isCCTV = prefs.getBool('saved_is_cctv') ?? false;
        final String deviceName =
            prefs.getString('saved_device_name') ?? uname ?? '長輩';
        final String elderRoomId =
            prefs.getString('elder_room_id') ?? uid?.toString() ?? '0';

        debugPrint('🛡️ [Splash] 偵測到本機長輩 session，改導向長輩主畫面而非身分頁');

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => _resolveElderDestination(
              isCCTV: isCCTV,
              deviceName: deviceName,
              elderRoomId: elderRoomId,
              effectiveUserId: uid ?? 0,
              effectiveUserName: uname ?? deviceName,
            ),
          ),
        );
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
    if (!mounted) return;
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
        final activeCalls = await FlutterCallkitIncoming.activeCalls();
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
          // 立即跳過動畫淡出
          if (mounted) setState(() => _fadedOut = true);
          // 直接導航（不等待 4s 動畫）
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => ElderScreen(
                  roomId: roomId,
                  deviceName: deviceName,
                  initialCallData: pendingAcceptedCall.value,
                ),
              ),
            );
          }
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
      body: AnimatedOpacity(
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


