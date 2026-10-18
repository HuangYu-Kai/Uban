import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'family_question_draft.dart';
import 'family_share_draft.dart';

// ★ 2026-10-15 對話紀錄：AI 照護秘書的對話紀錄只存在這台手機（SharedPreferences），
// 不送後端、不影響 AI 回答。本檔是「畫面訊息 <-> 可存檔 JSON」的純函式，方便單元測試。
//
// 存檔原則：
// - 只存「過去式」的內容。草稿卡（分享／出題／提醒）若沒有被確認，還原時一律變成純文字，
//   不再有按鈕——避免幾天後誤按、把過期的提醒或分享送出去。
// - 已完成的動作（已分享到時光牆、已出題、已同步的提醒）保留結果，唯讀顯示。
// - 絕不存本機 File 路徑（重開 App 後檔案可能已不存在）；附照片的訊息改存上傳後的網址。

/// 每位長輩最多保留的訊息則數（超過只留最近的）。
const int kCopilotHistoryLimit = 100;

/// 本機存檔 key：每個家屬帳號、每位長輩各一份。
String copilotHistoryKey(int familyUserId, String elderId) =>
    'copilot_history_v1_${familyUserId}_$elderId';

/// 把 [value] 轉成一定能 jsonEncode 的結構；轉不動就回 null（寧可不存也不要讓整份存檔失敗）。
dynamic _jsonSafe(dynamic value) {
  try {
    return jsonDecode(jsonEncode(value));
  } catch (_) {
    return null;
  }
}

String? _nonEmptyString(dynamic v) =>
    (v is String && v.trim().isNotEmpty) ? v.trim() : null;

/// 取分享／出題草稿卡輸入框的文字；controller 不存在或已不能讀就回空字串。
String _controllerText(dynamic controller) {
  if (controller is TextEditingController) {
    try {
      return controller.text.trim();
    } catch (_) {
      return '';
    }
  }
  return '';
}

/// 把畫面上的一則訊息轉成可存檔的 JSON；不該存的訊息（歡迎詞 `ephemeral: true`）回 null。
///
/// [elderName] 只用在「已出題給○○」的文字。
Map<String, dynamic>? serializeCopilotMessage(
  Map<String, dynamic> msg, {
  required String elderName,
}) {
  if (msg['ephemeral'] == true) return null;

  final ts = msg['ts'];
  final out = <String, dynamic>{
    'isUser': msg['isUser'] == true,
    'text': (msg['text'] ?? '').toString(),
    'ts': ts is String && ts.isNotEmpty ? ts : DateTime.now().toIso8601String(),
  };

  final imageUrl = _nonEmptyString(msg['imageUrl']);
  if (imageUrl != null) out['imageUrl'] = imageUrl;
  final relay = _nonEmptyString(msg['relayAudioUrl']);
  if (relay != null) out['relayAudioUrl'] = relay;

  final status = msg['statusSummary'];
  if (status is Map) {
    final safe = _jsonSafe(status);
    if (safe is Map) out['statusSummary'] = safe;
  }

  // 還原過的訊息已經帶著舊的「封存文字／照片」，要原樣帶下去。
  final archived = <String>[
    if (msg['archivedLines'] is List)
      for (final l in msg['archivedLines'] as List)
        if (l is String && l.isNotEmpty) l,
  ];
  String? archivedImageUrl = _nonEmptyString(msg['archivedImageUrl']);

  // 提醒草稿：已同步的存結果；沒確認的變成文字。
  final drafts = msg['scheduleDrafts'];
  if (drafts is List && drafts.isNotEmpty) {
    if (msg['isApplied'] == true) {
      final safe = _jsonSafe(drafts);
      if (safe is List) {
        out['scheduleDrafts'] = safe;
        out['isApplied'] = true;
      }
    } else {
      for (final d in drafts) {
        if (d is! Map) continue;
        final time = (d['time_str'] ?? '').toString();
        final repeat = (d['repeat_days'] ?? '每天').toString();
        final title = (d['title'] ?? '排程').toString();
        archived.add('未確認的提醒草稿：$time（$repeat）$title');
      }
    }
  }

  // 分享卡。
  final sharePhase = msg['sharePhase'];
  if (sharePhase is ShareCardPhase) {
    final text = _controllerText(msg['shareController']);
    final shareImage = _nonEmptyString(msg['shareImageUrl']);
    final shown = text.isNotEmpty ? text : (shareImage != null ? '（照片）' : '');
    if (sharePhase == ShareCardPhase.sent) {
      archived.add('✓ 已分享到時光牆：$shown');
      archivedImageUrl = shareImage ?? archivedImageUrl;
    } else {
      archived.add('未送出的分享草稿：$shown');
    }
  }

  // 出題卡。
  final questionPhase = msg['questionPhase'];
  if (questionPhase is QuestionCardPhase) {
    final text = _controllerText(msg['questionController']);
    if (questionPhase == QuestionCardPhase.sent) {
      archived.add('✓ 已出題給$elderName：$text');
    } else {
      archived.add('未送出的出題草稿：$text');
    }
  }

  if (archived.isNotEmpty) out['archivedLines'] = archived;
  if (archivedImageUrl != null) out['archivedImageUrl'] = archivedImageUrl;
  return out;
}

/// 把存檔的 JSON 還原成畫面用的訊息 map（標記 `restored: true`）。
/// 欄位缺漏或型別不對一律用安全預設，不丟例外。
Map<String, dynamic> deserializeCopilotMessage(Map<String, dynamic> json) {
  final tsRaw = json['ts'];
  final ts = (tsRaw is String && DateTime.tryParse(tsRaw) != null) ? tsRaw : null;

  Map<String, dynamic>? status;
  final rawStatus = json['statusSummary'];
  if (rawStatus is Map) {
    status = {
      for (final e in rawStatus.entries) e.key.toString(): e.value,
    };
    // 畫面會直接 cast 的欄位，型別不對就拿掉，避免畫面爆掉。
    if (status['recent_topics'] is! List) status.remove('recent_topics');
    if (status['next_appointment'] is! String) status.remove('next_appointment');
  }

  // 提醒草稿只在「已套用」時才還原；每一筆必須是 Map。
  List<Map<String, dynamic>>? drafts;
  final applied = json['isApplied'] == true;
  final rawDrafts = json['scheduleDrafts'];
  if (applied && rawDrafts is List) {
    final list = <Map<String, dynamic>>[
      for (final d in rawDrafts)
        if (d is Map) {for (final e in d.entries) e.key.toString(): e.value},
    ];
    if (list.isNotEmpty) drafts = list;
  }

  final lines = <String>[
    if (json['archivedLines'] is List)
      for (final l in json['archivedLines'] as List)
        if (l is String && l.isNotEmpty) l,
  ];

  final text = json['text'];
  return {
    'isUser': json['isUser'] == true,
    'text': text is String ? text : (text == null ? '' : text.toString()),
    'ts': ts,
    'restored': true,
    'imageUrl': _nonEmptyString(json['imageUrl']),
    'relayAudioUrl': _nonEmptyString(json['relayAudioUrl']),
    'statusSummary': status,
    'scheduleDrafts': drafts,
    'isApplied': drafts != null,
    'archivedLines': lines,
    'archivedImageUrl': _nonEmptyString(json['archivedImageUrl']),
  };
}

/// 解析存檔字串：必須是 JSON 陣列；null／亂碼／非陣列回 []，陣列內非物件的項目略過。
List<Map<String, dynamic>> decodeCopilotHistory(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return [
      for (final e in decoded)
        if (e is Map) {for (final kv in e.entries) kv.key.toString(): kv.value},
    ];
  } catch (_) {
    return [];
  }
}

/// 把整串畫面訊息轉成存檔字串：丟掉不存的、只留最後 [kCopilotHistoryLimit] 則。
String encodeCopilotHistory(
  List<Map<String, dynamic>> messages, {
  required String elderName,
}) {
  final out = <Map<String, dynamic>>[];
  for (final m in messages) {
    try {
      final s = serializeCopilotMessage(m, elderName: elderName);
      if (s != null) out.add(s);
    } catch (_) {
      // 單則訊息序列化失敗就略過，不影響其他訊息。
    }
  }
  final kept = out.length > kCopilotHistoryLimit
      ? out.sublist(out.length - kCopilotHistoryLimit)
      : out;
  return jsonEncode(kept);
}
