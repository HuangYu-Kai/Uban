import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/ui/uban_text.dart';
import '../../pet_companion_studio/services/pet_progress_service.dart';
import '../profile/widgets/pet_corner_actions.dart';

/// 排行榜卡標題旁的「第 3 季・還有 12 天」膠囊（設計稿 `.tag` 暖色）。
///
/// 季資料沿用既有 [PetProgressService.loadSeason]；點下去開啟與精簡模式 🗓️
/// 相同的賽季說明彈窗（[PetCornerActions.showSeasonInfoDialog]）。載入失敗時
/// 不顯示，不編造數字。
class PetSeasonChip extends StatefulWidget {
  /// 僅供 widget test 注入假資料（比照 `PetCornerActions.debugInitialSeasonForTest`）。
  @visibleForTesting
  final PetSeasonInfo? debugInitialSeasonForTest;

  const PetSeasonChip({super.key, this.debugInitialSeasonForTest});

  @override
  State<PetSeasonChip> createState() => _PetSeasonChipState();
}

class _PetSeasonChipState extends State<PetSeasonChip> {
  PetSeasonInfo? _season;

  @override
  void initState() {
    super.initState();
    final debug = widget.debugInitialSeasonForTest;
    if (debug != null) {
      _season = debug;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final season = await PetProgressService.loadSeason();
    if (mounted && season != null) setState(() => _season = season);
  }

  @override
  Widget build(BuildContext context) {
    final season = _season;
    if (season == null) return const SizedBox.shrink();
    final c = UbanColors.of(context);
    return Semantics(
      button: true,
      label: '第 ${season.seasonNo} 季，還有 ${season.daysRemaining} 天，點一下看說明',
      child: Material(
        color: c.warmContainer,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            HapticFeedback.lightImpact();
            PetCornerActions.showSeasonInfoDialog(context, season);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              '第 ${season.seasonNo} 季・還有 ${season.daysRemaining} 天',
              style: ubanText(15, FontWeight.w700, c.warm),
            ),
          ),
        ),
      ),
    );
  }
}
