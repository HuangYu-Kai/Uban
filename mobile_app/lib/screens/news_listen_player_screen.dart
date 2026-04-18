import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';

class NewsListenPlayerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> newsItems;
  final int initialIndex;

  const NewsListenPlayerScreen({
    super.key,
    required this.newsItems,
    required this.initialIndex,
  });

  @override
  State<NewsListenPlayerScreen> createState() => _NewsListenPlayerScreenState();
}

class _NewsListenPlayerScreenState extends State<NewsListenPlayerScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Random _random = Random();
  int _currentIndex = 0;
  bool _isLoadingAudio = false;
  bool _isPlaying = false;
  String? _error;
  Timer? _waveTimer;
  List<double> _waveHeights = List<double>.filled(11, 40);
  
  // 字幕相關
  List<dynamic> _subtitles = [];
  String _currentSubtitle = "";
  double _subtitleProgress = 0.0; // 0.0 to 1.0 within the current chunk
  StreamSubscription? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _currentIndex =
        widget.initialIndex.clamp(0, max(widget.newsItems.length - 1, 0));
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
      setState(() {
        _isPlaying = false;
        _currentSubtitle = "";
      });
      _stopWaveAnimation();
    });

    // 監聽播放進度以同步字幕
    _positionSubscription = _audioPlayer.onPositionChanged.listen((position) {
      if (!mounted || _subtitles.isEmpty) return;
      
      final ms = position.inMilliseconds;
      String matchedText = "";
      double progress = 0.0;

      for (var sub in _subtitles) {
        final start = sub['start_ms'] as int;
        final duration = sub['duration_ms'] as int;
        if (ms >= start && ms < (start + duration)) {
          matchedText = sub['text'] as String;
          progress = (ms - start) / (duration > 0 ? duration : 1);
          break;
        }
      }

      if (matchedText != _currentSubtitle || (progress - _subtitleProgress).abs() > 0.05) {
        setState(() {
          _currentSubtitle = matchedText;
          _subtitleProgress = progress.clamp(0.0, 1.0);
        });
      }
    });
    if (widget.newsItems.isNotEmpty) {
      _playCurrentNews();
    }
  }

  @override
  void dispose() {
    _waveTimer?.cancel();
    _positionSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playCurrentNews() async {
    if (widget.newsItems.isEmpty) return;
    final item = widget.newsItems[_currentIndex];
    final speechText = _composeSpeechText(item);
    setState(() {
      _isLoadingAudio = true;
      _error = null;
    });
    try {
      final response = await ApiService.synthesizeTts(text: speechText);
      if (response['success'] != true) {
        final detail =
            response['detail'] ?? response['message'] ?? response['error'];
        throw Exception(detail ?? 'Edge TTS 合成失敗');
      }
      final audioBase64 = (response['audio'] ?? '').toString();
      if (audioBase64.isEmpty) {
        throw Exception('語音資料為空');
      }
      
      // 更新字幕清單
      final subs = response['subtitles'];
      
      final audioPayload = _extractBase64Payload(audioBase64);
      final audioBytes = base64Decode(audioPayload);
      await _audioPlayer.stop();
      await _audioPlayer.play(BytesSource(audioBytes));
      if (!mounted) return;
      setState(() {
        _subtitles = (subs is List) ? subs : [];
        _currentSubtitle = "";
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
    final text = raw.trim();
    if (text.startsWith('data:')) {
      final commaIndex = text.indexOf(',');
      if (commaIndex >= 0 && commaIndex < text.length - 1) {
        return text.substring(commaIndex + 1);
      }
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

  @override
  Widget build(BuildContext context) {
    final item = widget.newsItems.isEmpty
        ? const <String, dynamic>{}
        : widget.newsItems[_currentIndex];
    final title = (item['title'] ?? '新聞朗讀').toString();
    final source = (item['category'] ?? '新聞').toString();
    final publishedDate = _formatNewsDate(item);
    final totalCount = max(widget.newsItems.length, 1);
    final currentCount = widget.newsItems.isEmpty ? 0 : (_currentIndex + 1);
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
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
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
                      fontSize: 48, // Reduced from 58 to fit better
                      height: 1.1,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
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
                              fontSize: 30, // Slightly reduced
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
                            fontWeight: FontWeight.w600,
                          ),
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
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 110, // Slightly reduced from 120
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: List.generate(_waveHeights.length, (i) {
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 240),
                                width: 8,
                                height: _waveHeights[i],
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
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildRoundControl(
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
                              icon: _isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              onTap: _togglePlayPause,
                              big: true,
                            ),
                      const SizedBox(width: 42),
                      _buildRoundControl(
                        icon: Icons.fast_forward_rounded,
                        onTap: () => _changeTrack(1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // 方案 B：動態大字字幕
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 100),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                    ),
                    child: Center(
                      child: _currentSubtitle.isEmpty
                          ? Text(
                              '準備播放中...',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 32, // Slightly reduced
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                style: const TextStyle(
                                  fontSize: 32, // Slightly reduced
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                  shadows: [
                                    Shadow(blurRadius: 8, color: Colors.black, offset: Offset(2, 2)),
                                  ],
                                ),
                                children: [
                                  TextSpan(
                                    text: _currentSubtitle.substring(0, (_currentSubtitle.length * _subtitleProgress).round().clamp(0, _currentSubtitle.length)),
                                    style: const TextStyle(color: Color(0xFFFFD700)),
                                  ),
                                  TextSpan(
                                    text: _currentSubtitle.substring((_currentSubtitle.length * _subtitleProgress).round().clamp(0, _currentSubtitle.length)),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    '往下滑查看更多',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 28, // Reduced from 40
                        fontWeight: FontWeight.w700),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded,
                      color: Colors.white, size: 48),
                  const SizedBox(height: 16),
                  _buildNewsSelectionList(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNewsSelectionList() {
    return Column(
      children: List.generate(widget.newsItems.length, (index) {
        final item = widget.newsItems[index];
        final isCurrent = index == _currentIndex;
        final title = (item['title'] ?? '').toString();
        final source = (item['category'] ?? '新聞').toString();
        final date = _formatNewsDate(item);

        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: isCurrent
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Material(
                  color: isCurrent
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(
                      color: isCurrent
                          ? const Color(0xFFFFE066)
                          : Colors.white.withValues(alpha: 0.25),
                      width: isCurrent ? 2.5 : 1.5,
                    ),
                  ),
                  child: InkWell(
                    onTap: () => _selectTrack(index),
                    splashColor: Colors.white.withValues(alpha: 0.3),
                    highlightColor: Colors.white.withValues(alpha: 0.2),
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isCurrent
                                            ? const Color(0xFFFFD700)
                                            : Colors.white.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        source,
                                        style: TextStyle(
                                          color: isCurrent
                                              ? const Color(0xFF1E293B)
                                              : Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      date,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.85),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: isCurrent ? 26 : 24,
                                    fontWeight: isCurrent
                                        ? FontWeight.w900
                                        : FontWeight.w700,
                                    height: 1.35,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          if (isCurrent)
                            const Icon(Icons.equalizer_rounded,
                                color: Color(0xFFFFD700), size: 38)
                          else
                            Icon(Icons.play_circle_outline_rounded,
                                color: Colors.white.withValues(alpha: 0.8),
                                size: 38),
                        ],
                      ),
                    ),
                  ),
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
  }) {
    final size = big ? 74.0 : 60.0;
    return InkWell(
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
    );
  }
}
