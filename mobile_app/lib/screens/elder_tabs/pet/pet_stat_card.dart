import 'package:flutter/material.dart';

import '../../../widgets/ui/ui.dart';
import '../../pet_companion_studio/models/pet_growth_state.dart';
import 'pet_ear_anchors.dart';

/// 舞台下方的數值卡（設計稿 `.statcard`）：第 N 階、體重、進度條。
/// 只用 [PetGrowthState] 既有的階段／體重／階段進度，不發明新數值。
/// 另外附品種切換（新功能，存在本機 `pet_breed`）。
class PetStatCard extends StatelessWidget {
  final PetGrowthState growth;
  final PetBreed breed;
  final ValueChanged<PetBreed> onBreedChanged;

  const PetStatCard({
    super.key,
    required this.growth,
    required this.breed,
    required this.onBreedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final stageNo = growth.stage.index + 1;
    final isMax = growth.stage == PetGrowthStage.values.last;
    final kg = (growth.weightGrams / 1000).toStringAsFixed(2);
    final hint = isMax
        ? '已達成最高形態'
        : '再胖 ${(growth.gramsToNextStage / 1000).toStringAsFixed(2)} 公斤就到第 ${stageNo + 1} 階';
    final dur = reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 900);

    return UbanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('第 $stageNo 階',
                    style: ubanText(15, FontWeight.w700, c.text2)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text.rich(TextSpan(
                    text: kg,
                    style: ubanBrandText(20, FontWeight.w600, c.text),
                    children: [
                      TextSpan(
                          text: ' 公斤',
                          style: ubanText(15, FontWeight.w700, c.text2)),
                    ],
                  )),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 進度條 12px、surface3 底、brand 填色，寬度 .9 秒彈性動畫。
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 12,
              color: c.surface3,
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: growth.stageProgress.clamp(0.02, 1.0)),
                duration: dur,
                curve: const Cubic(.34, 1.2, .64, 1),
                builder: (context, v, _) => FractionallySizedBox(
                  widthFactor: v.clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.brand,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const SizedBox(height: 12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(hint, style: ubanText(15, FontWeight.w400, c.text2)),
          const SizedBox(height: 12),
          UbanSegmented(
            key: const ValueKey('pet-breed-segmented'),
            labels: [for (final b in PetBreed.values) b.label],
            index: breed.index,
            small: true,
            onChanged: (i) => onBreedChanged(PetBreed.values[i]),
          ),
        ],
      ),
    );
  }
}
