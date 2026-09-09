import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/memoir_story.dart';

/// 長輩人生故事膠囊服務層 (MemoirService)
///
/// 支援本機 SharedPreferences 快取、精選示範資料注入、子女留言互動、
/// 以及「子女委託小豬提問」的佇列調度。
class MemoirService extends ChangeNotifier {
  static final MemoirService instance = MemoirService._internal();

  MemoirService._internal();

  // 快取鍵前綴
  static const String _memoirKeyPrefix = 'uban_memoirs_';
  static const String _delegationKeyPrefix = 'uban_memoir_delegations_';

  /// 預設故事膠囊（無初始假資料，由長輩口述與小豬對話真實生成）
  static List<MemoirStory> getPresetMemoirs(String elderId) {
    return const [];
  }

  /// 內建推薦話題庫（供子女端挑選委託小豬發問）
  List<Map<String, String>> getRecommendedPrompts() {
    return const [
      {
        'category': '感官與美食記憶',
        'question': '阿公，您小時候最喜歡吃的一道菜或點心是什麼？現在還吃得到嗎？',
        'tag': '美食記憶',
      },
      {
        'category': '感官與美食記憶',
        'question': '小時候放學回家，阿公都跟隔壁同伴在田裡或廟口玩什麼遊戲呀？',
        'tag': '經典回憶',
      },
      {
        'category': '青春與奮鬥打拼',
        'question': '阿公人生拿到的第一份薪水是多少錢？那時候買了什麼犒賞自己或孝敬父母？',
        'tag': '奮鬥歲月',
      },
      {
        'category': '青春與奮鬥打拼',
        'question': '阿公年輕當兵或出社會時，有沒有哪一位老朋友讓您印象最深刻？',
        'tag': '奮鬥歲月',
      },
      {
        'category': '浪漫與家庭牽絆',
        'question': '阿公，您跟阿嬤第一次約會是在哪裡？那時候心情會不會很緊張？',
        'tag': '經典回憶',
      },
      {
        'category': '浪漫與家庭牽絆',
        'question': '第一個孩子出生抱在懷裡的那一刻，阿公心裡在想什麼呢？',
        'tag': '溫馨寄語',
      },
      {
        'category': '人生錦囊與傳承',
        'question': '阿公走過這麼多年的人生風雨，最想傳授給年輕一代的一句智慧話是什麼？',
        'tag': '溫馨寄語',
      },
    ];
  }

  /// 取得長輩的故事膠囊列表
  Future<List<MemoirStory>> getMemoirs(String elderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_memoirKeyPrefix$elderId';
      final jsonStr = prefs.getString(key);

      if (jsonStr == null || jsonStr.trim().isEmpty) {
        return [];
      }

      final List decoded = jsonDecode(jsonStr);
      final rawStories = decoded
          .map((item) => MemoirStory.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      // 過濾移除過去預設的示範假資料 (memoir_001, memoir_002, memoir_003)
      final stories = rawStories
          .where((item) => !item.id.startsWith('memoir_00'))
          .toList();

      // 若有過濾掉假資料，同步更新本機儲存
      if (stories.length != rawStories.length) {
        await _saveMemoirsToLocal(elderId, stories);
      }

      return stories;
    } catch (e) {
      debugPrint('[MemoirService] Error reading memoirs: $e');
      return [];
    }
  }

  /// 儲存或更新一篇故事膠囊
  Future<void> saveMemoir(MemoirStory story) async {
    final elderId = story.elderId;
    final currentList = await getMemoirs(elderId);
    final index = currentList.indexWhere((item) => item.id == story.id);

    if (index >= 0) {
      currentList[index] = story;
    } else {
      currentList.insert(0, story);
    }

    await _saveMemoirsToLocal(elderId, currentList);
    notifyListeners();
  }

  /// 刪除一篇故事膠囊
  Future<void> deleteMemoir(String elderId, String storyId) async {
    final currentList = await getMemoirs(elderId);
    currentList.removeWhere((item) => item.id == storyId);
    await _saveMemoirsToLocal(elderId, currentList);
    notifyListeners();
  }

  /// 切換單篇故事的珍藏狀態
  Future<void> toggleFavorite(String elderId, String storyId) async {
    final currentList = await getMemoirs(elderId);
    final index = currentList.indexWhere((item) => item.id == storyId);
    if (index >= 0) {
      final old = currentList[index];
      currentList[index] = old.copyWith(isFavorite: !old.isFavorite);
      await _saveMemoirsToLocal(elderId, currentList);
      notifyListeners();
    }
  }

  /// 家屬新增一則悄悄話筆記
  Future<void> addFamilyNote(String elderId, String storyId, MemoirFamilyNote note) async {
    final currentList = await getMemoirs(elderId);
    final index = currentList.indexWhere((item) => item.id == storyId);
    if (index >= 0) {
      final old = currentList[index];
      final updatedNotes = List<MemoirFamilyNote>.from(old.familyNotes)..add(note);
      currentList[index] = old.copyWith(familyNotes: updatedNotes);
      await _saveMemoirsToLocal(elderId, currentList);
      notifyListeners();
    }
  }

  /// 子女委託小豬提問
  Future<void> delegatePrompt(MemoirPromptDelegation delegation) async {
    final elderId = delegation.elderId;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_delegationKeyPrefix$elderId';
    final existingJson = prefs.getString(key);

    List<MemoirPromptDelegation> list = [];
    if (existingJson != null && existingJson.isNotEmpty) {
      try {
        final List decoded = jsonDecode(existingJson);
        list = decoded
            .map((item) => MemoirPromptDelegation.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      } catch (_) {}
    }

    list.insert(0, delegation);
    await prefs.setString(key, jsonEncode(list.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  /// 取得所有尚未回答的委託提問
  Future<List<MemoirPromptDelegation>> getPendingPrompts(String elderId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_delegationKeyPrefix$elderId';
    final existingJson = prefs.getString(key);

    if (existingJson == null || existingJson.isEmpty) return [];

    try {
      final List decoded = jsonDecode(existingJson);
      final list = decoded
          .map((item) => MemoirPromptDelegation.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => !item.isAnswered)
          .toList();
      return list;
    } catch (_) {
      return [];
    }
  }

  /// 取得下一道要讓小豬發問的話題（若有子女委託優先，否則隨機從推薦話題挑選）
  Future<String> getNextPromptQuestion(String elderId) async {
    final pending = await getPendingPrompts(elderId);
    if (pending.isNotEmpty) {
      return pending.first.question;
    }
    final recommended = getRecommendedPrompts();
    final dayIndex = DateTime.now().day % recommended.length;
    return recommended[dayIndex]['question'] ?? '阿公，今天跟小豬說說你小時候的故事好不好？';
  }

  /// 標記委託話題為已回答
  Future<void> markPromptAnswered(String elderId, String promptQuestion) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_delegationKeyPrefix$elderId';
    final existingJson = prefs.getString(key);
    if (existingJson == null || existingJson.isEmpty) return;

    try {
      final List decoded = jsonDecode(existingJson);
      final list = decoded
          .map((item) => MemoirPromptDelegation.fromJson(Map<String, dynamic>.from(item)))
          .map((item) {
        if (item.question == promptQuestion) {
          return MemoirPromptDelegation(
            id: item.id,
            elderId: item.elderId,
            question: item.question,
            category: item.category,
            requestedBy: item.requestedBy,
            createdAt: item.createdAt,
            isAnswered: true,
          );
        }
        return item;
      }).toList();

      await prefs.setString(key, jsonEncode(list.map((e) => e.toJson()).toList()));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveMemoirsToLocal(String elderId, List<MemoirStory> stories) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_memoirKeyPrefix$elderId';
    final encoded = jsonEncode(stories.map((s) => s.toJson()).toList());
    await prefs.setString(key, encoded);
  }
}
