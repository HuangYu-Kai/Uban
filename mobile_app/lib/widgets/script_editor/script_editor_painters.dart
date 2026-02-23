import 'package:flutter/material.dart';
import '../../models/script_node.dart';

class NodeLinkPainter extends CustomPainter {
  final List<ScriptNode> nodes;
  final String? activeNodeId;
  NodeLinkPainter(this.nodes, this.activeNodeId);

  @override
  void paint(Canvas canvas, Size size) {
    for (var node in nodes) {
      if (node.childrenIds.isEmpty) continue;
      final start = node.position + const Offset(110, 100);

      bool isNodeActive = activeNodeId == node.id;

      for (var cid in node.childrenIds) {
        final childNode = nodes.any((n) => n.id == cid)
            ? nodes.firstWhere((n) => n.id == cid)
            : null;
        if (childNode == null) continue;

        final end = childNode.position + const Offset(110, 0);
        bool isPathActive =
            isNodeActive &&
            (activeNodeId !=
                null); // Simplification: highlight all outgoing from active

        final paint = Paint()
          ..color = isPathActive
              ? Colors.blueAccent.withValues(alpha: 0.6)
              : Colors.white24
          ..strokeWidth = isPathActive ? 3 : 2
          ..style = PaintingStyle.stroke;

        final arrowPaint = Paint()
          ..color = isPathActive
              ? Colors.blueAccent.withValues(alpha: 0.8)
              : Colors.white24
          ..style = PaintingStyle.fill;

        final path = Path()..moveTo(start.dx, start.dy);
        path.cubicTo(
          start.dx,
          start.dy + 60,
          end.dx,
          end.dy - 60,
          end.dx,
          end.dy,
        );

        if (isPathActive) {
          // Glow effect for active path
          canvas.drawPath(
            path,
            Paint()
              ..color = Colors.blueAccent.withValues(alpha: 0.2)
              ..strokeWidth = 8
              ..style = PaintingStyle.stroke
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
          );
        }

        canvas.drawPath(path, paint);

        // Draw Arrowhead
        final arrowPath = Path();
        arrowPath.moveTo(end.dx, end.dy);
        arrowPath.lineTo(end.dx - 6, end.dy - 10);
        arrowPath.lineTo(end.dx + 6, end.dy - 10);
        arrowPath.close();
        canvas.drawPath(arrowPath, arrowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.02)
      ..strokeWidth = 0.5;
    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
