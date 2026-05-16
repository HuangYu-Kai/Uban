import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';

class NewsListenPlayerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> newsItems;
  final int initialIndex;
  final int userId; // 新增 userId

  const NewsListenPlayerScreen({
    super.key,
    required this.newsItems,
    required this.initialIndex,
    required this.userId,
  });

  @override
  State<NewsListenPlayerScreen> createState() => _NewsListenPlayerScreenState();
}

class _NewsListenPlayerScreenState extends State<NewsListenPlayerScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Random _random = Random();
  late int _currentIndex;
  bool _isLoadingAudio = false;
  bool _isPlaying = false;
  String? _error;
  Timer? _waveTimer;
  List<double> _waveHeights = List<double>.filled(11, 40);

  // AI 總結相關
  bool _isSummarizing = false;
  String _summaryText = "";
  bool _isAiThinking = false;
  final AudioPlayer _aiAudioPlayer = AudioPlayer();

  // 字幕相關
  List<dynamic> _subtitles = [];
  String _currentSubtitle = '';
  int _currentSubtitleIndex = -1;
  double _subtitleProgress = 0.0;
  StreamSubscription? _positionSubscription;
  final ScrollController _subtitleScrollController = ScrollController();
  List<GlobalKey> _subtitleKeys = []; // 為每一句字幕準備身分證

  late List<Map<String, dynamic>> _localNewsItems;
  String _selectedCategory = '全部';
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _subtitleScrollController.dispose();
    _audioPlayer.dispose();
    _aiAudioPlayer.dispose();
    _waveTimer?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _localNewsItems = List.from(widget.newsItems);
    _currentIndex =
        widget.initialIndex.clamp(0, max(_localNewsItems.length - 1, 0));
    _scrollController.addListener(_onScroll);

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      final playing = state == PlayerState.playing;
      setState(() => _isPlaying = playing);
      if (playing) {
        _startWaveAnimation();
      } else {
        _stopWaveAnimation();
      }
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
          _currentSubtitle = _subtitles[matchedIndex]['text'] as String;
          _subtitleProgress = progress.clamp(0.0, 1.0);
        });
        _scrollToSubtitle(matchedIndex);
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

  void _scrollToSubtitle(int index) {
    if (index < 0 || index >= _subtitleKeys.length) return;
    final key = _subtitleKeys[index];

    // 延遲一下下，確保 UI 已經畫好
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (key.currentContext != null && _subtitleScrollController.hasClients) {
        try {
          final RenderBox box =
              key.currentContext!.findRenderObject() as RenderBox;
          final RenderBox container = _subtitleScrollController
              .position.context.storageContext
              .findRenderObject() as RenderBox;
          final Offset relativeOffset =
              box.localToGlobal(Offset.zero, ancestor: container);

          // 計算目標位置：讓該 Widget 的頂部 + 自身高度的一半 = 容器的一半
          final double targetOffset = _subtitleScrollController.offset +
              relativeOffset.dy -
              (container.size.height / 2) +
              (box.size.height / 2);

          // 使用 jumpTo 瞬間跳轉，不產生任何動畫，也不會干擾外層 PageView
          _subtitleScrollController.jumpTo(
            targetOffset.clamp(
                0.0, _subtitleScrollController.position.maxScrollExtent),
          );
        } catch (e) {
          debugPrint('❌ 瞬間捲動失敗: $e');
        }
      }
    });
  }

  void _onScroll() {
    if (!mounted) return;
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore) {
      _loadMoreNews();
    }
  }

  Future<void> _loadMoreNews() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    try {
      debugPrint('🔄 正在載入更多新聞... 類別: $_selectedCategory');
      // 依據目前選中的類別抓取更多，'全部' 則不帶類別過濾
      final apiCategory = _selectedCategory == '全部' ? '' : _selectedCategory;
      final response =
          await ApiService.getNews(category: apiCategory, limit: 10);

      if (response['status'] == 'success') {
        final newItems =
            List<Map<String, dynamic>>.from(response['data'] ?? []);
        if (newItems.isNotEmpty) {
          setState(() {
            // 避免加入重複標題的新聞
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
        // Direct stream from pre-generated URL
        final String fullUrl = "https://localhost-0.tail5abf5e.ts.net$audioUrl";
        await _audioPlayer.stop();
        await _audioPlayer.play(UrlSource(fullUrl));

        if (!mounted) return;
        if (!mounted) return;
        setState(() {
          _subtitles = (item['subtitles'] is List) ? item['subtitles'] : [];
          _subtitleKeys =
              List.generate(_subtitles.length, (index) => GlobalKey());
          _currentSubtitle = "";
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
      if (!mounted) return;
      setState(() {
        _subtitles = (subs is List) ? subs : [];
        _subtitleKeys =
            List.generate(_subtitles.length, (index) => GlobalKey());
        _currentSubtitle = "";
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
    // Safe Base64 decoding
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
      _subtitles = [];
      _currentSubtitle = "";
    });
    await _playCurrentNews();
  }

  Future<void> _handleNewsComplete() async {
    debugPrint('DEBUG: _handleNewsComplete called (index: $_currentIndex)');
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _currentSubtitle = "";
    });
    _stopWaveAnimation();
    
    // 播放結束後不自動觸發任何行為，等待使用者操作或點擊小豬總結
  }

  Future<void> _showNewsSummary() async {
    if (_isAiThinking) return;

    // 暫停新聞播放
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

      // 呼叫 AI 獲取新聞總結
      final response = await ApiService.petGreeting(
        widget.userId,
        "請針對這則新聞：『$title』\n內容：$content\n請以貼心小豬的身分，用『簡單白話』為長輩整理 3 個最重要的重點，總字數請控制在 60 字以內。"
      );

      if (!mounted) return;

      if (response['status'] == 'success') {
        final reply = response['reply'] ?? "抱歉，小豬沒辦法總結這則新聞。";
        
        setState(() {
          _summaryText = reply;
          _isAiThinking = false;
        });

        // 呼叫 TTS
        final ttsResponse = await ApiService.synthesizeTts(text: reply);
        if (ttsResponse['status'] == 'success' && ttsResponse['data'] != null) {
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
            child: AlertDialog(
              backgroundColor: Colors.white.withValues(alpha: 0.95),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/images/pig_summary_expert.png',
                        width: 70,
                        height: 70,
                      ).animate(onPlay: (controller) => controller.repeat())
                       .shimmer(duration: 2.seconds)
                       .scale(begin: const Offset(1, 1), end: const Offset(1.1, 1.1), duration: 1.seconds, curve: Curves.easeInOut),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Text(
                          '總結專家小豬',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF59B294),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 30),
                  Text(
                    _summaryText,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 22,
                      height: 1.6,
                      color: Colors.black87,
                    ),
                  ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0),
                  const SizedBox(height: 25),
                  ElevatedButton(
                    onPressed: () {
                      _aiAudioPlayer.stop();
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF59B294),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 0,
                    ),
                    child: const Text('我知道了', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _startWaveAnimation() {
    _waveTimer?.cancel();
    _waveTimer = Timer.periodic(const Duration(milliseconds: 280), (_) {
      if (!mounted || !_isPlaying) return;
      setState(() {
        _waveHeights = List<double>.generate(11, (i) {
          final base = 28 + (i.isOdd ? 8 : 0);
          return base + _random.nextInt(50).toDouble();
        });
      });
    });
  }

  void _stopWaveAnimation() {
    _waveTimer?.cancel();
    _waveTimer = null;
    if (!mounted) return;
    setState(() {
      _waveHeights = List<double>.filled(11, 34);
    });
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

  @override
  Widget build(BuildContext context) {
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
          child: PageView(
            scrollDirection: Axis.vertical,
            children: [
              Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: Colors.white, size: 26),
                          ),
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
                        // 字幕顯示區域 (全文本動態捲動)
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(vertical: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  width: 1),
                            ),
                            child: _subtitles.isEmpty
                                ? const Center(
                                    child: Text(
                                      '準備播放中...',
                                      style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 30,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  )
                                : SingleChildScrollView(
                                    controller: _subtitleScrollController,
                                    physics: const BouncingScrollPhysics(),
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 100),
                                    child: Column(
                                      children:
                                          List.generate(_subtitles.length, (index) {
                                        final isCurrent =
                                            index == _currentSubtitleIndex;
                                        final text =
                                            _subtitles[index]['text'] as String;

                                        return AnimatedOpacity(
                                          key: _subtitleKeys[index], // 給予身分證
                                          duration:
                                              const Duration(milliseconds: 200),
                                          opacity: isCurrent ? 1.0 : 0.4,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 4),
                                            child: RichText(
                                              textAlign: TextAlign.center,
                                              text: TextSpan(
                                                style: TextStyle(
                                                  fontSize: isCurrent
                                                      ? 30
                                                      : 22, // 稍微調大一點點，平衡置中感
                                                  fontWeight: isCurrent
                                                      ? FontWeight.w900
                                                      : FontWeight.w600,
                                                  height: 1.4,
                                                ),
                                                children: [
                                                  if (isCurrent) ...[
                                                    TextSpan(
                                                      text: text.substring(
                                                          0,
                                                          (text.length *
                                                                  _subtitleProgress)
                                                              .round()
                                                              .clamp(
                                                                  0, text.length)),
                                                      style: const TextStyle(
                                                          color: Color(0xFFFFD700)),
                                                    ),
                                                    TextSpan(
                                                      text: text.substring((text
                                                                  .length *
                                                              _subtitleProgress)
                                                          .round()
                                                          .clamp(0, text.length)),
                                                      style: const TextStyle(
                                                          color: Colors.white),
                                                    ),
                                                  ] else ...[
                                                    TextSpan(
                                                        text: text,
                                                        style: TextStyle(
                                                            color: Colors.white
                                                                .withValues(
                                                                    alpha: 0.4))),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text('向上滑查看更多新聞',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 18,
                                fontWeight: FontWeight.w600)),
                        const Icon(Icons.keyboard_arrow_up_rounded,
                            color: Colors.white70, size: 32),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                  // 右下角的小豬總結按鈕
                  Positioned(
                    right: 10,
                    top: 100,
                    child: GestureDetector(
                      onTap: _showNewsSummary,
                      child: Hero(
                        tag: 'pig_mascot',
                        child: Image.asset(
                          'assets/images/pig_summary_expert.png',
                          width: 80,
                          height: 80,
                        ),
                      ).animate(
                        target: _isAiThinking ? 1 : 0,
                        onPlay: (controller) => controller.repeat(),
                      ).shake(hz: 3, curve: Curves.easeInOut)
                       .scale(begin: const Offset(1, 1), end: const Offset(1.1, 1.1), duration: 1.seconds),
                    ),
                  ),
                ],
              ),
              // 第二頁：新聞清單 (瀏覽模式)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                            color: Colors.white54,
                            borderRadius: BorderRadius.circular(10))),
                    const SizedBox(height: 20),
                    const Text('新聞清單',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    _buildCategorySelector(),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: [
                            _buildNewsSelectionList(),
                            if (_isLoadingMore)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 30),
                                child: CircularProgressIndicator(
                                    color: Color(0xFFFFD700)),
                              ),
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
              SizedBox(
                height: 60, // 縮小高度
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(_waveHeights.length, (i) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      width: 8,
                      height: _waveHeights[i] * 0.6, // 同步縮小波形
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    );
                  }),
                ),
              ),
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

  Widget _buildCategorySelector() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      height: 60, // 加高到 60 確保大字體不溢位
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: _categories.map((category) {
            final isSelected = _selectedCategory == category;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedCategory = category;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFFD700).withValues(alpha: 0.95)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFFD700)
                          : Colors.white.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                                color: const Color(0xFFFFD700)
                                    .withValues(alpha: 0.25),
                                blurRadius: 12,
                                spreadRadius: 1)
                          ]
                        : [],
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      color: isSelected
                          ? const Color(0xFF1E293B)
                          : Colors.white.withValues(alpha: 0.9),
                      fontSize: 17,
                      fontWeight:
                          isSelected ? FontWeight.w900 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildNewsSelectionList() {
    final filteredItems = _selectedCategory == '全部'
        ? widget.newsItems
        : widget.newsItems
            .where((item) => (item['category'] ?? '') == _selectedCategory)
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
        final originalIndex = widget.newsItems.indexOf(item);
        final isCurrent = originalIndex == _currentIndex;
        final title = (item['title'] ?? '').toString();
        final source = (item['category'] ?? '新聞').toString();
        final date = _formatNewsDate(item);
        final imageUrl =
            ((item['image_url'] ?? item['image']) ?? '').toString().trim();
        final hasImage = imageUrl.startsWith('http');

        return Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: GestureDetector(
            onTap: () => _selectTrack(originalIndex),
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
                            style: TextStyle(
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
