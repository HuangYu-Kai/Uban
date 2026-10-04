import 'dart:convert';

import 'package:flutter/services.dart';

/// 小豬品種（資產檔名前綴）。
enum PetBreed {
  pink('pink', '粉紅豬'),
  black('black', '黑豬');

  final String id;
  final String label;
  const PetBreed(this.id, this.label);

  static PetBreed fromId(String? id) =>
      PetBreed.values.firstWhere((b) => b.id == id, orElse: () => PetBreed.pink);
}

/// 小豬視角：正面（平常）／側面（走路，鼻子朝左）。
enum PetView {
  front,
  side;

  String get id => name;
}

/// 單一耳標錨點（對應 `ear_anchors.json` 的一筆）。
class PetEarAnchor {
  /// 耳朵穿孔位置，占小豬圖片寬度的比例（0~1）。
  final double x;

  /// 耳朵穿孔位置，占小豬圖片高度的比例（0~1）。
  final double y;

  /// 耳標寬度 ÷ 小豬圖片高度。
  final double scale;

  /// 身體水平翻轉（朝右走）時，耳標是否畫在頭部圖層後面。
  final bool behindHeadWhenFlipped;

  const PetEarAnchor({
    required this.x,
    required this.y,
    required this.scale,
    required this.behindHeadWhenFlipped,
  });

  factory PetEarAnchor.fromJson(Map<String, dynamic> j) => PetEarAnchor(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        scale: (j['scale'] as num).toDouble(),
        behindHeadWhenFlipped: j['behindHeadWhenFlipped'] == true,
      );
}

/// 耳標錨點表：2 品種 × 2 視角 × 5 階 = 20 筆。
class PetEarAnchors {
  static const String assetPath = 'assets/images/pet_breeds/ear_anchors.json';

  final Map<String, PetEarAnchor> entries;

  /// 朝右走（身體翻轉）時，耳標往遠側耳朵挪的量（翻轉前座標、占圖寬比例）。
  final double flipDx;
  final double flipDy;

  /// 翻轉時耳標調暗的亮度倍率。
  final double flipDim;

  const PetEarAnchors({
    required this.entries,
    this.flipDx = 0.05,
    this.flipDy = -0.03,
    this.flipDim = 0.8,
  });

  static String keyOf(PetBreed breed, PetView view, int stage) =>
      '${breed.id}_${view.id}_$stage';

  /// [stage] 為 1~5；超出範圍會夾到邊界。
  PetEarAnchor? lookup(PetBreed breed, PetView view, int stage) =>
      entries[keyOf(breed, view, stage.clamp(1, 5))];

  factory PetEarAnchors.fromJsonString(String raw) {
    final root = jsonDecode(raw) as Map<String, dynamic>;
    final map = <String, PetEarAnchor>{};
    (root['entries'] as Map<String, dynamic>).forEach((k, v) {
      map[k] = PetEarAnchor.fromJson(v as Map<String, dynamic>);
    });
    final flipped = root['flipped'] as Map<String, dynamic>?;
    return PetEarAnchors(
      entries: map,
      flipDx: (flipped?['dx'] as num?)?.toDouble() ?? 0.05,
      flipDy: (flipped?['dy'] as num?)?.toDouble() ?? -0.03,
      flipDim: (flipped?['dim'] as num?)?.toDouble() ?? 0.8,
    );
  }

  static PetEarAnchors? _cached;

  /// 讀取（並快取）資產檔。
  static Future<PetEarAnchors> load([AssetBundle? bundle]) async {
    if (_cached != null && bundle == null) return _cached!;
    final raw = await (bundle ?? rootBundle).loadString(assetPath);
    final parsed = PetEarAnchors.fromJsonString(raw);
    if (bundle == null) _cached = parsed;
    return parsed;
  }
}

/// 小豬圖片的原始像素尺寸（寬, 高），用來在不量測 layout 的情況下算出圖寬。
/// 與 `assets/images/pet_breeds/{breed}_{view}_{n}.png` 一致。
const Map<String, List<int>> kPetSpriteSize = {
  'pink_front_1': [227, 355],
  'pink_front_2': [256, 375],
  'pink_front_3': [279, 392],
  'pink_front_4': [293, 400],
  'pink_front_5': [326, 409],
  'pink_side_1': [253, 215],
  'pink_side_2': [332, 249],
  'pink_side_3': [363, 269],
  'pink_side_4': [428, 303],
  'pink_side_5': [549, 335],
  'black_front_1': [184, 316],
  'black_front_2': [257, 395],
  'black_front_3': [304, 448],
  'black_front_4': [341, 496],
  'black_front_5': [418, 554],
  'black_side_1': [219, 142],
  'black_side_2': [281, 191],
  'black_side_3': [353, 236],
  'black_side_4': [411, 276],
  'black_side_5': [520, 301],
};

/// 設計稿 `FRONT_H`／`SIDE_H`：各階小豬圖片高度（設計基準寬 390 的 px）。
const List<double> kPetFrontHeights = [0, 120, 138, 150, 160, 170];
const List<double> kPetSideHeights = [0, 82, 96, 108, 118, 128];

String petSpriteAsset(PetBreed breed, PetView view, int stage) =>
    'assets/images/pet_breeds/${PetEarAnchors.keyOf(breed, view, stage.clamp(1, 5))}.png';

String petEarTagAsset(int stage) =>
    'assets/images/pet_breeds/ear_tag_${stage.clamp(1, 5)}.png';
