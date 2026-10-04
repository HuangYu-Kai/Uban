import 'package:flutter/material.dart';

/// 家屬端「警報卡片」的顯示文案與位置欄位解析（首頁「最新警示」＋警示中心共用）。
///
/// ★ 2026-10-02：原本 `home_alert_preview_card.dart` 與 `alert_center_screen.dart`
///   各自內嵌一份 if/else 文案，預設分支（含 `sos_voice` 與任何未知型別）一律寫成
///   「🚨 跌倒緊急警報／監視機偵測到長輩疑似跌倒」——違反 G196：`sos_voice`（長輩開口
///   對小嘎求救）沒有監視畫面，不可寫成跌倒、也不可叫家屬去看監視畫面。這裡把兩處
///   的文案集中成一份，並讓未知型別退回中性的「異常狀況」，不再宣稱跌倒。
///
/// ⚠️ 與 `cctv_alert_notification.dart::_typeLabel／_resolveTitle／_resolveBody`
///   （系統通知，會直接在 FCM 背景 isolate 執行）、`family_main_screen.dart::
///   _alertTypeLabel`（前景彈窗）是三份**刻意分開**的對照表，新增警報型別時要一起檢查
///   （見 cctv_alert_notification.dart 內 `_typeLabel` 的說明）。本檔只管「卡片」。
class AlertDisplay {
  AlertDisplay._();

  /// 長輩對小嘎開口求救（沒有監視機、`device_id` 為哨兵值 0）。
  static const String sosVoice = 'sos_voice';

  static bool isSos(String type) => type == sosVoice;

  /// 卡片標題（含 emoji 前綴）。未知型別退回中性「異常狀況」。
  static String title(String type) {
    switch (type) {
      case sosVoice:
        return '🆘 長輩開口求救';
      case 'fall':
        return '🚨 跌倒緊急警報';
      case 'crawl':
        return '⚠️ 疑似爬行警報';
      case 'lying_down':
        return '⚠️ 久躺未起警報';
      case 'prolonged_inactivity':
        return '⚠️ 長時間無活動警報';
      default:
        return '⚠️ 異常狀況警報';
    }
  }

  /// 即時警報內文。[confText] 為已格式化的信心度字串（例如 ` (信心度 87%)`），
  /// `sos_voice` 不是影像偵測，沒有信心度，一律忽略。
  static String liveDesc(String type, {String confText = ''}) {
    switch (type) {
      case sosVoice:
        return '長輩剛透過語音助理（小嘎）開口求救，請立即聯繫確認狀況。';
      case 'fall':
        return '監視機偵測到長輩疑似跌倒$confText，請立即確認！';
      case 'crawl':
        return '監視機偵測到長輩異常爬行動作$confText，請多加留意。';
      case 'lying_down':
        return '長輩在監視區域久躺不起$confText，建議關懷確認。';
      case 'prolonged_inactivity':
        return '長輩活動量異常偏低$confText，請留意長輩身體狀況。';
      default:
        return '長輩出現異常狀況$confText，請盡快確認。';
    }
  }

  /// 歷史（持久化）警報內文。
  static String pastDesc(String type) {
    switch (type) {
      case sosVoice:
        return '長輩曾透過語音助理（小嘎）開口求救。';
      case 'fall':
        return '監視機曾偵測到長輩疑似跌倒。';
      case 'crawl':
        return '監視機曾偵測到長輩異常爬行動作。';
      case 'lying_down':
        return '長輩曾在監視區域久躺不起。';
      case 'prolonged_inactivity':
        return '長輩曾出現活動量異常偏低。';
      default:
        return '長輩曾出現異常狀況。';
    }
  }

  /// 卡片圖示：求救用 SOS 圖示，其餘維持原本的警示三角。
  static IconData icon(String type) =>
      isSos(type) ? Icons.sos_rounded : Icons.warning_amber_rounded;

  /// 解析警報上「長輩最後位置」的經緯度。
  ///
  /// 後端只在 `sos_voice` 且長輩有開位置分享、有最近一筆定位時才會帶：Socket／REST 是
  /// 數字（`latitude`／`longitude`），FCM data 是字串，所以一律先 `toString()` 再解析。
  /// 兩個欄位任一缺漏、無法解析、非有限值或超出經緯度範圍都回傳 `null`——呼叫端據此
  /// 「完全不顯示位置相關 UI」，不補假提示。
  static ({double lat, double lng})? parseLocation(Map? m) {
    if (m == null) return null;
    final double? lat = double.tryParse('${m['latitude'] ?? ''}');
    final double? lng = double.tryParse('${m['longitude'] ?? ''}');
    if (lat == null || lng == null) return null;
    if (!lat.isFinite || !lng.isFinite) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return (lat: lat, lng: lng);
  }

  /// 解析位置時間（Socket／REST 為 `location_at`，FCM 為 `locationAt`，ISO UTC 帶 Z）。
  /// 回傳本地時間；缺漏或無法解析回傳 `null`。
  static DateTime? parseLocationAt(Map? m) {
    if (m == null) return null;
    final raw = (m['location_at'] ?? m['locationAt'])?.toString() ?? '';
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  /// 「最後位置：N 分鐘前」。[at] 為 `null`（後端沒給位置時間）時回傳 `null`，
  /// 呼叫端就不顯示這一行，不捏造時間。[now] 僅供測試注入。
  static String? lastLocationText(DateTime? at, {DateTime? now}) {
    if (at == null) return null;
    final diff = (now ?? DateTime.now()).difference(at);
    // 裝置時鐘略慢於伺服器時，差值可能為負，一律當作「剛剛」。
    if (diff.inMinutes < 1) return '最後位置：剛剛';
    if (diff.inMinutes < 60) return '最後位置：${diff.inMinutes} 分鐘前';
    if (diff.inHours < 24) return '最後位置：${diff.inHours} 小時前';
    return '最後位置：${diff.inDays} 天前';
  }
}
