import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../models/memoir_story.dart';
import '../../../../services/memoir_service.dart';

/// 顯示長輩口述人生故事分享彈窗
void showElderShareStoryDialog({
  required BuildContext context,
  required String promptQuestion,
  required bool isFromChild,
  required String elderId,
  required VoidCallback onSaved,
}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (dialogCtx) => ElderShareStoryDialog(
      promptQuestion: promptQuestion,
      isFromChild: isFromChild,
      elderId: elderId,
      onSaved: onSaved,
    ),
  );
}

// ── 🎙️ 長輩口述人生回憶錄互動彈窗 ──────────────────────────────
class ElderShareStoryDialog extends StatefulWidget {
  final String promptQuestion;
  final bool isFromChild;
  final String elderId;
  final VoidCallback onSaved;

  const ElderShareStoryDialog({
    super.key,
    required this.promptQuestion,
    required this.isFromChild,
    required this.elderId,
    required this.onSaved,
  });

  @override
  State<ElderShareStoryDialog> createState() => _ElderShareStoryDialogState();
}

class _ElderShareStoryDialogState extends State<ElderShareStoryDialog>
    with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  bool _isAnalyzing = false;
  bool _hasRecorded = false;
  bool _isSaving = false;
  late AnimationController _waveController;

  // 由 AI 自動智能提煉，長輩完全不需手動輸入或挑選
  String _aiTitle = '';
  String _aiTag = '經典回憶';
  String _aiTranscription = '';

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _waveController.dispose();
    super.dispose();
  }

  void _toggleRecord() {
    if (_isRecording) {
      _stopRecording();
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _isRecording = true;
        _hasRecorded = false;
        _recordSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {
          _recordSeconds++;
        });
        if (_recordSeconds >= 3) {
          _stopRecording();
        }
      });
    }
  }

  void _stopRecording() {
    _recordTimer?.cancel();
    HapticFeedback.mediumImpact();
    setState(() {
      _isRecording = false;
      _isAnalyzing = true;
    });

    // 模擬 AI 在 1 秒內智能整理口述語音、自動命名篇名、自動歸類
    Timer(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      final rawSpeech = _getSimulatedTranscription(widget.promptQuestion);
      final analyzed = _analyzeWithAi(widget.promptQuestion, rawSpeech);

      setState(() {
        _isAnalyzing = false;
        _hasRecorded = true;
        _aiTitle = analyzed.title;
        _aiTag = analyzed.tag;
        _aiTranscription = analyzed.story;
      });
      HapticFeedback.lightImpact();
    });
  }

  ({String title, String tag, String story}) _analyzeWithAi(
      String question, String transcript) {
    final text = '$question $transcript';

    String tag = '經典回憶';
    if (text.contains('吃') ||
        text.contains('菜') ||
        text.contains('紅豆') ||
        text.contains('點心') ||
        text.contains('美食') ||
        text.contains('滋味') ||
        text.contains('味道') ||
        text.contains('包子')) {
      tag = '美食記憶';
    } else if (text.contains('薪水') ||
        text.contains('工作') ||
        text.contains('打拼') ||
        text.contains('當兵') ||
        text.contains('生意') ||
        text.contains('學徒') ||
        text.contains('布行')) {
      tag = '奮鬥歲月';
    } else if (text.contains('祝福') ||
        text.contains('心裡話') ||
        text.contains('孩子') ||
        text.contains('孫') ||
        text.contains('傳承') ||
        text.contains('叮嚀')) {
      tag = '溫馨寄語';
    }

    String title = '阿公的珍貴人生回憶';
    if (text.contains('廟口') ||
        text.contains('田裡') ||
        text.contains('玩') ||
        text.contains('放學') ||
        text.contains('陀螺')) {
      title = '廟口童玩與純真田埂時光';
    } else if (text.contains('薪水') ||
        text.contains('第一份工作') ||
        text.contains('布行')) {
      title = '第一份薪水與買給父母的熱包子';
    } else if (text.contains('阿嬤') ||
        text.contains('約會') ||
        text.contains('新公園')) {
      title = '新公園水池邊與阿嬤的青澀約會';
    } else if (text.contains('紅豆') ||
        text.contains('灶坑') ||
        text.contains('吃') ||
        text.contains('母親')) {
      title = '冬日灶坑柴火上的暖心紅豆湯';
    } else if (text.contains('祝福') ||
        text.contains('孫') ||
        text.contains('全家')) {
      title = '阿公留給全家子孫的一生叮嚀';
    }

    return (title: title, tag: tag, story: transcript);
  }

  String _getSimulatedTranscription(String q) {
    if (q.contains('玩') ||
        q.contains('廟口') ||
        q.contains('田裡') ||
        q.contains('遊戲')) {
      return '那時候放學鞋子一脫，大家就衝到廟埕前打陀螺、彈彈珠，或者在剛收割完的稻田裡抓泥鰍烤地瓜。天黑了聽到家裡阿母在門口喊吃飯，大家才依依不捨跑回家。那種滿頭大汗、笑得合不攏嘴的單純快樂，現在想起來心裡還是好溫暖。';
    } else if (q.contains('薪水') || q.contains('工作')) {
      return '我那時候剛退伍，第一份工作是在布行當學徒，第一個月領到薪水只有八百塊錢。雖然不多，但那天下班我立刻買了一袋熱騰騰的包子和半斤茶葉帶回家給父母。看著父母臉上的笑容，心裡覺得一切辛苦都值得了。那份踏實感，一直陪著我走到今天。';
    } else if (q.contains('阿嬤') || q.contains('約會')) {
      return '那是民國六十幾年，媒人牽線後，我們約在新公園的水池邊散步。阿嬤那天穿著一件天藍色的洋裝，頭髮綁著整齊的馬尾。我手心全是汗，只敢聊些天氣和工作，連手都不敢牽，最後帶她去喝了一杯木瓜牛奶。那一幕，我這輩子都不會忘記。';
    } else if (q.contains('吃') || q.contains('美食') || q.contains('點心')) {
      return '小時候每到冬天寒流來襲，我母親總會在灶坑生起龍眼木柴火，大鐵鍋裡慢火熬煮著萬丹紅豆。那時候砂糖放得不多，但柴火的煙燻香氣與紅豆天然的甘甜融在一起，每個人捧著一個小碗趁熱喝，手腳立刻就暖了。至今任何甜品都比不上那種家裡的滋味。';
    } else if (q.contains('祝福') || q.contains('孩子') || q.contains('心裡話')) {
      return '孩子們、孫子們，阿公年紀大了，看著你們各自成家立業、踏實做人，阿公心裡只有滿滿的欣慰。人生就像爬山，有平路也有陡坡，只要全家人心連心、互相扶持包容，就沒有跨不過的難關。願你們大家都平安順心、知足常樂。';
    }
    return '今天跟小豬聊起以前的往事，回想起以前的日子雖然物資沒有現在豐富，但鄰里之間互相關照、真誠厚道。只要腳踏實地、心存善念，生活處處都是福氣。希望把這份平安與溫暖留給子孫後代。';
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    HapticFeedback.selectionClick();

    final story = MemoirStory(
      id: 'memoir_${DateTime.now().millisecondsSinceEpoch}',
      elderId: widget.elderId,
      title: _aiTitle.isNotEmpty ? _aiTitle : '阿公的珍貴人生回憶',
      tag: _aiTag,
      preview: _aiTranscription.length > 42
          ? '${_aiTranscription.substring(0, 42)}...'
          : _aiTranscription,
      fullStory: _aiTranscription,
      promptQuestion: widget.promptQuestion,
      audioAssetOrUrl: 'assets/audio/memoir_sample_1.mp3',
      imageAssetOrUrl: 'assets/images/memoir_card.png',
      recordedDate: DateTime.now(),
      isFavorite: false,
      familyNotes: [],
    );

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    await MemoirService.instance.saveMemoir(story);
    if (widget.isFromChild) {
      await MemoirService.instance
          .markPromptAnswered(widget.elderId, widget.promptQuestion);
    }

    widget.onSaved();
    navigator.pop();

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Text('🎉', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '人生故事已珍藏！AI 已自動歸檔至「$_aiTag」❤️',
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFFFFDF9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: Color(0xFFEADBCE), width: 1.8),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 標題列
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.isFromChild
                          ? const Color(0xFFFFF7ED)
                          : const Color(0xFFECFDF5),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      widget.isFromChild ? '💌' : '🎙️',
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '口述人生故事膠囊',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF451A03),
                          ),
                        ),
                        Text(
                          widget.isFromChild
                              ? '兒女想聽聽阿公當年的故事'
                              : '跟小豬說說話，AI 自動為您整理成自傳',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 12.5,
                            color: const Color(0xFF78350F),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Color(0xFF78350F)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 引導提問卡（大字體、親切）
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.isFromChild
                        ? [const Color(0xFFFFF7ED), const Color(0xFFFFEDD5)]
                        : [const Color(0xFFF0FDF4), const Color(0xFFE6F4EA)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: widget.isFromChild
                        ? const Color(0xFFF97316).withValues(alpha: 0.5)
                        : const Color(0xFF10B981).withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('🐽', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Text(
                          widget.isFromChild ? '兒女想聽阿公說：' : '小豬提問引導：',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: widget.isFromChild
                                ? const Color(0xFFC2410C)
                                : const Color(0xFF047857),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.promptQuestion,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF451A03),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ── 核心互動區 ──
              if (_isAnalyzing) ...[
                // 狀態 1：AI 智能提煉中
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF6F0),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFEADBCE), width: 1.5),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(
                          strokeWidth: 3.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '✨ 小豬正在為阿公整理回憶...',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF451A03),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'AI 自動生成篇名、智能分類中，馬上好喔！',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 13,
                          color: const Color(0xFF78350F),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (!_hasRecorded) ...[
                // 狀態 2：尚未錄音 / 錄音進行中
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: _isRecording
                        ? const Color(0xFFFEF2F2)
                        : const Color(0xFFFAF6F0),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: _isRecording
                          ? const Color(0xFFEF4444)
                          : const Color(0xFFEADBCE),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _toggleRecord,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: _isRecording ? 88 : 82,
                          height: _isRecording ? 88 : 82,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isRecording
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF10B981),
                            boxShadow: [
                              BoxShadow(
                                color: (_isRecording
                                        ? const Color(0xFFEF4444)
                                        : const Color(0xFF10B981))
                                    .withValues(alpha: 0.35),
                                blurRadius: 20,
                                spreadRadius: _isRecording ? 6 : 2,
                              ),
                            ],
                          ),
                          child: Icon(
                            _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                            size: 42,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_isRecording) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '小豬正在聽阿公說... 🔴 (說完再按一下完成)',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFEF4444),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // 聲波動態模擬
                        AnimatedBuilder(
                          animation: _waveController,
                          builder: (context, child) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(14, (index) {
                                final wave = math.sin(
                                        (_waveController.value * math.pi * 2) +
                                            (index * 0.45))
                                    .abs();
                                final barHeight = 8.0 + (wave * 22.0);
                                return Container(
                                  width: 3.5,
                                  height: barHeight,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444)
                                        .withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                );
                              }),
                            );
                          },
                        ),
                      ] else ...[
                        Text(
                          '按一下大麥克風，跟小豬聊聊天 🎙️',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF451A03),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '（請阿公放輕鬆隨意說，AI 小豬會自動為您整理成自傳篇章）',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 12.5,
                            color: const Color(0xFF78350F),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ] else ...[
                // 狀態 3：AI 整理完成展示卡片（純預覽，長輩零打字、零挑選負擔）
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF6F0),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.6),
                      width: 1.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // AI 提煉標籤
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD1FAE5),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: const Color(0xFF10B981), width: 1.2),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🏷️', style: TextStyle(fontSize: 12)),
                                const SizedBox(width: 4),
                                Text(
                                  'AI 自動歸納：$_aiTag',
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF047857),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '✨ AI 已轉寫為文字',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 11.5,
                              color: const Color(0xFF059669),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // AI 提煉篇名
                      Text(
                        '《 $_aiTitle 》',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF451A03),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // 口述整理內文
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFEADBCE)),
                        ),
                        child: Text(
                          _aiTranscription,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 15,
                            height: 1.55,
                            color: const Color(0xFF451A03),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // 一鍵封存按鈕
                ElevatedButton(
                  onPressed: _isSaving ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('🌟', style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Text(
                              '好的，小豬幫我收進回憶錄',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),

                const SizedBox(height: 8),

                // 重新錄音文字按鈕
                Center(
                  child: TextButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () {
                            setState(() {
                              _hasRecorded = false;
                              _isRecording = false;
                            });
                          },
                    icon: const Icon(Icons.refresh_rounded,
                        size: 16, color: Color(0xFF78350F)),
                    label: Text(
                      '想重講一段？按這裡重新錄音',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF78350F),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
