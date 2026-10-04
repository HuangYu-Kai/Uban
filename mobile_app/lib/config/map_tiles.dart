import 'package:flutter/foundation.dart';

/// 地圖底圖（圖磚）設定：網址、User-Agent 套件名與版權標示。
///
/// 圖磚網址由 `--dart-define=MAP_TILE_URL=` 注入（與 `SERVER_IP` 相同模式，不寫死在程式碼裡）。
/// 未設定時退回 OpenStreetMap 公用圖磚——該服務的使用政策不允許大量／商業流量，
/// 因此**只限開發使用**，正式版務必帶上 `MAP_TILE_URL`（例如 MapTiler）。
class MapTiles {
  MapTiles._();

  /// 由 `--dart-define=MAP_TILE_URL=...` 注入；未設定為空字串。
  static const String _configuredUrl = String.fromEnvironment('MAP_TILE_URL');

  /// 未設定 `MAP_TILE_URL` 時的開發用備援（OSM 公用圖磚）。
  static const String fallbackUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// `flutter_map` 的 `TileLayer.urlTemplate`。
  static String get urlTemplate => _configuredUrl.isEmpty ? fallbackUrl : _configuredUrl;

  /// 目前是否退回開發用的 OSM 公用圖磚。
  static bool get isFallback => _configuredUrl.isEmpty;

  /// `flutter_map` 的 `TileLayer.userAgentPackageName`（圖磚服務用來識別 App）。
  static const String userAgentPackageName = 'tw.uban.family';

  /// 版權標示來源。OSM 一律標示；使用 MapTiler 時另加 MapTiler。
  static List<MapTileAttribution> get attributions => [
        const MapTileAttribution(
          label: '© OpenStreetMap contributors',
          url: 'https://www.openstreetmap.org/copyright',
        ),
        if (urlTemplate.contains('maptiler'))
          const MapTileAttribution(
            label: '© MapTiler',
            url: 'https://www.maptiler.com/copyright/',
          ),
      ];

  /// 退回 OSM 公用圖磚時在 debug console 提醒（release 版不輸出）。
  static void warnIfFallback() {
    if (kDebugMode && isFallback) {
      debugPrint(
        '⚠️ MAP_TILE_URL 未設定，地圖底圖退回 OSM 公用圖磚（僅限開發使用）。'
        '正式版請以 --dart-define=MAP_TILE_URL=<圖磚網址> 指定。',
      );
    }
  }
}

/// 單一版權標示來源：顯示文字與可點擊的連結。
class MapTileAttribution {
  const MapTileAttribution({required this.label, required this.url});

  final String label;
  final String url;
}
