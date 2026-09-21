import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';
import '../emotion_timeline_screen.dart';

/// 😊 情緒時間軸預覽卡片（第四十九輪：接上真實資料）
///
/// 原本 100% 是假資料（`_loadEmotionData()` 硬編 6 個「開心/平靜」的時間點），
/// 是這輪修復的入口卡片——即使全頁修好了，家屬點進去之前看到的預覽還是假的
/// 就等於問題只修一半。改用 `GET /api/family_insight/emotion_events`：近 30
/// 天內真正被偵測到的負面情緒事件數量 + 最新一筆的摘要。
class EmotionPreviewCard extends StatefulWidget {
  final String elderName;
  final int? elderId;

  const EmotionPreviewCard({
    super.key,
    required this.elderName,
    this.elderId,
  });

  @override
  State<EmotionPreviewCard> createState() => _EmotionPreviewCardState();
}

enum _PreviewStatus { loading, hasData, empty, error }

class _EmotionPreviewCardState extends State<EmotionPreviewCard> {
  _PreviewStatus _status = _PreviewStatus.loading;
  List<Map<String, dynamic>> _events = [];
  String _errorMsg = '';

  static const int _lookbackDays = 30;

  @override
  void initState() {
    super.initState();
    _loadEmotionData();
  }

  @override
  void didUpdateWidget(EmotionPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.elderId != oldWidget.elderId) {
      _loadEmotionData();
    }
  }

  Future<void> _loadEmotionData() async {
    setState(() => _status = _PreviewStatus.loading);

    if (widget.elderId == null) {
      setState(() {
        _status = _PreviewStatus.error;
        _errorMsg = '尚未配對長輩';
      });
      return;
    }

    int? familyId;
    try {
      final prefs = await SharedPreferences.getInstance();
      familyId = prefs.getInt('caregiver_id');
    } catch (_) {
      familyId = null;
    }

    final resp = await ApiService.getEmotionEvents(
      widget.elderId.toString(),
      familyId: familyId,
      days: _lookbackDays,
      limit: 5,
    );

    if (!mounted) return;

    if (resp['status'] != 'success') {
      setState(() {
        _status = _PreviewStatus.error;
        // ★ 第五十一輪：同 emotion_timeline_screen.dart——FastAPI 錯誤回應
        // 只有 `detail`，原本的 fallback 鏈永遠取不到值，優先顯示 `detail`。
        _errorMsg = (resp['detail'] ?? resp['message'] ?? resp['error'] ?? '載入失敗').toString();
      });
      return;
    }

    final data = resp['data'] as Map<String, dynamic>?;
    final events = ((data?['events'] as List?) ?? []).cast<Map<String, dynamic>>();
    setState(() {
      _events = events;
      _status = events.isEmpty ? _PreviewStatus.empty : _PreviewStatus.hasData;
    });
  }

  Color get _accentColor {
    switch (_status) {
      case _PreviewStatus.hasData:
        return const Color(0xFFEF4444);
      case _PreviewStatus.error:
        return const Color(0xFF94A3B8);
      case _PreviewStatus.empty:
      case _PreviewStatus.loading:
        return const Color(0xFF10B981);
    }
  }

  String get _headerEmoji {
    switch (_status) {
      case _PreviewStatus.hasData:
        return '😟';
      case _PreviewStatus.error:
        return '⚠️';
      case _PreviewStatus.empty:
        return '😊';
      case _PreviewStatus.loading:
        return '⏳';
    }
  }

  String get _badgeText {
    switch (_status) {
      case _PreviewStatus.loading:
        return '載入中';
      case _PreviewStatus.error:
        return '載入失敗';
      case _PreviewStatus.empty:
        return '近$_lookbackDays天平穩';
      case _PreviewStatus.hasData:
        return '近$_lookbackDays天 ${_events.length} 次關注';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EmotionTimelineScreen(
              elderName: widget.elderName,
              elderId: widget.elderId,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFE2E8F0),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _accentColor.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    _headerEmoji,
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '情緒時間軸',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1E293B),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _accentColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _badgeText,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Color(0xFF94A3B8),
                    size: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildBody(),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '點擊查看完整情緒關注事件紀錄',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF64748B),
                      ),
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

  Widget _buildBody() {
    switch (_status) {
      case _PreviewStatus.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))),
        );
      case _PreviewStatus.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              const Icon(Icons.error_outline_rounded, size: 32, color: Color(0xFF94A3B8)),
              const SizedBox(height: 8),
              Text(
                _errorMsg,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansTc(fontSize: 13, color: const Color(0xFF64748B)),
              ),
            ],
          ),
        );
      case _PreviewStatus.empty:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              const Icon(Icons.sentiment_satisfied_alt_rounded, size: 40, color: Color(0xFF10B981)),
              const SizedBox(height: 12),
              Text(
                '近$_lookbackDays天沒有偵測到負面情緒事件',
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '也可能是這段期間對話較少，僅供參考',
                style: GoogleFonts.notoSansTc(
                  fontSize: 12,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        );
      case _PreviewStatus.hasData:
        final latest = _events.first;
        final isAngry = latest['emotion'] == 'angry';
        final rawText = (latest['raw_text'] as String?)?.trim();
        final ts = DateTime.tryParse((latest['timestamp'] ?? '').toString());
        final timeLabel = ts != null ? '${ts.month}/${ts.day} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}' : '';
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '最近一次：${isAngry ? '😠 生氣' : '😢 悲傷'}${timeLabel.isNotEmpty ? ' · $timeLabel' : ''}',
                style: GoogleFonts.notoSansTc(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFFEF4444)),
              ),
              if (rawText != null && rawText.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '「$rawText」',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF64748B), height: 1.4),
                ),
              ],
            ],
          ),
        );
    }
  }
}
