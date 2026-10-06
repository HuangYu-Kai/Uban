import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'ui/ui.dart';

/// 長輩端「浮動 chrome」（怎麼用？膠囊、全域語音助理鈕）共用的顯示狀態。
///
/// 刻意獨立成檔，不放在 `lib/globals.dart`（通話關鍵檔）。

/// 為 true 時語音助理鈕滑出畫面（目前沒有捲動邏輯會設它；「怎麼用？」膠囊已改走
/// [ElderHelpPill] 的收合／展開，不再讀這個值）。
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

/// 捲到底的判定門檻（px）：剩餘可捲距離小於此值就視為「在最底」。
const double kElderBottomThreshold = 8;

/// 這個捲動 metrics 是否已在最底。內容根本不可捲時 extentAfter 為 0，同樣回傳 true。
bool elderScrolledToBottom(ScrollMetrics m) =>
    m.extentAfter < kElderBottomThreshold;

/// 逐分頁記錄「目前最後已知的捲到底狀態」。
///
/// 一個分頁內可能有多個垂直捲動區（外層 RefreshIndicator + 內層清單）。每個捲動區
/// （以 [source] 區分，通常傳 `notification.context`）各自記錄最新 metrics，
/// 分頁的狀態取「目前 viewport 最大」的那個——內層小清單不會誤判整頁在底部；
/// 主捲動區自己的 viewport 變小（鍵盤、安全區變動）也能照常更新。水平捲動忽略。
class ElderBottomTracker {
  // tab -> (source -> (viewport, atBottom))
  final Map<int, Map<Object, ({double viewport, bool atBottom})>> _tabs = {};

  /// 餵入一筆 metrics；水平捲動回傳 false 並忽略。
  bool update(int tab, ScrollMetrics m, [Object source = 0]) {
    if (m.axis != Axis.vertical) return false;
    final entries = _tabs.putIfAbsent(tab, () => {});
    entries[source] = (
      viewport: m.viewportDimension,
      atBottom: elderScrolledToBottom(m),
    );
    return true;
  }

  /// 該分頁最後已知是否在底部；從未收過 metrics 則為 false。
  bool atBottom(int tab) {
    final entries = _tabs[tab];
    if (entries == null || entries.isEmpty) return false;
    var best = entries.values.first;
    for (final e in entries.values) {
      if (e.viewport > best.viewport) best = e;
    }
    return best.atBottom;
  }
}

/// 「怎麼用？」膠囊：預設縮進右緣只露出半圓突起，點突起才展開。
///
/// [expanded] 由外層決定（點突起後的暫時展開，或捲到底的常駐展開）。
/// 收合 ↔ 展開以水平滑動 300ms easeOutCubic 過場，系統「移除動畫」時瞬切。
/// [visible] 為 false（聊天分頁）時整顆淡出且不可點。
class ElderHelpPill extends StatelessWidget {
  final bool expanded;
  final bool visible;

  /// 展開狀態下點膠囊（開啟說明面板）。
  final VoidCallback onTap;

  /// 收合狀態下點突起（請求展開）。
  final VoidCallback onExpand;

  const ElderHelpPill({
    super.key,
    required this.expanded,
    required this.onTap,
    required this.onExpand,
    this.visible = true,
  });

  /// 縮進時露出的寬度（不含額外的透明點擊區）。
  static const double bumpVisible = 30;

  /// 縮進時往螢幕內側多給的透明點擊區，讓點擊目標 >= 48 寬。
  static const double bumpHitExtra = 18;

  /// 膠囊整體高度（含點擊區），與 elderNavClearanceWithPill 的 56 對應。
  static const double height = 56;

  /// 展開時離右緣的距離。
  static const double expandedMargin = 16;

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 260),
        opacity: visible ? 1 : 0,
        child: SizedBox(
          height: height,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: expanded ? 1 : 0),
            duration:
                reduce ? Duration.zero : const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => CustomSingleChildLayout(
              delegate: _PillLayoutDelegate(t),
              child: _buildBody(context, t),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, double t) {
    final c = UbanColors.of(context);
    final radius = BorderRadius.circular(999);
    return Semantics(
      button: true,
      label: expanded ? '怎麼用？' : '怎麼用？，點一下展開',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: expanded ? onTap : onExpand,
        child: Padding(
          // 縮進時左側多一塊透明點擊區；展開時收掉。
          padding: EdgeInsets.only(left: bumpHitExtra * (1 - t)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: c.shadows.glass,
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
                  decoration: BoxDecoration(
                    color: c.glass,
                    borderRadius: radius,
                    border: Border.all(color: c.glassLine, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.help_outline_rounded,
                          size: 20, color: c.brandStrong),
                      // 標籤隨展開程度淡入；縮進時整段在螢幕外。
                      Opacity(
                        opacity: t,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            '怎麼用？',
                            maxLines: 1,
                            style: ubanText(16, FontWeight.w700, c.brandStrong),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 把子元件靠右、垂直置中，露出寬度在「突起」與「完整膠囊」之間內插。
class _PillLayoutDelegate extends SingleChildLayoutDelegate {
  final double t;
  const _PillLayoutDelegate(this.t);

  // 預設會把父層的緊約束原樣丟給子元件（Positioned 左右皆 0 ⇒ 子元件被撐滿整行寬）。
  // 這裡放寬成 loose，膠囊才以自身內容寬度（圖示 + 「怎麼用？」）排版。
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    const tuckedVisible = ElderHelpPill.bumpHitExtra + ElderHelpPill.bumpVisible;
    final expandedVisible = childSize.width + ElderHelpPill.expandedMargin;
    final visibleW = tuckedVisible + (expandedVisible - tuckedVisible) * t;
    return Offset(size.width - visibleW, (size.height - childSize.height) / 2);
  }

  @override
  bool shouldRelayout(_PillLayoutDelegate old) => old.t != t;
}
