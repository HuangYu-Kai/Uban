/// 顯示用文字整理（只改畫面上的呈現，不改後端資料）。
library;

// emoji 主要區段＋變體選擇符／零寬連接字／膚色修飾，連同前後多餘空白一起去掉。
final RegExp _emoji = RegExp(
  r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}'
  r'\u{FE0E}\u{FE0F}\u{200D}\u{20E3}\u{E0020}-\u{E007F}]',
  unicode: true,
);

/// 去掉字串裡的彩色 emoji（例如提醒標題「下午補充溫開水 💧」→「下午補充溫開水」）。
/// 去完若變成空字串就回傳原字串，避免整個標題消失。
String stripEmoji(String text) {
  final cleaned =
      text.replaceAll(_emoji, '').replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  return cleaned.isEmpty ? text.trim() : cleaned;
}
