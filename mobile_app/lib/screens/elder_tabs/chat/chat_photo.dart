import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart' show ImageSource;

import '../../../widgets/ui/ui.dart';

/// ★ 2026-10-17 拍照問小嘎：長輩在聊天頁傳照片給小嘎（藥袋、食物、文件…）用到的
/// 純呈現元件與小工具。不碰網路、相機或相簿：選圖、上傳、送出都由
/// `ElderChatScreen` 負責，這裡只管版面與字級，所以可以單獨 pump 測試。

/// 長輩沒打字就直接送照片時，氣泡與送給後端的預設問句。
const String kChatPhotoDefaultText = '請幫我看這張照片';

/// 照片縮圖在氣泡裡的邊長（dp）。
const double kChatPhotoThumbSize = 160;

/// 取出 `POST /api/ai/upload_image` 回應裡的相對網址（`/uploads/xxx.jpg`）。
/// 回應格式：`{"status":"success","data":{"image_url":"/uploads/<name>"}}`；
/// 任何格式不符（含 `{'error': ...}`）一律回 null，呼叫端據此當作上傳失敗。
String? extractUploadedImageUrl(Map<String, dynamic> response) {
  if (response['status'] != 'success') return null;
  final data = response['data'];
  if (data is! Map) return null;
  final url = data['image_url'];
  if (url is String && url.trim().isNotEmpty) return url.trim();
  return null;
}

/// 選圖失敗（權限被拒、相機不可用…）時，給長輩看的白話說明。
String chatPhotoPickErrorMessage(Object error, ImageSource source) {
  final isCamera = source == ImageSource.camera;
  if (error is PlatformException) {
    final code = error.code;
    if (code == 'camera_access_denied' || code == 'camera_access_restricted') {
      return '沒有相機權限，請到手機「設定」允許相機後再試';
    }
    if (code == 'photo_access_denied' || code == 'photo_access_restricted') {
      return '沒有相簿權限，請到手機「設定」允許讀取相片後再試';
    }
  }
  return isCamera ? '相機暫時無法使用，請改從相簿選' : '相簿暫時無法開啟，請稍後再試';
}

/// 彈出「拍照／從相簿選／取消」底部選單，回傳選到的來源；取消或點外面關閉回 null。
Future<ImageSource?> showChatPhotoSourceSheet(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const ChatPhotoSourceSheet(),
  );
}

/// 底部選單本體：兩顆大按鈕＋取消。字 24、按鈕高 ≥72，窄螢幕下文字可收縮不溢位。
class ChatPhotoSourceSheet extends StatelessWidget {
  const ChatPhotoSourceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '要怎麼給小嘎看照片？',
              textAlign: TextAlign.center,
              style: ubanText(24, FontWeight.w800, c.text),
            ),
            const SizedBox(height: 16),
            _SourceButton(
              key: const ValueKey('chat_photo_camera'),
              icon: Icons.photo_camera_rounded,
              label: '拍照',
              filled: true,
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            const SizedBox(height: 12),
            _SourceButton(
              key: const ValueKey('chat_photo_gallery'),
              icon: Icons.photo_library_rounded,
              label: '從相簿選',
              filled: false,
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 12),
            _SourceButton(
              key: const ValueKey('chat_photo_cancel'),
              icon: Icons.close_rounded,
              label: '取消',
              filled: false,
              quiet: true,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final bool quiet;
  final VoidCallback onTap;

  const _SourceButton({
    super.key,
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
    this.quiet = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final bg = filled ? c.brandFill : (quiet ? Colors.transparent : c.brandContainer);
    final fg = filled ? c.onBrand : (quiet ? c.text2 : c.brandStrong);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 32, color: fg),
                const SizedBox(width: 12),
                // 文字包 Flexible：窄螢幕或放大字級時收縮，不出現 RenderFlex 溢位。
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ubanText(24, FontWeight.w800, fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 使用者氣泡內容：照片縮圖（圓角 160×160）＋下方的文字。
/// [image] 由呼叫端傳入（本機 `FileImage`），讓測試可以用記憶體圖片取代。
class ChatPhotoBubbleContent extends StatelessWidget {
  final ImageProvider image;
  final String text;
  final Color textColor;

  const ChatPhotoBubbleContent({
    super.key,
    required this.image,
    required this.text,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: kChatPhotoThumbSize,
            height: kChatPhotoThumbSize,
            child: Image(
              key: const ValueKey('chat_photo_thumb'),
              image: image,
              fit: BoxFit.cover,
              semanticLabel: '您傳給小嘎的照片',
              errorBuilder: (ctx, _, __) => Container(
                color: c.surface2,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(8),
                child: Text(
                  '照片無法顯示',
                  textAlign: TextAlign.center,
                  style: ubanText(18, FontWeight.w600, c.text2),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          text,
          style: ubanText(20, FontWeight.w600, textColor, height: 1.5),
        ),
      ],
    );
  }
}
