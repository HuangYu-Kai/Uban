import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/elder.dart';
import 'api_service.dart';

/// 🏠 長輩管理服務
/// 
/// 管理當前用戶配對的長輩列表，以及當前選中的長輩
class ElderManager {
  static const String _currentElderIdKey = 'current_elder_id';
  static const String _eldersCacheKey = 'paired_elders_cache';
  static const String _cacheTimestampKey = 'elders_cache_timestamp';
  static const String _currentUserIdKey = 'current_user_id';
  
  static final ElderManager _instance = ElderManager._internal();
  factory ElderManager() => _instance;
  ElderManager._internal();
  
  List<Elder> _pairedElders = [];
  Elder? _currentElder;
  int? _currentUserId;
  bool _isInitialized = false;
  
  /// 獲取當前選中的長輩
  Elder? get currentElder => _currentElder;
  
  /// 獲取所有配對的長輩列表
  List<Elder> get pairedElders => List.unmodifiable(_pairedElders);
  
  /// 獲取當前用戶 ID
  int? get currentUserId => _currentUserId;
  
  /// 是否已初始化
  bool get isInitialized => _isInitialized;
  
  /// 設定當前用戶 ID
  Future<void> setCurrentUserId(int userId) async {
    // 如果切換了用戶，清除舊的快取資料
    if (_currentUserId != null && _currentUserId != userId) {
      print('   🔄 User changed from $_currentUserId to $userId, clearing old data');
      _pairedElders = [];
      _currentElder = null;
      _isInitialized = false;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_eldersCacheKey);
      await prefs.remove(_cacheTimestampKey);
      await prefs.remove(_currentElderIdKey);
    }
    
    _currentUserId = userId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_currentUserIdKey, userId);
  }
  
  /// 從本地載入用戶 ID
  Future<void> loadCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUserId = prefs.getInt(_currentUserIdKey);
  }
  
  /// 初始化：載入配對的長輩列表
  Future<bool> initialize({int? userId}) async {
    try {
      print('🔄 ElderManager.initialize() called with userId: $userId');
      
      // 載入或設定用戶 ID
      if (userId != null) {
        await setCurrentUserId(userId);
      } else {
        await loadCurrentUserId();
      }
      
      print('   ElderManager._currentUserId: $_currentUserId');
      
      if (_currentUserId == null) {
        print('   ❌ No userId available, initialization failed');
        _isInitialized = false;
        return false;
      }
      
      // 嘗試從快取載入
      await _loadFromCache();
      print('   Loaded from cache: ${_pairedElders.length} elders');
      
      // 從 API 更新
      print('   Fetching from API...');
      final eldersData = await ApiService.getPairedElders(_currentUserId!);
      print('   API returned: ${eldersData.length} elders');
      
      if (eldersData.isNotEmpty) {
        _pairedElders = eldersData.map((json) => Elder.fromJson(json)).toList();
        await _saveToCache();
        
        // 載入上次選中的長輩，或選擇第一個
        await _loadCurrentElder();
        
        _isInitialized = true;
        print('   ✅ Initialization successful');
        print('   Current elder: ${_currentElder?.displayName}');
        return true;
      }
      
      // 如果 API 沒有資料，但快取有，就使用快取
      if (_pairedElders.isNotEmpty) {
        await _loadCurrentElder();
        _isInitialized = true;
        print('   ✅ Initialization successful (from cache)');
        print('   Current elder: ${_currentElder?.displayName}');
        return true;
      }
      
      print('   ⚠️  No paired elders found');
      _isInitialized = true;
      return false;
    } catch (e) {
      print('   ❌ Error during initialization: $e');
      // 網路錯誤時使用快取
      if (_pairedElders.isNotEmpty) {
        await _loadCurrentElder();
        _isInitialized = true;
        return true;
      }
      _isInitialized = false;
      return false;
    }
  }
  
  /// 切換當前選中的長輩
  Future<void> setCurrentElder(Elder elder) async {
    if (!_pairedElders.any((e) => e.id == elder.id)) {
      throw Exception('這個長輩不在配對列表中');
    }
    
    _currentElder = elder;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_currentElderIdKey, elder.id);
  }
  
  /// 重新整理配對列表
  Future<bool> refresh() async {
    if (_currentUserId == null) {
      return false;
    }
    
    try {
      final eldersData = await ApiService.getPairedElders(_currentUserId!);
      
      if (eldersData.isNotEmpty) {
        _pairedElders = eldersData.map((json) => Elder.fromJson(json)).toList();
        await _saveToCache();
        
        // 檢查當前選中的長輩是否還在列表中
        if (_currentElder != null) {
          final stillExists = _pairedElders.any((e) => e.id == _currentElder!.id);
          if (!stillExists) {
            // 當前長輩已解除配對，選擇第一個
            await _loadCurrentElder();
          } else {
            // 更新當前長輩的資料
            _currentElder = _pairedElders.firstWhere((e) => e.id == _currentElder!.id);
          }
        }
        
        return true;
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }
  
  /// 檢查快取是否過期（超過 30 分鐘）
  Future<bool> isCacheExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_cacheTimestampKey);
    
    if (timestamp == null) return true;
    
    final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final diff = DateTime.now().difference(cacheTime);
    
    return diff.inMinutes > 30;
  }
  
  /// 載入上次選中的長輩
  Future<void> _loadCurrentElder() async {
    if (_pairedElders.isEmpty) {
      _currentElder = null;
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final savedElderId = prefs.getInt(_currentElderIdKey);
    
    print('   📂 _loadCurrentElder: savedElderId = $savedElderId');
    
    if (savedElderId != null) {
      // 嘗試找到保存的長輩
      try {
        _currentElder = _pairedElders.firstWhere((e) => e.id == savedElderId);
        print('   ✅ Found saved elder: ${_currentElder?.displayName}');
      } catch (e) {
        // 找不到保存的長輩（可能是切換帳號或長輩已解除配對），選擇第一個
        print('   ⚠️  Saved elder not found, selecting first elder');
        _currentElder = _pairedElders.first;
        await prefs.setInt(_currentElderIdKey, _currentElder!.id);
      }
    } else {
      // 沒有保存記錄，選擇第一個
      print('   📝 No saved elder, selecting first elder');
      _currentElder = _pairedElders.first;
      await prefs.setInt(_currentElderIdKey, _currentElder!.id);
    }
    
    print('   ✅ _loadCurrentElder complete: ${_currentElder?.displayName}');
  }
  
  /// 從快取載入
  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_eldersCacheKey);
      
      if (cacheJson != null) {
        final List<dynamic> cachedData = jsonDecode(cacheJson);
        _pairedElders = cachedData.map((json) => Elder.fromJson(json)).toList();
      }
    } catch (e) {
      // 快取損壞，忽略
    }
  }
  
  /// 儲存到快取
  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = jsonEncode(_pairedElders.map((e) => e.toJson()).toList());
      
      await prefs.setString(_eldersCacheKey, cacheJson);
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      // 儲存失敗，忽略
    }
  }
  
  /// 清除所有資料
  Future<void> clear() async {
    _pairedElders = [];
    _currentElder = null;
    _currentUserId = null;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentElderIdKey);
    await prefs.remove(_eldersCacheKey);
    await prefs.remove(_cacheTimestampKey);
    await prefs.remove(_currentUserIdKey);
  }
}
