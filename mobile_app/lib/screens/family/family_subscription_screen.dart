import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_service.dart';

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
    'free':    {'display': '一般會員',  'price': 0,   'period': '',       'color': 0xFF9E9E9E, 'features': ['最多 2 台監視設備', '基礎 AI 對話', '標準電台頻道', '3 天活動紀錄']},
    'gold':    {'display': '黃金會員',  'price': 199, 'period': '/ 月',    'color': 0xFFFF9800, 'features': ['最多 3 台監視設備', '無限 AI 對話', '完整的劇本編輯器', 'AI 深度月報', '優先處理權']},
    'diamond': {'display': '鑽石會員',  'price': 499, 'period': '/ 月',    'color': 0xFF3F51B5, 'features': ['最多 5 台監視設備', '多達 3 台設備管理', '家屬端帳號無上限', '終身回憶錄雲端備份', '24/7 緊急救助連線']},
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

        final tierData = results[0];
        if (tierData['status'] == 'success' || tierData['tier_level'] != null) {
          setState(() {
            _currentTier = (tierData['tier_level'] ?? 'free').toString();
            _devicesMax = (tierData['devices_max'] ?? 2) as int;
          });
        }

        final recordsData = results[1];
        if (recordsData['status'] == 'success' || recordsData['records'] != null) {
          final list = (recordsData['records'] as List<dynamic>?) ?? [];
          setState(() {
            _records = list.map((r) => Map<String, dynamic>.from(r as Map)).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ [Subscription] 載入訂閱資料失敗: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '訂閱方案',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 目前層級 header ──
                  _buildCurrentTierBanner(),
                  const SizedBox(height: 32),
                  Text(
                    '選擇最適合您家人的方案',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '解鎖 AI 深度洞察，給予長輩最周全的陪伴',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // ── 方案卡片 ──
                  ..._buildPlanCards(),
                  const SizedBox(height: 32),
                  // ── 歷史記錄 ──
                  if (_records.isNotEmpty) ...[
                    Text(
                      '訂閱記錄',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._records.map((r) => _buildRecordRow(r)),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  // ── 目前在會員層級橫幅 ──
  Widget _buildCurrentTierBanner() {
    final meta = _tierMeta[_currentTier]!;
    final color = Color(meta["color"] as int);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '目前方案',
            style: GoogleFonts.notoSansTc(
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            meta["display"] as String,
            style: GoogleFonts.notoSansTc(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '最多 $_devicesMax 台監視設備',
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              color: Colors.white,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.2);
  }

  // ── 三個方案卡片 ──
  List<Widget> _buildPlanCards() {
    return _tierMeta.entries.map((entry) {
      final key = entry.key;
      final meta = entry.value;
      final isCurrent = key == _currentTier;
      final isPopular = key == 'gold';

      return _buildPlanCard(
        tierKey: key,
        title: meta["display"] as String,
        price: meta["price"] as int == 0 ? '免費' : 'NT\$ ${meta["price"]}',
        period: meta["period"] as String,
        subtitle: _tierSubtitle(key),
        color: Color(meta["color"] as int),
        features: (meta["features"] as List<String>),
        isPopular: isPopular,
        isCurrent: isCurrent,
      );
    }).toList();
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

  Widget _buildPlanCard({
    required String tierKey,
    required String title,
    required String price,
    String period = '',
    required String subtitle,
    required Color color,
    required List<String> features,
    bool isPopular = false,
    bool isCurrent = false,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isPopular ? color : Colors.grey.withValues(alpha: 0.2),
          width: isPopular ? 2 : 1,
        ),
        boxShadow: [
          if (isPopular)
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: Stack(
        children: [
          if (isPopular)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(22),
                    bottomLeft: Radius.circular(22),
                  ),
                ),
                child: Text(
                  '熱門推薦',
                  style: GoogleFonts.notoSansTc(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price,
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    if (period.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4, left: 4),
                        child: Text(
                          period,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                  ],
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const Divider(height: 32),
                ...features.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: color, size: 18),
                        const SizedBox(width: 12),
                        Text(
                          f,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isCurrent
                        ? null
                        : () {
                            // TODO: 整合 RevenueCat Purchases SDK 進行購買流程
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCurrent ? Colors.grey[100] : color,
                      foregroundColor: isCurrent ? Colors.grey : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: isCurrent
                          ? BorderSide(color: Colors.grey.shade300)
                          : null,
                    ),
                    child: Text(
                      isCurrent ? '當前方案' : '立即升級',
                      style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).slideX(begin: 0.1);
  }

  // ── 一筆歷史記錄列 ──
  Widget _buildRecordRow(Map<String, dynamic> record) {
    final tier = record['tier_level'] ?? 'free';
    final start = record['start_date'] ?? '';
    final end = record['end_date'] ?? '';
    final meta = _tierMeta[tier is String ? tier : 'free'] ?? _tierMeta['free']!;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Color(meta["color"] as int),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta["display"] as String,
                  style: GoogleFonts.notoSansTc(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (start.toString().isNotEmpty)
                  Text(
                    '${start.toString()} ~ ${end.toString()}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: Colors.grey[400]),
        ],
      ),
    );
  }
}