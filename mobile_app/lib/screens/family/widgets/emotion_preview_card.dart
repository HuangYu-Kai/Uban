import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';
import '../../../theme/app_theme.dart';
import '../emotion_timeline_screen.dart';
import 'fam_data_ui.dart';
import 'fam_ui.dart';

/// 情緒關注預覽卡片（家屬新設計 `.card` + `.sec-head`；點整張卡進情緒時間軸）（第四十九輪：接上真實資料）
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

  // 暖色只給「待處理」：有負面事件才用 warm 徽章，其餘中性；載入失敗用 danger 文字色在內文呈現。
  FamTone get _badgeTone {
    switch (_status) {
      case _PreviewStatus.hasData:
        return FamTone.warm;
      case _PreviewStatus.empty:
        return FamTone.brand;
      case _PreviewStatus.loading:
      case _PreviewStatus.error:
        return FamTone.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);

    return FamCard(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 標題與同列徽章：標題在 Expanded 內可收縮（鐵律 #14）。
          FamSecHead(
            title: '情緒關注',
            trailing: Flexible(child: FamChip(label: _badgeText, tone: _badgeTone)),
          ),
          const SizedBox(height: 12),
          _buildBody(c),
          const SizedBox(height: 12),
          Text(
            '點擊查看完整情緒關注事件紀錄',
            style: famText(c.text3, 12.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  /// `loading`／`error`／`empty` 都包在撐滿寬度的容器（[FamStateBlock]／`SizedBox(width: infinity)`）內，
  /// 讓內容相對整張卡片置中，不會縮寬貼齊左緣（第五十三輪「內部顯示歪一邊」的修法，沿用）。
  Widget _buildBody(UbanColors c) {
    switch (_status) {
      case _PreviewStatus.loading:
        return const FamStateBlock(
          height: 60,
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _PreviewStatus.error:
        return FamStateBlock(
          height: 60,
          child: Text(
            _errorMsg,
            textAlign: TextAlign.center,
            style: famText(c.text2, 13.5, height: 1.5),
          ),
        );
      case _PreviewStatus.empty:
        return FamStateBlock(
          height: 60,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '近$_lookbackDays天沒有偵測到負面情緒事件',
                textAlign: TextAlign.center,
                style: famText(c.text, 14.5, weight: FontWeight.w700, height: 1.4),
              ),
              const SizedBox(height: 4),
              Text(
                '也可能是這段期間對話較少，僅供參考',
                textAlign: TextAlign.center,
                style: famText(c.text2, 12.5, height: 1.4),
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
            color: c.surface2,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FamDot(color: c.warm, size: 10),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '最近一次：${isAngry ? '生氣' : '悲傷'}${timeLabel.isNotEmpty ? '・$timeLabel' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: famText(c.text, 14, weight: FontWeight.w700, height: 1.4),
                    ),
                  ),
                ],
              ),
              if (rawText != null && rawText.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '「$rawText」',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: famText(c.text2, 13, height: 1.5),
                ),
              ],
            ],
          ),
        );
    }
  }
}
