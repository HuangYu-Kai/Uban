# flutter_callkit_incoming 內嵌版修補記錄

基於上游 **3.0.0**（pub.dev）。排除 `example/` 與建置產物，保留 LICENSE。
`mobile_app/pubspec.yaml` 以 `dependency_overrides` 指向本目錄。

Kotlin 路徑：`android/src/main/kotlin/com/hiennv/flutter_callkit_incoming/`。其餘檔案與上游相同。
對照方式：`diff -r ~/.pub-cache/hosted/pub.dev/flutter_callkit_incoming-3.0.0 .`（差異應只有 `example/`、本檔，與下列兩個 Kotlin 檔）。

## 改動

1. **FlutterCallkitIncomingPlugin.kt `initSharedInstance` 的 else 分支**
   單例已存在但 `instance.context` 為 null 時，設為傳入的 context。
   原因：上游只在首次建立單例時設 context，之後 context 遺失就補不回來。

2. **FlutterCallkitIncomingPlugin.kt `onDetachedFromActivity`**
   只清 `activity`，不清 `context`。
   原因：上游把單例 context 設為 null（`MainActivity` 以 `finishAndRemoveTask` 結束即觸發）。之後 `showCallkitIncoming`、`startCall` 靜默無作用卻回 success，`endAllCalls`／`endCall`／`activeCalls` 丟出 `argument "content" is null`（即文件中的 MIUI `PlatformException(content is null)`）。

3. **CallkitIncomingBroadcastReceiver.kt，`ACTION_CALL_DECLINE` 與 `ACTION_CALL_ENDED`**
   新增 `clearIncomingWithFallback`：`getCallkitNotificationManager()` 非 null 時呼叫 `clearIncomingNotification(data, false)`，行為與上游完全相同；為 null 時改用系統 `NotificationManager.cancel(data.getString(EXTRA_CALLKIT_ID, "callkit_incoming").hashCode())`（與 `CallkitNotificationManager.clearIncomingNotification` 同一算法），並廣播 `CallkitIncomingActivity.getIntentEnded(context, false)` 關閉全螢幕來電畫面。
   原因：manager 遺失時通知與全螢幕畫面關不掉。限制：程序被殺且 Dart 無法啟動時，只能關通知，無法通知後端。

4. **FlutterCallkitIncomingPlugin.kt method channel `"endAllCalls"`**
   一律廣播 `getIntentEnded`，不再對未接聽來電廣播 `getIntentDecline`（與同檔 Kotlin 函式 `endAllCalls()` 一致）。
   原因：context 修好後，上游行為會讓 Dart 在「接聽前呼叫 endAllCalls」時收到 Decline 事件，接聽被當成拒接，甚至誤拒不相關來電。

## 為何不升級 3.1.x

- `CallEvent` 改為 sealed class，App 使用的 `event.event`、`event.body`、`Event.*` 消失。
- `activeCalls()` 改回傳物件，App 的 `call is! Map` 判斷會靜默跳過冷啟動補救。
- 鈴聲改為遵守靜音。

因此維持 3.0.0 並只補上述缺陷（修法參考上游 3.1.6）。
