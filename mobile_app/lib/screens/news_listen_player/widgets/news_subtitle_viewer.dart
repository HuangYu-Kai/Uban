import 'package:flutter/material.dart';

class NewsSubtitleViewer extends StatefulWidget {
  final List<dynamic> subtitles;
  final int currentSubtitleIndex;
  final double subtitleProgress;

  const NewsSubtitleViewer({
    super.key,
    required this.subtitles,
    required this.currentSubtitleIndex,
    required this.subtitleProgress,
  });

  @override
  State<NewsSubtitleViewer> createState() => _NewsSubtitleViewerState();
}

class _NewsSubtitleViewerState extends State<NewsSubtitleViewer> {
  final ScrollController _subtitleScrollController = ScrollController();
  List<GlobalKey> _subtitleKeys = [];

  @override
  void initState() {
    super.initState();
    _initKeys();
  }

  @override
  void didUpdateWidget(covariant NewsSubtitleViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.subtitles.length != oldWidget.subtitles.length) {
      _initKeys();
    }
    if (widget.currentSubtitleIndex != oldWidget.currentSubtitleIndex) {
      _scrollToSubtitle(widget.currentSubtitleIndex);
    }
  }

  @override
  void dispose() {
    _subtitleScrollController.dispose();
    super.dispose();
  }

  void _initKeys() {
    _subtitleKeys = List.generate(widget.subtitles.length, (index) => GlobalKey());
  }

  void _scrollToSubtitle(int index) {
    if (index < 0 || index >= _subtitleKeys.length) return;
    final key = _subtitleKeys[index];

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

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: widget.subtitles.isEmpty
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
              padding: const EdgeInsets.symmetric(vertical: 100),
              child: Column(
                children: List.generate(widget.subtitles.length, (index) {
                  final isCurrent = index == widget.currentSubtitleIndex;
                  final text = widget.subtitles[index]['text'] as String;

                  return AnimatedOpacity(
                    key: _subtitleKeys[index],
                    duration: const Duration(milliseconds: 200),
                    opacity: isCurrent ? 1.0 : 0.4,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: isCurrent ? 30 : 22,
                            fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
                            height: 1.4,
                          ),
                          children: [
                            if (isCurrent) ...[
                              TextSpan(
                                text: text.substring(
                                    0,
                                    (text.length * widget.subtitleProgress)
                                        .round()
                                        .clamp(0, text.length)),
                                style: const TextStyle(color: Color(0xFFFFD700)),
                              ),
                              TextSpan(
                                text: text.substring((text.length *
                                        widget.subtitleProgress)
                                    .round()
                                    .clamp(0, text.length)),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ] else ...[
                              TextSpan(
                                text: text,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
    );
  }
}
