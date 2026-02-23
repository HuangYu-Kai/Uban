import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/script_node.dart';

class NodeCard extends StatelessWidget {
  final ScriptNode node;
  final bool isSelected;
  final bool isActive;
  final VoidCallback onTap;
  final Function(DragUpdateDetails) onPanUpdate;
  final VoidCallback onDoubleTap;
  final VoidCallback onQuickAdd;

  const NodeCard({
    super.key,
    required this.node,
    required this.isSelected,
    required this.isActive,
    required this.onTap,
    required this.onPanUpdate,
    required this.onDoubleTap,
    required this.onQuickAdd,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: 300.ms,
      curve: Curves.easeOutCubic,
      left: node.position.dx,
      top: node.position.dy,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onPanUpdate: onPanUpdate,
            onTap: onTap,
            child: AnimatedScale(
              scale: isActive ? 1.05 : 1.0,
              duration: 300.ms,
              curve: Curves.easeOutBack,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: 220,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252525).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: isActive
                            ? Colors.blueAccent
                            : (isSelected
                                  ? Colors.white
                                  : node.color.withValues(alpha: 0.4)),
                        width: (isActive || isSelected) ? 3 : 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isActive ? Colors.blueAccent : node.color)
                              .withValues(alpha: isActive ? 0.3 : 0.1),
                          blurRadius: isActive ? 40 : 20,
                          spreadRadius: isActive ? 5 : 0,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: node.color.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                node.icon,
                                color: node.color,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                node.title,
                                style: GoogleFonts.notoSansTc(
                                  color: node.color,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onDoubleTap: onDoubleTap,
                          child: Text(
                            node.content,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansTc(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (node.childrenIds.isEmpty || isSelected)
            Positioned(
              bottom: -20,
              left: 44,
              right: 44,
              child: Center(
                child:
                    GestureDetector(
                          onTap: onQuickAdd,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  node.color,
                                  node.color.withValues(alpha: 0.8),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: node.color.withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        )
                        .animate(
                          onPlay: (controller) =>
                              controller.repeat(reverse: true),
                        )
                        .scale(
                          duration: 1500.ms,
                          begin: const Offset(1, 1),
                          end: const Offset(1.05, 1.05),
                          curve: Curves.easeInOut,
                        ),
              ),
            ),
        ],
      ),
    );
  }
}
