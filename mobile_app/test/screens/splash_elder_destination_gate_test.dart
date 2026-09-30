// 第五十三輪 callfix53b：補上 onboard53b 已知缺口——splash_screen.dart 冷啟動
// 偵測到既有長輩 session 時，原本完全繞過「年齡／居住地」必填檢查
// （`elder_pairing_display_screen.dart::_goToElderHome` 檔頭記載的已知範圍
// 限制）。修復方式見 `splash_screen.dart` 的 `_replaceWithElderDestinationOrOnboarding`。
//
// 任務協調者訂的三條紅線之一（紅線 2／3）：「有效待接聽來電」與「監控機」
// 兩種情境必須優先於補填檢查，不能被表單擋住。實作上不重新判斷這兩種情境
// （那組條件已經完整存在於 `_resolveElderDestination()` 內，含過期／角色
// 反轉檢查），而是只檢查它決定好的 widget 型別——只有 `ElderHomeScreen`
// （代表非監控機、也沒有有效待接聽來電）才需要做非同步的資料完整度檢查。
//
// 這個判斷式被抽成頂層純函式 `shouldCheckProfileCompletenessBeforeEntering`，
// 本測試只鎖住這個判斷式本身：不 pump `SplashScreen` 本尊——它的冷啟動流程
// 依賴 SharedPreferences、`ApiService`、`FlutterCallkitIncoming` 平台通道等
// 大量執行期依賴，不適合純 widget test（比照
// `test/screens/elder_screen_stack_sizing_test.dart` 的既有做法：只驗證會
// 出錯的那個最小結構，不勉強 pump 整個重量級畫面）。單純建構
// `ElderScreen`／`ElderHomeScreen` 的 widget 實例不需要任何執行期依賴
// （StatefulWidget 建構子只是存欄位，不觸發 `createState()`/`build()`）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/splash_screen.dart';
import 'package:flutter_application_1/screens/elder_home_screen.dart';
import 'package:flutter_application_1/screens/elder_screen.dart';

void main() {
  group('shouldCheckProfileCompletenessBeforeEntering（來電/監控機優先於補填的鑑別邏輯）', () {
    test('一般開機（非監控機、無待接聽來電）目的地是 ElderHomeScreen 時，必須檢查', () {
      const destination = ElderHomeScreen(userId: 1, userName: '測試長輩');
      expect(
        shouldCheckProfileCompletenessBeforeEntering(destination),
        isTrue,
        reason: '這是唯一「正常落地」的情境，補填檢查一定要在這裡發生，否則整個'
            '第五十三輪 onboard53 的必填改動對「一直沒登出過」的舊使用者形同虛設',
      );
    });

    test('紅線3：監控機模式（ElderScreen isCCTVMode:true）不得觸發補填檢查', () {
      const destination = ElderScreen(
        roomId: 'monitor_elder_1',
        isCCTVMode: true,
      );
      expect(
        shouldCheckProfileCompletenessBeforeEntering(destination),
        isFalse,
        reason: '監控機沒有「使用者」在操作，不應該被導去補填畫面（比照 '
            'elder_pairing_display_screen.dart 刻意跳過 isMonitor 分支的既有決定）',
      );
    });

    test('紅線2：帶有效待接聽來電資料（ElderScreen + initialCallData）不得觸發補填檢查', () {
      final destination = ElderScreen(
        roomId: 'comm_elder_1',
        initialCallData: const {
          'roomId': 'comm_elder_1',
          'senderId': 'caller-sid',
          'callId': 'call-1',
        },
      );
      expect(
        shouldCheckProfileCompletenessBeforeEntering(destination),
        isFalse,
        reason: '長輩有來電進來時必須直接進通話流程；若這裡誤判為 true，'
            '會在來電響鈴的路上插入一次非同步 API 呼叫，等於把使用者卡在表單，'
            '失去與家人聯繫的能力',
      );
    });
  });
}
