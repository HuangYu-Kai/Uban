import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

/// 一個專門用於聊天氣泡內的 YouTube 播放器組件
class YoutubeBubblePlayer extends StatefulWidget {
  final String videoId;
  
  const YoutubeBubblePlayer({
    super.key, 
    required this.videoId,
  });

  @override
  State<YoutubeBubblePlayer> createState() => _YoutubeBubblePlayerState();
}

class _YoutubeBubblePlayerState extends State<YoutubeBubblePlayer> {
  late YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      initialVideoId: widget.videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: false,      // 不要自動播放，讓長輩自己點擊
        mute: false,
        isLive: false,
        disableDragSeek: false,
        loop: false,
        forceHD: false,
        enableCaption: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: YoutubePlayer(
        controller: _controller,
        showVideoProgressIndicator: true,
        progressIndicatorColor: Colors.redAccent,
        progressColors: const ProgressBarColors(
          playedColor: Colors.red,
          handleColor: Colors.redAccent,
        ),
        onReady: () {
          debugPrint('Youtube player is ready for ID: ${widget.videoId}');
        },
      ),
    );
  }

  @override
  void deactivate() {
    // 當組件從樹中移除時暫停播放
    _controller.pause();
    super.deactivate();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
