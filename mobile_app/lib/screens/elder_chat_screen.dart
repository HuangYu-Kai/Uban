import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'news_listen_player/news_listen_player_screen.dart';
import 'elder_screen.dart';

/// 長輩端「和小嘎聊天」—— AI 聊天頁（串流 + Markdown 渲染）。
///
/// - 使用 ApiService.aiChatStream 串流接收 Ollama tokens
/// - AI 回覆氣泡使用 flutter_markdown 渲染（支援粗體、條列、LaTeX）
class ElderChatScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const ElderChatScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<ElderChatScreen> createState() => _ElderChatScreenState();
}

class _ChatMessage {
  String text;
  final bool isUser;
  bool isStreaming; // AI 訊息是否還在串流中

  _ChatMessage(this.text, this.isUser, {this.isStreaming = false});
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

  @override
  void initState() {
    super.initState();
    _messages.add(_ChatMessage(
      '您好，${widget.userName}！我是小嘎 😊\n想聊什麼都可以跟我說喔～',
      false,
    ));
    _initSpeech();
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
      final stream = ApiService.aiChatStream(widget.userId, text);
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
        setState(() {
          aiMsg.isStreaming = false;
          if (aiMsg.text.isEmpty) aiMsg.text = '嗯嗯，我在聽～';
          _isThinking = false;
        });
        
        // 觸發 TTS 語音播放
        _playTts(aiMsg.text);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage('小嘎現在連不上，稍後再聊喔 🙏', false));
        _isThinking = false;
      });
    }
    _scrollToBottom();
  }

  Future<void> _playTts(String text) async {
    debugPrint('🎙️ [TTS Stream] _playTts called. Text length: ${text.length}');
    try {
      // 移除 Markdown 語法、Emoji 等，使語音朗讀順暢
      String cleanText = text
          .replaceAll(RegExp(r'\*\*|__|\*|_|#|>|`|\[|\]|\(|\)'), '')
          .replaceAll(RegExp(r'!\[.*?\]\(.*?\)|\[.*?\]\(.*?\)', caseSensitive: false), '')
          .replaceAll(RegExp(r'[\u{1F600}-\u{1F64F}|\u{1F300}-\u{1F5FF}|\u{1F680}-\u{1F6FF}|\u{2600}-\u{26FF}|\u{2700}-\u{27BF}]', unicode: true), '') // 移除 Emoji
          .trim();

      debugPrint('🎙️ [TTS Stream] Cleaned text: "$cleanText"');
      if (cleanText.isEmpty) {
        debugPrint('🎙️ [TTS Stream] Cleaned text is empty. Skipping.');
        return;
      }

      final engine = _selectedLanguage == 'taigi' ? 'yating' : 'edge';
      
      // 構建實時語音音訊串流 URL
      final baseUrl = ApiService.baseUrl;
      final encodedText = Uri.encodeComponent(cleanText);
      final streamUrl = '$baseUrl/voice/tts/stream?text=$encodedText&engine=$engine';
      
      debugPrint('🎙️ [TTS Stream] Playing via UrlSource: $streamUrl');
      
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(streamUrl));
      debugPrint('🎙️ [TTS Stream] Play method invoked successfully.');
    } catch (e) {
      debugPrint('🎙️ [TTS Stream Failed] $e');
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
      int idx = newsItems.indexWhere((it) => it['id']?.toString() == newsIdStr);
      debugPrint('🎙️ [News Match Check] targetIdStr: $newsIdStr, category: $category, foundIdx: $idx, itemsCount: ${newsItems.length}');

      if (idx == -1 && category != 'all') {
        // 2. 備援：若在指定類別中沒查到，抓取全類別新聞進行全庫比對
        debugPrint('🎙️ [News Match Check] Not found in $category, trying fallback "all"...');
        final fallbackResp = await ApiService.getNews(category: 'all', limit: 50);
        if (fallbackResp['status'] == 'success' && fallbackResp['data'] != null) {
          final fallbackItems = fallbackResp['data']['items'];
          if (fallbackItems is List) {
            final parsedFallback = fallbackItems.map((e) => Map<String, dynamic>.from(e)).toList();
            final fIdx = parsedFallback.indexWhere((it) => it['id']?.toString() == newsIdStr);
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
          _buildLanguageToggle(),
        ],
      ),
    );
  }

  Widget _buildLanguageToggle() {
    return Container(
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
                          data: msg.text.isEmpty ? ' ' : msg.text,
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
                        // 串流中：顯示打字游標動畫
                        if (msg.isStreaming)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _StreamingCursor(),
                          ),
                      ],
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
            child: _voiceMode ? _buildHoldToTalkBar() : _buildTextField(),
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
