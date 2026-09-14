import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../pet_companion_studio/models/pet_growth_state.dart';

/// 🐷📋 小豬之家「資訊卡」──版面借用 Pokémon GO 寶可夢詳情頁那張壓在主視覺
/// 下方的白色圓角資訊卡：階段稱號、成長進度條、體重／階段／活力三欄數據，
/// 以及底部「餵小豬」大顆膠囊主按鈕。
///
/// ⚠️ 本元件只負責自己的外觀（白卡＋圓角＋邊框＋柔和陰影），呼叫端要用
/// 負偏移把它疊在 `PetHeroStage` 主視覺下緣——這裡不做任何位移，也不新增
/// 任何後端欄位，全部資料一律來自既有的 [PetGrowthState]。
class PetStatsSheet extends StatelessWidget {
  /// 小豬目前的成長狀態（稱號／進度／體重／活力皆從這裡讀取）。
  final PetGrowthState growthState;

  /// 點擊「餵小豬」大按鈕時觸發；實際開啟食匣抽屜的邏輯交給呼叫端負責。
  final VoidCallback onFeedTap;

  /// 橫向模式時略為收斂內距與稱號字級，維持與直向一致的資訊密度。
  final bool isLandscape;

  const PetStatsSheet({
    super.key,
    required this.growthState,
    required this.onFeedTap,
    this.isLandscape = false,
  });

  @override
  Widget build(BuildContext context) {
    // 是否已是最終階段（PetGrowthStage.values 最後一個，也就是招財金光大
    // 富豬）——已達最高階時 [PetGrowthState.kgToNextStageFormatted] 只會
    // 回傳「已達成最高形態」這種泛用文案，這裡換成更適合長輩讀的祝賀語，
    // 而不是繼續講「再 X 升級」卻沒有下一階可升。
    final bool isMaxStage =
        growthState.stage.index == PetGrowthStage.values.length - 1;
    final String progressCaption =
        isMaxStage ? '已經是最高階段了 👑' : '再 ${growthState.kgToNextStageFormatted} 升級';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(22, isLandscape ? 16 : 24, 22, 22),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: const Color(0xFFEADBCE), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 手把小凸起——暗示這張卡是壓在主視覺上的可視提示
          Center(
            child: Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFEADBCE),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

          // 1. 階段稱號大字
          Text(
            growthState.stage.title,
            style: GoogleFonts.notoSansTc(
              fontSize: isLandscape ? 23 : 27,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF451A03),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 14),

          // 2. 成長進度條
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: growthState.stageProgress,
              minHeight: 12,
              backgroundColor: const Color(0xFFF5EBE1),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            progressCaption,
            style: GoogleFonts.notoSansTc(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF8C6D58),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),

          // 3. 三欄數據（體重｜成長階段｜活力），欄間 1px 直線分隔
          //    比照 Pokémon GO 詳情頁的 weight | type | height 那一列。
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _StatColumn(
                    value: growthState.weightFormatted,
                    label: '體重',
                  ),
                ),
                Container(width: 1, height: 40, color: const Color(0xFFEADBCE)),
                Expanded(
                  child: _StatColumn(
                    value:
                        '${growthState.stage.icon} 第 ${growthState.stage.index + 1} 階',
                    label: '成長階段',
                  ),
                ),
                Container(width: 1, height: 40, color: const Color(0xFFEADBCE)),
                Expanded(
                  child: _StatColumn(
                    value: '${growthState.vitality}%',
                    label: '活力',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // 4. 大顆膠囊主按鈕「🥕 餵小豬」——長輩點擊區至少 64px 高
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.mediumImpact();
                onFeedTap();
              },
              borderRadius: BorderRadius.circular(36),
              child: Container(
                width: double.infinity,
                height: 68,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
                  ),
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Text(
                  '🥕 餵小豬',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF451A03),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 三欄數據其中一欄：上方數值大字、下方標籤小字。
///
/// ⚠️ [value] 一律是隨養成進度變動的動態字串（體重／階段／活力），欄寬又被
/// 三欄均分、系統字級也可能被長輩調大，因此固定 `maxLines: 1` + `ellipsis`，
/// 符合鐵律 #14／護欄 G159「同列多元素時內容需可收縮」的判準。
class _StatColumn extends StatelessWidget {
  final String value;
  final String label;

  const _StatColumn({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          style: GoogleFonts.notoSansTc(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF451A03),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.notoSansTc(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF8C6D58),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
