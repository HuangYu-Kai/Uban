import 'package:flutter/material.dart';

import '../../../services/api_service.dart';
import '../../../widgets/ui/ui.dart';
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

    final c = UbanColors.of(context);

    if (filteredItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            '目前沒有此分類的新聞',
            textAlign: TextAlign.center,
            style: ubanText(18, FontWeight.w500, c.text3),
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
        // ⚠️ 不可寫死正式站網址（鐵律 #1），且會讓沙盒建置防護誤判——改用
        // ApiService.serverRootUrl（同一修法見 news_article_screen.dart）。
        final imageUrl = rawImageUrl.startsWith('/')
            ? "${ApiService.serverRootUrl}$rawImageUrl"
            : rawImageUrl;
        final hasImage = imageUrl.startsWith('http');

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: PressableScale(
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
                color: c.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isCurrent ? c.brand : c.line,
                  width: isCurrent ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(isCurrent ? 22 : 23),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 圖片區域
                    SizedBox(
                      height: 150,
                      width: double.infinity,
                      child: Stack(
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
                          // 分類標籤（疊在圖上，固定白底深字）
                          Positioned(
                            top: 12,
                            left: 12,
                            right: 110,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  source,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ubanText(
                                      15, FontWeight.w700, const Color(0xFF16201C)),
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
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: c.brandFill,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.volume_up_rounded,
                                        color: c.onBrand, size: 18),
                                    const SizedBox(width: 4),
                                    Text('播放中',
                                        style: ubanText(
                                            15, FontWeight.w700, c.onBrand)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // 文字內容區域
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: ubanText(21, FontWeight.w900, c.text,
                                height: 1.4),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$source · $date',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ubanText(16, FontWeight.w500, c.text3),
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
