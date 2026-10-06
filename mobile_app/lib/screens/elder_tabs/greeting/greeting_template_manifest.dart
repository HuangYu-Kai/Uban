import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 祝賀圖「新增範本」資源（CC0 圖庫，來源見
/// `assets/images/greeting_templates/CREDITS.md`）的清單解析與圖庫分組。
/// 清單不存在、空白或格式壞掉時一律當作「沒有新增範本」，App 只用內建範本。
const String kGreetingTemplateDir = 'assets/images/greeting_templates/';
const String kGreetingTemplateManifestPath =
    '${kGreetingTemplateDir}manifest.json';

/// manifest 允許的分類（其餘視為壞資料略過）。
const Set<String> kGreetingManifestCategories = {
  'lotus',
  'koi',
  'sunrise',
  'bamboo',
  'mountain',
  'tea',
  'flower',
  'lake',
};

const Set<String> kGreetingTextPositions = {
  'topLeft',
  'topCenter',
  'topRight',
  'bottomLeft',
};

/// 圖庫分組標題（zh-TW）。內建範本的舊分類也在這裡（flower／tea 與新分類共用）。
const Map<String, String> kGreetingCategoryLabels = {
  'festival': '節慶祝賀',
  'solar_term': '時令節氣',
  'lotus': '蓮花',
  'koi': '錦鯉',
  'sunrise': '日出',
  'bamboo': '竹林',
  'mountain': '高山雲海',
  'tea': '茶園',
  'flower': '花卉',
  'lake': '湖景',
  'scenery': '四季山水',
};

/// 圖庫分組顯示順序。
const List<String> kGreetingCategoryOrder = [
  'festival',
  'solar_term',
  'lotus',
  'koi',
  'sunrise',
  'bamboo',
  'mountain',
  'tea',
  'flower',
  'lake',
  'scenery',
];

/// manifest 單筆範本。
class GreetingTemplateEntry {
  final String id;
  final String file;
  final String category;
  final String title;
  final String textPosition;
  final bool darkBg;

  const GreetingTemplateEntry({
    required this.id,
    required this.file,
    required this.category,
    required this.title,
    required this.textPosition,
    required this.darkBg,
  });

  /// `file` 可寫完整路徑（assets/ 開頭，正式 manifest 的格式）或只寫檔名。
  String get assetPath =>
      file.startsWith('assets/') ? file : '$kGreetingTemplateDir$file';
}

/// 解析 manifest JSON：壞的單筆會被略過、重複 id 只留第一筆；
/// 整份無法解析（null／空字串／不是陣列）回傳空清單。
List<GreetingTemplateEntry> parseGreetingManifest(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const [];
  }
  if (decoded is! List) return const [];
  final seen = <String>{};
  final out = <GreetingTemplateEntry>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final id = item['id'];
    final file = item['file'];
    final category = item['category'];
    final title = item['title'];
    if (id is! String || id.trim().isEmpty) continue;
    if (file is! String || file.trim().isEmpty) continue;
    // 路徑防呆：不允許往上層或絕對路徑
    if (file.contains('..') || file.startsWith('/')) continue;
    if (category is! String ||
        !kGreetingManifestCategories.contains(category)) {
      continue;
    }
    if (title is! String || title.trim().isEmpty) continue;
    if (!seen.add(id.trim())) continue;
    final pos = item['text_position'];
    out.add(GreetingTemplateEntry(
      id: id.trim(),
      file: file.trim(),
      category: category,
      title: title.trim(),
      textPosition:
          pos is String && kGreetingTextPositions.contains(pos) ? pos : 'topLeft',
      darkBg: item['dark_bg'] == true,
    ));
  }
  return out;
}

/// 從 [bundle] 讀 manifest；任何失敗（檔案不存在、讀取例外）都回空清單。
Future<List<GreetingTemplateEntry>> loadGreetingManifest(
    AssetBundle bundle) async {
  try {
    final raw = await bundle.loadString(kGreetingTemplateManifestPath);
    return parseGreetingManifest(raw);
  } catch (e) {
    debugPrint('祝賀圖範本清單未載入（只用內建範本）: $e');
    return const [];
  }
}

/// 圖庫的一個分組（標題＋範本）。
class GreetingGallerySection<T> {
  final String categoryId;
  final String label;
  final List<T> items;

  const GreetingGallerySection({
    required this.categoryId,
    required this.label,
    required this.items,
  });
}

/// 依分類分組並照 [kGreetingCategoryOrder] 排序；沒有範本的分類不出現，
/// 不認識的分類歸到最後的「其他」。組內維持輸入順序。
List<GreetingGallerySection<T>> groupGalleryByCategory<T>(
  Iterable<T> items,
  String Function(T) categoryOf,
) {
  final buckets = <String, List<T>>{};
  for (final it in items) {
    var cat = categoryOf(it);
    if (!kGreetingCategoryLabels.containsKey(cat)) cat = 'other';
    buckets.putIfAbsent(cat, () => []).add(it);
  }
  return [
    for (final cat in [...kGreetingCategoryOrder, 'other'])
      if (buckets[cat] != null)
        GreetingGallerySection<T>(
          categoryId: cat,
          label: kGreetingCategoryLabels[cat] ?? '其他',
          items: buckets[cat]!,
        ),
  ];
}
