import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../models/elder.dart';
import '../../services/api_service.dart';
import '../../utils/error_handler.dart';

/// 🤖 AI 照護共創助理對話視窗 (Family AI Care Co-pilot Screen) - 全新極光黑金極致 UI
class FamilyAiCopilotScreen extends StatefulWidget {
  final Elder? currentElder;

  const FamilyAiCopilotScreen({super.key, this.currentElder});

  @override
  State<FamilyAiCopilotScreen> createState() => _FamilyAiCopilotScreenState();
}

class _FamilyAiCopilotScreenState extends State<FamilyAiCopilotScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _chatMessages = [];
  bool _isSending = false;

  // 🎙️ 語音輸入（第四十九輪新增）：只把辨識結果寫回輸入框，絕不自動送出
  // ——語音可能聽錯，必須讓家屬看過文字內容、自己按送出鍵確認，否則等於
  // 讓系統代替家屬決定要建立什麼排程。
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _speechReady = false;
  bool _speechInitializing = false;

  @override
  void initState() {
    super.initState();
    final elderName = widget.currentElder?.displayName ?? '長輩';
    _chatMessages.add({
      'isUser': false,
      'text': '您好！我是您的 AI 照護共創助理 🤖\n您可以直接詢問「$elderName 今天過得怎麼樣？」，或以自然對話要我建立排程（例如：「每天早上 8 點與晚上 8 點提醒 $elderName 吃降血壓藥」）！',
      'statusSummary': null,
      'scheduleDrafts': null,
    });
  }

  @override
  void dispose() {
    _speechToText.stop();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 切換語音輸入的開始／停止。
  ///
  /// 第一次點擊才會請求麥克風權限並初始化 STT（`_speechReady` 快取結果，
  /// 之後點擊不用重新跑一次）；辨識結果只即時寫回 [_messageController]，
  /// **絕對不會**在辨識完成時自動呼叫 [_sendMessage]——語音辨識可能聽錯，
  /// 必須讓家屬自己看過文字內容、按下送出鍵確認，否則等於讓系統代替家屬
  /// 決定要建立什麼排程或問了什麼問題。
  Future<void> _toggleVoiceInput() async {
    if (_isListening) {
      await _speechToText.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    if (_isSending || _speechInitializing) return;

    if (!_speechReady) {
      _speechInitializing = true;
      try {
        final permStatus = await Permission.microphone.request();
        if (!permStatus.isGranted) {
          if (!mounted) return;
          // ★ 第五十輪（適老化）：改用統一的大字級／高對比 SnackBar 封裝，
          // 「前往設定」操作用 showWarning 的 action 參數保留下來。
          ErrorHandler.showWarning(
            context,
            permStatus.isPermanentlyDenied
                ? '尚未開啟麥克風權限，請至系統設定開啟後再試一次'
                : '需要麥克風權限才能使用語音輸入',
            action: permStatus.isPermanentlyDenied
                ? SnackBarAction(
                    label: '前往設定',
                    textColor: Colors.white,
                    onPressed: openAppSettings,
                  )
                : null,
          );
          return;
        }

        try {
          _speechReady = await _speechToText.initialize(
            onStatus: (status) {
              // 靜音一段時間後 speech_to_text 會自動停止聆聽（done/notListening），
              // 這裡只同步視覺狀態，不做任何送出動作。
              if ((status == 'done' || status == 'notListening') && _isListening && mounted) {
                setState(() => _isListening = false);
              }
            },
            onError: (err) {
              debugPrint('⚠️ [FamilyCopilot STT Error] ${err.errorMsg}');
              if (!mounted) return;
              setState(() => _isListening = false);
              // 可重試（改用打字或再試一次），非硬錯誤，用 showWarning。
              ErrorHandler.showWarning(context, '語音辨識發生錯誤，請改用打字或再試一次');
            },
          );
        } catch (e) {
          debugPrint('⚠️ [FamilyCopilot STT Init Exception] $e');
          _speechReady = false;
        }

        if (!_speechReady) {
          if (!mounted) return;
          // 裝置能力限制、可改用打字繼續完成任務，用 showWarning 而非硬錯誤。
          ErrorHandler.showWarning(context, '這台裝置目前無法使用語音輸入，請改用打字');
          return;
        }
      } finally {
        _speechInitializing = false;
      }
    }

    if (!mounted) return;
    setState(() => _isListening = true);
    await _speechToText.listen(
      localeId: 'zh_TW',
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
      ),
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      onResult: (result) {
        if (!mounted) return;
        // 只寫回輸入框、游標移到最後；不可在 result.finalResult 時自動送出。
        _messageController.value = TextEditingValue(
          text: result.recognizedWords,
          selection: TextSelection.collapsed(offset: result.recognizedWords.length),
        );
      },
    );
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

  Future<void> _sendMessage([String? presetText]) async {
    final text = (presetText ?? _messageController.text).trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    // 🔒 第四十九輪追加：後端現在會依 family_user_id 驗證家屬與長輩的綁定
    // 關係（無綁定回 404），不能再頂著寫死的 1 送出——那會讓真正的家屬
    // 全部被判定成「無權」。讀不到真實身分就 fail-closed：不送出請求、
    // 不用任何預設值頂替，比照 alert_center_screen.dart 既有慣例。
    final prefs = await SharedPreferences.getInstance();
    final familyUserId = prefs.getInt('caregiver_id');
    if (familyUserId == null) {
      if (!mounted) return;
      setState(() => _isSending = false);
      // 可重試（重新登入即可解決），用 showWarning。
      ErrorHandler.showWarning(context, '無法確認家屬身分，請重新登入後再試');
      return;
    }

    if (presetText == null) {
      _messageController.clear();
    }

    setState(() {
      _chatMessages.add({
        'isUser': true,
        'text': text,
        'statusSummary': null,
        'scheduleDrafts': null,
      });
    });
    _scrollToBottom();

    final elderName = widget.currentElder?.displayName ?? '長輩';
    final elderIdStr = widget.currentElder?.elderId ?? widget.currentElder?.id.toString() ?? '2';

    try {
      final res = await ApiService.post('/api/ai/family_copilot/chat', {
        'family_user_id': familyUserId,
        'elder_id': elderIdStr,
        'elder_name': elderName,
        'message': text,
      });

      Map<String, dynamic>? data;
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        data = Map<String, dynamic>.from(res['data']);
      } else {
        data = _generateFallbackResponse(text, elderName);
      }

      setState(() {
        _chatMessages.add({
          'isUser': false,
          'text': (data!['reply_text'] ?? '已為您處理完成！').toString(),
          'statusSummary': data['status_summary'],
          'scheduleDrafts': data['schedule_drafts'] != null ? List<dynamic>.from(data['schedule_drafts']) : null,
        });
      });
    } catch (e) {
      final fallbackData = _generateFallbackResponse(text, elderName);
      setState(() {
        _chatMessages.add({
          'isUser': false,
          'text': fallbackData['reply_text'].toString(),
          'statusSummary': fallbackData['status_summary'],
          'scheduleDrafts': fallbackData['schedule_drafts'] != null ? List<dynamic>.from(fallbackData['schedule_drafts']) : null,
        });
      });
    } finally {
      setState(() {
        _isSending = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _confirmBatchSchedule(List<dynamic> drafts, int messageIndex) async {
    final elderIdStr = widget.currentElder?.elderId ?? widget.currentElder?.id.toString() ?? '2';

    // 🔒 第四十九輪追加：family_id 同樣改讀真實家屬身分（見 _sendMessage
    // 的說明）。/api/reminder/batch_create 這支端點本身還沒有綁定驗證
    // （已回報、本輪不動），但繼續寫死 1 會讓每個家庭建立的排程全部被
    // 記成同一個假帳號建立，本身就是資料錯誤，讀不到就 fail-closed。
    final prefs = await SharedPreferences.getInstance();
    final familyUserId = prefs.getInt('caregiver_id');
    if (familyUserId == null) {
      if (!mounted) return;
      // 可重試（重新登入即可解決），用 showWarning。
      ErrorHandler.showWarning(context, '無法確認家屬身分，請重新登入後再試');
      return;
    }
    // ★ 上面 await SharedPreferences 之後才拿到 familyUserId，這裡是穿過
    // async gap 後第一次要用 context，必須補一次 mounted 檢查（analyzer
    // use_build_context_synchronously）。
    if (!mounted) return;

    // 1. 立即更新 UI 反饋，按鈕轉為成功狀態
    setState(() {
      _chatMessages[messageIndex]['isApplied'] = true;
    });

    // ★ 第五十輪（適老化）：改用統一的大字級／高對比 SnackBar 封裝。
    ErrorHandler.showSuccess(context, '已成功建立 ${drafts.length} 筆關懷排程，並同步至長輩端！');

    // 2. 背景異步同步寫入資料庫
    try {
      await ApiService.post('/api/reminder/batch_create', {
        'family_id': familyUserId,
        'elder_id': elderIdStr,
        'reminders': drafts,
      });
    } catch (e) {
      debugPrint('⚠️ 同步後端通知：$e');
    }
  }

  Map<String, dynamic> _generateFallbackResponse(String text, String elderName) {
    final isSchedule = text.contains('提醒') ||
        text.contains('吃藥') ||
        text.contains('排程') ||
        text.contains('散步') ||
        text.contains('量血壓') ||
        text.contains('看診') ||
        text.contains('記得') ||
        text.contains('點') ||
        text.contains('每天') ||
        text.contains('每週') ||
        text.contains('每日') ||
        text.contains('上午') ||
        text.contains('下午') ||
        text.contains('晚上') ||
        text.contains('早安') ||
        text.contains('呼叫') ||
        text.contains('吃') ||
        text.contains('叫');

    if (isSchedule) {
      String category = 'custom';
      if (text.contains('藥') || text.contains('血壓')) {
        category = 'medication';
      } else if (text.contains('散步') || text.contains('運動')) {
        category = 'exercise';
      } else if (text.contains('診') || text.contains('醫院')) {
        category = 'hospital';
      }

      String repeatRule = '每天';
      if (text.contains('一三五') || text.contains('一、三、五')) {
        repeatRule = '週一、週三、週五';
      } else if (text.contains('二四六') || text.contains('二、四、六')) {
        repeatRule = '週二、週四、週六';
      } else if (text.contains('週六') || text.contains('週日') || text.contains('禮拜六') || text.contains('禮拜日') || text.contains('週末')) {
        repeatRule = '週末';
      } else if (text.contains('週一') || text.contains('週五') || text.contains('工作日') || text.contains('平日')) {
        repeatRule = '週一至週五';
      } else if (text.contains('每日') || text.contains('每天')) {
        repeatRule = '每天';
      }

      String titleStr = text;
      for (final sub in ['提醒他', '提醒', '呼叫', '叫', '跟他說', '記得', '叫長輩', '幫我']) {
        if (titleStr.contains(sub)) {
          titleStr = titleStr.split(sub).last;
        }
      }
      final kinshipTerms = r'老爸|老媽|阿公|阿嬤|爺爺|奶奶|長輩|伯伯|媽媽|爸爸|叔叔|阿姨|大舅|姑姑|伯母|外公|外婆';
      final dynamicPattern = '${RegExp.escape(elderName)}|$kinshipTerms';
      titleStr = titleStr.replaceAll(RegExp('^(每週[一二三四五六日、]+|每週|每日|每天|早上|上午|下午|晚上|中午|\\d{1,2}點半|\\d{1,2}點|\\d{1,2}分|$dynamicPattern|\\s+)+'), '').trim();
      if (titleStr.isEmpty) titleStr = '定時叮嚀';

      final allTimeMatches = RegExp(r'(早上|上午|下午|晚上|中午)?\s*(\d{1,2})\s*[點時分:]\s*(\d{1,2}|半)?分?').allMatches(text).toList();
      List<Map<String, dynamic>> draftList = [];

      if (allTimeMatches.isNotEmpty) {
        for (final mMatch in allTimeMatches) {
          final period = mMatch.group(1);
          int h = int.parse(mMatch.group(2)!);
          int m = 0;
          if (mMatch.group(3) == '半' || text.contains('點半') || text.contains('時半')) {
            m = 30;
          } else if (mMatch.group(3) != null && RegExp(r'^\d+$').hasMatch(mMatch.group(3)!)) {
            m = int.parse(mMatch.group(3)!);
          }
          if ((period == '下午' || period == '晚上') && h < 12) h += 12;
          if ((period == '早上' || period == '上午') && h == 12) h = 0;
          final timeStr = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

          draftList.add({
            'title': titleStr,
            'category': category,
            'time_str': timeStr,
            'repeat_days': repeatRule,
            'start_date': DateTime.now().toString().split(' ')[0],
            'note': '家屬指令：$text',
          });
        }
      } else {
        draftList.add({
          'title': titleStr,
          'category': category,
          'time_str': '08:00',
          'repeat_days': repeatRule,
          'start_date': DateTime.now().toString().split(' ')[0],
          'note': '家屬指令：$text',
        });
      }

      return {
        'reply_text': '沒問題！我已為您解析出 ${draftList.length} 筆關懷排程設定，請確認下方草稿內容，點擊按鈕即可一鍵同步至 $elderName 的裝置：',
        'status_summary': null,
        'schedule_drafts': draftList,
      };
    }

    // ⚠️ 第四十九輪誠實性修復：這個分支只在完全連不上後端時才會走到
    // （見 _sendMessage 的 catch）。舊版在這裡依「現在幾點」編一段看起來
    // 煞有其事、其實與長輩真實狀況完全無關的假近況（例如固定寫死「今日
    // 各時段用藥與關懷打卡皆已全數完成」）。既然是離線也查不到任何真實
    // 資料，唯一誠實的做法就是照實告知「現在連不上，這不是真的近況」，
    // 不能因為畫面要有東西顯示就編數字——這正是本輪要根除的問題本身，
    // 沒有理由只修後端、留著前端這個離線分支繼續騙。
    return {
      'reply_text': '目前無法連線到伺服器，暫時無法查詢 $elderName 的即時近況。請檢查網路連線後再試一次。',
      'status_summary': {
        'mood_status': '目前無法連線，查不到情緒紀錄。',
        'mood_score': null,
        'medication_status': '目前無法連線，查不到用藥打卡紀錄。',
        'activity_status': '目前無法連線，查不到活動與步數資料。',
        'recent_topics': [],
        'next_appointment': '目前無法連線，查不到排程資料。',
      },
      'schedule_drafts': [],
    };
  }

  @override
  Widget build(BuildContext context) {
    final elderName = widget.currentElder?.displayName ?? '長輩';

    return Scaffold(
      backgroundColor: const Color(0xFF0B132B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2541),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0284C7), Color(0xFF6366F1)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 照護共創助理',
                  style: GoogleFonts.notoSansTc(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '線上陪伴 $elderName',
                      style: GoogleFonts.notoSansTc(fontSize: 11, color: const Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 對話訊息列表
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                itemCount: _chatMessages.length,
                itemBuilder: (context, index) {
                  final msg = _chatMessages[index];
                  final isUser = msg['isUser'] == true;
                  final statusSummary = msg['statusSummary'];
                  final scheduleDrafts = msg['scheduleDrafts'];
                  final isApplied = msg['isApplied'] == true;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isUser) ...[
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [Color(0xFF0284C7), Color(0xFF6366F1)]),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 16),
                              ),
                              const SizedBox(width: 10),
                            ],

                            // 對話主氣泡
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                                decoration: BoxDecoration(
                                  gradient: isUser
                                      ? const LinearGradient(
                                          colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                  color: isUser ? null : const Color(0xFF1C2541),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(20),
                                    topRight: const Radius.circular(20),
                                    bottomLeft: Radius.circular(isUser ? 20 : 4),
                                    bottomRight: Radius.circular(isUser ? 4 : 20),
                                  ),
                                  border: Border.all(
                                    color: isUser
                                        ? const Color(0xFF38BDF8).withValues(alpha: 0.3)
                                        : const Color(0xFF334155).withValues(alpha: 0.6),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isUser
                                          ? const Color(0xFF0284C7).withValues(alpha: 0.25)
                                          : Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  msg['text'],
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: 14,
                                    color: Colors.white,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // 近況摘要卡片
                        if (!isUser && statusSummary != null) ...[
                          const SizedBox(height: 12),
                          _buildStatusSummaryCard(statusSummary),
                        ],

                        // 排程草稿卡片
                        if (!isUser && scheduleDrafts != null && scheduleDrafts.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _buildScheduleDraftCard(scheduleDrafts, index, isApplied),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),

            if (_isSending)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8), strokeWidth: 2)),
              ),

            // 快捷推薦話題 Pills
            Container(
              height: 42,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildPresetPill(Icons.wb_sunny_rounded, '$elderName 今天過得怎麼樣？', const Color(0xFF38BDF8)),
                  _buildPresetPill(Icons.medication_rounded, '每天 08:00 與 20:00 提醒吃降血壓藥', const Color(0xFF10B981)),
                  _buildPresetPill(Icons.directions_run_rounded, '每週六日下午 4 點提醒出門散步 30 分鐘', const Color(0xFFF59E0B)),
                ],
              ),
            ),

            // 輸入框
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFF1C2541),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B132B),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: TextField(
                        controller: _messageController,
                        style: GoogleFonts.notoSansTc(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: _isListening ? '🎤 聆聽中，請說話…' : '詢問長輩近況，或對話建立排程...',
                          hintStyle: GoogleFonts.notoSansTc(color: const Color(0xFF64748B), fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 🎙️ 語音輸入按鈕（第四十九輪新增）。固定寬度圖示鈕，左側輸入框
                  // 已用 Expanded 吸收剩餘空間，窄螢幕下不會造成 RenderFlex 溢位
                  // （鐵律 #14）。收聽中改紅色漸層＋麥克風實心圖示，明顯區分狀態。
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isListening
                            ? [const Color(0xFFEF4444), const Color(0xFFF87171)]
                            : [const Color(0xFF334155), const Color(0xFF1C2541)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isListening
                            ? const Color(0xFFEF4444).withValues(alpha: 0.6)
                            : const Color(0xFF475569),
                      ),
                      boxShadow: _isListening
                          ? [
                              BoxShadow(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                                blurRadius: 10,
                              ),
                            ]
                          : null,
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: _isSending ? null : _toggleVoiceInput,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0284C7), Color(0xFF6366F1)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: () => _sendMessage(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetPill(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _sendMessage(text),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(text, style: GoogleFonts.notoSansTc(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusSummaryCard(Map<String, dynamic> summary) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.85,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2541),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.4), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // ★ 第四十九輪誠實性修復：mood_title 改名 mood_status，內容從
              //   模型自由發揮的「心情愉悅 ☀️」短標籤改成 Python 依真實資料
              //   組出的完整句子（例如「今天偵測到 1 次負面情緒…」），長度不
              //   再可控，因此改用 Expanded + ellipsis，避免窄螢幕溢位（鐵律
              //   #14）。
              Expanded(
                child: Text(
                  summary['mood_status'] ?? '目前沒有情緒紀錄',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  style: GoogleFonts.notoSansTc(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF38BDF8)),
                ),
              ),
              // mood_score 沒有真實依據時一律為 null——不顯示分數徽章，
              // 不要顯示 0、也不要自己補一個數字（第四十九輪明訂）。
              if (summary['mood_score'] != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '情緒: ${summary['mood_score']} 分',
                    style: GoogleFonts.notoSansTc(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(summary['medication_status'] ?? '', style: GoogleFonts.notoSansTc(fontSize: 13, color: const Color(0xFFCBD5E1))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.directions_run_rounded, color: Color(0xFF38BDF8), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(summary['activity_status'] ?? '', style: GoogleFonts.notoSansTc(fontSize: 13, color: const Color(0xFFCBD5E1))),
              ),
            ],
          ),
          // 📅 近期排程（第四十九輪新增顯示欄位）：這個欄位過去雖然由後端
          // 回傳，但前端從未渲染過，等於白算——現在後端已經是查
          // remote_reminders 得到的真實下一筆提醒，補上對應的顯示列。
          if ((summary['next_appointment'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.event_rounded, color: Color(0xFFF59E0B), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(summary['next_appointment'], style: GoogleFonts.notoSansTc(fontSize: 13, color: const Color(0xFFCBD5E1))),
                ),
              ],
            ),
          ],
          // recent_topics 沒有真實話題來源時，後端回空陣列——不顯示整個
          // 話題標籤區塊，不用空的 Wrap 留下多餘留白（第四十九輪明訂）。
          if ((summary['recent_topics'] as List<dynamic>?)?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: (summary['recent_topics'] as List<dynamic>).map((t) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
                  ),
                  child: Text('# $t', style: GoogleFonts.notoSansTc(fontSize: 11, color: const Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScheduleDraftCard(List<dynamic> drafts, int messageIndex, bool isApplied) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.85,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2541),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.playlist_add_check_rounded, color: Color(0xFF10B981), size: 18),
              ),
              const SizedBox(width: 8),
              Text(
                'AI 解析出 ${drafts.length} 筆關懷排程草稿',
                style: GoogleFonts.notoSansTc(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...drafts.map((d) {
            final cat = d['category'] ?? 'custom';
            IconData iconData = Icons.alarm_rounded;
            Color iconColor = const Color(0xFF38BDF8);

            if (cat == 'medication') {
              iconData = Icons.medication_rounded;
              iconColor = const Color(0xFF10B981);
            } else if (cat == 'exercise') {
              iconData = Icons.directions_run_rounded;
              iconColor = const Color(0xFFF59E0B);
            } else if (cat == 'hospital') {
              iconData = Icons.local_hospital_rounded;
              iconColor = const Color(0xFFEF4444);
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0B132B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(iconData, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d['title'] ?? '排程',
                          style: GoogleFonts.notoSansTc(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '⏰ ${d['time_str']} (${d['repeat_days'] ?? "每天"})',
                          style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isApplied ? const Color(0xFF475569) : const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: isApplied ? 0 : 3,
              ),
              onPressed: isApplied
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      _confirmBatchSchedule(drafts, messageIndex);
                    },
              icon: Icon(isApplied ? Icons.check_circle_rounded : Icons.sync_rounded, color: Colors.white, size: 20),
              label: Text(
                isApplied ? '✅ 已成功同步至長輩端' : '🚀 一鍵確認同步至長輩端',
                style: GoogleFonts.notoSansTc(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
