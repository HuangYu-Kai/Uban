import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../theme/uban_motion.dart';
import 'pet_carrot_button.dart';
import 'pet_ear_anchors.dart';
import 'pet_pig_sprite.dart';
import 'pet_scene.dart';
import 'pet_tag_pendulum.dart';

/// 長輩端「小豬」分頁的寶可夢 GO 式夥伴舞台（設計稿 `#tabPet .buddy`）。
///
/// 不依賴 geolocator／pedometer／後端：資料與動作全由外部傳入，方便獨立測試。
///
/// - 天空依時段、天氣三級（晴／陣雨／陰雨）；遠山、飄雲、柔和影子（無白圈）。
/// - 小豬平常正面＋呼吸；每 9 秒換側面圖走一段再走回、轉回正面並跳一下；
///   點小豬跳一下＋愛心。耳標掛在左耳，帶阻尼鐘擺。
/// - 餵食只有胡蘿蔔：右下角圓鈕，點一下或拖到小豬身上。資料由 [onFeedRequest]
///   處理（回傳 true 才播動畫）；動畫：飛到嘴邊 → 咀嚼（4 次 squash）＋碎屑 →
///   愛心 → 跳一下，結束呼叫 [onFeedDone]。
///
/// 整個舞台只有一個 [Ticker]（[PetStageClock]），所有動畫只用 transform／
/// opacity 與 CustomPainter。[reduceMotion] 時不啟動 Ticker：不走路、不下雨、
/// 餵食瞬間完成。
class PetBuddyStage extends StatefulWidget {
  /// 小豬階段 1~5（來自 `PetGrowthStage.index + 1`）。
  final int stage;
  final PetBreed breed;

  /// null = 依本機時間自動切換。
  final PetTimeOfDay? time;
  final PetWeather weather;

  /// 胡蘿蔔剩餘數量；0 時按鈕為灰色停用外觀。
  final int carrotCount;

  /// 玩家要餵胡蘿蔔。回傳 true＝資料已更新、可以播動畫；false＝失敗不播。
  final bool Function() onFeedRequest;

  /// 餵食動畫（含愛心與跳躍）全部播完。
  final VoidCallback? onFeedDone;

  /// 數量為 0 時點了胡蘿蔔鈕。
  final VoidCallback? onEmptyCarrot;

  /// 數量為 0 時，先呼叫它重新讀取帳本（回傳最新可餵數量）再決定：仍為 0 才
  /// 呼叫 [onEmptyCarrot]，>0 就照常餵。未提供時直接視為沒有胡蘿蔔。
  final Future<int> Function()? onRefreshCarrot;

  /// 一般提示（例如拖放沒落在小豬身上）。
  final ValueChanged<String>? onHint;

  /// 舞台右上角（音樂鈕）。
  final Widget? cornerAction;

  /// 耳標錨點；null 時由資產檔非同步載入。
  final PetEarAnchors? anchors;

  /// 測試用：強制減少動態；null 時讀系統設定。
  final bool? reduceMotionOverride;

  /// 設計基準寬度（390）下的舞台高度。
  static const double designWidth = 390;
  static const double designHeight = 300;

  const PetBuddyStage({
    super.key,
    required this.stage,
    required this.breed,
    required this.weather,
    required this.carrotCount,
    required this.onFeedRequest,
    this.time,
    this.onFeedDone,
    this.onEmptyCarrot,
    this.onRefreshCarrot,
    this.onHint,
    this.cornerAction,
    this.anchors,
    this.reduceMotionOverride,
  });

  @override
  State<PetBuddyStage> createState() => PetBuddyStageState();
}

enum _PigAnim { none, hop, ready, chew }

class _Leg {
  final int d; // -1 往左、+1 往右（身體翻轉）
  final double start, dur, from, to;
  double nextStep;
  final VoidCallback done;
  _Leg(this.d, this.start, this.dur, this.from, this.to, this.done)
      : nextStep = start + .32;
}

class _Fx {
  final bool heart;
  final double x, y, start, dx, dy;
  final Color color;
  _Fx.heart(this.x, this.y, this.start)
      : heart = true,
        dx = 0,
        dy = 0,
        color = const Color(0xFFF26D7D);
  _Fx.crumb(this.x, this.y, this.start, this.dx, this.dy)
      : heart = false,
        color = const Color(0xFFF28C28);
  double get duration => heart ? 1.3 : .65;
}

class _Flyer {
  final Offset start, ctrl, to;
  final double t0;
  _Flyer(this.start, this.ctrl, this.to, this.t0);
}

class _Pointer {
  final Offset startGlobal;
  final bool canDrag;
  Offset? ghost; // 舞台座標，左上角
  _Pointer(this.startGlobal, this.canDrag);
}

class PetBuddyStageState extends State<PetBuddyStage>
    with SingleTickerProviderStateMixin {
  final GlobalKey _stageKey = GlobalKey();
  final PetStageClock clock = PetStageClock();
  final PetTagPendulum _pend = PetTagPendulum();
  final PetRainField _rain = PetRainField();
  final math.Random _rnd = math.Random();
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  PetEarAnchors? _anchors;
  late int _shownStage;
  int? _pendingStage;
  late PetTimeOfDay _autoTime;
  double _nextTimeCheck = 30;
  bool _reduce = false;

  // 場景尺寸（build 時更新）
  double _w = PetBuddyStage.designWidth, _h = PetBuddyStage.designHeight;
  double _s = 1;

  // 走路 / 動畫狀態
  PetView _view = PetView.front;
  bool _flip = false;
  bool _bobbing = false;
  double _bobStart = 0;
  double _offset = 0; // 設計 px
  bool _walkActive = false;
  bool _feeding = false;
  _Leg? _leg;
  double _nextWalk = 9;
  double _nextJiggle = 3.8;
  _PigAnim _anim = _PigAnim.none;
  double _animStart = 0;
  final List<(double, VoidCallback)> _events = [];
  final List<_Fx> _fx = [];
  _Flyer? _flyer;
  _Pointer? _ptr;
  bool _dropOk = false;

  bool get _busy => _walkActive || _feeding;
  double get _now => clock.seconds;

  /// 測試／除錯用：目前是否正在走路或餵食。
  bool get isBusy => _busy;
  bool get isFlipped => _flip;
  PetView get view => _view;
  int get shownStage => _shownStage;

  PetTimeOfDay get _time => widget.time ?? _autoTime;

  @override
  void initState() {
    super.initState();
    _shownStage = widget.stage.clamp(1, 5);
    _autoTime = PetTimeOfDay.fromHour(DateTime.now().hour);
    _anchors = widget.anchors;
    if (_anchors == null) {
      PetEarAnchors.load().then((a) {
        if (mounted) setState(() => _anchors = a);
      }).catchError((Object _) {});
    }
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = widget.reduceMotionOverride ?? reduceMotion(context);
    if (_reduce) {
      _ticker.stop();
      _resetSim();
    } else if (!_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(covariant PetBuddyStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.anchors != null) _anchors = widget.anchors;
    final stage = widget.stage.clamp(1, 5);
    if (stage != _shownStage) {
      if (_feeding) {
        _pendingStage = stage; // 餵食動畫播完才換圖（升階由外部另行呈現）
      } else {
        _shownStage = stage;
      }
    }
    if (oldWidget.breed != widget.breed && !_busy) _hop();
    final r = widget.reduceMotionOverride;
    if (r != null && r != _reduce) didChangeDependencies();
  }

  @override
  void dispose() {
    _ticker.dispose();
    clock.dispose();
    super.dispose();
  }

  void _resetSim() {
    _events.clear();
    _fx.clear();
    _leg = null;
    _flyer = null;
    _walkActive = false;
    _bobbing = false;
    _flip = false;
    _view = PetView.front;
    _offset = 0;
    _anim = _PigAnim.none;
    if (_feeding) {
      // 不能在 build 階段回呼外部（didChangeDependencies 呼叫到這裡）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _feeding) _finishFeed();
      });
    }
  }

  // ── 時間推進 ─────────────────────────────────────────

  void _at(double delay, VoidCallback f) => _events.add((_now + delay, f));

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastElapsed).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastElapsed = elapsed;
    final now = clock.seconds + dt;

    // 排程事件
    if (_events.isNotEmpty) {
      final due = _events.where((e) => e.$1 <= now).toList();
      if (due.isNotEmpty) {
        _events.removeWhere((e) => e.$1 <= now);
        due.sort((a, b) => a.$1.compareTo(b.$1));
        for (final e in due) {
          e.$2();
        }
      }
    }

    // 耳標鐘擺
    _pend.step(dt);

    // 走路
    final leg = _leg;
    if (leg != null) {
      final k = ((now - leg.start) / leg.dur).clamp(0.0, 1.0);
      _offset = leg.from + (leg.to - leg.from) * Curves.easeInOut.transform(k);
      while (now >= leg.nextStep && k < 1) {
        _stepN++;
        _pend.kick((_stepN % 2 == 0 ? 1 : -1) * 55.0 - leg.d * 25);
        leg.nextStep += .32;
      }
      if (k >= 1) {
        _leg = null;
        _bobbing = false;
        _pend.lean = 0;
        _pend.kick(leg.d * 60.0);
        leg.done();
      }
    }

    // 飛行中的胡蘿蔔 → 咀嚼
    final fly = _flyer;
    if (fly != null && now - fly.t0 >= _flyDuration) {
      _flyer = null;
      _startChew(now);
    }

    // 待機：每 9 秒走一段；耳標偶爾自己晃一下
    if (now >= _nextWalk) {
      _nextWalk += 9;
      _startWalk(now);
    }
    if (now >= _nextJiggle) {
      _nextJiggle += 3.8;
      if (!_busy) _pend.kick((_rnd.nextDouble() - .5) * 60);
    }
    if (widget.time == null && now >= _nextTimeCheck) {
      _nextTimeCheck += 30;
      final t = PetTimeOfDay.fromHour(DateTime.now().hour);
      if (t != _autoTime) setState(() => _autoTime = t);
    }

    // 雨
    _rain.step(dt);
    _fx.removeWhere((f) => now - f.start > f.duration + 1.2);

    clock.tick(dt);
  }

  int _stepN = 0;
  static const double _flyDuration = .52;

  // ── 幾何 ─────────────────────────────────────────────

  Rect _pigRect([double? offsetDesign]) {
    final stage = _shownStage;
    final hd = (_view == PetView.front ? kPetFrontHeights : kPetSideHeights)[stage];
    final size = kPetSpriteSize[PetEarAnchors.keyOf(widget.breed, _view, stage)] ??
        const [1, 1];
    final h = hd * _s;
    final w = h * size[0] / size[1];
    final left = _w / 2 - w / 2 + (offsetDesign ?? _offset) * _s;
    return Rect.fromLTWH(left, _h - 44 * _s - h, w, h);
  }

  Offset _toStage(Offset global) {
    final box = _stageKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  bool _overPig(Offset p) {
    final r = _pigRect();
    return p.dx > r.left - 30 &&
        p.dx < r.right + 30 &&
        p.dy > r.top - 40 &&
        p.dy < r.bottom + 10;
  }

  // ── 動作 ─────────────────────────────────────────────

  void _hop() {
    if (_reduce) return;
    _anim = _PigAnim.hop;
    _animStart = _now;
    _pend.kick(-140);
    _at(.26, () => _pend.kick(90));
  }

  void _spawnHeart(double x, double y, [double delay = 0]) {
    _fx.add(_Fx.heart(x, y, _now + delay));
  }

  void _onPigTap() {
    if (_busy || _reduce) return;
    _hop();
    final r = _pigRect();
    _spawnHeart(r.center.dx - 13, r.top - 6);
  }

  void _startWalk(double now) {
    if (_busy || _reduce) return;
    _walkActive = true;
    final dir = _rnd.nextBool() ? 1 : -1;
    // 右下角有胡蘿蔔鈕，往右走短一點。
    final dist = dir > 0 ? 40 + _rnd.nextDouble() * 15 : 70 + _rnd.nextDouble() * 30;
    _view = PetView.side;
    void leg(int d, VoidCallback done, double delay) {
      _at(delay, () {
        _flip = d > 0;
        _bobbing = true;
        _bobStart = _now;
        _pend.lean = d * 7.0; // 走路時耳標往後甩
        _stepN = 0;
        final from = d == dir ? 0.0 : dir * dist;
        final to = d == dir ? dir * dist : 0.0;
        _leg = _Leg(d, _now, 2.2, from, to, done);
      });
    }

    leg(dir, () {
      leg(-dir, () {
        _flip = false;
        _offset = 0;
        _view = PetView.front;
        _walkActive = false;
        _hop();
      }, .5);
    }, 0);
  }

  // ── 餵食 ─────────────────────────────────────────────

  void _feed(Offset fromCenter) {
    if (_busy) return;
    if (widget.carrotCount <= 0) {
      final refresh = widget.onRefreshCarrot;
      if (refresh == null) {
        widget.onEmptyCarrot?.call();
        return;
      }
      if (_refreshing) return;
      _refreshing = true;
      refresh().catchError((Object _) => 0).then((n) {
        _refreshing = false;
        if (!mounted || _busy) return;
        if (n <= 0) {
          widget.onEmptyCarrot?.call();
        } else {
          _doFeed(fromCenter);
        }
      });
      return;
    }
    _doFeed(fromCenter);
  }

  bool _refreshing = false;

  void _doFeed(Offset fromCenter) {
    if (!widget.onFeedRequest()) return;
    _feeding = true;
    if (_reduce) {
      _finishFeed();
      return;
    }
    final pr = _pigRect();
    final to = Offset(pr.center.dx - 32, pr.top + pr.height * .42 - 32);
    final start = fromCenter - const Offset(32, 32);
    final ctrl = Offset((start.dx + to.dx) / 2, math.min(start.dy, to.dy) - 90);
    _anim = _PigAnim.ready;
    _animStart = _now;
    _flyer = _Flyer(start, ctrl, to, _now);
  }

  void _startChew(double now) {
    _anim = _PigAnim.chew;
    _animStart = now;
    final r = _pigRect();
    final cx = r.center.dx, top = r.top, h = r.height;
    for (var n = 0; n < 8; n++) {
      _at(.15 * (n + 1), () {
        _pend.kick(n % 2 == 1 ? 40 : -40);
        for (var i = 0; i < 3; i++) {
          _fx.add(_Fx.crumb(
            cx + (_rnd.nextDouble() - .5) * 40,
            top + h * .45,
            _now,
            (_rnd.nextDouble() - .5) * 90,
            30 + _rnd.nextDouble() * 50,
          ));
        }
      });
    }
    _at(1.25, () {
      for (var i = 0; i < 3; i++) {
        _spawnHeart(cx - 13 + (i - 1) * 34, top - 4, i * .14);
      }
      _hop();
      _at(.6, _finishFeed);
    });
  }

  void _finishFeed() {
    _feeding = false;
    final p = _pendingStage;
    if (p != null) {
      _pendingStage = null;
      if (mounted) setState(() => _shownStage = p);
    }
    widget.onFeedDone?.call();
  }

  // ── 胡蘿蔔鈕：點一下或拖到小豬身上 ─────────────────────

  void _onPtrDown(PointerDownEvent e) {
    _ptr = _Pointer(e.position, !_busy && widget.carrotCount > 0);
  }

  void _onPtrMove(PointerMoveEvent e) {
    final p = _ptr;
    if (p == null || !p.canDrag) return;
    if (p.ghost == null && (e.position - p.startGlobal).distance > 12) {
      p.ghost = _toStage(e.position) - const Offset(36, 36);
    }
    if (p.ghost != null) {
      final pos = _toStage(e.position);
      p.ghost = pos - const Offset(36, 36);
      final ok = _overPig(pos);
      if (ok != _dropOk) setState(() => _dropOk = ok);
      clock.ping();
      if (_reduce) setState(() {});
    }
  }

  void _onPtrUp(PointerUpEvent e) {
    final p = _ptr;
    _ptr = null;
    if (p == null) return;
    final wasOk = _dropOk;
    if (_dropOk) setState(() => _dropOk = false);
    if (p.ghost == null) {
      // 沒拖動＝點一下
      _feed(_buttonCenterInStage());
      return;
    }
    final center = p.ghost! + const Offset(36, 36);
    if (wasOk || _overPig(center)) {
      _feed(center);
    } else {
      widget.onHint?.call('拖到小豬身上就能餵');
      if (_reduce) setState(() {});
    }
  }

  void _onPtrCancel(PointerCancelEvent e) {
    _ptr = null;
    if (_dropOk) setState(() => _dropOk = false);
  }

  Offset _buttonCenterInStage() =>
      Offset(_w - 12 - PetCarrotButton.size / 2, _h - 12 - PetCarrotButton.size / 2);

  // ── 繪製 ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : PetBuddyStage.designWidth;
      _w = w;
      _s = w / PetBuddyStage.designWidth;
      _h = PetBuddyStage.designHeight * _s;
      final size = Size(_w, _h);
      _rain.configure(_reduce ? PetWeather.sunny : widget.weather, size);
      final pal = PetScenePalette.of(_time, widget.weather);

      return SizedBox(
        key: _stageKey,
        width: _w,
        height: _h,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: TweenAnimationBuilder<PetScenePalette>(
            tween: PetScenePaletteTween(end: pal),
            duration: _reduce ? Duration.zero : const Duration(milliseconds: 800),
            builder: (context, p, _) => Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                RepaintBoundary(
                  child: CustomPaint(painter: PetSkyPainter(p, _s)),
                ),
                RepaintBoundary(
                  child: CustomPaint(painter: PetCloudPainter(p, _s, clock)),
                ),
                RepaintBoundary(
                  child: CustomPaint(painter: PetGroundPainter(p, _s)),
                ),
                _buildPigLayer(),
                if (!_reduce)
                  IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: PetRainPainter(
                            _rain, clock, _time == PetTimeOfDay.night),
                      ),
                    ),
                  ),
                _buildChrome(),
                _buildFxLayer(),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildChrome() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 12,
          top: 12,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .25),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_time.label}・${widget.weather.label}',
                style: const TextStyle(
                  fontFamily: 'NotoSansTC',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        if (widget.cornerAction != null)
          Positioned(top: 12, right: 12, child: widget.cornerAction!),
        Positioned(
          right: 12,
          bottom: 12,
          child: Semantics(
            button: true,
            label: widget.carrotCount > 0
                ? '餵胡蘿蔔，還有 ${widget.carrotCount} 根'
                : '胡蘿蔔吃完了，打卡就能賺',
            onTap: () => _feed(_buttonCenterInStage()),
            excludeSemantics: true,
            child: Listener(
              key: const ValueKey('pet-carrot-button'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPtrDown,
              onPointerMove: _onPtrMove,
              onPointerUp: _onPtrUp,
              onPointerCancel: _onPtrCancel,
              child: PetCarrotButton(count: widget.carrotCount),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPigLayer() {
    return AnimatedBuilder(
      animation: clock,
      builder: (context, _) {
        final r = _pigRect();
        final s = _s;
        return Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            Positioned(
              left: r.left,
              top: r.top,
              width: r.width,
              height: r.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 柔和影子（沒有白圈）
                  Positioned(
                    left: r.width * .11,
                    width: r.width * .78,
                    bottom: -6 * s,
                    height: 20 * s,
                    child: const IgnorePointer(
                      child: CustomPaint(painter: _ShadowPainter()),
                    ),
                  ),
                  if (_dropOk)
                    Positioned(
                      left: -10 * s,
                      right: -10 * s,
                      top: -14 * s,
                      bottom: -4 * s,
                      child: const IgnorePointer(
                        child: CustomPaint(painter: _DashedRingPainter()),
                      ),
                    ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _onPigTap,
                      child: Semantics(
                        label: '摸摸小豬',
                        button: true,
                        child: Transform(
                          alignment: Alignment.bottomCenter,
                          transform: _pigMatrix(s),
                          child: Transform(
                            alignment: Alignment.bottomCenter,
                            transform: _bodyMatrix(s),
                            child: PetPigSprite(
                              breed: widget.breed,
                              view: _view,
                              stage: _shownStage,
                              flip: _flip,
                              tagAngle: _pend.angle,
                              anchors: _anchors,
                              width: r.width,
                              height: r.height,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // `.pig` 的 hop／ready／chew（transform-origin 50% 100%）
  Matrix4 _pigMatrix(double s) {
    final t = _now - _animStart;
    final m = Matrix4.identity();
    switch (_anim) {
      case _PigAnim.none:
        return m;
      case _PigAnim.ready:
        final k = Curves.easeOut.transform((t / .35).clamp(0.0, 1.0));
        _mScale(m, 1 + .06 * k, 1 - .08 * k);
        return m;
      case _PigAnim.chew:
        if (t >= 1.2) {
          _anim = _PigAnim.none;
          return m;
        }
        final ph = (t % .3) / .3;
        final k = Curves.easeInOut.transform(ph < .5 ? ph / .5 : (ph - .5) / .5);
        // 0%/100%：(1.04,.95)；50%：(.97,1.04)
        final a = ph < .5 ? (1.04, .95) : (.97, 1.04);
        final b = ph < .5 ? (.97, 1.04) : (1.04, .95);
        _mScale(m, a.$1 + (b.$1 - a.$1) * k, a.$2 + (b.$2 - a.$2) * k);
        return m;
      case _PigAnim.hop:
        if (t >= .5) {
          _anim = _PigAnim.none;
          return m;
        }
        const curve = Cubic(.3, 1.6, .5, 1);
        // keyframes：0 / 20% / 50% / 80% / 100%
        const kf = <(double, double, double, double)>[
          (0, 1, 1, 0),
          (.2, 1.08, .9, 0),
          (.5, .95, 1.06, -26),
          (.8, 1.04, .96, 0),
          (1, 1, 1, 0),
        ];
        final p = t / .5;
        for (var i = 0; i < kf.length - 1; i++) {
          if (p <= kf[i + 1].$1) {
            final a = kf[i], b = kf[i + 1];
            final k = curve.transform((p - a.$1) / (b.$1 - a.$1));
            double l(double x, double y) => x + (y - x) * k;
            _mTranslate(m, 0.0, l(a.$4, b.$4) * s);
            _mScale(m, l(a.$2, b.$2), l(a.$3, b.$3));
            break;
          }
        }
        return m;
    }
  }

  // `.pigbody` 的呼吸／小跑／翻轉（transform-origin 50% 100%）
  Matrix4 _bodyMatrix(double s) {
    final m = Matrix4.identity();
    if (_reduce) {
      if (_flip) _mScale(m, -1.0, 1.0);
      return m;
    }
    if (_bobbing) {
      final ph = ((_now - _bobStart) % .32) / .32;
      final k = Curves.easeInOut.transform(ph < .5 ? ph / .5 : 1 - (ph - .5) / .5);
      if (_flip) _mScale(m, -1.0, 1.0);
      _mTranslate(m, 0.0, -4 * s * k);
      m.rotateZ((_flip ? 1.5 : -1.5) * k * math.pi / 180);
      return m;
    }
    if (_flip) {
      _mScale(m, -1.0, 1.0);
      return m;
    }
    final ph = (_now % 3.2) / 3.2;
    final k = Curves.easeInOut.transform(ph < .5 ? ph / .5 : 1 - (ph - .5) / .5);
    _mScale(m, 1 - .01 * k, 1 + .025 * k);
    return m;
  }

  Widget _buildFxLayer() {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: clock,
        builder: (context, _) {
          final now = _now;
          final kids = <Widget>[
            CustomPaint(size: Size(_w, _h), painter: _FxPainter(List.of(_fx), now)),
          ];
          final fly = _flyer;
          if (fly != null) {
            final k = ((now - fly.t0) / _flyDuration).clamp(0.0, 1.0);
            final e = k < .5 ? 2 * k * k : 1 - math.pow(-2 * k + 2, 2) / 2;
            double bez(double a, double c, double b) =>
                (1 - e) * (1 - e) * a + 2 * (1 - e) * e * c + e * e * b;
            kids.add(Positioned(
              left: bez(fly.start.dx, fly.ctrl.dx, fly.to.dx),
              top: bez(fly.start.dy, fly.ctrl.dy, fly.to.dy),
              child: Transform.rotate(
                angle: -e * 220 * math.pi / 180,
                child: Transform.scale(scale: 1 - e * .55, child: _carrotImg(64)),
              ),
            ));
          }
          final g = _ptr?.ghost;
          if (g != null) {
            kids.add(Positioned(left: g.dx, top: g.dy, child: _carrotImg(72)));
          }
          return Stack(clipBehavior: Clip.none, children: kids);
        },
      ),
    );
  }

  Widget _carrotImg(double size) => Image.asset(
        'assets/images/pet_foods/food_carrot.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        errorBuilder: (_, __, ___) =>
            SizedBox(width: size, height: size, child: const Center(child: Text('🥕'))),
      );
}

class _ShadowPainter extends CustomPainter {
  const _ShadowPainter();
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(1, size.height / size.width);
    final r = size.width / 2;
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color.fromRGBO(0, 0, 0, .24), Color.fromRGBO(0, 0, 0, 0)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShadowPainter old) => false;
}

class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.elliptical(size.width * .4, size.height * .4),
    );
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final m in (Path()..addRRect(rr)).computeMetrics()) {
      for (double d = 0; d < m.length; d += 12) {
        canvas.drawPath(m.extractPath(d, math.min(d + 7, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => false;
}

class _FxPainter extends CustomPainter {
  final List<_Fx> items;
  final double now;
  _FxPainter(this.items, this.now);

  static Path _heart() => Path()
    ..moveTo(12, 20)
    ..cubicTo(12, 20, 5, 15.8, 5, 10.8)
    ..arcToPoint(const Offset(12, 8.4), radius: const Radius.circular(3.9))
    ..arcToPoint(const Offset(19, 10.8), radius: const Radius.circular(3.9))
    ..cubicTo(19, 15.8, 12, 20, 12, 20)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in items) {
      final t = now - f.start;
      if (t < 0 || t > f.duration) continue;
      if (f.heart) {
        // float：0% o0 ty10 s.6 → 15% o1 ty0 s1.1 → 100% o0 ty-90 s1（ease-out）
        double o, ty, sc;
        const e = Curves.easeOut;
        final p = t / f.duration;
        if (p < .15) {
          final k = e.transform(p / .15);
          o = k;
          ty = 10 - 10 * k;
          sc = .6 + .5 * k;
        } else {
          final k = e.transform((p - .15) / .85);
          o = 1 - k;
          ty = -90 * k;
          sc = 1.1 - .1 * k;
        }
        canvas.save();
        canvas.translate(f.x, f.y + ty);
        canvas.translate(13, 13);
        canvas.scale(sc);
        canvas.translate(-13, -13);
        canvas.scale(26 / 24);
        canvas.drawPath(
            _heart(), Paint()..color = f.color.withValues(alpha: o.clamp(0.0, 1.0)));
        canvas.restore();
      } else {
        final k = const Cubic(.2, .6, .4, 1).transform(t / f.duration);
        canvas.drawCircle(
          Offset(f.x + f.dx * k, f.y + f.dy * k),
          4,
          Paint()..color = f.color.withValues(alpha: 1 - k),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FxPainter old) => true;
}

void _mScale(Matrix4 m, double x, double y) => m.scaleByDouble(x, y, 1, 1);
void _mTranslate(Matrix4 m, double x, double y) =>
    m.translateByDouble(x, y, 0, 1);
