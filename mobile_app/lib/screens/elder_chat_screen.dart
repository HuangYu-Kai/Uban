import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/youtube_bubble_player.dart';
import 'news_listen_player/news_listen_player_screen.dart';
import 'elder_screen.dart';

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

  // 語音輸入與 ASR (Faster-Whisper)
  final AudioRecorder _recorder = AudioRecorder();
  bool _speechReady = false;
  bool _isListening = false;
  String _recognized = '';
  bool _voiceMode = true; // true=語音「按住說話」列，false=鍵盤輸入
  String? _recordingPath;

  // 語音播放 (TTS) 與國台語切換
  final AudioPlayer _audioPlayer = AudioPlayer();
  String _selectedLanguage = 'mandarin'; // 'mandarin' 或 'taigi'
  bool _isNavigatingToNews = false; // 防連擊鎖與載入狀態
  String _currentAppellation = ''; // 長輩/子女設定的專屬稱呼

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
      _speechReady = await _recorder.hasPermission();
      debugPrint('🎙️ [ASR Init] Microphone permission: $_speechReady');
    } catch (e) {
      debugPrint('🎙️ [ASR Init Failed] $e');
      _speechReady = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _startListening() async {
    if (_isThinking || _isListening) return;
    if (!_speechReady) {
      _speechReady = await _recorder.hasPermission();
      if (!_speechReady) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('這台裝置未授權麥克風權限，請改用打字或開啟權限喔')),
          );
        }
        return;
      }
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/temp_stt_voice.wav';
      _recordingPath = path;

      setState(() {
        _isListening = true;
        _recognized = '聆聽中，請開始說話...';
      });

      // 開始錄音 (單聲道、16kHz 最適合語音轉文字格式)
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      debugPrint('🎙️ [ASR Start] Recording started to: $path');
    } catch (e) {
      debugPrint('🎙️ [ASR Start Failed] $e');
      setState(() {
        _isListening = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('啟動錄音失敗: $e')),
        );
      }
    }
  }

  Future<void> _stopListeningAndSend() async {
    if (!_isListening) return;
    try {
      final path = await _recorder.stop();
      debugPrint('🎙️ [ASR Stop] Recording stopped. File path: $path');

      setState(() {
        _isListening = false;
        _isThinking = true; // 顯示思考中動畫
        _recognized = '';
      });

      if (path != null) {
        // 呼叫 AI Server 的 ASR (/api/voice/transcribe) 轉錄音檔
        final text = await ApiService.transcribeAudio(path);
        debugPrint('🎙️ [ASR Result] Transcribed text: $text');

        if (text != null && text.isNotEmpty) {
          setState(() {
            _controller.text = text;
            _voiceMode = false; // 自動切換為鍵盤打字模式，供使用者確認與手動送出
            _isThinking = false;
          });
        } else {
          setState(() {
            _isThinking = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('沒有聽清楚，請再試一次喔 😊')),
            );
          }
        }
      } else {
        setState(() {
          _isThinking = false;
        });
      }
    } catch (e) {
      debugPrint('🎙️ [ASR Stop Failed] $e');
      setState(() {
        _isListening = false;
        _isThinking = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('語音傳輸失敗: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    _audioPlayer.dispose();
    _controller.dispose();
    _scroll.dispose();
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

      // 2. 構建多伺服器候選位址（優先存取配置了 Yating API 金鑰的高效能 AI Hub: boyo-desktop）
      final encodedText = Uri.encodeComponent(cleanText);
      final candidateUrls = [
        'https://boyo-desktop.tail531c8a.ts.net/api/voice/tts/stream?text=$encodedText&engine=$engine',
        '${ApiService.localAiBaseUrl}/voice/tts/stream?text=$encodedText&engine=$engine',
        '${ApiService.baseUrl.replaceFirst('/api', '')}/api/voice/tts/stream?text=$encodedText&engine=$engine',
      ].toSet().toList();

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary,
                radius: 20,
                child: const Text('嘎', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              const SizedBox(width: 10),
              Text(
                '和小嘎聊天',
                style: GoogleFonts.notoSansTc(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          Row(
            children: [
              _buildLanguageToggle(key: widget.languageToggleKey),
              const SizedBox(width: 2),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.grey, size: 24),
                tooltip: '重新載入歷史紀錄',
                onPressed: _loadChatHistory,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey, size: 24),
                tooltip: '清空紀錄',
                onPressed: _clearChatHistory,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageToggle({Key? key}) {
    return Container(
      key: key,
      width: 130,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: _selectedLanguage == 'taigi'
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Container(
              width: 63,
              height: 36,
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedLanguage = 'mandarin'),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: Text(
                      '國語',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _selectedLanguage == 'mandarin'
                            ? Colors.white
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedLanguage = 'taigi'),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: Text(
                      '台語',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _selectedLanguage == 'taigi'
                            ? Colors.white
                            : Colors.grey[600],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        color: AppColors.background,
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: ListView.builder(
                      controller: _scroll,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      itemCount: _messages.length + (_isThinking ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return _buildThinkingBubble();
                        }
                        return _buildBubble(_messages[index]);
                      },
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(22),
                  topRight: const Radius.circular(22),
                  bottomLeft: Radius.circular(isUser ? 22 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              // ── 使用者訊息：純文字；AI 訊息：Markdown 渲染 ──
              child: isUser
                  ? Text(
                      msg.text,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 20,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
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
                            p: GoogleFonts.notoSansTc(
                              fontSize: 20,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                            strong: GoogleFonts.notoSansTc(
                              fontSize: 20,
                              height: 1.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                            em: GoogleFonts.notoSansTc(
                              fontSize: 20,
                              height: 1.5,
                              fontStyle: FontStyle.italic,
                              color: AppColors.textPrimary,
                            ),
                            listBullet: GoogleFonts.notoSansTc(
                              fontSize: 20,
                              height: 1.5,
                              color: AppColors.textPrimary,
                            ),
                            code: GoogleFonts.sourceCodePro(
                              fontSize: 16,
                              backgroundColor: const Color(0xFFF0F0F0),
                              color: const Color(0xFF2E7D78),
                            ),
                            h1: GoogleFonts.notoSansTc(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                            h2: GoogleFonts.notoSansTc(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                            h3: GoogleFonts.notoSansTc(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                            blockquoteDecoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: AppColors.primary,
                                  width: 4,
                                ),
                              ),
                              color: AppColors.primary.withValues(alpha: 0.06),
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
                        // 非串流中：顯示當時 TTS 朗讀純文字紀錄與再聽一次重播條
                        if (!msg.isStreaming &&
                            (msg.ttsText?.isNotEmpty == true || msg.text.isNotEmpty))
                          _buildTtsReplayBar(msg),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// AI 對話框中的語系標記與語音重播按鈕（不重複呈現文字，僅以聲音圖示提供隨時重聽）
  Widget _buildTtsReplayBar(_ChatMessage msg) {
    final bool isTaigi = msg.ttsLanguage == 'taigi';
    final bool isPlaying = msg.isPlayingAudio;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 語系標籤 (記錄當時是用台語還是國語)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isTaigi ? const Color(0xFFEA580C) : const Color(0xFF16A34A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isTaigi ? '🏮 台語' : '🗣️ 國語',
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 聲音 ICON（直接點擊播放/停止，不寫「再聽一次」文字）
          InkWell(
            onTap: () => _playOrReplayTts(msg),
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: isPlaying
                    ? const Color(0xFFFEF3C7)
                    : (isTaigi ? const Color(0xFFFFF7ED) : const Color(0xFFF0FDF4)),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isPlaying
                      ? const Color(0xFFF59E0B)
                      : (isTaigi ? const Color(0xFFFDBA74) : const Color(0xFF86EFAC)),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                isPlaying ? Icons.pause_circle_filled_rounded : Icons.volume_up_rounded,
                color: isPlaying
                    ? const Color(0xFFD97706)
                    : (isTaigi ? const Color(0xFFEA580C) : const Color(0xFF16A34A)),
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingBubble() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ThinkingDots(),
                const SizedBox(width: 8),
                Text(
                  '小嘎想想…',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        MediaQuery.of(context).viewInsets.bottom > 0 ? 12 : 120,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 切換：語音 / 鍵盤
          GestureDetector(
            key: widget.voiceToggleKey,
            onTap: () => setState(() => _voiceMode = !_voiceMode),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                _voiceMode ? Icons.keyboard_rounded : Icons.mic_none_rounded,
                color: AppColors.primaryDark,
                size: 30,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: KeyedSubtree(
              key: widget.inputAreaKey,
              child: _voiceMode ? _buildHoldToTalkBar() : _buildTextField(),
            ),
          ),
          if (!_voiceMode) ...[
            const SizedBox(width: 10),
            Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _send,
                child: const Padding(
                  padding: EdgeInsets.all(15),
                  child:
                      Icon(Icons.send_rounded, color: Colors.white, size: 30),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 「按住 說話」列
  Widget _buildHoldToTalkBar() {
    return GestureDetector(
      onLongPressStart: (_) => _startListening(),
      onLongPressEnd: (_) => _stopListeningAndSend(),
      onLongPressCancel: () => _stopListeningAndSend(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _isListening ? AppColors.primaryLight : Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          _isListening ? '放開　送出' : '按住　說話',
          style: GoogleFonts.notoSansTc(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryDark,
          ),
        ),
      ),
    );
  }

  Widget _buildTextField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _controller,
        minLines: 1,
        maxLines: 4,
        autofocus: true,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _send(),
        style: GoogleFonts.notoSansTc(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: '想跟小嘎說什麼…',
          hintStyle:
              GoogleFonts.notoSansTc(fontSize: 19, color: AppColors.textHint),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
      ),
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
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ── 三點跳動「思考中」動畫 ──
class _ThinkingDots extends StatefulWidget {
  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with TickerProviderStateMixin {
  late List<AnimationController> _ctrls;
  late List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      );
      Future.delayed(Duration(milliseconds: i * 160), () {
        if (mounted) ctrl.repeat(reverse: true);
      });
      return ctrl;
    });
    _anims = _ctrls
        .map((c) => Tween<double>(begin: 0, end: -6).animate(
              CurvedAnimation(parent: c, curve: Curves.easeInOut),
            ))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _anims[i],
          builder: (_, __) => Transform.translate(
            offset: Offset(0, _anims[i].value),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }
}
