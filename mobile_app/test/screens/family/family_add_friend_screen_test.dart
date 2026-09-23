// 第五十二輪任務 C：家屬端加好友畫面 QR／分享／掃描回歸測試。
//
// 涵蓋兩類測試：
//
// 1. 純邏輯（不需要 pump 畫面）：驗證 [encodeFamilyFriendQr] 產生的字串一定
//    能被 [decodeFamilyFriendQr] 解析回原本的代碼，且非 Uban 家屬好友 QR
//    （字首不符）會被正確判斷為 null。這兩個函式就是畫面實際在用的程式碼
//    （見 lib/screens/family/family_add_friend_screen.dart），特意拉到 State
//    類別外面宣告成頂層函式，測試才能直接呼叫，不用另外重寫一份平行邏輯、
//    也不用碰觸私有成員。
//
// 2. 畫面靜態結構：驗證「我的代碼／掃描／搜尋加好友／好友管理」四個分頁
//    都存在（不需要網路，_buildModeSwitcher 是純靜態 UI）。
//
// ⚠️ 誠實範圍聲明——以下行為本測試「刻意不」在 pump 出來的畫面上驗證，
// 需要實機或有網路的環境才能確認：
//   - QR 碼／複製代碼／分享代碼按鈕的實際渲染：這三者只在
//     `_myCode != null` 時才顯示，而 `_myCode` 來自
//     `FamilyFriendService.getMyCode()` 的真實 HTTP 呼叫；測試沙盒沒有對應
//     網路，呼叫必定失敗、`_myCode` 恆為 null，畫面會落到
//     `_buildInlineErrorBlock`（既有行為，非本輪新增），QR／分享 UI 因此
//     無法在此環境下被 pump 出來驗證。
//   - 「分享代碼」按鈕實際點擊觸發的系統分享面板：`share_plus` 會呼叫平台
//     原生 channel，測試沙盒沒有掛載對應的平台實作，不安全點擊測試。
//   - 「掃描」分頁實際開啟相機預覽：`mobile_scanner` 一樣需要平台原生
//     channel（相機權限、鏡頭裝置），本測試只驗證分頁按鈕存在，不會真的
//     切換進去觸發 MobileScannerController 初始化。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/screens/family/family_add_friend_screen.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('QR 內容編碼／解碼純邏輯', () {
    test('encode 產生的字串帶有 uban-family: 字首', () {
      expect(encodeFamilyFriendQr('AB12'), equals('uban-family:AB12'));
      expect(kFamilyFriendQrPrefix, equals('uban-family:'));
    });

    test('decode 能把 encode 產生的字串還原成原本的代碼（往返一致）', () {
      for (final code in ['AB12', '23Z9', 'HJKL', '0000']) {
        final qrContent = encodeFamilyFriendQr(code);
        expect(decodeFamilyFriendQr(qrContent), equals(code),
            reason: '代碼 $code 編碼再解碼必須得到原本的值');
      }
    });

    test('decode 對不符字首的字串（非 Uban 家屬好友 QR）回傳 null', () {
      expect(decodeFamilyFriendQr('uban-friend:AB12'), isNull,
          reason: '長輩端的 QR（uban-friend: 字首）不該被誤判成家屬端好友碼');
      expect(decodeFamilyFriendQr('https://example.com/some-store-qr'), isNull);
      expect(decodeFamilyFriendQr('AB12'), isNull, reason: '裸代碼（沒有字首）也必須被拒絕，不能猜測式接受');
    });

    test('decode 會清掉前後空白（掃描器有時會夾帶換行／空白字元）', () {
      expect(decodeFamilyFriendQr('uban-family: AB12 \n'), equals('AB12'));
    });
  });

  group('畫面靜態結構', () {
    Widget buildHarness() {
      return const MaterialApp(
        home: FamilyAddFriendScreen(familyId: 2, familyName: '測試家屬'),
      );
    }

    testWidgets('四個分頁（我的代碼／掃描／搜尋加好友／好友管理）都存在', (WidgetTester tester) async {
      await tester.pumpWidget(buildHarness());
      // 分頁切換列是純靜態 UI，不依賴 _myCode 是否載入成功，一個短 pump 足夠。
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('我的代碼'), findsOneWidget);
      expect(find.text('掃描'), findsOneWidget,
          reason: '第五十二輪任務 C：家屬端比照長輩端補上掃描分頁，這裡必須看得到入口');
      expect(find.text('搜尋加好友'), findsOneWidget);
      expect(find.text('好友管理'), findsOneWidget);
    });
  });
}
