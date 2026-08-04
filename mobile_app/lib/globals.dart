import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

ValueNotifier<Map<String, String?>?> pendingAcceptedCall = ValueNotifier(null);
bool isAppReady = false;
String? appRole;

/// ★ 2026-07-18：來電有效期（毫秒）。與後端 socket_app.py 的 expires_at/FCM ttl
///   以及 CallKit `duration` 三者必須一致，否則會出現「通知還在響但接聽被判過期」。
/// ★ 2026-07-20：有效期 45s→120s，與後端 socket_app.py expires_at/FCM ttl 同步。
///   Android Doze/省電桶可能延遲 FCM 60-90 秒，45s ttl 會在 Doze 期間過期。
///   CallKit duration 保持 45s 不變（使用者接聽時間仍以 45s 為限）。
const int kCallValidityMs = 120000;

/// ★ 2026-07-19：SplashScreen 是否仍在畫面上（冷啟動導航進行中）。
///   冷啟動接聽來電時，SplashScreen 是 pendingAcceptedCall 的唯一導航擁有者；
///   main.dart 的全域兜底導航在此期間必須讓位，避免把 VideoCallScreen push 到
///   Splash 上後又被 Splash 的 pushReplacement 洗掉（家屬接聽後只進主畫面的 bug）。
bool splashActive = false;

/// ★ issue 3/10：通話/監控畫面結束時的安全導航。
/// 若目前路由可以 pop（代表是從某個主畫面正常推入的），則直接返回；
/// 若無法 pop（例如冷啟動後直接被導向通話畫面，沒有上一頁），
/// 則導向呼叫端提供的 [fallbackScreen]（通常是長輩/家屬主畫面），
/// 並清空導航堆疊，避免出現黑屏或無回應畫面。
void safeNavigateBack(BuildContext context, Widget fallbackScreen) {
  if (!context.mounted) return;
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  } else {
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => fallbackScreen),
      (route) => false,
    );
  }
}

/// ★ 2026-08-02 第十四輪：解析各通路傳來的 isVideoCall。
/// Socket 給 bool、FCM 經後端 `str()` 會變成 "True"/"False"（Python 首字大寫）、
/// prefs/CallKit extra 給字串——一律在此正規化。
/// **只有明確為 false 才判定為語音通話**，其餘（含 null、無法解析）一律 true（安全預設）。
bool parseIsVideoCall(dynamic raw) {
  if (raw == null) return true;
  if (raw is bool) return raw;
  return raw.toString().trim().toLowerCase() != 'false';
}
