import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/models/memoir_story.dart';
import 'package:flutter_application_1/services/memoir_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MemoirService Tests', () {
    late MemoirService service;
    const testElderId = 'elder_test_888';

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = MemoirService.instance;
    });

    test('首次讀取時為空（零假資料）', () async {
      final memoirs = await service.getMemoirs(testElderId);
      expect(memoirs, isEmpty);
    });

    test('會自動過濾舊版假資料 (memoir_001~003)', () async {
      final mockStories = [
        MemoirStory(
          id: 'memoir_001',
          elderId: testElderId,
          title: '舊假資料',
          tag: '經典回憶',
          preview: '預覽',
          fullStory: '內文',
          promptQuestion: '問題',
          recordedDate: DateTime.now(),
        ),
        MemoirStory(
          id: 'memoir_real_123',
          elderId: testElderId,
          title: '真實長輩回憶',
          tag: '真實故事',
          preview: '真實預覽',
          fullStory: '真實內文',
          promptQuestion: '真實提問',
          recordedDate: DateTime.now(),
        ),
      ];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'uban_memoirs_$testElderId',
        jsonEncode(mockStories.map((s) => s.toJson()).toList()),
      );

      final memoirs = await service.getMemoirs(testElderId);
      expect(memoirs.length, 1);
      expect(memoirs.first.id, 'memoir_real_123');
      expect(memoirs.first.title, '真實長輩回憶');
    });

    test('可以新增自訂人生故事膠囊並持久化', () async {
      final newStory = MemoirStory(
        id: 'story_new_1',
        elderId: testElderId,
        title: '年輕時學開貨車的故事',
        tag: '奮鬥歲月',
        preview: '那年十八歲考到駕照，跟著師傅跑全台灣...',
        fullStory: '那年十八歲考到大貨車駕照，跟著師傅從基隆載貨到高雄港，一路上的公路風光與辛苦汗水，是我一生中最難忘的青春記憶。',
        promptQuestion: '阿公，你以前年輕時開過大貨車嗎？',
        recordedDate: DateTime.now(),
      );

      await service.saveMemoir(newStory);

      final list = await service.getMemoirs(testElderId);
      expect(list.length, 1);
      expect(list.first.id, 'story_new_1');
      expect(list.first.title, '年輕時學開貨車的故事');
    });

    test('家屬可以在故事膠囊中留下悄悄話筆記', () async {
      final story = MemoirStory(
        id: 'story_for_note',
        elderId: testElderId,
        title: '布莊回憶',
        tag: '經典回憶',
        preview: '預覽',
        fullStory: '故事內文',
        promptQuestion: '提問',
        recordedDate: DateTime.now(),
      );
      await service.saveMemoir(story);

      final note = MemoirFamilyNote(
        author: '小華',
        relation: '外孫',
        note: '阿公太帥了！好崇拜你！',
        createdAt: DateTime.now(),
      );

      await service.addFamilyNote(testElderId, story.id, note);

      final updatedList = await service.getMemoirs(testElderId);
      final updatedStory = updatedList.firstWhere((s) => s.id == story.id);
      expect(updatedStory.familyNotes.any((n) => n.note == '阿公太帥了！好崇拜你！'), isTrue);
    });

    test('家屬可以委託小豬向長輩提問並取得未回答委託', () async {
      final delegation = MemoirPromptDelegation(
        id: 'delegation_001',
        elderId: testElderId,
        question: '阿公，你以前是怎麼追到阿嬤的？',
        category: '浪漫愛情',
        requestedBy: '阿強',
        createdAt: DateTime.now(),
      );

      await service.delegatePrompt(delegation);

      final pending = await service.getPendingPrompts(testElderId);
      expect(pending.length, 1);
      expect(pending.first.question, '阿公，你以前是怎麼追到阿嬤的？');

      final nextQuestion = await service.getNextPromptQuestion(testElderId);
      expect(nextQuestion, '阿公，你以前是怎麼追到阿嬤的？');

      // 標記已回答
      await service.markPromptAnswered(testElderId, '阿公，你以前是怎麼追到阿嬤的？');
      final remainingPending = await service.getPendingPrompts(testElderId);
      expect(remainingPending, isEmpty);
    });

    test('切換珍藏狀態正常', () async {
      final story = MemoirStory(
        id: 'story_for_fav',
        elderId: testElderId,
        title: '珍藏測試故事',
        tag: '經典回憶',
        preview: '預覽',
        fullStory: '故事內文',
        promptQuestion: '提問',
        recordedDate: DateTime.now(),
        isFavorite: false,
      );
      await service.saveMemoir(story);

      await service.toggleFavorite(testElderId, story.id);

      final afterList = await service.getMemoirs(testElderId);
      expect(afterList.first.isFavorite, isTrue);
    });
  });
}
