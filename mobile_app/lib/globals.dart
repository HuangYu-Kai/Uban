import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

ValueNotifier<Map<String, String?>?> pendingAcceptedCall = ValueNotifier(null);
bool isAppReady = false;
String? appRole;

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
