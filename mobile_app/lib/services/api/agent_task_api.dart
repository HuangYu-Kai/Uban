import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// ★ 2026-11 代理人協調：家屬端 API 層。
/// 家屬的 AI 照護秘書把問題交給長輩的小嘎去問，問到後回報（`agent-task-done`）。

/// 交辦結果。[message] 一律是可直接給家屬看的繁體中文。
class AgentTaskCreateResult {
  final bool ok;
  final String message;
  final String taskId;
  const AgentTaskCreateResult(this.ok, this.message, {this.taskId = ''});
}

class AgentTaskApi {
  static const String networkErrorMessage = '目前連不上伺服器，請確認網路後再試一次';
  static const String defaultSentMessage = '已交給小嘎，問到會通知您。';

  /// 從後端錯誤回應挑出可顯示的原因（FastAPI 為 `detail`）。
  static String? _detail(Map<String, dynamic>? res) {
    final d = res?['detail'] ?? res?['message'];
    return d is String && d.trim().isNotEmpty ? d.trim() : null;
  }

  /// 解析 `POST /api/agent_task/create` 的回應（純函式，方便測試）。
  /// 404（未綁定）與 409（待辦過多）後端皆回 `detail`；ApiClient 不帶狀態碼，故以 detail 為準。
  static AgentTaskCreateResult parseCreateResponse(Map<String, dynamic>? res) {
    if (res == null) return const AgentTaskCreateResult(false, networkErrorMessage);
    if (res['success'] == true) {
      final data = res['data'];
      final reply = data is Map ? (data['reply_text'] ?? '').toString().trim() : '';
      final id = data is Map ? (data['task_id'] ?? '').toString() : '';
      return AgentTaskCreateResult(true, reply.isEmpty ? defaultSentMessage : reply,
          taskId: id);
    }
    final detail = _detail(res);
    return AgentTaskCreateResult(
        false, detail ?? '暫時無法交給小嘎，請確認已與長輩完成綁定，稍後再試');
  }

  static Future<AgentTaskCreateResult> create({
    required int familyUserId,
    required String elderId,
    required String question,
    required String purpose,
    required String followup,
  }) async {
    try {
      final res = await ApiClient.post('/api/agent_task/create', {
        'family_user_id': familyUserId,
        'elder_id': elderId,
        'question': question,
        'purpose': purpose,
        'followup': followup,
      });
      return parseCreateResponse(res);
    } catch (e) {
      debugPrint('⚠️ [AgentTaskApi] create error: $e');
      return const AgentTaskCreateResult(false, networkErrorMessage);
    }
  }

  /// `GET /api/agent_task/list`；失敗回 null（呼叫端靜默略過）。
  static Future<List<Map<String, dynamic>>?> list({
    required int familyUserId,
    required String elderId,
    int limit = 20,
  }) async {
    try {
      final res = await ApiClient.get(
          '/api/agent_task/list?family_user_id=$familyUserId&elder_id=${Uri.encodeQueryComponent(elderId)}&limit=$limit');
      if (res == null || res['success'] != true) return null;
      final data = res['data'];
      final tasks = data is Map ? data['tasks'] : null;
      if (tasks is! List) return null;
      return [
        for (final t in tasks)
          if (t is Map) {for (final e in t.entries) e.key.toString(): e.value},
      ];
    } catch (e) {
      debugPrint('⚠️ [AgentTaskApi] list error: $e');
      return null;
    }
  }
}
