import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/stt_locale.dart';
import 'global_assistant_button.dart';

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
      // ★ 第五十一輪：助理面板自己撐開時，全域浮動麥克風鈕讓位，不要疊在面板上。
      builder: (ctx) => AssistantHiddenZone(
        child: GoogleAssistantOverlay(
          userName: userName,
          aiName: aiName,
          userId: userId,
          initialPrompt: initialPrompt,
        ),
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

  /// 第五十三輪新增：語音辨識出「最終結果」後，是否正在等待長輩親自確認
  /// （true 時 build() 會在輸入列上方插入 _buildVoiceConfirmPanel()，顯示
  /// 「送出」／「重新說一次」兩個大按鈕）。
  ///
  /// ⚠️ 背景：語音輸入的偵測精度過低（連年輕人使用也常誤辨識），辨識一
  /// 結束就自動送出等於把辨識錯誤直接發給 AI，長輩完全沒有機會看到、
  /// 更沒機會修正——這是本輪回報的最大問題。修法是把「聆聽結束」與
  /// 「真的送出」拆成兩個獨立步驟，中間插入這個確認狀態。
  bool _awaitingVoiceConfirm = false;

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
        // 單純呼叫喚醒詞（如「Hey 嘎蛙」），播報完後才自動開啟麥克風聆聽長輩說話。
        //
        // ⚠️ 第五十二輪修正：原本這裡自己 setCompletionHandler，又另外排一個
        // Future.delayed(2500ms) 當「兜底」跟它賽跑——上面 setSpeechRate(0.5)
        // 把語速放慢一半，一句「怎麼了嗎 ○○」常常講不完 2.5 秒，兜底計時器
        // 先到、就在助理還在講話時判定「講完了」而開啟麥克風，把喇叭外放的
        // 「怎麼了嗎」錄進自己的麥克風，STT 精度又低，於是被誤辨識成長輩
        // 說的話（使用者回報的「怎麼了媽媽」正是這樣來的——本質是聽到自己）。
        // 改用既有的 _speakAndWait()：completion／error handler 雙保險 + 8
        // 秒逾時兜底，只有一條路徑會判定「講完了」，不會有兩個計時器互相
        // 賽跑；它內部也已經加了「念之前先關麥克風」的對稱防呆（見下方）。
        await _speakAndWait(greeting);
        if (mounted && !_isThinking && !_isListening) {
          _startListening();
        }
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
              // ⚠️ 第五十三輪：這裡是「引擎自行判定聆聽結束」的路徑（例如
              // pauseFor 逾時、長輩停頓過久），跟 onResult 的 finalResult
              // 分支是兩條各自獨立的觸發路徑——先前兩條都直接呼叫
              // _processUserQuery，只堵住其中一條，語音精度不足時仍會從
              // 這裡自動送出、繞過確認畫面。統一改走 _enterVoiceConfirm()，
              // 交給長輩看過文字、按下「送出」才會真的問 AI。
              final text = _textController.text.trim();
              if (text.isNotEmpty && !_isThinking) {
                _enterVoiceConfirm();
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
    // ⚠️ 第五十二輪：開始聽之前先確保 TTS 真的停了——不管是自動流程還是
    // 長輩手動點麥克風鈕觸發，都不該讓「助理還在講話」與「麥克風同時開著」
    // 同時成立，否則喇叭外放的助理語音會被自己的麥克風錄進去、誤判成長輩
    // 說的話（見 _speakAndWait 的對稱防呆）。
    await _flutterTts.stop();
    if (!_speechReady) {
      _speechReady = await _speechToText.initialize();
    }
    if (_speechReady && !_isListening) {
      setState(() {
        _isListening = true;
        // 開始新一輪聆聽時，把上一輪殘留的確認區塊（若有）一併收起，避免
        // 舊的辨識文字跟新一輪的聆聽狀態同時顯示、讓長輩搞不清楚在確認哪句話。
        _awaitingVoiceConfirm = false;
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
            // ⚠️ 第五十三輪：語音輸入的偵測精度過低（即使年輕人使用也常誤
            // 辨識），辨識結束不能直接送出——改成停止聆聽、把文字留在輸入框
            // 讓長輩看過，交給 _buildVoiceConfirmPanel() 的「送出」／
            // 「重新說一次」兩個大按鈕決定下一步，不在這裡直接呼叫 AI。
            _stopListeningForConfirm();
          }
        },
      );
    }
  }

  /// 停止語音聆聽，轉入「確認區塊」等待長輩確認或重新說一次。
  ///
  /// 第五十三輪：取代原本聆聽結束就直接送出的 _stopListeningAndSend()——
  /// 語音辨識精度不足以在沒有人工確認的情況下就直接發給 AI。這裡同時是
  /// 「onResult 收到 finalResult」與「長輩聆聽中手動點麥克風鈕提前停止」
  /// 兩種情境的共用進入點（見下方 build() 內的送出/麥克風鈕）。
  Future<void> _stopListeningForConfirm() async {
    if (_isListening) {
      await _speechToText.stop();
      if (mounted) setState(() => _isListening = false);
    }
    _enterVoiceConfirm();
  }

  /// 把輸入框裡目前的辨識文字轉為「等待確認」狀態，交給
  /// _buildVoiceConfirmPanel() 的「送出」／「重新說一次」讓長輩決定下一步。
  /// 刻意不在這裡呼叫 _processUserQuery——這正是本輪要修的「誤辨識也會
  /// 自動送出」問題的關鍵分界點。
  void _enterVoiceConfirm() {
    if (!mounted) return;
    final text = _textController.text.trim();
    if (text.isEmpty || _isThinking) return;
    setState(() => _awaitingVoiceConfirm = true);
  }

  /// 確認區塊「送出」：長輩確認辨識文字無誤，這時才真的送出去問 AI。
  void _confirmVoiceInput() {
    final text = _textController.text.trim();
    setState(() => _awaitingVoiceConfirm = false);
    if (text.isNotEmpty) {
      _processUserQuery(text);
    }
  }

  /// 確認區塊「重新說一次」：清空辨識錯誤（或長輩不滿意）的文字，重新開始聆聽。
  Future<void> _retryVoiceInput() async {
    setState(() {
      _awaitingVoiceConfirm = false;
      _textController.clear();
    });
    await _startListening();
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
    // ⚠️ 第五十二輪：開口念之前先確保麥克風是關的——TTS 播放期間如果 STT
    // 還開著，喇叭外放的內容會被自己的麥克風錄進去，變成聽自己講話
    // （見 _initTtsAndGreeting 的說明）。這裡是唯一的「開口念」入口，把
    // 防呆放在這裡，往後不管哪個呼叫端要念話都自動受保護。
    if (_isListening) {
      await _speechToText.stop();
      if (mounted) setState(() => _isListening = false);
    }

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
    // ⚠️ 第五十二輪：送出提問前也把麥克風真的關掉——稍後 AI 回覆的 TTS
    // 開始播放時，如果聆聽還沒關（例如打字送出時剛好還沒收到 STT 的
    // done 回呼），就會把自己的回覆錄進自己的麥克風。
    if (_isListening) {
      await _speechToText.stop();
      if (mounted) setState(() => _isListening = false);
    }

    setState(() {
      _dialogHistory.add({"role": "user", "text": query});
      _textController.clear();
      _isThinking = true;
      // 第五十三輪：不管從哪個入口送出（確認區塊／既有送出鈕／打字
      // onSubmitted／快捷 chip），一旦真的送出就收起確認區塊，避免殘留。
      _awaitingVoiceConfirm = false;
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

              // 第五十三輪：語音辨識出最終結果後的確認區塊，插在快捷 chip
              // 與輸入列之間；下方的 TextField 仍可直接用鍵盤修改文字。
              if (_awaitingVoiceConfirm) ...[
                _buildVoiceConfirmPanel(),
                const SizedBox(height: 16),
              ],

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
                        ? _stopListeningForConfirm
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

  /// 語音辨識完成後的確認區塊——第五十三輪新增。
  ///
  /// 用大字級＋ElderScale.buttonHeight（長輩端統一的大按鈕高度）讓長輩一眼
  /// 看懂「這是我剛剛說的話嗎」，並給「送出」／「重新說一次」兩個選擇；
  /// 辨識到的文字本身仍留在上方可編輯的 TextField 中，長輩也可以直接用
  /// 鍵盤修改後再按送出，不必整句重講。
  Widget _buildVoiceConfirmPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.45),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.hearing_rounded, color: Color(0xFF10B981), size: 26),
              const SizedBox(width: 10),
              // 文案刻意具體（「我聽到您說的是上面這句話，這樣對嗎？」），
              // 不用「確認送出」這類抽象詞——長輩要判斷的是「這句話對不
              // 對」，不是理解一個操作術語。固定字串，仍包 Expanded／
              // overflow 是比照本檔其他標題列的一貫寫法（鐵律 #14）。
              Expanded(
                child: Text(
                  '我聽到您說的是上面這句話，這樣對嗎？',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: ElderScale.buttonHeight,
                  child: OutlinedButton.icon(
                    onPressed: _retryVoiceInput,
                    icon: const Icon(Icons.mic_rounded, size: 26),
                    label: Text(
                      '重新說一次',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: ElderScale.buttonHeight,
                  child: ElevatedButton.icon(
                    onPressed: _confirmVoiceInput,
                    icon: const Icon(Icons.send_rounded, size: 26),
                    label: Text(
                      '送出',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
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
}
