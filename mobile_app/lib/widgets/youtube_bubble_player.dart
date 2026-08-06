import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../globals.dart';

/// 一個專門用於聊天氣泡內的 YouTube 播放器組件
/// 採用「影音卡片 + 獨立視訊 Modal 彈窗」架構，徹底隔離 ListView 重繪與背景 Audio Focus 搶奪導致的跳針問題。
class YoutubeBubblePlayer extends StatelessWidget {
  final String videoId;
  final VoidCallback? onPlay;

  const YoutubeBubblePlayer({
    super.key,
    required this.videoId,
    this.onPlay,
  });

  void _playInModal(BuildContext context) {
    // 觸發停止背景 TTS
    onPlay?.call();

    // 開啟完全隔離的獨立視訊 Modal 彈窗
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => _YoutubePlayerDialog(videoId: videoId),
    );
  }

  Future<void> _openExternalYoutube() async {
    final url = Uri.parse('https://www.youtube.com/watch?v=$videoId');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.85).clamp(240.0, 480.0);
    final thumbnailUrl = 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: cardWidth,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Image.network(
                    thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => Container(
                      color: Colors.grey[900],
                      child: const Icon(Icons.music_note, color: Colors.white54, size: 48),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.35),
                  ),
                ),
                GestureDetector(
                  onTap: () => _playInModal(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withValues(alpha: 0.5),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                        SizedBox(width: 6),
                        Text(
                          '點擊播放音樂影片',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: const Color(0xFF1E293B),
            child: InkWell(
              onTap: _openExternalYoutube,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.open_in_new, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      '全螢幕/App開啟播放',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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

/// 獨立隔離的 YouTube 視訊 Modal 彈窗 (單一持久視訊節點，徹底消除 WebView 重載全螢幕循環 BUG)
class _YoutubePlayerDialog extends StatefulWidget {
  final String videoId;

  const _YoutubePlayerDialog({required this.videoId});

  @override
  State<_YoutubePlayerDialog> createState() => _YoutubePlayerDialogState();
}

class _YoutubePlayerDialogState extends State<_YoutubePlayerDialog> {
  late YoutubePlayerController _controller;
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    isMediaPlayingNotifier.value = true; // ★ 告知系統媒體正在播放，暫停背景 WakeWord 語音喚醒對 AudioFocus 的無限衝擊
    _controller = YoutubePlayerController(
      initialVideoId: widget.videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        isLive: false,
        disableDragSeek: false,
        loop: false,
        forceHD: false,
        enableCaption: true,
        useHybridComposition: true,
      ),
    );
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });
    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _closeDialog() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final targetWidth = _isFullScreen ? screenSize.width : (screenSize.width * 0.95).clamp(280.0, 640.0);
    final insetPadding = _isFullScreen ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16, vertical: 24);

    return PopScope(
      canPop: !_isFullScreen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isFullScreen) {
          _toggleFullScreen();
        }
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: insetPadding,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: targetWidth,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(_isFullScreen ? 0 : 20),
            boxShadow: _isFullScreen
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: _isFullScreen ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 頂部控制列
              Container(
                color: const Color(0xFF1E293B),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.ondemand_video_rounded, color: Colors.redAccent, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          _isFullScreen ? '全螢幕播放' : '影音播放器',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        // 全螢幕切換按鈕
                        IconButton(
                          icon: Icon(
                            _isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                          tooltip: _isFullScreen ? '縮小視窗' : '全螢幕放大',
                          onPressed: _toggleFullScreen,
                        ),
                        // 關閉彈窗按鈕
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
                          tooltip: '關閉影片',
                          onPressed: _closeDialog,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 視訊區域 (維持在同一個 Widget 節點，永遠不被 Re-parent/Unmount)
              Expanded(
                flex: _isFullScreen ? 1 : 0,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: YoutubePlayer(
                      controller: _controller,
                      showVideoProgressIndicator: true,
                      progressIndicatorColor: Colors.redAccent,
                      progressColors: const ProgressBarColors(
                        playedColor: Colors.red,
                        handleColor: Colors.redAccent,
                      ),
                    ),
                  ),
                ),
              ),
              if (!_isFullScreen) const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller.dispose();
    isMediaPlayingNotifier.value = false; // ★ 彈窗關閉後，恢復全域背景 WakeWord 語音喚醒監聽
    super.dispose();
  }
}
