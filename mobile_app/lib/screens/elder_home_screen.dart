import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lunar/lunar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/api_service.dart';
import 'identification_screen.dart';

class ElderHomeScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const ElderHomeScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<ElderHomeScreen> createState() => _ElderHomeScreenState();
}

class _ElderHomeScreenState extends State<ElderHomeScreen> {
  int _selectedIndex = 0; // 0: Home/Calendar, 1: Chat, 2: Profile/Settings
  bool _isRecording = false;

  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final ScrollController _scrollController = ScrollController(); // 控制聊天捲動
  bool _speechEnabled = false;
  final List<Map<String, dynamic>> _messages =
      []; // 儲存對話歷史 [{role: 'user', text: '...'}, {role: 'ai', text: '...'}]
  String _lastWords = '';
  bool _isAILoading = false;
  late String _lunarDate;
  late String _solarTerm;
  late String _dayName;
  late String _dateStr;
  late String _monthStr;
  late String _yearStr;

  @override
  void initState() {
    super.initState();
    _updateTime();
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

  void _updateTime() {
    final now = DateTime.now();
    final lunar = Lunar.fromDate(now);

    setState(() {
      _lunarDate = "${lunar.getMonthInChinese()}月${lunar.getDayInChinese()}";
      _solarTerm = lunar.getJieQi();
      if (_solarTerm.isEmpty) {
        _solarTerm = "立春";
      }

      try {
        _dayName = DateFormat('EEEE', 'zh_TW').format(now);
        _dateStr = DateFormat('dd').format(now);
        _monthStr = DateFormat('MM月', 'zh_TW').format(now);
        _yearStr = DateFormat('yyyy').format(now);
      } catch (e) {
        debugPrint('DateFormat error: $e');
        _dayName = "星期${['一', '二', '三', '四', '五', '六', '日'][now.weekday - 1]}";
        _dateStr = now.day.toString().padLeft(2, '0');
        _monthStr = "${now.month}月";
        _yearStr = now.year.toString();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Stack(
        children: [
          // 頁面內容切換
          IndexedStack(
            index: _selectedIndex,
            children: [_buildHomeView(), _buildChatView(), _buildProfileView()],
          ),
          // 自定義浮動導覽列
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildFloatingNavBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileView() {
    return Container(
      color: const Color(0xFFF1F5F9),
      width: double.infinity,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            CircleAvatar(
              radius: 60,
              backgroundColor: const Color(0xFF59B294).withValues(alpha: 0.1),
              child: const Icon(
                Icons.person_rounded,
                size: 80,
                color: Color(0xFF59B294),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.userName,
              style: GoogleFonts.notoSansTc(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '長輩模式 (測試中)',
              style: GoogleFonts.notoSansTc(fontSize: 18, color: Colors.grey),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
              child: SizedBox(
                width: double.infinity,
                height: 70,
                child: ElevatedButton.icon(
                  onPressed: _handleLogout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.redAccent,
                    elevation: 0,
                    side: const BorderSide(color: Colors.redAccent, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 28),
                  label: Text(
                    '登出測試環境',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 80), // 避開導覽列
          ],
        ),
      ),
    );
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '切換身分',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        content: Text('確定要登出並回到身分辨識頁面嗎？', style: GoogleFonts.notoSansTc()),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              '取消',
              style: GoogleFonts.notoSansTc(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('caregiver_id');
              await prefs.remove('caregiver_name');

              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const IdentificationScreen()),
                (route) => false,
              );
            },
            child: Text(
              '登出',
              style: GoogleFonts.notoSansTc(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatView() {
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
            onPressed: () => setState(() => _selectedIndex = 0),
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

  Widget _buildHomeView() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF59B294), Color(0xFFF1F5F9)],
          stops: [0.0, 0.3],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildGreetingRow(),
                      const SizedBox(height: 20),
                      _buildCalendarCard(),
                      const SizedBox(height: 20),
                      _buildMainFeaturesRow(),
                      const SizedBox(height: 20),
                      _buildNewsSection(),
                      const SizedBox(height: 100), // 留白給浮動底部
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingNavBar() {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, Icons.home_rounded),
          _buildNavItem(1, Icons.chat_bubble_rounded),
          _buildNavItem(2, Icons.person_rounded),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, isSelected ? -15 : 0, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF59B294) : Colors.transparent,
          shape: BoxShape.circle,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF59B294).withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ]
              : [],
        ),
        child: Icon(
          icon,
          size: 32,
          color: isSelected ? Colors.white : Colors.grey[400],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const SizedBox(height: 20);
  }

  Widget _buildGreetingRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '早安！',
              style: GoogleFonts.notoSansTc(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.wb_sunny_rounded,
                    color: Colors.orange,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '超級會員',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      color: Colors.orange[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        CircleAvatar(
          radius: 35,
          backgroundImage: const NetworkImage(
            'https://i.pravatar.cc/150?u=elder',
          ), // Mock
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarCard() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Row(
        children: [
          // 左側西曆方塊
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFF59B294).withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      _monthStr,
                      style: GoogleFonts.notoSansTc(
                        color: const Color(0xFF59B294),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _yearStr,
                      style: GoogleFonts.inter(
                        color: const Color(0xFF59B294),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  _dateStr,
                  style: GoogleFonts.inter(
                    fontSize: 64,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF59B294),
                  ),
                ),
                Text(
                  _dayName,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    color: const Color(0xFF59B294),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // 右側農曆標註
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _lunarDate,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF59B294),
                  ),
                ),
                Text(
                  _solarTerm,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF59B294),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainFeaturesRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 代誌報給你知
        Expanded(
          flex: 3,
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              image: const DecorationImage(
                image: AssetImage('assets/images/newspaper.png'),
                fit: BoxFit.cover,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '代誌',
                        style: TextStyle(
                          fontFamily: 'StarPanda',
                          fontSize: 32,
                          color: const Color(0xFF334155),
                        ),
                      ),
                      Text(
                        '報給你知',
                        style: TextStyle(
                          fontFamily: 'StarPanda',
                          fontSize: 32,
                          color: const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        // 朋友
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Container(
                height: 220,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFCFEADF),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '朋友',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_circle_right,
                          color: Color(0xFF59B294),
                          size: 28,
                        ),
                      ],
                    ),
                    const Expanded(child: SizedBox()),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildFriendAvatar('GAWA'),
                          _buildFriendAvatar('倪阿恭'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFriendAvatar(String name) {
    return Column(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Colors.grey[200],
          child: const Icon(Icons.person, size: 20),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          style: GoogleFonts.notoSansTc(
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildNewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text(
                  '最新',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 20),
                Text(
                  '賽金豬',
                  style: GoogleFonts.notoSansTc(
                    color: Colors.grey,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '頭條早知道',
          style: TextStyle(
            fontFamily: 'StarPanda',
            fontSize: 40,
            color: const Color(0xFF59B294),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.newspaper,
                        color: Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '聯合新聞網',
                        style: GoogleFonts.notoSansTc(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  Text('02-05', style: GoogleFonts.inter(color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '過半台灣人想「微退休」！滙豐揭關鍵門檻：先存到 730 萬元',
                style: GoogleFonts.notoSansTc(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
