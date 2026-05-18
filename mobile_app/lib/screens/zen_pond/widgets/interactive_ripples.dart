import 'package:flutter/material.dart';
import '../painters/ripple_painter.dart';

class InteractiveRipples extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool isSOSMode;

  const InteractiveRipples({
    super.key, 
    required this.child, 
    required this.onTap, 
    this.isSOSMode = false,
  });

  @override
  State<InteractiveRipples> createState() => _InteractiveRipplesState();
}

class _InteractiveRipplesState extends State<InteractiveRipples> with SingleTickerProviderStateMixin {
  final List<RippleInfo> _ripples = [];
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), 
    )..addListener(() {
        if (_ripples.isEmpty) return;
        
        setState(() {
          for (var ripple in _ripples) {
            // 放慢擴散與淡出的速度，營造更平靜的感覺
            ripple.radius += widget.isSOSMode ? 6.0 : 2.0;
            ripple.opacity -= 0.008;
          }
          _ripples.removeWhere((r) => r.opacity <= 0);
        });
      });
      
    _animationController.repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _addRipple(PointerDownEvent event) {
    setState(() {
      _ripples.add(RippleInfo(position: event.localPosition));
    });
    widget.onTap(); // 觸發 controller 的邏輯 (例如 SOS 計數)
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _addRipple,
      child: Stack(
        children: [
          widget.child,
          // 使用 IgnorePointer 確保漣漪圖層不會阻擋任何點擊
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: RipplePainter(
                ripples: _ripples,
                isSOSMode: widget.isSOSMode,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
