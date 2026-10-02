import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/utils/taiwan_districts.dart';

/// 台灣縣市／行政區白名單單元測試。
///
/// ★ 第五十三輪 onboard53b：長輩端／家屬端「年齡與居住地改為必填」——
/// 這份白名單同時是 `CityDistrictPicker` 下拉選單的資料來源，也是前端
/// 送出前的最後一道檢查（後端 `services/taiwan_regions.py::is_valid_city_district`
/// 是同一份資料的 Python 版本，兩邊的規則必須一致）。
void main() {
  group('isValidCityDistrict', () {
    test('合法的縣市＋行政區組合回傳 true', () {
      expect(isValidCityDistrict('臺北市', '大安區'), isTrue);
      expect(isValidCityDistrict('高雄市', '鳳山區'), isTrue);
    });

    test('縣市與行政區不成對（區不屬於該縣市）回傳 false', () {
      // 大安區屬於臺北市，不屬於高雄市。
      expect(isValidCityDistrict('高雄市', '大安區'), isFalse);
    });

    test('縣市不在白名單內回傳 false', () {
      expect(isValidCityDistrict('台北縣', '板橋區'), isFalse); // 舊稱，已併入新北市
      expect(isValidCityDistrict('Taipei', '大安區'), isFalse);
    });

    test('city 或 district 為 null 時回傳 false', () {
      expect(isValidCityDistrict(null, '大安區'), isFalse);
      expect(isValidCityDistrict('臺北市', null), isFalse);
      expect(isValidCityDistrict(null, null), isFalse);
    });

    test('每個縣市至少有一個行政區，且清單彼此不重複健全性檢查', () {
      for (final city in kTaiwanCities) {
        final districts = kTaiwanDistricts[city];
        expect(districts, isNotNull, reason: '$city 應該要有對應的行政區清單');
        expect(districts!.isNotEmpty, isTrue, reason: '$city 的行政區清單不應為空');
        expect(districts.toSet().length, districts.length,
            reason: '$city 的行政區清單內不應有重複項目');
      }
    });

    // ★ canary：先證明「合法組合」與「不合法組合」的判斷不是恆為同一個值。
    test('canary：合法與不合法組合的判斷結果不同', () {
      expect(isValidCityDistrict('臺北市', '大安區'),
          isNot(equals(isValidCityDistrict('臺北市', '不存在的區'))));
    });
  });
}
