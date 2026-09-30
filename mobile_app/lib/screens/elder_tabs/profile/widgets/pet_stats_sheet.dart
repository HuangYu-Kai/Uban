import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../pet_companion_studio/models/pet_growth_state.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// 🐷📋 小豬之家「資訊卡」──版面借用 Pokémon GO 寶可夢詳情頁那張壓在主視覺
/// 下方的白色圓角資訊卡：階段稱號、自訂小豬名稱、成長進度條、體重／階段／活力三欄數據，
/// 以及底部「餵小豬」大顆膠囊主按鈕。
///
/// ⚠️ 本元件只負責自己的外觀（白卡＋全圓角＋邊框＋柔和陰影），呼叫端要用
/// 負偏移把它疊在 `PetHeroStage` 主視覺下緣。
class PetStatsSheet extends StatefulWidget {
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
  State<PetStatsSheet> createState() => _PetStatsSheetState();
}

class _PetStatsSheetState extends State<PetStatsSheet> {
  static const String _prefPetNameKey = 'custom_pet_name';
  String? _customPetName;

  @override
  void initState() {
    super.initState();
    _loadCustomPetName();
  }

  Future<void> _loadCustomPetName() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefPetNameKey);
    if (saved != null && saved.trim().isNotEmpty && mounted) {
      setState(() {
        _customPetName = saved.trim();
      });
    }
  }

  Future<void> _saveCustomPetName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(_prefPetNameKey);
      if (mounted) {
        setState(() {
          _customPetName = null;
        });
      }
    } else {
      await prefs.setString(_prefPetNameKey, trimmed);
      if (mounted) {
        setState(() {
          _customPetName = trimmed;
        });
      }
    }
  }

  void _showEditNameDialog() {
    final controller = TextEditingController(
      text: _customPetName ?? widget.growthState.stage.title,
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(0xFFFFFDF9),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF3C7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.edit_rounded,
                color: Color(0xFFB45309),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '為小豬取名字',
              style: GoogleFonts.notoSansTc(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: const Color(0xFF451A03),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '請輸入您喜歡的稱呼（例如：發財豬、圓圓、阿財）：',
              style: GoogleFonts.notoSansTc(
                fontSize: 15,
                color: const Color(0xFF8C6D58),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 10,
              style: GoogleFonts.notoSansTc(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF451A03),
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFFAF7F2),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                hintText: widget.growthState.stage.title,
                hintStyle: GoogleFonts.notoSansTc(
                  fontSize: 18,
                  color: const Color(0xFFD4C5B9),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFEADBCE)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Color(0xFFF59E0B),
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '取消',
              style: GoogleFonts.notoSansTc(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF8C6D58),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _saveCustomPetName(controller.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              '完成',
              style: GoogleFonts.notoSansTc(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isMaxStage =
        widget.growthState.stage.index == PetGrowthStage.values.length - 1;
    final String progressCaption = isMaxStage
        ? '已經是最高階段了'
        : '再 ${widget.growthState.kgToNextStageFormatted} 升級';

    final displayName = _customPetName ?? widget.growthState.stage.title;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(22, widget.isLandscape ? 16 : 24, 22, 22),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(28),
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

          // 1. 小豬名稱（可點擊鉛筆修改）
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  displayName,
                  style: GoogleFonts.notoSansTc(
                    fontSize: widget.isLandscape ? 23 : 27,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF451A03),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _showEditNameDialog();
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    size: 18,
                    color: Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
          if (_customPetName != null && _customPetName != widget.growthState.stage.title) ...[
            const SizedBox(height: 4),
            Text(
              widget.growthState.stage.title,
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFB45309),
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 14),

          // 2. 成長進度條
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: widget.growthState.stageProgress,
              minHeight: 12,
              backgroundColor: const Color(0xFFF5EBE1),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _StatColumn(
                  value: widget.growthState.weightFormatted,
                  label: '體重',
                ),
              ),
              Container(width: 1, height: 40, color: const Color(0xFFEADBCE)),
              Expanded(
                child: _StatColumn(
                  value: '第 ${widget.growthState.stage.index + 1} 階',
                  label: '成長階段',
                ),
              ),
              Container(width: 1, height: 40, color: const Color(0xFFEADBCE)),
              Expanded(
                child: _StatColumn(
                  value: '${widget.growthState.vitality}%',
                  label: '活力',
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // 4. 大顆膠囊主按鈕「餵小豬」——長輩點擊區至少 64px 高，去除 emoji
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.mediumImpact();
                widget.onFeedTap();
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
                  '餵小豬',
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
      // 不再被 stretch 撐成固定高度，明確以內容決定高度最安全
      mainAxisSize: MainAxisSize.min,
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
