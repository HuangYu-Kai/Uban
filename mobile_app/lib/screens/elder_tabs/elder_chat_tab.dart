import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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

class _ElderChatTabState extends State<ElderChatTab> {
  bool _isRecording = false;

  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final ScrollController _scrollController = ScrollController(); // 控制聊天捲動
  bool _speechEnabled = false;
  final List<Map<String, dynamic>> _messages =
      []; // 儲存對話歷史 [{role: 'user', text: '...'}, {role: 'ai', text: '...'}]
  String _lastWords = '';
  bool _isAILoading = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initTts();
  }

  void _initTts() async {
    await _flutterTts.setLanguage("zh-TW");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _speak(String text) async {
    if (text.isNotEmpty) {
      await _flutterTts.speak(text);
    }
  }

  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onStatus: (status) => debugPrint('Speech status: $status'),
        onError: (errorNotification) =>
            debugPrint('Speech error: $errorNotification'),
      );
      setState(() {});
    } catch (e) {
      debugPrint('Speech init failed: $e');
    }
  }

  void _startListening() async {
    if (!_speechEnabled) {
      debugPrint('Speech not enabled!');
      return;
    }

    setState(() {
      _lastWords = ''; // 清空上次結果
    });

    try {
      await _speechToText.listen(
        onResult: (result) {
          debugPrint(
            'Speech result: ${result.recognizedWords} (final: ${result.finalResult})',
          );
          setState(() {
            _lastWords = result.recognizedWords;
          });
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        localeId: "zh-TW",
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
      setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('Error starting speech: $e');
    }
  }

  void _stopListening({bool shouldSend = true}) async {
    await _speechToText.stop();
    setState(() => _isRecording = false);

    if (shouldSend && _lastWords.trim().isNotEmpty) {
      _sendToAIChat(_lastWords);
    } else if (!shouldSend) {
      // 如果是取消，清空文字避免下次殘留
      setState(() => _lastWords = '');
    }
  }

  Future<void> _sendToAIChat(String message) async {
    if (message.trim().isEmpty) return;

    setState(() {
      _isAILoading = true;
      // 將使用者的話加入清單
      _messages.add({"role": "user", "text": message});
    });

    try {
      final String apiUrl = "${ApiService.baseUrl}/ai/chat";

      final response = await http
          .post(
            Uri.parse(apiUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"user_id": widget.userId, "message": message}),
          )
          .timeout(const Duration(seconds: 90)); // 提升至 90 秒超時，給 Agent 更多思考時間

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply = data['reply'] ?? '沒有回應';
        setState(() {
          // 將 AI 的話加入清單
          _messages.add({"role": "ai", "text": reply});
          _lastWords = ''; // 成功發送後清理，確保 UI 不會殘留紅字
        });
        _speak(reply);
      } else {
        setState(() {
          _messages.add({"role": "ai", "text": "對不起，我現在有點忙，請等一下再跟我說。"});
        });
      }
    } catch (e) {
      String errorMsg = '發生錯誤: $e';
      if (e.toString().contains('TimeoutException')) {
        errorMsg = 'AI 思考太久了，請再試一次喔！';
      }
      setState(() {
        _messages.add({"role": "ai", "text": errorMsg});
      });
    } finally {
      if (mounted) {
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
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFDFCF9), // 稍微暖色系的背景
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 1. Header 與 搜尋區
            _buildChatHeader(),

            // 2. 快捷功能 Grid
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Column(
                  children: [
                    // --- 顯示對話歷史清單 ---
                    if (_messages.isNotEmpty || _isAILoading)
                      _buildChatDialogueArea(),

                    // 如果沒有對話也沒在載入，則顯示歡迎圖示
                    if (_messages.isEmpty && !_isAILoading)
                      Column(
                        children: [
                          const Icon(Icons.search, color: Color(0xFF1E293B)),
                        ],
                      ),
                    // 如果沒有對話也沒在載入，則顯示歡迎圖示與快捷按鈕
                    if (_messages.isEmpty && !_isAILoading)
                      Column(
                        children: [
                          const Icon(
                            Icons.search,
                            size: 36,
                            color: Color(0xFF1E293B),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '有什麼想問我的嗎？',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 18,
                              color: Colors.grey,
                            ),
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
                                Colors.blue[50]!,
                                onTap: () => _sendToAIChat("幫我查查今天的農曆宜忌。"),
                              ),
                              _buildQuickActionCard(
                                '士林區\n天氣',
                                Icons.wb_sunny_rounded,
                                Colors.orange[50]!,
                                onTap: () => _sendToAIChat("現在士林區的天氣怎麼樣？"),
                              ),
                              _buildQuickActionCard(
                                '身體\n不舒服',
                                Icons.health_and_safety_rounded,
                                Colors.red[50]!,
                                onTap: () => _sendToAIChat("我現在身體有點不舒服..."),
                              ),
                              _buildQuickActionCard(
                                '這是\n詐騙嗎？',
                                Icons.verified_user_rounded,
                                Colors.green[50]!,
                                onTap: () =>
                                    _sendToAIChat("我剛剛接到一通奇怪的電話，這是詐騙嗎？"),
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            // 4. 底部輸入區域
            _buildChatInputArea(),
            const SizedBox(height: 100), // 留白給導航欄
          ],
        ),
      ),
    );
  }

  Widget _buildChatDialogueArea() {
    return Column(
      children: [
        // 遍歷所有歷史訊息
        ..._messages.map((msg) {
          final isUser = msg['role'] == 'user';
          if (isUser) {
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
                  msg['text'],
                  style: GoogleFonts.notoSansTc(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
              ),
            );
          } else {
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
                    Text(
                      msg['text'],
                      style: GoogleFonts.notoSansTc(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }),

        // AI 思考中的載入指示
        if (_isAILoading)
          Align(
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
          ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildChatHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF8DB08B), // 墨綠色系 (對應截圖)
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
        ],
      ),
    );
  }

  Widget _buildQuickActionCard(
    String title,
    IconData icon,
    Color bgColor, {
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

  Widget _buildChatInputArea() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // 「+」按鈕 (功能擴展)
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
          // 純語音控制列 (自適應高度避免溢位)
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 54),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: const Color(0xFF8DB08B).withValues(alpha: 0.2),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    if (_isRecording) {
                      _stopListening();
                    } else {
                      _startListening();
                    }
                  },
                  borderRadius: BorderRadius.circular(30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isRecording
                            ? Icons.stop_circle_rounded
                            : Icons.mic_none_rounded,
                        color: _isRecording
                            ? Colors.redAccent
                            : const Color(0xFF8DB08B),
                        size: 30,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          _isRecording
                              ? (_lastWords.isEmpty ? '正在聽...' : _lastWords)
                              : (_isAILoading ? '思考中...' : '按這裡開始說話'),
                          style: GoogleFonts.notoSansTc(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _isRecording
                                ? Colors.redAccent
                                : const Color(0xFF8DB08B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_isRecording) ...[
            const SizedBox(width: 8),
            // 取消按鈕 (當錄音中時顯示)
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
    );
  }
}
