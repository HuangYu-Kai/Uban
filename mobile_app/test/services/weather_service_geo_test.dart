import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/weather_service.dart';

void main() {
  group('WeatherService GPS 純函式', () {
    test('座標四捨五入到小數 2 位', () {
      expect(WeatherService.roundCoord(25.03449), 25.03);
      expect(WeatherService.roundCoord(121.5655), 121.57);
      expect(WeatherService.roundCoord(22.0), 22.0);
    });

    test('快取鍵包含四捨五入後座標，不同區不共用', () {
      expect(WeatherService.geoCacheKey(25.03, 121.56),
          'cached_weather_geo_25.03_121.56');
      expect(WeatherService.geoCacheKey(25.0, 121.5),
          'cached_weather_geo_25.00_121.50');
      expect(WeatherService.geoCacheKey(25.03, 121.56),
          isNot(WeatherService.geoCacheKey(25.06, 121.52)));
    });

    test('最近縣市推定', () {
      expect(WeatherService.nearestCityName(25.04, 121.55), '台北');
      expect(WeatherService.nearestCityName(22.63, 120.30), '高雄');
      expect(WeatherService.nearestCityName(23.99, 121.60), '花蓮');
      expect(WeatherService.nearestCityName(24.43, 118.32), '金門');
    });

    test('定位新鮮度（6 小時內）', () {
      final now = DateTime(2026, 10, 6, 12);
      expect(
          WeatherService.isFixFresh(
              now.subtract(const Duration(hours: 5)), now),
          isTrue);
      expect(
          WeatherService.isFixFresh(
              now.subtract(const Duration(hours: 6)), now),
          isFalse);
      expect(
          WeatherService.isFixFresh(
              now.subtract(const Duration(days: 1)), now),
          isFalse);
    });
  });
}
