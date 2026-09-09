import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/models/memoir_story.dart';
import 'package:flutter_application_1/widgets/memoir_detail_sheet.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final testStory = MemoirStory(
    id: 'test_story_1',
    elderId: 'elder_001',
    title: '迪化街的布莊歲月',
    tag: '經典回憶',
    preview: '年輕時在迪化街經營布料批發的奮鬥故事...',
    fullStory: '那時候每天清晨天還沒亮，碼頭的貨車就絡繹不絕。做人跟做布料一樣，經緯分明、踏實不偷工，這是我一輩子最驕傲的原則。',
    promptQuestion: '阿公，那時候布莊最讓你得意的是什麼事？',
    audioAssetOrUrl: 'assets/audio/memoir_sample_1.mp3',
    imageAssetOrUrl: 'assets/images/memoir_card.png',
    recordedDate: DateTime(2025, 5, 20),
    isFavorite: false,
    familyNotes: [
      MemoirFamilyNote(
        author: '小宇',
        relation: '長子',
        note: '爸爸的話我永遠記在心裡！',
        createdAt: DateTime(2025, 5, 21),
      ),
    ],
  );

  testWidgets('MemoirDetailSheet 正確呈現故事詳情、播放錄音模擬與留言功能', (WidgetTester tester) async {
    // 設定較大的測試視窗避免 BottomSheet 滾動截斷
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemoirDetailSheet(
            story: testStory,
            elderName: '王阿公',
            familyUserName: '女兒小雅',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 驗證標題、標籤、引導提問與內文
    expect(find.text('迪化街的布莊歲月'), findsOneWidget);
    expect(find.text('經典回憶'), findsOneWidget);
    expect(find.text('小豬溫暖引導提問：'), findsOneWidget);
    expect(find.text('「阿公，那時候布莊最讓你得意的是什麼事？」'), findsOneWidget);
    expect(find.textContaining('做人跟做布料一樣，經緯分明'), findsOneWidget);

    // 驗證長輩原聲錄音區塊
    expect(find.text('王阿公的口述原聲錄音'), findsOneWidget);

    // 驗證既有家屬留言
    expect(find.text('小宇 (長子)'), findsOneWidget);
    expect(find.text('爸爸的話我永遠記在心裡！'), findsOneWidget);

    // 驗證語音播放互動（點擊播放按鈕圖示）
    final playIcon = find.byIcon(Icons.play_arrow_rounded);
    expect(playIcon, findsOneWidget);
    await tester.tap(playIcon);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    // 測試新增家屬悄悄話留言
    final inputField = find.byType(TextField);
    expect(inputField, findsOneWidget);
    await tester.enterText(inputField, '阿公辛苦了，我們這週末回去看您！');
    await tester.pumpAndSettle();

    final sendBtn = find.byIcon(Icons.send_rounded);
    expect(sendBtn, findsOneWidget);
    await tester.tap(sendBtn);
    await tester.pumpAndSettle();

    // 驗證新留言出現在畫面上
    expect(find.text('阿公辛苦了，我們這週末回去看您！'), findsOneWidget);
  });
}
