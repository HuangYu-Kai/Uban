import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../widgets/ui/ui.dart';

/// 長輩端「和小嘎聊天」換新設計用到的純呈現元件。
///
/// 全部不碰網路、錄音、TTS、SharedPreferences：行為（送出、長按錄音、重聽）都由
/// `ElderChatScreen` 以回呼傳入，所以可以單獨 pump 測試版面與字級。

// ───────────────────────── 國語／台語分段（.langseg）─────────────────────────

/// 設計稿 `.langseg`：surface2 膠囊、padding 4、按鈕 padding 8×14、字 16/700。
/// 長輩端字級下限 18、按鈕最小高 48，所以字放到 18、高 48。傳入的 [key] 掛在整個元件上。
class ChatLangSeg extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  const ChatLangSeg({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            Semantics(
              button: true,
              selected: i == index,
              label: labels[i],
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: reduceMotion(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  constraints: const BoxConstraints(minHeight: 48, minWidth: 64),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index ? c.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: i == index
                        ? const [
                            BoxShadow(
                              color: Color.fromRGBO(0, 0, 0, .08),
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    style: ubanText(18, FontWeight.w700,
                        i == index ? c.brandStrong : c.text2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────── 泡泡（.bub）─────────────────────────

/// 設計稿 `.bub`：最大寬 84%、padding 14×18、圓角 24、尾角 8。
/// ai：surface 底＋卡片陰影、靠左；me：brandFill 底、靠右，無陰影。
class ChatBubbleFrame extends StatelessWidget {
  final bool isUser;
  final Widget child;

  const ChatBubbleFrame({super.key, required this.isUser, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return LayoutBuilder(builder: (context, box) {
      return Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: box.maxWidth * .84),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: isUser ? c.brandFill : c.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(24),
                topRight: const Radius.circular(24),
                bottomLeft: Radius.circular(isUser ? 24 : 8),
                bottomRight: Radius.circular(isUser ? 8 : 24),
              ),
              boxShadow: isUser ? null : c.shadows.card,
            ),
            child: child,
          ),
        ),
      );
    });
  }
}

/// AI 泡泡底部的「再聽一次」（設計稿 `.bub .replay`）。點擊範圍高 ≥48。
/// [languageLabel] 是當時 TTS 用的語系（國語／台語），保留原本的語系紀錄。
class ChatReplayButton extends StatelessWidget {
  final bool isPlaying;
  final String languageLabel;
  final VoidCallback onTap;

  const ChatReplayButton({
    super.key,
    required this.isPlaying,
    required this.languageLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Semantics(
            button: true,
            label: isPlaying ? '停止播放' : '再聽一次',
            excludeSemantics: true,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.volume_up_rounded,
                      size: 24,
                      color: c.brandStrong,
                    ),
                    const SizedBox(width: 6),
                    Text(isPlaying ? '停止播放' : '再聽一次',
                        style: ubanText(18, FontWeight.w700, c.brandStrong)),
                  ],
                ),
              ),
            ),
          ),
          Text(languageLabel, style: ubanText(18, FontWeight.w400, c.text3)),
        ],
      ),
    );
  }
}

/// 設計稿 `.typing`：三顆 text3 色小點上下跳。reduceMotion 時不跳。
class ChatThinkingDots extends StatefulWidget {
  const ChatThinkingDots({super.key});

  @override
  State<ChatThinkingDots> createState() => _ChatThinkingDotsState();
}

class _ChatThinkingDotsState extends State<ChatThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && !reduceMotion(context)) {
      _started = true;
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                margin: EdgeInsets.only(right: i == 2 ? 0 : 5),
                width: 9,
                height: 9,
                transform: Matrix4.translationValues(0, _dotLift(i), 0),
                decoration: BoxDecoration(
                  color: c.text3.withValues(alpha: _dotOpacity(i)),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ui.css @keyframes ty：0/60/100% 靜止（透明度 .5），30% 上浮 5px 並全亮；
  // 三顆各延遲 0、.15s、.3s（週期 1.2s）。
  double _phase(int i) => ((_ctrl.value * 1200 - i * 150) % 1200) / 1200;

  double _dotLift(int i) {
    final p = _phase(i);
    if (p >= .6) return 0;
    return -5 * math.sin(p / .6 * math.pi);
  }

  double _dotOpacity(int i) {
    final p = _phase(i);
    if (p >= .6) return .5;
    return .5 + .5 * math.sin(p / .6 * math.pi);
  }
}

// ───────────────────────── 輸入列（.chatbar）─────────────────────────

/// 設計稿 `.chatbar`：鍵盤／麥克風圓鈕（64）＋「按住　說話」大膠囊（高 ≥64）。
/// 文字模式則是膠囊文字框＋送出圓鈕。長按錄音與送出的實際動作都由呼叫端提供。
class ChatInputBar extends StatelessWidget {
  /// true＝語音（按住說話），false＝鍵盤輸入。
  final bool voiceMode;
  final bool isListening;
  final VoidCallback onToggleMode;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final TextEditingController controller;
  final VoidCallback onSend;

  /// 距離螢幕底的留白（含浮動導覽列）。
  final double bottomPadding;

  /// 新手指引高光目標：掛在鍵盤／麥克風圓鈕與輸入區上。
  final Key? toggleKey;
  final Key? inputAreaKey;

  const ChatInputBar({
    super.key,
    required this.voiceMode,
    required this.isListening,
    required this.onToggleMode,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.controller,
    required this.onSend,
    required this.bottomPadding,
    this.toggleKey,
    this.inputAreaKey,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, bottomPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 切換：語音 / 鍵盤
          Semantics(
            button: true,
            label: voiceMode ? '改用打字' : '改用語音',
            excludeSemantics: true,
            child: PressableScale(
              onTap: onToggleMode,
              child: Container(
                key: toggleKey,
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.surface,
                  boxShadow: c.shadows.card,
                ),
                child: Icon(
                  voiceMode ? Icons.keyboard_rounded : Icons.mic_none_rounded,
                  color: c.brandStrong,
                  size: 28,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: KeyedSubtree(
              key: inputAreaKey,
              child: voiceMode ? _holdToTalk(context, c) : _textField(c),
            ),
          ),
          if (!voiceMode) ...[
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: '送出',
              excludeSemantics: true,
              child: PressableScale(
                onTap: onSend,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.brandFill,
                  ),
                  child: Icon(Icons.send_rounded, color: c.onBrand, size: 28),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 「按住　說話」：設計稿 `.talk`（按住時放大 1.04、底色換 brandStrong、字色換 bg）。
  Widget _holdToTalk(BuildContext context, UbanColors c) {
    final reduce = reduceMotion(context);
    final dur = reduce ? Duration.zero : const Duration(milliseconds: 300);
    return GestureDetector(
      onLongPressStart: (_) => onHoldStart(),
      onLongPressEnd: (_) => onHoldEnd(),
      onLongPressCancel: onHoldEnd,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: isListening ? '放開送出' : '按住說話',
        excludeSemantics: true,
        child: AnimatedScale(
          scale: isListening ? 1.04 : 1,
          duration: dur,
          curve: UbanMotion.springBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isListening ? c.brandStrong : c.brandFill,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic_rounded,
                    size: 28, color: isListening ? c.bg : c.onBrand),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    isListening ? '放開　送出' : '按住　說話',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ubanText(21, FontWeight.w700,
                        isListening ? c.bg : c.onBrand),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _textField(UbanColors c) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(32),
        boxShadow: c.shadows.card,
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        minLines: 1,
        maxLines: 4,
        autofocus: true,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => onSend(),
        style: ubanText(20, FontWeight.w600, c.text),
        decoration: InputDecoration(
          hintText: '想跟小嘎說什麼…',
          hintStyle: ubanText(19, FontWeight.w400, c.text3),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
      ),
    );
  }
}

// ───────────────────────── 邊緣漸層（標題下、輸入列上）─────────────────────────

/// 設計稿 `.chat-head::after`／`.chatbar::before`：泡泡接近標題或輸入列時淡出到背景色，
/// 不再從後方穿透。[atTop] 為 true 時由背景色漸層到透明（貼在清單上緣），否則反過來
/// （貼在清單下緣）。不吃觸控。
class ChatEdgeFade extends StatelessWidget {
  final bool atTop;
  final double height;

  const ChatEdgeFade({super.key, required this.atTop, this.height = 24});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Positioned(
      left: 0,
      right: 0,
      top: atTop ? 0 : null,
      bottom: atTop ? null : 0,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: atTop ? Alignment.topCenter : Alignment.bottomCenter,
              end: atTop ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [c.bg, c.bg.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── 橡皮筋拉伸（ui.js 聊天橡皮筋）─────────────────────────

/// ui.js 聊天橡皮筋的公式（純函式，方便測試）。
///
/// 捲到頂再往下拉（[edge] = -1）或捲到底再往上拉（[edge] = 1）時，依「超出距離」
/// 算出一個有正負號的拉伸量 [pull]，每顆泡泡再依離被拉的邊多遠位移不同的量，
/// 離邊越遠位移越多 → 相鄰泡泡被拉開；放手後回到 0 就是回彈。
class ChatRubberBand {
  ChatRubberBand._();

  /// ui.js `MAX_PULL`：拉伸量的上限（px）。
  static const double maxPull = 26;

  /// ui.js `RESIST`：超出距離到多大才逼近上限。
  static const double resist = 90;

  /// 由「手指拖過邊界的距離」[over]（px，恆 ≥ 0）算出拉伸量大小：
  /// `MAX_PULL * (1 - 1 / (1 + over / RESIST))`。
  static double magnitude(double over) {
    if (over <= 0) return 0;
    return maxPull * (1 - 1 / (1 + over / resist));
  }

  /// 第 [index] 顆（共 [count] 顆）泡泡的垂直位移。[pull] 帶正負號：
  /// 往下拉（頂端）為正、往上拉（底端）為負；[edge] 為 -1（頂）或 1（底）。
  static double offsetFor({
    required int index,
    required int count,
    required double pull,
    required int edge,
  }) {
    if (pull == 0 || edge == 0) return 0;
    final n = math.max(1, count - 1);
    final dist = edge < 0 ? index / n : 1 - index / n;
    return pull * (0.3 + dist * 0.95);
  }

  /// 由捲動狀態算出 (拉伸量, 邊)。BouncingScrollPhysics 已把手指距離「阻尼」成較小的
  /// 超出量（約 0.5 倍），這裡除以 [nativeDamping] 還原成接近手指實際拖過的距離，
  /// 再套 ui.js 的公式。沒有超出邊界回傳 (0, 0)。
  static ({double pull, int edge}) fromMetrics({
    required double pixels,
    required double minScrollExtent,
    required double maxScrollExtent,
    double nativeDamping = 0.55,
  }) {
    if (pixels < minScrollExtent) {
      final over = (minScrollExtent - pixels) / nativeDamping;
      return (pull: magnitude(over), edge: -1);
    }
    if (pixels > maxScrollExtent) {
      final over = (pixels - maxScrollExtent) / nativeDamping;
      return (pull: -magnitude(over), edge: 1);
    }
    return (pull: 0, edge: 0);
  }
}

/// 把 [ChatRubberBand] 的拉伸量套到一顆泡泡上。[pull] 由清單上層的 ScrollNotification 更新；
/// 沒有拉伸（0）時不建立 Transform，完全不影響正常捲動與命中測試。
class ChatPullItem extends StatelessWidget {
  final int index;
  final int count;
  final ValueListenable<({double pull, int edge})> pull;
  final Widget child;

  const ChatPullItem({
    super.key,
    required this.index,
    required this.count,
    required this.pull,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<({double pull, int edge})>(
      valueListenable: pull,
      child: child,
      builder: (context, v, child) {
        if (v.pull == 0) return child!;
        return Transform.translate(
          offset: Offset(
            0,
            ChatRubberBand.offsetFor(
                index: index, count: count, pull: v.pull, edge: v.edge),
          ),
          child: child,
        );
      },
    );
  }
}
