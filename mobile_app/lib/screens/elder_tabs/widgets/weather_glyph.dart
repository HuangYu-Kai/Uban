import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/uban_motion.dart';

/// 設計稿 `.wx` 天氣小圖（ui.css 723–730）：太陽光暈慢慢呼吸（3.4s）＋雲朵微飄（4.5s）。
///
/// [rainy] 為 true 時改畫「雲＋雨滴」（沒有太陽），用於降雨機率偏高。
/// 系統開啟「移除動畫」時維持靜止。光暈是半透明放射漸層，不是帶色陰影。
class WeatherGlyph extends StatefulWidget {
  final bool rainy;
  final double size;

  const WeatherGlyph({super.key, this.rainy = false, this.size = 40});

  @override
  State<WeatherGlyph> createState() => _WeatherGlyphState();
}

class _WeatherGlyphState extends State<WeatherGlyph>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _drift;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3400));
    _drift = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4500));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = reduceMotion(context);
    if (reduce && _started) {
      _pulse.stop();
      _drift.stop();
      _started = false;
    } else if (!reduce && !_started) {
      _pulse.repeat(reverse: true);
      _drift.repeat(reverse: true);
      _started = true;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final cloudColor = widget.rainy ? c.info : c.brandStrong;
    return Semantics(
      excludeSemantics: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: FittedBox(
          child: SizedBox(
            width: 34,
            height: 34,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (!widget.rainy)
                  Positioned(
                    left: 3,
                    top: 2,
                    width: 15,
                    height: 15,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Positioned(
                          left: -7,
                          top: -7,
                          right: -7,
                          bottom: -7,
                          child: AnimatedBuilder(
                            animation: _pulse,
                            builder: (_, __) {
                              final v =
                                  Curves.easeInOut.transform(_pulse.value);
                              return Opacity(
                                opacity: .8 + .2 * v,
                                child: Transform.scale(
                                  scale: 1 + .15 * v,
                                  child: const DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          Color.fromRGBO(250, 200, 70, .5),
                                          Color.fromRGBO(250, 200, 70, .16),
                                          Color.fromRGBO(250, 200, 70, 0),
                                        ],
                                        stops: [0, .46, .68],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                center: Alignment(-.24, -.36),
                                colors: [Color(0xFFFFE8A3), Color(0xFFF8C23E)],
                                stops: [0, .72],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Positioned(
                  // 雨天沒有太陽：雲置中、放大並抬高，雨滴落在雲的正下方。
                  left: widget.rainy ? 4.5 : null,
                  right: widget.rainy ? null : 0,
                  bottom: widget.rainy ? 9 : 5,
                  width: widget.rainy ? 27 : 21,
                  height: widget.rainy ? 13 : 11,
                  child: AnimatedBuilder(
                    animation: _drift,
                    builder: (_, child) => Transform.translate(
                      offset: Offset(
                          -2.5 * Curves.easeInOut.transform(_drift.value), 0),
                      child: child,
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: cloudColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 3,
                          top: -6,
                          width: 12,
                          height: 12,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: cloudColor, shape: BoxShape.circle),
                          ),
                        ),
                        Positioned(
                          right: 3,
                          top: -4,
                          width: 8,
                          height: 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: cloudColor, shape: BoxShape.circle),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.rainy)
                  for (final x in const [10.0, 16.0, 22.0])
                    Positioned(
                      left: x,
                      bottom: 1,
                      width: 2.5,
                      height: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.info,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
