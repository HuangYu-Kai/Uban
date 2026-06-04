import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../services/api_service.dart';

// 【全新升級】暖心水燈禪意木牌面板 (取代荷葉，提供頂級字體對比與長輩輔助按鈕)

class LotusLeafCard extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  final String? imageUrl;

  const LotusLeafCard({
    super.key,
    required this.message,
    required this.onDismiss,
    this.imageUrl,
  });

  /// 正規化圖片 URL
  String _normalizeImageUrl(String url) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      final base = ApiService.baseUrl.replaceAll('/api', '');
      if (url.startsWith('/')) {
        return '$base$url';
      }
      return '$base/$url';
    }
    String normalized = url.replaceAll('fastly.picsum.photos', 'picsum.photos');
    if (normalized.contains('picsum.photos') && normalized.endsWith('.jpg')) {
      normalized = normalized.substring(0, normalized.length - 4);
    }
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Dismissible(
        // 【核心修正】使用固定的 ValueKey 代替每次重建都不同的 UniqueKey()，
        // 確保手勢狀態在滑動過程中不會因為重繪而被取消，左右滑動刪除功能才能完美生效！
        key: const ValueKey('notification_dismissible'),
        direction: DismissDirection.horizontal,
        onDismissed: (_) => onDismiss(),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.88,
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            // 溫暖的宣紙/象牙白底色，提供最頂級的長輩可讀性與視覺光澤
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFDF9), Color(0xFFFDFBF7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            // 典雅的沉香木紋邊框
            border: Border.all(
              color: const Color(0xFF8C6D58),
              width: 3.5,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              // 卡片陰影
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
              // 水燈暖光暈渲染 (營造水面祈福水燈的禪意發光感)
              BoxShadow(
                color: const Color(0xFFFFB74D).withOpacity(0.25),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 頂部水燈插圖與優雅標題
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.star_rounded,
                    color: Color(0xFFFFB74D),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '家人捎來的暖心訊息',
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
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 精緻的泥金分隔線
              Container(
                height: 1.5,
                width: 80,
                color: const Color(0xFFD7CCC8),
              ),
              const SizedBox(height: 24),
              // 2. 拍立得紙框家人照片 (若有圖片則展示)
              if (imageUrl != null) ...[
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
                          _normalizeImageUrl(imageUrl!),
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
                            debugPrint('LotusLeafCard image load error: $error | url: $imageUrl');
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

              // 訊息主體 (超大高對比黑體字，極度體貼長輩)
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansTc(
                  fontSize: 26,
                  height: 1.5,
                  color: const Color(0xFF3E2723), // 溫和高雅的深巧克力木褐色，對比度極佳且不傷眼
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),
              // 底部互動區域
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 1. 直覺的點擊按鈕，長輩不需學習滑動也可輕鬆關閉，大幅提升無障礙體驗
                  ElevatedButton(
                    onPressed: onDismiss,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8C6D58),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 2,
                    ),
                    child: Text(
                      '讀完了，收起',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 2. 指示性滑動提示
              Text(
                '👈 左右滑動亦可快速收起 👉',
                style: GoogleFonts.notoSansTc(
                  fontSize: 13,
                  color: const Color(0xFF8D6E63),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
    );
  }
}
