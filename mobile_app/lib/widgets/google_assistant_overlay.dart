import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../services/api_service.dart';

/// Uban 專屬全域長輩 AI 語音助理彈出視窗與服務
class GoogleAssistantOverlay extends StatefulWidget {
  final String userName;
  final String aiName;
  final int userId;
  final String? initialPrompt;

  const GoogleAssistantOverlay({
    super.key,
    required this.userName,
    required this.aiName,
    required this.userId,
    this.initialPrompt,
  });

  /// 靜態便利方法：開啟 Uban AI 助理 BottomSheet 視窗
  static Future<void> show(
    BuildContext context, {
    required String userName,
    required String aiName,
    required int userId,
    String? initialPrompt,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => GoogleAssistantOverlay(
        userName: userName,
        aiName: aiName,
        userId: userId,
        initialPrompt: initialPrompt,
      ),
    );
  }

  @override
  State<GoogleAssistantOverlay> createState() => _GoogleAssistantOverlayState();
}

class _GoogleAssistantOverlayState extends State<GoogleAssistantOverlay>
    with SingleTickerProviderStateMixin {
  final FlutterTts _flutterTts = FlutterTts();
  final SpeechToText _speechToText = SpeechToText();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late AnimationController _waveController;

  bool _isListening = false;
  bool _isThinking = false;
  bool _speechReady = false;
  final List<Map<String, String>> _dialogHistory = [];

  @override
  void initState() {
    super.initState();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _initTtsAndGreeting();
    _initSpeech();
  }

  /// 初始化 TTS 並自動播報首句 "怎麼了嗎 宇璿"
  Future<void> _initTtsAndGreeting() async {
    try {
      await _flutterTts.setLanguage("zh-TW");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ],
      );

      final greeting = "怎麼了嗎 ${widget.userName}";
      setState(() {
        _dialogHistory.add({"role": "assistant", "text": greeting});
      });

      await _flutterTts.speak(greeting);

      // 如果有初始語意請求，自動發送
      if (widget.initialPrompt != null && widget.initialPrompt!.isNotEmpty) {
        _processUserQuery(widget.initialPrompt!);
      }
    } catch (e) {
      debugPrint("🤖 [UbanAssistant] TTS init error: $e");
    }
  }

  /// 初始化 ASR 語音辨識
  Future<void> _initSpeech() async {
    try {
      _speechReady = await _speechToText.initialize(
        onError: (val) => debugPrint('🤖 [ASR Error] $val'),
        onStatus: (status) {
          debugPrint('🤖 [ASR Status] $status');
          if (status == 'done' || status == 'notListening') {
            if (mounted && _isListening) {
              setState(() => _isListening = false);
            }
          }
        },
      );
    } catch (e) {
      debugPrint('🤖 [ASR Init Exception] $e');
    }
  }

  /// 開始語音聆聽
  Future<void> _startListening() async {
    if (!_speechReady) {
      _speechReady = await _speechToText.initialize();
    }
    if (_speechReady && !_isListening) {
      setState(() {
        _isListening = true;
      });
      await _speechToText.listen(
        localeId: 'zh_TW',
        onResult: (result) {
          setState(() {
            _textController.text = result.recognizedWords;
          });
          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            _stopListeningAndSend();
          }
        },
      );
    }
  }

  /// 停止語音並發送至 AI
  Future<void> _stopListeningAndSend() async {
    if (_isListening) {
      await _speechToText.stop();
      setState(() => _isListening = false);
    }
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      _processUserQuery(text);
    }
  }

  /// 處理使用者提問
  Future<void> _processUserQuery(String query) async {
    if (query.isEmpty || _isThinking) return;

    await _flutterTts.stop();

    setState(() {
      _dialogHistory.add({"role": "user", "text": query});
      _textController.clear();
      _isThinking = true;
    });

    _scrollToBottom();

    try {
      String fullResponse = '';
      bool firstChunk = true;

      // 呼叫 ApiService.aiChatStream (Stream<String>)
      await for (final token in ApiService.aiChatStream(widget.userId, query)) {
        if (!mounted) return;
        setState(() {
          if (firstChunk) {
            _isThinking = false;
            fullResponse = token;
            _dialogHistory.add({"role": "assistant", "text": fullResponse});
            firstChunk = false;
          } else {
            fullResponse += token;
            if (_dialogHistory.isNotEmpty &&
                _dialogHistory.last["role"] == "assistant") {
              _dialogHistory.last["text"] = fullResponse;
            }
          }
        });
        _scrollToBottom();
      }

      if (fullResponse.isEmpty) {
        // Fallback for empty stream reply
        fullResponse = "好的 ${widget.userName}，我在這裡！有什麼我可以為您服務的嗎？";
        setState(() {
          _isThinking = false;
          _dialogHistory.add({"role": "assistant", "text": fullResponse});
        });
      }

      // 朗讀 AI 回覆
      await _flutterTts.speak(fullResponse);
    } catch (e) {
      debugPrint("🤖 [UbanAssistant] Query Error: $e");
      final errReply = "抱歉 ${widget.userName}，網路連線稍微有點狀況，請再跟我說一次喔！";
      setState(() {
        _isThinking = false;
        _dialogHistory.add({"role": "assistant", "text": errReply});
      });
      await _flutterTts.speak(errReply);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _flutterTts.stop();
    _speechToText.stop();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A), // Uban 獨特夜空藍黑奢華風格
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 30,
            spreadRadius: 6,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 頂部 Handle 條與標題
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.graphic_eq_rounded,
                          color: Color(0xFF38BDF8),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Uban AI 陪伴助理 • ${widget.aiName}',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 🤖 Uban 專屬動態極光音波脈衝 (Cyber Aurora Waveform)
              _buildUbanPulseEqualizer(),

              const SizedBox(height: 20),

              // 對話區域
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.18),
                  ),
                ),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final msg in _dialogHistory)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Align(
                            alignment: msg["role"] == "user"
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: msg["role"] == "user"
                                    ? const Color(0xFF0EA5E9)
                                    : Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                msg["text"] ?? '',
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_isThinking)
                        Row(
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${widget.aiName} 思考中…',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 16,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 快捷推薦 Card Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildChip('☀️ 今天台北天氣如何？'),
                    const SizedBox(width: 8),
                    _buildChip('📰 讀最新的重點新聞'),
                    const SizedBox(width: 8),
                    _buildChip('🎵 想聽輕鬆老歌'),
                    const SizedBox(width: 8),
                    _buildChip('💬 陪我聊聊天'),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 輸入欄位與麥克風按鈕
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      style: GoogleFonts.notoSansTc(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                      decoration: InputDecoration(
                        hintText: _isListening
                            ? '正在聆聽您的呼叫…'
                            : '跟 ${widget.aiName} 說點什麼…',
                        hintStyle: GoogleFonts.notoSansTc(
                          color: Colors.white54,
                          fontSize: 16,
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (val) => _processUserQuery(val),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Send or Mic button
                  GestureDetector(
                    onTap: _isListening
                        ? _stopListeningAndSend
                        : () {
                            if (_textController.text.trim().isNotEmpty) {
                              _processUserQuery(_textController.text.trim());
                            } else {
                              _startListening();
                            }
                          },
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isListening
                              ? [const Color(0xFFEF4444), const Color(0xFFF87171)]
                              : [const Color(0xFF38BDF8), const Color(0xFF0284C7)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_isListening
                                    ? Colors.redAccent
                                    : const Color(0xFF38BDF8))
                                .withValues(alpha: 0.4),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isListening
                            ? Icons.mic
                            : (_textController.text.trim().isNotEmpty
                                ? Icons.send
                                : Icons.mic_none),
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Uban 專屬動態極光音波脈衝 (Cyber Aurora Waveform)
  Widget _buildUbanPulseEqualizer() {
    final colors = [
      const Color(0xFF38BDF8), // Cyan
      const Color(0xFF10B981), // Emerald
      const Color(0xFF14B8A6), // Teal
      const Color(0xFFF59E0B), // Amber
      const Color(0xFF14B8A6), // Teal
      const Color(0xFF10B981), // Emerald
      const Color(0xFF38BDF8), // Cyan
    ];

    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 光芒 AI 核心波點
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.8),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // 7 條漸變動態音波等化器
              ...List.generate(7, (index) {
                final factor = (index == 3) ? 1.0 : (index == 2 || index == 4 ? 0.75 : 0.5);
                final phase = (index * 0.2);
                final rawVal = (math.sin((_waveController.value * math.pi * 2) + phase) + 1) / 2;
                final height = 8.0 + (rawVal * 24.0 * factor);

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 6,
                  height: height,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        colors[index],
                        colors[index].withValues(alpha: 0.4),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: colors[index].withValues(alpha: 0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(width: 16),
              // 右側對稱 AI 核心波點
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.8),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChip(String label) {
    return GestureDetector(
      onTap: () {
        final cleanPrompt = label.substring(2).trim();
        _processUserQuery(cleanPrompt);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansTc(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}
