import 'package:flutter/material.dart';

import '../../widgets/ui/uban_glass_nav_bar.dart';

/// 長輩端各分頁底部要讓出的距離：玻璃導覽列高度 + 系統安全區 + 16 呼吸空間。
///
/// 取代舊導覽列（高 104）時代寫死的 104～130，各分頁的捲動內容／輸入列都用
/// 這個值，內容才不會被懸浮導覽列蓋住。
double elderNavClearance(BuildContext context) =>
    UbanGlassNavBar.totalHeight + MediaQuery.paddingOf(context).bottom + 16;

/// 長輩外殼底部導覽列的五個項目（依序：首頁／電話／小豬／聊天／我的）。
///
/// 抽成純函式方便測試。[keys] 若有給，第 i 個 key 會掛在第 i 項上（外部新手
/// 指引 spotlight 用的 `_navItemKeys`）；長度不足的項目不掛 key。
List<UbanNavItem> buildElderNavItems([List<Key?> keys = const []]) {
  Key? k(int i) => i < keys.length ? keys[i] : null;
  return [
    UbanNavItem(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: '首頁',
      key: k(0),
    ),
    UbanNavItem(
      icon: Icons.phone_outlined,
      selectedIcon: Icons.phone_rounded,
      label: '電話',
      key: k(1),
    ),
    UbanNavItem(
      icon: Icons.savings_outlined,
      selectedIcon: Icons.savings_rounded,
      label: '小豬',
      key: k(2),
    ),
    UbanNavItem(
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
      label: '聊天',
      key: k(3),
    ),
    UbanNavItem(
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      label: '我的',
      key: k(4),
    ),
  ];
}
