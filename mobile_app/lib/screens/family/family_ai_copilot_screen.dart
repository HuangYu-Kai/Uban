import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../models/elder.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/family_theme.dart';
import '../../utils/error_handler.dart';
import '../../services/api/daily_question_api.dart';
import 'daily_question_screen.dart'
    show DailyAsker, DailyAudioButton, DailyHistoryLoader, resolveFamilyId;
import 'family_question_draft.dart';
import 'family_share_draft.dart';
import 'widgets/fam_interaction_ui.dart';
import 'widgets/fam_ui.dart';

/// 🤖 AI 照護秘書對話視窗 (Family AI Care Co-pilot Screen)。
///
/// 2026-10 起改家屬新設計（海灣藍、design_prototype/family.html #copilot）：
/// `famSubBar`、快捷分段 `.qrow`、對話泡泡 `.cbub`、排程確認卡 `.sched`、底部輸入列 `.cbar`；
/// 語音輸入與送出邏輯完全不變。
///
/// 2026-10 起「互動」分頁的留言／時光牆入口併入這裡：秘書有三項能力——
/// 分享近況給長輩（可附照片，產生分享草稿卡、確認後才發到時光牆）、查長輩近況、建立提醒草稿。
class FamilyAiCopilotScreen extends StatefulWidget {
  final Elder? currentElder;

  /// 預先填入輸入框的草稿（互動分頁的快捷鈕用）。只填入、不自動送出。
  final String? initialMessage;

  /// ★ 2026-10-07 交接 A2 測試注入點；null 時使用真實 API。
  final DailyHistoryLoader? historyLoader;
  final DailyAsker? asker;

  const FamilyAiCopilotScreen({
    super.key,
    this.currentElder,
    this.initialMessage,
    this.historyLoader,
    this.asker,
  });

  @override
  State<FamilyAiCopilotScreen> createState() => _FamilyAiCopilotScreenState();
}

class _FamilyAiCopilotScreenState extends State<FamilyAiCopilotScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _chatMessages = [];
  bool _isSending = false;

  /// 待附的照片（送出時先上傳、再帶 image_url 給後端）。
  File? _attachedImage;

  // 後端會串接 Ollama→Gemini 兩段 LLM 呼叫，常超過預設 15 秒，故此端點放寬到 45 秒。
  static const Duration _copilotTimeout = Duration(seconds: 45);

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
    final initial = widget.initialMessage;
    if (initial != null && initial.isNotEmpty) {
      _messageController.value = TextEditingValue(
        text: initial,
        selection: TextSelection.collapsed(offset: initial.length),
      );
    }
    _chatMessages.add({
      'isUser': false,
      'text': '您好！我是您的 AI 照護秘書 🤖\n我可以幫您：\n・分享近況或照片給 $elderName（例如：「跟$elderName說：今天孫子考了 100 分」，也可以附照片）\n・查詢「$elderName 今天過得怎麼樣？」\n・出題給 $elderName（例如：「想問$elderName：小時候住哪裡？」）\n・建立提醒（例如：「每天早上 8 點與晚上 8 點提醒 $elderName 吃降血壓藥」）',
      'statusSummary': null,
      'scheduleDrafts': null,
    });
    // ★ 2026-10-07 交接 A2：長輩回答由秘書轉告。
    _loadAnswerRelays();
  }

  /// ★ 2026-10-07 交接 A2：打開秘書時讀每日一問歷史，把近 7 天、本機沒看過的回答
  /// 以秘書訊息轉告（有語音附播放鈕）。顯示後才記入本機已看過清單（device 層級）。
  /// 讀取失敗就靜默略過（轉告是加分功能，不打擾家屬）。
  Future<void> _loadAnswerRelays() async {
    final elderId =
        widget.currentElder?.elderId ?? widget.currentElder?.id.toString();
    if (elderId == null) return;
    try {
      final fid = await resolveFamilyId(null);
      if (fid == null) return;
      final items = widget.historyLoader != null
          ? await widget.historyLoader!(elderId, fid)
          : await DailyQuestionApi.getHistory(elderId: elderId, familyId: fid);
      if (items == null || !mounted) return;
      final seen = await loadSeenAnswerIds(elderId);
      final fresh = selectUnseenAnswers(items, seen);
      if (fresh.isEmpty || !mounted) return;
      final elderName = widget.currentElder?.displayName ?? '長輩';
      setState(() {
        for (final it in fresh) {
          _chatMessages.add({
            'isUser': false,
            'text': answerRelayText(elderName, it),
            'relayAudioUrl': it.hasAudio ? it.answerAudioUrl : null,
            'statusSummary': null,
            'scheduleDrafts': null,
          });
        }
      });
      _scrollToBottom();
      await saveSeenAnswerIds(
          elderId, {...seen, ...fresh.map((e) => e.id.toString())});
    } catch (e) {
      debugPrint('⚠️ [FamilyCopilot] 轉告長輩回答失敗：$e');
    }
  }

  @override
  void dispose() {
    _speechToText.stop();
    _messageController.dispose();
    for (final m in _chatMessages) {
      (m['shareController'] as TextEditingController?)?.dispose();
      (m['questionController'] as TextEditingController?)?.dispose();
    }
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
            onStatus: _onCopilotSttStatus,
            onError: _onCopilotSttError,
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
    // ★ 2026-10-06 喚醒詞修正：SpeechToText 是單例，listen 前把本畫面的
    //   回呼掛回去（避免被先初始化的其他畫面佔用）。
    _speechToText.errorListener = _onCopilotSttError;
    _speechToText.statusListener = _onCopilotSttStatus;
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

  // ★ 2026-10-06 喚醒詞修正：由 initialize 的行內回呼抽成方法（見 listen 前註解）。
  void _onCopilotSttStatus(String status) {
    // 靜音一段時間後 speech_to_text 會自動停止聆聽（done/notListening），
    // 這裡只同步視覺狀態，不做任何送出動作。
    if ((status == 'done' || status == 'notListening') && _isListening && mounted) {
      setState(() => _isListening = false);
    }
  }

  void _onCopilotSttError(SpeechRecognitionError err) {
    debugPrint('⚠️ [FamilyCopilot STT Error] ${err.errorMsg}');
    if (!mounted) return;
    setState(() => _isListening = false);
    // 可重試（改用打字或再試一次），非硬錯誤，用 showWarning。
    ErrorHandler.showWarning(context, '語音辨識發生錯誤，請改用打字或再試一次');
  }

  /// 快捷：只把草稿填進輸入框（不自動送出），讓家屬補完再送。
  void _prefill(String text) {
    _messageController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
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
    final imageFile = presetText == null ? _attachedImage : null;
    if ((text.isEmpty && imageFile == null) || _isSending) return;

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

    // 有附照片：先上傳；失敗就中止，文字與照片都保留讓家屬重試（不假裝成功）。
    String? uploadedUrl;
    if (imageFile != null) {
      uploadedUrl = await ApiService.uploadCommunityImage(imageFile);
      if (!mounted) return;
      if (uploadedUrl == null) {
        setState(() => _isSending = false);
        ErrorHandler.showWarning(context, '照片上傳失敗，請檢查網路後再試一次');
        return;
      }
    }
    // 只有照片沒有文字時：畫面上顯示「（照片）」，送給後端的 message 用空字串——
    // 後端有附照片就直接回分享草稿（文字空白讓家屬自己填），若送「分享照片」，
    // 這四個字會被當成要轉述給長輩的內容。
    final sendText = text.isEmpty ? '（照片）' : text;

    if (presetText == null) {
      _messageController.clear();
    }

    setState(() {
      _attachedImage = null;
      _chatMessages.add({
        'isUser': true,
        'text': sendText,
        'localImage': imageFile,
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
        if (uploadedUrl != null) 'image_url': uploadedUrl,
      }, timeout: _copilotTimeout);

      final Map<String, dynamic> data;
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        data = Map<String, dynamic>.from(res['data']);
      } else if (res == null) {
        // 網路失敗或逾時：ApiClient 回 null，走離線後備（不編造近況）。
        data = uploadedUrl != null
            ? _buildServerErrorResponse(elderName, null)
            : _generateFallbackResponse(text, elderName);
      } else {
        // 伺服器有回應但非 success（404 未綁定、500 等）：與離線分開顯示。
        final msg = res['message'] ?? res['detail'];
        data = uploadedUrl != null
            ? _buildServerErrorResponse(elderName, msg is String ? msg : null)
            : _serverFailureResponse(text, elderName, msg is String ? msg : null);
      }

      if (!mounted) return;
      setState(() => _addBotMessage(data, uploadedImageUrl: uploadedUrl));
    } catch (e) {
      debugPrint('⚠️ [FamilyCopilot] 送出失敗：$e');
      if (!mounted) return;
      final fallbackData = uploadedUrl != null
          ? _buildServerErrorResponse(elderName, null)
          : _serverFailureResponse(text, elderName, null);
      setState(() => _addBotMessage(fallbackData));
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
        _scrollToBottom();
      }
    }
  }

  /// 從相簿選一張照片附上（送出時才上傳）。
  Future<void> _pickImage() async {
    if (_isSending) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked == null || !mounted) return;
      setState(() => _attachedImage = File(picked.path));
    } catch (e) {
      debugPrint('⚠️ [FamilyCopilot] 選照片失敗：$e');
      if (!mounted) return;
      ErrorHandler.showWarning(context, '無法開啟相簿，請確認已允許照片權限');
    }
  }

  /// 確認送出分享草稿：建立時光牆貼文（author_role 'family'）。
  /// 失敗時卡片保留、顯示錯誤，可重試；不假裝成功。
  Future<void> _confirmShare(int messageIndex) async {
    final msg = _chatMessages[messageIndex];
    if (msg['sharePhase'] == ShareCardPhase.sending ||
        msg['sharePhase'] == ShareCardPhase.sent) {
      return;
    }
    final controller = msg['shareController'] as TextEditingController;
    final imageUrl = msg['shareImageUrl'] as String?;
    final content = controller.text.trim();
    if (!canSendShare(text: content, hasImage: imageUrl != null, sending: false)) return;

    setState(() {
      msg['sharePhase'] = ShareCardPhase.sending;
      msg['shareError'] = null;
    });

    String? error;
    try {
      final prefs = await SharedPreferences.getInstance();
      final familyId = prefs.getInt('caregiver_id');
      if (familyId == null) {
        error = '無法確認家屬身分，請重新登入後再試';
      } else {
        final userName =
            prefs.getString('caregiver_name') ?? prefs.getString('user_name') ?? '家人';
        final res = await ApiService.createCommunityPost(
          familyId: familyId,
          authorId: familyId,
          authorName: userName,
          authorRole: 'family',
          content: content,
          imageUrl: imageUrl,
        );
        if (res == null) error = '送出失敗，請檢查網路後再試一次';
      }
    } catch (e) {
      debugPrint('⚠️ [FamilyCopilot] 分享送出失敗：$e');
      error = '送出失敗，請稍後再試';
    }

    if (!mounted) return;
    setState(() {
      if (error == null) {
        msg['sharePhase'] = ShareCardPhase.sent;
        msg['shareError'] = null;
      } else {
        msg['sharePhase'] = ShareCardPhase.draft;
        msg['shareError'] = error;
      }
    });
    _scrollToBottom();
  }

  /// ★ 2026-10-07 交接 A2：確認出題草稿，呼叫既有的 `POST /api/daily_question/ask`。
  /// 失敗時卡片保留、顯示 API 回的真實原因，可修改後重試；不假裝成功。
  Future<void> _confirmQuestion(int messageIndex) async {
    final msg = _chatMessages[messageIndex];
    if (msg['questionPhase'] == QuestionCardPhase.sending ||
        msg['questionPhase'] == QuestionCardPhase.sent) {
      return;
    }
    final controller = msg['questionController'] as TextEditingController;
    final question = controller.text.trim();
    if (!canSendQuestion(text: question, sending: false)) return;

    setState(() {
      msg['questionPhase'] = QuestionCardPhase.sending;
      msg['questionError'] = null;
    });

    String? error;
    try {
      final DailyAskResult r;
      if (widget.asker != null) {
        r = await widget.asker!(question: question);
      } else {
        final fid = await resolveFamilyId(null);
        final elderId =
            widget.currentElder?.elderId ?? widget.currentElder?.id.toString();
        if (fid == null || elderId == null) {
          r = const DailyAskResult(false, '無法確認家屬身分，請重新登入後再試');
        } else {
          r = await DailyQuestionApi.ask(
              familyId: fid, elderId: elderId, question: question);
        }
      }
      if (!r.ok) error = r.message;
    } catch (e) {
      debugPrint('⚠️ [FamilyCopilot] 出題送出失敗：$e');
      error = '送出失敗，請稍後再試';
    }

    if (!mounted) return;
    setState(() {
      if (error == null) {
        msg['questionPhase'] = QuestionCardPhase.sent;
        msg['questionError'] = null;
      } else {
        msg['questionPhase'] = QuestionCardPhase.draft;
        msg['questionError'] = error;
      }
    });
    _scrollToBottom();
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

    // ⚠️ 第四十九輪誠實性修復：這個分支只在 res == null（網路失敗或逾時）
    // 時才會走到（見 _sendMessage）。舊版在這裡依「現在幾點」編一段看起來
    // 煞有其事、其實與長輩真實狀況完全無關的假近況（例如固定寫死「今日
    // 各時段用藥與關懷打卡皆已全數完成」）。既然是離線也查不到任何真實
    // 資料，唯一誠實的做法就是照實告知「現在連不上，這不是真的近況」，
    // 不能因為畫面要有東西顯示就編數字——這正是本輪要根除的問題本身，
    // 沒有理由只修後端、留著前端這個離線分支繼續騙。
    return {
      'reply_text': '目前無法連線到伺服器，或伺服器回應逾時，暫時無法查詢 $elderName 的即時近況。請稍後再試一次。',
      'status_summary': null,
      'schedule_drafts': [],
    };
  }

  /// 伺服器有回應、但不是 success（例如 404 未綁定、500）時的提示。
  /// 與「連不上／逾時」分開顯示，家屬才知道該檢查綁定而不是網路。
  Map<String, dynamic> _buildServerErrorResponse(String elderName, String? serverMsg) {
    final detail = (serverMsg == null || serverMsg.isEmpty) ? '' : '（$serverMsg）';
    return {
      'reply_text': '伺服器暫時無法處理這個問題$detail。請稍後再試，或確認已與 $elderName 完成綁定。',
      'status_summary': null,
      'schedule_drafts': [],
    };
  }

  /// 伺服器失敗時的後備：先試本機排程解析，解析不出排程才顯示伺服器錯誤。
  Map<String, dynamic> _serverFailureResponse(String text, String elderName, String? serverMsg) {
    final local = _generateFallbackResponse(text, elderName);
    final drafts = local['schedule_drafts'];
    if (drafts is List && drafts.isNotEmpty) return local;
    return _buildServerErrorResponse(elderName, serverMsg);
  }

  /// 測試用：直接塞入一則後端回覆（例如帶 `question_draft` 的 ASK_DAILY_QUESTION），
  /// 避免測試必須模擬 `/api/ai/family_copilot/chat`。
  @visibleForTesting
  void testInjectBotReply(Map<String, dynamic> data) {
    setState(() => _addBotMessage(data));
  }

  /// 把回覆資料加成一則機器人訊息。
  void _addBotMessage(Map<String, dynamic> data, {String? uploadedImageUrl}) {
    // share_draft 可能缺席（舊版後端）或為 null。
    var share = data['intent'] == 'SHARE_WITH_ELDER' || data['share_draft'] != null
        ? ShareDraft.tryParse(data['share_draft'])
        : null;
    // 有附照片時後端一定回 SHARE_WITH_ELDER；草稿若漏了 image_url，以剛上傳的為準。
    if (uploadedImageUrl != null && data['intent'] == 'SHARE_WITH_ELDER') {
      share = ShareDraft(text: share?.text ?? '', imageUrl: share?.imageUrl ?? uploadedImageUrl);
    }
    // ★ 2026-10-07 交接 A2：question_draft 可能缺席（舊版後端）或為 null。
    final question = data['intent'] == 'ASK_DAILY_QUESTION' || data['question_draft'] != null
        ? QuestionDraft.tryParse(data['question_draft'])
        : null;
    _chatMessages.add({
      if (question != null) ...{
        'questionController': TextEditingController(text: question.text),
        'questionPhase': QuestionCardPhase.draft,
        'questionError': null,
      },
      if (share != null) ...{
        'shareImageUrl': share.imageUrl,
        'shareController': TextEditingController(text: share.text),
        'sharePhase': ShareCardPhase.draft,
        'shareError': null,
      },
      'isUser': false,
      'text': (data['reply_text'] ?? '已為您處理完成！').toString(),
      'statusSummary': data['status_summary'],
      'scheduleDrafts': data['schedule_drafts'] != null ? List<dynamic>.from(data['schedule_drafts']) : null,
    });
  }

  @override
  Widget build(BuildContext context) {
    // 2026-10：家屬新設計——push 出來的家屬頁要自己掛家屬主題（設計稿 #copilot）。
    return FamilyThemeScope(
      child: Builder(builder: _buildScreen),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final c = UbanColors.of(context);
    final elderName = widget.currentElder?.displayName ?? '長輩';

    return Scaffold(
      backgroundColor: c.bg,
      appBar: famSubBar(
        context,
        title: 'AI 照護秘書',
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // 快捷推薦話題（`.qrow`）：點下去等同把該句話送出，行為與改版前的 Pills 相同。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: FamFilterRow(
                children: [
                  FamFilterChip(
                    label: '分享近況',
                    selected: false,
                    onTap: () => _prefill('跟$elderName說：'),
                  ),
                  // ★ 2026-10-07 交接 A2：預填「想問{稱呼}：」，家屬補完再送。
                  FamFilterChip(
                    label: '想問$elderName一個問題',
                    selected: false,
                    onTap: () => _prefill('想問$elderName：'),
                  ),
                  FamFilterChip(
                    label: '近況速報',
                    selected: false,
                    onTap: () => _sendMessage('$elderName 今天過得怎麼樣？'),
                  ),
                  FamFilterChip(
                    label: '吃藥提醒',
                    selected: false,
                    onTap: () => _sendMessage('每天 08:00 與 20:00 提醒吃降血壓藥'),
                  ),
                  FamFilterChip(
                    label: '散步提醒',
                    selected: false,
                    onTap: () => _sendMessage('每週六日下午 4 點提醒出門散步 30 分鐘'),
                  ),
                ],
              ),
            ),

            // 對話訊息列表
            Expanded(
              child: ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                itemCount: _chatMessages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final msg = _chatMessages[index];
                  final isUser = msg['isUser'] == true;
                  final statusSummary = msg['statusSummary'];
                  final scheduleDrafts = msg['scheduleDrafts'];
                  final isApplied = msg['isApplied'] == true;
                  final localImage = msg['localImage'];
                  final sharePhase = msg['sharePhase'] as ShareCardPhase?;
                  final questionPhase = msg['questionPhase'] as QuestionCardPhase?;
                  final relayAudioUrl = msg['relayAudioUrl'] as String?;

                  return FamChatBubble(
                    mine: isUser,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg['text'],
                          style: FamChatBubble.textStyle(context, mine: isUser),
                        ),
                        if (isUser && localImage is File) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(localImage,
                                width: 120, height: 120, fit: BoxFit.cover),
                          ),
                        ],
                        // 分享草稿卡
                        if (!isUser && sharePhase != null)
                          ShareDraftCard(
                            controller: msg['shareController'] as TextEditingController,
                            imageUrl: msg['shareImageUrl'] as String?,
                            elderName: elderName,
                            phase: sharePhase,
                            errorText: msg['shareError'] as String?,
                            onSend: () => _confirmShare(index),
                            onCancel: () => setState(
                                () => msg['sharePhase'] = ShareCardPhase.cancelled),
                          ),
                        // ★ 2026-10-07 交接 A2：出題卡
                        if (!isUser && questionPhase != null)
                          QuestionDraftCard(
                            controller: msg['questionController'] as TextEditingController,
                            elderName: elderName,
                            phase: questionPhase,
                            errorText: msg['questionError'] as String?,
                            onSend: () => _confirmQuestion(index),
                            onCancel: () => setState(
                                () => msg['questionPhase'] = QuestionCardPhase.cancelled),
                          ),
                        // ★ 2026-10-07 交接 A2：長輩語音回答的播放鈕
                        if (!isUser && relayAudioUrl != null) ...[
                          const SizedBox(height: 8),
                          DailyAudioButton(url: relayAudioUrl),
                        ],
                        // 近況摘要
                        if (!isUser && statusSummary != null)
                          _buildStatusSummary(statusSummary),
                        // 排程草稿確認卡（`.sched`）
                        if (!isUser && scheduleDrafts != null && scheduleDrafts.isNotEmpty)
                          _buildScheduleDraft(scheduleDrafts, index, isApplied),
                      ],
                    ),
                  );
                },
              ),
            ),

            if (_isSending)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: c.brand, strokeWidth: 2.2),
                  ),
                ),
              ),

            // 已附照片的縮圖（可移除）
            if (_attachedImage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(_attachedImage!,
                            width: 64, height: 64, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: Semantics(
                          button: true,
                          label: '移除照片',
                          child: GestureDetector(
                            onTap: _isSending
                                ? null
                                : () => setState(() => _attachedImage = null),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: c.text2,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded,
                                  size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 底部輸入列（`.cbar`）：輸入框＋語音＋送出。固定寬度圓鈕、輸入框 Expanded，
            // 窄螢幕下不會造成 RenderFlex 溢位（鐵律 #14）。
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: FamInput(
                      controller: _messageController,
                      hintText: _isListening ? '聆聽中，請說話…' : '分享近況、問近況或設提醒…',
                      height: 50,
                      radius: 999,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FamRoundBtn(
                    icon: Icons.add_photo_alternate_outlined,
                    tooltip: '附照片',
                    size: 50,
                    background: c.brandContainer,
                    foreground: c.brandStrong,
                    onTap: _isSending ? null : _pickImage,
                  ),
                  const SizedBox(width: 8),
                  // 🎙️ 語音輸入按鈕（第四十九輪新增）。收聽中改 danger 底，明顯區分狀態。
                  FamRoundBtn(
                    icon: _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    tooltip: _isListening ? '停止語音輸入' : '語音輸入',
                    size: 50,
                    background: _isListening ? c.danger : c.brandFill,
                    foreground: _isListening ? Colors.white : c.onBrand,
                    onTap: _isSending ? null : _toggleVoiceInput,
                  ),
                  const SizedBox(width: 8),
                  FamRoundBtn(
                    icon: Icons.send_rounded,
                    tooltip: '送出',
                    size: 50,
                    onTap: () => _sendMessage(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 近況摘要：放在 AI 泡泡內，純文字列（不放小圖示）。
  Widget _buildStatusSummary(Map<String, dynamic> summary) {
    final c = UbanColors.of(context);

    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '$label  ',
                style: famText(c.text3, 13, weight: FontWeight.w700),
              ),
              TextSpan(text: value, style: famText(c.text2, 14, height: 1.5)),
            ]),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ★ 第四十九輪誠實性修復：mood_title 改名 mood_status，內容從
          //   模型自由發揮的短標籤改成 Python 依真實資料組出的完整句子，
          //   長度不再可控，所以在泡泡內自然換行（鐵律 #14）。
          Text(
            summary['mood_status'] ?? '目前沒有情緒紀錄',
            style: famText(c.text, 15, weight: FontWeight.w700, height: 1.5),
          ),
          // mood_score 沒有真實依據時一律為 null——不顯示分數徽章，
          // 不要顯示 0、也不要自己補一個數字（第四十九輪明訂）。
          if (summary['mood_score'] != null) ...[
            const SizedBox(height: 6),
            FamChip(label: '情緒: ${summary['mood_score']} 分', tone: FamTone.brand),
          ],
          line('用藥', (summary['medication_status'] ?? '').toString()),
          line('活動', (summary['activity_status'] ?? '').toString()),
          // 📅 近期排程（第四十九輪新增顯示欄位）：後端已經是查
          // remote_reminders 得到的真實下一筆提醒，補上對應的顯示列。
          if ((summary['next_appointment'] as String?)?.isNotEmpty == true)
            line('排程', summary['next_appointment'].toString()),
          // recent_topics 沒有真實話題來源時，後端回空陣列——不顯示整個
          // 話題標籤區塊，不用空的 Wrap 留下多餘留白（第四十九輪明訂）。
          if ((summary['recent_topics'] as List<dynamic>?)?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in (summary['recent_topics'] as List<dynamic>))
                  FamChip(label: '# $t'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 排程草稿：`.sched` 列＋確認鈕，放在 AI 泡泡內。確認鈕的行為與改版前相同
  /// （`_confirmBatchSchedule`，已套用後鈕停用）。
  Widget _buildScheduleDraft(List<dynamic> drafts, int messageIndex, bool isApplied) {
    final c = UbanColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'AI 解析出 ${drafts.length} 筆關懷排程草稿',
            style: famText(c.text2, 13.5, weight: FontWeight.w700),
          ),
          for (var i = 0; i < drafts.length; i++)
            FamSched(
              first: i == 0,
              time: (drafts[i]['time_str'] ?? '').toString(),
              meta: (drafts[i]['repeat_days'] ?? '每天').toString(),
              title: (drafts[i]['title'] ?? '排程').toString(),
            ),
          const SizedBox(height: 12),
          FamButton(
            label: isApplied ? '已成功同步至長輩端' : '一鍵確認同步至長輩端',
            height: 44,
            onPressed: isApplied
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    _confirmBatchSchedule(drafts, messageIndex);
                  },
          ),
        ],
      ),
    );
  }
}
