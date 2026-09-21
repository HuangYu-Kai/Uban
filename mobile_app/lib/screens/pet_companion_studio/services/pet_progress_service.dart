import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';

/// 單一成長階段門檻，對應後端 `pet_stage_threshold` 表一列
/// （`GET /api/pet/thresholds` 的 `data.stages[i]`）。
class PetStageBounds {
  final int stageNo;
  final String title;
  final int minWeightGrams;

  /// 該階段的體重上限（公克）。**null 代表無上限**（目前只有第 5 階，也就
  /// 是最高階，是 null）——不要拿 null 去算進度條分母，呼叫端要先判斷是否
  /// 為 null。
  final int? maxWeightGrams;
  final String imageAssetPath;

  const PetStageBounds({
    required this.stageNo,
    required this.title,
    required this.minWeightGrams,
    required this.maxWeightGrams,
    required this.imageAssetPath,
  });

  factory PetStageBounds.fromJson(Map<String, dynamic> json) {
    return PetStageBounds(
      stageNo: (json['stage_no'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      minWeightGrams: (json['min_weight_grams'] as num?)?.toInt() ?? 0,
      maxWeightGrams: (json['max_weight_grams'] as num?)?.toInt(),
      imageAssetPath: json['image_asset_path']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toCacheJson() => {
        'stage_no': stageNo,
        'title': title,
        'min_weight_grams': minWeightGrams,
        'max_weight_grams': maxWeightGrams,
        'image_asset_path': imageAssetPath,
      };
}

/// 目前賽季資訊（`GET /api/pet/season`）。
class PetSeasonInfo {
  final int seasonNo;
  final DateTime startDate;
  final DateTime endDate;
  final String status;
  final int daysRemaining;

  const PetSeasonInfo({
    required this.seasonNo,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.daysRemaining,
  });

  factory PetSeasonInfo.fromJson(Map<String, dynamic> json) {
    return PetSeasonInfo(
      seasonNo: (json['season_no'] as num?)?.toInt() ?? 0,
      startDate: DateTime.tryParse(json['start_date']?.toString() ?? '') ?? DateTime.now(),
      endDate: DateTime.tryParse(json['end_date']?.toString() ?? '') ?? DateTime.now(),
      status: json['status']?.toString() ?? 'active',
      daysRemaining: (json['days_remaining'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 今日食物解鎖來源原始資料（`GET /api/pet/food-unlocks/{elder_id}`）。
class PetFoodUnlockSource {
  /// 後端今天的步數。**null 代表「後端答不出來」**（`elder_daily_step` 查
  /// 詢失敗，或該表在目前環境不存在）——與「答案是 0」語意不同，呼叫端取
  /// 到 null 時應該退回使用裝置端既有的步數來源，不要當成 0 步處理。
  final int? todaySteps;
  final int medicationCheckinsToday;

  /// 目前恆為 0——activity_log 的 exercise 事件全專案只有讀取端、沒有任何
  /// 寫入路徑（見 uban-api/routers/pet.py 的端點說明）。保留這個欄位只是
  /// 讓資料結構對齊後端回應，暫時不要拿它做解鎖判斷（見
  /// PetFoodItem.isUnlockedFor 的說明）。
  final int exerciseEventsToday;

  const PetFoodUnlockSource({
    required this.todaySteps,
    required this.medicationCheckinsToday,
    required this.exerciseEventsToday,
  });

  factory PetFoodUnlockSource.fromJson(Map<String, dynamic> json) {
    return PetFoodUnlockSource(
      todaySteps: (json['today_steps'] as num?)?.toInt(),
      medicationCheckinsToday: (json['medication_checkins_today'] as num?)?.toInt() ?? 0,
      exerciseEventsToday: (json['exercise_events_today'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 今日食物消耗量——「食物帳本」（`GET /api/pet/food-ledger/{elder_id}`）。
/// 讓賺取制食物（見 `PetFoodItem.isEarnedQuantity`，目前只有 carrot）的
/// 「已賺得份數」在裝置重新啟動後依然知道今天已經吃掉幾份，不會因為
/// App 重開就把已消耗的份數清零、變相又能超額投餵。
class PetFoodLedger {
  /// key 是 food_id（例如 'carrot'），value 是今天已消耗的份數。
  final Map<String, int> consumed;

  const PetFoodLedger({required this.consumed});

  factory PetFoodLedger.fromJson(Map<String, dynamic> json) {
    final Map<String, int> parsed = {};
    final raw = json['consumed'];
    if (raw is Map) {
      raw.forEach((key, value) {
        final n = (value as num?)?.toInt();
        if (n != null) parsed[key.toString()] = n;
      });
    }
    return PetFoodLedger(consumed: parsed);
  }

  /// 指定食物今天已消耗的份數；查無紀錄視為 0（「今天還沒吃過」與「查詢
  /// 失敗」是不同語意——後者呼叫端應該整個 [PetFoodLedger] 當作 null 處理，
  /// 不要走到這裡）。
  int consumedOf(String foodId) => consumed[foodId] ?? 0;
}

/// 寵物「階段門檻」「賽季」「今日食物解鎖來源」「今日食物帳本」四組端點
/// 的前端存取層，對應後端 `uban-api/routers/pet.py` 的
/// `GET /api/pet/thresholds` / `GET /api/pet/season` /
/// `GET /api/pet/food-unlocks/{elder_id}` /
/// `GET/POST /api/pet/food-ledger`（第五十一輪新增，見 [PetFoodLedger]／
/// [loadFoodLedger]／[recordFoodConsumption] 的說明）。
///
/// 與 `pet_leaderboard_service.dart`（體重上傳／排行榜）是同一個路由檔的
/// 不同端點，刻意拆成獨立檔案而不是塞進同一個 service class——那邊已經有
/// `lastLeaderboardError` 這種與排行榜耦合的錯誤狀態，混在一起容易互相
/// 弄髒對方的錯誤欄位。
///
/// 錯誤處理策略（與本檔其餘服務一致：失敗只記 log，不拋例外，不影響既有
/// 的寵物養成功能）：
/// - 階段門檻：失敗時沿用 [fallbackStageBounds]（寫死的線性門檻，與後端
///   seed 值相同），寵物養成的核心體驗（成長階段判定）不能因為網路問題
///   整個壞掉或空白。
/// - 賽季／食物解鎖來源：沒有「正確的寫死預設值」可以頂替（賽季序號、
///   打卡次數都是會變的即時資料，編造一個數字反而會誤導使用者），失敗時
///   回傳 null，呼叫端應該隱藏該區塊或退回既有行為，而不是顯示假資料。
class PetProgressService {
  static const Duration _timeout = Duration(seconds: 15);

  static const String _prefsStageBoundsKey = 'uban_pet_stage_bounds_cache_json';

  /// 寫死的線性成長門檻（與後端 `pet_stage_threshold` seed 值相同：
  /// 0/20000/40000/60000/80000，每階等距 20 公斤）。取代舊版寫在
  /// `PetGrowthStage` enum 裡的非線性門檻（15000/35000/65000/90000）——
  /// 本輪需求明確要求換成新曲線，fallback 也必須跟著換，否則離線與連線時
  /// 長輩會看到不同的成長階段判定，造成困惑。階段名稱與圖檔路徑照抄舊版
  /// enum（後端也是照抄同一份），顯示不會變。
  static const List<PetStageBounds> fallbackStageBounds = [
    PetStageBounds(
      stageNo: 1,
      title: '一口小粉糰',
      minWeightGrams: 0,
      maxWeightGrams: 20000,
      imageAssetPath: 'assets/images/pet_stages/pig_stage_1.png',
    ),
    PetStageBounds(
      stageNo: 2,
      title: '元氣小福豬',
      minWeightGrams: 20000,
      maxWeightGrams: 40000,
      imageAssetPath: 'assets/images/pet_stages/pig_stage_2.png',
    ),
    PetStageBounds(
      stageNo: 3,
      title: '白胖肉肉豬',
      minWeightGrams: 40000,
      maxWeightGrams: 60000,
      imageAssetPath: 'assets/images/pet_stages/pig_stage_3.png',
    ),
    PetStageBounds(
      stageNo: 4,
      title: '富貴大元寶',
      minWeightGrams: 60000,
      maxWeightGrams: 80000,
      imageAssetPath: 'assets/images/pet_stages/pig_stage_4.png',
    ),
    PetStageBounds(
      stageNo: 5,
      title: '招財金光大富豬',
      minWeightGrams: 80000,
      maxWeightGrams: null,
      imageAssetPath: 'assets/images/pet_stages/pig_stage_5.png',
    ),
  ];

  static List<PetStageBounds>? _cachedStageBounds;
  static PetSeasonInfo? _cachedSeason;

  /// 目前生效中的階段門檻——成功從後端取得（或曾經在本機快取過）就用那份，
  /// 否則用 [fallbackStageBounds]。同步取值，UI 隨時可讀，不必等待
  /// Future，畫面第一幀也一定有值可用。
  static List<PetStageBounds> get stageBounds => _cachedStageBounds ?? fallbackStageBounds;

  /// 目前賽季——尚未成功載入過時是 null，呼叫端應隱藏賽季區塊，不要顯示
  /// 編造的數字。
  static PetSeasonInfo? get cachedSeason => _cachedSeason;

  static Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// 進入寵物介面時呼叫一次：先套用上次成功快取的門檻（若有），畫面立刻
  /// 有值可用，再嘗試連線更新成最新值。兩步刻意分開——本機快取套用是同步
  /// 讀檔、幾乎必定比等一次網路請求快，不必讓畫面空等。
  static Future<void> ensureStageBoundsLoaded() async {
    if (_cachedStageBounds == null) {
      await _loadStageBoundsFromPrefs();
    }
    await refreshStageBounds();
  }

  static Future<void> _loadStageBoundsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsStageBoundsKey);
      if (raw == null) return;
      final List<dynamic> list = jsonDecode(raw);
      final parsed =
          list.whereType<Map<String, dynamic>>().map(PetStageBounds.fromJson).toList();
      if (_isValidStageBoundsList(parsed)) {
        _cachedStageBounds = parsed;
      }
    } catch (e) {
      debugPrint('⚠️ [PetProgressService] 讀取本機門檻快取失敗: $e');
    }
  }

  /// 5 個階段、stage_no 必須依序 1~5——資料形狀跟 [fallbackStageBounds] 對
  /// 不上就整份丟棄，寧可退回寫死預設值，也不要讓形狀錯誤的資料害
  /// `PetGrowthStage.values` 的索引對應出錯（見 pet_growth_state.dart）。
  static bool _isValidStageBoundsList(List<PetStageBounds> list) {
    if (list.length != fallbackStageBounds.length) return false;
    for (int i = 0; i < list.length; i++) {
      if (list[i].stageNo != i + 1) return false;
    }
    return true;
  }

  /// 連線取得最新門檻。成功時更新記憶體快取並寫回 SharedPreferences；失敗
  /// （逾時、連不上、格式錯誤）只記 log，沿用目前的 [stageBounds]（上次
  /// 快取或寫死預設值），不拋例外、不影響呼叫端。
  static Future<bool> refreshStageBounds() async {
    try {
      final response = await http
          .get(Uri.parse('${ApiService.baseUrl}/pet/thresholds'))
          .timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['status'] == 'success') {
        final stagesJson = (data['data'] as Map<String, dynamic>?)?['stages'] as List?;
        if (stagesJson != null) {
          final parsed = stagesJson
              .whereType<Map<String, dynamic>>()
              .map(PetStageBounds.fromJson)
              .toList()
            ..sort((a, b) => a.stageNo.compareTo(b.stageNo));
          if (_isValidStageBoundsList(parsed)) {
            _cachedStageBounds = parsed;
            unawaited(_persistStageBoundsToPrefs(parsed));
            return true;
          }
          debugPrint('⚠️ [PetProgressService] 門檻資料形狀不符預期，沿用舊值: $stagesJson');
        }
      }
    } catch (e) {
      debugPrint('⚠️ [PetProgressService] refreshStageBounds error: $e');
    }
    return false;
  }

  static Future<void> _persistStageBoundsToPrefs(List<PetStageBounds> bounds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsStageBoundsKey,
        jsonEncode(bounds.map((b) => b.toCacheJson()).toList()),
      );
    } catch (e) {
      debugPrint('⚠️ [PetProgressService] 寫入本機門檻快取失敗: $e');
    }
  }

  /// 取得目前賽季。成功回傳 [PetSeasonInfo] 並更新 [cachedSeason]；失敗
  /// （逾時、連不上、格式錯誤）回傳 null——刻意不編造賽季序號或剩餘天數
  /// 頂替，呼叫端應該隱藏賽季區塊。
  static Future<PetSeasonInfo?> loadSeason() async {
    try {
      final response =
          await http.get(Uri.parse('${ApiService.baseUrl}/pet/season')).timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['status'] == 'success') {
        final seasonJson = data['data'] as Map<String, dynamic>?;
        if (seasonJson != null) {
          final season = PetSeasonInfo.fromJson(seasonJson);
          _cachedSeason = season;
          return season;
        }
      }
    } catch (e) {
      debugPrint('⚠️ [PetProgressService] loadSeason error: $e');
    }
    return null;
  }

  /// 取得「今日食物解鎖來源」原始資料（步數／服藥打卡次數／運動事件數）。
  /// elder_id 查無此人（後端回 404）或連線失敗一律回傳 null——呼叫端應該
  /// 退回既有行為（只用裝置端步數判斷解鎖，不含打卡加成），不影響既有的
  /// 寵物養成功能。
  static Future<PetFoodUnlockSource?> loadFoodUnlocks(String elderId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiService.baseUrl}/pet/food-unlocks/$elderId'))
          .timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['status'] == 'success') {
        final unlockJson = data['data'] as Map<String, dynamic>?;
        if (unlockJson != null) {
          return PetFoodUnlockSource.fromJson(unlockJson);
        }
      }
    } catch (e) {
      debugPrint('⚠️ [PetProgressService] loadFoodUnlocks error: $e');
    }
    return null;
  }

  /// 取得「今日食物消耗量」（`GET /api/pet/food-ledger/{elder_id}
  /// ?ledger_date=YYYY-MM-DD`）。
  ///
  /// ⚠️ [ledgerDate] 必須是**裝置本機日期**（`yyyy-MM-dd`），不可用伺服器
  /// 時區推算——長輩若剛好在跨日前後操作，裝置與伺服器時區不一致會誤判
  /// 成前一天或後一天，讓「今天已賺得」與「今天已消耗」對不上日期，算出
  /// 錯誤的可餵份數。呼叫端一律用 `DateTime.now()` 組出這個字串。
  ///
  /// 失敗（逾時、連不上、elder_id 404、格式錯誤）回傳 null——呼叫端不可
  /// 把 null 當成「今天消耗 0 份」處理，那等於允許超額投餵；正確做法是
  /// 把對應的賺取制食物暫時顯示成不可餵（見 [PetFoodLedger] 類別說明與
  /// `ElderProfileTab`／`PetStudioScreen` 的庫存計算邏輯）。
  static Future<PetFoodLedger?> loadFoodLedger(
    String elderId,
    String ledgerDate,
  ) async {
    try {
      final response = await http
          .get(Uri.parse(
              '${ApiService.baseUrl}/pet/food-ledger/$elderId?ledger_date=$ledgerDate'))
          .timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['status'] == 'success') {
        final ledgerJson = data['data'] as Map<String, dynamic>?;
        // ★ 後端在「查得到、今天是 0 份」與「這次查不到（例如 elder_food_ledger
        //   表還沒建好）」之間刻意分成 `consumed: {}` 與 `consumed: null` 兩種
        //   回應（見 uban-api/routers/pet.py 的 get_food_ledger 說明）。
        //   `PetFoodLedger.fromJson` 會把非 Map 的 consumed 一律讀成空 Map，
        //   等於把「查不到」講成「今天一份都還沒吃」——那會讓賺取制食物的
        //   可餵份數直接回到滿額，正是本輪要修掉的超額投餵。這裡在轉成
        //   model 之前先攔下來，回 null 走既有的「暫時不可餵」路徑。
        if (ledgerJson != null && ledgerJson['consumed'] != null) {
          return PetFoodLedger.fromJson(ledgerJson);
        }
      }
    } catch (e) {
      debugPrint('⚠️ [PetProgressService] loadFoodLedger error: $e');
    }
    return null;
  }

  /// 記一筆食物消耗（`POST /api/pet/food-ledger`，body
  /// `{elder_id, ledger_date, food_id}`）。成功回傳 true。
  ///
  /// [ledgerDate] 同樣必須是裝置本機日期，理由同 [loadFoodLedger]。
  ///
  /// 呼叫端（[PetFoodItem.isEarnedQuantity] 的賺取制食物餵食流程）在收到
  /// false 時不可先扣本機庫存後又假裝成功——本機計數與後端帳本一旦不同
  /// 步，重開 App 後又會出現「本機以為還有份數、後端其實已經扣完」或反過
  /// 來「明明吃過還能再吃」的落差，這正是本次要修的那個問題本身。
  static Future<bool> recordFoodConsumption({
    required String elderId,
    required String ledgerDate,
    required String foodId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/pet/food-ledger'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'elder_id': elderId,
              'ledger_date': ledgerDate,
              'food_id': foodId,
            }),
          )
          .timeout(_timeout);
      final data = _decode(response);
      return response.statusCode == 200 && data['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ [PetProgressService] recordFoodConsumption error: $e');
      return false;
    }
  }
}
