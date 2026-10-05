import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../models/memoir_story.dart';
import '../services/memoir_service.dart';
import '../theme/app_theme.dart';
import '../theme/family_theme.dart';
import '../screens/family/widgets/fam_data_ui.dart';
import '../screens/family/widgets/fam_ui.dart';

/// 長輩人生故事膠囊詳細視窗 (MemoirDetailSheet)
///
/// 提供懷舊繪本式排版、長輩原聲語音播放模擬（具備聲波動畫）、
/// 完整文字、以及子女「給長輩的悄悄話筆記」留言互動區。
///
/// 2026-10 外觀改版：換成家屬端新設計系統（海灣藍 ocean，見 theme/family_theme.dart
/// 與 theme/app_theme.dart 的 UbanColors.familyLight/familyDark）。本輪**純 UI 換皮**：
/// 收藏切換、分享、播放、關閉、所有 onTap/onPressed 閉包、Navigator、API、
/// SharedPreferences、狀態欄位與方法簽章皆與改版前相同，只換顏色／字型／圓角／元件外觀。
class MemoirDetailSheet extends StatefulWidget {
  final MemoirStory story;
  final String elderName;
  final String familyUserName;

  const MemoirDetailSheet({
    super.key,
    required this.story,
    required this.elderName,
    this.familyUserName = '家屬',
  });

  static Future<void> show(
    BuildContext context, {
    required MemoirStory story,
    required String elderName,
    String familyUserName = '家屬',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MemoirDetailSheet(
        story: story,
        elderName: elderName,
        familyUserName: familyUserName,
      ),
    );
  }

  @override
  State<MemoirDetailSheet> createState() => _MemoirDetailSheetState();
}

class _MemoirDetailSheetState extends State<MemoirDetailSheet> {
  late MemoirStory _currentStory;
  final TextEditingController _noteController = TextEditingController();
  bool _isFavorite = false;

  // 語音播放模擬狀態
  bool _isPlayingAudio = false;
  int _currentSeconds = 0;
  final int _totalSeconds = 135; // 2:15 總時長
  Timer? _audioTimer;

  // showModalBottomSheet 的路由不在呼叫端的 FamilyThemeScope 之下，
  // build() 自己掛一層；State 方法（例如 SnackBar）要用這個捕捉到的
  // context 才吃得到家屬色票，否則會落回 App 預設色票。
  BuildContext? _themed;
  BuildContext get _themeCtx => _themed ?? context;
  UbanColors get _c => UbanColors.of(_themeCtx);

  @override
  void initState() {
    super.initState();
    _currentStory = widget.story;
    _isFavorite = widget.story.isFavorite;
  }

  @override
  void dispose() {
    _audioTimer?.cancel();
    _noteController.dispose();
    super.dispose();
  }

  void _toggleAudioPlayback() {
    setState(() {
      _isPlayingAudio = !_isPlayingAudio;
    });

    if (_isPlayingAudio) {
      _audioTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() {
          if (_currentSeconds >= _totalSeconds) {
            _currentSeconds = 0;
            _isPlayingAudio = false;
            _audioTimer?.cancel();
          } else {
            _currentSeconds++;
          }
        });
      });
    } else {
      _audioTimer?.cancel();
    }
  }

  String _formatTime(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _submitFamilyNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty) return;

    final note = MemoirFamilyNote(
      author: widget.familyUserName,
      relation: '家屬',
      note: text,
      createdAt: DateTime.now(),
    );

    await MemoirService.instance.addFamilyNote(
      _currentStory.elderId,
      _currentStory.id,
      note,
    );

    setState(() {
      _currentStory = _currentStory.copyWith(
        familyNotes: List<MemoirFamilyNote>.from(_currentStory.familyNotes)..add(note),
      );
      _noteController.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('❤️ 已送出給長輩的溫馨留言！'),
          backgroundColor: _c.brandFill,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleFavorite() async {
    await MemoirService.instance.toggleFavorite(_currentStory.elderId, _currentStory.id);
    setState(() {
      _isFavorite = !_isFavorite;
      _currentStory = _currentStory.copyWith(isFavorite: _isFavorite);
    });
  }

  @override
  Widget build(BuildContext context) {
    // push 出去的家屬元件不在主殼的 Theme 之下，這裡自己包一層才吃得到家屬海灣藍色票。
    return FamilyThemeScope(
      child: Builder(builder: _buildSheet),
    );
  }

  Widget _buildSheet(BuildContext context) {
    _themed = context;
    final c = _c;
    final size = MediaQuery.of(context).size;

    return Container(
      constraints: BoxConstraints(
        maxHeight: size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: c.shadows.card,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 頂部拖曳把手
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: c.line,
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // 標題列
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                FamChip(label: _currentStory.tag, tone: FamTone.brand),
                const SizedBox(width: 8),
                Text(
                  DateFormat('yyyy年MM月dd日').format(_currentStory.recordedDate),
                  style: famText(c.text2, 12),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: _isFavorite ? c.warm : c.text2,
                    size: 24,
                  ),
                  tooltip: _isFavorite ? '已珍藏' : '加入珍藏',
                  onPressed: _toggleFavorite,
                ),
                FamIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '關閉',
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),

          // 滾動內容區
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 懷舊裝飾卡片與小豬引導問題
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: c.brandContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/images/memoir_card.png',
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: c.brandContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.auto_stories_rounded, color: c.brandStrong),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text('🐷 ', style: TextStyle(fontSize: 14)),
                                  Text(
                                    '小豬溫暖引導提問：',
                                    style: famText(c.brandStrong, 12, weight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _currentStory.promptQuestion.isNotEmpty
                                    ? '「${_currentStory.promptQuestion}」'
                                    : '「阿公，今天跟小豬分享您的故事好不好？」',
                                style: famText(c.text, 13, weight: FontWeight.w600, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 故事標題
                  Text(
                    _currentStory.title,
                    style: famText(c.text, 22, weight: FontWeight.w900, height: 1.3),
                  ),

                  const SizedBox(height: 14),

                  // 語音播放器卡片
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: c.brandSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: _toggleAudioPlayback,
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: c.brandFill,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isPlayingAudio ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: c.onBrand,
                              size: 26,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '${widget.elderName}的口述原聲錄音',
                                    style: famText(c.text, 13, weight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 6),
                                  if (_isPlayingAudio)
                                    Row(
                                      children: List.generate(4, (i) => Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                        width: 3,
                                        height: 10.0 + (i % 2 == 0 ? 6.0 : 0.0),
                                        decoration: BoxDecoration(
                                          color: c.brandFill,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ).animate(onPlay: (ctl) => ctl.repeat(reverse: true))
                                       .scaleY(begin: 0.4, end: 1.2, duration: 400.ms + (i * 100).ms)),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatTime(_currentSeconds),
                                    style: famText(c.brandStrong, 11, weight: FontWeight.bold, tabular: true),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: LinearProgressIndicator(
                                        value: _currentSeconds / _totalSeconds,
                                        backgroundColor: c.surface3,
                                        valueColor: AlwaysStoppedAnimation(c.brandFill),
                                        minHeight: 4,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _formatTime(_totalSeconds),
                                    style: famText(c.text3, 11, tabular: true),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 完整口述文字
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: c.shadows.card,
                    ),
                    child: Text(
                      _currentStory.fullStory,
                      style: famText(c.text, 16, weight: FontWeight.w500, height: 1.8),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── 子女悄悄話筆記區 ──
                  Row(
                    children: [
                      Icon(Icons.favorite_rounded, color: c.danger, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '家人給${widget.elderName}的悄悄話 (${_currentStory.familyNotes.length})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: famText(c.text, 15, weight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_currentStory.familyNotes.isEmpty)
                    const FamNote(
                      text: '尚無家人留下筆記，身為子女在下方留下第一則溫馨鼓勵吧！',
                    )
                  else
                    ..._currentStory.familyNotes.map((note) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${note.author} (${note.relation})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: famText(c.text, 13, weight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                DateFormat('MM/dd HH:mm').format(note.createdAt),
                                style: famText(c.text3, 11, tabular: true),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            note.note,
                            style: famText(c.text2, 13, height: 1.4),
                          ),
                        ],
                      ),
                    )),

                  const SizedBox(height: 12),

                  // 留言輸入框
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _noteController,
                          style: famText(c.text, 14),
                          decoration: InputDecoration(
                            hintText: '寫下給${widget.elderName}的溫馨叮嚀...',
                            hintStyle: famText(c.text3, 13),
                            filled: true,
                            fillColor: c.surface2,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: c.line),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: c.line),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: c.brandFill, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _submitFamilyNote,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.brandFill,
                          foregroundColor: c.onBrand,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: const Icon(Icons.send_rounded, size: 18),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
