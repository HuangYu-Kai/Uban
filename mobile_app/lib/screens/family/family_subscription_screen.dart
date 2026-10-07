import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_service.dart';
import '../../theme/family_theme.dart';
import '../../widgets/ui/ui.dart';
import 'widgets/fam_data_ui.dart';
import 'widgets/fam_ui.dart';

/// 家屬端訂閱方案頁（`.prohero` + `.plan`）。
///
/// 2026-10 起外觀改家屬新設計；方案、價格、功能清單與讀取訂閱／記錄的 API 與改版前相同。
/// 「立即升級」目前仍是空操作（購買流程在 `SubscriptionTestScreen`／RevenueCat，下一批處理）。
class FamilySubscriptionScreen extends StatefulWidget {
  const FamilySubscriptionScreen({super.key});

  @override
  State<FamilySubscriptionScreen> createState() =>
      _FamilySubscriptionScreenState();
}

class _FamilySubscriptionScreenState extends State<FamilySubscriptionScreen> {
  String _currentTier = 'free';
  int _devicesMax = 2;
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  int? _userId;

  static const _tierMeta = {
    'free':    {'display': '一般會員',  'price': 0,   'period': '',       'features': ['最多 2 台監視設備', '基礎 AI 對話', '標準電台頻道', '3 天活動紀錄']},
    'gold':    {'display': '黃金會員',  'price': 199, 'period': '/ 月',    'features': ['最多 3 台監視設備', '無限 AI 對話', '完整的劇本編輯器', 'AI 深度月報', '優先處理權']},
    'diamond': {'display': '鑽石會員',  'price': 499, 'period': '/ 月',    'features': ['最多 5 台監視設備', '多達 3 台設備管理', '家屬端帳號無上限', '終身回憶錄雲端備份', '24/7 緊急救助連線']},
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _userId = prefs.getInt('saved_id') ?? prefs.getInt('caregiver_id');

      if (_userId != null) {
        final results = await Future.wait([
          ApiService.getSubscriptionTier(_userId!),
          ApiService.getSubscriptionRecords(_userId!),
        ]);

        // ★ 2026-10-07 交接 B2：後端回 {status, data:{tier_level, devices_max, ...}} /
        //   {status, data:{records:[...]}}，原本讀最外層 → 永遠顯示一般會員；改讀 data。
        final tierRes = results[0];
        final tierData = tierRes['data'] is Map
            ? Map<String, dynamic>.from(tierRes['data'] as Map)
            : <String, dynamic>{};
        if (tierRes['status'] == 'success' && tierData['tier_level'] != null) {
          if (!mounted) return;
          setState(() {
            _currentTier = tierData['tier_level'].toString();
            _devicesMax = (tierData['devices_max'] as num?)?.toInt() ?? 2;
          });
        }

        final recRes = results[1];
        final recData = recRes['data'] is Map
            ? Map<String, dynamic>.from(recRes['data'] as Map)
            : <String, dynamic>{};
        if (recRes['status'] == 'success') {
          final list = (recData['records'] as List<dynamic>?) ?? [];
          if (!mounted) return;
          setState(() {
            _records = list.map((r) => Map<String, dynamic>.from(r as Map)).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ [Subscription] 載入訂閱資料失敗: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  // 家屬主題之下的 context（State 自己的 context 在 FamilyThemeScope 之上）；每次 build 更新。
  BuildContext? _themed;
  BuildContext get _themeCtx => _themed ?? context;
  UbanColors get _c => UbanColors.of(_themeCtx);

  @override
  Widget build(BuildContext context) {
    // 2026-10：push 出來的家屬頁要自己掛家屬主題；Builder 讓下方 context 位於主題之內。
    return FamilyThemeScope(
      child: Builder(builder: _buildScreen),
    );
  }

  Widget _buildScreen(BuildContext context) {
    _themed = context;
    final c = _c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: famSubBar(context, title: '訂閱方案'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 目前層級 `.prohero` ──
                  _buildCurrentTierBanner(),
                  const SizedBox(height: 22),
                  Text(
                    '選擇最適合您家人的方案',
                    style: famText(c.text, 20, weight: FontWeight.w900, height: 1.3),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '解鎖 AI 深度洞察，給予長輩最周全的陪伴',
                    style: famText(c.text2, 14, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  // ── 方案卡片 ──
                  ..._buildPlanCards(),
                  // ── 歷史記錄 ──
                  if (_records.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _buildRecords(),
                  ],
                ],
              ),
            ),
    );
  }

  Map<String, Object> get _currentMeta =>
      _tierMeta[_currentTier] ?? _tierMeta['free']!;

  // ── 目前在會員層級橫幅（`.prohero`：flat brandContainer，不用漸層） ──
  Widget _buildCurrentTierBanner() {
    final c = _c;
    final meta = _currentMeta;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.brandContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('目前方案', style: famText(c.text2, 13, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            meta['display'] as String,
            style: famText(c.brandStrong, 24, weight: FontWeight.w900, height: 1.3),
          ),
          const SizedBox(height: 8),
          Text(
            '最多 $_devicesMax 台監視設備',
            style: famText(c.text2, 14.5, height: 1.6),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  // ── 三個方案卡片 ──
  List<Widget> _buildPlanCards() {
    final out = <Widget>[];
    for (final entry in _tierMeta.entries) {
      final key = entry.key;
      final meta = entry.value;
      final isCurrent = key == _currentTier;
      final isPopular = key == 'gold';
      final price = meta['price'] as int;

      out.add(const SizedBox(height: 10));
      out.add(
        FamPlanCard(
          title: meta['display'] as String,
          price: price == 0 ? '免費' : 'NT\$ $price',
          period: (meta['period'] as String).replaceAll('/ 月', '／月'),
          subtitle: _tierSubtitle(key),
          features: (meta['features'] as List<String>),
          selected: isCurrent,
          badge: isCurrent ? '目前方案' : (isPopular ? '熱門推薦' : null),
          badgeTone: isCurrent ? FamTone.brand : FamTone.info,
          action: FamButton(
            label: isCurrent ? '當前方案' : '立即升級',
            kind: isCurrent ? FamButtonKind.outline : FamButtonKind.filled,
            onPressed: isCurrent
                ? null
                : () {
                    // TODO: 整合 RevenueCat Purchases SDK 進行購買流程
                  },
          ),
        ).animate().fadeIn(duration: 400.ms),
      );
    }
    return out;
  }

  String _tierSubtitle(String tierKey) {
    switch (tierKey) {
      case 'free':
        return '基礎陪伴與體驗';
      case 'gold':
        return '深度情緒分析與長期記憶';
      case 'diamond':
        return '多設備管理與 24/7 緊急救助';
      default:
        return '';
    }
  }

  Widget _buildRecords() {
    return FamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FamSecHead(title: '訂閱記錄'),
          const SizedBox(height: 6),
          for (var i = 0; i < _records.length; i++)
            _buildRecordRow(_records[i], first: i == 0),
        ],
      ),
    );
  }

  // ── 一筆歷史記錄列 ──
  Widget _buildRecordRow(Map<String, dynamic> record, {bool first = false}) {
    final c = _c;
    final tier = record['tier_level'] ?? 'free';
    final start = record['start_date'] ?? '';
    final end = record['end_date'] ?? '';
    final meta = _tierMeta[tier is String ? tier : 'free'] ?? _tierMeta['free']!;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          FamDot(color: tier == 'free' ? c.text3 : c.brand, size: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta['display'] as String,
                  style: famText(c.text, 15, weight: FontWeight.w700),
                ),
                if (start.toString().isNotEmpty)
                  Text(
                    '${start.toString()} ~ ${end.toString()}',
                    style: famText(c.text2, 12.5, tabular: true, height: 1.4),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
