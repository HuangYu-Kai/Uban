import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:video_player/video_player.dart';
import 'package:markdown/markdown.dart' as md;
import '../../services/api_service.dart';

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
  String? _sttLocaleToUse; // 緩存語系，避免每次按下麥克風都要搜尋

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

        // 初始化時順便找好支援的繁體語系並存起來
        if (_speechEnabled) {
          _speechToText.locales().then((locales) {
            final zhTw = locales.where(
              (l) => l.localeId.contains('zh') || l.localeId.contains('cmn'),
            );
            if (zhTw.isNotEmpty) {
              _sttLocaleToUse = zhTw.first.localeId;
              debugPrint('STT pre-cached Locale: $_sttLocaleToUse');
            } else {
              debugPrint('zh-TW not found during STT init');
            }
          });
        }
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
      await _speechToText.listen(
        onResult: (result) {
          debugPrint('STT result: ${result.recognizedWords}');
          setState(() => _lastWords = result.recognizedWords);
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        localeId: _sttLocaleToUse, // 直接使用已經挑好的語系
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
                // 第一個字進來時，就該消除「思考中」的泡泡
                if (_isAILoading) {
                  setState(() => _isAILoading = false);
                }

                final chunk = data['chunk'] as String;
                currentParagraph += chunk;
                pendingSentence += chunk;

                // 直接保留原始文字交由 Markdown 渲染。
                // (過去用來過濾角色前綴的 Regex 已移除，因會誤砍含有冒號的 url 如 https: 且後端已限制不生成前綴)
                String cleanParagraph = currentParagraph;

                setState(() {
                  _messages[aiMsgIndex]["text"] = cleanParagraph;
                });
                _scrollToBottom();

                // 若遇到標點符號，把這句話推進語音佇列
                if (RegExp(r'[，。！？；,\.!\?]').hasMatch(chunk)) {
                  // 方案二：前端強制過濾 (Regex) 已取消。
                  // 避免 `https:` 冒號前的內容被誤會是標題而被砍掉。
                  String cleanSentence = pendingSentence.trim();

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
              builders: {'img': CustomImageBuilder()},
              styleSheet: MarkdownStyleSheet(
                p: GoogleFonts.notoSansTc(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
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
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.add_rounded,
                    color: Color(0xFF8DB08B),
                    size: 30,
                  ),
                  onPressed: () {},
                ),
              ),
              const SizedBox(width: 12),

              // 麥克風按鈕
              Expanded(
                child: GestureDetector(
                  onLongPress: locked ? null : _startListening,
                  onLongPressUp: locked ? null : _stopListening,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: micColor,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        if (_isRecording)
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.3),
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isRecording
                              ? Icons.mic_rounded
                              : Icons.mic_none_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          statusText,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: const Color(0xFF8DB08B)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansTc(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 影片播放器元件 ───────────────────────────────────────────────────────────
class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerWidget({super.key, required this.videoUrl});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize()
          .then((_) {
            // Initialization complete
            setState(() {});
          })
          .catchError((err) {
            debugPrint("Video play error: $err");
            setState(() {
              _isError = true;
            });
          });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isError) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: Colors.grey[200],
        child: const Text("影片載入失敗", style: TextStyle(color: Colors.red)),
      );
    }

    if (!_controller.value.isInitialized) {
      return const Padding(
        padding: EdgeInsets.all(20.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        ),
        VideoProgressIndicator(_controller, allowScrubbing: true),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(
                _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: const Color(0xFF59B294),
                size: 30,
              ),
              onPressed: () {
                setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                });
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Markdown 多媒體擴充 ──────────────────────────────────────────────────────

class CustomImageBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final url = element.attributes['src'] ?? '';
    final alt = element.attributes['alt'] ?? '';
    if (url.isEmpty) return const SizedBox.shrink();

    // 如果 alt 或副檔名符合影片格式，則渲染影片 (利用 Markdown 圖片連結偽裝影片指令)
    if (alt == '影片' || url.toLowerCase().endsWith('.mp4')) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: VideoPlayerWidget(videoUrl: url),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[200],
              child: const Text("圖片載入失敗", style: TextStyle(color: Colors.red)),
            );
          },
        ),
      ),
    );
  }
}
