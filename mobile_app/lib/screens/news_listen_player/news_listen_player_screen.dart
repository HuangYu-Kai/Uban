import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../services/api_service.dart';
import 'widgets/news_card_list.dart';
import 'widgets/news_category_selector.dart';
import 'widgets/news_sound_wave_indicator.dart';
import 'widgets/news_subtitle_viewer.dart';
import 'widgets/news_summary_dialog.dart';

class NewsListenPlayerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> newsItems;
  final int initialIndex;
  final int userId;

  const NewsListenPlayerScreen({
    super.key,
    required this.newsItems,
    required this.initialIndex,
    required this.userId,
  });

  @override
  State<NewsListenPlayerScreen> createState() => _NewsListenPlayerScreenState();
}

class _NewsListenPlayerScreenState extends State<NewsListenPlayerScreen>
    with TickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  late int _currentIndex;
  bool _isLoadingAudio = false;
  bool _isPlaying = false;
  String? _error;

  // AI 總結相關
  String _summaryText = "";
  bool _isAiThinking = false;
  final AudioPlayer _aiAudioPlayer = AudioPlayer();

  // 字幕相關
  List<dynamic> _subtitles = [];
  int _currentSubtitleIndex = -1;
  double _subtitleProgress = 0.0;
  StreamSubscription? _positionSubscription;

  late List<Map<String, dynamic>> _localNewsItems;
  String _selectedCategory = '全部';
  final ScrollController _newsScrollController = ScrollController();
  bool _isLoadingMore = false;

  // 自定義滑動面板相關
  late AnimationController _panelController;
  late Animation<double> _panelAnimation;
  bool _isSheetExpanded = false;

  // 小豬對話框縮放動畫
  late Animation<double> _pigScaleAnim;

  @override
  void dispose() {
    _newsScrollController.dispose();
    _audioPlayer.dispose();
    _aiAudioPlayer.dispose();
    _positionSubscription?.cancel();
    _panelController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _localNewsItems = List.from(widget.newsItems);
    _currentIndex =
        widget.initialIndex.clamp(0, max(_localNewsItems.length - 1, 0));
    _newsScrollController.addListener(_onNewsScroll);

    // 面板動畫控制器
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _panelAnimation = CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    // 小豬在面板接近展開時（最後 35% 行程）以彈性效果縮放出現
    _pigScaleAnim = CurvedAnimation(
      parent: _panelController,
      curve: const Interval(0.65, 1.0, curve: Curves.elasticOut),
    );

    // 監聽面板狀態變更
    _panelController.addListener(() {
      if (!mounted) return;
      final expanded = _panelController.value > 0.5;
      if (expanded != _isSheetExpanded) {
        setState(() {
          _isSheetExpanded = expanded;
        });
      }
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      final playing = state == PlayerState.playing;
      setState(() => _isPlaying = playing);
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      _handleNewsComplete();
    });

    // 監聽播放進度以同步字幕
    _positionSubscription = _audioPlayer.onPositionChanged.listen((position) {
      if (!mounted || _subtitles.isEmpty) return;

      final ms = position.inMilliseconds;
      int matchedIndex = -1;
      double progress = 0.0;

      for (int i = 0; i < _subtitles.length; i++) {
        final sub = _subtitles[i];
        final start = sub['start_ms'] as int;
        final duration = sub['duration_ms'] as int;
        if (ms >= start && ms < (start + duration)) {
          matchedIndex = i;
          progress = (ms - start) / (duration > 0 ? duration : 1);
          break;
        }
      }

      if (matchedIndex != -1 && matchedIndex != _currentSubtitleIndex) {
        debugPrint(
            '🎯 切換字幕至第 $matchedIndex 句: ${_subtitles[matchedIndex]['text']}');
        setState(() {
          _currentSubtitleIndex = matchedIndex;
          _subtitleProgress = progress.clamp(0.0, 1.0);
        });
      } else if (matchedIndex != -1) {
        setState(() {
          _subtitleProgress = progress.clamp(0.0, 1.0);
        });
      }
    });

    if (widget.newsItems.isNotEmpty) {
      _playCurrentNews();
    }
  }

  void _expandPanel() {
    _panelController.forward();
  }

  void _collapsePanel() {
    _panelController.animateTo(0.0, curve: Curves.easeOut);
  }

  void _onNewsScroll() {
    if (!mounted) return;
    if (_newsScrollController.position.pixels >=
            _newsScrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore) {
      _loadMoreNews();
    }
  }

  Future<void> _loadMoreNews() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    try {
      debugPrint('🔄 正在載入更多新聞... 類別: $_selectedCategory');
      final apiCategory = _selectedCategory == '全部' ? '' : _selectedCategory;
      final response =
          await ApiService.getNews(category: apiCategory, limit: 10);

      if (response['status'] == 'success') {
        final newItems =
            List<Map<String, dynamic>>.from(response['data'] ?? []);
        if (newItems.isNotEmpty) {
          setState(() {
            final existingTitles =
                _localNewsItems.map((i) => i['title'] as String).toSet();
            final uniqueNewItems = newItems
                .where((i) => !existingTitles.contains(i['title']))
                .toList();
            _localNewsItems.addAll(uniqueNewItems);
            debugPrint('✅ 載入完成，新增了 ${uniqueNewItems.length} 則新聞');
          });
        }
      }
    } catch (e) {
      debugPrint('❌ 載入更多失敗: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _playCurrentNews() async {
    if (_localNewsItems.isEmpty) return;
    final item = _localNewsItems[_currentIndex];

    setState(() {
      _isLoadingAudio = true;
      _error = null;
    });

    try {
      final String? audioUrl = item['audio_url'];
      if (audioUrl != null && audioUrl.isNotEmpty) {
        final String fullUrl =
            "https://localhost-0.tail5abf5e.ts.net$audioUrl";
        await _audioPlayer.stop();
        await _audioPlayer.play(UrlSource(fullUrl));

        if (!mounted) return;
        setState(() {
          _subtitles = (item['subtitles'] is List) ? item['subtitles'] : [];
          _currentSubtitleIndex = -1;
          _isLoadingAudio = false;
          _isPlaying = true;
        });
        return;
      }

      // Fallback: Live Synthesis
      final speechText = _composeSpeechText(item);
      final response = await ApiService.synthesizeTts(text: speechText);
      if (response['status'] != 'success') {
        final detail =
            response['detail'] ?? response['message'] ?? response['error'];
        throw Exception(detail ?? 'TTS 合成失敗');
      }
      final audioBase64 = (response['audio_base64'] ?? '').toString();
      if (audioBase64.isEmpty) {
        throw Exception('語音資料為空');
      }

      final subs = response['subtitles'];
      String payload = _extractBase64Payload(audioBase64);
      final audioBytes = base64Decode(payload);

      await _audioPlayer.stop();
      await _audioPlayer.play(BytesSource(audioBytes));

      if (!mounted) return;
      setState(() {
        _subtitles = (subs is List) ? subs : [];
        _currentSubtitleIndex = -1;
        _isLoadingAudio = false;
        _isPlaying = true;
      });
    } catch (e) {
      debugPrint('NewsListenPlayer TTS error: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingAudio = false;
        _isPlaying = false;
        _error = '語音播放失敗，請點播放再試一次';
      });
    }
  }

  String _extractBase64Payload(String raw) {
    String text = raw.trim();
    if (text.startsWith('data:')) {
      final commaIndex = text.indexOf(',');
      if (commaIndex >= 0 && commaIndex < text.length - 1) {
        text = text.substring(commaIndex + 1);
      }
    }
    text = text.replaceAll(RegExp(r'\s+'), '');
    final missingPadding = text.length % 4;
    if (missingPadding > 0) {
      text += '=' * (4 - missingPadding);
    }
    return text;
  }

  Future<void> _togglePlayPause() async {
    if (_isLoadingAudio) return;
    if (_isPlaying) {
      await _audioPlayer.pause();
      return;
    }
    if (_error != null) {
      await _playCurrentNews();
      return;
    }
    await _audioPlayer.resume();
  }

  Future<void> _changeTrack(int delta) async {
    if (widget.newsItems.isEmpty) return;
    final len = widget.newsItems.length;
    final nextIndex = (_currentIndex + delta + len) % len;
    _selectTrack(nextIndex);
  }

  Future<void> _selectTrack(int index) async {
    if (widget.newsItems.isEmpty) return;
    setState(() {
      _currentIndex = index;
      _error = null;
      _currentSubtitleIndex = -1;
    });
    await _playCurrentNews();
  }

  Future<void> _handleNewsComplete() async {
    debugPrint('DEBUG: _handleNewsComplete called (index: $_currentIndex)');
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
    });
  }

  Future<void> _showNewsSummary() async {
    if (_isAiThinking) return;

    if (_isPlaying) {
      _togglePlayPause();
    }

    setState(() {
      _isAiThinking = true;
      _summaryText = "小豬正在幫您整理重點...";
    });

    try {
      final currentNews = _localNewsItems[_currentIndex];
      final title = currentNews['title'] ?? "這則新聞";
      final content = currentNews['content'] ?? "";

      final response = await ApiService.petGreeting(widget.userId,
          "請針對這則新聞：『$title』\n內容：$content\n請以貼心小豬的身分，用『簡單白話』為長輩整理 3 個最重要的重點，總字數請控制在 60 字以內。");

      if (!mounted) return;

      if (response['status'] == 'success') {
        final reply = response['reply'] ?? "抱歉，小豬沒辦法總結這則新聞。";

        setState(() {
          _summaryText = reply;
          _isAiThinking = false;
        });

        // 呼叫 TTS
        final ttsResponse = await ApiService.synthesizeTts(text: reply);
        if (ttsResponse['status'] == 'success' &&
            ttsResponse['data'] != null) {
          final audioUrl = ttsResponse['data']['url'];
          if (audioUrl != null) {
            await _aiAudioPlayer.play(UrlSource(audioUrl));
          }
        }

        _showSummaryDialog();
      } else {
        throw Exception(response['message'] ?? "Unknown error");
      }
    } catch (e) {
      debugPrint('DEBUG: Summary error: $e');
      setState(() => _isAiThinking = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('小豬現在有點累，請稍後再試')),
        );
      }
    }
  }

  void _showSummaryDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Summary",
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) => const SizedBox(),
      transitionBuilder: (context, anim1, anim2, child) {
        return Transform.scale(
          scale: anim1.value,
          child: Opacity(
            opacity: anim1.value,
            child: NewsSummaryDialog(
              summaryText: _summaryText,
              onClose: () {
                _aiAudioPlayer.stop();
                Navigator.of(context).pop();
              },
            ),
          ),
        );
      },
    );
  }

  String _composeSpeechText(Map<String, dynamic> item) {
    final category = (item['category'] ?? '').toString().trim();
    final title = (item['title'] ?? '').toString().trim();
    final content = (item['content'] ?? '').toString().trim();
    final header = category.isNotEmpty ? '[$category] $title' : title;
    if (content.isEmpty) return header;
    final clipped =
        content.length > 180 ? '${content.substring(0, 180)}。' : content;
    return '$header。$clipped';
  }

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

  List<String> get _categories {
    final Set<String> categories = {'全部'};
    for (var item in _localNewsItems) {
      final cat = (item['category'] ?? '').toString().trim();
      if (cat.isNotEmpty) categories.add(cat);
    }
    return categories.toList();
  }

  /// 取得當前新聞標題（給小豬對話框用）
  String get _currentNewsTitle {
    if (_localNewsItems.isEmpty) return '';
    final item = _localNewsItems[_currentIndex];
    return (item['title'] ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double panelHeight = screenHeight * 0.72;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8BAF88), Color(0xFF56B59F)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // 底層：聆聽介面，支持手勢交互
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: (details) {
                  final delta = details.primaryDelta;
                  if (delta == null) return;
                  
                  // Dragging UP (negative delta) pulls panel UP (increases animation value)
                  // Dragging DOWN (positive delta) pulls panel DOWN (decreases animation value)
                  _panelController.value =
                      (_panelController.value - delta / panelHeight).clamp(0.0, 1.0);
                },
                onVerticalDragEnd: (details) {
                  final velocity = details.primaryVelocity;
                  if (!_isSheetExpanded) {
                    if (velocity != null && velocity < -300) {
                      _expandPanel();
                      return;
                    }
                    if (_panelController.value > 0.2) {
                      _expandPanel();
                    } else {
                      _collapsePanel();
                    }
                  } else {
                    if (velocity != null && velocity > 300) {
                      _collapsePanel();
                      return;
                    }
                    if (_panelController.value < 0.8) {
                      _collapsePanel();
                    } else {
                      _expandPanel();
                    }
                  }
                },
                child: _buildListeningView(),
              ),

              // 上層：白色面板（自定義 Positioned）
              _buildCustomWhitePanel(panelHeight),

              // 小豬 + 對話框（跟隨面板同步升降與彈性縮放）
              _buildPigMascot(panelHeight),
            ],
          ),
        ),
      ),
    );
  }

  /// 聆聽介面（底層）
  Widget _buildListeningView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      child: Column(
        children: [
          // 返回 + 小豬總結按鈕（聆聽模式下）
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 26),
              ),
              if (!_isSheetExpanded)
                GestureDetector(
                  onTap: _showNewsSummary,
                  child: Hero(
                    tag: 'pig_mascot',
                    child: Image.asset(
                      'assets/images/pig_summary_expert.png',
                      width: 65,
                      height: 65,
                    ),
                  )
                      .animate(
                        target: _isAiThinking ? 1 : 0,
                        onPlay: (controller) => controller.repeat(),
                      )
                      .shake(hz: 3, curve: Curves.easeInOut)
                      .scale(
                          begin: const Offset(1, 1),
                          end: const Offset(1.1, 1.1),
                          duration: 1.seconds),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '代誌\n報給你知',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'StarPanda',
              fontSize: 48,
              height: 1.1,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          _buildPlayerHeader(),
          const SizedBox(height: 15),
          // 字幕顯示區域
          Expanded(
            child: NewsSubtitleViewer(
              subtitles: _subtitles,
              currentSubtitleIndex: _currentSubtitleIndex,
              subtitleProgress: _subtitleProgress,
            ),
          ),
          const SizedBox(height: 10),
          // 提示文字（與第二張圖一致：往下滑查看更多 + 向下箭頭 V）
          AnimatedOpacity(
            opacity: _isSheetExpanded ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: _isSheetExpanded,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _expandPanel,
                child: const Column(
                  children: [
                    Text('往下滑查看更多新聞',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white70, size: 32),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  /// 自定義白色面板（動畫包裹定位，高度固定 72% 防止溢出）
  Widget _buildCustomWhitePanel(double panelHeight) {
    return AnimatedBuilder(
      animation: _panelAnimation,
      builder: (context, child) {
        final bottomOffset = -panelHeight + (panelHeight * _panelAnimation.value);
        return Positioned(
          left: 0,
          right: 0,
          bottom: bottomOffset,
          height: panelHeight,
          child: child!,
        );
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Color(0x30000000),
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          children: [
            // 拖拽指示條/交界處手柄 (點擊或拖動皆可收回)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                final delta = details.primaryDelta;
                if (delta == null) return;
                _panelController.value =
                    (_panelController.value - delta / panelHeight).clamp(0.0, 1.0);
              },
              onVerticalDragEnd: (details) {
                final velocity = details.primaryVelocity;
                if (velocity != null) {
                  if (velocity > 300) {
                    _collapsePanel();
                    return;
                  } else if (velocity < -300) {
                    _expandPanel();
                    return;
                  }
                }
                if (_panelController.value > 0.4) {
                  _expandPanel();
                } else {
                  _collapsePanel();
                }
              },
              onTap: _collapsePanel,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 14, bottom: 14),
                color: Colors.transparent,
                child: Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
            // 分類選擇器
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: NewsCategorySelector(
                categories: _categories,
                selectedCategory: _selectedCategory,
                onWhiteBackground: true,
                onCategorySelected: (category) {
                  setState(() {
                    _selectedCategory = category;
                  });
                },
              ),
            ),
            // 新聞列表 (使用 BouncingScrollPhysics 帶來更流暢的滑動感受)
            Expanded(
              child: ListView(
                controller: _newsScrollController,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                children: [
                  NewsCardList(
                    newsItems: _localNewsItems,
                    currentIndex: _currentIndex,
                    selectedCategory: _selectedCategory,
                    userId: widget.userId,
                    onSelectTrack: _selectTrack,
                  ),
                  if (_isLoadingMore)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF59B294),
                        ),
                      ),
                    ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 小豬吉祥物 + 對話框（跟隨面板同步升降與彈性縮放）
  Widget _buildPigMascot(double panelHeight) {
    final currentTitle = _currentNewsTitle;
    final displayText = currentTitle.length > 20
        ? '${currentTitle.substring(0, 20)}...'
        : currentTitle;

    return AnimatedBuilder(
      animation: _panelAnimation,
      builder: (context, child) {
        if (_panelAnimation.value < 0.1) return const SizedBox.shrink();

        // 精準跟隨白色面板的頂部邊緣升降
        final bottomPosition = panelHeight * _panelAnimation.value - 10.0;

        return Positioned(
          right: 10,
          bottom: bottomPosition,
          child: ScaleTransition(
            scale: _pigScaleAnim,
            alignment: Alignment.bottomRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 對話框
                if (currentTitle.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxWidth: 180),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '正在唸：',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 6),
                // 小豬圖片
                GestureDetector(
                  onTap: _showNewsSummary,
                  child: Image.asset(
                    'assets/images/pig_summary_expert.png',
                    width: 60,
                    height: 60,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayerHeader() {
    final item = _localNewsItems.isEmpty
        ? const <String, dynamic>{}
        : _localNewsItems[_currentIndex];
    final title = (item['title'] ?? '新聞朗讀').toString();
    final source = (item['category'] ?? '新聞').toString();
    final publishedDate = _formatNewsDate(item);
    final totalCount = max(_localNewsItems.length, 1);
    final currentCount = _localNewsItems.isEmpty ? 0 : (_currentIndex + 1);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              const Text(
                '正在播放：',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 33,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '第 $currentCount / $totalCount 則 · $source · $publishedDate',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w600,
                    height: 1.3),
              ),
              const SizedBox(height: 18),
              // 音波波動畫 (已模組化)
              NewsSoundWaveIndicator(isPlaying: _isPlaying),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildRoundControl(
              key: const ValueKey('prev_button'),
              tooltip: '上一則',
              icon: Icons.fast_rewind_rounded,
              onTap: () => _changeTrack(-1),
            ),
            const SizedBox(width: 42),
            _isLoadingAudio
                ? const SizedBox(
                    width: 58,
                    height: 58,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 3),
                  )
                : _buildRoundControl(
                    key: const ValueKey('play_pause_button'),
                    tooltip: _isPlaying ? '暫停' : '播放',
                    icon: _isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    onTap: _togglePlayPause,
                    big: true,
                  ),
            const SizedBox(width: 42),
            _buildRoundControl(
              key: const ValueKey('next_button'),
              tooltip: '下一則',
              icon: Icons.fast_forward_rounded,
              onTap: () => _changeTrack(1),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRoundControl({
    required IconData icon,
    required VoidCallback onTap,
    bool big = false,
    Key? key,
    String? tooltip,
  }) {
    final size = big ? 74.0 : 60.0;
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: const Color(0xFF59B294),
            size: big ? 42 : 30,
          ),
        ),
      ),
    );
  }
}
