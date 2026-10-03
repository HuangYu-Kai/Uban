// lib/services/location_device_status.dart
import 'package:geolocator/geolocator.dart';

/// 長輩手機「定位權限／定位服務」狀態的共用定義（長輩端回報、家屬端顯示共用）。
///
/// 狀態字串與後端 `POST /location/device-status/{elderId}` 的 `status` 欄位一致，
/// 不可自行新增或改名。純函式、無副作用，方便單元測試。
class LocationDeviceStatus {
  LocationDeviceStatus._();

  static const String ok = 'ok';
  static const String permissionDenied = 'permission_denied';
  static const String permissionDeniedForever = 'permission_denied_forever';
  static const String serviceDisabled = 'service_disabled';
  static const String foregroundOnly = 'foreground_only';

  /// 「會讓位置更新不了」的狀態；`null`、`ok` 與未知字串（例如日後後端新增的值）
  /// 一律視為沒有問題，不顯示警示。
  static bool isProblem(Object? status) =>
      status == permissionDenied ||
      status == permissionDeniedForever ||
      status == serviceDisabled ||
      status == foregroundOnly;

  /// 由裝置實際狀態換算成回報用字串。
  ///
  /// - 定位服務關閉 → `service_disabled`（優先於權限）
  /// - `deniedForever` → `permission_denied_forever`；`denied` → `permission_denied`
  /// - `whileInUse` → `foreground_only`（Android 與 iOS 皆代表背景時無法回報）
  /// - `always` → `ok`
  /// - `unableToDetermine`（Web 等無法判斷的平台）→ `ok`，不誤報
  static String fromDevice({
    required bool serviceEnabled,
    required LocationPermission permission,
  }) {
    if (!serviceEnabled) return serviceDisabled;
    switch (permission) {
      case LocationPermission.deniedForever:
        return permissionDeniedForever;
      case LocationPermission.denied:
        return permissionDenied;
      case LocationPermission.whileInUse:
        return foregroundOnly;
      case LocationPermission.always:
      case LocationPermission.unableToDetermine:
        return ok;
    }
  }

  /// 家屬首頁卡片用的簡短警示（一行）。非問題狀態回傳 `null`。
  static String? shortLabel(Object? status) {
    switch (status) {
      case serviceDisabled:
        return '⚠️ 長輩手機定位功能已關閉';
      case permissionDenied:
      case permissionDeniedForever:
        return '⚠️ 長輩手機未允許定位';
      case foregroundOnly:
        return '⚠️ 長輩手機只允許使用 App 時定位';
    }
    return null;
  }

  /// 家屬地圖畫面用的完整說明（含該怎麼做）。非問題狀態回傳 `null`。
  static String? familyMessage(Object? status) {
    switch (status) {
      case serviceDisabled:
        return '長輩手機的定位功能已關閉，暫時無法更新位置。請協助長輩打開手機的定位。';
      case permissionDenied:
      case permissionDeniedForever:
        return '長輩手機尚未允許 Uban 使用位置，請協助長輩到手機設定開啟。';
      case foregroundOnly:
        return '長輩手機只允許「使用 App 時」定位，App 不在畫面上時無法回報。請協助長輩改為「一律允許」。';
    }
    return null;
  }

  /// 「（N 分鐘前回報）」；[at] 為 null 回傳空字串。超過 60 分鐘改用小時、
  /// 超過 24 小時改用天，避免出現「（3000 分鐘前回報）」。
  static String reportedAgoText(DateTime? at, {DateTime? now}) {
    if (at == null) return '';
    final diff = (now ?? DateTime.now()).difference(at);
    if (diff.inMinutes < 1) return '（剛剛回報）';
    if (diff.inMinutes < 60) return '（${diff.inMinutes} 分鐘前回報）';
    if (diff.inHours < 24) return '（${diff.inHours} 小時前回報）';
    return '（${diff.inDays} 天前回報）';
  }
}
