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
    final imageUrl =
        ((newsItem['image_url'] ?? newsItem['image']) ?? '').toString().trim();
    final hasImage = imageUrl.startsWith('http');

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // 頂部圖片 + 返回按鈕
          SliverAppBar(
            expandedHeight: hasImage ? 280 : 0,
            pinned: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            leading: Padding(
              padding: const EdgeInsets.all(6),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: Color(0xFF1E293B),
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
            title: const Text(
              '← 返回',
              style: TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            flexibleSpace: hasImage
                ? FlexibleSpaceBar(
                    background: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFFF3F4F6),
                      ),
                    ),
                  )
                : null,
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
                      '$date',
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
    );
  }
}
