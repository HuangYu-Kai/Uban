// 賽季說明彈窗迴歸測試（第五十三輪，任務 6）。
//
// 使用者原話：「長輩端的寵物賽季顯示的字太小，老人不易看見，並且僅顯示
// 『第一季，還有 XX 天』，老人根本不會知道這個彈出提示代表什麼」。
//
// 背景：見 `pet_corner_actions.dart` 內 `_showSeasonInfoDialog` 開頭的
// 說明——精簡模式（長輩實際最常見的直向手機首頁，`compact: true`）原本
// 點擊賽季圖示只會彈出 2 秒鐘、預設字級的 `SnackBar`（僅「第 N 季，還剩
// N 天」七個字），這正是使用者回報的來源；非精簡模式（橫屏／
// `pet_studio_screen.dart`）其實早就換成了圖文並茂、白話說明的
// `PetSeasonCard`，只是精簡模式這個進入點沒有跟著換。
//
// 本檔驗證改成的說明對話框：
//   1. 確實會出現，且不再是舊的 2 秒 SnackBar；
//   2. 內容重用 `PetSeasonCard` 既有的白話說明與 `ElderScale` 字級
//      （24pt 標題／20pt 副標／18pt 說明句），不是另外自訂一組更小的字；
//   3. 有一個長輩可以自己按著關閉的「知道了」按鈕，不再受 2 秒自動消失
//      的時間壓力限制。
//
// ⚠️ `PetProgressService.loadSeason()` 打的是真實 `GET /api/pet/season`，
// `flutter test` 的 `TestWidgetsFlutterBinding` 會攔截所有 HTTP 請求並
// 一律回傳失敗（比照 `elder_home_tab_news_visibility_test.dart` 檔頭
// 說明），導致 `_season` 恆為 null、賽季圖示與本彈窗永遠不會被建出來。
// 因此透過 `PetCornerActions.debugInitialSeasonForTest`
// （`@visibleForTesting`，production 呼叫端恆為 null，見該欄位說明）
// 直接注入假賽季資料，繞開網路。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/screens/elder_tabs/profile/widgets/pet_corner_actions.dart';
import 'package:flutter_application_1/screens/pet_companion_studio/services/pet_progress_service.dart';

void main() {
  // google_fonts 在測試環境找不到本地字型資產時會嘗試打網路抓取，關掉
  // runtime fetching 讓它退回系統 fallback 字型（比照既有測試慣例）。
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final fakeSeason = PetSeasonInfo(
    seasonNo: 3,
    startDate: DateTime(2026, 9, 1),
    endDate: DateTime(2026, 9, 30),
    status: 'active',
    daysRemaining: 12,
  );

  testWidgets('精簡模式點擊賽季圖示：彈出說明對話框，不再是 2 秒 SnackBar',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: PetCornerActions(
              userId: 1,
              compact: true,
              debugInitialSeasonForTest: fakeSeason,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull, reason: '掛載精簡模式膠囊群不應有任何例外');

    // 點擊前：對話框內容不應該存在。
    expect(find.text('第 3 季'), findsNothing);

    await tester.tap(find.text('🗓️'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '開啟賽季說明對話框不應有任何例外');

    // ① 對話框確實開啟，且重用 PetSeasonCard 既有的大字文案／ElderScale
    // 字級，而不是舊版 SnackBar 那種預設字級的短句。
    expect(find.text('第 3 季'), findsOneWidget,
        reason: '應該顯示 PetSeasonCard 的大字標題（24pt），而非舊版 SnackBar 的小字');
    expect(find.text('還有 12 天結束'), findsOneWidget);
    // ★ 核心斷言：長輩必須看得懂「這代表什麼、時間到了會怎樣」，不能只有
    // 「第 N 季，還有 N 天」這種沒有解釋的短句。
    expect(find.text('時間到會結算排名，小豬會從頭養起'), findsOneWidget,
        reason: '必須包含白話說明句，不能只有「第 N 季，還有 N 天」');

    // ② 不再是 2 秒自動消失、看不清楚的 SnackBar。
    expect(find.byType(SnackBar), findsNothing,
        reason: '第五十三輪 item 6 之後，賽季說明改走對話框，不應再出現 SnackBar');

    // ③ 長輩自己按「知道了」才關閉，不受時間壓力限制。
    expect(find.text('知道了'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('第 3 季'), findsNothing, reason: '按下「知道了」後對話框應該關閉');
  });
}
