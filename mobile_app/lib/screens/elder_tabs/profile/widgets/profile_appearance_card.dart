import 'package:flutter/material.dart';

import '../../../../theme/elder_theme_mode.dart';
import '../../../../widgets/ui/ui.dart';

/// 「我的」分頁的「外觀」卡片：跟隨系統／淺色／深色三段切換。
///
/// 選取狀態跟著 [ElderThemeModeController]；[controller] 預設為共用實例（測試可注入）。
class ProfileAppearanceCard extends StatelessWidget {
  final ElderThemeModeController? controller;

  const ProfileAppearanceCard({super.key, this.controller});

  static const _modes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];

  @override
  Widget build(BuildContext context) {
    final ctrl = controller ?? ElderThemeModeController.instance;
    final c = UbanColors.of(context);
    return UbanCard(
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: ctrl,
        builder: (context, mode, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('外觀', style: ubanText(20, FontWeight.w800, c.text)),
            const SizedBox(height: 4),
            Text('選擇畫面要亮色、暗色，或跟著手機走',
                style: ubanText(18, FontWeight.w500, c.text2)),
            const SizedBox(height: 14),
            UbanSegmented(
              labels: const ['跟隨系統', '淺色', '深色'],
              index: _modes.indexOf(mode),
              onChanged: (i) => ctrl.set(_modes[i]),
            ),
          ],
        ),
      ),
    );
  }
}
