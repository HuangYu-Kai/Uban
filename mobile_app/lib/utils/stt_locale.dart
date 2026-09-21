import 'package:speech_to_text/speech_to_text.dart';

/// 從裝置回報的可用語音辨識語系中，挑出最適合辨識中文的 `localeId`。
///
/// ★ 第五十一輪：不同 Android 語音辨識引擎對語系 ID 的命名不一致
/// （`zh_TW`／`zh-TW`／`cmn-Hant-TW` 都可能出現），傳入引擎沒有的 ID 不會
/// 報錯，而是靜默退回裝置預設語系（常常是英文），導致中文辨識率極低卻
/// 完全查不出原因。正確做法是列舉裝置實際回報的語系、從中挑選，而不是
/// 寫死一個猜測值：優先精準匹配 `zh_tw`／`zh-tw`，其次任何包含 `zh` 或
/// `cmn` 的語系，都找不到就回傳 `null`（交給系統預設語系）。
///
/// 這份邏輯原本只存在於 `elder_chat_tab.dart`，本輪抽成共用實作供
/// `google_assistant_overlay.dart` 一併使用，避免兩處各自維護一份幾乎
/// 相同、容易漂移的判斷。
String? pickChineseSttLocale(List<LocaleName> locales) {
  final zhTw = locales.where(
    (l) =>
        l.localeId.toLowerCase() == 'zh_tw' ||
        l.localeId.toLowerCase() == 'zh-tw',
  );
  if (zhTw.isNotEmpty) return zhTw.first.localeId;

  final anyZh = locales.where(
    (l) =>
        l.localeId.toLowerCase().contains('zh') ||
        l.localeId.toLowerCase().contains('cmn'),
  );
  if (anyZh.isNotEmpty) return anyZh.first.localeId;

  return null;
}
