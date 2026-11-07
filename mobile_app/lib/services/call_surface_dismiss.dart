// ★ 2026-11-07：「來電被取消／結束」時，一次關掉所有來電表面的共用入口（G144 的三面清除）。
//
// 來電表面共有：App 內來電 dialog（main.dart 全域版、ElderHomeScreen 版、FamilyMainScreen 版）、
// CallKit 全螢幕／通知、備援本機通知（LocalCallNotification）、以及預寫的 pending prefs。
// 過去每個 `Signaling.onCancelCall` 覆寫（main／elder_home／family_main／family_dashboard）
// 與 FCM 取消分支各做一部分，漏掉的那一面就變成「對方掛了通知還在」：
//   - family_main／family_dashboard 的覆寫完全沒關 CallKit 備援通知、沒清 prefs；
//   - FCM 前景取消只關 main 的 dialog，ElderHome／FamilyMain 自己的 dialog 還在；
//   - 沒有任何地方把 callId 寫進跨 isolate 的已取消清單。
// 這裡集中處理：標記已取消 → 關 App 內 dialog（所有註冊者）→ 結束 CallKit → 關備援通知
// → 清 pending prefs（只清 callId 吻合或無法判斷者，不誤殺另一通合法 pending）。
// 全程每一步各自 try/catch：任何一步失敗都不得阻斷其餘步驟，也不得向外丟例外。

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show BuildContext, ModalRoute, Navigator;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../globals.dart';
import 'cancelled_call_store.dart';
import 'local_call_notification.dart';

/// 是否該清除某個 pending prefs 項目。
///
/// - 取消事件沒有 callId（[cancelledCallId] 空）→ 無法比對，沿用舊行為清掉（裝置同時只會有一通待處理來電）。
/// - pending 項目沒有 callId（舊資料）→ 清掉（髒資料也不該留）。
/// - 兩者都有 → 只有相同才清，避免用另一通的取消事件抹掉這一通合法的 pending。
bool shouldClearPendingForCancel({String? pendingCallId, String? cancelledCallId}) {
  final String cancelled = (cancelledCallId ?? '').trim();
  final String pending = (pendingCallId ?? '').trim();
  if (cancelled.isEmpty || pending.isEmpty) return true;
  return cancelled == pending;
}

class CallSurfaceDismisser {
  CallSurfaceDismisser._();

  /// App 內來電 dialog 的關閉回呼（各畫面註冊自己的；dispose 時務必 [unregisterDialogCloser]）。
  static final Set<void Function()> _dialogClosers = <void Function()>{};

  static void registerDialogCloser(void Function() closer) => _dialogClosers.add(closer);
  static void unregisterDialogCloser(void Function() closer) => _dialogClosers.remove(closer);

  /// 安全關閉 [dialogContext] 所屬的 dialog route。永不丟例外。
  ///
  /// `Navigator.pop(context)` 會彈掉「該 Navigator 目前最上層的 route」，不一定是 dialog 本身：
  /// dialog 已被別的取消路徑關掉、使用者又進了別的畫面（例如剛按下接聽的通話房）時，
  /// 再 pop 一次會誤殺無辜畫面。因此只在 dialog route 仍是最上層時才 pop；
  /// 還在堆疊但被蓋住時改用 removeRoute；context 已失效就什麼都不做。
  static void popDialogSafely(BuildContext? dialogContext) {
    if (dialogContext == null) return;
    try {
      if (!dialogContext.mounted) return;
      final route = ModalRoute.of(dialogContext);
      if (route == null) return;
      if (route.isCurrent) {
        Navigator.of(dialogContext).pop();
      } else if (route.isActive) {
        Navigator.of(dialogContext).removeRoute(route);
      }
    } catch (e) {
      debugPrint('⚠️ [CallDismiss] 關閉 dialog 失敗（忽略）: $e');
    }
  }

  /// 關閉所有已註冊的 App 內來電 dialog（不碰 CallKit／通知／prefs）。
  static void closeInAppDialogs() {
    for (final closer in List<void Function()>.from(_dialogClosers)) {
      try {
        closer();
      } catch (e) {
        debugPrint('⚠️ [CallDismiss] 關閉 App 內來電 dialog 失敗（忽略）: $e');
      }
    }
  }

  /// 把這通來電的所有表面關掉。永不丟例外。
  ///
  /// [closeDialogs]：背景 isolate 沒有 Navigator，傳 false 略過。
  static Future<void> dismissAll({String? callId, bool closeDialogs = true}) async {
    final String id = (callId ?? '').trim();
    // 1) 先標記：之後任何路徑（含延遲抵達的來電 FCM）查詢都會命中。
    try {
      await CancelledCallStore.mark(id);
    } catch (_) {}
    // 2) App 內 dialog
    if (closeDialogs) closeInAppDialogs();
    // 3) CallKit（MIUI 會拋 PlatformException(content is null)，必須接住 await 的非同步例外）
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      debugPrint('⚠️ [CallDismiss] endAllCalls 失敗（不影響後續）: $e');
    }
    // 4) 備援通知（內部已 try/catch）
    try {
      await LocalCallNotification.cancel();
    } catch (_) {}
    // 5) pending prefs
    await clearPendingCallPrefs(cancelledCallId: id);
  }

  /// 清除 pending 來電 prefs（`pendingAcceptedCall`／`pendingRingCallData`／`pendingRingCall`／
  /// `pendingLocalRingCall`），並同步重設記憶體中的 [pendingAcceptedCall]。
  static Future<void> clearPendingCallPrefs({String? cancelledCallId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      try {
        await prefs.reload();
      } catch (_) {}
      for (final key in const [
        'pendingAcceptedCall',
        'pendingRingCallData',
        'pendingRingCall',
        'pendingLocalRingCall',
      ]) {
        try {
          final String? raw = prefs.getString(key);
          if (raw == null) continue;
          String? pendingId;
          try {
            final dynamic decoded = jsonDecode(raw);
            if (decoded is Map) pendingId = decoded['callId']?.toString();
          } catch (_) {}
          if (shouldClearPendingForCancel(
              pendingCallId: pendingId, cancelledCallId: cancelledCallId)) {
            await prefs.remove(key);
          }
        } catch (e) {
          debugPrint('⚠️ [CallDismiss] 清除 $key 失敗（忽略）: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ [CallDismiss] 清除 pending prefs 失敗（忽略）: $e');
    }
    try {
      final Map<String, String?>? mem = pendingAcceptedCall.value;
      if (mem != null &&
          shouldClearPendingForCancel(
              pendingCallId: mem['callId'], cancelledCallId: cancelledCallId)) {
        pendingAcceptedCall.value = null;
      }
    } catch (_) {}
  }
}
