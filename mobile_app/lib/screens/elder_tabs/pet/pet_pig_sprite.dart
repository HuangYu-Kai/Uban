import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pet_ear_anchors.dart';

/// 小豬本體圖＋耳標。
///
/// 耳標永遠戴在豬的**左耳**：
/// - 正面圖：畫面右側那隻耳；
/// - 側面圖（鼻子朝左）：看得到的那隻耳；
/// - 朝右走（[flip] 為 true、整個身體水平翻轉）：左耳在遠側，耳標改畫在頭部
///   圖層**後面**、往後上方挪一點並調暗，不會鏡像到看得見的那隻耳。
///
/// z 順序就是 [Stack] 的子項順序：翻轉且錨點要求時，耳標在前（下層）、豬圖在
/// 後（上層）；其餘情況耳標在豬圖上面。測試用 [earTagKey]／[pigImageKey] 斷言。
class PetPigSprite extends StatelessWidget {
  static const Key earTagKey = ValueKey('pet-ear-tag');
  static const Key pigImageKey = ValueKey('pet-pig-image');

  final PetBreed breed;
  final PetView view;
  final int stage;

  /// 身體是否水平翻轉（朝右走）。翻轉本身由外層 Transform 負責，這裡只決定
  /// 耳標的層次與位移。
  final bool flip;

  /// 耳標鐘擺角度（度）。
  final double tagAngle;

  final PetEarAnchors? anchors;

  /// 圖片實際顯示尺寸（已含舞台縮放）。
  final double width;
  final double height;

  const PetPigSprite({
    super.key,
    required this.breed,
    required this.view,
    required this.stage,
    required this.flip,
    required this.tagAngle,
    required this.anchors,
    required this.width,
    required this.height,
  });

  /// 翻轉時耳標是否畫在頭後（供測試與 build 共用）。
  bool get tagBehindHead {
    final a = anchors?.lookup(breed, view, stage);
    return flip && (a?.behindHeadWhenFlipped ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(
      petSpriteAsset(breed, view, stage),
      key: pigImageKey,
      width: width,
      height: height,
      fit: BoxFit.fill,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
      errorBuilder: (_, __, ___) => SizedBox(width: width, height: height),
    );
    final tag = _buildTag();
    final behind = tagBehindHead;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (tag != null && behind) tag,
          Positioned.fill(child: img),
          if (tag != null && !behind) tag,
        ],
      ),
    );
  }

  Widget? _buildTag() {
    final set = anchors;
    final a = set?.lookup(breed, view, stage);
    if (set == null || a == null) return null;
    final shifted = tagBehindHead;
    final left = a.x * width + (shifted ? set.flipDx * width : 0);
    final top = a.y * height + (shifted ? set.flipDy * width : 0);
    Widget tag = Image.asset(
      petEarTagAsset(stage),
      width: height * a.scale,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
    if (shifted) {
      final d = set.flipDim;
      tag = ColorFiltered(
        colorFilter: ColorFilter.matrix(<double>[
          d, 0, 0, 0, 0, //
          0, d, 0, 0, 0,
          0, 0, d, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: tag,
      );
    }
    return Positioned(
      key: earTagKey,
      left: left,
      top: top,
      // CSS：transform-origin 50% 12%、translate(-50%,-12%) 後以該點為軸心擺動。
      child: FractionalTranslation(
        translation: const Offset(-.5, -.12),
        child: Transform.rotate(
          angle: tagAngle * math.pi / 180,
          alignment: const Alignment(0, -.76),
          child: tag,
        ),
      ),
    );
  }
}
