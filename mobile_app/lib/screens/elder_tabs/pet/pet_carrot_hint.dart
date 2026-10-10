import 'package:flutter/material.dart';

import '../../../widgets/ui/ui.dart';

/// 舞台下方的胡蘿蔔進度提示（常駐）。文字由 `CarrotProgress.hintText` 提供。
class PetCarrotHint extends StatelessWidget {
  final String text;

  const PetCarrotHint({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.warmContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Text('🥕', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: ubanText(18, FontWeight.w700, c.text, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
