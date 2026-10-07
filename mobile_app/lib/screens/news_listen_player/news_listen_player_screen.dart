import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../globals.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/ui.dart';
import 'widgets/news_card_list.dart';
import 'widgets/news_category_selector.dart';
import 'widgets/news_sound_wave_indicator.dart';
import 'widgets/news_subtitle_viewer.dart';
import 'widgets/news_summary_dialog.dart';

class NewsListenPlayerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> newsItems;
  final int initialIndex;
  final int userId;

  /// 進場時是否自動展開新聞列表面板（給「看更多新聞」用；一般聆聽為 false）。
  final bool startExpanded;

  const NewsListenPlayerScreen({
    super.key,
    required this.newsItems,
    required this.initialIndex,
    required this.userId,
    this.startExpanded = false,
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

  /// ★ 2026-10-07 喚醒詞修正：是否由本畫面把 isMediaPlayingNotifier 設成 true。
  bool _setMediaFlag = false;

  @override
  void dispose() {
    // ★ 2026-10-07 喚醒詞修正：新聞播放中直接離開本頁時，播放器停止的回呼會被
    //   下方 `if (!mounted) return` 擋掉，旗標永遠卡在 true，首頁「嘿嘎蛙」喚醒詞
    //   就一直被暫停到 App 重開。離開時若旗標是本頁設的，必須還原。
    if (_setMediaFlag) {
      _setMediaFlag = false;
      isMediaPlayingNotifier.value = false;
    }
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
    try {
      final audioCtx = AudioContext(
        android: const AudioContextAndroid(
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.none,
        ),
      );
      _audioPlayer.setAudioContext(audioCtx);
      _aiAudioPlayer.setAudioContext(audioCtx);
    } catch (_) {}
    _localNewsItems = List.from(widget.newsItems);
    _currentIndex =
        widget.initialIndex.clamp(0, max(_localNewsItems.length - 1, 0));
    _newsScrollController.addListener(_onNewsScroll);

    // 「看更多新聞」進來時，進場後自動展開新聞列表面板（用既有滑動動畫）。
    if (widget.startExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _panelController.forward();
      });
    }

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

    // 監聽面板狀態變更，調用 setState 確保 Positioned 與動畫數值更新同步
    _panelController.addListener(() {
      if (!mounted) return;
      setState(() {
        _isSheetExpanded = _panelController.value > 0.5;
      });
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      final playing = state == PlayerState.playing;
      isMediaPlayingNotifier.value = playing;
      _setMediaFlag = playing;
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

  Future<void> _refreshNews() async {
    try {
      debugPrint('🔄 正在重新整理最新新聞... 類別: $_selectedCategory');
      final apiCategory = _selectedCategory == '全部' ? '' : _selectedCategory;
      final response =
          await ApiService.getNews(category: apiCategory, limit: 15); // 載入最新的 15 則

      if (response['status'] == 'success') {
        final newItems =
            List<Map<String, dynamic>>.from(response['data'] ?? []);
        if (newItems.isNotEmpty) {
          setState(() {
            // 用最新載入的新聞更新/取代，以確保最新新聞排在最前，並過濾掉重複項
            final existingTitles = newItems.map((i) => i['title'] as String).toSet();
            final oldUniqueItems = _localNewsItems
                .where((i) => !existingTitles.contains(i['title']))
                .toList();
            
            // 重新組裝：最新新聞放在最前
            _localNewsItems = [...newItems, ...oldUniqueItems];
            
            // 為了不讓當前正在播放的索引錯亂，需要重新定位當前正在播放新聞的索引
            if (widget.newsItems.isNotEmpty && _currentIndex >= 0 && _currentIndex < widget.newsItems.length) {
              final currentNews = widget.newsItems[_currentIndex];
              final currentTitle = currentNews['title'] as String;
              final newIndex = _localNewsItems.indexWhere((i) => (i['title'] as String) == currentTitle);
              if (newIndex >= 0) {
                _currentIndex = newIndex;
              }
            }
            debugPrint('✅ 整理完成，目前共有 ${_localNewsItems.length} 則新聞');
          });
        }
      }
    } catch (e) {
      debugPrint('❌ 重新整理失敗: $e');
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
        // ⚠️ 不可寫死正式站網址（鐵律 #1），且會讓沙盒建置防護誤判——改用
        // ApiService.serverRootUrl（同一修法見 news_article_screen.dart）。
        final String fullUrl = "${ApiService.serverRootUrl}$audioUrl";
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
    final c = UbanColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double screenHeight = MediaQuery.of(context).size.height;
    final double panelHeight = screenHeight * 0.88; // 面板展開比例 88%，完全蓋過「正在播放」部分

    // 背景：品牌綠柔和漸層（設計稿 --news-a/--news-b）。亮色取 brandFill→brandStrong，
    // 深色用較深的綠（#1E4A3B→#0F231C）。疊在其上的白字為內容固定色。
    final gradientColors = isDark
        ? const [Color(0xFF1E4A3B), Color(0xFF0F231C)]
        : [c.brandFill, c.brandStrong];

    return Scaffold(
      backgroundColor: gradientColors.last,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: const Alignment(-0.4, -1),
            end: const Alignment(0.4, 1),
            colors: gradientColors,
          ),
        ),
        child: Stack(
          children: [
            // 底層：聆聽介面，加頂部 SafeArea 以保護狀態欄，但底部不加，讓面板延伸至最底部
            SafeArea(
              bottom: false,
              child: GestureDetector(
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
                child: _buildListeningView(c),
              ),
            ),

            // 上層：新聞列表面板（自定義 Positioned，延伸至螢幕最底部）
            _buildCustomWhitePanel(panelHeight, c),

            // 小豬 + 對話框（當面板展開時，以彈性動畫出現在右下角）
            _buildPigMascot(panelHeight, c),
          ],
        ),
      ),
    );
  }

  /// 疊在綠色漸層上的玻璃鈕底（設計稿 `.glassbtn`）。
  BoxDecoration _glassDecoration() => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      );

  /// 聆聽介面（底層）
  Widget _buildListeningView(UbanColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
      child: Column(
        children: [
          // 返回 + 重點整理按鈕（玻璃鈕），中間有隨面板上滑漸顯的導航欄標題
          Stack(
            alignment: Alignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Semantics(
                    button: true,
                    label: '返回',
                    excludeSemantics: true,
                    child: PressableScale(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: _glassDecoration(),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                  if (!_isSheetExpanded)
                    Flexible(
                      child: PressableScale(
                        onTap: _showNewsSummary,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 52),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 8),
                          decoration: _glassDecoration(),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.auto_awesome,
                                  color: Colors.white, size: 22),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '重點整理',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ubanText(
                                      18, FontWeight.w700, Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                          .animate(
                            target: _isAiThinking ? 1 : 0,
                            onPlay: (controller) => controller.repeat(),
                          )
                          .shake(hz: 3, curve: Curves.easeInOut)
                          .scale(
                              begin: const Offset(1, 1),
                              end: const Offset(1.05, 1.05),
                              duration: 1.seconds),
                    ),
                ],
              ),
              // 中間的導航欄標題：當面板滑上來時漸顯，滑下去時漸隱
              IgnorePointer(
                child: Opacity(
                  opacity: _panelAnimation.value,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 64),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '代誌報給你知',
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'StarPanda',
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // 動態高度與縮放的標題：邊往上擠邊淡出
          _buildAnimatedTitle(),
          const SizedBox(height: 10),
          _buildNowCard(),
          const SizedBox(height: 14),
          _buildControls(),
          const SizedBox(height: 14),
          // 字幕顯示區域（卡拉 OK 高對比進度）
          Expanded(
            child: NewsSubtitleViewer(
              subtitles: _subtitles,
              currentSubtitleIndex: _currentSubtitleIndex,
              subtitleProgress: _subtitleProgress,
            ),
          ),
          const SizedBox(height: 6),
          // 提示文字（第五十三輪 item 8，有測試 news_listen_player_scroll_hint_test）：
          // 「在此處往上滑查看更多新聞」＋向上箭頭；字級沿用 ElderScale.body、顏色
          // AppColors.accent（測試鎖定）。這次外加深色半透明膠囊底提升對比，並用
          // FittedBox(scaleDown) 讓 textScaler 1.3 時整句縮小而不是被省略。
          AnimatedOpacity(
            opacity: _isSheetExpanded ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: _isSheetExpanded,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _expandPanel,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('在此處往上滑查看更多新聞',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            style: ElderScale.body.copyWith(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w800,
                            )),
                      ),
                      const Icon(Icons.keyboard_arrow_up_rounded,
                          color: AppColors.accent, size: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 大標題「代誌 報給你知」（StarPanda 個性字，設計稿 `.nl-title` 46px）。
  /// 面板上滑時淡出並收縮高度；字不隨系統字級放大（已是 46px 展示字）。
  Widget _buildAnimatedTitle() {
    final opacity = (1.0 - _panelAnimation.value).clamp(0.0, 1.0);
    final containerHeight = 104.0 * opacity;

    return Opacity(
      opacity: opacity,
      child: Container(
        height: containerHeight,
        width: double.infinity,
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(),
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '代誌\n報給你知',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontFamily: 'StarPanda',
              fontSize: 46,
              height: 1.05,
              letterSpacing: 0.9,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  /// 新聞列表面板（舊稱白色面板；現用 surface 色，隨亮暗模式）。
  Widget _buildCustomWhitePanel(double panelHeight, UbanColors c) {
    final bottomOffset = -panelHeight + (panelHeight * _panelAnimation.value);

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomOffset,
      height: panelHeight,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: const [
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
                padding: const EdgeInsets.only(top: 12, bottom: 14),
                color: Colors.transparent,
                child: Center(
                  child: Container(
                    width: 56,
                    height: 6,
                    decoration: BoxDecoration(
                      color: c.surface3,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
            // 分類選擇器
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: NewsCategorySelector(
                categories: _categories,
                selectedCategory: _selectedCategory,
                onWhiteBackground: true,
                onCategorySelected: (category) {
                  setState(() {
                    _selectedCategory = category;
                  });
                  if (_newsScrollController.hasClients) {
                    _newsScrollController.jumpTo(0.0);
                  }
                },
              ),
            ),
            // 新聞列表 (使用 BouncingScrollPhysics 帶來更流暢的滑動感受)
            Expanded(
              child: RefreshIndicator(
                color: c.brand,
                backgroundColor: c.surface,
                onRefresh: _refreshNews,
                child: ListView(
                  controller: _newsScrollController,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    NewsCardList(
                      newsItems: _localNewsItems,
                      currentIndex: _currentIndex,
                      selectedCategory: _selectedCategory,
                      userId: widget.userId,
                      onSelectTrack: _selectTrack,
                    ),
                    if (_isLoadingMore)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 30),
                        child: Center(
                          child: CircularProgressIndicator(color: c.brand),
                        ),
                      ),
                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 小豬吉祥物 + 對話框（面板展開時在右下角以彈性效果縮放出現）
  Widget _buildPigMascot(double panelHeight, UbanColors c) {
    if (_panelAnimation.value < 0.1) {
      return const Positioned(
        right: 0,
        bottom: 0,
        child: SizedBox.shrink(),
      );
    }

    final currentTitle = _currentNewsTitle;
    final displayText = currentTitle.length > 20
        ? '${currentTitle.substring(0, 20)}...'
        : currentTitle;

    return Positioned(
      right: 14,
      bottom: 24,
      child: ScaleTransition(
        scale: _pigScaleAnim,
        alignment: Alignment.bottomRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 對話框
            if (currentTitle.isNotEmpty)
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(4),
                    ),
                    boxShadow: c.shadows.card,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('正在唸：',
                          style: ubanText(14, FontWeight.w600, c.text3)),
                      const SizedBox(height: 2),
                      Text(
                        displayText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            ubanText(18, FontWeight.w700, c.text, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(width: 8),
            // 圓形「聽」按鈕
            Semantics(
              button: true,
              label: '小豬幫您整理重點',
              excludeSemantics: true,
              child: PressableScale(
                onTap: _showNewsSummary,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.brandFill,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '聽',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontFamily: 'StarPanda',
                      fontSize: 32,
                      color: c.onBrand,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 「正在播放」卡（設計稿 `.nowcard`）：標籤＋音波、標題、第幾則・分類・日期。
  Widget _buildNowCard() {
    final item = _localNewsItems.isEmpty
        ? const <String, dynamic>{}
        : _localNewsItems[_currentIndex];
    final title = (item['title'] ?? '新聞朗讀').toString();
    final source = (item['category'] ?? '新聞').toString();
    final publishedDate = _formatNewsDate(item);
    final totalCount = max(_localNewsItems.length, 1);
    final currentCount = _localNewsItems.isEmpty ? 0 : (_currentIndex + 1);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '正在播放',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(18, FontWeight.w700, Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              // 音波波動畫 (已模組化)
              NewsSoundWaveIndicator(isPlaying: _isPlaying),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ubanText(22, FontWeight.w900, Colors.white, height: 1.35),
          ),
          const SizedBox(height: 6),
          Text(
            '第 $currentCount / $totalCount 則 · $source · $publishedDate',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ubanText(
                16, FontWeight.w600, Colors.white.withValues(alpha: 0.9)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ubanText(18, FontWeight.w700, Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  /// 播放控制列：上一則／播放暫停／下一則（key 有測試，勿改）。
  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildRoundControl(
          key: const ValueKey('prev_button'),
          tooltip: '上一則',
          icon: Icons.fast_rewind_rounded,
          onTap: () => _changeTrack(-1),
        ),
        const SizedBox(width: 30),
        _isLoadingAudio
            ? const SizedBox(
                width: 78,
                height: 78,
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 3),
                ),
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
        const SizedBox(width: 30),
        _buildRoundControl(
          key: const ValueKey('next_button'),
          tooltip: '下一則',
          icon: Icons.fast_forward_rounded,
          onTap: () => _changeTrack(1),
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
    final size = big ? 78.0 : 60.0;
    final c = UbanColors.of(context);
    return Tooltip(
      message: tooltip ?? '',
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: PressableScale(
          key: key,
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: c.brandStrong,
              size: big ? 38 : 30,
            ),
          ),
        ),
      ),
    );
  }
}
