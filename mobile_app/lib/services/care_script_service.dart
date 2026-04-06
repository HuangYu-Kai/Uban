// lib/services/care_script_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/care_script.dart';
import 'database_helper.dart';
import 'signaling.dart';

/// 關心劇本管理服務
/// 
/// 負責管理子女設定的主動關心劇本
class CareScriptService {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final Signaling _signaling = Signaling();

  // ========================================
  // CRUD 操作
  // ========================================

  /// 儲存劇本
  Future<void> saveScript(CareScript script) async {
    await _db.insert('care_scripts', script.toMap());
    debugPrint('✅ [CareScriptService] Saved script: ${script.id}');
  }

  /// 更新劇本
  Future<void> updateScript(CareScript script) async {
    await _db.update(
      'care_scripts',
      script.toMap(),
      where: 'id = ?',
      whereArgs: [script.id],
    );
    debugPrint('✅ [CareScriptService] Updated script: ${script.id}');
  }

  /// 刪除劇本
  Future<void> deleteScript(String scriptId) async {
    await _db.delete(
      'care_scripts',
      where: 'id = ?',
      whereArgs: [scriptId],
    );
    debugPrint('✅ [CareScriptService] Deleted script: $scriptId');
  }

  /// 獲取特定長輩的所有劇本
  Future<List<CareScript>> getScripts(int elderId) async {
    final results = await _db.getCareScripts(elderId);
    return results.map((m) => CareScript.fromMap(m)).toList();
  }

  /// 切換劇本啟用狀態
  Future<void> toggleScript(String scriptId, bool enabled) async {
    await _db.update(
      'care_scripts',
      {'enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [scriptId],
    );
    debugPrint('✅ [CareScriptService] Toggled script $scriptId: $enabled');
  }

  // ========================================
  // 劇本執行
  // ========================================

  /// 立即執行劇本
  Future<void> executeScriptNow(CareScript script) async {
    await _signaling.sendHeartbeat(
      script.elderId,
      script.message,
      audioPath: script.customAudioPath,
      playSound: script.enableVoice,
    );

    // 記錄執行
    await _db.update(
      'care_scripts',
      {'last_executed_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [script.id],
    );

    await _db.logExecution(
      type: 'care_script',
      relatedId: script.id,
      elderId: script.elderId,
      status: 'success',
      details: 'Manual execution',
    );

    debugPrint('✅ [CareScriptService] Executed script: ${script.id}');
  }

  /// 檢查並執行到期的劇本
  /// 
  /// 此方法應該由後台任務定期調用
  Future<void> checkAndExecuteScheduledScripts() async {
    final now = DateTime.now();
    final currentTime = TimeOfDay.fromDateTime(now);
    final currentDay = ['週一', '週二', '週三', '週四', '週五', '週六', '週日'][now.weekday - 1];

    // 獲取所有啟用的劇本
    final results = await _db.query(
      'care_scripts',
      where: 'enabled = 1',
    );

    for (final scriptMap in results) {
      final script = CareScript.fromMap(scriptMap);

      // 檢查是否在重複日期內
      if (!script.repeatDays.contains(currentDay)) continue;

      // 檢查時間是否匹配（容差 1 分鐘）
      final scriptMinutes = script.time.hour * 60 + script.time.minute;
      final currentMinutes = currentTime.hour * 60 + currentTime.minute;

      if ((currentMinutes - scriptMinutes).abs() <= 1) {
        // 檢查是否今天已執行過
        final lastExecuted = script.lastExecutedAt;
        if (lastExecuted != null) {
          final lastDate = DateTime.parse(lastExecuted);
          if (lastDate.year == now.year &&
              lastDate.month == now.month &&
              lastDate.day == now.day) {
            continue; // 今天已執行過
          }
        }

        // 執行劇本
        await executeScriptNow(script);
      }
    }
  }

  // ========================================
  // 預設劇本範本
  // ========================================

  /// 獲取預設劇本範本
  List<CareScript> getDefaultTemplates(int elderId) {
    final now = DateTime.now();
    return [
      CareScript(
        id: 'template_morning',
        elderId: elderId,
        time: const TimeOfDay(hour: 8, minute: 0),
        message: '早安！新的一天開始了，記得吃早餐喔',
        type: ScriptType.greeting,
        enableVoice: true,
        repeatDays: ['週一', '週二', '週三', '週四', '週五', '週六', '週日'],
        enabled: false,
        createdAt: now,
      ),
      CareScript(
        id: 'template_medication',
        elderId: elderId,
        time: const TimeOfDay(hour: 8, minute: 30),
        message: '記得吃藥喔！按時服藥對身體很重要',
        type: ScriptType.reminder,
        enableVoice: true,
        repeatDays: ['週一', '週二', '週三', '週四', '週五', '週六', '週日'],
        enabled: false,
        createdAt: now,
      ),
      CareScript(
        id: 'template_lunch',
        elderId: elderId,
        time: const TimeOfDay(hour: 12, minute: 0),
        message: '午餐時間到了！記得吃飽飽',
        type: ScriptType.reminder,
        enableVoice: true,
        repeatDays: ['週一', '週二', '週三', '週四', '週五', '週六', '週日'],
        enabled: false,
        createdAt: now,
      ),
      CareScript(
        id: 'template_exercise',
        elderId: elderId,
        time: const TimeOfDay(hour: 15, minute: 0),
        message: '下午了，天氣不錯的話出去走走吧',
        type: ScriptType.activity,
        enableVoice: true,
        repeatDays: ['週一', '週二', '週三', '週四', '週五', '週六', '週日'],
        enabled: false,
        createdAt: now,
      ),
      CareScript(
        id: 'template_evening',
        elderId: elderId,
        time: const TimeOfDay(hour: 20, minute: 0),
        message: '晚安！該休息了，早點睡對身體好',
        type: ScriptType.greeting,
        enableVoice: true,
        repeatDays: ['週一', '週二', '週三', '週四', '週五', '週六', '週日'],
        enabled: false,
        createdAt: now,
      ),
    ];
  }
}
