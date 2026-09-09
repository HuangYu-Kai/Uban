import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/screens/family/memoirs_gallery_screen.dart';

import 'package:flutter_application_1/models/memoir_story.dart';
import 'package:flutter_application_1/services/memoir_service.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('MemoirsGalleryScreen 空白狀態顯示友善提示', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MemoirsGalleryScreen(
          elderId: 'elder_empty',
          elderName: '王阿公',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('📖 王阿公的數位自傳回憶錄'), findsOneWidget);
    expect(find.text('珍藏 0 篇口述回憶 · 世代傳承'), findsOneWidget);
    expect(find.text('目前此分類尚無故事'), findsOneWidget);
  });

  testWidgets('MemoirsGalleryScreen 渲染標題、故事卡片與分類標籤', (WidgetTester tester) async {
    // 預先寫入真實故事（無假資料）
    await MemoirService.instance.saveMemoir(MemoirStory(
      id: 'story_real_1',
      elderId: 'elder_test',
      title: '廟口童玩與純真田埂時光',
      tag: '經典回憶',
      preview: '那時候放學鞋子一脫，大家就衝到廟埕前打陀螺...',
      fullStory: '那時候放學鞋子一脫，大家就衝到廟埕前打陀螺、彈彈珠，或者在剛收割完的稻田裡抓泥鰍烤地瓜。',
      promptQuestion: '小時候都玩什麼？',
      recordedDate: DateTime.now(),
    ));

    await tester.pumpWidget(
      const MaterialApp(
        home: MemoirsGalleryScreen(
          elderId: 'elder_test',
          elderName: '王阿公',
        ),
      ),
    );

    // 等待 SharedPreferences 讀取與 UI 渲染
    await tester.pumpAndSettle();

    // 驗證標題列
    expect(find.text('📖 王阿公的數位自傳回憶錄'), findsOneWidget);
    expect(find.text('珍藏 1 篇口述回憶 · 世代傳承'), findsOneWidget);

    // 驗證分類 ChoiceChip
    expect(find.widgetWithText(ChoiceChip, '全部'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '經典回憶'), findsOneWidget);

    // 驗證真實故事有被呈現
    expect(find.text('廟口童玩與純真田埂時光'), findsOneWidget);

    // 驗證委託提問按鈕
    expect(find.text('委託提問'), findsOneWidget);
  });

  testWidgets('MemoirsGalleryScreen 可切換自傳繪本翻頁模式與委託提問彈窗', (WidgetTester tester) async {
    await MemoirService.instance.saveMemoir(MemoirStory(
      id: 'story_real_1',
      elderId: 'elder_test',
      title: '廟口童玩與純真田埂時光',
      tag: '經典回憶',
      preview: '那時候放學鞋子一脫，大家就衝到廟埕前打陀螺...',
      fullStory: '那時候放學鞋子一脫，大家就衝到廟埕前打陀螺、彈彈珠，或者在剛收割完的稻田裡抓泥鰍烤地瓜。',
      promptQuestion: '小時候都玩什麼？',
      recordedDate: DateTime.now(),
    ));

    await tester.pumpWidget(
      const MaterialApp(
        home: MemoirsGalleryScreen(
          elderId: 'elder_test',
          elderName: '王阿公',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 點擊切換為「繪本翻頁」檢視模式
    final bookIcon = find.byIcon(Icons.auto_stories_rounded);
    expect(bookIcon, findsOneWidget);
    await tester.tap(bookIcon);
    await tester.pumpAndSettle();

    // 驗證繪本翻頁自傳模式章節與標題
    expect(find.text('第 1 / 1 章'), findsOneWidget);
    expect(find.text('廟口童玩與純真田埂時光'), findsOneWidget);
    expect(find.text('聆聽長輩口述原聲 & 留言'), findsOneWidget);

    // 點擊頂部按鈕「委託提問」
    final delegateBtn = find.text('委託提問');
    await tester.tap(delegateBtn);
    await tester.pumpAndSettle();

    // 驗證委託小豬提問彈窗
    expect(find.text('委託小豬向王阿公提問'), findsOneWidget);
    expect(find.text('💡 點選推薦問題：'), findsOneWidget);
    expect(find.text('託付給小豬'), findsOneWidget);
  });
}
