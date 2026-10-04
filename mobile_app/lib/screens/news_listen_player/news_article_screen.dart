import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../widgets/ui/ui.dart';

/// 新聞文章閱讀頁面
///
/// 提供無干擾的閱讀體驗，20pt 內文（行高 1.85），
/// 並包含「聆聽新聞」按鈕可跳回播放模式。
class NewsArticleScreen extends StatelessWidget {
  final Map<String, dynamic> newsItem;
  final List<Map<String, dynamic>> newsItems;
  final int currentIndex;
  final int userId;
  final VoidCallback onListenNews;

  const NewsArticleScreen({
    super.key,
    required this.newsItem,
    required this.newsItems,
    required this.currentIndex,
    required this.userId,
    required this.onListenNews,
  });

  String _formatNewsDate(Map<String, dynamic> item) {
    final raw = (item['published_at_raw'] ?? '').toString().trim();
    if (raw.isNotEmpty) {
      return raw.length >= 10 ? raw.substring(0, 10) : raw;
    }
    final parsed = (item['published_at'] ?? '').toString().trim();
    if (parsed.isNotEmpty) {
      return parsed.length >= 10 ? parsed.substring(0, 10) : parsed;
    }
    return '--';
  }

  @override
  Widget build(BuildContext context) {
    final title = (newsItem['title'] ?? '').toString();
    final content = (newsItem['content'] ?? '').toString();
    final source = (newsItem['category'] ?? '新聞').toString();
    final date = _formatNewsDate(newsItem);
    final rawImageUrl =
        ((newsItem['image_url'] ?? newsItem['image']) ?? '').toString().trim();
    // ⚠️ 不可寫死正式站網址（鐵律 #1）：這裡曾經直接寫死正式站的 Tailscale
    // 網域，會讓沙盒的建置防護（run_autonomous_sandbox.py 的
    // _assert_web_build_is_not_production）誤判成每一個建置都指向正式站而
    // 一律拒絕執行。改用 ApiService.serverRootUrl，讓建置時的
    // --dart-define=SERVER_IP 真正生效。
    final imageUrl = rawImageUrl.startsWith('/')
        ? "${ApiService.serverRootUrl}$rawImageUrl"
        : rawImageUrl;
    final hasImage = imageUrl.startsWith('http');

    final c = UbanColors.of(context);

    return Scaffold(
      backgroundColor: c.bg,
      body: ScrollConfiguration(
        behavior: const NoOverscrollBehavior(),
        child: CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            // 頂部圖片 + 返回按鈕（設計稿 `.ahero`）
            SliverAppBar(
              expandedHeight: 240,
              toolbarHeight: 64,
              pinned: true,
              backgroundColor: c.surface,
              surfaceTintColor: Colors.transparent,
              leadingWidth: 128,
              leading: Padding(
                padding: const EdgeInsets.only(left: 14, top: 8, bottom: 8),
                child: Semantics(
                  button: true,
                  label: '返回',
                  excludeSemantics: true,
                  child: PressableScale(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.arrow_back_ios_new_rounded,
                              color: Color(0xFF16201C), size: 20),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '返回',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ubanText(
                                  18, FontWeight.w700, const Color(0xFF16201C)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    hasImage
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _buildGradientPlaceholder(source),
                          )
                        : _buildGradientPlaceholder(source),
                    if (!hasImage)
                      Positioned(
                        right: 14,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.32),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('示意圖',
                              style: ubanText(
                                  14, FontWeight.w600, Colors.white)),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 文章內容（設計稿 `.abody`）
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 分類標籤
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: c.brandContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        source,
                        style: ubanText(16, FontWeight.w700, c.brandStrong),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 標題
                    Text(
                      title,
                      style:
                          ubanText(28, FontWeight.w900, c.text, height: 1.35),
                    ),
                    const SizedBox(height: 10),

                    // 日期
                    Text(
                      date,
                      style: ubanText(16, FontWeight.w500, c.text3),
                    ),
                    const SizedBox(height: 16),

                    // 聆聽新聞按鈕（主要 CTA，xl 76）
                    UbanButton(
                      label: '聆聽新聞',
                      icon: Icons.headphones_rounded,
                      size: UbanButtonSize.xl,
                      onPressed: () {
                        onListenNews();
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(height: 20),

                    // 內文：20pt、行高 1.85
                    Text(
                      content.isNotEmpty ? content : '（此新聞暫無內文）',
                      style: ubanText(
                        20,
                        FontWeight.w400,
                        content.isNotEmpty ? c.text : c.text3,
                        height: 1.85,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientPlaceholder(String category) {
    final List<Color> colors;
    final IconData icon;

    switch (category) {
      case '國際':
        colors = [const Color(0xFF2C3E50), const Color(0xFF3498DB)];
        icon = Icons.public_rounded;
        break;
      case '財經':
        colors = [const Color(0xFF11998E), const Color(0xFF38EF7D)];
        icon = Icons.trending_up_rounded;
        break;
      case '運動':
        colors = [const Color(0xFFF12711), const Color(0xFFF5AF19)];
        icon = Icons.sports_basketball_rounded;
        break;
      case '生活':
      case '健康':
        colors = [const Color(0xFF833AB4), const Color(0xFFFD1D1D)];
        icon = Icons.favorite_rounded;
        break;
      case '科技':
        colors = [const Color(0xFF00C6FF), const Color(0xFF0072FF)];
        icon = Icons.biotech_rounded;
        break;
      default:
        colors = [const Color(0xFF8BAF88), const Color(0xFF59B294)]; // Theme Green
        icon = Icons.newspaper_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          size: 72,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

class NoOverscrollBehavior extends ScrollBehavior {
  const NoOverscrollBehavior();

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child; // Completely disables the stretch/glow overscroll indicator
  }
}
