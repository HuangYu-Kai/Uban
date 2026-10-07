import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'widgets/fam_interaction_ui.dart';
import 'widgets/fam_ui.dart';

/// AI 照護秘書「分享給長輩」的草稿資料（後端 `share_draft`，可能缺席／為 null）。
class ShareDraft {
  final String text;
  final String? imageUrl;
  const ShareDraft({required this.text, this.imageUrl});

  /// 解析後端回覆的 `share_draft`。舊版後端沒有此欄位、或格式不對時回 null
  /// （呼叫端就當作沒有分享草稿，不顯示卡片）。
  static ShareDraft? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final t = raw['text'];
    final img = raw['image_url'];
    final text = t is String ? t : '';
    final imageUrl = (img is String && img.trim().isNotEmpty) ? img.trim() : null;
    if (text.trim().isEmpty && imageUrl == null) return null;
    return ShareDraft(text: text, imageUrl: imageUrl);
  }
}

/// 分享草稿卡的狀態（由畫面持有，卡片本身無狀態，避免捲出畫面後遺失）。
enum ShareCardPhase { draft, sending, sent, cancelled }

/// 「送出」鈕是否可按：沒有文字且沒有照片、或正在送出時停用。
bool canSendShare({required String text, required bool hasImage, required bool sending}) {
  if (sending) return false;
  return text.trim().isNotEmpty || hasImage;
}

/// 對話中的分享草稿卡：可編輯文字、照片預覽、「送出給{稱呼}」／「取消」。
class ShareDraftCard extends StatelessWidget {
  final TextEditingController controller;
  final String? imageUrl;
  final String elderName;
  final ShareCardPhase phase;
  final String? errorText;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  const ShareDraftCard({
    super.key,
    required this.controller,
    required this.imageUrl,
    required this.elderName,
    required this.phase,
    required this.errorText,
    required this.onSend,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    if (phase == ShareCardPhase.sent) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          '已送出，小嘎會在$elderName下次聊天時轉達',
          style: famText(c.brandStrong, 14.5, weight: FontWeight.w700, height: 1.5),
        ),
      );
    }
    if (phase == ShareCardPhase.cancelled) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text('已取消分享', style: famText(c.text3, 14, height: 1.5)),
      );
    }
    final sending = phase == ShareCardPhase.sending;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('分享草稿', style: famText(c.text3, 13, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          FamInput(
            controller: controller,
            hintText: '想跟$elderName說什麼？',
            minLines: 2,
            maxLines: 5,
            height: 72,
            keyboardType: TextInputType.multiline,
          ),
          if (imageUrl != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 80,
                    alignment: Alignment.center,
                    color: c.brandContainer,
                    child: Text('照片預覽無法顯示', style: famText(c.text3, 13)),
                  ),
                ),
              ),
            ),
          ],
          if (errorText != null) ...[
            const SizedBox(height: 8),
            Text(errorText!, style: famText(c.danger, 13.5, height: 1.4)),
          ],
          const SizedBox(height: 10),
          // 送出鈕依輸入框內容即時啟停（空白且無照片不可送）。
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final ok = canSendShare(
                text: value.text,
                hasImage: imageUrl != null,
                sending: sending,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FamButton(
                    label: '送出給$elderName',
                    loading: sending,
                    onPressed: ok ? onSend : null,
                  ),
                  const SizedBox(height: 6),
                  FamButton(
                    label: '取消',
                    kind: FamButtonKind.ghost,
                    onPressed: sending ? null : onCancel,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
