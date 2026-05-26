import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

class NewsSummaryDialog extends StatelessWidget {
  final String summaryText;
  final VoidCallback onClose;

  const NewsSummaryDialog({
    super.key,
    required this.summaryText,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white.withValues(alpha: 0.95),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/images/pig_summary_expert.png',
                width: 70,
                height: 70,
              ).animate(onPlay: (controller) => controller.repeat())
               .shimmer(duration: 2.seconds)
               .scale(begin: const Offset(1, 1), end: const Offset(1.1, 1.1), duration: 1.seconds, curve: Curves.easeInOut),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  '總結專家小豬',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF59B294),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 30),
          Text(
            summaryText,
            style: GoogleFonts.notoSansTc(
              fontSize: 22,
              height: 1.6,
              color: Colors.black87,
            ),
          ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0),
          const SizedBox(height: 25),
          ElevatedButton(
            onPressed: onClose,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF59B294),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: const Text('我知道了', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
