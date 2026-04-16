import 'dart:async';
import 'dart:convert';
import 'dart:math';

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
  bool _showTranscript = false;
  
  // 字幕相關
  List<dynamic> _subtitles = [];
  String _currentSubtitle = "";
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
      String? matchedText;
      
      // 尋找當前毫秒對應的字幕
      for (var sub in _subtitles) {
        final start = sub['start_ms'] as int;
        final duration = sub['duration_ms'] as int;
        if (ms >= start && ms < (start + duration)) {
          matchedText = sub['text'] as String;
          break;
        }
      }
      
      if (matchedText != null && matchedText != _currentSubtitle) {
        setState(() {
          _currentSubtitle = matchedText!;
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
      final response = await ApiService.synthesizeEdgeTts(text: speechText);
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
    setState(() {
      _currentIndex = nextIndex;
      _error = null;
      _showTranscript = false;
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

  String _transcriptText(Map<String, dynamic> item) {
    final content = (item['content'] ?? '').toString().trim();
    if (content.isNotEmpty) return content;
    return (item['title'] ?? '').toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.newsItems.isEmpty
        ? const <String, dynamic>{}
        : widget.newsItems[_currentIndex];
    final title = (item['title'] ?? '新聞朗讀').toString();
    final source = (item['category'] ?? '新聞').toString();
    final publishedDate = _formatNewsDate(item);
    final transcript = _transcriptText(item);
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
                const SizedBox(height: 8),
                const Text(
                  '代誌\n報給你知',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'StarPanda',
                    fontSize: 58,
                    height: 1.15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
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
                        height: 120,
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
                const SizedBox(height: 28),
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
                const SizedBox(height: 18),
                // 方案 B：動態大字字幕 (移至下方)
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 80),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      _currentSubtitle.isEmpty ? (title.length > 10 ? "${title.substring(0, 10)}..." : title) : _currentSubtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34, // 超大字體，符合長輩需求
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(blurRadius: 4, color: Colors.black54, offset: Offset(2, 2)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () =>
                            setState(() => _showTranscript = !_showTranscript),
                        borderRadius: BorderRadius.circular(18),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.subject_rounded,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                _showTranscript ? '收起文字稿' : '顯示文字稿',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                _showTranscript
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 220),
                        crossFadeState: _showTranscript
                            ? CrossFadeState.showFirst
                            : CrossFadeState.showSecond,
                        firstChild: Container(
                          constraints: const BoxConstraints(maxHeight: 130),
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                          child: SingleChildScrollView(
                            child: Text(
                              transcript.isEmpty ? '沒有可顯示的文字稿' : transcript,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ),
                        secondChild: const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const Text(
                  '往下滑查看更多',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w700),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Colors.white, size: 56),
              ],
            ),
          ),
        ),
      ),
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
