import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ★ 2026-09-22 第五十一輪（長5）：長輩端語音助理的**全域**入口。
///
/// 在這之前，叫得出小嘎的地方只有兩個，而且兩個都活在 `ElderHomeScreen` 的
/// `Stack` 裡（喚醒詞監聽、隨身救生圈 FAB），只覆蓋 5 個分頁；任何
/// `Navigator.push` 出去的畫面——通話房、監控、新聞播放器、配對頁——長輩都
/// 叫不出語音助理，這就是使用者回報的「語音助理叫不出來」。
///
/// 解法是把一顆可拖曳、可收邊的浮動麥克風鈕掛在 `MaterialApp.builder` 這一層
/// （比 `Navigator` 更外面，所以蓋得住所有路由），但**不重寫**任何助理邏輯：
/// 真正的啟動流程仍是 `ElderHomeScreen::_triggerGoogleAssistantOverlay`，
/// 它在 `initState` 時把自己登記到 [elderAssistantLauncherNotifier]，浮動鈕只
/// 負責呼叫。這樣喚醒詞暫停、畫面情境注入、`autoCall` 撥號接手全部沿用同一份
/// 程式碼，不會出現兩套會漂移的助理入口。
///
/// 登記者是 `ElderHomeScreen`，所以這顆鈕**只在長輩端登入後存在**——家屬端與
/// 登入前的畫面上 notifier 是 null，什麼都不會畫出來。
typedef ElderAssistantLauncher = void Function([String? prompt]);

/// 目前可用的語音助理啟動器；null＝不是長輩端 session，浮動鈕不顯示。
final ValueNotifier<ElderAssistantLauncher?> elderAssistantLauncherNotifier =
    ValueNotifier<ElderAssistantLauncher?>(null);

/// 目前有幾個「禁止浮動鈕出現」的畫面在畫面上（見 [AssistantHiddenZone]）。
final ValueNotifier<int> assistantHiddenDepthNotifier = ValueNotifier<int>(0);

/// 把不該被浮動鈕遮到的畫面包起來（通話房、來電響鈴畫面、監控畫面）。
///
/// 刻意做成「畫面自己在 `build()` 裡包一層 widget」，而不是去動那些畫面的
/// `initState()` / `dispose()`——`CLAUDE_call-monitor-ui-map.md` §5.4 把通話畫面
/// 的 `initState`/`dispose` 順序列為「絕對不要碰」，但「widget 樹的排版重構」
/// 在可以隨便改的那一欄。這個 widget 自己的 State 生命週期與被包住的路由同生
/// 共死，計數不會漏掉。
class AssistantHiddenZone extends StatefulWidget {
  const AssistantHiddenZone({super.key, required this.child});

  final Widget child;

  @override
  State<AssistantHiddenZone> createState() => _AssistantHiddenZoneState();
}

class _AssistantHiddenZoneState extends State<AssistantHiddenZone> {
  bool _counted = false;

  @override
  void initState() {
    super.initState();
    _counted = true;
    assistantHiddenDepthNotifier.value++;
  }

  @override
  void dispose() {
    // 只減自己加過的那一次，重入或重建都不會把計數推成負的。
    if (_counted) {
      _counted = false;
      final next = assistantHiddenDepthNotifier.value - 1;
      assistantHiddenDepthNotifier.value = next < 0 ? 0 : next;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 全域浮動麥克風鈕本體。掛在 `MaterialApp.builder`，見 `main.dart`。
class GlobalAssistantButton extends StatefulWidget {
  const GlobalAssistantButton({super.key});

  /// 位置以「可用區域的比例」存，換裝置或轉向都不會跑到畫面外。
  static const String _prefsDx = 'assistant_fab_dx';
  static const String _prefsDy = 'assistant_fab_dy';
  static const String _prefsCollapsed = 'assistant_fab_collapsed';

  @override
  State<GlobalAssistantButton> createState() => _GlobalAssistantButtonState();
}

class _GlobalAssistantButtonState extends State<GlobalAssistantButton> {
  static const double _expandedSize = 72; // 長輩端的手指尺寸，不要再縮小
  static const double _collapsedSize = 40;
  static const double _margin = 8;
  static const Duration _idleBeforeCollapse = Duration(seconds: 5);

  /// 0 = 靠左、1 = 靠右；垂直則是 0（頂）~1（底）的比例。
  double _dxFraction = 1;
  double _dyFraction = 0.62;
  bool _collapsed = false;
  bool _dragging = false;
  bool _loaded = false;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _restorePosition();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  Future<void> _restorePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dx = prefs.getDouble(GlobalAssistantButton._prefsDx);
      final dy = prefs.getDouble(GlobalAssistantButton._prefsDy);
      final collapsed = prefs.getBool(GlobalAssistantButton._prefsCollapsed);
      if (!mounted) return;
      setState(() {
        if (dx != null) _dxFraction = dx.clamp(0.0, 1.0);
        if (dy != null) _dyFraction = dy.clamp(0.0, 1.0);
        _collapsed = collapsed ?? false;
        _loaded = true;
      });
    } catch (e) {
      debugPrint('⚠️ [GlobalAssistantButton] 讀取位置失敗，改用預設值: $e');
      if (mounted) setState(() => _loaded = true);
    }
    _scheduleCollapse();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(GlobalAssistantButton._prefsDx, _dxFraction);
      await prefs.setDouble(GlobalAssistantButton._prefsDy, _dyFraction);
      await prefs.setBool(GlobalAssistantButton._prefsCollapsed, _collapsed);
    } catch (e) {
      debugPrint('⚠️ [GlobalAssistantButton] 位置寫入失敗: $e');
    }
  }

  void _scheduleCollapse() {
    _idleTimer?.cancel();
    if (_collapsed) return;
    _idleTimer = Timer(_idleBeforeCollapse, () {
      if (!mounted || _dragging) return;
      setState(() => _collapsed = true);
      _persist();
    });
  }

  void _onTap() {
    if (_collapsed) {
      // 收邊狀態先「叫回來」，避免長輩誤觸半透明小圓點就開始講話。
      setState(() => _collapsed = false);
      _persist();
      _scheduleCollapse();
      return;
    }
    _idleTimer?.cancel();
    final launcher = elderAssistantLauncherNotifier.value;
    if (launcher == null) return;
    launcher();
    _scheduleCollapse();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    return ValueListenableBuilder<ElderAssistantLauncher?>(
      valueListenable: elderAssistantLauncherNotifier,
      builder: (context, launcher, _) {
        if (launcher == null) return const SizedBox.shrink();
        return ValueListenableBuilder<int>(
          valueListenable: assistantHiddenDepthNotifier,
          builder: (context, hiddenDepth, __) {
            // 通話房／來電響鈴／監控畫面上一律讓位，不能擋到接聽與掛斷鍵。
            if (hiddenDepth > 0) return const SizedBox.shrink();
            return _buildDraggable(context);
          },
        );
      },
    );
  }

  Widget _buildDraggable(BuildContext context) {
    final media = MediaQuery.of(context);
    final padding = media.padding;
    final size = _collapsed ? _collapsedSize : _expandedSize;

    final double minX = _margin;
    final double maxX = media.size.width - size - _margin;
    final double minY = padding.top + _margin;
    final double maxY = media.size.height - padding.bottom - size - _margin;
    final double spanX = (maxX - minX).clamp(0.0, double.infinity);
    final double spanY = (maxY - minY).clamp(0.0, double.infinity);

    final double left = minX + spanX * _dxFraction;
    final double top = minY + spanY * _dyFraction;

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        onPanStart: (_) {
          _idleTimer?.cancel();
          setState(() {
            _dragging = true;
            _collapsed = false; // 拖的時候放大，長輩才看得到自己拖到哪
          });
        },
        onPanUpdate: (details) {
          if (spanX <= 0 || spanY <= 0) return;
          setState(() {
            _dxFraction = (_dxFraction + details.delta.dx / spanX).clamp(0.0, 1.0);
            _dyFraction = (_dyFraction + details.delta.dy / spanY).clamp(0.0, 1.0);
          });
        },
        onPanEnd: (_) {
          setState(() {
            _dragging = false;
            _dxFraction = _dxFraction >= 0.5 ? 1.0 : 0.0; // 放開就吸到最近的邊
          });
          _persist();
          _scheduleCollapse();
        },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: _collapsed ? 0.45 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2E7D5B), Color(0xFF1A472A)],
              ),
              boxShadow: _collapsed
                  ? const []
                  : const [
                      BoxShadow(
                        color: Color(0x552E7D5B),
                        blurRadius: 14,
                        offset: Offset(0, 4),
                      ),
                    ],
            ),
            child: Icon(
              Icons.mic,
              color: Colors.white,
              size: _collapsed ? 22 : 38,
              semanticLabel: '語音助理',
            ),
          ),
        ),
      ),
    );
  }
}
