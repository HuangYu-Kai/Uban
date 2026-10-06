/// 「手動輸入移機登入代碼」的全域掛鉤。
///
/// ★ 2026-10-06 登入流程改善：移機網頁（`/recovery?code=...`）會顯示一組數字
/// 代碼，但 App 原本沒有地方可以輸入。長輩身分選擇畫面
/// （`elder_pairing_display_screen.dart`）新增「輸入家人給的登入代碼」入口，
/// 輸入後呼叫本掛鉤，沿用 `main.dart` 既有的 Deep Link 復原確認對話框
/// （`_showRecoveryConfirmationDialog`：驗證代碼、顯示長輩／家屬姓名、確認後存
/// 偏好並導航）。
///
/// 為什麼用全域函式而不是讓畫面直接 import main.dart：main.dart 是通話／FCM
/// 的高風險檔案，畫面反向依賴它會造成循環 import；由 main.dart 的 State 在
/// initState 註冊、dispose 清除（僅在仍指向自己時），對 main.dart 的改動降到最小。
///
/// 為 null 代表 App 根 Widget 尚未就緒，呼叫端應提示「暫時無法使用，請稍後再試」。
void Function(String code)? recoveryCodeHandler;
