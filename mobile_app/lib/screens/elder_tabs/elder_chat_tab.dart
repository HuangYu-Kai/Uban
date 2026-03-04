import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import '../../services/api_service.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class ElderChatTab extends StatefulWidget {
  final int userId;
  final VoidCallback onBackToHome;

  const ElderChatTab({
    super.key,
    required this.userId,
    required this.onBackToHome,
  });

  @override
  State<ElderChatTab> createState() => _ElderChatTabState();
}

class _ElderChatTabState extends State<ElderChatTab>
    with TickerProviderStateMixin {
  // --- STT ---
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isRecording = false;
  String _lastWords = '';

  // --- TTS ---
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false; // ① TTS 播放中鎖定麥克風

  // --- AI ---
  bool _isAILoading = false;

  // --- 對話 ---
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();

  // --- ④ 連續對話模式 ---
  bool _voiceLoopEnabled = false;

  // --- 聲波動畫控制器（直接初始化避免 late 熱重載問題）---
  final List<AnimationController> _waveControllers = [];
  final List<Animation<double>> _waveAnimations = [];

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initTts();
    _initWaveAnimations();
  }

  // ② 初始化聲波動畫（3 條不同頻率的波）
  void _initWaveAnimations() {
    _waveControllers.clear();
    _waveAnimations.clear();
    for (int i = 0; i < 3; i++) {
      final c = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 400 + i * 180),
      )..repeat(reverse: true);
      _waveControllers.add(c);
    }
    for (final c in _waveControllers) {
      _waveAnimations.add(
        Tween<double>(
          begin: 6.0,
          end: 28.0,
        ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
      );
    }
  }

  // ③ 初始化 TTS
  void _initTts() async {
    await _flutterTts.setLanguage("zh-TW");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  // ③ TTS 播放（用 Completer 確保 Android 也能可靠偵測播放完畢）
  Future<void> _speak(String text, {bool isStreaming = false}) async {
    final plainText = text
        .replaceAll(RegExp(r'\*+'), '')
        .replaceAll(RegExp(r'#+\s*'), '')
        .replaceAll(RegExp(r'\n+'), '，');
    if (plainText.isEmpty) return;

    final completer = Completer<void>();

    _flutterTts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    _flutterTts.setErrorHandler((_) {
      if (!completer.isCompleted) completer.complete();
    });
    _flutterTts.setCancelHandler(() {
      if (!completer.isCompleted) completer.complete();
    });

    if (mounted) setState(() => _isSpeaking = true);
    await _flutterTts.speak(plainText);

    // 等待完成，最多 60 秒防呆
    await completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {},
    );

    if (mounted && !isStreaming) {
      setState(() => _isSpeaking = false);
      // ④ 連續對話模式：TTS 播完後自動開始聆聽
      if (_voiceLoopEnabled && !_isAILoading) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted && !_isAILoading && !_isSpeaking && !_isRecording) {
          _startListening();
        }
      }
    }
  }

  // 申請麥克風權限並初始化 STT
  void _initSpeech() async {
    final status = await Permission.microphone.request();
    debugPrint('Microphone permission: $status');

    if (status.isGranted) {
      try {
        _speechEnabled = await _speechToText.initialize(
          onStatus: (sttStatus) {
            debugPrint('STT status: $sttStatus');
            // 當 STT 自動停止聆聽時 (done/notListening)
            if ((sttStatus == 'done' || sttStatus == 'notListening') &&
                _isRecording) {
              // 給 onResult 一點時間處理最後的文字，然後才觸發停止
              Future.delayed(const Duration(milliseconds: 600), () {
                if (mounted && _isRecording) {
                  _stopListening();
                }
              });
            }
          },
          onError: (err) => debugPrint('STT error: $err'),
        );
      } catch (e) {
        debugPrint('STT init failed: $e');
        _speechEnabled = false;
      }
    } else {
      _speechEnabled = false;
    }
    if (mounted) setState(() {});
  }

  // ① 長按開始錄音
  void _startListening() async {
    // 思考中禁止錄音，但如果 AI 正在說話則允許打斷 (Barge-in)
    if (_isAILoading) return;

    // 清空語音佇列，避免打斷後上一句又突然開播
    _sentenceQueue.clear();

    // 如果正在說話，立即停止 TTS
    if (_isSpeaking) {
      await _flutterTts.stop();
      if (mounted) setState(() => _isSpeaking = false);
    }

    // 若 STT 未初始化，顯示提示
    if (!_speechEnabled) {
      if (mounted) {
        setState(() {
          _messages.add({"role": "ai", "text": "麥克風還沒準備好，請稍等一下再試 🎙️"});
        });
        _scrollToBottom();
      }
      return;
    }

    setState(() {
      _lastWords = '';
      _isRecording = true;
    });

    try {
      // 嘗試找到 zh-TW 語系，沒有就用裝置預設
      String? localeToUse;
      final locales = await _speechToText.locales();
      final zhTw = locales.where(
        (l) => l.localeId.contains('zh') || l.localeId.contains('cmn'),
      );
      if (zhTw.isNotEmpty) {
        localeToUse = zhTw.first.localeId;
        debugPrint('STT Locale: ${zhTw.first.localeId}');
      } else {
        debugPrint('zh-TW not found, using device default');
      }

      await _speechToText.listen(
        onResult: (result) {
          debugPrint('STT result: ${result.recognizedWords}');
          setState(() => _lastWords = result.recognizedWords);
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        localeId: localeToUse,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      debugPrint('STT listen error: $e');
      if (mounted) {
        setState(() {
          _isRecording = false;
          _messages.add({"role": "ai", "text": "語音辨識暫時有問題，可以用鍵盤輸入試試 😊"});
        });
        _scrollToBottom();
      }
    }
  }

  // ① 放開停止並發送
  void _stopListening({bool shouldSend = true}) async {
    if (!_isRecording && shouldSend) return; // 避免重複呼叫

    // 如果想要發送但目前字是空的，稍微等一下最後一批 result
    if (shouldSend && _lastWords.trim().isEmpty) {
      await Future.delayed(const Duration(milliseconds: 400));
    }

    await _speechToText.stop();
    final words = _lastWords.trim();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _lastWords = '';
      });
    }

    if (shouldSend) {
      if (_isAILoading) return; // 避免同時發送兩次

      if (words.isNotEmpty) {
        _sendToAIChat(words);
      } else {
        // ⑤ 空結果友善提示 (避免太常觸發，加上一點延遲判斷)
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted &&
              !_isAILoading &&
              !_isRecording &&
              _messages.isNotEmpty &&
              _messages.last["text"] != "我好像沒聽清楚，再說一次好嗎？😊") {
            setState(() {
              _messages.add({"role": "ai", "text": "我好像沒聽清楚，再說一次好嗎？😊"});
            });
            _scrollToBottom();
          }
        });
      }
    }
  }

  // 方案一：填補空白詞 (Filler Words)
  void _playFillerWord() async {
    final fillers = ["嗯...", "我想想喔...", "好，我聽到了...", "原來如此..."];
    fillers.shuffle();
    final filler = fillers.first;

    // 如果沒有在說話，先墊一句維持溫度
    if (!_isSpeaking && mounted) {
      setState(() => _isSpeaking = true);
      await _flutterTts.speak(filler);
      // 注意：這裡不設 _isSpeaking = false，因為馬上好戲上場
    }
  }

  // 接收到句子後的語音佇列
  final List<String> _sentenceQueue = [];
  bool _isProcessingQueue = false;

  Future<void> _processSentenceQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    while (_sentenceQueue.isNotEmpty) {
      if (!mounted) break;
      final text = _sentenceQueue.removeAt(0);
      await _speak(text, isStreaming: true);
    }

    _isProcessingQueue = false;

    if (mounted && _sentenceQueue.isEmpty && !_isAILoading) {
      setState(() => _isSpeaking = false);
      // ④ 連續對話模式：TTS 播完後自動開始聆聽
      if (_voiceLoopEnabled) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted && !_isRecording) {
          _startListening();
        }
      }
    }
  }

  Future<void> _sendToAIChat(String message) async {
    if (message.trim().isEmpty) return;

    setState(() {
      _isAILoading = true;
      _messages.add({"role": "user", "text": message});
      // 預先塞入一個空的 AI 回覆，之後靠串流更新這個 index
      _messages.add({"role": "ai", "text": ""});
    });
    _scrollToBottom();

    // 馬上播放填補詞，消除機器感
    _playFillerWord();

    try {
      final String apiUrl = "${ApiService.baseUrl}/ai/chat_stream";

      final request = http.Request('POST', Uri.parse(apiUrl))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({"user_id": widget.userId, "message": message});

      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        throw Exception('Server error: ${response.statusCode}');
      }

      int aiMsgIndex = _messages.length - 1;
      String currentParagraph = "";
      String pendingSentence = ""; // 累積到標點符號就送去念

      // 監聽 SSE (Server-Sent Events)
      await for (var bytes in response.stream.transform(utf8.decoder)) {
        if (!mounted) break;

        final lines = bytes.split('\n');
        for (var line in lines) {
          if (line.startsWith('data: ')) {
            final dataStr = line.substring(6).trim();
            if (dataStr.isEmpty) continue;

            try {
              final data = jsonDecode(dataStr);

              if (data['done'] == true) {
                // 串流結束
                if (pendingSentence.trim().isNotEmpty) {
                  _sentenceQueue.add(pendingSentence.trim());
                  _processSentenceQueue();
                }
                setState(() => _isAILoading = false);
                break;
              }

              if (data['chunk'] != null) {
                final chunk = data['chunk'] as String;
                currentParagraph += chunk;
                pendingSentence += chunk;

                // 同步將過濾後的乾淨文字顯示在畫面上，避免長輩看到奇怪的符號
                String cleanParagraph = currentParagraph.replaceAll(
                  RegExp(r'^(\*\*|\*|).*?(\*\*|\*|)[：:]\s*'),
                  '',
                );

                setState(() {
                  _messages[aiMsgIndex]["text"] = cleanParagraph;
                });
                _scrollToBottom();

                // 若遇到標點符號，把這句話推進語音佇列
                if (RegExp(r'[，。！？；,\.!\?]').hasMatch(chunk)) {
                  // 方案二：前端強制過濾 (Regex)
                  // 2. 過濾掉可能生成的角色前綴，例如「**老朋友**：」、「小美：」等
                  String cleanSentence = pendingSentence.replaceAll(
                    RegExp(r'^(\*\*|\*|).*?(\*\*|\*|)[：:]\s*'),
                    '',
                  );

                  cleanSentence = cleanSentence.trim();

                  if (cleanSentence.isNotEmpty) {
                    _sentenceQueue.add(cleanSentence);
                    _processSentenceQueue();
                  }
                  pendingSentence = "";
                }
              }
            } catch (e) {
              debugPrint("SSE JSON parse error: $e");
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Streaming error: $e");
      String errorMsg = 'AI 思考太久了，或是網路不穩，請再試一次喔！';
      setState(() {
        _isAILoading = false;
        // 把最後一個空白的 AI 訊息換成錯誤訊息
        _messages.last["text"] = errorMsg;
      });
      _speak(errorMsg);
    } finally {
      if (mounted && _isAILoading) {
        setState(() => _isAILoading = false);
        _scrollToBottom();
      }
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
    for (final c in _waveControllers) {
      c.dispose();
    }
    _scrollController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  // ─── BUILD ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFDFCF9),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildChatHeader(),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Column(
                  children: [
                    if (_messages.isNotEmpty || _isAILoading)
                      _buildChatDialogueArea(),

                    if (_messages.isEmpty && !_isAILoading) _buildWelcomeArea(),
                  ],
                ),
              ),
            ),
            _buildChatInputArea(),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  // ─── 歡迎畫面 ─────────────────────────────────────────────────────────
  Widget _buildWelcomeArea() {
    return Column(
      children: [
        const Icon(
          Icons.record_voice_over_rounded,
          size: 48,
          color: Color(0xFF8DB08B),
        ),
        const SizedBox(height: 12),
        Text(
          '有什麼想問我的嗎？',
          style: GoogleFonts.notoSansTc(fontSize: 20, color: Colors.grey),
        ),
        const SizedBox(height: 30),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 24,
          crossAxisSpacing: 24,
          children: [
            _buildQuickActionCard(
              '今日\n農曆宜忌',
              Icons.calendar_today_rounded,
              onTap: () => _sendToAIChat("幫我查查今天的農曆宜忌。"),
            ),
            _buildQuickActionCard(
              '現在\n天氣如何',
              Icons.wb_sunny_rounded,
              onTap: () => _sendToAIChat("現在外面的天氣怎麼樣？"),
            ),
            _buildQuickActionCard(
              '身體\n不舒服',
              Icons.health_and_safety_rounded,
              onTap: () => _sendToAIChat("我現在身體有點不舒服…"),
            ),
            _buildQuickActionCard(
              '這是\n詐騙嗎？',
              Icons.verified_user_rounded,
              onTap: () => _sendToAIChat("我剛剛接到一通奇怪的電話，這是詐騙嗎？"),
            ),
          ],
        ),
      ],
    );
  }

  // ─── 對話區 ───────────────────────────────────────────────────────────
  Widget _buildChatDialogueArea() {
    return Column(
      children: [
        ..._messages.map((msg) {
          final isUser = msg['role'] == 'user';
          return isUser
              ? _buildUserBubble(msg['text'])
              : _buildAIBubble(msg['text']);
        }),
        if (_isAILoading) _buildThinkingBubble(),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildUserBubble(String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 15, left: 40),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF8DB08B).withValues(alpha: 0.15),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
          ),
        ),
        child: Text(
          text,
          style: GoogleFonts.notoSansTc(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E293B),
          ),
        ),
      ),
    );
  }

  Widget _buildAIBubble(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20, right: 40),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.auto_awesome,
                  color: Color(0xFF59B294),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'AI 陪伴',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    color: const Color(0xFF59B294),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            MarkdownBody(
              data: text,
              styleSheet: MarkdownStyleSheet(
                p: GoogleFonts.notoSansTc(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                  height: 1.4,
                ),
                strong: GoogleFonts.notoSansTc(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF59B294),
                  height: 1.4,
                ),
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
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFF59B294),
              ),
            ),
            const SizedBox(width: 15),
            Text(
              '正在思考...',
              style: GoogleFonts.notoSansTc(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF59B294),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────
  Widget _buildChatHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF8DB08B),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 28,
            ),
            onPressed: widget.onBackToHome,
          ),
          const Spacer(),
          // ④ 連續對話模式 Toggle
          Row(
            children: [
              Text(
                '連續對話',
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: _voiceLoopEnabled,
                  onChanged: (v) => setState(() => _voiceLoopEnabled = v),
                  thumbColor: WidgetStateProperty.all(Colors.white),
                  activeTrackColor: const Color(0xFF3D7A60),
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── 底部輸入區（長按麥克風 + 聲波動畫）────────────────────────────────
  Widget _buildChatInputArea() {
    // 狀態判斷
    // 只在 AI 思考時才鎖定麥克風；如果正在播放 (isSpeaking)，允許長輩按住打斷
    final bool locked = _isAILoading;
    final Color micColor = locked
        ? Colors.grey
        : _isRecording
        ? Colors.redAccent
        : const Color(0xFF8DB08B);

    String statusText;
    if (_isAILoading) {
      statusText = 'AI 思考中...';
    } else if (_isSpeaking) {
      statusText = '按住可以打斷並說話';
    } else if (_isRecording) {
      statusText = _lastWords.isEmpty ? '正在聽...' : _lastWords;
    } else {
      statusText = _voiceLoopEnabled ? '連續對話已開啟，放開說話' : '按住說話，放開送出';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ② 聲波動畫（只在錄音時顯示）
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isRecording && _waveAnimations.isNotEmpty
                ? Padding(
                    key: const ValueKey('wave'),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(3, (i) {
                        return AnimatedBuilder(
                          animation: _waveAnimations[i],
                          builder: (context, child) {
                            return Container(
                              width: 8,
                              height: _waveAnimations[i].value,
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(
                                  alpha: 0.7 + i * 0.1,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            );
                          },
                        );
                      }),
                    ),
                  )
                : const SizedBox(key: ValueKey('no-wave'), height: 0),
          ),

          Row(
            children: [
              // 「+」功能按鈕（保留）
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFF8DB08B).withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 12),

              // ① 長按麥克風按鈕
              Expanded(
                child: GestureDetector(
                  onLongPressStart: (_) {
                    if (!locked) _startListening();
                  },
                  onLongPressEnd: (_) {
                    if (_isRecording) _stopListening();
                  },
                  onLongPressCancel: () {
                    if (_isRecording) _stopListening(shouldSend: false);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    constraints: const BoxConstraints(minHeight: 54),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _isRecording
                          ? Colors.redAccent.withValues(alpha: 0.08)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: micColor.withValues(alpha: 0.4),
                        width: 1.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isRecording
                              ? Icons.mic_rounded
                              : locked
                              ? Icons.lock_rounded
                              : Icons.mic_none_rounded,
                          color: micColor,
                          size: 30,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            statusText,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _isRecording
                                  ? Colors.redAccent
                                  : locked
                                  ? Colors.grey
                                  : const Color(0xFF8DB08B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 取消按鈕（錄音中才顯示）
              if (_isRecording) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _stopListening(shouldSend: false),
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.redAccent,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ─── 快捷卡片 ─────────────────────────────────────────────────────────
  Widget _buildQuickActionCard(
    String title,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 40,
                color: const Color(0xFF1E293B).withValues(alpha: 0.6),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansTc(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
