import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../widgets/youtube_bubble_player.dart';

// 【全新升級】長輩專屬落葉話題卡片 (支援左滑開始聊天、右滑捨棄話題)

class LeafMessageCard extends StatefulWidget {
  final String id;
  final String message;
  final String? imageUrl;
  final String? videoId; // 支援影片播放
  final VoidCallback onSwipeLeft;  // 左滑: 開始聊天
  final VoidCallback onSwipeRight; // 右滑: 捨棄話題

  const LeafMessageCard({
    super.key,
    required this.id,
    required this.message,
    this.imageUrl,
    this.videoId,
    required this.onSwipeLeft,
    required this.onSwipeRight,
  });

  @override
  State<LeafMessageCard> createState() => _LeafMessageCardState();
}

class _LeafMessageCardState extends State<LeafMessageCard> {
  /// 正規化圖片 URL，修正常見的錯誤格式
  String _normalizeImageUrl(String url) {
    // 修正 fastly.picsum.photos → picsum.photos（fastly CDN URL 回傳 400）
    String normalized = url.replaceAll('fastly.picsum.photos', 'picsum.photos');
    // 移除 picsum URL 尾端的 .jpg（picsum.photos 不需要副檔名）
    if (normalized.contains('picsum.photos') && normalized.endsWith('.jpg')) {
      normalized = normalized.substring(0, normalized.length - 4);
    }
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    // 右滑 (startToEnd) 捨棄背景 - 莫蘭迪紅
    final Widget discardBg = Container(
      decoration: BoxDecoration(
        color: const Color(0xFFD48D8D), // 禪意暖紅
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF8C6D58),
          width: 3.5,
        ),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 32),
      child: Row(
        children: [
          const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 42),
          const SizedBox(width: 12),
          Text(
            '捨棄話題',
            style: GoogleFonts.notoSansTc(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );

    // 左滑 (endToStart) 聊天背景 - 莫蘭迪綠
    final Widget chatBg = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF8CAF9F), // 禪意碧綠
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF8C6D58),
          width: 3.5,
        ),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '開始聊天',
            style: GoogleFonts.notoSansTc(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 42),
        ],
      ),
    );

    return Center(
      child: Dismissible(
        // 使用 leaf 的 id 做 ValueKey，確保滑動不遺失狀態
        key: ValueKey('leaf_dismiss_${widget.id}'),
        direction: DismissDirection.horizontal,
        background: discardBg,
        secondaryBackground: chatBg,
        onDismissed: (direction) {
          if (direction == DismissDirection.endToStart) {
            widget.onSwipeLeft();
          } else if (direction == DismissDirection.startToEnd) {
            widget.onSwipeRight();
          }
        },
        child: Container(
          width: MediaQuery.of(context).size.width * 0.88,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.70,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
          decoration: BoxDecoration(
            // 溫潤宣紙金沙漸層
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFDF9), Color(0xFFFDFBF7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            // 古雅沉香實木邊框
            border: Border.all(
              color: const Color(0xFF8C6D58),
              width: 3.5,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
              // 微熱浮動水燈光暈
              BoxShadow(
                color: const Color(0xFFFFB74D).withOpacity(0.18),
                blurRadius: 25,
                spreadRadius: 3,
              ),
            ],
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 頂部插圖與精緻標題
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFFFB74D),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '捎來的禪意捎信',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF8C6D58),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFFFB74D),
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 泥金精細分隔線
                Container(
                  height: 1.5,
                  width: 80,
                  color: const Color(0xFFD7CCC8),
                ),
                const SizedBox(height: 24),

                // 2. 拍立得紙框家人照片 (若有圖片則展示)
                if (widget.imageUrl != null) ...[
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE0DCD3), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            _normalizeImageUrl(widget.imageUrl!),
                            fit: BoxFit.cover,
                            height: 180,
                            width: double.infinity,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                height: 180,
                                color: const Color(0xFFF5F2EB),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF8C6D58),
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              debugPrint('LeafMessageCard image load error: $error | url: ${widget.imageUrl}');
                              return Container(
                                height: 180,
                                color: const Color(0xFFF5F2EB),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.broken_image_rounded,
                                      color: Color(0xFFBCAAA4),
                                      size: 48,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '圖片載入失敗',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                ],

                // 3. 訊息主體 (超大高對比巧克力黑體，長輩易讀)
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 27,
                    height: 1.55,
                    color: const Color(0xFF3E2723), // 深巧克力色，對比清晰溫和
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.videoId != null) ...[
                  const SizedBox(height: 20),
                  YoutubeBubblePlayer(videoId: widget.videoId!),
                ],
                const SizedBox(height: 32),

                // 4. 滑動引導指示 (左滑聊天，右滑捨棄)
                Text(
                  '👈 左滑開始聊 | 右滑捨棄 👉',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    color: const Color(0xFF8D6E63),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
    );
  }
}
