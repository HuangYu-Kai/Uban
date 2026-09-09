import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../models/memoir_story.dart';
import '../../services/memoir_service.dart';
import '../../widgets/memoir_detail_sheet.dart';

/// 長輩專屬數位自傳與人生回憶錄畫廊 (MemoirsGalleryScreen)
///
/// 支援標籤篩選、時間軸列表模式、手作自傳繪本翻頁模式 (Storybook Mode)、
/// 以及「委託小豬向長輩提問」互動。
class MemoirsGalleryScreen extends StatefulWidget {
  final String elderId;
  final String elderName;
  final String familyUserName;

  const MemoirsGalleryScreen({
    super.key,
    required this.elderId,
    required this.elderName,
    this.familyUserName = '家屬',
  });

  @override
  State<MemoirsGalleryScreen> createState() => _MemoirsGalleryScreenState();
}

class _MemoirsGalleryScreenState extends State<MemoirsGalleryScreen> {
  final MemoirService _service = MemoirService.instance;
  List<MemoirStory> _stories = [];
  bool _isLoading = true;
  String _selectedTag = '全部';
  bool _isStorybookMode = false; // 是否切換至自傳翻頁書模式
  late PageController _pageController;
  int _currentBookPage = 0;

  final List<String> _tags = ['全部', '經典回憶', '美食記憶', '溫馨寄語', '奮鬥歲月', '❤️ 珍藏'];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _service.addListener(_onServiceUpdate);
    _loadStories();
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _pageController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      _loadStories();
    }
  }

  Future<void> _loadStories() async {
    final list = await _service.getMemoirs(widget.elderId);
    if (mounted) {
      setState(() {
        _stories = list;
        _isLoading = false;
      });
    }
  }

  List<MemoirStory> get _filteredStories {
    if (_selectedTag == '全部') return _stories;
    if (_selectedTag == '❤️ 珍藏') {
      return _stories.where((s) => s.isFavorite).toList();
    }
    return _stories.where((s) => s.tag == _selectedTag).toList();
  }

  void _showDelegatePromptDialog() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textController = TextEditingController();
    final recommended = _service.getRecommendedPrompts();
    String selectedCategory = '經典回憶';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E2836) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: cs.outline.withValues(alpha: 0.3), width: 1.5),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF97316).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Text('🐷', style: TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '委託小豬向${widget.elderName}提問',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      '小豬會在日常閒聊時主動幫您發問',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💡 點選推薦問題：',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: recommended.take(4).map((item) {
                      final q = item['question']!;
                      return ActionChip(
                        label: Text(
                          q,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansTc(fontSize: 11),
                        ),
                        backgroundColor: isDark ? const Color(0xFF131B24) : const Color(0xFFFFF7ED),
                        side: BorderSide(color: const Color(0xFFF97316).withValues(alpha: 0.4)),
                        onPressed: () {
                          setDialogState(() {
                            textController.text = q;
                            selectedCategory = item['tag'] ?? '經典回憶';
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '或是自訂想問的話題：',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: textController,
                    maxLines: 3,
                    style: GoogleFonts.notoSansTc(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '例如：想聽阿公聊聊年輕時怎麼追到阿嬤的？',
                      hintStyle: GoogleFonts.notoSansTc(fontSize: 13, color: cs.onSurfaceVariant),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF131B24) : const Color(0xFFF9FAFB),
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFF97316), width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('取消', style: GoogleFonts.notoSansTc(color: cs.onSurfaceVariant)),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final q = textController.text.trim();
                if (q.isEmpty) return;

                final messenger = ScaffoldMessenger.of(context);
                final delegation = MemoirPromptDelegation(
                  id: 'del_${DateTime.now().millisecondsSinceEpoch}',
                  elderId: widget.elderId,
                  question: q,
                  category: selectedCategory,
                  requestedBy: widget.familyUserName,
                  createdAt: DateTime.now(),
                );

                await _service.delegatePrompt(delegation);
                if (ctx.mounted) Navigator.pop(ctx);

                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('🐷 小豬已收下委託！下次閒聊將主動向長輩提問 ❤️'),
                      backgroundColor: Color(0xFFF97316),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.send_rounded, size: 16),
              label: Text('託付給小豬', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF97316),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8F6F0),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📖 ${widget.elderName}的數位自傳回憶錄',
              style: GoogleFonts.notoSansTc(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
            ),
            Text(
              '珍藏 ${_stories.length} 篇口述回憶 · 世代傳承',
              style: GoogleFonts.notoSansTc(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          // 模式切換（列表 vs 翻頁自傳書）
          IconButton(
            tooltip: _isStorybookMode ? '切換列表模式' : '切換繪本翻頁模式',
            icon: Icon(
              _isStorybookMode ? Icons.view_agenda_rounded : Icons.auto_stories_rounded,
              color: const Color(0xFFF97316),
            ),
            onPressed: () {
              setState(() {
                _isStorybookMode = !_isStorybookMode;
              });
            },
          ),
          // 委託小豬提問
          TextButton.icon(
            onPressed: _showDelegatePromptDialog,
            icon: const Text('🐷', style: TextStyle(fontSize: 16)),
            label: Text(
              '委託提問',
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFF97316),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 標籤篩選列
                if (!_isStorybookMode)
                  Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _tags.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        final tag = _tags[i];
                        final isSelected = tag == _selectedTag;
                        return ChoiceChip(
                          label: Text(
                            tag,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? Colors.white : cs.onSurface,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: const Color(0xFFF97316),
                          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                          side: BorderSide(
                            color: isSelected
                                ? const Color(0xFFF97316)
                                : cs.outline.withValues(alpha: 0.3),
                          ),
                          onSelected: (val) {
                            if (val) {
                              setState(() => _selectedTag = tag);
                            }
                          },
                        );
                      },
                    ),
                  ),

                // 內容視圖：翻頁書模式 or 列表模式
                Expanded(
                  child: _isStorybookMode
                      ? _buildStorybookView(cs, isDark)
                      : _buildListView(cs, isDark),
                ),
              ],
            ),
    );
  }

  // ── 1. 列表模式 ──
  Widget _buildListView(ColorScheme cs, bool isDark) {
    final list = _filteredStories;

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_stories_rounded, size: 60, color: Color(0xFFF97316)),
            const SizedBox(height: 16),
            Text(
              '目前此分類尚無故事',
              style: GoogleFonts.notoSansTc(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '點擊右上角「委託提問」，讓小豬今天就問長輩吧！',
              style: GoogleFonts.notoSansTc(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: list.length,
      itemBuilder: (ctx, index) {
        final story = list[index];
        return _buildStoryCard(story, cs, isDark, index);
      },
    );
  }

  Widget _buildStoryCard(MemoirStory story, ColorScheme cs, bool isDark, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cs.outline.withValues(alpha: isDark ? 0.3 : 0.6),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.outline.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => MemoirDetailSheet.show(
          context,
          story: story,
          elderName: widget.elderName,
          familyUserName: widget.familyUserName,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 頂部標籤與珍藏
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF97316).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF97316).withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      story.tag,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFEA580C),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('yyyy/MM/dd').format(story.recordedDate),
                    style: GoogleFonts.notoSansTc(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      story.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: story.isFavorite ? const Color(0xFFEF4444) : cs.onSurfaceVariant,
                      size: 20,
                    ),
                    onPressed: () => _service.toggleFavorite(widget.elderId, story.id),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // 標題
              Text(
                story.title,
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),

              const SizedBox(height: 6),

              // 預覽文字
              Text(
                story.preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansTc(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 12),

              // 底部工具列：小豬提問與留言數
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.volume_up_rounded, size: 14, color: Color(0xFF3B82F6)),
                        const SizedBox(width: 4),
                        Text(
                          '原聲錄音',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF3B82F6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (story.familyNotes.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.tertiary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Color(0xFF10B981)),
                          const SizedBox(width: 4),
                          Text(
                            '${story.familyNotes.length} 則留言',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  Text(
                    '閱讀全文 >',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFF97316),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: (index * 60).ms, duration: 250.ms);
  }

  // ── 2. 繪本翻頁自傳書模式 (Storybook Mode) ──
  Widget _buildStorybookView(ColorScheme cs, bool isDark) {
    if (_stories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_stories_rounded, size: 60, color: Color(0xFFF97316)),
            const SizedBox(height: 16),
            Text(
              '目前尚無故事回憶',
              style: GoogleFonts.notoSansTc(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '點擊右上角「委託提問」，讓小豬今天就問長輩吧！',
              style: GoogleFonts.notoSansTc(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 頁碼提示
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            '第 ${_currentBookPage + 1} / ${_stories.length} 章',
            style: GoogleFonts.notoSansTc(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFF97316),
            ),
          ),
        ),

        // 翻頁書主體卡片
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _stories.length,
            onPageChanged: (i) => setState(() => _currentBookPage = i),
            physics: const BouncingScrollPhysics(),
            itemBuilder: (ctx, index) {
              final story = _stories[index];
              return Container(
                margin: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A222D) : const Color(0xFFFFFDF8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFFD97706).withValues(alpha: 0.3),
                    width: 2.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 頂部留聲機插畫與章節標籤
                      Center(
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.asset(
                                'assets/images/memoir_card.png',
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF97316).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                story.tag,
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFEA580C),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 故事標題
                      Center(
                        child: Text(
                          story.title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // 引導提問引文框
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF222D3D) : const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFF97316).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          '🐷 小豬：「${story.promptQuestion}」',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFD97706),
                            height: 1.4,
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // 口述全文
                      Text(
                        story.fullStory,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 16,
                          height: 1.8,
                          color: cs.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 24),

                      // 底部原聲試聽按鈕
                      Center(
                        child: OutlinedButton.icon(
                          onPressed: () => MemoirDetailSheet.show(
                            context,
                            story: story,
                            elderName: widget.elderName,
                            familyUserName: widget.familyUserName,
                          ),
                          icon: const Icon(Icons.headphones_rounded, color: Color(0xFF3B82F6)),
                          label: Text(
                            '聆聽長輩口述原聲 & 留言',
                            style: GoogleFonts.notoSansTc(
                              color: const Color(0xFF3B82F6),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF3B82F6), width: 1.2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
