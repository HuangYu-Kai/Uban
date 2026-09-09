import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../models/memoir_story.dart';
import '../services/memoir_service.dart';

/// 長輩人生故事膠囊詳細視窗 (MemoirDetailSheet)
///
/// 提供懷舊繪本式排版、長輩原聲語音播放模擬（具備聲波動畫）、
/// 完整文字、以及子女「給長輩的悄悄話筆記」留言互動區。
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
        const SnackBar(
          content: Text('❤️ 已送出給長輩的溫馨留言！'),
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 2),
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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Container(
      constraints: BoxConstraints(
        maxHeight: size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A222D) : const Color(0xFFFAF8F5),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: cs.outline.withValues(alpha: isDark ? 0.3 : 0.8),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
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
              color: cs.outline.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // 標題列
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.tertiary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.outline, width: 1.2),
                  ),
                  child: Text(
                    _currentStory.tag,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('yyyy年MM月dd日').format(_currentStory.recordedDate),
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: _isFavorite ? const Color(0xFFEF4444) : cs.onSurfaceVariant,
                    size: 24,
                  ),
                  tooltip: _isFavorite ? '已珍藏' : '加入珍藏',
                  onPressed: _toggleFavorite,
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 24),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

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
                      color: isDark ? const Color(0xFF222D3D) : const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFF97316).withValues(alpha: 0.4),
                        width: 1.2,
                      ),
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
                                color: const Color(0xFFF97316).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.auto_stories_rounded, color: Color(0xFFF97316)),
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
                                    style: GoogleFonts.notoSansTc(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFFF97316),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _currentStory.promptQuestion.isNotEmpty
                                    ? '「${_currentStory.promptQuestion}」'
                                    : '「阿公，今天跟小豬分享您的故事好不好？」',
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                  height: 1.4,
                                ),
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
                    style: GoogleFonts.notoSansTc(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                      height: 1.3,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 語音播放器卡片
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF131B24) : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: _toggleAudioPlayback,
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: Color(0xFF3B82F6),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isPlayingAudio ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
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
                                    style: GoogleFonts.notoSansTc(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  if (_isPlayingAudio)
                                    Row(
                                      children: List.generate(4, (i) => Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                        width: 3,
                                        height: 10.0 + (i % 2 == 0 ? 6.0 : 0.0),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF3B82F6),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ).animate(onPlay: (c) => c.repeat(reverse: true))
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
                                    style: GoogleFonts.notoSansTc(
                                      fontSize: 11,
                                      color: const Color(0xFF3B82F6),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: LinearProgressIndicator(
                                        value: _currentSeconds / _totalSeconds,
                                        backgroundColor: cs.outline.withValues(alpha: 0.2),
                                        valueColor: const AlwaysStoppedAnimation(Color(0xFF3B82F6)),
                                        minHeight: 4,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _formatTime(_totalSeconds),
                                    style: GoogleFonts.notoSansTc(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant,
                                    ),
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
                      color: isDark ? const Color(0xFF1E2836) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: cs.outline.withValues(alpha: isDark ? 0.3 : 0.6),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: cs.outline.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      _currentStory.fullStory,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 16,
                        height: 1.8,
                        color: cs.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── 子女悄悄話筆記區 ──
                  Row(
                    children: [
                      const Icon(Icons.favorite_rounded, color: Color(0xFFEF4444), size: 18),
                      const SizedBox(width: 6),
                      Text(
                        '家人給${widget.elderName}的悄悄話 (${_currentStory.familyNotes.length})',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_currentStory.familyNotes.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(
                        '尚無家人留下筆記，身為子女在下方留下第一則溫馨鼓勵吧！',
                        style: GoogleFonts.notoSansTc(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    )
                  else
                    ..._currentStory.familyNotes.map((note) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF243042) : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${note.author} (${note.relation})',
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface,
                                ),
                              ),
                              Text(
                                DateFormat('MM/dd HH:mm').format(note.createdAt),
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            note.note,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                              height: 1.4,
                            ),
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
                          decoration: InputDecoration(
                            hintText: '寫下給${widget.elderName}的溫馨叮嚀...',
                            hintStyle: GoogleFonts.notoSansTc(fontSize: 13, color: cs.onSurfaceVariant),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF131B24) : Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: cs.outlineVariant),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: cs.outlineVariant),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: cs.primary, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _submitFamilyNote,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
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
