import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../globals.dart';
import '../utils/stt_locale.dart';
import '../services/api_service.dart';
import '../services/friend_service.dart';
import '../services/api/elder_daily_question_api.dart';
import '../theme/app_theme.dart';
import '../widgets/ui/ui.dart';
import 'elder_tabs/chat/chat_widgets.dart';
import 'elder_tabs/daily_question_answer_sheet.dart';
import 'elder_tabs/elder_layout.dart';
import '../widgets/youtube_bubble_player.dart';
import 'news_listen_player/news_listen_player_screen.dart';
import 'elder_screen.dart';
import '../services/care_message_store.dart';

/// 長輩端「和小嘎聊天」—— AI 聊天頁（串流 + Markdown 渲染）。
///
/// - 使用 ApiService.aiChatStream 串流接收 Ollama tokens
/// - AI 回覆氣泡使用 flutter_markdown 渲染（支援粗體、條列、LaTeX）
class ElderChatScreen extends StatefulWidget {
  final int userId;
  final String userName;

  // ★ 第四十一輪（item 2）：新手指引用的高光目標 GlobalKey，全部選填。由
  //   上層 ElderHomeScreen 持有並傳入，傳 null 時完全不影響現有畫面。
  final GlobalKey? voiceToggleKey;
  final GlobalKey? inputAreaKey;
  final GlobalKey? languageToggleKey;

  const ElderChatScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.voiceToggleKey,
    this.inputAreaKey,
    this.languageToggleKey,
  });

  @override
  State<ElderChatScreen> createState() => _ElderChatScreenState();
}

class _ChatMessage {
  final String id;
  String text;
  final bool isUser;
  bool isStreaming; // AI 訊息是否還在串流中
  String? ttsLanguage; // 記錄發送當下的語系 ('mandarin' 或 'taigi')
  String? ttsText; // 記錄當初 TTS 實際唸出來的純淨文字
  String? ttsAudioPath; // 本地快取音檔路徑（特別是台語，存入本地，點了直接重播，免額外發送 Yating API）
  bool isPlayingAudio; // 當前是否正在播放中
  DailyQuestion? dailyQuestion; // ★ 每日一問：非 null 時氣泡下方顯示「我來回答」

  _ChatMessage(
    this.text,
    this.isUser, {
    String? id,
    this.isStreaming = false,
    this.ttsLanguage,
    this.ttsText,
    this.ttsAudioPath,
    this.isPlayingAudio = false,
  }) : id = id ?? '${DateTime.now().millisecondsSinceEpoch}_${text.hashCode.abs()}';
}

class _ElderChatScreenState extends State<ElderChatScreen> {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _isThinking = false; // 等待第一個 token 出現前的「思考中」狀態

  // 語音輸入：一律使用手機內建語音辨識（speech_to_text），不再上傳伺服器 Whisper
  final SpeechToText _speechToText = SpeechToText();
  String? _sttLocaleToUse;
  bool _pausedWakeWord = false; // 是否由本頁暫停了首頁喚醒詞監聽
  bool _speechReady = false;
  bool _isListening = false;
  String _recognized = '';
  bool _voiceMode = true; // true=語音「按住說話」列，false=鍵盤輸入

  // 語音播放 (TTS) 與國台語切換
  final AudioPlayer _audioPlayer = AudioPlayer();
  String _selectedLanguage = 'mandarin'; // 'mandarin' 或 'taigi'
  bool _isNavigatingToNews = false; // 防連擊鎖與載入狀態
  String _currentAppellation = ''; // 長輩/子女設定的專屬稱呼

  // 橡皮筋拉伸量（有正負號；見 ChatRubberBand）。(0, 0) 代表沒有拉伸。
  final ValueNotifier<({double pull, int edge})> _pull =
      ValueNotifier((pull: 0.0, edge: 0));

  @override
  void initState() {
    super.initState();
    _currentAppellation = widget.userName;
    try {
      _audioPlayer.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.none,
        ),
      ));
    } catch (_) {}

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          for (final m in _messages) {
            m.isPlayingAudio = false;
          }
        });
      }
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.stopped || state == PlayerState.completed) {
        if (mounted) {
          setState(() {
            for (final m in _messages) {
              m.isPlayingAudio = false;
            }
          });
        }
      }
    });

    _loadUserAppellation();
    _initSpeech();
    _loadChatHistory();

    // ★ 2026-09-15：小嘎主動關懷的訊息接進聊天室。
    //   關懷訊息本來就是「小嘎說的話」，放在與小嘎的聊天裡最合理，長輩
    //   不必再學一個新的地方去找。用 ValueNotifier 而非回呼欄位，才不會
    //   被其他畫面覆寫；而且本頁在 IndexedStack 中會被保活、initState 只跑
    //   一次，靠監聽才能即時接到新訊息。
    CareMessageStore.instance.latest.addListener(_onCareMessage);
  }

  /// 載入由長輩或子女設定的專屬稱呼（優先從本機快取讀取，並向後端 API 同步）
  Future<void> _loadUserAppellation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localAppellation = prefs.getString('elder_appellation') ??
          prefs.getString('user_name') ??
          prefs.getString('caregiver_name');
      if (localAppellation != null && localAppellation.trim().isNotEmpty) {
        if (mounted) {
          setState(() {
            _currentAppellation = localAppellation.trim();
          });
        }
      }

      // 從後端個人設定同步最新稱呼 (appellation)
      final profile = await ApiService.getElderProfile(widget.userId);
      if (profile['status'] == 'success' && profile['data'] != null) {
        final serverApp = profile['data']['appellation']?.toString().trim();
        if (serverApp != null && serverApp.isNotEmpty) {
          await prefs.setString('elder_appellation', serverApp);
          if (mounted) {
            setState(() {
              _currentAppellation = serverApp;
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadChatHistory() async {
    // 1. 本地 SharedPreferences 快速讀取快取 (0ms 無痛瞬間載入先前聊天紀錄)
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cached = prefs.getString('chat_history_${widget.userId}');
      if (cached != null && cached.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(cached);
        final List<_ChatMessage> localLoaded = decoded
            .map((item) => _ChatMessage(
                  item['text'] ?? '',
                  item['isUser'] == true,
                  id: item['id']?.toString(),
                  ttsLanguage: item['ttsLanguage'],
                  ttsText: item['ttsText'],
                  ttsAudioPath: item['ttsAudioPath'],
                ))
            .where((m) => m.text.isNotEmpty)
            .toList();

        if (mounted && localLoaded.isNotEmpty) {
          setState(() {
            _messages.clear();
            _messages.addAll(localLoaded);
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('⚠️ [Local ChatHistory Load Error] $e');
    }

    // 2. 異步向後端同步最新聊天歷史紀錄
    try {
      final res = await ApiService.get('/ai/history?user_id=${widget.userId}&limit=50');
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        final List<dynamic> rawMessages = res['data']['messages'] ?? [];
        if (rawMessages.isNotEmpty) {
          final List<_ChatMessage> remoteLoaded = [];
          for (var item in rawMessages) {
            final role = item['role'] ?? 'user';
            final text = item['text'] ?? '';
            if (text.isNotEmpty) {
              remoteLoaded.add(_ChatMessage(
                text,
                role == 'user',
                ttsLanguage: role == 'user' ? null : 'mandarin',
                ttsText: role == 'user' ? null : _extractCleanTtsText(text),
              ));
            }
          }
          if (mounted && remoteLoaded.isNotEmpty) {
            setState(() {
              _messages.clear();
              _messages.addAll(remoteLoaded);
            });
            _saveLocalChatHistory();
            _scrollToBottom();
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [Remote ChatHistory Load Error] $e');
    }

    if (_messages.isEmpty && mounted) {
      final name = _currentAppellation.isNotEmpty ? _currentAppellation : widget.userName;
      setState(() {
        _messages.add(_ChatMessage(
          '您好，$name！我是小嘎 😊\n想聊什麼都可以跟我說喔～',
          false,
          ttsText: '您好，$name！我是小嘎，想聊什麼都可以跟我說喔～',
          ttsLanguage: 'mandarin',
        ));
      });
    }

    // ★ 任務 D：聊天歷史載入完成後，讓小嘎在對話中自然提出回憶選題，
    // 取代原本個人分頁獨立的「小豬想聽你說」橫幅。
    await _maybeAskMemoirPrompt();
  }

  /// ★ 任務 D／2026-10-07 每日一問：把「今天的問題」（後端 GET /daily_question/today，
  /// 家人出題或題庫）自然接進 AI 聊天，以小嘎的身分附加一則訊息到 _messages，並附
  /// 「我來回答」開啟回答面板；已回答則不問。每個題目只問一次（旗標
  /// `daily_question_asked_<id>`），避免每次切分頁重問（連環彈窗回歸）。
  /// 這則訊息刻意不寫進 chat_history 快取。
  /// 小嘎主動關懷訊息抵達 → 以小嘎的身分附加一則聊天訊息，
  /// 讓長輩事後在聊天室裡找得到「今天小嘎跟我說過什麼」。
  void _onCareMessage() {
    final msg = CareMessageStore.instance.latest.value;
    if (msg == null || !mounted) return;
    // 同一則不重複加入（ValueNotifier 在相同物件時不會通知，這裡多一層防護）
    if (_messages.isNotEmpty && _messages.last.text == msg.text) return;
    setState(() {
      _messages.add(_ChatMessage(
        msg.text,
        false,
        ttsText: msg.text,
        ttsLanguage: 'mandarin',
      ));
    });
    _scrollToBottom();
    // 主動關懷屬於真的對話內容，與每日回憶選題不同，要寫進歷史保留下來。
    _saveLocalChatHistory();
  }

  Future<void> _maybeAskMemoirPrompt() async {
    try {
      // ★ 2026-10-07 每日一問：問題來源改為後端「今天的問題」（家人出題或題庫），
      // 取代本機 MemoirService 選題。已回答就不再問。
      final resolvedElderId = await FriendService.resolveMyElderId(widget.userId);
      final elderKey = resolvedElderId ?? 'elder_${widget.userId}';
      final dq = await ElderDailyQuestionApi.getToday(elderKey);
      if (!mounted || dq == null || dq.answered) return;

      // 每個題目只問一次（SharedPreferences 旗標），避免每次切分頁都重問。
      final prefs = await SharedPreferences.getInstance();
      final askedKey = 'daily_question_asked_${dq.id}';
      if (prefs.getBool(askedKey) == true) return;

      final greeting = dq.isFromFamily && dq.askedByName != null
          ? '跟您聊個天～家人 ${dq.askedByName} 想問您：${dq.question}'
          : '跟您聊個天～${dq.question}';

      setState(() {
        _messages.add(_ChatMessage(
          greeting,
          false,
          ttsText: greeting,
          ttsLanguage: 'mandarin',
        )..dailyQuestion = dq);
      });
      _scrollToBottom();

      await prefs.setBool(askedKey, true);
    } catch (e) {
      debugPrint('⚠️ [DailyQuestionPrompt] error: $e');
    }
  }

  /// ★ 每日一問：從聊天室的小嘎提問開啟同一個回答面板。
  Future<void> _openDailyAnswer(_ChatMessage msg) async {
    final dq = msg.dailyQuestion;
    if (dq == null) return;
    final elderId = await FriendService.resolveMyElderId(widget.userId) ??
        'elder_${widget.userId}';
    if (!mounted) return;
    final ok = await showDailyQuestionAnswerSheet(context,
        question: dq, elderId: elderId);
    if (!ok || !mounted) return;
    setState(() => msg.dailyQuestion = null);
    ElderDailyQuestionApi.refreshSignal.value++;
    // 走既有關懷訊息路徑；本頁的 _onCareMessage 會把它接成小嘎的一則訊息。
    await CareMessageStore.instance.add(
        text: '謝謝您分享，家人一定會很開心！', type: 'family', emotion: 'happy');
  }

  Future<void> _saveLocalChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listData = _messages
          .where((m) => !m.isStreaming && m.text.isNotEmpty)
          .map((m) => {
                'id': m.id,
                'text': m.text,
                'isUser': m.isUser,
                'ttsLanguage': m.ttsLanguage,
                'ttsText': m.ttsText,
                'ttsAudioPath': m.ttsAudioPath,
              })
          .toList();
      await prefs.setString('chat_history_${widget.userId}', jsonEncode(listData));
    } catch (e) {
      debugPrint('⚠️ [Save Local ChatHistory Error] $e');
    }
  }

  Future<void> _clearChatHistory() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空對話紀錄'),
        content: const Text('確定要清除過往的聊天紀錄嗎？清除後無法復原喔。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('確定清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('chat_history_${widget.userId}');
        await ApiService.delete('/ai/history?user_id=${widget.userId}');
        if (mounted) {
          final name = _currentAppellation.isNotEmpty ? _currentAppellation : widget.userName;
          setState(() {
            _messages.clear();
            _messages.add(_ChatMessage(
              '您好，$name！我是小嘎 😊\n已為您重置聊天紀錄，想聊什麼隨時跟我說喔～',
              false,
              ttsText: '您好，$name！我是小嘎，已為您重置聊天紀錄，想聊什麼隨時跟我說喔～',
              ttsLanguage: 'mandarin',
            ));
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已成功重置對話紀錄')),
          );
        }
      } catch (e) {
        debugPrint('⚠️ [Clear History Error] $e');
      }
    }
  }

  Future<void> _initSpeech() async {
    try {
      final status = await Permission.microphone.request();
      if (status.isGranted) {
        // 不依賴 onStatus：按住說話由按下／放開驅動；
        // 辨識器可能已被首頁喚醒詞初始化過，這裡不重設其回呼。
        _speechReady = await _speechToText.initialize(
          onError: (err) => debugPrint('🎙️ [STT error] $err'),
        );
        if (_speechReady) {
          final locales = await _speechToText.locales();
          _sttLocaleToUse = pickChineseSttLocale(locales);
          debugPrint('🎙️ [STT Init] locale -> $_sttLocaleToUse');
        }
      } else {
        _speechReady = false;
      }
    } catch (e) {
      debugPrint('🎙️ [STT Init Failed] $e');
      _speechReady = false;
    }
    if (mounted) setState(() {});
  }

  /// 還原首頁喚醒詞監聽（只在由本頁暫停時才還原）。
  void _restoreWakeWord() {
    if (_pausedWakeWord) {
      _pausedWakeWord = false;
      isMediaPlayingNotifier.value = false;
    }
  }

  Future<void> _startListening() async {
    if (_isThinking || _isListening) return;
    if (!_speechReady) {
      await _initSpeech();
      if (!_speechReady) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('這台裝置未授權麥克風權限，請改用打字或開啟權限喔')),
          );
        }
        return;
      }
    }
    if (!mounted) return;

    // 錄音期間暫停首頁喚醒詞監聽（共用同一個原生辨識器）
    _pausedWakeWord = !isMediaPlayingNotifier.value;
    if (_pausedWakeWord) isMediaPlayingNotifier.value = true;

    setState(() {
      _isListening = true;
      _recognized = '';
    });

    try {
      // ★ 2026-10-06 喚醒詞修正：SpeechToText 是單例，回呼可能還是首頁喚醒詞
      //   的；本畫面不依賴 status，改掛只印 log 的回呼，避免喚醒詞的重啟邏輯
      //   在本畫面錄音期間被觸發（錄音期間喚醒詞已由 isMediaPlayingNotifier 暫停）。
      _speechToText.errorListener =
          (err) => debugPrint('🎙️ [STT error] $err');
      _speechToText.statusListener =
          (status) => debugPrint('🎙️ [STT status] $status');
      await _speechToText.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() => _recognized = result.recognizedWords);
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        localeId: _sttLocaleToUse,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      debugPrint('🎙️ [STT Start Failed] $e');
      _restoreWakeWord();
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _recognized = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('語音辨識暫時無法使用，請改用打字')),
      );
    }
  }

  Future<void> _stopListeningAndSend() async {
    if (!_isListening) return;
    String text = '';
    try {
      // 放開瞬間最後一段結果可能還沒回來，稍等一下
      if (_recognized.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
      await _speechToText.stop();
      text = _recognized.trim();
    } catch (e) {
      debugPrint('🎙️ [STT Stop Failed] $e');
    } finally {
      _restoreWakeWord();
      if (mounted) {
        setState(() {
          _isListening = false;
          _recognized = '';
        });
      }
    }
    if (!mounted) return;
    if (text.isNotEmpty) {
      setState(() {
        _controller.text = text;
        _voiceMode = false; // 切換為鍵盤模式，供長輩確認後手動送出
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('我好像沒聽清楚，再說一次好嗎？')),
      );
    }
  }

  @override
  void dispose() {
    CareMessageStore.instance.latest.removeListener(_onCareMessage);
    _speechToText.stop();
    _restoreWakeWord();
    _audioPlayer.dispose();
    _controller.dispose();
    _scroll.dispose();
    _pull.dispose();
    super.dispose();
  }

  /// 發送訊息，使用串流接收 AI 回應
  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isThinking) return;

    setState(() {
      _messages.add(_ChatMessage(text, true));
      _isThinking = true;
      _controller.clear();
    });
    _scrollToBottom();

    // 加入一個空白的 AI 訊息泡泡，稍後會在串流中逐字填入
    final aiMsg = _ChatMessage('', false, isStreaming: true);

    try {
      final stream = ApiService.aiChatStream(
        widget.userId,
        text,
        appellation: _currentAppellation.isNotEmpty ? _currentAppellation : widget.userName,
        userName: widget.userName,
      );
      bool firstToken = true;

      await for (final token in stream) {
        if (!mounted) break;

        if (token.startsWith('[ERROR]')) {
          setState(() {
            if (firstToken) {
              _messages.add(_ChatMessage('小嘎現在連不上，稍後再聊喔 🙏', false));
            } else {
              aiMsg.text += '\n\n（連線中斷）';
              aiMsg.isStreaming = false;
            }
            _isThinking = false;
          });
          return;
        }

        if (firstToken) {
          firstToken = false;
          setState(() {
            _isThinking = false;
            _messages.add(aiMsg); // 首個 token 到了才把泡泡加入
          });
        }

        setState(() {
          aiMsg.text += token;
        });
        _scrollToBottom();
      }

      // 串流結束
      if (mounted) {
        final cleanText = _extractCleanTtsText(aiMsg.text);
        setState(() {
          aiMsg.isStreaming = false;
          if (aiMsg.text.isEmpty) aiMsg.text = '嗯嗯，我在聽～';
          aiMsg.ttsLanguage = _selectedLanguage; // 記錄當初 TTS 唸出來的語系 ('mandarin' 或 'taigi')
          aiMsg.ttsText = cleanText;             // 記錄當初 TTS 唸出來的純淨內容
          _isThinking = false;
        });
        
        _saveLocalChatHistory();

        // 觸發 TTS 語音播放與本機快取
        _playOrReplayTts(aiMsg);
      }
    } catch (e) {
      if (!mounted) return;
      final errorText = '小嘎現在連不上，稍後再聊喔 🙏';
      setState(() {
        _messages.add(_ChatMessage(
          errorText,
          false,
          ttsLanguage: _selectedLanguage,
          ttsText: _extractCleanTtsText(errorText),
        ));
        _isThinking = false;
      });
      _saveLocalChatHistory();
    }
    _scrollToBottom();
  }

  /// 提取純淨 TTS 朗讀文字：移除影片標籤、Markdown 語法與 Emoji
  static String _extractCleanTtsText(String text) {
    return text
        .replaceAll(RegExp(r'\[VIDEO_ID:[^\]]+\]'), '')
        .replaceAll(RegExp(r'（[^）]*?）|\([^)]*?\)'), '') // 移除舞台指示或括號口吻（如 （溫和地）、(微笑) 等）
        .replaceAll(RegExp(r'\*\*|__|\*|_|#|>|`|\[|\]'), '')
        .replaceAll(RegExp(r'!\[.*?\]\(.*?\)|\[.*?\]\(.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\u{1F600}-\u{1F64F}|\u{1F300}-\u{1F5FF}|\u{1F680}-\u{1F6FF}|\u{2600}-\u{26FF}|\u{2700}-\u{27BF}]', unicode: true), '') // 移除 Emoji
        .trim();
  }

  /// 語音播放與重播控制（包含多候選伺服器備援與台語 100% 本機快取防重複計費機制）
  Future<void> _playOrReplayTts(_ChatMessage msg) async {
    // 若當前正播放此訊息語音，點擊即停止
    if (msg.isPlayingAudio) {
      await _audioPlayer.stop();
      if (mounted) {
        setState(() {
          msg.isPlayingAudio = false;
        });
      }
      return;
    }

    final cleanText = (msg.ttsText != null && msg.ttsText!.isNotEmpty)
        ? msg.ttsText!
        : _extractCleanTtsText(msg.text);

    if (cleanText.isEmpty) {
      debugPrint('🎙️ [TTS] Cleaned text is empty. Skipping.');
      return;
    }

    // 停止其它訊息播放，並標註此訊息為播放中
    await _audioPlayer.stop();
    if (mounted) {
      setState(() {
        for (final m in _messages) {
          m.isPlayingAudio = false;
        }
        msg.isPlayingAudio = true;
      });
    }

    try {
      final lang = msg.ttsLanguage ?? _selectedLanguage;
      final engine = lang == 'taigi' ? 'yating' : 'edge';

      // 1. 優先檢查本地快取（特別是台語）
      if (msg.ttsAudioPath != null &&
          File(msg.ttsAudioPath!).existsSync() &&
          File(msg.ttsAudioPath!).lengthSync() > 0) {
        debugPrint('🎙️ [TTS Cache Hit] 命中本地快取音檔: ${msg.ttsAudioPath} (語言: $lang, 引擎: $engine)');
        await _audioPlayer.play(DeviceFileSource(msg.ttsAudioPath!));
        return;
      }

      // 2. 構建伺服器位址（第五十一輪：移除 boyo-desktop 候選——那是 Tailscale
      // MagicDNS 名稱，未加入該 tailnet 的手機在公開 DNS 上解析不到，只會白白
      // 卡到逾時才輪到下一候選；主後端已同時提供 /api/voice/tts/stream）。
      final encodedText = Uri.encodeComponent(cleanText);
      final candidateUrls = [
        '${ApiService.baseUrl.replaceFirst('/api', '')}/api/voice/tts/stream?text=$encodedText&engine=$engine',
      ];

      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/tts_cache');
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }
      final cachedFile = File('${cacheDir.path}/${lang}_${msg.id}.mp3');

      bool downloadSuccess = false;
      for (int i = 0; i < candidateUrls.length; i++) {
        final targetUrl = candidateUrls[i];
        try {
          debugPrint('🎙️ [TTS Download Attempt ${i + 1}] ($lang / $engine) -> $targetUrl');
          final response = await http.get(Uri.parse(targetUrl)).timeout(const Duration(seconds: 30));
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            await cachedFile.writeAsBytes(response.bodyBytes);
            downloadSuccess = true;
            debugPrint('🎙️ [TTS Download Success] 成功存入本地快取: ${cachedFile.path} (${response.bodyBytes.length} bytes)');
            break;
          } else {
            debugPrint('⚠️ [TTS Download] 伺服器返回空音檔 (HTTP ${response.statusCode}, bytes=${response.bodyBytes.length})，切換下一候選位址');
          }
        } catch (e) {
          debugPrint('⚠️ [TTS Download Error] $targetUrl 失敗: $e');
        }
      }

      if (downloadSuccess && cachedFile.existsSync() && cachedFile.lengthSync() > 0) {
        if (mounted) {
          setState(() {
            msg.ttsAudioPath = cachedFile.path;
          });
        } else {
          msg.ttsAudioPath = cachedFile.path;
        }
        _saveLocalChatHistory();
        debugPrint('🎙️ [TTS Play] 播放本地音檔: ${cachedFile.path}');
        await _audioPlayer.play(DeviceFileSource(cachedFile.path));
      } else {
        debugPrint('❌ [TTS Failed] 所有候選伺服器皆無法合成語音');
        if (mounted) {
          setState(() => msg.isPlayingAudio = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${lang == 'taigi' ? '台語' : '國語'}語音播放失敗，請檢查網路')),
          );
        }
      }
    } catch (e) {
      debugPrint('🎙️ [TTS Play Failed] $e');
      if (mounted) {
        setState(() => msg.isPlayingAudio = false);
      }
    }
  }

  Future<void> _handleNewsLinkClick(String linkPath) async {
    if (_isNavigatingToNews) {
      debugPrint('🎙️ [News Link Clicked] 忽略重複連擊 (Debounce Active)');
      return;
    }
    _isNavigatingToNews = true;

    // 提示長輩「載入中」以防止疑慮連擊
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Text(
              '📰 正在為您載入新聞播放器，請稍候...',
              style: GoogleFonts.notoSansTc(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    try {
      debugPrint('🎙️ [News Link Clicked] path: $linkPath');
      String category = 'all';
      String newsIdStr = linkPath.trim();
      
      if (linkPath.contains('/')) {
        final parts = linkPath.split('/');
        category = parts[0].trim();
        newsIdStr = parts[1].trim();
      }

      // 1. 優先從對應新聞類別中獲取新聞列表
      var response = await ApiService.getNews(category: category, limit: 50);
      List<Map<String, dynamic>> newsItems = [];
      if (response['status'] == 'success' && response['data'] != null) {
        final items = response['data']['items'];
        if (items is List) {
          newsItems = items.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }

      int targetIndex = 0;
      int idx = newsItems.indexWhere((it) => 
          it['id']?.toString() == newsIdStr || 
          (it['title'] != null && newsIdStr.isNotEmpty && (it['title'].toString().contains(newsIdStr) || newsIdStr.contains(it['title'].toString()))));
      debugPrint('🎙️ [News Match Check] targetIdStr: $newsIdStr, category: $category, foundIdx: $idx, itemsCount: ${newsItems.length}');

      if (idx == -1 && category != 'all') {
        // 2. 備援：若在指定類別中沒查到，抓取全類別新聞進行全庫比對
        debugPrint('🎙️ [News Match Check] Not found in $category, trying fallback "all"...');
        final fallbackResp = await ApiService.getNews(category: 'all', limit: 50);
        if (fallbackResp['status'] == 'success' && fallbackResp['data'] != null) {
          final fallbackItems = fallbackResp['data']['items'];
          if (fallbackItems is List) {
            final parsedFallback = fallbackItems.map((e) => Map<String, dynamic>.from(e)).toList();
            final fIdx = parsedFallback.indexWhere((it) => 
                it['id']?.toString() == newsIdStr || 
                (it['title'] != null && newsIdStr.isNotEmpty && (it['title'].toString().contains(newsIdStr) || newsIdStr.contains(it['title'].toString()))));
            if (fIdx != -1) {
              newsItems = parsedFallback;
              targetIndex = fIdx;
              debugPrint('🎙️ [News Match Check] Found in fallback "all" at index: $fIdx');
            }
          }
        }
      } else if (idx != -1) {
        targetIndex = idx;
      }

      debugPrint('🎙️ [News Final Navigation] Target Index: $targetIndex, Title: ${newsItems.isNotEmpty ? newsItems[targetIndex]['title'] : "N/A"}');

      // 記錄長輩新聞點閱偏好至 activity_log 以實現個人化記憶
      if (newsItems.isNotEmpty) {
        final targetNews = newsItems[targetIndex];
        final newsTitle = targetNews['title'] ?? '點閱新聞';
        ApiService.logActivity(
          widget.userId,
          'news_view',
          '【新聞點閱】類別: $category | 標題: $newsTitle',
          extraData: {'category': category, 'id': newsIdStr, 'title': newsTitle},
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NewsListenPlayerScreen(
            newsItems: newsItems.isNotEmpty
                ? newsItems
                : [
                    {'id': newsIdStr, 'title': '新聞載入中...', 'content': '請稍候...'}
                  ],
            initialIndex: targetIndex,
            userId: widget.userId,
          ),
        ),
      );
    } catch (e) {
      debugPrint('開啟新聞播放器失敗: $e');
    } finally {
      _isNavigatingToNews = false;
    }
  }

  void _handleCallLinkClick() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ElderScreen(
          roomId: widget.userId.toString(),
          deviceName: widget.userName,
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildHeader() {
    final c = UbanColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ★ 鐵律 #14：標題（28pt）與兩顆 48 寬的圖示鈕同列，標題用 Expanded 可收縮、
          // 最多兩行；國語／台語分段放在下一列，窄螢幕＋大字級也不會擠出右邊。
          Row(
            children: [
              Expanded(
                child: Text(
                  '和小嘎聊天',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(28, FontWeight.w900, c.text, height: 1.25),
                ),
              ),
              IconButton(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: Icon(Icons.refresh_rounded, color: c.text2, size: 28),
                tooltip: '重新載入歷史紀錄',
                onPressed: _loadChatHistory,
              ),
              IconButton(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: Icon(Icons.delete_outline_rounded,
                    color: c.text2, size: 28),
                tooltip: '清空紀錄',
                onPressed: _clearChatHistory,
              ),
            ],
          ),
          const SizedBox(height: 6),
          _buildLanguageToggle(key: widget.languageToggleKey),
        ],
      ),
    );
  }

  /// 國語／台語分段（設計稿 `.langseg`）。切換仍只是改 [_selectedLanguage]，
  /// 後續送出與 TTS 讀的是同一個欄位。
  Widget _buildLanguageToggle({Key? key}) {
    return ChatLangSeg(
      key: key,
      labels: const ['國語', '台語'],
      index: _selectedLanguage == 'taigi' ? 1 : 0,
      onChanged: (i) =>
          setState(() => _selectedLanguage = i == 1 ? 'taigi' : 'mandarin'),
    );
  }

  /// 橡皮筋：只在捲到頂再往下拉、或捲到底再往上拉（BouncingScrollPhysics 產生超出量）
  /// 時才算出拉伸量，正常捲動時恆為 (0, 0)。公式見 [ChatRubberBand]。
  bool _onChatScroll(ScrollNotification n) {
    if (n.depth != 0 || reduceMotion(context)) return false;
    final m = n.metrics;
    final v = ChatRubberBand.fromMetrics(
      pixels: m.pixels,
      minScrollExtent: m.minScrollExtent,
      maxScrollExtent: m.maxScrollExtent,
    );
    if (v == _pull.value) return false;
    // 版面計算階段送出的捲動通知（例如內容變短）不能立刻通知 ValueListenableBuilder
    // 重建，延到這一幀結束再更新。
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pull.value = v;
      });
    } else {
      _pull.value = v;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final total = _messages.length + (_isThinking ? 1 : 0);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ColoredBox(
        color: c.bg,
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: Stack(
                      children: [
                        NotificationListener<ScrollNotification>(
                          onNotification: _onChatScroll,
                          child: ListView.builder(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics()),
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                            itemCount: total,
                            itemBuilder: (context, index) {
                              final Widget item = index == _messages.length
                                  ? _buildThinkingBubble()
                                  : _buildBubble(_messages[index]);
                              return ChatPullItem(
                                index: index,
                                count: total,
                                pull: _pull,
                                child: item,
                              );
                            },
                          ),
                        ),
                        // 標題下、輸入列上的漸層遮底：泡泡靠近時淡出到背景色。
                        const ChatEdgeFade(atTop: true, height: 18),
                        const ChatEdgeFade(atTop: false, height: 30),
                      ],
                    ),
                  ),
                  _buildInputBar(),
                ],
              ),
              if (_isListening) _buildListeningOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // 錄音中：上方即時顯示辨識到的字，下方麥克風 + 放開送出
  Widget _buildListeningOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          child: Column(
            children: [
              // 上方：即時辨識文字大氣泡
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 60, 28, 0),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 90),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF95EC69), // WeChat 綠
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _recognized.isEmpty ? '請開始說話…' : _recognized,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                      color: _recognized.isEmpty
                          ? Colors.black45
                          : Colors.black87,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // 下方：麥克風 + 放開送出
              const Icon(Icons.graphic_eq_rounded,
                  color: Colors.white, size: 64),
              const SizedBox(height: 14),
              Text(
                '放開　送出給小嘎',
                style: GoogleFonts.notoSansTc(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(_ChatMessage msg) {
    final c = UbanColors.of(context);
    final isUser = msg.isUser;

    // --- [YouTube 影片 ID 偵測與提煉] ---
    final tagMatch = RegExp(r'\[VIDEO_ID:([^\]]+)\]').firstMatch(msg.text);
    final urlRegex = RegExp(
        r'https?:\/\/(?:www\.)?(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/|youtube\.com\/v\/)([\w-]{11})');
    final urlMatch = urlRegex.firstMatch(msg.text);

    String? videoId;
    String displayLine = msg.text;

    if (tagMatch != null) {
      videoId = tagMatch.group(1);
      displayLine = displayLine.replaceAll(tagMatch.group(0)!, '').trim();
    } else if (urlMatch != null) {
      videoId = urlMatch.group(1);
    }

    TextStyle md(double size, FontWeight w, {FontStyle? italic}) => ubanText(
          size,
          w,
          c.text,
          height: 1.5,
        ).copyWith(fontStyle: italic);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ChatBubbleFrame(
        isUser: isUser,
        // ── 使用者訊息：純文字；AI 訊息：Markdown 渲染 ──
        child: isUser
            ? Text(
                msg.text,
                style: ubanText(20, FontWeight.w600, c.onBrand, height: 1.5),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: displayLine.isEmpty ? ' ' : displayLine,
                    onTapLink: (text, href, title) {
                      debugPrint('🔗 [Markdown Link Tapped] text: $text, href: $href');
                      if (href != null) {
                        if (href.startsWith('news://')) {
                          final newsIdStr = href.replaceFirst('news://', '');
                          _handleNewsLinkClick(newsIdStr);
                        } else if (href.contains('news') && href.contains('id=')) {
                          final uri = Uri.tryParse(href);
                          final newsIdStr = uri?.queryParameters['id'] ?? '';
                          _handleNewsLinkClick(newsIdStr);
                        } else if (href.startsWith('call://')) {
                          _handleCallLinkClick();
                        }
                      }
                    },
                    styleSheet: MarkdownStyleSheet(
                      p: md(20, FontWeight.w500),
                      strong: md(20, FontWeight.w800),
                      em: md(20, FontWeight.w500, italic: FontStyle.italic),
                      // 設計稿 `.bub .link`：連結用 brandStrong 粗體。
                      a: ubanText(20, FontWeight.w700, c.brandStrong,
                              height: 1.5)
                          .copyWith(decoration: TextDecoration.underline),
                      listBullet: md(20, FontWeight.w500),
                      code: GoogleFonts.sourceCodePro(
                        fontSize: 18,
                        backgroundColor: c.surface2,
                        color: c.brandStrong,
                      ),
                      h1: ubanText(24, FontWeight.w900, c.text),
                      h2: ubanText(22, FontWeight.w800, c.text),
                      h3: ubanText(20, FontWeight.w700, c.text),
                      blockquoteDecoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: c.brand, width: 4),
                        ),
                        color: c.brandSoft,
                      ),
                    ),
                    softLineBreak: true,
                  ),
                  if (videoId != null && !msg.isStreaming) ...[
                    const SizedBox(height: 12),
                    YoutubeBubblePlayer(
                      key: ValueKey(videoId),
                      videoId: videoId,
                      onPlay: () {
                        debugPrint('🎥 YouTube video started playing -> Stopping TTS to release audio focus');
                        _audioPlayer.stop();
                      },
                    ),
                  ],
                  // 串流中：顯示打字游標動畫
                  if (msg.isStreaming)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _StreamingCursor(),
                    ),
                  // ★ 每日一問：小嘎的提問氣泡附「我來回答」大按鈕（開同一個回答面板）
                  if (msg.dailyQuestion != null && !msg.isStreaming) ...[
                    const SizedBox(height: 10),
                    UbanButton(
                      key: const ValueKey('chat_daily_answer'),
                      label: '我來回答',
                      icon: Icons.mic_rounded,
                      onPressed: () => _openDailyAnswer(msg),
                    ),
                  ],
                  // 非串流中：顯示當時 TTS 朗讀的語系與「再聽一次」重播鈕
                  if (!msg.isStreaming &&
                      (msg.ttsText?.isNotEmpty == true || msg.text.isNotEmpty))
                    _buildTtsReplayBar(msg),
                ],
              ),
      ),
    );
  }

  /// AI 泡泡的「再聽一次」（設計稿 `.bub .replay`），點擊仍呼叫 [_playOrReplayTts]；
  /// 同時標示當時朗讀用的是國語還是台語。
  Widget _buildTtsReplayBar(_ChatMessage msg) {
    return ChatReplayButton(
      isPlaying: msg.isPlayingAudio,
      languageLabel: msg.ttsLanguage == 'taigi' ? '台語' : '國語',
      onTap: () => _playOrReplayTts(msg),
    );
  }

  Widget _buildThinkingBubble() {
    final c = UbanColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ChatBubbleFrame(
        isUser: false,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ChatThinkingDots(),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '小嘎想想…',
                style: ubanText(18, FontWeight.w600, c.text2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return ChatInputBar(
      voiceMode: _voiceMode,
      isListening: _isListening,
      // 切換：語音 / 鍵盤
      onToggleMode: () => setState(() => _voiceMode = !_voiceMode),
      // 「按住 說話」：長按開始／結束仍是原本的錄音函式
      onHoldStart: _startListening,
      onHoldEnd: _stopListeningAndSend,
      controller: _controller,
      onSend: _send,
      bottomPadding: MediaQuery.of(context).viewInsets.bottom > 0
          ? 12
          : elderNavClearance(context),
      toggleKey: widget.voiceToggleKey,
      inputAreaKey: widget.inputAreaKey,
    );
  }
}

// ── 打字游標閃爍動畫 ──
class _StreamingCursor extends StatefulWidget {
  @override
  State<_StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<_StreamingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0, end: 1).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 10,
        height: 20,
        decoration: BoxDecoration(
          color: UbanColors.of(context).brand,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
