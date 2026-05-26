import 'package:flutter/material.dart';

import '../news_article_screen.dart';

class NewsCardList extends StatelessWidget {
  final List<Map<String, dynamic>> newsItems;
  final int currentIndex;
  final String selectedCategory;
  final ValueChanged<int> onSelectTrack;
  final int userId;

  const NewsCardList({
    super.key,
    required this.newsItems,
    required this.currentIndex,
    required this.selectedCategory,
    required this.onSelectTrack,
    required this.userId,
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
    final filteredItems = selectedCategory == '全部'
        ? newsItems
        : newsItems
            .where((item) => (item['category'] ?? '') == selectedCategory)
            .toList();

    if (filteredItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            '目前沒有此分類的新聞',
            style: TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return Column(
      children: List.generate(filteredItems.length, (index) {
        final item = filteredItems[index];
        final originalIndex = newsItems.indexOf(item);
        final isCurrent = originalIndex == currentIndex;
        final title = (item['title'] ?? '').toString();
        final source = (item['category'] ?? '新聞').toString();
        final date = _formatNewsDate(item);
        final rawImageUrl =
            ((item['image_url'] ?? item['image']) ?? '').toString().trim();
        final imageUrl = rawImageUrl.startsWith('/')
            ? "https://localhost-0.tail5abf5e.ts.net$rawImageUrl"
            : rawImageUrl;
        final hasImage = imageUrl.startsWith('http');

        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => NewsArticleScreen(
                    newsItem: item,
                    newsItems: newsItems,
                    currentIndex: originalIndex,
                    userId: userId,
                    onListenNews: () {
                      onSelectTrack(originalIndex);
                    },
                  ),
                ),
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: isCurrent
                    ? Border.all(
                        color: const Color(0xFF59B294),
                        width: 3,
                      )
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                  if (isCurrent)
                    BoxShadow(
                      color: const Color(0xFF59B294).withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(isCurrent ? 17 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 圖片區域
                    SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          hasImage
                              ? Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _buildGradientPlaceholder(source),
                                )
                              : _buildGradientPlaceholder(source),
                          // 分類標籤
                          Positioned(
                            top: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B)
                                    .withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                source,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          // 播放中標示
                          if (isCurrent)
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF59B294),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.volume_up_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      '播放中',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // 文字內容區域
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF1E293B),
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '$source · $date'.toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
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
          size: 64,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
