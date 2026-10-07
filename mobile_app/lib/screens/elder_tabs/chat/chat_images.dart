import 'package:flutter/material.dart';

import '../../../services/api/family_updates_api.dart';
import '../../../widgets/ui/ui.dart';

/// 聊天紀錄存本機時，照片網址清單的編碼／解碼（舊紀錄沒有 images 欄位 → 空清單）。
List<String> decodeChatImages(dynamic raw) {
  if (raw is! List) return const [];
  return [
    for (final u in raw)
      if ((u ?? '').toString().trim().isNotEmpty) u.toString().trim(),
  ];
}

/// 小嘎轉述家人分享時附在氣泡下方的照片：1 張滿版圓角；2 張以上兩欄縮圖。
/// 點圖開全螢幕檢視（可雙指縮放，右上大叉叉關閉）。
class ChatImageGallery extends StatelessWidget {
  final List<String> images;
  const ChatImageGallery({super.key, required this.images});

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, box) {
      const gap = 8.0;
      final single = images.length == 1;
      final w = box.maxWidth.isFinite ? box.maxWidth : 240.0;
      final cell = single ? w : (w - gap) / 2;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final url in images)
            _ChatImageTile(
              url: url,
              width: cell,
              height: single ? cell * 0.75 : cell,
            ),
        ],
      );
    });
  }
}

class _ChatImageTile extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  const _ChatImageTile(
      {required this.url, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final full = ElderFamilyUpdatesApi.imageUrl(url);
    return Semantics(
      button: true,
      label: '家人分享的照片，點兩下放大',
      child: GestureDetector(
        key: const ValueKey('chat_image_tile'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ChatImageViewer(url: full),
        )),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: width,
            height: height,
            child: Image.network(
              full,
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, progress) => progress == null
                  ? child
                  : _placeholder(ctx, const CircularProgressIndicator()),
              errorBuilder: (ctx, _, __) => _placeholder(
                ctx,
                Text('照片暫時無法顯示',
                    textAlign: TextAlign.center,
                    style: ubanText(16, FontWeight.w600,
                        UbanColors.of(ctx).text2)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext ctx, Widget child) => Container(
        color: UbanColors.of(ctx).surface2,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: child,
      );
}

/// 全螢幕看照片：可雙指縮放；右上角大「關閉」鈕。
class ChatImageViewer extends StatelessWidget {
  final String url;
  const ChatImageViewer({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (ctx, child, p) => p == null
                        ? child
                        : const Center(child: CircularProgressIndicator()),
                    errorBuilder: (ctx, _, __) => Center(
                      child: Text('照片暫時無法顯示',
                          style: ubanText(20, FontWeight.w600, Colors.white)),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Semantics(
                button: true,
                label: '關閉照片',
                child: Material(
                  color: Colors.white24,
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: const ValueKey('chat_image_close'),
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).pop(),
                    child: const SizedBox(
                      width: 64,
                      height: 64,
                      child: Icon(Icons.close_rounded,
                          color: Colors.white, size: 40),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
