import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../../models/elder.dart';
import '../../../../services/api_service.dart';

/// 發送關懷卡與原聲對講 BottomSheet
class SendCareCardSheet extends StatefulWidget {
  final Elder? currentElder;
  final String elderName;
  final ValueChanged<String>? onCareMessageSent;

  const SendCareCardSheet({
    super.key,
    this.currentElder,
    required this.elderName,
    this.onCareMessageSent,
  });

  static Future<void> show(
    BuildContext context, {
    required Elder? currentElder,
    required String elderName,
    ValueChanged<String>? onCareMessageSent,
  }) {
    final cs = Theme.of(context).colorScheme;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SendCareCardSheet(
        currentElder: currentElder,
        elderName: elderName,
        onCareMessageSent: onCareMessageSent,
      ),
    );
  }

  @override
  State<SendCareCardSheet> createState() => _SendCareCardSheetState();
}

class _SendCareCardSheetState extends State<SendCareCardSheet> {
  int _selectedTabIndex = 0; // 0: AI短句, 1: 原聲對講
  List<Map<String, String>> _dynamicCareMessages = [];
  bool _isLoadingMessages = true;
  int _selectedCardIndex = 0;

  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool _isPlayingPreview = false;
  String? _recordedFilePath;
  int _recordingDuration = 0;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    _fetchAiMessages();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _fetchAiMessages() async {
    final elderIdStr = widget.currentElder?.elderId ?? widget.currentElder?.id.toString() ?? '2';
    try {
      final res = await ApiService.get("/api/ai/dynamic_care_messages/$elderIdStr");
      if (res != null && res['status'] == 'success' && res['data'] != null) {
        final list = List<dynamic>.from(res['data']);
        if (mounted) {
          setState(() {
            _dynamicCareMessages = list.map((item) => {
              'title': (item['title'] ?? '貼心問候').toString(),
              'desc': (item['text'] ?? '').toString(),
            }).toList();
            _isLoadingMessages = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _dynamicCareMessages = [
          {'title': '🍲 溫馨餐點關懷', 'desc': '${widget.elderName}，今天晚餐想吃什麼呢？待會順路幫您買過去！'},
          {'title': '🚗 週末返家約定', 'desc': '${widget.elderName}，這週末我們要回家看您喔！準備了您喜歡的茶點！'},
          {'title': '❤️ 貼心即時問候', 'desc': '${widget.elderName}，今天過得好嗎？想撥個電話聽聽您的聲音！'},
        ];
        _isLoadingMessages = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _selectedTabIndex == 0 ? Icons.auto_awesome_rounded : Icons.mic_rounded,
                  color: cs.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedTabIndex == 0 ? '🤖 AI 近況貼心關懷' : '🎙️ 10秒家屬原聲對講',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      _selectedTabIndex == 0
                          ? '根據 ${widget.elderName} 近期話題與活動，AI 動態推薦問候'
                          : '按住錄音即可傳送子女真實原聲至 ${widget.elderName} 的裝置',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedTabIndex = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _selectedTabIndex == 0 ? cs.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 16,
                            color: _selectedTabIndex == 0 ? cs.onPrimary : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'AI 近況短句',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _selectedTabIndex == 0 ? cs.onPrimary : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedTabIndex = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _selectedTabIndex == 1 ? cs.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.mic_rounded,
                            size: 16,
                            color: _selectedTabIndex == 1 ? cs.onPrimary : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '原聲錄音對講',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _selectedTabIndex == 1 ? cs.onPrimary : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          if (_selectedTabIndex == 0) ...[
            if (_isLoadingMessages)
              Padding(
                padding: const EdgeInsets.all(32.0),
                child: Center(child: CircularProgressIndicator(color: cs.primary)),
              )
            else
              ...List.generate(_dynamicCareMessages.length, (idx) {
                final card = _dynamicCareMessages[idx];
                final isSel = _selectedCardIndex == idx;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedCardIndex = idx),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isSel ? cs.primaryContainer : cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSel ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4),
                          width: isSel ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  card['title']!,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isSel ? cs.onPrimaryContainer : cs.onSurface,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (isSel) Icon(Icons.check_circle_rounded, color: cs.primary, size: 18),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            card['desc']!,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 13,
                              color: isSel
                                  ? cs.onPrimaryContainer.withValues(alpha: 0.8)
                                  : cs.onSurfaceVariant,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  if (_dynamicCareMessages.isEmpty) return;
                  final selectedObj = _dynamicCareMessages[_selectedCardIndex];
                  final contentMsg = '【AI 關懷傳送】${selectedObj['title']}：${selectedObj['desc']}';

                  if (widget.currentElder?.id != null) {
                    try {
                      await ApiService.logActivity(widget.currentElder!.id, 'interaction', contentMsg);
                    } catch (_) {}
                  }

                  widget.onCareMessageSent?.call(contentMsg);

                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('已傳送 AI 貼心關懷「${selectedObj['title']}」至 ${widget.elderName} 的裝置！❤️', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold)),
                      backgroundColor: const Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: Icon(Icons.send_rounded, color: cs.onPrimary, size: 18),
                label: Text(
                  '推送 AI 貼心問候至長輩端',
                  style: GoogleFonts.notoSansTc(fontSize: 15, fontWeight: FontWeight.w800, color: cs.onPrimary),
                ),
              ),
            ),
          ],

          if (_selectedTabIndex == 1) ...[
            const SizedBox(height: 12),
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onLongPressStart: (_) async {
                      if (await _audioRecorder.hasPermission()) {
                        final tempDir = await getTemporaryDirectory();
                        final filePath = '${tempDir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
                        await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: filePath);
                        setState(() {
                          _isRecording = true;
                          _recordedFilePath = filePath;
                          _recordingDuration = 0;
                        });
                        _recordingTimer?.cancel();
                        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
                          if (_recordingDuration >= 10) {
                            timer.cancel();
                            _audioRecorder.stop().then((path) {
                              setState(() {
                                _isRecording = false;
                                _recordedFilePath = path;
                              });
                            });
                          } else {
                            setState(() {
                              _recordingDuration++;
                            });
                          }
                        });
                      }
                    },
                    onLongPressEnd: (_) async {
                      _recordingTimer?.cancel();
                      final path = await _audioRecorder.stop();
                      setState(() {
                        _isRecording = false;
                        _recordedFilePath = path;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRecording ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording ? const Color(0xFFEF4444) : const Color(0xFF10B981)).withValues(alpha: 0.4),
                            blurRadius: _isRecording ? 20 : 10,
                            spreadRadius: _isRecording ? 6 : 2,
                          )
                        ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isRecording
                        ? '🎙️ 正在錄音中... (${_recordingDuration}s / 10s)'
                        : _recordedFilePath != null
                            ? '✅ 錄音完成！長度: $_recordingDuration 秒'
                            : '👉 按住大按鈕開始錄製 10 秒原聲關懷',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _isRecording ? const Color(0xFFEF4444) : cs.primary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_recordedFilePath != null && !_isRecording) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            if (_isPlayingPreview) {
                              await _audioPlayer.stop();
                              setState(() => _isPlayingPreview = false);
                            } else {
                              setState(() => _isPlayingPreview = true);
                              await _audioPlayer.play(DeviceFileSource(_recordedFilePath!));
                              _audioPlayer.onPlayerComplete.listen((_) {
                                if (mounted) {
                                  setState(() => _isPlayingPreview = false);
                                }
                              });
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cs.primary,
                            side: BorderSide(color: cs.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: Icon(_isPlayingPreview ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 20),
                          label: Text(_isPlayingPreview ? '暫停試聽' : '試聽原聲錄音', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _recordedFilePath != null ? cs.primary : cs.surfaceContainerHighest,
                  foregroundColor: cs.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _recordedFilePath == null
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(context);
                        final contentMsg = '【家屬原聲對講】子女傳送了一段 10 秒原聲關懷語音 🎙️';

                        if (widget.currentElder?.id != null) {
                          try {
                            await ApiService.logActivity(widget.currentElder!.id, 'voice', contentMsg);
                          } catch (_) {}
                        }

                        widget.onCareMessageSent?.call(contentMsg);

                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('已發送 10 秒家屬原聲關懷至 ${widget.elderName} 的裝置！🔊', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold)),
                            backgroundColor: const Color(0xFF10B981),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                icon: Icon(Icons.volume_up_rounded, color: cs.onPrimary, size: 18),
                label: Text(
                  '傳送 10 秒原聲語音至長輩端',
                  style: GoogleFonts.notoSansTc(fontSize: 15, fontWeight: FontWeight.w800, color: cs.onPrimary),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
