import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

class FamilyMarketplaceView extends StatefulWidget {
  const FamilyMarketplaceView({super.key});

  @override
  State<FamilyMarketplaceView> createState() => _FamilyMarketplaceViewState();
}

class _FamilyMarketplaceViewState extends State<FamilyMarketplaceView> {
  final Set<String> _installedScripts = {};
  final Set<String> _installingScripts = {};

  void _handleInstall(String title) async {
    if (_installedScripts.contains(title) ||
        _installingScripts.contains(title)) {
      return;
    }

    setState(() {
      _installingScripts.add(title);
    });

    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() {
        _installingScripts.remove(title);
        _installedScripts.add(title);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已成功安裝劇本：$title'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showDetails(String title, String desc) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          title,
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        content: Text(desc),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          '劇本市集',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 搜尋欄
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const TextField(
                decoration: InputDecoration(
                  hintText: '搜尋劇本：失智關懷、睡前故事...',
                  border: InputBorder.none,
                  icon: Icon(Icons.search, color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // 熱門分類
            Text(
              '熱門分類',
              style: GoogleFonts.notoSansTc(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildCategoryRow(),
            const SizedBox(height: 32),

            // 精選劇本列表
            Text(
              '熱門推薦',
              style: GoogleFonts.notoSansTc(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildMarketCard(
              title: '懷境金曲引導流',
              desc: '由專家設計的互動路徑，引導長輩從音樂進入往事回憶，有效提升認知活躍度。',
              author: '王醫師',
              isExpert: true,
              price: '50',
              icon: Icons.music_note,
              color: Colors.purple,
            ),
            _buildMarketCard(
              title: '每日節氣食補建議',
              desc: '根據當前節氣與長輩健康數據，自動生成溫暖的飲食叮嚀與家常聊點。',
              author: '李營養師',
              isExpert: true,
              price: '30',
              icon: Icons.spa,
              color: Colors.green,
            ),
            _buildMarketCard(
              title: '睡前放鬆冥想',
              desc: '專業助眠引導語配搭環境音，幫助長輩降低焦慮，平穩進入夢鄉。',
              author: 'UBan 團隊',
              isExpert: false,
              price: '免費',
              icon: Icons.nights_stay,
              color: Colors.indigo,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _categoryChip('失智預防', Icons.psychology, Colors.blue),
          _categoryChip('生活提醒', Icons.notifications_active, Colors.amber),
          _categoryChip('情感陪伴', Icons.favorite, Colors.pink),
          _categoryChip('趣味遊戲', Icons.videogame_asset, Colors.green),
        ],
      ),
    );
  }

  Widget _categoryChip(String label, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.notoSansTc(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarketCard({
    required String title,
    required String desc,
    required String author,
    required String price,
    required IconData icon,
    required Color color,
    bool isExpert = false,
  }) {
    final bool isInstalled = _installedScripts.contains(title);
    final bool isInstalling = _installingScripts.contains(title);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          '作者：$author',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        if (isExpert) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '專家認證',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  price.contains('免費') ? '免費' : 'NT\$ $price',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            desc,
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 16),
              const SizedBox(width: 4),
              const Text('4.9 (1.2k+ 次購買)'),
              const Spacer(),
              TextButton(
                onPressed: () => _showDetails(title, desc),
                child: const Text('了解更多'),
              ),
              SizedBox(
                width: 100,
                child: ElevatedButton(
                  onPressed: (isInstalled || isInstalling)
                      ? null
                      : () => _handleInstall(title),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isInstalled ? Colors.grey : color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  child: isInstalling
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(isInstalled ? '已安裝' : '取得劇本'),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.05, end: 0);
  }
}
