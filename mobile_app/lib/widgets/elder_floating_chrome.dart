import 'dart:async';

import 'package:flutter/foundation.dart';

/// 長輩端「浮動 chrome」（怎麼用？膠囊、全域語音助理鈕）共用的顯示狀態。
///
/// 刻意獨立成檔，不放在 `lib/globals.dart`（通話關鍵檔）。

/// 往下捲動時為 true：「怎麼用？」膠囊與語音助理鈕一起滑出畫面。
final ValueNotifier<bool> elderFloatingChromeHidden = ValueNotifier<bool>(false);

/// 目前停留在聊天分頁時為 true：兩顆浮動鈕都不顯示（避免蓋住輸入列）。
final ValueNotifier<bool> elderChatTabActive = ValueNotifier<bool>(false);

/// 新手導覽遮罩顯示中的計數（>0 即有遮罩）；語音助理鈕此時必須讓位。
final ValueNotifier<int> tutorialActiveDepth = ValueNotifier<int>(0);

/// 在 initState / dispose 內安全地調整 [tutorialActiveDepth]
/// （延後到 microtask，避免 build / unmount 期間通知 listener 觸發 setState 例外）。
void adjustTutorialActiveDepth(int delta) {
  scheduleMicrotask(() {
    final next = tutorialActiveDepth.value + delta;
    tutorialActiveDepth.value = next < 0 ? 0 : next;
  });
}
