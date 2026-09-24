// 新聞內頁捲動提示文案／樣式迴歸測試（第五十三輪，任務 8）。
//
// 使用者原話：「點進新聞後會有『往下滑查看更多新聞』，將其改成『在此處
// 往上滑查看更多新聞』，並將顏色用的更顯眼，且放大該提示文字的字體
// 大小」。
//
// 背景：見 `news_listen_player_screen.dart` 內該提示文字上方的說明——
// 原文「往下滑查看更多新聞」方向寫反了（`onVerticalDragUpdate` 的註解
// 明講「Dragging UP（負值 delta）pulls panel UP」，`onVerticalDragEnd`
// 也是 `velocity < -300`〔往上滑〕才觸發 `_expandPanel()`），且長輩端
// 反映字級太小（原本硬寫死 18pt）、顏色不夠顯眼（原本 `Colors.white70`）。
//
// ⚠️ 本檔是 `news_listen_player_screen.dart` 第一次有 widget test 覆蓋，
// 過程中意外發現：**即使完全不改任何文字／字級**，`_buildListeningView()`
// 外層 Column 在 flutter test 預設的 800x600（近似橫向比例）畫布下就已經
// 溢位；換成本專案慣用的直向手機量測基準（360x640／412x915，見
// `elder_home_tab_news_visibility_test.dart`）後，360x640／375x667 這兩個
// 常見窄機尺寸也各自溢位 10px／25px——這是既有問題，不是本輪任務 8 造成
// 的，但鐵律 #14 是無條件的硬性規則，遇到就一併修掉（合併
// `_buildListeningView()`／`_buildPlayerHeader()` 內幾處通用留白，完整
// 理由見程式碼內對應註解），不是去動與本輪無關的其他 213 處候選點。
//
// 因此本檔改用本專案標準的直向手機尺寸量測（比照 elder_home_tab 系列），
// 而不是套用 flutter test 預設、與任何真實長輩手機比例都不像的 800x600
// 畫布；並把「不可再有 RenderFlex 溢位」也一併列為硬斷言。
//
// 本檔只驗證「新文案／字級／顏色／箭頭方向／無溢位」這幾個靜態事實，
// 不驅動實際拖曳手勢（拖曳邏輯本身未被本輪改動）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/news_listen_player/news_listen_player_screen.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

void main() {
  final sizes = <({String label, double width, double height})>[
    (label: '360x640（窄機）', width: 360.0, height: 640.0),
    (label: '412x915（大機）', width: 412.0, height: 915.0),
  ];

  for (final size in sizes) {
    testWidgets('${size.label}：捲動提示文案改為「往上滑」、字級與顏色皆升級，且不溢位',
        (tester) async {
      tester.view.physicalSize = Size(size.width, size.height);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: NewsListenPlayerScreen(
            newsItems: [
              {
                'id': 'fake-1',
                'title': 'TEST_NEWS_TITLE',
                'category': '生活',
              },
            ],
            initialIndex: 0,
            userId: 1,
          ),
        ),
      );
      // 只 pump 固定次數、不用 pumpAndSettle——本畫面有音訊播放與字幕等
      // 非同步流程，測試環境網路一律失敗，避免因懸而未決的 Future／Timer
      // 讓 pumpAndSettle 卡住（比照 elder_home_tab 系列測試的既有慣例）。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // ★ 核心斷言之零（鐵律 #14）：本畫面在本尺寸下不可出現 RenderFlex
      // 溢位——過程中發現的既有問題，本輪一併修掉，見檔頭說明。
      expect(tester.takeException(), isNull,
          reason: '${size.label} 不應該出現任何例外（含 RenderFlex 溢位）');

      // ★ 核心斷言之一：舊文案「往下滑查看更多新聞」不應該再出現——方向
      // 寫反了（見檔頭說明），新文案「在此處往上滑查看更多新聞」必須存在。
      expect(find.text('往下滑查看更多新聞'), findsNothing,
          reason: '舊文案方向寫反，第五十三輪 item 8 之後不應該再出現');
      final hintFinder = find.text('在此處往上滑查看更多新聞');
      expect(hintFinder, findsOneWidget, reason: '必須改成使用者指定的新文案');

      // ★ 核心斷言之二：字級沿用 ElderScale.body（22pt，「長輩可讀最小值」），
      // 比原本硬寫死的 18pt 更大，且顏色改用更顯眼的 AppColors.accent，
      // 不再是不易辨識的 Colors.white70。
      final hintWidget = tester.widget<Text>(hintFinder);
      expect(hintWidget.style?.fontSize, ElderScale.body.fontSize,
          reason: '字級應沿用 ElderScale.body（22pt），比原本的 18pt 更大');
      expect(hintWidget.style?.color, AppColors.accent,
          reason: '顏色應改用更顯眼的 AppColors.accent，不應再是 Colors.white70');

      // ★ 箭頭方向必須與「往上滑」的新文案一致，避免文字與圖示互相矛盾。
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing,
          reason: '文案已改成往上滑，不應該再殘留向下箭頭');
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget,
          reason: '箭頭方向應改成向上，與新文案一致');
    });
  }
}
