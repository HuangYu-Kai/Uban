import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart';
import '../controllers/pet_controller.dart';

/// 寵物互動室主視圖
/// 以 Stack 將 3D 場景與透明控制層分離，便於 UI/UX 擴充
class PetRoomView extends StatefulWidget {
  const PetRoomView({super.key});

  @override
  State<PetRoomView> createState() => _PetRoomViewState();
}

class _PetRoomViewState extends State<PetRoomView> {
  static const String _assetPath = 'assets/models/modern_apartment_interior.glb';
  static const String _defaultCameraOrbit = '0deg 75deg 3m';

  bool _isLoading = true; 
  bool _gyroEnabled = false;
  DateTime _lastGyroUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;

  // 相機軌道
  String _cameraOrbit = _defaultCameraOrbit;
  double _yawDeg = 0;
  double _pitchDeg = 75;

  WebViewController? _webViewController;
  
  final GlobalKey _mvKey = GlobalKey(); 

  // 使用 ValueNotifier 避免 setState 導致全域重繪
  final ValueNotifier<Offset> _pigPosNotifier = ValueNotifier(const Offset(-1000, -1000));
  final ValueNotifier<String> _pigStateNotifier = ValueNotifier('idle');
  final ValueNotifier<bool> _pigFacingNotifier = ValueNotifier(true);
  final ValueNotifier<double> _pigScaleNotifier = ValueNotifier(1.0);


  void _setGyroEnabled(bool enabled) {
    if (_gyroEnabled == enabled) return;
    _gyroEnabled = enabled;

    if (!enabled) {
      _gyroSubscription?.cancel();
      _gyroSubscription = null;
      setState(() {});
      return;
    }

    _gyroSubscription?.cancel();
    _gyroSubscription = gyroscopeEventStream().listen((event) {
      final now = DateTime.now();
      if (now.difference(_lastGyroUpdate) < const Duration(milliseconds: 45)) {
        return;
      }
      _lastGyroUpdate = now;

      // 使用角速度近似積分，將裝置旋轉映射到 cameraOrbit。
      const double dt = 0.045;
      const double radiansToDegrees = 57.2958;
      final double yawDelta = (-event.y) * dt * radiansToDegrees;
      final double pitchDelta = event.x * dt * radiansToDegrees;

      _yawDeg = (_yawDeg + yawDelta).clamp(-180.0, 180.0);
      _pitchDeg = (_pitchDeg + pitchDelta).clamp(35.0, 115.0);

      if (!mounted) return;
      final newOrbit = '${_yawDeg.toStringAsFixed(1)}deg ${_pitchDeg.toStringAsFixed(1)}deg 1m';
      setState(() {
        _cameraOrbit = newOrbit;
      });
      _webViewController?.runJavaScript('var mv = document.querySelector("model-viewer"); if(mv) mv.cameraOrbit = "$newOrbit";');
    });

    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    
    // 初始化控制器邏輯
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<PetController>();
      controller.onMoveRequested = (x, z, y, state) => _moveToZone(x, z, y, state);
      controller.startAiLoop();
    });

    // 救援計時器
    Timer(const Duration(seconds: 5), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
        });
        debugPrint("救援計時器：已強行解鎖加載畫面");
      }
    });
  }


  void _resetGyroCamera() {
    _yawDeg = 0;
    _pitchDeg = 75;
    setState(() {
      _cameraOrbit = _defaultCameraOrbit;
    });
    _webViewController?.runJavaScript('var mv = document.querySelector("model-viewer"); if(mv) mv.cameraOrbit = "$_defaultCameraOrbit";');
  }

  void _moveToZone(double x, double z, double y, String state) {
    _webViewController?.runJavaScript('''
      if (window.setPigTarget) {
        window.setPigTarget($x, $z, $y);
        window.setPigState('$state');
      }
    ''');
    // 注意：這裡不呼叫 setState，UI 更新由 Controller 通知 Consumer 完成
  }

  @override
  void dispose() {
    _gyroSubscription?.cancel();
    // 停止控制器循環
    context.read<PetController>().stopAiLoop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PetController>();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
        Positioned.fill(
          child: Selector<PetController, String>(
            selector: (context, ctrl) => ctrl.currentAnimation,
            builder: (context, animName, child) => _StaticModelViewer(
              key: _mvKey,
              src: _assetPath,
              cameraOrbit: _cameraOrbit,
              animationName: animName,
              onWebViewCreated: (controller) => _webViewController = controller,
              javascriptChannels: {
                JavascriptChannel(
                  'ModelTapChannel',
                  onMessageReceived: (message) {
                    try {
                      final data = jsonDecode(message.message);
                      if (data['type'] == 'sync_pig') {
                        if (mounted) {
                          _pigPosNotifier.value = Offset(data['x'].toDouble(), data['y'].toDouble());
                          _pigStateNotifier.value = data['state'];
                          _pigFacingNotifier.value = data['facingRight'];
                          _pigScaleNotifier.value = data['scale']?.toDouble() ?? 1.0;
                        }
                        return;
                      }
                    } catch (e) {
                      debugPrint('Error decoding message: $e');
                    }
                    debugPrint('Received tap message: ${message.message}');
                    controller.handleModelTapPayload(message.message);
                  },
                ),
                JavascriptChannel(
                  'ModelStateChannel',
                  onMessageReceived: (message) {
                    if (!mounted) return;
                    final state = message.message;
                    if (state == 'loaded') {
                      setState(() {
                        _isLoading = false;
                      });
                    } else if (state == 'error') {
                      setState(() {
                        _isLoading = false;
                      });
                    }
                  },
                ),
              },
              relatedJs: '''
                (function() {
                  document.body.style.background = 'transparent';
                  const init = () => {
                    const mv = document.querySelector('model-viewer');
                    if (!mv) { setTimeout(init, 500); return; }
                    if (document.getElementById('hotspot-pig')) return;

                    const btn = document.createElement('div');
                    btn.id = 'hotspot-pig';
                    btn.slot = 'hotspot-pig';
                    btn.style.width = '80px';
                    btn.style.height = '80px';
                    btn.style.background = 'red';
                    btn.style.color = 'white';
                    btn.style.borderRadius = '12px';
                    btn.style.display = 'flex';
                    btn.style.alignItems = 'center';
                    btn.style.justifyContent = 'center';
                    btn.innerText = 'PIG';
                    btn.style.pointerEvents = 'none';
                    btn.setAttribute('data-position', '0 0.5 0');
                    btn.setAttribute('data-normal', '0 1 0');

                    mv.appendChild(btn);
                    const hs = btn;
                    const pigImg = btn; // Use btn itself as fallback

                    let cur = {x: 0, y: 0.5, z: 0};
                    let tgt = {x: 0, y: 0.5, z: 0};
                    let walking = false;

                    window.setPigTarget = (x, z, y) => {
                      tgt = {x, y: 0.5, z};
                      walking = true;
                      if (!window._walkReq) requestAnimationFrame(walk);
                    };

                    const walk = () => {
                      if (!walking) { window._walkReq = null; return; }
                      const dx = tgt.x - cur.x;
                      const dz = tgt.z - cur.z;
                      const d = Math.sqrt(dx*dx + dz*dz);
                      if (d < 0.02) {
                        walking = false;
                        cur.x = tgt.x; cur.z = tgt.z;
                      } else {
                        const s = 0.012;
                        cur.x += (dx/d)*s; cur.z += (dz/d)*s;
                        if (Math.abs(dx) > 0.005) {
                           pigImg.style.transform = (dx > 0) ? 'scaleX(1)' : 'scaleX(-1)';
                        }
                      }
                      hs.setAttribute('data-position', cur.x + ' ' + cur.y + ' ' + cur.z);
                      window._walkReq = requestAnimationFrame(walk);
                    };

                    let isDragging = false;
                    let startX = 0, startY = 0;

                    mv.addEventListener('pointerdown', (e) => {
                      isDragging = false;
                      startX = e.clientX;
                      startY = e.clientY;
                    }, true);

                    mv.addEventListener('pointermove', (e) => {
                      if (Math.abs(e.clientX - startX) > 10 || Math.abs(e.clientY - startY) > 10) {
                        isDragging = true;
                      }
                    }, true);

                    mv.addEventListener('click', (e) => {
                      if (!isDragging) {
                        const h = mv.positionAndNormalFromPoint(e.clientX, e.clientY);
                        if (h && h.position) {
                          window.setPigTarget(h.position.x, h.position.z, 0.05);
                        }
                        e.preventDefault();
                        e.stopImmediatePropagation();
                      }
                    }, true);

                    if (window.ModelStateChannel) window.ModelStateChannel.postMessage('loaded');
                  };
                  init();
                })();
              ''',
            ),
          ),
        ),
        Positioned(
          top: 110,
          left: 24,
          right: 24,
          child: Consumer<PetController>(
            builder: (context, ctrl, child) => _OverlayPanel(
              statusHunger: ctrl.status.hunger,
              statusEnergy: ctrl.status.energy,
              statusHappiness: ctrl.status.happiness,
              dialog: ctrl.currentDialog,
              targetArea: ctrl.targetArea,
              targetX: ctrl.targetPosition.x,
              targetZ: ctrl.targetPosition.z,
              targetConfidence: ctrl.targetPosition.confidence,
              gyroEnabled: _gyroEnabled,
              onGyroChanged: _setGyroEnabled,
              onGyroReset: _resetGyroCamera,
              currentGoal: ctrl.currentGoal,
              pigScale: _pigScaleNotifier.value, // 這裡可以簡單用 Notifier 的值，因為 Panel 本身會隨 Consumer 重建
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 32,
          child: _ActionButtons(
            onPlay: () => context.read<PetController>().play(),
            onFeed: () => context.read<PetController>().feed(),
            onRest: () => context.read<PetController>().rest(),
          ),
        ),
        

        if (_isLoading)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xAA000000),
              child: Center(
                child: _ModelLoadingIndicator(),
              ),
            ),
          ),

        Positioned(
          top: 56,
          left: 16,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  // 如果是作為 main.dart 的 home 直接啟動 (沒有上一頁)，則關閉 App
                  SystemChannels.platform.invokeMethod('SystemNavigator.pop');
                }
              },
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
        ),
      ],
    ),
  );
}

}

class _OverlayPanel extends StatelessWidget {
  final int statusHunger;
  final int statusEnergy;
  final int statusHappiness;
  final String dialog;
  final String targetArea;
  final double targetX;
  final double targetZ;
  final double targetConfidence;
  final bool gyroEnabled;
  final ValueChanged<bool> onGyroChanged;
  final VoidCallback onGyroReset;
  final String currentGoal;
  final double pigScale;

  const _OverlayPanel({
    required this.statusHunger,
    required this.statusEnergy,
    required this.statusHappiness,
    required this.dialog,
    required this.targetArea,
    required this.targetX,
    required this.targetZ,
    required this.targetConfidence,
    required this.gyroEnabled,
    required this.onGyroChanged,
    required this.onGyroReset,
    required this.currentGoal,
    required this.pigScale,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusBar(label: '飢餓度', value: statusHunger, color: Colors.orange),
          const SizedBox(height: 6),
          _StatusBar(label: '體力', value: statusEnergy, color: Colors.blue),
          const SizedBox(height: 6),
          _StatusBar(label: '快樂', value: statusHappiness, color: Colors.pink),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '陀螺儀視角',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              Switch(value: gyroEnabled, onChanged: onGyroChanged),
              TextButton(onPressed: onGyroReset, child: const Text('重置視角')),
            ],
          ),
          Text(
            '目標：$currentGoal | 深度縮放：${pigScale.toStringAsFixed(2)}x',
            style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '目標位置：$targetArea',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            '座標 x:${targetX.toStringAsFixed(2)} z:${targetZ.toStringAsFixed(2)}｜命中率 ${(targetConfidence * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            dialog,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatusBar({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: value / 100,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: Text(
            '$value',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final VoidCallback onPlay;
  final VoidCallback onFeed;
  final VoidCallback onRest;

  const _ActionButtons({
    required this.onPlay,
    required this.onFeed,
    required this.onRest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onPlay,
              child: const Text('玩耍'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: onFeed,
              child: const Text('餵食'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: onRest,
              child: const Text('休息'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelLoadingIndicator extends StatelessWidget {
  const _ModelLoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        SizedBox(height: 10),
        Text(
          '模型載入中...',
          style: TextStyle(color: Colors.white),
        ),
      ],
    );
  }
}

/// 靜態 3D 模型組件，防止任何重建導致的相機跳轉
class _StaticModelViewer extends StatefulWidget {
  final String src;
  final String cameraOrbit;
  final String animationName;
  final Function(WebViewController) onWebViewCreated;
  final Set<JavascriptChannel> javascriptChannels;
  final String relatedJs;

  const _StaticModelViewer({
    super.key,
    required this.src,
    required this.cameraOrbit,
    required this.animationName,
    required this.onWebViewCreated,
    required this.javascriptChannels,
    required this.relatedJs,
  });

  @override
  State<_StaticModelViewer> createState() => _StaticModelViewerState();
}

class _StaticModelViewerState extends State<_StaticModelViewer> {
  @override
  Widget build(BuildContext context) {
    return ModelViewer(
      src: widget.src,
      alt: 'modern apartment scene',
      ar: true,
      autoRotate: false,
      cameraControls: true,
      minCameraOrbit: 'auto auto 0m',
      maxCameraOrbit: 'auto auto 5m',
      cameraOrbit: widget.cameraOrbit,
      animationName: widget.animationName,
      onWebViewCreated: (webViewController) {
        debugPrint('WebView Created - Injecting JS');
        webViewController.runJavaScript(widget.relatedJs);
        widget.onWebViewCreated(webViewController);
      },
      javascriptChannels: widget.javascriptChannels,
      relatedJs: widget.relatedJs,
    );
  }
}
