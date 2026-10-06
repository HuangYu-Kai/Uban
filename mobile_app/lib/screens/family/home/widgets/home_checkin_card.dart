import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../models/elder.dart';
import '../../../../services/api_service.dart';
import '../../../../widgets/ui/ui.dart';
import '../../widgets/fam_ui.dart';
import '../../../../utils/display_text.dart';

/// 家屬首頁「今日打卡」卡：長輩今天的目標／提醒完成進度（含長輩自建目標）。
///
/// 資料來自 `GET /api/reminder/elder/{id}/today-progress`（後端以台灣日期、與長輩端
/// 相同的「今天是否適用」規則計算）。家屬端沒有訂閱 `reminder-sync`（該回呼由長輩端畫面
/// 獨占），因此以「下拉重整（父層遞增 [refreshToken]）＋ 每 60 秒輕量輪詢」維持新鮮。
class HomeCheckinCard extends StatefulWidget {
  final Elder? currentElder;

  /// 父層下拉重整時遞增，卡片即重讀。
  final int refreshToken;

  const HomeCheckinCard({super.key, this.currentElder, this.refreshToken = 0});

  @override
  State<HomeCheckinCard> createState() => _HomeCheckinCardState();
}

class _HomeCheckinCardState extends State<HomeCheckinCard> {
  bool _loading = true;
  bool _error = false;
  Map<String, dynamic>? _data;
  Timer? _timer;

  String? get _elderId =>
      widget.currentElder?.elderId ?? widget.currentElder?.id.toString();

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load(silent: true));
  }

  @override
  void didUpdateWidget(covariant HomeCheckinCard old) {
    super.didUpdateWidget(old);
    if (old.currentElder?.elderId != widget.currentElder?.elderId ||
        old.currentElder?.id != widget.currentElder?.id ||
        old.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final id = _elderId;
    if (id == null) {
      if (mounted) setState(() { _loading = false; _error = false; _data = null; });
      return;
    }
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final d = await ApiService.getTodayProgress(id);
      if (!mounted) return;
      setState(() { _data = d; _loading = false; _error = false; });
    } catch (_) {
      if (!mounted) return;
      // 輪詢失敗且已有資料時保留舊資料，不閃錯誤。
      setState(() { _loading = false; _error = _data == null; });
    }
  }

  List<Map<String, dynamic>> get _items => [
        for (final e in (_data?['items'] as List? ?? const []))
          Map<String, dynamic>.from(e as Map),
      ];

  void _openAll() {
    final items = _items;
    showUbanSheet<void>(
      context,
      (ctx) => _CheckinListSheet(items: items),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final elderName = widget.currentElder?.name ?? '長輩';

    Widget body;
    if (_loading && _data == null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: c.brandFill),
          ),
        ),
      );
    } else if (_error) {
      body = Row(
        children: [
          Expanded(child: Text('暫時讀不到打卡進度', style: famText(c.text3, 14))),
          FamButton(
            label: '重試', kind: FamButtonKind.ghost, height: 40, expand: false,
            onPressed: _load,
          ),
        ],
      );
    } else {
      final items = _items;
      if (items.isEmpty) {
        body = Text('今天沒有安排的事項', style: famText(c.text3, 14));
      } else {
        final done = (_data?['done'] as num?)?.toInt() ?? 0;
        final total = (_data?['total'] as num?)?.toInt() ?? items.length;
        final pending = items.where((i) => i['completed'] != true).toList();
        final completed = items.where((i) => i['completed'] == true).toList();
        body = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            UbanProgressRing(done: done, total: total),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pending.isEmpty)
                    Text('今天都完成了', style: famText(c.text, 16, weight: FontWeight.w800))
                  else ...[
                    Text('下一件', style: famText(c.text3, 12.5)),
                    Text(
                      '${pending.first['time_str']}　${stripEmoji(pending.first['title'].toString())}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: famText(c.text, 15.5, weight: FontWeight.w800, height: 1.3),
                    ),
                  ],
                  if (completed.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final i in completed.take(3))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_rounded, size: 15, color: c.brandStrong),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                stripEmoji(i['title'].toString()),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: famText(c.text2, 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        );
      }
    }

    return FamCard(
      onTap: (_data != null && _items.isNotEmpty) ? _openAll : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FamSecHead(
            title: '今日打卡',
            trailing: Text(elderName,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: famText(c.text3, 13)),
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }
}

class _CheckinListSheet extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _CheckinListSheet({required this.items});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final done = items.where((i) => i['completed'] == true).length;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FamSecHead(
            title: '今日打卡',
            trailing: FamChip(label: '$done／${items.length}', tone: FamTone.brand),
          ),
          const SizedBox(height: 8),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    i['completed'] == true
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 22,
                    color: i['completed'] == true ? c.brandStrong : c.text3,
                  ),
                  const SizedBox(width: 10),
                  Text(i['time_str'].toString(),
                      style: famText(c.text2, 14, weight: FontWeight.w700, tabular: true)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      stripEmoji(i['title'].toString()),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: famText(
                        i['completed'] == true ? c.text3 : c.text, 15,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (i['created_by_role'] == 'elder') ...[
                    const SizedBox(width: 8),
                    const FamChip(label: '長輩自訂', tone: FamTone.info),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
