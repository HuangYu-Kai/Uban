import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// 顯示教學（若尚未看過）。
  ///
  /// 🛡️ 防呆設計（皆為刻意行為，請勿「順手」拿掉）：
  /// - SharedPreferences 讀取失敗一律視為「已經看過」直接跳過——寧可少看一次
  ///   教學，也不要讓教學擋住使用者操作 App。
  /// - 個別步驟若目標元件尚未 layout（`targetKey.currentContext == null`），
  ///   該步驟自動退化為無挖洞的置中卡片，不會拋例外或卡住。
  /// - 使用者按下實體返回鍵時，等同「跳過教學」：本函式刻意不加
  ///   `PopScope(canPop: false)`，讓 Flutter 對話框路由的預設返回鍵行為（關閉
  ///   本路由）自然生效，畫面絕不會卡在遮罩下。
  static Future<void> showIfNeeded(
    BuildContext context, {
    required String tutorialId,
    required List<TutorialStep> steps,
    double titleFontSize = 22,
    double bodyFontSize = 18,
    double buttonHeight = 56,
  }) async {
    if (steps.isEmpty) return;
    final String prefsKey = '$_prefsKeyPrefix$tutorialId';

    bool alreadyDone;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      alreadyDone = prefs.getBool(prefsKey) ?? false;
    } catch (_) {
      // 讀取失敗 → 視為已完成，直接跳過，絕不擋住使用者。
      return;
    }
    if (alreadyDone) return;

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
    // 注意：能執行到這裡代表上面的讀取一定成功過（失敗會提早 return），
    // 因此 prefs 必定已被賦值，不需要再判斷 null。
    try {
      await prefs.setBool(prefsKey, true);
    } catch (_) {}
  }
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

class _SpotlightTutorialViewState extends State<_SpotlightTutorialView> {
  int _stepIndex = 0;

  /// 目前步驟高光目標「捲動完成後」量到的螢幕座標。
  ///
  /// 之所以不在 build() 內直接同步呼叫 `_resolveTargetRect`，是因為切換步驟
  /// 時必須先把目標捲進視野（見 [_scrollTargetIntoView]），量測結果只能取自
  /// 捲動「完成之後」——捲動途中量到的座標是舊的，會讓高光框停在錯的位置。
  /// null 代表「暫時不挖洞」：可能是這一步本來就沒有目標、目標量不到、或
  /// 正在捲動中尚未量到新結果（此時退化成置中卡片，不會顯示錯誤位置的洞）。
  Rect? _targetRect;

  /// 每次切換步驟遞增一次。用來讓「使用者在捲動完成前又連按下一步」時，
  /// 前一步驟過期的非同步捲動結果不會在回來後覆蓋新步驟已經量到的結果。
  int _updateToken = 0;

  @override
  void initState() {
    super.initState();
    // 等本 widget 自己也至少畫過一影格再開始捲動／量測，做法與
    // SpotlightTutorial.showIfNeeded 開對話框前的 postFrameCallback 一致。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollTargetIntoView();
    });
  }

  void _handleNext() {
    if (_stepIndex >= widget.steps.length - 1) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _stepIndex++;
      // 換下一步先清空舊高光——舊座標對應的是上一步的目標，留著只會讓洞口
      // 停在錯的地方，不如先退化成置中卡片，等新目標捲好、量好再顯示。
      _targetRect = null;
    });
    _scrollTargetIntoView();
  }

  void _handleSkip() {
    Navigator.of(context).maybePop();
  }

  /// 把目前步驟的目標（若有）捲進視野，捲動確定完成後才量測並套用高光矩形。
  ///
  /// 三種既有防呆情境原封不動保留，任何一種都不會拋例外或卡住教學：
  /// - `targetKey == null`（純文字步驟）→ 不呼叫 ensureVisible，`_targetRect`
  ///   維持 null（見欄位註解，呼叫端已先在 setState 或初始值清空）。
  /// - `targetKey.currentContext == null`（元件尚未 layout，例如在 lazy list
  ///   裡從未被 build 過）→ ensureVisible 對這種情況無能為力，略過捲動，
  ///   直接落到下面的量測（結果同樣是 null），等同既有的「跳過高光」行為。
  /// - 目標不在任何 Scrollable 內（例如釘在 AppBar／底部導覽列上）→
  ///   `Scrollable.ensureVisible` 對此本身就是安全的立即完成 no-op。
  void _scrollTargetIntoView() {
    final int token = ++_updateToken;
    final GlobalKey? key = widget.steps[_stepIndex].targetKey;
    if (key == null) return;
    unawaited(_scrollAndMeasure(key, token));
  }

  Future<void> _scrollAndMeasure(GlobalKey key, int token) async {
    final BuildContext? targetContext = key.currentContext;
    if (targetContext != null) {
      try {
        await Scrollable.ensureVisible(
          targetContext,
          // 讓目標落在畫面中間偏上：挖洞的高光留在上半部，下方留出足夠空間
          // 給指引卡片（_buildCard 的上下半判斷才不會卡在邊界附近），也避免
          // 卡片（最高可達螢幕 55%）從下往上蓋到剛捲好的目標。
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

    setState(() => _targetRect = _resolveTargetRect(key));
  }

  /// 量測目標元件目前在螢幕上的位置與大小。
  /// 量不到（尚未 layout、已被 dispose、或不是 RenderBox）一律回傳 null，
  /// 呼叫端據此退化為無挖洞的置中卡片——見類別註解的防呆說明。
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
    final Size screenSize = MediaQuery.of(context).size;
    final Rect? holeRect = _targetRect?.inflate(8);

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
                painter: _SpotlightPainter(holeRect: holeRect),
              ),
            ),
          ),
          _buildCard(context, step, screenSize, holeRect),
        ],
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    TutorialStep step,
    Size screenSize,
    Rect? holeRect,
  ) {
    final EdgeInsets safePadding = MediaQuery.of(context).padding;
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

    // 無目標的步驟（例如歡迎詞）→ 卡片直接置中。
    if (holeRect == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: card,
        ),
      );
    }

    // 有目標 → 卡片放在挖洞的另一側，避免蓋住高光目標。
    // 洞在螢幕上半部 → 卡片放下面；洞在下半部 → 卡片放上面。
    final bool holeInTopHalf = holeRect.center.dy < screenSize.height / 2;
    return Positioned(
      left: 20,
      right: 20,
      top: holeInTopHalf ? null : safePadding.top + 24,
      bottom: holeInTopHalf ? safePadding.bottom + 24 : null,
      child: card,
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
    final bool isLastStep = stepIndex >= stepCount - 1;

    return Material(
      color: Colors.white,
      elevation: 12,
      borderRadius: BorderRadius.circular(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '第 ${stepIndex + 1} / 共 $stepCount 步',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
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
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        step.body,
                        style: TextStyle(
                          fontSize: bodyFontSize,
                          color: const Color(0xFF334155),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: buttonHeight,
                      child: OutlinedButton(
                        onPressed: onSkip,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF94A3B8)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          '跳過教學',
                          style: TextStyle(
                            fontSize: bodyFontSize,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: buttonHeight,
                      child: ElevatedButton(
                        onPressed: onNext,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF59B294),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          isLastStep ? '完成' : '下一步',
                          style: TextStyle(
                            fontSize: bodyFontSize,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
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

/// 全螢幕暗色遮罩 + 挖洞聚焦效果。
/// 用 `Path.combine(PathOperation.difference, ...)` 直接從遮罩路徑中挖掉目標
/// 區域（而非貼圖或近似做法），挖空處完全透明、直接透出下方畫面內容。
class _SpotlightPainter extends CustomPainter {
  final Rect? holeRect;
  static const double _holeRadius = 16;

  const _SpotlightPainter({required this.holeRect});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint overlayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.75);
    final Path outerPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final Rect? hole = holeRect;
    if (hole == null) {
      canvas.drawPath(outerPath, overlayPaint);
      return;
    }

    final RRect holeRRect =
        RRect.fromRectAndRadius(hole, const Radius.circular(_holeRadius));
    final Path holePath = Path()..addRRect(holeRRect);
    final Path combined =
        Path.combine(PathOperation.difference, outerPath, holePath);
    canvas.drawPath(combined, overlayPaint);

    // 高光邊框，加強聚焦感。
    final Paint borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(holeRRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.holeRect != holeRect;
  }
}
