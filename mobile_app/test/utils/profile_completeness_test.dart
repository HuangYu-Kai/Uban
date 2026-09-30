import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/utils/profile_completeness.dart';

/// `isProfileConfirmedIncomplete` 單元測試。
///
/// ★ 第五十三輪 onboard53b：長輩端／家屬端「年齡與居住地改為必填」共用的
/// 判斷邏輯（見 `lib/utils/profile_completeness.dart` 檔頭說明）。
///
/// 對應任務要求的三組情境：
/// 1. 三欄齊全 → 不跳補填（回傳 false）
/// 2. 任一為空 → 跳補填（回傳 true）
/// 3. API 讀取失敗（逾時／離線／伺服器錯誤／例外）→ 不強制、放行（回傳 false）
void main() {
  group('isProfileConfirmedIncomplete', () {
    test('三欄齊全時回傳 false（不跳補填）', () {
      final result = {
        'status': 'success',
        'data': {
          'age': 75,
          'residence_city': '臺北市',
          'residence_district': '大安區',
        },
      };
      expect(isProfileConfirmedIncomplete(result), isFalse);
    });

    test('age 為 null 時回傳 true（跳補填）', () {
      final result = {
        'status': 'success',
        'data': {
          'age': null,
          'residence_city': '臺北市',
          'residence_district': '大安區',
        },
      };
      expect(isProfileConfirmedIncomplete(result), isTrue);
    });

    test('residence_city 為 null 時回傳 true（跳補填）', () {
      final result = {
        'status': 'success',
        'data': {
          'age': 75,
          'residence_city': null,
          'residence_district': '大安區',
        },
      };
      expect(isProfileConfirmedIncomplete(result), isTrue);
    });

    test('residence_district 為空字串時回傳 true（跳補填）', () {
      final result = {
        'status': 'success',
        'data': {
          'age': 75,
          'residence_city': '臺北市',
          'residence_district': '',
        },
      };
      expect(isProfileConfirmedIncomplete(result), isTrue);
    });

    test('residence_city 為空字串時回傳 true（跳補填）', () {
      final result = {
        'status': 'success',
        'data': {
          'age': 75,
          'residence_city': '',
          'residence_district': '大安區',
        },
      };
      expect(isProfileConfirmedIncomplete(result), isTrue);
    });

    test('三欄皆缺時回傳 true（跳補填）', () {
      final result = {
        'status': 'success',
        'data': <String, dynamic>{},
      };
      expect(isProfileConfirmedIncomplete(result), isTrue);
    });

    // --- fail-open：讀取失敗一律不強制、直接放行 ---

    test('status 非 success（例如逾時）時回傳 false（fail-open，不強制）', () {
      final result = {'status': 'error', 'message': '連線逾時，請檢查網路'};
      expect(isProfileConfirmedIncomplete(result), isFalse);
    });

    test('data 缺漏時回傳 false（fail-open，不強制）', () {
      final result = {'status': 'success'};
      expect(isProfileConfirmedIncomplete(result), isFalse);
    });

    test('data 型別不是 Map 時回傳 false（fail-open，不強制）', () {
      final result = {'status': 'success', 'data': 'unexpected string'};
      expect(isProfileConfirmedIncomplete(result), isFalse);
    });

    test('apiResult 本身為 null（呼叫端 catch 到例外）時回傳 false（fail-open，不強制）', () {
      expect(isProfileConfirmedIncomplete(null), isFalse);
    });

    // ★ canary：先證明「資料確定缺」與「讀不到資料」在本函式裡是兩種不同結果，
    //   不是隨便回傳同一個常數就能通過上面全部測試——如果實作被誤改成恆
    //   回傳 false（例如誤刪了完整度判斷、只保留 fail-open 分支），下面這個
    //   斷言會先失敗，而不是全部測試靜悄悄地一起變綠。
    test('canary：資料確定不完整時不會被 fail-open 分支吃掉', () {
      final confirmedIncomplete = {
        'status': 'success',
        'data': {'age': null, 'residence_city': null, 'residence_district': null},
      };
      final unreadable = {'status': 'error'};
      expect(isProfileConfirmedIncomplete(confirmedIncomplete),
          isNot(equals(isProfileConfirmedIncomplete(unreadable))));
    });
  });
}
