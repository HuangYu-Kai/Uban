import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../globals.dart';
import '../../services/api/elder_daily_question_api.dart';
import '../../utils/stt_locale.dart';
import '../../widgets/ui/ui.dart';

/// 送出回答的注入點（測試用；正式呼叫端走 [ElderDailyQuestionApi.submitAnswer]）。
typedef DailyAnswerSender = Future<DailyAnswerResult> Function({
  required int questionId,
  String? text,
  String? audioPath,
});

/// ★ 2026-10-07 每日一問：開啟「回答今天的小問題」全高底部面板。
///
/// 回傳 true 代表已送出成功（呼叫端負責讓小嘎說「謝謝您分享…」並刷新卡片）。
Future<bool> showDailyQuestionAnswerSheet(
  BuildContext context, {
  required DailyQuestion question,
  required Object elderId,
  DailyAnswerSender? sender,
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: UbanColors.of(context).bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => SizedBox(
      height: MediaQuery.sizeOf(context).height,
      child: DailyQuestionAnswerSheet(
        question: question,
        elderId: elderId,
        sender: sender,
      ),
    ),
  );
  return r == true;
}

/// 長輩端回答面板：主要輸入是「按住說話」（裝置語音辨識）→ 辨識結果進入可編輯的
/// 大字文字框讓長輩確認；也可用鍵盤打字。次要是「錄一段聲音給家人聽」。
/// 兩種麥克風輸入互斥（不同時進行）。
class DailyQuestionAnswerSheet extends StatefulWidget {
  final DailyQuestion question;
  final Object elderId;
  final DailyAnswerSender? sender;

  /// 錄音上限（秒）。
  static const int maxRecordSeconds = 120;
  static const int maxTextLength = 500;

  const DailyQuestionAnswerSheet({
    super.key,
    required this.question,
    required this.elderId,
    this.sender,
  });

  @override
  State<DailyQuestionAnswerSheet> createState() =>
      _DailyQuestionAnswerSheetState();
}

class _DailyQuestionAnswerSheetState extends State<DailyQuestionAnswerSheet> {
  final TextEditingController _text = TextEditingController();

  // 平台物件全部延後到真正需要時才建立（測試環境沒有平台通道）。
  SpeechToText? _stt;
  bool _speechReady = false;
  String? _sttLocale;
  bool _listening = false;
  String _recognized = '';
  // 本次錄音期間辨識器回報的最後一個錯誤，用來給出具體提示。
  String? _lastSttError;

  AudioRecorder? _recorder;
  AudioPlayer? _player;
  StreamSubscription<void>? _playerDone;
  bool _recording = false;
  bool _playing = false;
  int _elapsed = 0;
  int _recordedSeconds = 0;
  String? _audioPath;
  Timer? _timer;

  bool _sending = false;
  String? _error;

  /// 只在「是我暫停的」才還原喚醒詞，避免蓋掉其他媒體（同 elder_chat_screen）。
  bool _pausedWakeWord = false;

  @override
  void initState() {
    super.initState();
    final prev = widget.question.answerText;
    if (widget.question.answered && prev != null) _text.text = prev;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _playerDone?.cancel();
    try {
      _stt?.stop();
    } catch (_) {}
    try {
      _recorder?.dispose();
    } catch (_) {}
    _player?.dispose();
    _restoreWakeWord();
    _text.dispose();
    super.dispose();
  }

  void _pauseWakeWord() {
    if (_pausedWakeWord) return;
    _pausedWakeWord = !isMediaPlayingNotifier.value;
    if (_pausedWakeWord) isMediaPlayingNotifier.value = true;
  }

  void _restoreWakeWord() {
    if (_pausedWakeWord) {
      _pausedWakeWord = false;
      isMediaPlayingNotifier.value = false;
    }
  }

  bool get _hasContent => _text.text.trim().isNotEmpty || _audioPath != null;
  bool get _busyMic => _listening || _recording;
  bool get _canSubmit => _hasContent && !_busyMic && !_sending;

  // ───────────────────────── 語音辨識（同 elder_chat_screen）─────────────────────────

  Future<bool> _initSpeech() async {
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) return false;
      final stt = _stt ??= SpeechToText();
      _speechReady = await stt.initialize(
        onError: (err) => debugPrint('🎙️ [DailyQ STT error] $err'),
      );
      if (_speechReady) {
        _sttLocale = pickChineseSttLocale(await stt.locales());
      }
    } catch (e) {
      debugPrint('🎙️ [DailyQ STT Init Failed] $e');
      _speechReady = false;
    }
    return _speechReady;
  }

  Future<void> _startListening() async {
    if (_sending || _busyMic) return;
    if (!_speechReady && !await _initSpeech()) {
      _setError('這台裝置未授權麥克風權限，請改用打字或開啟權限喔');
      return;
    }
    if (!mounted) return;
    _pauseWakeWord();
    await _stopPlayback();
    setState(() {
      _listening = true;
      _recognized = '';
      _error = null;
    });
    try {
      final stt = _stt!;
      // 單例辨識器的回呼可能還是首頁喚醒詞的：先換成只印 log 的回呼，
      // 避免喚醒詞的重啟邏輯在本畫面錄音期間被觸發（G59）。
      _lastSttError = null;
      stt.errorListener = (err) {
        debugPrint('🎙️ [DailyQ STT error] $err');
        _lastSttError = err.errorMsg;
      };
      stt.statusListener = (s) => debugPrint('🎙️ [DailyQ STT status] $s');
      await stt.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() => _recognized = result.recognizedWords);
        },
        listenFor: const Duration(seconds: 30),
        // ★ 2026-10-08：按住說話只取最終結果，不要部分結果、也不設 pauseFor。
        //   實機（小米 HyperOS＋Google 語音服務）的部分結果文字是空字串
        //   （字放在套件不讀的 UNSTABLE_TEXT），套件還會據此提早送出一個
        //   空白的「最終結果」，之後 Google 真正的辨識結果就被丟掉，
        //   畫面一律顯示「沒聽清楚」。pauseFor 依賴部分結果判斷停頓，
        //   沒有部分結果時會在 4 秒後誤切，所以一併拿掉；放開按鈕才結束。
        // ignore: deprecated_member_use
        partialResults: false,
        localeId: _sttLocale,
        listenOptions: SpeechListenOptions(
          partialResults: false,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      debugPrint('🎙️ [DailyQ STT Start Failed] $e');
      _restoreWakeWord();
      if (!mounted) return;
      setState(() {
        _listening = false;
        _recognized = '';
      });
      _setError('語音辨識暫時無法使用，請改用打字');
    }
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    String heard = '';
    try {
      if (_recognized.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
      await _stt?.stop();
      // 部分裝置放開後才給最終結果，最多再等 1.5 秒（同 elder_chat_screen）。
      for (var i = 0; i < 15 && _recognized.trim().isEmpty; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      heard = _recognized.trim();
    } catch (e) {
      debugPrint('🎙️ [DailyQ STT Stop Failed] $e');
    } finally {
      _restoreWakeWord();
      if (mounted) {
        setState(() {
          _listening = false;
          _recognized = '';
        });
      }
    }
    if (!mounted) return;
    if (heard.isEmpty) {
      _setError(sttFailureMessage(_lastSttError));
      return;
    }
    // 辨識結果放進可編輯文字框，讓長輩確認或修改後再送出。
    final limited = heard.length > DailyQuestionAnswerSheet.maxTextLength
        ? heard.substring(0, DailyQuestionAnswerSheet.maxTextLength)
        : heard;
    setState(() {
      _text.text = limited;
      _text.selection = TextSelection.collapsed(offset: limited.length);
      _error = null;
    });
  }

  // ───────────────────────── 錄一段聲音（record）─────────────────────────

  Future<void> _startRecording() async {
    if (_sending || _busyMic) return;
    try {
      final rec = _recorder ??= AudioRecorder();
      if (!await rec.hasPermission()) {
        _setError('需要允許麥克風權限才能錄音，請到手機設定開啟');
        return;
      }
      await _stopPlayback();
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/daily_answer_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _pauseWakeWord();
      await rec.start(const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _elapsed = 0;
        _audioPath = null;
        _recordedSeconds = 0;
        _error = null;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        if (_elapsed + 1 >= DailyQuestionAnswerSheet.maxRecordSeconds) {
          setState(() => _elapsed = DailyQuestionAnswerSheet.maxRecordSeconds);
          _stopRecording();
        } else {
          setState(() => _elapsed++);
        }
      });
    } catch (e) {
      debugPrint('⚠️ [DailyQ] 開始錄音失敗: $e');
      _restoreWakeWord();
      _setError('無法開始錄音，請稍後再試');
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _timer?.cancel();
    String? path;
    try {
      path = await _recorder?.stop();
    } catch (e) {
      debugPrint('⚠️ [DailyQ] 停止錄音失敗: $e');
    }
    _restoreWakeWord();
    if (!mounted) return;
    final secs = _elapsed;
    setState(() {
      _recording = false;
      if (path == null || secs < 1) {
        _audioPath = null;
        _recordedSeconds = 0;
        _error = '錄音太短了，請按住按鈕再說久一點';
      } else {
        _audioPath = path;
        _recordedSeconds = secs;
      }
    });
  }

  Future<void> _stopPlayback() async {
    if (!_playing) return;
    try {
      await _player?.stop();
    } catch (_) {}
    if (mounted) setState(() => _playing = false);
  }

  Future<void> _togglePreview() async {
    final path = _audioPath;
    if (path == null || _busyMic) return;
    if (_playing) {
      await _stopPlayback();
      return;
    }
    try {
      final p = _player ??= AudioPlayer();
      _playerDone ??= p.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = false);
      });
      setState(() => _playing = true);
      await p.play(DeviceFileSource(path));
    } catch (e) {
      debugPrint('⚠️ [DailyQ] 試聽失敗: $e');
      if (mounted) setState(() => _playing = false);
      _setError('無法播放錄音');
    }
  }

  Future<void> _deleteRecording() async {
    await _stopPlayback();
    if (mounted) {
      setState(() {
        _audioPath = null;
        _recordedSeconds = 0;
      });
    }
  }

  // ───────────────────────── 送出 ─────────────────────────

  void _setError(String? m) {
    if (mounted) setState(() => _error = m);
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    await _stopPlayback();
    setState(() {
      _sending = true;
      _error = null;
    });
    final text = _text.text.trim();
    final t = text.isEmpty ? null : text;
    final DailyAnswerResult r;
    final sender = widget.sender;
    if (sender != null) {
      r = await sender(
          questionId: widget.question.id, text: t, audioPath: _audioPath);
    } else {
      r = await ElderDailyQuestionApi.submitAnswer(
        questionId: widget.question.id,
        elderId: widget.elderId,
        text: t,
        audioPath: _audioPath,
      );
    }
    if (!mounted) return;
    if (r.ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _sending = false;
        _error = ElderDailyQuestionApi.networkErrorMessage;
      });
    }
  }

  // ───────────────────────── UI ─────────────────────────

  Widget _holdButton({
    required Key key,
    required String label,
    required IconData icon,
    required bool active,
    required bool enabled,
    required VoidCallback onStart,
    required VoidCallback onEnd,
    bool primary = true,
  }) {
    final c = UbanColors.of(context);
    final bg = active ? c.danger : (primary ? c.brandFill : c.brandContainer);
    final fg = active || primary ? Colors.white : c.brandStrong;
    return Opacity(
      opacity: enabled || active ? 1 : .45,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onLongPressStart: enabled ? (_) => onStart() : null,
        onLongPressEnd: enabled || active ? (_) => onEnd() : null,
        onLongPressCancel: active ? onEnd : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fg, size: 30),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: ubanText(22, FontWeight.w800, fg, height: 1.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final q = widget.question;
    final canMic = !_sending;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '回答今天的小問題',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ubanText(22, FontWeight.w800, c.brandStrong),
                  ),
                ),
                IconButton(
                  key: const ValueKey('daily_sheet_close'),
                  iconSize: 32,
                  constraints:
                      const BoxConstraints(minWidth: 60, minHeight: 60),
                  onPressed:
                      _sending ? null : () => Navigator.of(context).pop(false),
                  icon: Icon(Icons.close_rounded, color: c.text2),
                  tooltip: '關閉',
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    q.question,
                    key: const ValueKey('daily_sheet_question'),
                    style: ubanText(26, FontWeight.w800, c.text, height: 1.4),
                  ),
                  if (q.isFromFamily && q.askedByName != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '（家人 ${q.askedByName} 出的題目）',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ubanText(20, FontWeight.w600, c.text2),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _holdButton(
                    key: const ValueKey('daily_hold_talk'),
                    label: _listening ? '放開　完成' : '按住　說出答案',
                    icon: Icons.mic_rounded,
                    active: _listening,
                    enabled: canMic && !_recording,
                    onStart: _startListening,
                    onEnd: _stopListening,
                  ),
                  if (_listening) ...[
                    const SizedBox(height: 10),
                    Text(
                      _recognized.isEmpty ? '我在聽，請說…' : _recognized,
                      key: const ValueKey('daily_listening_text'),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style:
                          ubanText(22, FontWeight.w600, c.text2, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey('daily_answer_text'),
                    controller: _text,
                    enabled: !_sending,
                    maxLength: DailyQuestionAnswerSheet.maxTextLength,
                    minLines: 3,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                    onChanged: (_) => setState(() => _error = null),
                    style: ubanText(22, FontWeight.w600, c.text, height: 1.4),
                    decoration: InputDecoration(
                      hintText: '說完會出現在這裡，也可以直接打字',
                      hintStyle: ubanText(20, FontWeight.w500, c.text3),
                      filled: true,
                      fillColor: c.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '或者，錄一段聲音給家人聽',
                    style: ubanText(20, FontWeight.w700, c.text2),
                  ),
                  const SizedBox(height: 10),
                  _holdButton(
                    key: const ValueKey('daily_hold_record'),
                    label: _recording
                        ? '錄音中 $_elapsed 秒（放開結束）'
                        : (_audioPath == null
                            ? '按住　錄一段聲音給家人聽'
                            : '按住　重錄'),
                    icon: Icons.fiber_manual_record_rounded,
                    active: _recording,
                    enabled: canMic && !_listening,
                    primary: false,
                    onStart: _startRecording,
                    onEnd: _stopRecording,
                  ),
                  if (_audioPath != null && !_recording) ...[
                    const SizedBox(height: 10),
                    UbanButton(
                      key: const ValueKey('daily_preview'),
                      label: _playing ? '停止播放' : '聽聽看（$_recordedSeconds 秒）',
                      icon: _playing
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      variant: UbanButtonVariant.tonal,
                      onPressed: _sending ? null : _togglePreview,
                    ),
                    const SizedBox(height: 8),
                    UbanButton(
                      key: const ValueKey('daily_delete_audio'),
                      label: '刪除錄音',
                      icon: Icons.delete_outline_rounded,
                      variant: UbanButtonVariant.outline,
                      onPressed: _sending ? null : _deleteRecording,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: const ValueKey('daily_error'),
                      textAlign: TextAlign.center,
                      style:
                          ubanText(20, FontWeight.w700, c.danger, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: UbanButton(
              key: const ValueKey('daily_submit'),
              label: '送出給家人',
              icon: Icons.send_rounded,
              size: UbanButtonSize.xl,
              loading: _sending,
              onPressed: _canSubmit ? _submit : null,
            ),
          ),
        ],
      ),
    );
  }
}
