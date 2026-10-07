import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../services/api/checkin_api.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ui/uban_sheet.dart';
import '../widgets/fam_ui.dart';

/// 送出動作的簽名（測試可注入假的；預設走 [CheckinApi.sendCheer]）。
typedef CheerSender = Future<CheerResult> Function({
  String? text,
  String? audioPath,
});

/// ★ 2026-10-07 打卡雙向互動：家屬對長輩「完成打卡」送出鼓勵（預設短句／文字／錄音）。
///
/// 文字由後端交給小嘎唸給長輩聽；錄音則直接播放家屬本人的聲音。
/// 錄音沿用 [SendCareCardSheet] 的 `record` 權限與 aacLc/.m4a 作法，上限 30 秒。
/// 成功時以 `Navigator.pop(true)` 關閉，呼叫端據此顯示 SnackBar 並標記「已鼓勵」。
class SendCheerSheet extends StatefulWidget {
  final String elderName;
  final String itemTitle;
  final int familyId;
  final String elderId;
  final int? reminderId;
  final String? localDate;

  /// 測試注入點；null 時使用真實 API。
  final CheerSender? sender;

  const SendCheerSheet({
    super.key,
    required this.elderName,
    required this.itemTitle,
    required this.familyId,
    required this.elderId,
    this.reminderId,
    this.localDate,
    this.sender,
  });

  static const List<String> presets = ['好棒！', '辛苦了', '我以你為榮', '記得多喝水', '愛你喔'];
  static const int maxRecordSeconds = 30;
  static const int maxTextLength = 100;

  /// 顯示面板；回傳 true 表示已成功送出。
  static Future<bool> show(
    BuildContext context, {
    required String elderName,
    required String itemTitle,
    required int familyId,
    required String elderId,
    int? reminderId,
    String? localDate,
  }) async {
    final r = await showUbanSheet<bool>(
      context,
      (ctx) => SendCheerSheet(
        elderName: elderName,
        itemTitle: itemTitle,
        familyId: familyId,
        elderId: elderId,
        reminderId: reminderId,
        localDate: localDate,
      ),
    );
    return r == true;
  }

  @override
  State<SendCheerSheet> createState() => _SendCheerSheetState();
}

class _SendCheerSheetState extends State<SendCheerSheet> {
  final TextEditingController _text = TextEditingController();
  // 錄音器／播放器延後到真正需要時才建立（測試環境沒有平台通道，建構期間不碰）。
  AudioRecorder? _recorder;
  AudioPlayer? _player;
  StreamSubscription<void>? _playerDone;

  bool _recording = false;
  bool _playing = false;
  bool _sending = false;
  int _elapsed = 0;
  int _recordedSeconds = 0;
  String? _audioPath;
  String? _error;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _playerDone?.cancel();
    _recorder?.dispose();
    _player?.dispose();
    _text.dispose();
    super.dispose();
  }

  void _setError(String? m) {
    if (mounted) setState(() => _error = m);
  }

  Future<void> _startRecording() async {
    if (_sending || _recording) return;
    try {
      final rec = _recorder ??= AudioRecorder();
      if (!await rec.hasPermission()) {
        _setError('需要允許麥克風權限才能錄音，請到手機設定開啟');
        return;
      }
      await _stopPlayback();
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/cheer_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await rec.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _elapsed = 0;
        _audioPath = null;
        _error = null;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        if (_elapsed + 1 >= SendCheerSheet.maxRecordSeconds) {
          setState(() => _elapsed = SendCheerSheet.maxRecordSeconds);
          _stopRecording();
        } else {
          setState(() => _elapsed++);
        }
      });
    } catch (e) {
      debugPrint('⚠️ [SendCheerSheet] 開始錄音失敗: $e');
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
      debugPrint('⚠️ [SendCheerSheet] 停止錄音失敗: $e');
    }
    if (!mounted) return;
    final secs = _elapsed;
    setState(() {
      _recording = false;
      if (path == null || secs < 1) {
        _audioPath = null;
        _recordedSeconds = 0;
        _error = '錄音太短了，請按住說話鍵再說久一點';
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
    if (path == null) return;
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
      debugPrint('⚠️ [SendCheerSheet] 試聽失敗: $e');
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

  bool get _hasContent => _text.text.trim().isNotEmpty || _audioPath != null;

  Future<void> _send() async {
    if (_sending || _recording || !_hasContent) return;
    await _stopPlayback();
    setState(() {
      _sending = true;
      _error = null;
    });
    final text = _text.text.trim();
    final sender = widget.sender;
    final CheerResult r;
    if (sender != null) {
      r = await sender(text: text.isEmpty ? null : text, audioPath: _audioPath);
    } else {
      r = await CheckinApi.sendCheer(
        familyId: widget.familyId,
        elderId: widget.elderId,
        reminderId: widget.reminderId,
        localDate: widget.localDate,
        text: text.isEmpty ? null : text,
        audioPath: _audioPath,
      );
    }
    if (!mounted) return;
    if (r.ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _sending = false;
        _error = r.message;
      });
    }
  }

  void _pickPreset(String phrase) {
    if (_sending) return;
    setState(() {
      _text.text = phrase;
      _text.selection = TextSelection.collapsed(offset: phrase.length);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final canSend = _hasContent && !_recording && !_sending;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 標題字串含長輩姓名／事項名稱（長度不可控），一律 maxLines＋ellipsis（規則 14）。
        Text(
          '送個鼓勵給${widget.elderName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: famText(c.text, 18, weight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          '完成了「${widget.itemTitle}」',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: famText(c.text2, 13, height: 1.4),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in SendCheerSheet.presets)
              ActionChip(
                key: ValueKey('preset_$p'),
                label: Text(p, style: famText(c.brandStrong, 14, weight: FontWeight.w700)),
                backgroundColor: c.brandContainer,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                onPressed: _sending ? null : () => _pickPreset(p),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('cheer_text'),
          controller: _text,
          enabled: !_sending,
          maxLength: SendCheerSheet.maxTextLength,
          maxLines: 2,
          minLines: 1,
          onChanged: (_) => setState(() => _error = null),
          style: famText(c.text, 15),
          decoration: InputDecoration(
            hintText: '想對${widget.elderName}說的話（可不填）',
            hintStyle: famText(c.text3, 14),
            filled: true,
            fillColor: c.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildRecorder(c),
        const SizedBox(height: 10),
        Text(
          '文字會由小嘎唸給長輩聽，錄音會直接播放您的聲音',
          textAlign: TextAlign.center,
          style: famText(c.text3, 12.5, height: 1.4),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            key: const ValueKey('cheer_error'),
            textAlign: TextAlign.center,
            style: famText(c.danger, 13.5, weight: FontWeight.w700, height: 1.4),
          ),
        ],
        const SizedBox(height: 12),
        FamButton(
          key: const ValueKey('cheer_send'),
          label: _sending ? '送出中…' : '送出鼓勵',
          height: 52,
          loading: _sending,
          onPressed: canSend ? _send : null,
        ),
      ],
    );
  }

  Widget _buildRecorder(UbanColors c) {
    final String status;
    if (_recording) {
      status = '錄音中… $_elapsed／${SendCheerSheet.maxRecordSeconds} 秒（放開即停止）';
    } else if (_audioPath != null) {
      status = '已錄好 $_recordedSeconds 秒';
    } else {
      status = '按住麥克風說句話（最長 ${SendCheerSheet.maxRecordSeconds} 秒）';
    }
    return Column(
      children: [
        GestureDetector(
          key: const ValueKey('cheer_record'),
          onLongPressStart: (_) => _startRecording(),
          onLongPressEnd: (_) => _stopRecording(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _recording ? c.danger : c.brandFill,
            ),
            child: Icon(
              _recording ? Icons.stop_rounded : Icons.mic_rounded,
              color: _recording ? Colors.white : c.onBrand,
              size: 36,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          status,
          textAlign: TextAlign.center,
          style: famText(_recording ? c.danger : c.brandStrong, 13.5,
              weight: FontWeight.w700),
        ),
        if (_audioPath != null && !_recording) ...[
          const SizedBox(height: 8),
          // 窄螢幕下兩顆按鈕可換行（Wrap），不用 Row（規則 14）。
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              FamButton(
                label: _playing ? '停止試聽' : '試聽',
                kind: FamButtonKind.tonal,
                height: 40,
                expand: false,
                onPressed: _sending ? null : _togglePreview,
              ),
              FamButton(
                label: '刪除重錄',
                kind: FamButtonKind.outline,
                height: 40,
                expand: false,
                onPressed: _sending ? null : _deleteRecording,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
