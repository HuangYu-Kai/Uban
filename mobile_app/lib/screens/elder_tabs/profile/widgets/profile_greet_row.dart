import 'package:flutter/material.dart';

import '../../../../widgets/ui/ui.dart';

/// 「我的」頁首問候列（設計稿 `.greet`）：頭像（名字第一個字）＋名字＋年齡／地區。
///
/// [detail] 只有在既有資料拿得到時才有值（例如「76 歲・臺北市萬華區」），拿不到
/// 就整行不顯示，不補假資料。名字與 [detail] 都是動態字串，一律可收縮＋省略。
class ProfileGreetRow extends StatelessWidget {
  final String name;
  final String? detail;

  const ProfileGreetRow({super.key, required this.name, this.detail});

  /// 以既有的長輩資料組出「76 歲・臺北市萬華區」；兩者都沒有回傳 null。
  static String? buildDetail(Map<String, dynamic>? profile) {
    if (profile == null) return null;
    final ageRaw = profile['age'];
    final age = ageRaw is num ? ageRaw.toInt() : int.tryParse('${ageRaw ?? ''}');
    final city = (profile['residence_city'] ?? '').toString().trim();
    final district = (profile['residence_district'] ?? '').toString().trim();
    final place = '$city$district'.trim();
    final parts = <String>[
      if (age != null && age > 0) '$age 歲',
      if (place.isNotEmpty) place,
    ];
    return parts.isEmpty ? null : parts.join('・');
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '我' : trimmed.characters.first;
    final d = detail;
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.brandContainer,
          ),
          child: Text(initial,
              style: ubanText(24, FontWeight.w900, c.brandStrong)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(trimmed.isEmpty ? '我的' : trimmed,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(26, FontWeight.w900, c.text)),
              if (d != null)
                Text(d,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ubanText(18, FontWeight.w400, c.text2)),
            ],
          ),
        ),
      ],
    );
  }
}
