import 'package:flutter/material.dart';

import '../../../widgets/ui/ui.dart';

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
    // 疊在綠色漸層上的字幕面板：固定深色半透明底＋白字（內容固定色，亮暗模式皆同）。
    // 卡拉 OK 進度「高對比」：已唸＝純白＋粗體，未唸＝白 55%，非當前句＝白 45%。
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(24),
      ),
      child: widget.subtitles.isEmpty
          ? Center(
              child: Text(
                '準備播放中...',
                textAlign: TextAlign.center,
                style: ubanText(
                    26, FontWeight.w900, Colors.white.withValues(alpha: 0.9)),
              ),
            )
          : SingleChildScrollView(
              controller: _subtitleScrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Column(
                children: List.generate(widget.subtitles.length, (index) {
                  final isCurrent = index == widget.currentSubtitleIndex;
                  final text = widget.subtitles[index]['text'] as String;
                  final split = (text.length * widget.subtitleProgress)
                      .round()
                      .clamp(0, text.length);

                  return AnimatedOpacity(
                    key: _subtitleKeys[index],
                    duration: const Duration(milliseconds: 200),
                    opacity: 1.0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: RichText(
                        textAlign: TextAlign.center,
                        textScaler: MediaQuery.textScalerOf(context),
                        text: TextSpan(
                          style: ubanText(
                            isCurrent ? 26 : 20,
                            isCurrent ? FontWeight.w900 : FontWeight.w600,
                            Colors.white,
                            height: 1.45,
                          ),
                          children: [
                            if (isCurrent) ...[
                              TextSpan(
                                text: text.substring(0, split),
                                style: const TextStyle(color: Colors.white),
                              ),
                              TextSpan(
                                text: text.substring(split),
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.55)),
                              ),
                            ] else
                              TextSpan(
                                text: text,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45)),
                              ),
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
