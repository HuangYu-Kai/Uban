import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 舞台時段：依本機時間自動切換（設計稿 `tod()`）。
enum PetTimeOfDay {
  dawn('清晨'),
  day('白天'),
  dusk('黃昏'),
  night('夜晚');

  final String label;
  const PetTimeOfDay(this.label);

  /// 5 點前夜晚、5–8 清晨、8–17 白天、17–19 黃昏、其後夜晚。
  static PetTimeOfDay fromHour(int h) => h < 5
      ? night
      : h < 8
          ? dawn
          : h < 17
              ? day
              : h < 19
                  ? dusk
                  : night;
}

/// 天氣三級，沿用 `WeatherService` 的降雨機率分級（<20 晴、<50 陣雨、其餘陰雨）。
enum PetWeather {
  sunny('多雲到晴'),
  shower('局部陣雨'),
  rain('陰雨綿綿');

  final String label;
  const PetWeather(this.label);

  static PetWeather fromRainProbability(int? p) => p == null || p < 20
      ? sunny
      : p < 50
          ? shower
          : rain;
}

/// 一組場景色與天氣層參數；可線性內插（切時段／天氣時 .8 秒漸變）。
@immutable
class PetScenePalette {
  final Color skyA, skyB, hillA, hillB, hillC, ground, groundD, orb, cloud;
  final double orbX, orbY; // 設計基準（寬 390）的圓心座標
  final double orbOpacity, stars, moon, overcast, moreClouds, puddles;

  const PetScenePalette({
    required this.skyA,
    required this.skyB,
    required this.hillA,
    required this.hillB,
    required this.hillC,
    required this.ground,
    required this.groundD,
    required this.orb,
    required this.cloud,
    required this.orbX,
    required this.orbY,
    required this.orbOpacity,
    required this.stars,
    required this.moon,
    required this.overcast,
    required this.moreClouds,
    required this.puddles,
  });

  static const _cDay = _Base(
    Color(0xFF8FD3F4), Color(0xFFE3F6FB), Color(0xFF9ED38A), Color(0xFF7EC27A),
    Color(0xFF5FAE6E), Color(0xFF8CCB72), Color(0xFF6FB25C),
    Color(0xFFFFF3C4), 321, 57,
  );
  static const _cDawn = _Base(
    Color(0xFFF7B7A3), Color(0xFFFFE9C9), Color(0xFFB9D69A), Color(0xFF94C485),
    Color(0xFF77B076), Color(0xFF9BCF7A), Color(0xFF7DB866),
    Color(0xFFFFE0A6), 321, 143,
  );
  static const _cDusk = _Base(
    Color(0xFF7E6BB0), Color(0xFFF7A976), Color(0xFF8EA67F), Color(0xFF6E8E6B),
    Color(0xFF56775A), Color(0xFF86AD6A), Color(0xFF6A9457),
    Color(0xFFFFC38A), 63, 133,
  );
  static const _cNight = _Base(
    Color(0xFF152241), Color(0xFF3A4B7A), Color(0xFF3E5A55), Color(0xFF2F4A46),
    Color(0xFF243C39), Color(0xFF4E7A55), Color(0xFF3C6345),
    Color(0xFFF4F1DE), 321, 57,
  );

  factory PetScenePalette.of(PetTimeOfDay t, PetWeather w) {
    final b = switch (t) {
      PetTimeOfDay.day => _cDay,
      PetTimeOfDay.dawn => _cDawn,
      PetTimeOfDay.dusk => _cDusk,
      PetTimeOfDay.night => _cNight,
    };
    final rain = w == PetWeather.rain;
    Color land(Color c) => rain ? _desaturate(c, .6, .85) : c;
    final cloud = rain
        ? const Color.fromRGBO(150, 160, 170, .9)
        : t == PetTimeOfDay.night
            ? const Color.fromRGBO(200, 210, 235, .25)
            : const Color.fromRGBO(255, 255, 255, .85);
    return PetScenePalette(
      skyA: b.skyA,
      skyB: b.skyB,
      hillA: land(b.hillA),
      hillB: land(b.hillB),
      hillC: land(b.hillC),
      ground: land(b.ground),
      groundD: land(b.groundD),
      orb: b.orb,
      cloud: cloud,
      orbX: b.orbX,
      orbY: b.orbY,
      orbOpacity: switch (w) {
        PetWeather.sunny => 1,
        PetWeather.shower => .55,
        PetWeather.rain => 0,
      },
      stars: t == PetTimeOfDay.night ? 1 : 0,
      moon: t == PetTimeOfDay.night ? 1 : 0,
      overcast: switch (w) {
        PetWeather.sunny => 0,
        PetWeather.shower => .45,
        PetWeather.rain => 1,
      },
      moreClouds: w == PetWeather.sunny ? 0 : 1,
      puddles: rain ? 1 : 0,
    );
  }

  static PetScenePalette lerp(PetScenePalette a, PetScenePalette b, double t) {
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    double d(double x, double y) => x + (y - x) * t;
    return PetScenePalette(
      skyA: c(a.skyA, b.skyA),
      skyB: c(a.skyB, b.skyB),
      hillA: c(a.hillA, b.hillA),
      hillB: c(a.hillB, b.hillB),
      hillC: c(a.hillC, b.hillC),
      ground: c(a.ground, b.ground),
      groundD: c(a.groundD, b.groundD),
      orb: c(a.orb, b.orb),
      cloud: c(a.cloud, b.cloud),
      orbX: d(a.orbX, b.orbX),
      orbY: d(a.orbY, b.orbY),
      orbOpacity: d(a.orbOpacity, b.orbOpacity),
      stars: d(a.stars, b.stars),
      moon: d(a.moon, b.moon),
      overcast: d(a.overcast, b.overcast),
      moreClouds: d(a.moreClouds, b.moreClouds),
      puddles: d(a.puddles, b.puddles),
    );
  }

  static Color _desaturate(Color c, double sat, double bright) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation((hsl.saturation * sat).clamp(0.0, 1.0))
        .withLightness((hsl.lightness * bright).clamp(0.0, 1.0))
        .toColor();
  }
}

class _Base {
  final Color skyA, skyB, hillA, hillB, hillC, ground, groundD, orb;
  final double orbX, orbY;
  const _Base(this.skyA, this.skyB, this.hillA, this.hillB, this.hillC,
      this.ground, this.groundD, this.orb, this.orbX, this.orbY);
}

class PetScenePaletteTween extends Tween<PetScenePalette> {
  PetScenePaletteTween({super.begin, super.end});
  @override
  PetScenePalette lerp(double t) => PetScenePalette.lerp(begin!, end!, t);
}

/// 場景時鐘：舞台唯一的 Ticker 每幀推進它，雲與雨的 painter 用它當 repaint。
class PetStageClock extends ChangeNotifier {
  double seconds = 0;
  void tick(double dt) {
    seconds += dt;
    notifyListeners();
  }

  /// 不推進時間、只通知重繪（拖曳中的胡蘿蔔跟手用）。
  void ping() => notifyListeners();
}

/// 雨粒子（設計稿 `startRain`）：陣雨 40 條、陰雨 110 條；夜晚調暗。
class PetRainField {
  final math.Random _rnd;
  final List<_Drop> _drops = [];
  Size _size = Size.zero;

  PetRainField([math.Random? rnd]) : _rnd = rnd ?? math.Random(7);

  int get count => _drops.length;

  void configure(PetWeather w, Size size) {
    final n = w == PetWeather.rain
        ? 110
        : w == PetWeather.shower
            ? 40
            : 0;
    if (size == _size && _drops.length == n) return;
    _size = size;
    _drops.clear();
    for (var i = 0; i < n; i++) {
      _drops.add(_Drop(
        _rnd.nextDouble() * size.width,
        _rnd.nextDouble() * size.height,
        10 + _rnd.nextDouble() * 12,
        9 + _rnd.nextDouble() * 6,
      ));
    }
  }

  /// 設計稿以 60fps 每幀位移 v px，這裡換成每秒。
  void step(double dt) {
    final f = dt * 60;
    for (final d in _drops) {
      d.y += d.v * f;
      d.x -= d.v * .18 * f;
      if (d.y > _size.height) {
        d.y = -d.l;
        d.x = _rnd.nextDouble() * (_size.width + 40);
      }
    }
  }
}

class _Drop {
  double x, y;
  final double l, v;
  _Drop(this.x, this.y, this.l, this.v);
}

/// 天空、星星、日月、陰天遮罩（最底層，只在切時段／天氣時重畫）。
class PetSkyPainter extends CustomPainter {
  final PetScenePalette pal;
  final double s;
  PetSkyPainter(this.pal, this.s);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [pal.skyA, pal.skyB],
        ).createShader(rect),
    );
    if (pal.stars > 0) {
      final p = Paint();
      const pts = [
        [.20, .18, 1.5],
        [.42, .30, 1.5],
        [.64, .14, 1.0],
        [.82, .40, 1.5],
        [.12, .44, 1.0],
        [.52, .08, 1.0],
      ];
      for (final q in pts) {
        p.color = Colors.white.withValues(alpha: pal.stars);
        canvas.drawCircle(
            Offset(size.width * q[0], size.height * q[1]), q[2] * s, p);
      }
    }
    if (pal.orbOpacity > 0) {
      final c = Offset(pal.orbX * s, pal.orbY * s);
      final r = 23 * s;
      canvas.saveLayer(
          rect, Paint()..color = Color.fromRGBO(0, 0, 0, pal.orbOpacity));
      canvas.drawCircle(c, r, Paint()..color = pal.orb);
      if (pal.moon > 0) {
        // 月牙：內陰影（-10,-4）＝右下留一圈暗面。
        canvas.save();
        canvas.clipPath(
            Path()..addOval(Rect.fromCircle(center: c, radius: r)));
        canvas.drawCircle(
            c,
            r,
            Paint()
              ..color = const Color(0xFFD9D4B8).withValues(alpha: pal.moon));
        canvas.drawCircle(
            c + Offset(-10 * s, -4 * s), r, Paint()..color = pal.orb);
        canvas.restore();
      }
      canvas.restore();
    }
    if (pal.overcast > 0) {
      canvas.saveLayer(
          rect, Paint()..color = Color.fromRGBO(0, 0, 0, pal.overcast));
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.fromRGBO(90, 100, 110, .55),
              Color.fromRGBO(120, 128, 135, .15),
              Color.fromRGBO(120, 128, 135, 0),
            ],
            stops: [0, .6, 1],
          ).createShader(rect),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(PetSkyPainter old) => old.pal != pal || old.s != s;
}

class _CloudSpec {
  final double top, width, duration, delay;
  final bool more;
  const _CloudSpec(this.top, this.width, this.duration, this.delay, this.more);
}

const _clouds = [
  _CloudSpec(40, 70, 38, 0, false),
  _CloudSpec(86, 54, 52, -20, false),
  _CloudSpec(22, 90, 44, -8, true),
  _CloudSpec(64, 76, 60, -34, true),
];

/// 飄雲：由場景時鐘驅動，從 -120 漂到 460（設計稿 `drift`）。
class PetCloudPainter extends CustomPainter {
  final PetScenePalette pal;
  final double s;
  final PetStageClock clock;
  PetCloudPainter(this.pal, this.s, this.clock) : super(repaint: clock);

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in _clouds) {
      final alpha = c.more ? pal.moreClouds : 1.0;
      if (alpha <= 0) continue;
      final phase = (((clock.seconds - c.delay) / c.duration) % 1 + 1) % 1;
      final x = (-120 + phase * 580) * s;
      final y = c.top * s;
      final paint = Paint()
        ..color = pal.cloud.withValues(alpha: pal.cloud.a * alpha);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, c.width * s, 22 * s),
            Radius.circular(11 * s)),
        paint,
      );
      canvas.drawCircle(Offset(x + 26 * s, y), 14 * s, paint);
      canvas.drawCircle(Offset(x + 44 * s, y + 1 * s), 10 * s, paint);
    }
  }

  @override
  bool shouldRepaint(PetCloudPainter old) =>
      old.pal != pal || old.s != s || old.clock != clock;
}

/// 遠山、地面、草叢、水窪。小豬腳下不畫白圈，影子由小豬元件自己畫。
class PetGroundPainter extends CustomPainter {
  final PetScenePalette pal;
  final double s;
  PetGroundPainter(this.pal, this.s);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // 遠山：viewBox 400x130、preserveAspectRatio none、貼在底部 70 之上。
    final hillTop = h - (70 + 130) * s;
    Path poly(List<List<double>> pts) {
      final p = Path();
      for (var i = 0; i < pts.length; i++) {
        final x = pts[i][0] / 400 * w, y = hillTop + pts[i][1] * s;
        i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      return p..close();
    }

    canvas.drawPath(
        poly([
          [0, 130], [0, 70], [50, 40], [95, 62], [140, 28], [190, 58],
          [240, 22], [290, 54], [340, 30], [400, 60], [400, 130]
        ]),
        Paint()..color = pal.hillC);
    canvas.drawPath(
        poly([
          [0, 130], [0, 92], [60, 64], [120, 86], [175, 58], [235, 84],
          [300, 60], [360, 82], [400, 70], [400, 130]
        ]),
        Paint()..color = pal.hillB);
    canvas.drawPath(
        poly([
          [0, 130], [0, 108], [80, 90], [150, 104], [220, 88], [300, 102],
          [400, 92], [400, 130]
        ]),
        Paint()..color = pal.hillA);

    // 地面：左右各超出 10%，頂部橢圓圓角。
    final gRect =
        Rect.fromLTWH(-w * .1, h + 40 * s - 150 * s, w * 1.2, 150 * s);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        gRect,
        topLeft: Radius.elliptical(gRect.width * .5, gRect.height * .4),
        topRight: Radius.elliptical(gRect.width * .5, gRect.height * .4),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [pal.ground, pal.groundD],
        ).createShader(gRect),
    );

    if (pal.puddles > 0) {
      void puddle(double left, double bottom, double pw) {
        final r = Rect.fromLTWH(left, h - bottom * s - 10 * s, pw * s, 10 * s);
        canvas.drawOval(
          r,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.fromRGBO(220, 235, 245, .7 * pal.puddles),
                Color.fromRGBO(150, 175, 195, .4 * pal.puddles),
              ],
            ).createShader(r),
        );
      }

      puddle(w * .14, 26, 70);
      puddle(w * .74 - 54 * s, 14, 54);
    }

    void tuft(double left) {
      canvas.save();
      canvas.translate(left, h - 52 * s - 16 * s);
      canvas.scale(s, s);
      canvas.drawPath(
          Path()
            ..moveTo(2, 16)
            ..lineTo(5, 6)
            ..lineTo(8, 16)
            ..close()
            ..moveTo(8, 16)
            ..lineTo(11, 2)
            ..lineTo(14, 16)
            ..close()
            ..moveTo(14, 16)
            ..lineTo(17, 7)
            ..lineTo(20, 16)
            ..close(),
          Paint()..color = pal.groundD);
      canvas.restore();
    }

    tuft(w * .12);
    tuft(w * .90 - 22 * s);
  }

  @override
  bool shouldRepaint(PetGroundPainter old) => old.pal != pal || old.s != s;
}

/// 雨絲（畫在小豬之上）。減少動態時不建立。
class PetRainPainter extends CustomPainter {
  final PetRainField field;
  final PetStageClock clock;
  final bool night;
  PetRainPainter(this.field, this.clock, this.night) : super(repaint: clock);

  @override
  void paint(Canvas canvas, Size size) {
    if (field.count == 0) return;
    final p = Paint()
      ..color = Color.fromRGBO(225, 235, 245, night ? .35 : .6)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (final d in field._drops) {
      path.moveTo(d.x, d.y);
      path.lineTo(d.x + d.l * .18, d.y - d.l);
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(PetRainPainter old) =>
      old.night != night || old.field != field || old.clock != clock;
}
