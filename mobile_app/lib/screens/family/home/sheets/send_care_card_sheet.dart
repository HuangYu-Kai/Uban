import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../models/elder.dart';
import '../../../../services/api_service.dart';
import '../../../../services/api/checkin_api.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/ui/uban_segmented.dart';
import '../../../../widgets/ui/uban_sheet.dart';
import '../../widgets/fam_ui.dart';

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
    return showUbanSheet(
      context,
      (ctx) => SendCareCardSheet(
        currentElder: currentElder,
        elderName: elderName,
        onCareMessageSent: onCareMessageSent,
      ),
      useRootNavigator: false,
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

  // ★ 2026-10-07 交接 C1：送出狀態。以前只寫一筆 activity_log 就說「已傳送」、語音檔根本沒上傳；
  //   現在要伺服器確認才算成功，失敗保留面板並顯示真實原因。
  bool _sending = false;
  String? _sendError;

  /// 家屬 id（與 AI 照護秘書分享同一來源 caregiver_id）。
  Future<int?> _familyId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('caregiver_id') ?? prefs.getInt('saved_id');
  }

  /// 文字：走「家人分享」`POST /api/community/posts`（author_role family），
  /// 與 AI 照護秘書分享草稿同一條路，長輩的小嘎開場會轉達。回傳錯誤原因，成功回 null。
  Future<String?> _sendTextShare(String text) async {
    final familyId = await _familyId();
    if (familyId == null) return '無法確認家屬身分，請重新登入後再試';
    final prefs = await SharedPreferences.getInstance();
    final userName =
        prefs.getString('caregiver_name') ?? prefs.getString('user_name') ?? '家人';
    final (data, err) = await ApiService.createCommunityPostChecked(
      familyId: familyId,
      authorId: familyId,
      authorName: userName,
      authorRole: 'family',
      content: text,
    );
    return data == null ? (err ?? '送出失敗，請稍後再試') : null;
  }

  /// 語音：貼文不支援音檔，改走 `POST /api/checkin_cheer`（純語音、不綁提醒），
  /// 長輩端既有的加油播放流程會播放。回傳錯誤原因，成功回 null。
  Future<String?> _sendVoiceCheer(String path) async {
    final familyId = await _familyId();
    final elderId = widget.currentElder?.elderId;
    if (familyId == null) return '無法確認家屬身分，請重新登入後再試';
    if (elderId == null || elderId.isEmpty) return '尚未取得長輩代碼，請稍後再試';
    final r = await CheckinApi.sendCheer(
      familyId: familyId,
      elderId: elderId,
      audioPath: path,
    );
    return r.ok ? null : r.message;
  }

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
    final c = UbanColors.of(context);

    // 外殼（圓角 32、grab、捲動、最高 86%）由 UbanSheet 提供。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _selectedTabIndex == 0 ? 'AI 近況貼心關懷' : '10 秒家屬原聲對講',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: famText(c.text, 18, weight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          _selectedTabIndex == 0
              ? '根據 ${widget.elderName} 近期話題與活動，AI 動態推薦問候'
              : '按住錄音即可傳送子女真實原聲至 ${widget.elderName} 的裝置',
          style: famText(c.text2, 13, height: 1.4),
        ),
        const SizedBox(height: 16),

        UbanSegmented(
          small: true,
          labels: const ['AI 近況短句', '原聲錄音對講'],
          index: _selectedTabIndex,
          onChanged: (i) => setState(() {
            _selectedTabIndex = i;
            _sendError = null;
          }),
        ),
        const SizedBox(height: 18),

        if (_selectedTabIndex == 0) ...[
          if (_isLoadingMessages)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(child: CircularProgressIndicator(color: c.brandFill)),
            )
          else
            ...List.generate(_dynamicCareMessages.length, (idx) {
              final card = _dynamicCareMessages[idx];
              final isSel = _selectedCardIndex == idx;
              // 與長輩選擇器同一套選取語彙：選中者 2px 品牌外框＋右側單選圓點。
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: c.surface2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSel ? c.brand : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => setState(() => _selectedCardIndex = idx),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  card['title']!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: famText(c.text, 15, weight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  card['desc']!,
                                  style: famText(c.text2, 13.5, height: 1.45),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSel ? c.brandFill : Colors.transparent,
                              border: Border.all(
                                color: isSel ? c.brandFill : c.line,
                                width: 2,
                              ),
                            ),
                            child: isSel
                                ? Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                        color: c.onBrand, shape: BoxShape.circle),
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 8),
          if (_sendError != null && _selectedTabIndex == 0) ...[
            Text(_sendError!, style: famText(c.danger, 13.5, height: 1.4)),
            const SizedBox(height: 8),
          ],
          FamButton(
            label: '推送 AI 貼心問候至長輩端',
            height: 52,
            loading: _sending,
            onPressed: (_sending || _dynamicCareMessages.isEmpty)
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final nav = Navigator.of(context);
                    final selectedObj = _dynamicCareMessages[_selectedCardIndex];
                    final desc = selectedObj['desc'] ?? '';
                    setState(() {
                      _sending = true;
                      _sendError = null;
                    });
                    final err = await _sendTextShare(desc);
                    if (!mounted) return;
                    if (err != null) {
                      setState(() {
                        _sending = false;
                        _sendError = err;
                      });
                      return;
                    }
                    widget.onCareMessageSent
                        ?.call('【AI 關懷傳送】${selectedObj['title']}：$desc');
                    nav.pop();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('已送出，小嘎會在${widget.elderName}下次聊天時轉達 ❤️',
                            style: famText(c.surface, 14, weight: FontWeight.w700)),
                      ),
                    );
                  },
          ),
        ],

        if (_selectedTabIndex == 1) ...[
          const SizedBox(height: 4),
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
                  // 錄音鈕：品牌實心圓（錄音中轉 danger），不帶色光暈。
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording ? c.danger : c.brandFill,
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                      color: _isRecording ? Colors.white : c.onBrand,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _isRecording
                      ? '正在錄音中... (${_recordingDuration}s / 10s)'
                      : _recordedFilePath != null
                          ? '錄音完成！長度: $_recordingDuration 秒'
                          : '按住大按鈕開始錄製 10 秒原聲關懷',
                  textAlign: TextAlign.center,
                  style: famText(_isRecording ? c.danger : c.brandStrong, 14,
                      weight: FontWeight.w700),
                ),
                const SizedBox(height: 16),

                if (_recordedFilePath != null && !_isRecording) ...[
                  FamButton(
                    label: _isPlayingPreview ? '暫停試聽' : '試聽原聲錄音',
                    kind: FamButtonKind.tonal,
                    height: 46,
                    expand: false,
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
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (_sendError != null && _selectedTabIndex == 1) ...[
            Text(_sendError!, style: famText(c.danger, 13.5, height: 1.4)),
            const SizedBox(height: 8),
          ],
          FamButton(
            label: '傳送 10 秒原聲語音至長輩端',
            height: 52,
            loading: _sending,
            onPressed: (_recordedFilePath == null || _sending || _isRecording)
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final nav = Navigator.of(context);
                    setState(() {
                      _sending = true;
                      _sendError = null;
                    });
                    final err = await _sendVoiceCheer(_recordedFilePath!);
                    if (!mounted) return;
                    if (err != null) {
                      setState(() {
                        _sending = false;
                        _sendError = err;
                      });
                      return;
                    }
                    widget.onCareMessageSent
                        ?.call('【家屬原聲對講】子女傳送了一段 10 秒原聲關懷語音 🎙️');
                    nav.pop();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('已送出原聲語音，${widget.elderName}會在開啟 App 時聽到 🔊',
                            style: famText(c.surface, 14, weight: FontWeight.w700)),
                      ),
                    );
                  },
          ),
        ],
      ],
    );
  }
}
