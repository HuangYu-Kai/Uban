import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../widgets/ui/ui.dart';

// ★ 2026-10-07 交接 B1／E：「長輩檔案」與「對話偏好」兩頁共用的資料存取與小元件。
//   原本單一頁 elder_profile_edit_screen.dart 已拆成：
//   - elder_basic_profile_screen.dart（長輩檔案）
//   - elder_talk_preference_screen.dart（對話偏好）

/// 兩頁的資料存取介面。正式環境走 [ApiService]；widget 測試可注入假的實作。
class ElderProfileGateway {
  /// GET `/api/user/profile/{id}`，回 `{status, data}`。
  final Future<Map<String, dynamic>> Function(int userId) load;

  /// PUT `/api/user/profile/{id}`，只送有改的欄位。
  final Future<Map<String, dynamic>> Function(int userId, Map<String, dynamic> fields) save;

  /// 該長輩的話題偏好清單：`{status, data: List}`。
  final Future<Map<String, dynamic>> Function(String elderId) listTopics;

  /// 新增話題（`priority`／`avoid`／`forbidden`）。
  final Future<Map<String, dynamic>> Function(String elderId, String keyword, String type) addTopic;

  final Future<Map<String, dynamic>> Function(int topicId) deleteTopic;

  const ElderProfileGateway({
    required this.load,
    required this.save,
    required this.listTopics,
    required this.addTopic,
    required this.deleteTopic,
  });

  const ElderProfileGateway.live()
      : load = ApiService.getElderProfile,
        save = ApiService.putProfileFields,
        listTopics = ApiService.getTalkTopics,
        addTopic = ApiService.createTalkTopic,
        deleteTopic = ApiService.deleteTalkTopic;
}

/// 從 `{status, data}` 取出 `data`；失敗回 null（呼叫端用 [ApiService.failureMessageOf] 取原因）。
Map<String, dynamic>? profileDataOf(Map<String, dynamic> response) {
  if (response['status'] == 'success' && response['data'] is Map) {
    return Map<String, dynamic>.from(response['data'] as Map);
  }
  return null;
}

/// 長輩的 user id（呼叫端傳入的 elderData 可能叫 user_id 或 id）。
int? elderUserIdOf(Map<String, dynamic> elderData) {
  final v = elderData['user_id'] ?? elderData['id'];
  if (v is int) return v;
  return int.tryParse('${v ?? ''}');
}

/// 後端存的性別可能是 M／F，也可能是「男／女」；正規化成 'M'／'F'，其他回 null（未填）。
String? normalizeGender(dynamic raw) {
  final s = '${raw ?? ''}'.trim();
  if (s.isEmpty) return null;
  if (s.contains('女') || s.toLowerCase().startsWith('f')) return 'F';
  if (s.contains('男') || s.toLowerCase().startsWith('m')) return 'M';
  return null;
}

/// 把使用者輸入的興趣／素材拆成清單（逗號、全形逗號、頓號、換行皆可，去空白、去重複）。
List<String> splitInterests(String text) {
  final seen = <String>{};
  final out = <String>[];
  for (final part in text.split(RegExp(r'[,，、\n]'))) {
    final t = part.trim();
    if (t.isNotEmpty && seen.add(t)) out.add(t);
  }
  return out;
}

void showProfileSnack(BuildContext context, String message, {bool success = false}) {
  final c = UbanColors.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, style: ubanText(15, FontWeight.w600, Colors.white)),
      backgroundColor: success ? c.brandFill : c.danger,
      behavior: SnackBarBehavior.floating,
    ));
}

/// 區塊卡片：標題＋內容。標題在 Expanded 內可收縮（鐵律 #14）。
class ProfileSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const ProfileSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return UbanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: c.brandStrong),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(18, FontWeight.w800, c.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

/// 小標籤（欄位上方說明）。文字可換行不溢位。
class ProfileLabel extends StatelessWidget {
  final String text;
  const ProfileLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: ubanText(14, FontWeight.w700, c.text2, height: 1.4)),
    );
  }
}

/// 載入失敗時的整頁狀態（可重試），避免顯示一張空表單讓人誤存。
class ProfileLoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ProfileLoadError({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 40, color: c.text3),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: ubanText(16, FontWeight.w600, c.text2, height: 1.5),
            ),
            const SizedBox(height: 16),
            UbanButton(
              label: '重新載入',
              expand: false,
              variant: UbanButtonVariant.tonal,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
