import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class GameService {
  // ⚠️ 第五十一輪修復：原本讀 dotenv 的 `API_BASE_URL`，但專案 `.env` 從未
  // 定義這把鍵，因此永遠拿到寫死的預設值 `http://10.0.2.2:5000`——只在
  // Android 模擬器連本機 Flask（5000 埠）時碰巧可用，實機或改連現行的
  // FastAPI 後端（8000 埠）一律連不到，且不會有任何錯誤提示，容易誤導
  // 下一個人以為這個服務仍在正常運作。改用專案統一的 [ApiService.baseUrl]
  // （底層即 `ApiClient.baseUrl`，走 `--dart-define=SERVER_IP`，鐵律 #1
  // 「不可寫死 IP／伺服器網址」的既有機制），不再自行猜測位址。
  //
  // ⚠️ 目前找不到任何從 main.dart 可達的呼叫鏈會用到本類別——grep 全專案，
  // 呼叫端只有 `widgets/desktop_pet.dart`／`screens/admin_appearance_screen.dart`
  // ／`screens/leaderboard_screen.dart`／`screens/pet_profile_screen.dart`／
  // `screens/test_home_page.dart`，五者互相引用成一個封閉小群，但沒有任何
  // 檔案從 `main.dart` 或其他可達路徑建構 `TestHomePage`／`DesktopPet`，
  // 整群都是死碼。本輪不刪除檔案（不在本次任務範圍內），僅修正這個會
  // 誤導人的寫死位址，避免下一個人依賴它連不到後端卻查不出原因。
  static String get baseUrl => '${ApiService.baseUrl}/game';

  Future<Map<String, dynamic>> distributeAppearances({String? elderId}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/distribute_appearances'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'elder_id': elderId}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to distribute appearances: ${response.body}');
    }
  }

  Future<List<Map<String, dynamic>>> getLeaderboard(String elderId) async {
    final response = await http.get(Uri.parse('$baseUrl/leaderboard/$elderId'));
    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.map((e) => Map<String, dynamic>.from(e)).toList();
    } else {
      throw Exception('Failed to fetch leaderboard: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> checkResetStepTotal() async {
    final response = await http.post(Uri.parse('$baseUrl/check_reset'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to check reset: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getElderStatus(String elderId) async {
    final response = await http.get(Uri.parse('$baseUrl/elder_status/$elderId'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch elder status: ${response.body}');
    }
  }

  // --- New Admin & Elder Endpoints ---
  
  Future<Map<String, dynamic>> getElderCollection(String elderId) async {
    final response = await http.get(Uri.parse('$baseUrl/elder/collection/$elderId'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch elder collection: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> updateSteps(String elderId, int deltaSteps) async {
    final response = await http.post(
      Uri.parse('$baseUrl/elder/update_steps'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'elder_id': elderId,
        'delta_steps': deltaSteps,
      }),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to update steps: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getAdminElderInfo(String elderId) async {
    final response = await http.get(Uri.parse('$baseUrl/admin/elder_info/$elderId'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch admin elder info: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> assignAppearance(String elderId, int gawaId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/assign_appearance'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'elder_id': elderId, 'gawa_id': gawaId}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to assign appearance: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> setDistributionTime(String isoTimeStr) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/set_distribution_time'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'distribution_time': isoTimeStr}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to set distribution time: ${response.body}');
    }
  }

  /// 設置長輩步數（使用 save_steps 端點，累加方式）
  /// 注意：後端 /save_steps 是累加步數，不是設置總步數
  Future<Map<String, dynamic>> setSteps(String elderId, int deltaSteps) async {
    final response = await http.post(
      Uri.parse('$baseUrl/save_steps'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'elder_id': elderId,
        'steps': deltaSteps,
      }),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to set steps: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> saveSteps(String elderId, int steps) async {
    final response = await http.post(
      Uri.parse('$baseUrl/save_steps'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'elder_id': elderId, 'steps': steps}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to save steps: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> updatePetStatus(String elderId, int hunger, int intimacy) async {
    final response = await http.post(
      Uri.parse('$baseUrl/update_pet_status'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'elder_id': elderId,
        'hunger': hunger,
        'intimacy': intimacy,
      }),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to update pet status: ${response.body}');
    }
  }
}
