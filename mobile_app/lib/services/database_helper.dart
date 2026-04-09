// lib/services/database_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:async';
import 'package:flutter_application_1/utils/app_logger.dart';

/// 本地資料庫管理服務
/// 
/// 負責管理所有子女端本地數據存儲
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'family_care.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // ========================================
    // 1. 關心劇本表
    // ========================================
    await db.execute('''
      CREATE TABLE care_scripts (
        id TEXT PRIMARY KEY,
        elder_id INTEGER NOT NULL,
        time TEXT NOT NULL,
        message TEXT NOT NULL,
        type TEXT NOT NULL,
        enable_voice INTEGER DEFAULT 1,
        custom_audio_path TEXT,
        repeat_days TEXT NOT NULL,
        enabled INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        last_executed_at TEXT,
        FOREIGN KEY (elder_id) REFERENCES elders (id)
      )
    ''');

    // ========================================
    // 2. 每日時間表
    // ========================================
    await db.execute('''
      CREATE TABLE schedule_items (
        id TEXT PRIMARY KEY,
        elder_id INTEGER NOT NULL,
        time TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        type TEXT NOT NULL,
        reminder_message TEXT NOT NULL,
        play_sound INTEGER DEFAULT 1,
        music_url TEXT,
        enabled INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY (elder_id) REFERENCES elders (id)
      )
    ''');

    // ========================================
    // 3. 用藥提醒
    // ========================================
    await db.execute('''
      CREATE TABLE medications (
        id TEXT PRIMARY KEY,
        elder_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        dosage TEXT NOT NULL,
        frequency TEXT NOT NULL,
        times TEXT NOT NULL,
        enabled INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY (elder_id) REFERENCES elders (id)
      )
    ''');

    // ========================================
    // 4. 用藥記錄
    // ========================================
    await db.execute('''
      CREATE TABLE medication_logs (
        id TEXT PRIMARY KEY,
        medication_id TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        confirmed INTEGER DEFAULT 0,
        confirmed_at TEXT,
        FOREIGN KEY (medication_id) REFERENCES medications (id)
      )
    ''');

    // ========================================
    // 5. 回診提醒
    // ========================================
    await db.execute('''
      CREATE TABLE appointments (
        id TEXT PRIMARY KEY,
        elder_id INTEGER NOT NULL,
        hospital TEXT NOT NULL,
        department TEXT NOT NULL,
        date TEXT NOT NULL,
        time TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (elder_id) REFERENCES elders (id)
      )
    ''');

    // ========================================
    // 6. 家庭回憶
    // ========================================
    await db.execute('''
      CREATE TABLE memories (
        id TEXT PRIMARY KEY,
        elder_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        category TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        image_path TEXT,
        audio_path TEXT,
        tags TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (elder_id) REFERENCES elders (id)
      )
    ''');

    // ========================================
    // 7. AI 人格設定
    // ========================================
    await db.execute('''
      CREATE TABLE ai_personas (
        id TEXT PRIMARY KEY,
        elder_id INTEGER NOT NULL,
        base_persona TEXT NOT NULL,
        warmth REAL DEFAULT 0.8,
        verbosity REAL DEFAULT 0.6,
        favorite_topics TEXT,
        forbidden_topics TEXT,
        custom_responses TEXT,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (elder_id) REFERENCES elders (id)
      )
    ''');

    // ========================================
    // 8. 長輩心情記錄
    // ========================================
    await db.execute('''
      CREATE TABLE mood_records (
        id TEXT PRIMARY KEY,
        elder_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        score REAL NOT NULL,
        label TEXT NOT NULL,
        emoji TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (elder_id) REFERENCES elders (id)
      )
    ''');

    // ========================================
    // 9. 對話洞察
    // ========================================
    await db.execute('''
      CREATE TABLE conversation_insights (
        id TEXT PRIMARY KEY,
        elder_id INTEGER NOT NULL,
        emoji TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (elder_id) REFERENCES elders (id)
      )
    ''');

    // ========================================
    // 10. 執行歷史記錄
    // ========================================
    await db.execute('''
      CREATE TABLE execution_history (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        related_id TEXT NOT NULL,
        elder_id INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        status TEXT NOT NULL,
        details TEXT,
        FOREIGN KEY (elder_id) REFERENCES elders (id)
      )
    ''');

    appLogger.d('✅ [DatabaseHelper] Database created successfully');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 未來版本升級邏輯
    appLogger.d('📦 [DatabaseHelper] Upgrading database from $oldVersion to $newVersion');
  }

  // ========================================
  // 通用 CRUD 操作
  // ========================================

  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    final db = await database;
    return await db.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );
  }

  Future<int> update(
    String table,
    Map<String, dynamic> data, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final db = await database;
    return await db.update(
      table,
      data,
      where: where,
      whereArgs: whereArgs,
    );
  }

  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final db = await database;
    return await db.delete(
      table,
      where: where,
      whereArgs: whereArgs,
    );
  }

  // ========================================
  // 專用查詢方法
  // ========================================

  /// 獲取特定長輩的所有關心劇本
  Future<List<Map<String, dynamic>>> getCareScripts(int elderId) async {
    return await query(
      'care_scripts',
      where: 'elder_id = ? AND enabled = 1',
      whereArgs: [elderId],
      orderBy: 'time ASC',
    );
  }

  /// 獲取特定長輩的每日時間表
  Future<List<Map<String, dynamic>>> getScheduleItems(int elderId) async {
    return await query(
      'schedule_items',
      where: 'elder_id = ? AND enabled = 1',
      whereArgs: [elderId],
      orderBy: 'time ASC',
    );
  }

  /// 獲取特定長輩的用藥提醒
  Future<List<Map<String, dynamic>>> getMedications(int elderId) async {
    return await query(
      'medications',
      where: 'elder_id = ? AND enabled = 1',
      whereArgs: [elderId],
      orderBy: 'created_at DESC',
    );
  }

  /// 獲取今日用藥記錄
  Future<List<Map<String, dynamic>>> getTodayMedicationLogs(int elderId) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final db = await database;
    
    return await db.rawQuery('''
      SELECT ml.*, m.name, m.dosage
      FROM medication_logs ml
      JOIN medications m ON ml.medication_id = m.id
      WHERE m.elder_id = ? AND ml.timestamp LIKE ?
      ORDER BY ml.timestamp DESC
    ''', [elderId, '$today%']);
  }

  /// 獲取特定長輩的回憶
  Future<List<Map<String, dynamic>>> getMemories(
    int elderId, {
    String? category,
    int? limit,
  }) async {
    String? where = 'elder_id = ?';
    List<dynamic> whereArgs = [elderId];

    if (category != null && category != 'all') {
      where += ' AND category = ?';
      whereArgs.add(category);
    }

    return await query(
      'memories',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  /// 獲取特定長輩的 AI 人格設定
  Future<Map<String, dynamic>?> getAiPersona(int elderId) async {
    final results = await query(
      'ai_personas',
      where: 'elder_id = ?',
      whereArgs: [elderId],
      limit: 1,
    );

    return results.isNotEmpty ? results.first : null;
  }

  /// 獲取最近 N 天的心情記錄
  Future<List<Map<String, dynamic>>> getRecentMoodRecords(
    int elderId,
    int days,
  ) async {
    final startDate = DateTime.now().subtract(Duration(days: days));
    final startDateStr = startDate.toIso8601String().split('T')[0];

    return await query(
      'mood_records',
      where: 'elder_id = ? AND date >= ?',
      whereArgs: [elderId, startDateStr],
      orderBy: 'date ASC',
    );
  }

  /// 記錄執行歷史
  Future<void> logExecution({
    required String type,
    required String relatedId,
    required int elderId,
    required String status,
    String? details,
  }) async {
    await insert('execution_history', {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'type': type,
      'related_id': relatedId,
      'elder_id': elderId,
      'timestamp': DateTime.now().toIso8601String(),
      'status': status,
      'details': details,
    });
  }

  // ========================================
  // 清理與維護
  // ========================================

  /// 清理過期的執行歷史（保留 30 天）
  Future<void> cleanupOldHistory() async {
    final cutoffDate = DateTime.now().subtract(Duration(days: 30));
    final cutoffStr = cutoffDate.toIso8601String();

    await delete(
      'execution_history',
      where: 'timestamp < ?',
      whereArgs: [cutoffStr],
    );

    appLogger.d('🧹 [DatabaseHelper] Cleaned up old execution history');
  }

  /// 關閉資料庫連接
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
