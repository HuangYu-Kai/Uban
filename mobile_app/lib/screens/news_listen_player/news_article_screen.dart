import 'package:flutter/material.dart';

/// 新聞文章閱讀頁面
///
/// 提供無干擾的閱讀體驗，22px 內文字體，
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
    final imageUrl = rawImageUrl.startsWith('/')
        ? "https://localhost-0.tail5abf5e.ts.net$rawImageUrl"
        : rawImageUrl;
    final hasImage = imageUrl.startsWith('http');

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: ScrollConfiguration(
        behavior: const NoOverscrollBehavior(),
        child: CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
          // 頂部圖片 + 返回按鈕
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            leadingWidth: 120,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.arrow_back_rounded,
                        color: Color(0xFF1E293B),
                        size: 20,
                      ),
                      SizedBox(width: 4),
                      Text(
                        '返回',
                        style: TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: hasImage
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildGradientPlaceholder(source),
                    )
                  : _buildGradientPlaceholder(source),
            ),
          ),

          // 文章內容
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 分類標籤
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF59B294).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        source,
                        style: const TextStyle(
                          color: Color(0xFF59B294),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 標題
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF1E293B),
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        height: 1.3,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 日期
                    Text(
                      date,
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 分隔線
                    Container(
                      height: 1,
                      color: const Color(0xFFE5E7EB),
                    ),
                    const SizedBox(height: 24),

                    // 聆聽新聞按鈕
                    GestureDetector(
                      onTap: () {
                        onListenNews();
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF8BAF88), Color(0xFF59B294)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  const Color(0xFF59B294).withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.headphones_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                            SizedBox(width: 10),
                            Text(
                              '聆聽新聞',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // 內文
                    Text(
                      content.isNotEmpty ? content : '（此新聞暫無內文）',
                      style: TextStyle(
                        color: content.isNotEmpty
                            ? const Color(0xFF374151)
                            : const Color(0xFF9CA3AF),
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                        height: 1.8,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 60),
                  ],
                ),
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
