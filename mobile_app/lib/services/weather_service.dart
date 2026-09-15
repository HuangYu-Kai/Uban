// lib/services/weather_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// 天氣查詢結果（給長輩端首頁天氣卡片使用）。
///
/// [isFromCache] 只在「連線失敗、改用本機舊資料頂替」時才會是 true，讓 UI
/// 可以加一行小字說明「這是上次查到的資料」；快取仍新鮮（一小時內）而省下
/// 這次連線的情況，對長輩來說跟剛查到的沒有分別，因此 [isFromCache] 維持
/// false，不特別標示。
class WeatherInfo {
  /// 解析出的顯示城市名（例如「台北」「屏東」）。
  final String city;
  final double maxTemp;
  final double minTemp;

  /// 降雨機率（百分比整數，0-100）。
  final int rainProbability;

  /// 天氣狀況文字。用詞與後端 AI 工具（`tools_service.py::get_weather_info`）
  /// 完全一致的三段分級，避免長輩問小嘎「今天天氣如何」時，AI 講的跟首頁
  /// 卡片顯示的兜不起來。
  final String condition;

  final DateTime fetchedAt;

  /// true = 這是連線失敗後拿出來頂替的舊資料。
  final bool isFromCache;

  const WeatherInfo({
    required this.city,
    required this.maxTemp,
    required this.minTemp,
    required this.rainProbability,
    required this.condition,
    required this.fetchedAt,
    this.isFromCache = false,
  });

  WeatherInfo copyWith({bool? isFromCache}) => WeatherInfo(
        city: city,
        maxTemp: maxTemp,
        minTemp: minTemp,
        rainProbability: rainProbability,
        condition: condition,
        fetchedAt: fetchedAt,
        isFromCache: isFromCache ?? this.isFromCache,
      );

  Map<String, dynamic> toJson() => {
        'city': city,
        'maxTemp': maxTemp,
        'minTemp': minTemp,
        'rainProbability': rainProbability,
        'condition': condition,
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  /// 從快取 JSON 還原。讀出來一律先當「非快取」，是否要標成 [isFromCache]
  /// 由呼叫端（[WeatherService.getWeather]）依實際情境決定。
  factory WeatherInfo.fromJson(Map<String, dynamic> json) => WeatherInfo(
        city: json['city'].toString(),
        maxTemp: (json['maxTemp'] as num).toDouble(),
        minTemp: (json['minTemp'] as num).toDouble(),
        rainProbability: (json['rainProbability'] as num).round(),
        condition: json['condition'].toString(),
        fetchedAt: DateTime.parse(json['fetchedAt'].toString()),
        isFromCache: false,
      );
}

/// 縣市座標對照表的一列。[variants] 是用來比對長輩 `location` 自由文字的
/// 候選子字串（同時容忍「台」「臺」兩種寫法），[displayName] 是卡片上要
/// 顯示、也是 SharedPreferences 快取鍵位使用的簡短城市名。
class _CityCoord {
  final List<String> variants;
  final double lat;
  final double lon;
  final String displayName;
  const _CityCoord(this.variants, this.lat, this.lon, this.displayName);
}

/// 天氣服務——長輩端首頁天氣卡片的唯一資料來源。
///
/// 資料源與欄位刻意跟後端 AI 工具（`Uban-api/services/tools_service.py`
/// 的 `get_weather_info`）使用同一個 open-meteo 端點與欄位組合，讓 App 畫面
/// 與小嘎口頭講的天氣資訊不會互相矛盾。
class WeatherService {
  WeatherService._();

  static const Duration _cacheValidity = Duration(hours: 1);
  static const Duration _networkTimeout = Duration(seconds: 8);

  /// 台灣 22 縣市座標表。比對時採「子字串包含」，且同時列出「台」「臺」
  /// 兩種寫法的候選字串。新竹縣／嘉義縣刻意排在對應的市之前，讓「嘉義縣
  /// 民雄鄉」這種完整縣名優先命中縣、而不是被單純「嘉義」誤判成市。
  static const List<_CityCoord> _cityTable = [
    _CityCoord(['台北市', '臺北市', '台北', '臺北'], 25.03, 121.56, '台北'),
    _CityCoord(['新北市', '新北'], 25.02, 121.46, '新北'),
    _CityCoord(['桃園市', '桃園'], 24.99, 121.30, '桃園'),
    _CityCoord(['台中市', '臺中市', '台中', '臺中'], 24.14, 120.67, '台中'),
    _CityCoord(['台南市', '臺南市', '台南', '臺南'], 22.99, 120.21, '台南'),
    _CityCoord(['高雄市', '高雄'], 22.62, 120.31, '高雄'),
    _CityCoord(['基隆市', '基隆'], 25.13, 121.74, '基隆'),
    _CityCoord(['新竹縣'], 24.84, 121.02, '新竹縣'),
    _CityCoord(['新竹市', '新竹'], 24.81, 120.96, '新竹市'),
    _CityCoord(['嘉義縣'], 23.45, 120.26, '嘉義縣'),
    _CityCoord(['嘉義市', '嘉義'], 23.48, 120.45, '嘉義市'),
    _CityCoord(['苗栗縣', '苗栗'], 24.56, 120.82, '苗栗'),
    _CityCoord(['彰化縣', '彰化'], 24.05, 120.52, '彰化'),
    _CityCoord(['南投縣', '南投'], 23.96, 120.97, '南投'),
    _CityCoord(['雲林縣', '雲林'], 23.71, 120.43, '雲林'),
    _CityCoord(['屏東縣', '屏東'], 22.55, 120.55, '屏東'),
    _CityCoord(['宜蘭縣', '宜蘭'], 24.70, 121.74, '宜蘭'),
    _CityCoord(['花蓮縣', '花蓮'], 23.99, 121.60, '花蓮'),
    _CityCoord(['台東縣', '臺東縣', '台東', '臺東'], 22.76, 121.14, '台東'),
    _CityCoord(['澎湖縣', '澎湖'], 23.57, 119.58, '澎湖'),
    _CityCoord(['金門縣', '金門'], 24.43, 118.32, '金門'),
    _CityCoord(['連江縣', '馬祖', '連江'], 26.16, 119.95, '馬祖'),
  ];

  /// 完全找不到、或長輩沒填居住地時的保底值——跟後端
  /// `tools_service.py::get_weather_info` 的預設值（台北 25.03, 121.56）一致。
  static const _CityCoord _fallback = _CityCoord(['台北'], 25.03, 121.56, '台北');

  static _CityCoord _resolveCity(String? location) {
    final text = location?.trim();
    if (text != null && text.isNotEmpty) {
      for (final candidate in _cityTable) {
        if (candidate.variants.any((v) => text.contains(v))) {
          return candidate;
        }
      }
    }
    return _fallback;
  }

  /// 讀取長輩的 `location` 自由文字欄位。
  ///
  /// ⚠️ 依 `friend_service.dart::resolveMyElderId` 的既有寫法解開
  /// `{status, data, error}` 信封——必須先確認 `status == 'success'`，再從
  /// `data` 裡取欄位，不可以直接讀取頂層（`elder_profile_edit_screen.dart`
  /// 那樣讀是既有 bug，不要重蹈覆轍）。讀取欄位固定用 `location`；
  /// `residence_city` / `residence_district` 後端從未真正回傳過（半成品的
  /// 前端欄位），一律不使用。
  static Future<String?> _resolveLocationText(int userId) async {
    try {
      final result = await ApiService.getElderProfile(userId);
      if (result['status'] == 'success') {
        final data = result['data'];
        if (data is Map) {
          final loc = data['location'];
          if (loc != null && loc.toString().trim().isNotEmpty) {
            return loc.toString();
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [WeatherService] 讀取長輩居住地失敗: $e');
    }
    return null;
  }

  /// 降雨機率 → 天氣狀況文字。分級與用詞逐字取自
  /// `tools_service.py::get_weather_info`，不可各自為政。
  static String _conditionFor(int rainProbability) {
    if (rainProbability < 20) return '多雲到晴';
    if (rainProbability < 50) return '局部陣雨';
    return '陰雨綿綿';
  }

  static String _cacheKey(String city) => 'cached_weather_$city';

  static Future<WeatherInfo?> _readCache(String city) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(city));
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return WeatherInfo.fromJson(decoded);
    } catch (e) {
      debugPrint('⚠️ [WeatherService] 讀取天氣快取失敗: $e');
      return null;
    }
  }

  static Future<void> _writeCache(WeatherInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey(info.city), jsonEncode(info.toJson()));
    } catch (e) {
      debugPrint('⚠️ [WeatherService] 寫入天氣快取失敗: $e');
    }
  }

  /// 對外主入口：依 [userId] 解析長輩居住地並取得天氣。
  ///
  /// 絕對不拋出例外（全程 try/catch 包住）——這是首頁卡片直接呼叫的資料
  /// 來源，任何未預期例外都不該傳進 widget tree。失敗且無任何快取可用時
  /// 回傳 null，由畫面顯示「暫時看不到」的溫和文案。
  static Future<WeatherInfo?> getWeather(int userId) async {
    try {
      final locationText = await _resolveLocationText(userId);
      final cityCoord = _resolveCity(locationText);

      final cached = await _readCache(cityCoord.displayName);
      if (cached != null &&
          DateTime.now().difference(cached.fetchedAt) < _cacheValidity) {
        // 快取仍新鮮，直接用，不必連網。
        return cached;
      }

      try {
        final uri = Uri.parse(
          'https://api.open-meteo.com/v1/forecast'
          '?latitude=${cityCoord.lat}&longitude=${cityCoord.lon}'
          '&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max'
          '&timezone=Asia%2FTaipei',
        );
        final response = await http.get(uri).timeout(_networkTimeout);
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final daily = decoded is Map ? decoded['daily'] : null;
        if (daily is! Map) throw Exception('回應缺少 daily 欄位');

        final maxList = daily['temperature_2m_max'];
        final minList = daily['temperature_2m_min'];
        final rainList = daily['precipitation_probability_max'];
        if (maxList is! List ||
            minList is! List ||
            rainList is! List ||
            maxList.isEmpty ||
            minList.isEmpty ||
            rainList.isEmpty) {
          throw Exception('daily 資料為空');
        }

        final rain = (rainList[0] as num).round();
        final info = WeatherInfo(
          city: cityCoord.displayName,
          maxTemp: (maxList[0] as num).toDouble(),
          minTemp: (minList[0] as num).toDouble(),
          rainProbability: rain,
          condition: _conditionFor(rain),
          fetchedAt: DateTime.now(),
          isFromCache: false,
        );
        await _writeCache(info);
        return info;
      } catch (e) {
        debugPrint('⚠️ [WeatherService] 連線取得天氣失敗，改用舊資料頂替: $e');
        if (cached != null) return cached.copyWith(isFromCache: true);
        return null;
      }
    } catch (e) {
      debugPrint('⚠️ [WeatherService] getWeather 發生未預期錯誤: $e');
      return null;
    }
  }
}
