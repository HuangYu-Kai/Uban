import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../widgets/youtube_bubble_player.dart';

import 'sound_wave_indicator.dart';
import '../controllers/zen_pond_controller.dart';

class DiaryDialogContent extends StatefulWidget {
  final ZenPondController controller;
  final SpeechToText speechToText;
  final String? currentLocaleId;
  final Function(String) sendToAiChat;
  final AudioPlayer historyAudioPlayer;
  final Function(String, String, ZenPondController) playHistoryTts;
  final bool speechEnabled;
  final Function(ZenPondController) showTextInputDialog;
  final Function() scrollToBottom;
  final ScrollController historyScrollController;
  final bool isAiThinking;

  const DiaryDialogContent({
    super.key,
    required this.controller,
    required this.speechToText,
    required this.currentLocaleId,
    required this.sendToAiChat,
    required this.historyAudioPlayer,
    required this.playHistoryTts,
    required this.speechEnabled,
    required this.showTextInputDialog,
    required this.scrollToBottom,
    required this.historyScrollController,
    required this.isAiThinking,
  });

  @override
  State<DiaryDialogContent> createState() => _DiaryDialogContentState();
}

class _DiaryDialogContentState extends State<DiaryDialogContent> {
  String? _selectedDate;
  bool _isDialogRecording = false;
  String _dialogRecognizedWords = '聆聽中，請說話...';
  bool _isGeneratingRag = false;

  Map<String, List<Map<String, dynamic>>> _groupHistoryByDate(List<Map<String, dynamic>> history) {
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (var item in history) {
      final int timestamp = item['timestamp'] ?? 0;
      if (timestamp == 0) continue;
      final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final dateStr = "${dt.year}年${dt.month}月${dt.day}日";
      groups.putIfAbsent(dateStr, () => []).add(item);
    }
    return groups;
  }

  String _getFriendlyDateLabel(String dateStr) {
    final now = DateTime.now();
    final todayStr = "${now.year}年${now.month}月${now.day}日";
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr = "${yesterday.year}年${yesterday.month}月${yesterday.day}日";
    
    if (dateStr == todayStr) {
      return "今天";
    } else if (dateStr == yesterdayStr) {
      return "昨天";
    } else {
      final regExp = RegExp(r'(\d+)年(\d+)月(\d+)日');
      final match = regExp.firstMatch(dateStr);
      if (match != null) {
        final year = match.group(1);
        final month = match.group(2);
        final day = match.group(3);
        if (year == now.year.toString()) {
          return "$month/$day";
        }
        return "$year/$month/$day";
      }
      return dateStr;
    }
  }

  String _generateTopic(List<Map<String, dynamic>> messages) {
    if (messages.isEmpty) return "開始對話";
    
    final allText = messages.map((m) => (m['text'] ?? '').toString()).join(' ').toLowerCase();

    if (allText.contains('家人') || allText.contains('秀珠') || allText.contains('配對') || allText.contains('兒子') || allText.contains('女兒') || allText.contains('孫子') || allText.contains('老伴')) {
      return "一起討論家人";
    }
    if (allText.contains('旅遊') || allText.contains('陽明山') || allText.contains('花鐘') || allText.contains('台南') || allText.contains('出去玩') || allText.contains('景點') || allText.contains('研究')) {
      return "對旅遊地點研究";
    }
    if (allText.contains('音樂') || allText.contains('聽歌') || allText.contains('點歌') || allText.contains('播歌') || allText.contains('放音樂')) {
      return "點歌聽音樂放鬆";
    }
    if (allText.contains('天氣') || allText.contains('氣溫') || allText.contains('下雨') || allText.contains('颱風') || allText.contains('大陽') || allText.contains('晴天')) {
      return "討論天氣狀況";
    }
    if (allText.contains('健康') || allText.contains('吃藥') || allText.contains('醫生') || allText.contains('醫院') || allText.contains('不舒服') || allText.contains('血壓')) {
      return "討論生活與健康";
    }
    if (allText.contains('回憶') || allText.contains('以前') || allText.contains('落葉') || allText.contains('記得') || allText.contains('小時候')) {
      return "回想過去的回憶";
    }
    if (allText.contains('步數') || allText.contains('運動') || allText.contains('散步') || allText.contains('走路')) {
      return "討論日常活動與計步";
    }
    
    return "日常溫馨閒聊";
  }

  void _showClearConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          '確定要清空日記嗎？',
          style: GoogleFonts.notoSansTc(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: const Color(0xFF3E2723),
          ),
        ),
        content: Text(
          '清空後將無法復原與小幫手的溫馨對話紀錄喔。',
          style: GoogleFonts.notoSansTc(fontSize: 18, color: Colors.grey[700]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '留著日記',
              style: GoogleFonts.notoSansTc(fontSize: 18, color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              widget.controller.clearHistory();
              setState(() {
                _selectedDate = null;
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              '確定清空',
              style: GoogleFonts.notoSansTc(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.controller,
      child: Consumer<ZenPondController>(
        builder: (context, controller, child) {
          final groups = _groupHistoryByDate(controller.history);
          final isShowingContent = _selectedDate != null;

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              width: double.infinity,
              height: MediaQuery.of(context).size.height * 0.8,
              decoration: BoxDecoration(
                color: const Color(0xFFFCFBF7), // 宣紙白暖色背景
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // 頂部 Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              if (isShowingContent)
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF8C6D58), size: 22),
                                  onPressed: () {
                                    setState(() {
                                      _selectedDate = null;
                                    });
                                  },
                                ),
                              if (isShowingContent) const SizedBox(width: 4),
                              const Icon(
                                Icons.history_edu_rounded,
                                color: Color(0xFF8C6D58),
                                size: 28,
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  isShowingContent
                                      ? "${_getFriendlyDateLabel(_selectedDate!)} ${_generateTopic(groups[_selectedDate!] ?? [])}"
                                      : '目錄',
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: isShowingContent ? 20 : 26,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF3E2723),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 清空歷史按鈕
                        TextButton.icon(
                          onPressed: _showClearConfirmDialog,
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                          label: Text(
                            '清空日記',
                            style: GoogleFonts.notoSansTc(color: Colors.redAccent, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFEFEBE9)),

                  // 主要區域
                  Expanded(
                    child: isShowingContent
                        ? _buildContentView(groups[_selectedDate!] ?? [])
                        : _buildDirectoryView(groups),
                  ),

                  // 底部控制列（僅在內容頁顯示）
                  if (isShowingContent) ...[
                    const Divider(height: 1, color: Color(0xFFEFEBE9)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // 1. 打字聊天
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: const Color(0xFFF5EBE6),
                            child: IconButton(
                              icon: const Icon(Icons.keyboard, color: Color(0xFF8C6D58), size: 28),
                              onPressed: () {
                                Navigator.pop(context); // 先關日記
                                widget.showTextInputDialog(controller); // 打開打字對話框
                              },
                            ),
                          ),
                          // 2. 語音對話按鈕 (跟我說話) - 直接在日記內錄音
                          ElevatedButton.icon(
                            onPressed: () async {
                              if (!widget.speechEnabled) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('請先允許麥克風權限')),
                                );
                                return;
                              }
                              setState(() {
                                _isDialogRecording = true;
                                _dialogRecognizedWords = '聆聽中，請說話...';
                              });
                              controller.forceRefresh();
                              await widget.speechToText.listen(
                                localeId: widget.currentLocaleId,
                                onResult: (result) {
                                  final words = result.recognizedWords;
                                  setState(() {
                                    _dialogRecognizedWords = words.isNotEmpty ? words : '聆聽中，請說話...';
                                  });
                                  controller.forceRefresh();
                                  if (result.finalResult && words.isNotEmpty) {
                                    setState(() { _isDialogRecording = false; });
                                    controller.forceRefresh();
                                    widget.sendToAiChat(words);
                                  }
                                },
                                listenMode: ListenMode.confirmation,
                              );
                            },
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: _isDialogRecording
                                  ? const Icon(Icons.mic, size: 28, key: ValueKey('mic_on'), color: Colors.white)
                                  : const Icon(Icons.mic_none, size: 28, key: ValueKey('mic_off')),
                            ),
                            label: Text(
                              _isDialogRecording ? _dialogRecognizedWords : '跟我說話',
                              style: GoogleFonts.notoSansTc(fontSize: 16, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isDialogRecording
                                  ? const Color(0xFFB71C1C)
                                  : const Color(0xFF8C6D58),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 2,
                            ),
                          ),
                          // 3. 關閉日記
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: const Color(0xFFEFEBE9),
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Color(0xFF8C6D58), size: 28),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // 目錄頁底部：點擊關閉
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: const Color(0xFFEFEBE9),
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Color(0xFF8C6D58), size: 28),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDirectoryView(Map<String, List<Map<String, dynamic>>> groups) {
    final sortedDates = groups.keys.toList()..sort((a, b) => b.compareTo(a)); // 新的在上面

    return Column(
      children: [
        Expanded(
          child: sortedDates.isEmpty
              ? Center(
                  child: Text(
                    '目前還沒有對話日記喔，\n快與小幫手聊聊天吧 😊',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 22,
                      color: Colors.grey[600],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: sortedDates.length,
                  itemBuilder: (context, index) {
                    final dateStr = sortedDates[index];
                    final messages = groups[dateStr] ?? [];
                    final friendlyDate = _getFriendlyDateLabel(dateStr);
                    final topic = _generateTopic(messages);
                    
                    String preview = "";
                    if (messages.isNotEmpty) {
                      final lastMsg = messages.last;
                      final prefix = lastMsg['sender'] == 'user' ? '我：' : '小幫手：';
                      preview = "$prefix${lastMsg['text']}";
                      if (preview.length > 25) {
                        preview = "${preview.substring(0, 25)}...";
                      }
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF0), // 溫暖紙張底色
                        border: Border.all(color: const Color(0xFFEFEBE9), width: 1.5),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedDate = dateStr;
                          });
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                radius: 24,
                                backgroundColor: Color(0xFFF5EBE6),
                                child: Icon(Icons.chrome_reader_mode_outlined, color: Color(0xFF8C6D58), size: 26),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "$friendlyDate $topic",
                                      style: GoogleFonts.notoSansTc(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF3E2723),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      preview,
                                      style: GoogleFonts.notoSansTc(
                                        fontSize: 16,
                                        color: Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Icon(Icons.arrow_forward_ios_rounded, size: 18, color: Colors.grey),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${messages.length} 則',
                                    style: GoogleFonts.notoSansTc(fontSize: 14, color: Colors.grey[500]),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        
        // RAG 話題生成按鈕區域
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          decoration: const BoxDecoration(
            color: Color(0xFFF5EBE6),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
          ),
          child: Center(
            child: ElevatedButton.icon(
              onPressed: _isGeneratingRag ? null : () async {
                setState(() { _isGeneratingRag = true; });
                final success = await widget.controller.generateAndAddRagLeaf(1);
                setState(() { _isGeneratingRag = false; });
                if (!mounted) return;
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已為您在池塘中落下新的回憶話題 🍂')),
                  );
                  final todayStr = "${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日";
                  setState(() {
                    _selectedDate = todayStr;
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('暫時無法喚起回憶，請稍後再試 😊')),
                  );
                }
              },
              icon: _isGeneratingRag
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Icon(Icons.psychology_alt_rounded, size: 26),
              label: Text(
                _isGeneratingRag ? '正在喚起回憶中...' : '🍂 喚起腦海中的回憶落葉',
                style: GoogleFonts.notoSansTc(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB74D), // 溫暖落葉金黃色
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 3,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContentView(List<Map<String, dynamic>> messages) {
    // 每次對話變更或重繪，自動滾動到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.historyScrollController.hasClients) {
        widget.historyScrollController.jumpTo(
          widget.historyScrollController.position.maxScrollExtent,
        );
      }
    });

    final showThinking = widget.isAiThinking && (_selectedDate == "${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日");

    return ListView.builder(
      controller: widget.historyScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: messages.length + (showThinking ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) {
          return _buildThinkingBubble();
        }
        final item = messages[index];
        final isUser = item['sender'] == 'user';
        return _buildHistoryBubble(item, isUser, widget.controller);
      },
    );
  }

  Widget _buildHistoryBubble(Map<String, dynamic> item, bool isUser, ZenPondController ctrl) {
    final text = item['text'] ?? '';
    final imageUrl = item['imageUrl'] as String?;
    final videoId = item['videoId'] as String?;
    final timestamp = item['timestamp'] ?? 0;
    final bubbleId = "${timestamp}_${item['sender']}";

    final isPlaying = ctrl.ttsPlayingId == bubbleId;
    final isLoading = ctrl.ttsLoading && isPlaying;

    final bubbleColor = isUser ? const Color(0xFFF5EBE6) : const Color(0xFFE6F0EA);
    final textColor = const Color(0xFF3E2723);
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final margin = isUser 
        ? const EdgeInsets.only(left: 60, right: 0, bottom: 16) 
        : const EdgeInsets.only(left: 0, right: 60, bottom: 16);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: margin,
        child: Column(
          crossAxisAlignment: align,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 8, right: 8),
              child: Text(
                isUser ? '我' : '貼心小幫手',
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF8C6D58),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(4),
                  bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 24, // 24pt 大字
                      height: 1.5,
                      color: textColor,
                    ),
                  ),
                  
                  if (!isUser) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => widget.playHistoryTts(bubbleId, text, ctrl),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isPlaying ? const Color(0xFFC8E6C9) : Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF8C6D58).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isLoading)
                              const SoundWaveIndicator(color: Color(0xFF8C6D58))
                            else if (isPlaying)
                              const SoundWaveIndicator(color: Color(0xFF4CAF50))
                            else
                              const Icon(
                                Icons.volume_mute,
                                color: Color(0xFF8C6D58),
                                size: 18,
                              ),
                            const SizedBox(width: 6),
                            Text(
                              isLoading ? '載入中...' : (isPlaying ? '正在朗讀' : '讀給我聽'),
                              style: GoogleFonts.notoSansTc(
                                fontSize: 14,
                                color: const Color(0xFF8C6D58),
                                fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                  if (imageUrl != null && imageUrl.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.broken_image, size: 60, color: Colors.grey),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '📸 分享的照片',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (videoId != null && videoId.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: 280,
                        height: 160,
                        child: YoutubeBubblePlayer(videoId: videoId),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 0, right: 60, bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 8, right: 8),
              child: Text(
                '貼心小幫手',
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF8C6D58),
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFE6F0EA),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(20),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF8C6D58),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '正在認真思考中...',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 20,
                      color: const Color(0xFF3E2723),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
