import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'elder_floating_chrome.dart';

import '../theme/app_theme.dart';
import '../theme/uban_motion.dart';
import 'elder_overlay_button.dart';
import 'ui/uban_text.dart';

/// 單一教學步驟的定義。
///
/// [targetKey] 是要被「挖洞聚焦」的目標元件的 GlobalKey；若為 null，代表這一步
/// 沒有特定目標（例如整個教學的「歡迎」開場步驟），畫面上不挖洞，指引卡片直接置中。
class TutorialStep {
  final GlobalKey? targetKey;
  final String title;
  final String body;

  const TutorialStep({
    this.targetKey,
    required this.title,
    required this.body,
  });
}

/// 可重用的步驟式高光新手指引元件。
///
/// 用法：
/// ```dart
/// SpotlightTutorial.showIfNeeded(
///   context,
///   tutorialId: 'elder_home_v1',
///   steps: [
///     TutorialStep(title: '歡迎使用', body: '這裡會一步步帶您認識畫面'),
///     TutorialStep(targetKey: someKey, title: '這裡可以...', body: '說明文字'),
///   ],
/// );
/// ```
///
/// 內部行為：讀取 SharedPreferences 的 `tutorial_done_<tutorialId>`，已經看過
/// 就直接 return、什麼都不顯示；沒看過才顯示，使用者按完「完成」或「跳過教學」
/// （或按下實體返回鍵）之後，才會寫入完成旗標。
///
/// ⚠️ 這個元件是給**長輩端與家屬端共用**的（家屬端由第二階段接手），因此字級／
/// 按鈕高度全部開放參數覆寫，預設值採用長輩端規格（大字、大按鈕）。
class SpotlightTutorial {
  SpotlightTutorial._();

  static const String _prefsKeyPrefix = 'tutorial_done_';
  static const String prefsKeyAllDismissed = 'elder_all_tutorials_dismissed';

  /// 顯示教學（若尚未看過且未被全域跳過）。
  ///
  /// 🛡️ 防呆設計（皆為刻意行為，請勿「順手」拿掉）：
  /// - SharedPreferences 讀取失敗一律視為「已經看過」直接跳過——寧可少看一次
  ///   教學，也不要讓教學擋住使用者操作 App。
  /// - 使用者按過「跳過教學」後，會設定全域旗標 `elder_all_tutorials_dismissed`，
  ///   徹底杜絕首頁與後續分頁連環彈窗轟炸長輩的體驗災難。
  /// - 個別步驟若目標元件尚未 layout（`targetKey.currentContext == null`），
  ///   該步驟自動退化為無挖洞的置中卡片，不會拋例外或卡住。
  /// - 使用者按下實體返回鍵時，等同「跳過教學」：本函式刻意不加
  ///   `PopScope(canPop: false)`，讓 Flutter 對話框路由的預設返回鍵行為（關閉
  ///   本路由）自然生效，畫面絕不會卡在遮罩下。
  static Future<void> showIfNeeded(
    BuildContext context, {
    required String tutorialId,
    required List<TutorialStep> steps,
    double titleFontSize = 24,
    double bodyFontSize = 18,
    double buttonHeight = 56,
  }) async {
    if (steps.isEmpty) return;
    final String prefsKey = '$_prefsKeyPrefix$tutorialId';

    bool alreadyDone = false;
    bool allDismissed = false;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      allDismissed = prefs.getBool(prefsKeyAllDismissed) ?? false;
      alreadyDone = prefs.getBool(prefsKey) ?? false;
    } catch (_) {
      // 讀取失敗 → 視為已完成，直接跳過，絕不擋住使用者。
      return;
    }
    if (allDismissed || alreadyDone) return;

    // 確保至少經過一次完整 layout，量測目標元件位置才會準確
    // （呼叫端可能在 setState 之後緊接著呼叫本函式，此時新畫面尚未 layout 完）。
    final Completer<void> frameCompleter = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!frameCompleter.isCompleted) frameCompleter.complete();
    });
    await frameCompleter.future;

    if (!context.mounted) return;

    await showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      barrierLabel: tutorialId,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return _SpotlightTutorialView(
          steps: steps,
          titleFontSize: titleFontSize,
          bodyFontSize: bodyFontSize,
          buttonHeight: buttonHeight,
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );

    // 走完全部步驟、按「跳過教學」、或被實體返回鍵關閉，都算「已顯示過」，
    // 不再重複打擾使用者。寫入失敗就算了（最差情況下次再顯示一次，不影響功能）。
    try {
      await prefs.setBool(prefsKey, true);
    } catch (_) {}
  }

  /// 強制重播教學（用於「我的」分頁中的【重新觀看新手導覽】後悔藥入口）。
  static Future<void> showForce(
    BuildContext context, {
    required String tutorialId,
    required List<TutorialStep> steps,
    double titleFontSize = 24,
    double bodyFontSize = 18,
    double buttonHeight = 56,
  }) async {
    if (steps.isEmpty) return;
    final Completer<void> frameCompleter = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!frameCompleter.isCompleted) frameCompleter.complete();
    });
    await frameCompleter.future;

    if (!context.mounted) return;

    await showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      barrierLabel: tutorialId,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return _SpotlightTutorialView(
          steps: steps,
          titleFontSize: titleFontSize,
          bodyFontSize: bodyFontSize,
          buttonHeight: buttonHeight,
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  /// 重設所有教學進度（可配合重播或設定重置使用）。
  static Future<void> resetAllTutorials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKeyAllDismissed, false);
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefsKeyPrefix)).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}

/// 以 [UbanMotion.tutorialSpring]（設計稿 `Spring(.75, 300)`）驅動的單一數值。
class _SpringValue {
  _SpringValue(TickerProvider vsync, double initial)
      : controller = AnimationController.unbounded(vsync: vsync, value: initial);

  final AnimationController controller;

  double get value => controller.value;

  void to(double target, {required bool snap}) {
    if (snap) {
      controller.stop();
      controller.value = target;
      return;
    }
    controller.animateWith(SpringSimulation(
      UbanMotion.tutorialSpring,
      controller.value,
      target,
      controller.velocity,
    ));
  }

  void dispose() => controller.dispose();
}

class _SpotlightTutorialView extends StatefulWidget {
  final List<TutorialStep> steps;
  final double titleFontSize;
  final double bodyFontSize;
  final double buttonHeight;

  const _SpotlightTutorialView({
    required this.steps,
    required this.titleFontSize,
    required this.bodyFontSize,
    required this.buttonHeight,
  });

  @override
  State<_SpotlightTutorialView> createState() =>
      _SpotlightTutorialViewState();
}

class _SpotlightTutorialViewState extends State<_SpotlightTutorialView>
    with TickerProviderStateMixin {
  int _stepIndex = 0;

  /// 目前步驟高光目標「捲動完成後」量到的螢幕座標（已外擴 8）。
  ///
  /// 之所以不在 build() 內直接同步量測，是因為切換步驟時必須先把目標捲進視野
  /// （見 [_scrollTargetIntoView]），量測結果只能取自捲動「完成之後」。
  /// null 代表「沒有洞」：這一步本來就沒有目標、或目標量不到（退化成置中卡片）。
  /// 換到「有目標」的下一步時**不清空**舊值——挖洞要像設計稿一樣以彈簧從上一個
  /// 目標直接移到新目標，而不是先縮成一點再長出來；新結果量到前卡片位置沿用舊的。
  Rect? _targetRect;

  /// 每次切換步驟遞增一次。用來讓「使用者在捲動完成前又連按下一步」時，
  /// 前一步驟過期的非同步捲動結果不會在回來後覆蓋新步驟已經量到的結果。
  int _updateToken = 0;

  // 洞口的 x／y／w／h 各自一條彈簧（同設計稿 hs[0..3]）。
  late final _SpringValue _hx;
  late final _SpringValue _hy;
  late final _SpringValue _hw;
  late final _SpringValue _hh;
  bool _springsReady = false;
  late final Listenable _holeListenable;

  @override
  void initState() {
    super.initState();
    adjustTutorialActiveDepth(1);
    _hx = _SpringValue(this, 0);
    _hy = _SpringValue(this, 0);
    _hw = _SpringValue(this, 0);
    _hh = _SpringValue(this, 0);
    _holeListenable = Listenable.merge(
        [_hx.controller, _hy.controller, _hw.controller, _hh.controller]);
    // 等本 widget 自己也至少畫過一影格再開始捲動／量測，做法與
    // SpotlightTutorial.showIfNeeded 開對話框前的 postFrameCallback 一致。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollTargetIntoView();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_springsReady) {
      _springsReady = true;
      // 初始：洞口是螢幕正中央的一個點，之後才彈開到第一個目標。
      final Size s = MediaQuery.sizeOf(context);
      _hx.to(s.width / 2, snap: true);
      _hy.to(s.height / 2, snap: true);
    }
  }

  @override
  void dispose() {
    adjustTutorialActiveDepth(-1);
    _hx.dispose();
    _hy.dispose();
    _hw.dispose();
    _hh.dispose();
    super.dispose();
  }

  /// 把洞口彈到 [rect]；null 代表縮回螢幕中央的一個點（無目標的步驟）。
  void _applyHole(Rect? rect) {
    final Size s = MediaQuery.sizeOf(context);
    final bool snap = reduceMotion(context);
    final Rect r = rect ?? Rect.fromLTWH(s.width / 2, s.height / 2, 0, 0);
    _hx.to(r.left, snap: snap);
    _hy.to(r.top, snap: snap);
    _hw.to(r.width, snap: snap);
    _hh.to(r.height, snap: snap);
  }

  void _handleNext() {
    if (_stepIndex >= widget.steps.length - 1) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _stepIndex++;
      // 無目標的步驟：舊洞口立刻失效（卡片置中、洞縮成點）。
      // 有目標的步驟：保留舊洞口位置直到新目標捲好、量好（見 _targetRect 註解）。
      if (widget.steps[_stepIndex].targetKey == null) _targetRect = null;
    });
    _scrollTargetIntoView();
  }

  void _handleSkip() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SpotlightTutorial.prefsKeyAllDismissed, true);
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  /// 把目前步驟的目標（若有）捲進視野，捲動確定完成後才量測並套用高光矩形。
  ///
  /// 三種既有防呆情境原封不動保留，任何一種都不會拋例外或卡住教學：
  /// - `targetKey == null`（純文字步驟）→ 不呼叫 ensureVisible，不挖洞。
  /// - `targetKey.currentContext == null`（元件尚未 layout，例如在 lazy list
  ///   裡從未被 build 過）→ 略過捲動，量測結果同樣是 null，退化為置中卡片。
  /// - 目標不在任何 Scrollable 內（例如釘在 AppBar／底部導覽列上）→
  ///   `Scrollable.ensureVisible` 對此本身就是安全的立即完成 no-op。
  void _scrollTargetIntoView() {
    final int token = ++_updateToken;
    final GlobalKey? key = widget.steps[_stepIndex].targetKey;
    if (key == null) {
      _applyHole(null);
      return;
    }
    unawaited(_scrollAndMeasure(key, token));
  }

  Future<void> _scrollAndMeasure(GlobalKey key, int token) async {
    final BuildContext? targetContext = key.currentContext;
    if (targetContext != null) {
      try {
        await Scrollable.ensureVisible(
          targetContext,
          // 讓目標落在畫面中間偏上：挖洞的高光留在上半部，下方留出足夠空間
          // 給指引卡片，也避免卡片（最高可達螢幕 55%）蓋到剛捲好的目標。
          alignment: 0.3,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } catch (_) {
        // 捲動途中發生例外（例如過程中該 Scrollable 被移除）→ 視為無法捲動，
        // 忽略即可，不中斷教學，仍走下面的量測與既有 fallback。
      }
    }

    if (!mounted) return; // widget 可能在 await 期間被 dispose。
    if (token != _updateToken) return; // 捲動完成前使用者已切到別的步驟，結果過期。

    final Rect? measured = _resolveTargetRect(key)?.inflate(8);
    setState(() => _targetRect = measured);
    _applyHole(measured);
  }

  /// 量測目標元件目前在螢幕上的位置與大小。
  /// 量不到（尚未 layout、已被 dispose、或不是 RenderBox）一律回傳 null，
  /// 呼叫端據此退化為無挖洞的置中卡片。
  Rect? _resolveTargetRect(GlobalKey? key) {
    if (key == null) return null;
    final BuildContext? targetContext = key.currentContext;
    if (targetContext == null) return null;
    final RenderObject? renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox) return null;
    if (!renderObject.attached || !renderObject.hasSize) return null;
    try {
      final Offset topLeft = renderObject.localToGlobal(Offset.zero);
      return topLeft & renderObject.size;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TutorialStep step = widget.steps[_stepIndex];
    final Size screenSize = MediaQuery.sizeOf(context);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // 全螢幕遮罩：吃掉所有點擊（包含被挖洞的目標本身——高光只是視覺聚焦，
          // 不是可互動區），只有下方指引卡片上的按鈕才能互動。
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: CustomPaint(
                size: Size.infinite,
                painter: _SpotlightPainter(
                  x: _hx.controller,
                  y: _hy.controller,
                  w: _hw.controller,
                  h: _hh.controller,
                  repaint: _holeListenable,
                ),
              ),
            ),
          ),
          _buildCard(context, step, screenSize),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, TutorialStep step, Size screenSize) {
    final EdgeInsets safePadding = MediaQuery.paddingOf(context);
    final Rect? hole = _targetRect;
    final card = _TutorialCard(
      step: step,
      stepIndex: _stepIndex,
      stepCount: widget.steps.length,
      titleFontSize: widget.titleFontSize,
      bodyFontSize: widget.bodyFontSize,
      buttonHeight: widget.buttonHeight,
      maxHeight: screenSize.height * 0.55,
      onNext: _handleNext,
      onSkip: _handleSkip,
    );

    // 無目標 → 置中；有目標 → 放在洞的另一側（洞在上半部卡片放下面，反之亦然）。
    // 以 AnimatedAlign 讓卡片在三個位置間以彈性曲線移動（設計稿 top/bottom 450ms）。
    final Alignment alignment = hole == null
        ? Alignment.center
        : (hole.center.dy < screenSize.height / 2
            ? Alignment.bottomCenter
            : Alignment.topCenter);

    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, safePadding.top + 24, 16, safePadding.bottom + 28),
        child: AnimatedAlign(
          alignment: alignment,
          duration: reduceMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 450),
          curve: const Cubic(.34, 1.3, .64, 1),
          child: card,
        ),
      ),
    );
  }
}

class _TutorialCard extends StatelessWidget {
  final TutorialStep step;
  final int stepIndex;
  final int stepCount;
  final double titleFontSize;
  final double bodyFontSize;
  final double buttonHeight;
  final double maxHeight;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _TutorialCard({
    required this.step,
    required this.stepIndex,
    required this.stepCount,
    required this.titleFontSize,
    required this.bodyFontSize,
    required this.buttonHeight,
    required this.maxHeight,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final bool isLastStep = stepIndex >= stepCount - 1;
    final double btnFont = bodyFontSize < 18 ? 18 : bodyFontSize;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (int i = 0; i < stepCount; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: i == stepIndex ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == stepIndex ? c.brand : c.surface3,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '第 ${stepIndex + 1}／共 $stepCount 步',
                    style: ubanText(15, FontWeight.w600, c.text3),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        step.title,
                        style: ubanText(titleFontSize, FontWeight.w900, c.text,
                            height: 1.3),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        step.body,
                        style: ubanText(bodyFontSize, FontWeight.w500, c.text2,
                            height: 1.55),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 設計稿 .acts：1fr 1.4fr。
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: OverlayButton(
                      label: '跳過教學',
                      filled: false,
                      fontSize: btnFont,
                      minHeight: buttonHeight,
                      onPressed: onSkip,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 7,
                    child: OverlayButton(
                      label: isLastStep ? '完成' : '下一步',
                      fontSize: btnFont,
                      minHeight: buttonHeight,
                      onPressed: onNext,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 全螢幕 75% 黑遮罩 + 挖洞聚焦（圓角 20）＋ 3px 白框。
/// 用單一 evenOdd 路徑（外框矩形 + 洞口圓角矩形）從遮罩中挖掉目標
/// 區域，挖空處完全透明、直接透出下方畫面內容。洞口數值來自四條彈簧。
class _SpotlightPainter extends CustomPainter {
  final AnimationController x, y, w, h;
  static const double _holeRadius = 20;

  _SpotlightPainter({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint overlayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.75);
    final Rect fullRect = Rect.fromLTWH(0, 0, size.width, size.height);

    // 彈簧過衝時寬高可能短暫為負；與設計稿一致，寬度 ≤ 8 視為沒有洞。
    final double hw = w.value;
    final double hh = h.value;
    if (hw <= 8 || hh <= 8) {
      canvas.drawRect(fullRect, overlayPaint);
      return;
    }

    final RRect holeRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x.value, y.value, hw, hh),
        const Radius.circular(_holeRadius));
    // 單一路徑 + evenOdd：外框矩形與洞口重疊處被視為「外」而不填色，洞內不蓋黑。
    final Path overlayPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(fullRect)
      ..addRRect(holeRRect);
    canvas.drawPath(overlayPath, overlayPaint);

    // 白框：CSS border 畫在盒內，所以把筆畫往內縮半個線寬。
    final Paint ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(holeRRect.deflate(1.5), ringPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) => false;
}
