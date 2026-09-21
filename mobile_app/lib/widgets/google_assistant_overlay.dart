import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../services/api_service.dart';
import '../utils/stt_locale.dart';

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

  /// 靜態便利方法：開啟 Uban AI 助理 BottomSheet 視窗。
  ///
  /// 2026-09-16 第四十九輪 item 8：回傳型別由 `Future<void>` 改為
  /// `Future<Map<String, dynamic>?>`——純加法，既有不接回傳值的呼叫端
  /// （例如 `ai_assistant_settings_dialog.dart` 的「試用小嘎」入口）行為不變。
  /// 若長輩透過語音觸發了「幫我打電話／視訊」，關閉視窗時會帶回
  /// `{'autoCall': true, 'isVideo': bool}`；一般關閉（無撥號請求）回傳 null。
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String userName,
    required String aiName,
    required int userId,
    String? initialPrompt,
  }) async {
    return showModalBottomSheet<Map<String, dynamic>?>(
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
  // ★ 第五十一輪：改用 utils/stt_locale.dart 挑選裝置實際支援的中文語系，
  // 不再寫死 'zh_TW'（見 _initSpeech／_startListening）。
  String? _sttLocaleToUse;
  final List<Map<String, String>> _dialogHistory = [];

  @override
  void initState() {
    super.initState();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _initSpeech().then((_) {
      if (mounted) _initTtsAndGreeting();
    });
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

      // 如果有初始語意請求（如長輩一口氣問了「今天天氣如何」），自動發送
      if (widget.initialPrompt != null && widget.initialPrompt!.isNotEmpty) {
        _processUserQuery(widget.initialPrompt!);
      } else {
        // 單純呼叫喚醒詞（如「Hey 嘎蛙」），播報完後自動開啟麥克風聆聽長輩說話
        bool autoStarted = false;
        void autoStartMic() {
          if (!autoStarted && mounted && !_isThinking && !_isListening) {
            autoStarted = true;
            _startListening();
          }
        }

        _flutterTts.setCompletionHandler(() {
          autoStartMic();
        });

        await _flutterTts.speak(greeting);

        // 兜底保護：若特定裝置 TTS 未觸發 completionHandler，2.5 秒後自動啟動麥克風
        Future.delayed(const Duration(milliseconds: 2500), () {
          autoStartMic();
        });
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
              // 長輩說完停頓後自動提交已辨識的文字
              final text = _textController.text.trim();
              if (text.isNotEmpty && !_isThinking) {
                _processUserQuery(text);
              }
            }
          }
        },
      );

      // ★ 第五十一輪：列舉裝置實際支援的語系，挑出可用的中文 localeId
      // （見 utils/stt_locale.dart 說明），不再直接寫死 'zh_TW'——部分
      // Android 辨識引擎不認得這個 ID，會靜默退回英文等裝置預設語系。
      if (_speechReady) {
        final locales = await _speechToText.locales();
        _sttLocaleToUse = pickChineseSttLocale(locales);
        debugPrint('🤖 [ASR Locale] 選用語系: $_sttLocaleToUse');
      }
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
        // 使用 _initSpeech() 掃描裝置語系後選出的 ID；找不到中文語系時為
        // null，交給系統預設（見 utils/stt_locale.dart）。
        localeId: _sttLocaleToUse,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        ),
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
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

  /// [AUTO_CALL:video] / [AUTO_CALL:audio]：語音觸發自動撥號（家人，整戶響）
  /// 的動作標記，比照 ai_chat_screen.dart 對 [VIDEO_ID:xxx] 的既有處理方式
  /// （第四十九輪 item 8）。不帶人名——長輩端撥給家人本來就是整戶手機一起響，
  /// 不支援指定對象，標記裡放一個兌現不了的名字只會製造誤解。
  static final RegExp _autoCallPattern = RegExp(r'\[AUTO_CALL:(video|audio)\]');

  /// [AUTO_CALL_FRIEND:video:<elder_id>] / [AUTO_CALL_FRIEND:audio:<elder_id>]：
  /// 語音觸發指定好友撥號的動作標記（第四十九輪 item 8 好友路徑）。刻意用
  /// 跟上面完全不同的標記名稱，而不是在同一個正則裡加可選尾碼——兩個正則
  /// 互斥，各自處理固定形狀，不必讓前端判斷「這次有沒有帶尾碼」。elder_id
  /// 由後端 tools_service.py::initiate_video_call 查完好友清單、確定唯一
  /// 相符後才給，前端不做第二次名字比對，直接拿來用。
  static final RegExp _autoCallFriendPattern =
      RegExp(r'\[AUTO_CALL_FRIEND:(video|audio):([A-Za-z0-9]+)\]');

  /// 剝除兩種動作標記，避免原始標記字樣顯示在對話氣泡、或被 TTS 逐字唸出來。
  String _stripAutoCallMarker(String text) => text
      .replaceAll(_autoCallPattern, '')
      .replaceAll(_autoCallFriendPattern, '')
      .trim();

  /// 等待 TTS **真正念完**這句話才返回——僅供撥號前的確認語使用（第四十九輪
  /// item 8 補強）。`flutter_tts` 的 `speak()` 這個 Future 預設在「引擎開始
  /// 念」就完成，不是「念完」才完成；本檔 `_initTtsAndGreeting`（上方）已經
  /// 因為同一個限制改用 `setCompletionHandler` + 逾時兜底，這裡是同一問題在
  /// 撥號安全網上的版本——`_processUserQuery` 下方念完確認語才 `pop()` 的
  /// 設計，前提是「念完」真的等到念完，不能只是呼叫了 `speak()`。
  /// 刻意不用 `awaitSpeakCompletion(true)`：查過 flutter_tts 4.2.5 的
  /// Android 原生原始碼（`FlutterTtsPlugin.kt` 的 `onError`）後發現那個開關
  /// 在引擎出錯時不會釋放 pending 的 speak() Future，會讓撥號被無限期卡住，
  /// 比現在「沒念完就跳轉」更糟。改用 completionHandler／errorHandler 雙保
  /// 險＋逾時兜底，任一條路徑都能讓函式正常返回，撥號請求一定會被送出。
  Future<void> _speakAndWait(
    String text, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final completer = Completer<void>();
    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    _flutterTts.setCompletionHandler(finish);
    _flutterTts.setErrorHandler((_) => finish());
    await _flutterTts.speak(text);
    await completer.future.timeout(timeout, onTimeout: () {});
  }

  /// 處理使用者提問
  Future<void> _processUserQuery(String query) async {
    if (query.isEmpty || _isThinking) return;

    // 清除問候語 completionHandler，防止 AI 回覆完誤觸
    _flutterTts.setCompletionHandler(() {});
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
            _dialogHistory.add({
              "role": "assistant",
              "text": _stripAutoCallMarker(fullResponse),
            });
            firstChunk = false;
          } else {
            fullResponse += token;
            if (_dialogHistory.isNotEmpty &&
                _dialogHistory.last["role"] == "assistant") {
              _dialogHistory.last["text"] = _stripAutoCallMarker(fullResponse);
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

      // ★ 第四十九輪 item 8：偵測撥號動作標記。必須用「串流結束後組完的
      //   完整 fullResponse」判斷，不能逐 token 判斷——標記字樣可能被切在
      //   兩個 token 之間，逐 token 正則永遠對不上。兩個正則互斥（後端只會
      //   回傳其中一種），先查好友標記、查無再查家人標記即可。
      final friendMatch = _autoCallFriendPattern.firstMatch(fullResponse);
      final familyMatch = friendMatch == null
          ? _autoCallPattern.firstMatch(fullResponse)
          : null;
      final bool hasAutoCall = friendMatch != null || familyMatch != null;
      final bool wantsVideoCall =
          (friendMatch?.group(1) ?? familyMatch?.group(1)) == 'video';
      final String? friendElderId = friendMatch?.group(2);

      // 朗讀 AI 回覆（念剝除標記後的乾淨文字，不把標記唸出來）。好友路徑的
      // 確認語已經在後端把好友名字寫進乾淨文字裡（見 tools_service.py），
      // 這裡不需要、也不應該再自己組一句不帶名字的話蓋過去。
      // ⚠️ 有撥號標記時改走 `_speakAndWait`——單純 `await speak()` 不會等真正
      // 念完（見該函式註解），沿用它會讓下面「聽完才跳畫面」形同虛設；一般
      // 對話回覆維持原本的寫法，不需要為每一句閒聊都多等一輪逾時。
      if (hasAutoCall) {
        await _speakAndWait(_stripAutoCallMarker(fullResponse));
      } else {
        await _flutterTts.speak(_stripAutoCallMarker(fullResponse));
      }

      // ★ 念完確認語才關閉視窗並帶出撥號請求，讓長輩聽完「我幫您打電話給
      //   誰」才跳畫面，不要話講到一半人就被拉去別的畫面（上方已改用
      //   `_speakAndWait` 真正等到念完，不是只等呼叫）。實際撥出由呼叫端
      //   （elder_home_screen.dart）比照 friends_screen.dart::_startCall() /
      //   _startFriendCall() 的既有配方，透過建構 ElderScreen(autoCall:true,
      //   ...) 完成——這裡只負責回報「要不要撥、視訊還是語音、指定哪位好友」，
      //   不直接碰 Signaling。
      if (hasAutoCall && mounted) {
        Navigator.of(context).pop({
          'autoCall': true,
          'isVideo': wantsVideoCall,
          'friendElderId': friendElderId,
        });
        return;
      }
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
    _flutterTts.setCompletionHandler(() {});
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
                  // ★ AI 名稱為使用者可自訂字串，長度不定；用 Expanded 包住左側
                  //   區塊並讓標題文字省略號截斷，避免把右側關閉鈕推出螢幕。
                  Expanded(
                    child: Row(
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
                        Expanded(
                          child: Text(
                            'Uban AI 陪伴助理 • ${widget.aiName}',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
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
