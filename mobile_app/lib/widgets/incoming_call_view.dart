import 'package:flutter/material.dart';

import '../theme/uban_motion.dart' show reduceMotion;

/// 全螢幕來電畫面（純展示）。
///
/// 對應設計稿 `design_prototype/index.html` 的 `#incoming .callmodal`：深色底、
/// 脈動外框＋大頭貼、「XXX 來電」、拒接／接聽兩顆大鈕。長輩端 `ElderHomeScreen`、
/// `main.dart` 的 FCM 前景備援、`ElderScreen` 內的一般來電選擇三處共用。
///
/// ★ 通話子系統（CLAUDE_call-monitor.md／G26／G27／G81／G199）：本 widget **只負責
///   外觀**。它沒有任何狀態旗標、不碰 Navigator、不碰 Signaling／SharedPreferences、
///   不自己決定「接聽／拒接」要做什麼——兩顆按鈕只會呼叫呼叫端傳進來的
///   [onDecline]／[onAccept]，呼叫端原本 `onPressed` 內的閉包原封不動搬進這兩個參數。
///   `showDialog` 的參數、`AssistantHiddenZone`、`.then` 收尾全部留在呼叫端。
///
/// 顏色是「通話房固定色」，不隨主題（與設計稿 ui.css 一致）。
class IncomingCallView extends StatefulWidget {
  const IncomingCallView({
    super.key,
    required this.callerName,
    required this.subtitle,
    required this.onDecline,
    required this.onAccept,
    this.isEmergency = false,
    this.avatarText,
  });

  /// 來電者顯示名稱；標題為「$callerName 來電」。
  final String callerName;

  /// 副標（例如「您的家人正在呼叫您！」）。
  final String subtitle;

  /// 「拒接」按下時呼叫（呼叫端原本的 onPressed 閉包）。
  final VoidCallback onDecline;

  /// 「接聽」按下時呼叫（呼叫端原本的 onPressed 閉包）。
  final VoidCallback onAccept;

  /// 緊急來電外觀（紅色警示圖示、標題「🚨 緊急來電」）。純外觀旗標，不影響任何邏輯。
  final bool isEmergency;

  /// 大頭貼文字；省略時取 [callerName] 的第一個字。
  final String? avatarText;

  // 通話房固定色（design_prototype/ui.css）。
  static const Color bg = Color(0xFF111916);
  static const Color danger = Color(0xFFE5484D);
  static const Color accept = Color(0xFF6FCBAA);
  static const Color acceptText = Color(0xFF062A1D);
  static const Color avatarBg = Color(0xFFDFF3EB);
  static const Color avatarFg = Color(0xFF1F7A5C);

  @override
  State<IncomingCallView> createState() => _IncomingCallViewState();
}

class _IncomingCallViewState extends State<IncomingCallView>
    with TickerProviderStateMixin {
  // 脈動：兩圈 2.4s、第二圈延遲 1.2s（= 相位差 0.5）。
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  // 進場：淡入 .3s＋scale 1.04→1 .4s。
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  static const Curve _rippleCurve = Cubic(.2, .6, .3, 1);
  static const Curve _enterCurve = Cubic(.2, .8, .2, 1);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // reduceMotion：不脈動、不做進場動畫（直接顯示終態）。
    if (reduceMotion(context)) {
      _pulse.stop();
      _enter.value = 1;
    } else if (!_started || !_pulse.isAnimating) {
      _started = true;
      if (_enter.value < 1 && !_enter.isAnimating) _enter.forward();
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _enter.dispose();
    super.dispose();
  }

  Widget _ring(double phase, bool still) {
    if (still) {
      return IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: .35), width: 2),
          ),
        ),
      );
    }
    final t = _rippleCurve.transform((_pulse.value + phase) % 1.0);
    return IgnorePointer(
      child: Opacity(
        opacity: (1 - t).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: .8 + .9 * t, // .8 → 1.7
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: .35), width: 2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar() {
    final name = widget.callerName.trim();
    final String letter = widget.avatarText ??
        (name.isEmpty ? '' : String.fromCharCodes(name.runes.take(1)));
    return Container(
      width: 120,
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.isEmergency ? const Color(0xFFFDE2E2) : IncomingCallView.avatarBg,
      ),
      child: widget.isEmergency
          ? const Icon(Icons.warning_rounded, size: 64, color: IncomingCallView.danger)
          : Text(
              letter,
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: IncomingCallView.avatarFg,
              ),
            ),
    );
  }

  Widget _actionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color background,
    required Color foreground,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        minimumSize: const Size(0, 84),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32),
          const SizedBox(width: 8),
          // 硬規則 14：同列有圖示，文字必須可收縮（textScaler 1.3、窄螢幕）。
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    final title = widget.isEmergency ? '🚨 緊急來電' : '${widget.callerName} 來電';

    return Material(
      color: IncomingCallView.bg,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulse, _enter]),
        builder: (context, child) {
          final e = _enterCurve.transform(_enter.value.clamp(0.0, 1.0));
          // 淡入只佔前 .3s（= 進場 .4s 的前 75%）。
          final fade = (_enter.value / .75).clamp(0.0, 1.0);
          return Opacity(
            opacity: fade,
            child: Transform.scale(scale: 1.04 - .04 * e, child: child),
          );
        },
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              // 設計稿上緣留白 96；矮螢幕（橫放）縮小，避免擠掉按鈕。
              final double topPad = c.maxHeight >= 560 ? 96 : 16;
              return Padding(
                padding: EdgeInsets.fromLTRB(24, topPad, 24, 40),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 140,
                                height: 140,
                                child: Stack(
                                  alignment: Alignment.center,
                                  clipBehavior: Clip.none,
                                  children: [
                                    AnimatedBuilder(
                                      animation: _pulse,
                                      builder: (context, _) => SizedBox(
                                        width: 140,
                                        height: 140,
                                        child: _ring(0, reduce),
                                      ),
                                    ),
                                    if (!reduce)
                                      AnimatedBuilder(
                                        animation: _pulse,
                                        builder: (context, _) => SizedBox(
                                          width: 140,
                                          height: 140,
                                          child: _ring(.5, false),
                                        ),
                                      ),
                                    _avatar(),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 22),
                              // 長名稱可收縮：最多兩行再省略（硬規則 14）。
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.subtitle,
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 22,
                                  color: Colors.white.withValues(alpha: .8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            onPressed: widget.onDecline,
                            icon: Icons.call_end,
                            label: '拒接',
                            background: IncomingCallView.danger,
                            foreground: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _actionButton(
                            onPressed: widget.onAccept,
                            icon: Icons.call,
                            label: '接聽',
                            background: IncomingCallView.accept,
                            foreground: IncomingCallView.acceptText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
