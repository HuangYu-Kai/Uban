import 'package:flutter/material.dart';

class NewsSelectionList extends StatelessWidget {
  final List<Map<String, dynamic>> newsItems;
  final int currentIndex;
  final String selectedCategory;
  final ValueChanged<int> onSelectTrack;

  const NewsSelectionList({
    super.key,
    required this.newsItems,
    required this.currentIndex,
    required this.selectedCategory,
    required this.onSelectTrack,
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
          child: Text('目前沒有此分類的新聞',
              style: TextStyle(color: Colors.white70, fontSize: 18)),
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
        final imageUrl =
            ((item['image_url'] ?? item['image']) ?? '').toString().trim();
        final hasImage = imageUrl.startsWith('http');

        return Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: GestureDetector(
            onTap: () => onSelectTrack(originalIndex),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 220, // 增加到 220，確保萬無一失
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isCurrent
                      ? const Color(0xFFFFD700)
                      : Colors.white.withValues(alpha: 0.15),
                  width: isCurrent ? 3.5 : 1,
                ),
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(21),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: hasImage
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(color: const Color(0xFF2D3748)),
                            )
                          : Container(color: const Color(0xFF2D3748)),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.2),
                              Colors.black.withValues(alpha: 0.8),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? const Color(0xFFFFD700)
                                      : Colors.white24,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  source,
                                  style: TextStyle(
                                    color: isCurrent
                                        ? const Color(0xFF1E293B)
                                        : Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (isCurrent)
                                const Icon(Icons.volume_up,
                                    color: Color(0xFFFFD700), size: 20),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              height: 1.3,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            date,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
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
}
