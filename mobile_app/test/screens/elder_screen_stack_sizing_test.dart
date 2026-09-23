// 第五十二輪任務 A：驗證 elder_screen.dart 的 0×0 Stack 修復。
//
// 背景：使用者實機回報長輩端通話房（一般通話與緊急通話皆然）進入後全黑、
// 無法掛斷也無法進行任何操作，只能等家屬端掛斷後被系統自動 pop 回主畫面。
// 已定位的根因：`elder_screen.dart::build()` 回傳的
// `Scaffold(body: Stack(children: [...]))`，第五十一輪在 Stack 的 children
// 裡插入了一個非 Positioned 子元件 `const AssistantHiddenZone(child:
// SizedBox.shrink())`，而其餘 children 全是 `Positioned`/`Positioned.fill`。
//
// 依 Flutter `RenderStack` 的尺寸規則——只要 children 裡有任何一個「非
// Positioned」子元件，Stack 的尺寸就由那些非 Positioned 子元件決定（取
// 最大寬高、再套用外部約束）；完全沒有非 Positioned 子元件時才會退回吃滿
// 外部約束。`Scaffold` 的 body 拿到的是寬鬆約束（min 0），於是整個 Stack
// 連同底下所有 `Positioned.fill` 視訊畫面與按鈕，一起被那個 0×0 的標記
// widget 拖成 0×0——黑屏、零尺寸、無法 hit-test，與回報症狀完全吻合。
//
// 本測試不 pump `ElderScreen` 本尊：它的建構需要已連線的 `Signaling`
// 單例、WebRTC renderer、SharedPreferences 等大量執行期依賴，不適合純
// widget test。改直接重現造成崩潰的最小結構，並使用**正式程式碼**中的
// `AssistantHiddenZone`（`lib/widgets/global_assistant_button.dart`）——
// 不是另外手刻的替身——確保測的是真正會跑進 App 的那個 widget，其餘結構
// （Scaffold 黑底 + Stack + Positioned.fill）逐字對照 elder_screen.dart
// 的寫法。
//
// 三組斷言（鐵律：驗證必須有可能失敗——下面第一組刻意重建「修復前」的
// 結構，證明本測試有能力抓到這個回歸，不是恆綠檢查）：
//   1. 「修復前」結構（AssistantHiddenZone 混在 Stack children 裡）
//      → Stack 與其 Positioned.fill 內容物的量測尺寸都必須是 0×0。
//   2. 「修復後」結構（AssistantHiddenZone 包住整個 Scaffold）
//      → Stack 與其內容物的量測尺寸都必須等於畫面尺寸，且按鈕點得到。
//   3. AssistantHiddenZone 搬到外層後，計數行為（浮動鈕讓位判斷的依據）
//      與包在 Stack 內完全相同——佐證修復不影響它原本的用途。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/widgets/global_assistant_button.dart';

void main() {
  // 固定測試視窗尺寸，讓「等於畫面尺寸」的斷言是一個具體、非平凡的數字，
  // 不依賴 flutter_test 套件版本之間可能不同的預設視窗尺寸。
  const screenSize = Size(400, 800);

  Future<void> setScreenSize(WidgetTester tester) async {
    tester.view.physicalSize = screenSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  setUp(() {
    // 每個測試各自獨立：保險起見在開始前重置這個模組層級的計數器，避免
    // 測試執行順序互相影響（正常情況下 AssistantHiddenZone.dispose() 已
    // 經會自己扣掉加過的那一次）。
    assistantHiddenDepthNotifier.value = 0;
  });

  testWidgets(
    '【回歸重現】AssistantHiddenZone 混進 Stack children 時，'
    'Stack 與其 Positioned.fill 內容物都會塌成 0×0'
    '（第五十一輪 elder_screen.dart 的真實結構，證明本測試有能力抓到這個 bug）',
    (tester) async {
      await setScreenSize(tester);
      final stackKey = GlobalKey();
      final contentKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              key: stackKey,
              children: [
                // 與第五十一輪 elder_screen.dart 逐字相同的寫法。
                const AssistantHiddenZone(child: SizedBox.shrink()),
                Positioned.fill(
                  child: Container(key: contentKey, color: Colors.redAccent),
                ),
              ],
            ),
          ),
        ),
      );

      final stackSize =
          tester.renderObject<RenderBox>(find.byKey(stackKey)).size;
      final contentSize =
          tester.renderObject<RenderBox>(find.byKey(contentKey)).size;

      expect(
        stackSize,
        Size.zero,
        reason:
            '有非 Positioned 子元件（AssistantHiddenZone(child: '
            'SizedBox.shrink())）混在 Stack children 裡時，RenderStack 的'
            '尺寸由該子元件決定——本體 0×0，故整個 Stack 應塌成 0×0。若這個'
            '斷言失敗（尺寸不是 0），代表 Flutter 版本對 RenderStack 尺寸'
            '規則的行為已經改變，必須重新確認修復前的結構是否還會重現'
            '原始 bug，不可直接假設本測試仍然有效。',
      );
      expect(
        contentSize,
        Size.zero,
        reason:
            'Stack 尺寸塌成 0×0 後，Positioned.fill 的版面約束是「填滿 '
            'Stack 自己的尺寸」，因此底下的視訊畫面／按鈕容器也會被壓成 '
            '0×0，沒有任何 hit-test 區域——這正是使用者回報「無法掛斷、'
            '無法操作」的成因。',
      );
    },
  );

  testWidgets(
    '【修復驗證】AssistantHiddenZone 包住整個 Scaffold 後，'
    'Stack 與其 Positioned.fill 內容物尺寸都等於畫面尺寸，且按鈕點得到'
    '（第五十二輪修復後 elder_screen.dart 的真實結構）',
    (tester) async {
      await setScreenSize(tester);
      final stackKey = GlobalKey();
      final contentKey = GlobalKey();
      var tapped = false;

      await tester.pumpWidget(
        AssistantHiddenZone(
          child: MaterialApp(
            home: Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                key: stackKey,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      key: contentKey,
                      onTap: () => tapped = true,
                      child: Container(color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final stackSize =
          tester.renderObject<RenderBox>(find.byKey(stackKey)).size;
      final contentSize =
          tester.renderObject<RenderBox>(find.byKey(contentKey)).size;

      expect(
        stackSize,
        screenSize,
        reason:
            'Stack children 全部是 Positioned/Positioned.fill（沒有任何非 '
            'Positioned 子元件）時，RenderStack 應退回吃滿外部約束—— '
            'Scaffold body 的寬鬆約束上限就是整個畫面，尺寸應等於 '
            '$screenSize。',
      );
      expect(
        contentSize,
        screenSize,
        reason: 'Positioned.fill 應填滿已還原為全螢幕的 Stack，掛斷鍵等'
            '控制項因此重新擁有正常的 hit-test 區域。',
      );

      await tester.tap(find.byKey(contentKey));
      await tester.pump();
      expect(
        tapped,
        isTrue,
        reason: 'Stack 撐滿全螢幕後，Positioned.fill 底下的按鈕應該點得'
            '到——對應使用者要能正常掛斷、操作通話房。',
      );
    },
  );

  testWidgets(
    'AssistantHiddenZone 包在 Scaffold 外層時，'
    '浮動助理鈕讓位計數器（assistantHiddenDepthNotifier）行為與包在 '
    'Stack 內完全相同',
    (tester) async {
      // 佐證 elder_screen.dart build() 開頭註解的前提：搬到外層不影響它
      // 自己的計數邏輯（計數只依賴 AssistantHiddenZone 自身的 State
      // 生命週期，與它包在 widget 樹的哪個位置無關）。
      expect(assistantHiddenDepthNotifier.value, 0);

      final mountedNotifier = ValueNotifier<bool>(true);
      addTearDown(mountedNotifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: mountedNotifier,
            builder: (context, isMounted, _) {
              if (!isMounted) return const SizedBox.shrink();
              return const AssistantHiddenZone(child: SizedBox.shrink());
            },
          ),
        ),
      );
      expect(
        assistantHiddenDepthNotifier.value,
        1,
        reason: '進場時應該加一，浮動鈕讓位。',
      );

      mountedNotifier.value = false;
      await tester.pump();
      expect(
        assistantHiddenDepthNotifier.value,
        0,
        reason: '離場（dispose）時應該扣回去，浮動鈕恢復顯示。',
      );
    },
  );
}
