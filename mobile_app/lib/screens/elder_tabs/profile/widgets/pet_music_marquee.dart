import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 🎵 音樂出處跑馬燈——標注目前播放曲目的「作者－歌曲名稱」。
///
/// 需求原文只要求「小小的不要佔用到版面」，且專案沒有現成的 marquee 套件
/// （見 `Uban/CLAUDE.md` 不隨意新增依賴的既有慣例），因此自己用
/// `AnimationController` + `Transform.translate`（實際上用 `Positioned`
/// 位移達到同樣效果）手刻一顆極簡滾動文字，不引入新套件。
///
/// ⚠️ 鐵律 #14 通常要求「Row＋動態字串」包 `Flexible`／`ellipsis`
/// 才算「可收縮」；但跑馬燈的本質就是要讓使用者看到完整文字（只是分批捲動
/// 過去），`ellipsis` 會把後半段文字永遠截斷、失去標注出處的意義。這裡改用
/// 效果等效的收縮手法：外層固定寬度＋`ClipRect` 硬裁切，文字位移量永遠算在
/// 容器範圍內，**保證不會溢出版面**，只是用「捲動」取代「截斷」而已。
///
/// 字級刻意用固定小字（12px）而非專案既有的 `ElderScale` 字級慣例——這是
/// 純裝飾性的版權標注，不是長輩需要辨讀的功能性文字，比照同一個小豬之家子
/// 系統裡其餘裝飾性文字（`pet_hero_stage.dart` 的問候語膠囊、
/// `hand_drawn_piglet_actor.dart` 的對話氣泡與心情標籤）一律用
/// `GoogleFonts.notoSansTc` 搭配自訂小字級、不套用 `ElderScale` 的既有做法。
class PetMusicMarquee extends StatefulWidget {
  /// 要捲動顯示的文字，例如「Erik Satie - 裸體歌舞第一號」。
  final String text;

  const PetMusicMarquee({super.key, required this.text});

  @override
  State<PetMusicMarquee> createState() => _PetMusicMarqueeState();
}

class _PetMusicMarqueeState extends State<PetMusicMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const double _height = 18.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant PetMusicMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 換曲時文字內容跟著換——重置捲動位置到起點，避免文字長度變化造成
    // 位移量瞬間跳位、視覺上像卡頓一下。
    if (oldWidget.text != widget.text) {
      _controller
        ..reset()
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle textStyle = GoogleFonts.notoSansTc(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF78350F).withValues(alpha: 0.75),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth;
        final TextPainter painter = TextPainter(
          text: TextSpan(text: widget.text, style: textStyle),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final double textWidth = painter.width;

        // 文字比容器窄時不必捲動——靜止置中顯示即可，避免小螢幕或短標題
        // 明明放得下卻還跑來跑去，徒增視覺干擾（且靜止時已保證不溢位，不
        // 需要額外的 ClipRect）。
        if (textWidth <= maxWidth) {
          return SizedBox(
            height: _height,
            width: maxWidth,
            child: Center(
              child: Text(widget.text, style: textStyle, maxLines: 1),
            ),
          );
        }

        return ClipRect(
          child: SizedBox(
            height: _height,
            width: maxWidth,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // 從容器右緣外側（dx = maxWidth）捲動到完全滑出左緣
                // （dx = -textWidth），符合一般跑馬燈「由右向左」的直覺。
                final double dx =
                    maxWidth - _controller.value * (maxWidth + textWidth);
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      left: dx,
                      top: 0,
                      child: Text(
                        widget.text,
                        style: textStyle,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
