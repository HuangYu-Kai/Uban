import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
// ★ 2026-08-17 第二十五輪（需求 7）：讀取目前登入家屬的 caregiver_id，
//   以呼叫 GET /api/alerts/{elder_id} 時帶上後端要求的 user_id 關係驗證。
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/elder.dart';
import '../../services/api_service.dart';
import 'alert_center_screen.dart';
import 'zone_calibration_screen.dart';

/// 🏠 子女端首頁 Tab (全新極光玻璃與 AI 情緒氣象台 + 生活時光牆)
class FamilyHomeTab extends StatefulWidget {
  final Elder? currentElder;
  final bool isElderOnline;
  final VoidCallback? onNavigateToAlerts;

  /// ★ 2026-08-10 第十九輪（需求 4）：「撥打電話聊聊 → 開始撥號」的實際動作。
  /// 分支整合後這顆按鈕只剩一個 SnackBar、完全不會撥號；改由父層
  /// `FamilyMainScreen` 注入與互動分頁同一條 `VideoCallScreen` 路徑
  /// （帶 `targetSocketId`），避免這裡再自行拼一份房號邏輯而漂移。
  final List<Map<String, dynamic>> activeAlerts;
  final VoidCallback? onStartVideoCall;

  /// ★ 2026-08-18 IPS prototype：長輩目前所在區域卡片所需資料，全部由父層
  /// `FamilyMainScreen` 提供，本分頁不自行呼叫 API（與 [activeAlerts] 同一套
  /// 「父層擁有資料來源」慣例）。
  /// [monitorDevices] 與傳給 `FamilyInteractionTab` 的是同一份清單（已過濾成
  /// 只含 `deviceMode=='monitor'` 的裝置），用來判斷「是否已綁定監視機」與
  /// 取得第一台監視機的 deviceId/deviceName（開啟校準畫面用）。
  /// [elderZone] 是正規化後的 `{zone, enteredAt, updatedAt}`，null 代表尚無
  /// 任何定位紀錄。
  final List<dynamic> monitorDevices;
  final Map<String, dynamic>? elderZone;
  final int? userId;

  const FamilyHomeTab({
    super.key,
    this.currentElder,
    this.isElderOnline = false,
    this.activeAlerts = const [],
    this.monitorDevices = const [],
    this.elderZone,
    this.userId,
    this.onNavigateToAlerts,
    this.onStartVideoCall,
  });

  @override
  State<FamilyHomeTab> createState() => _FamilyHomeTabState();
}

class _FamilyHomeTabState extends State<FamilyHomeTab> {
  void _showSendCareCardModal(BuildContext context, String elderName) {
    final List<Map<String, String>> careCards = [
      {'title': '週末溫馨聚餐卡 🍲', 'desc': '阿公，這個週末一起去吃美味熱呼呼的火鍋好嗎？我訂好餐廳囉！'},
      {'title': '午後語音茶會卡 🍵', 'desc': '阿公，下午放鬆一下，喝杯溫茶，我待會撥視訊電話給您聊聊昔日故事！'},
      {'title': '天天開心健康關懷卡 ❤️', 'desc': '祝阿公今天也有個好心情！記得多喝水、動動身體，女兒隨時想念您喔！'},
    ];

    String selectedCard = careCards[0]['title']!;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.mark_email_unread_rounded, color: Color(0xFFF59E0B), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '傳送親情關懷卡片',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '選擇溫馨卡片傳送至 $elderName 的通話視訊機',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 12,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ...careCards.map((card) {
                    final isSel = selectedCard == card['title'];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        onTap: () {
                          setModalState(() {
                            selectedCard = card['title']!;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSel ? const Color(0xFF38BDF8).withValues(alpha: 0.15) : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSel ? const Color(0xFF38BDF8) : Colors.white12,
                              width: isSel ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                card['title']!,
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isSel ? const Color(0xFF38BDF8) : Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                card['desc']!,
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 12,
                                  color: const Color(0xFFCBD5E1),
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
                        backgroundColor: const Color(0xFF38BDF8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(ctx);
                        final selectedObj = careCards.firstWhere((c) => c['title'] == selectedCard);
                        final contentMsg = '【家族心意】收到女兒傳送的「${selectedObj['title']}」：${selectedObj['desc']}';

                        if (widget.currentElder?.id != null) {
                          try {
                            await ApiService.logActivity(widget.currentElder!.id, 'interaction', contentMsg);
                          } catch (_) {}
                        }

                        if (mounted) {
                          setState(() {
                            _realLogs.insert(0, {
                              'log_id': DateTime.now().millisecondsSinceEpoch,
                              'event_type': 'interaction',
                              'content': contentMsg,
                              'timestamp': DateTime.now().toIso8601String(),
                            });
                          });

                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('已成功將「$selectedCard」傳送至 $elderName 的裝置！❤️', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold)),
                              backgroundColor: const Color(0xFF10B981),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      label: Text(
                        '確定傳送關懷卡片',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Map<String, String> _cleanAiLogText(String rawText) {
    if (!rawText.contains('長者詢問：') && !rawText.contains('AI 回應：')) {
      return {'user': '', 'ai': rawText};
    }
    String userPart = '';
    String aiPart = rawText;

    if (rawText.contains('| AI 回應：')) {
      final parts = rawText.split('| AI 回應：');
      userPart = parts[0].replaceAll('長者詢問：', '').trim();
      aiPart = parts.length > 1 ? parts[1].trim() : '';
    } else if (rawText.contains('AI 回應：')) {
      final parts = rawText.split('AI 回應：');
      userPart = parts[0].replaceAll('長者詢問：', '').trim();
      aiPart = parts.length > 1 ? parts[1].trim() : '';
    } else {
      userPart = rawText.replaceAll('長者詢問：', '').trim();
    }
    return {'user': userPart, 'ai': aiPart};
  }

  final Set<String> _likedCategories = {};
  String? _selectedTopicKeyword;

  Map<String, dynamic>? _moodInsightData;
  List<dynamic> _realLogs = [];
  // ★ 2026-08-17 第二十五輪（需求 7）：持久化的緊急警報記錄（emergency_alerts 表，
  //   由 GET /api/alerts/{elder_id} 取得）。根因是「最新警示」原本只讀 _realLogs
  //   （來自 activity_log 表），但跌倒警報是 yolo_alert_dispatcher 寫進另一張
  //   emergency_alerts 表，兩張表沒有交集，導致歷史跌倒永遠不會出現在首頁。
  List<dynamic> _emergencyAlerts = [];
  int _selectedDateFilterIndex = 0; // 0: 今天, 1: 昨天, 2: 歷史月曆
  DateTime? _selectedHistoricalDate;

  @override
  void initState() {
    super.initState();
    _loadDynamicData();
  }


  void _showFullDialogueDialog(BuildContext context, String query, String ai, String timeStr) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.auto_stories_rounded, color: Color(0xFFF59E0B)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '🗣️ AI 語音陪伴對話紀錄 ($timeStr)',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansTc(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('👴 長輩提問：', style: GoogleFonts.notoSansTc(color: const Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
              ),
              child: Text(query, style: GoogleFonts.notoSansTc(color: Colors.white, height: 1.4)),
            ),
            const SizedBox(height: 14),
            Text('🤖 AI 小嘎回報與陪伴：', style: GoogleFonts.notoSansTc(color: const Color(0xFFFCD34D), fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
              ),
              child: Text(ai, style: GoogleFonts.notoSansTc(color: const Color(0xFFFEF3C7), height: 1.4)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('關閉', style: GoogleFonts.notoSansTc(color: const Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showCategoryDetailModal(
    BuildContext context, {
    required String categoryTitle,
    required IconData categoryIcon,
    required Color categoryColor,
    required List<Map<String, dynamic>> items,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(color: Colors.black87, blurRadius: 30, spreadRadius: 5),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 14),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: categoryColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: categoryColor, width: 1.5),
                      ),
                      child: Icon(categoryIcon, color: categoryColor, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            categoryTitle,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '包含 ${items.length} 筆相關新聞閱覽與 AI 陪伴對話',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 12,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white60),
                      onPressed: () => Navigator.pop(c),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 24),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          '尚無該主題分類的新紀錄',
                          style: GoogleFonts.notoSansTc(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        itemCount: items.length,
                        itemBuilder: (context, idx) {
                          final item = items[idx];
                          final isChat = item['isChat'] == true;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: (item['color'] as Color).withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: (item['color'] as Color).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        item['badge'] as String,
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          color: item['color'] as Color,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item['title'] as String,
                                        style: GoogleFonts.notoSansTc(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${item['date']} ${item['time']}',
                                      style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  item['desc'] as String,
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: 13.5,
                                    height: 1.45,
                                    color: const Color(0xFFCBD5E1),
                                  ),
                                ),
                                if (isChat) ...[
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                      foregroundColor: const Color(0xFFFCD34D),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: const BorderSide(color: Color(0xFFF59E0B)),
                                      ),
                                    ),
                                    onPressed: () {
                                      _showFullDialogueDialog(
                                        context,
                                        item['fullQuery'] as String? ?? '',
                                        item['fullAi'] as String? ?? '',
                                        item['time'] as String? ?? '',
                                      );
                                    },
                                    icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                                    label: Text(
                                      '📖 展開檢視長輩與 AI 完整對話逐字稿',
                                      style: GoogleFonts.notoSansTc(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void didUpdateWidget(FamilyHomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentElder?.id != oldWidget.currentElder?.id) {
      _loadDynamicData();
    }
  }

  Future<void> _loadDynamicData() async {
    if (widget.currentElder == null) return;
    final elderIdStr = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();

    try {
      final insight = await ApiService.getElderMoodInsight(elderIdStr);
      final logs = await ApiService.getElderActivityLogs(elderIdStr, limit: 30);
      // ★ 2026-08-17 第二十五輪（需求 7）：一併把持久化的跌倒警報（emergency_alerts 表）
      //   補進來，讓「最新警示」不再只看得到 activity_log。後端 GET /api/alerts/{elder_id}
      //   要求必填 user_id 做關係驗證，這裡沿用 family_interaction_tab.dart 已用過的
      //   SharedPreferences 'caregiver_id' 取得目前登入家屬本人的 user_id；
      //   讀不到就略過此次抓取（保持與既有 try/catch 一致：絕不讓失敗擲出例外）。
      final prefs = await SharedPreferences.getInstance();
      final familyUserId = prefs.getInt('caregiver_id');
      final emergencyAlerts = familyUserId != null
          ? await ApiService.getEmergencyAlerts(elderIdStr, userId: familyUserId, limit: 30)
          : <dynamic>[];
      if (mounted) {
        setState(() {
          _moodInsightData = insight;
          _realLogs = logs;
          _emergencyAlerts = emergencyAlerts;
        });
      }
    } catch (e) {
      // Ignore exception gracefully
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: const Color(0xFF38BDF8),
      backgroundColor: const Color(0xFF1E293B),
      onRefresh: _loadDynamicData,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 1. 長輩頂部極光卡片與在線狀態
                _buildElderHeaderCard(context),
                const SizedBox(height: 16),

                // 1.5 📍 IPS prototype：長輩目前所在區域
                _buildZoneCard(context),
                const SizedBox(height: 16),

                // 2. 🤖 亮點一：AI 長輩情緒氣象台 & 破冰金句卡片
                _buildAiMoodRadarCard(context),
                const SizedBox(height: 16),

                // 3. 📸 亮點二：長輩生活動態時光牆 (Elder Life Feed)
                _buildElderLifeFeedSection(context),
                const SizedBox(height: 16),

                // 4. 警示預覽
                _buildAlertPreview(context),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 1. 長輩頂部極光卡片與在線狀態 ───

  Widget _buildElderHeaderCard(BuildContext context) {
    final online = widget.isElderOnline;
    final name = widget.currentElder?.displayName ?? '長輩';
    final location = widget.currentElder?.location ?? '台北市';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // 大頭照與在線 Pulse
              Stack(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 2),
                      image: const DecorationImage(
                        image: AssetImage('assets/images/user_avatar.png'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: _PulseDot(color: online ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: online ? const Color(0xFF10B981).withValues(alpha: 0.25) : Colors.white12,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: online ? const Color(0xFF34D399) : Colors.white24,
                            ),
                          ),
                          child: Text(
                            online ? '在線通話機' : '離線',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: online ? const Color(0xFF6EE7B7) : const Color(0xFFCBD5E1),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 14, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 4),
                        Builder(builder: (context) {
                          int totalSteps = 0;
                          for (final item in _realLogs) {
                            final text = item['content']?.toString() ?? '';
                            final m = RegExp(r'(\d{1,3}(?:,\d{3})*|\d+)\s*步').firstMatch(text);
                            if (m != null) {
                              final parsed = int.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0;
                              if (parsed > totalSteps) totalSteps = parsed;
                            }
                          }
                          final stepDisplay = totalSteps > 0 ? totalSteps : (widget.currentElder?.id != null ? 3850 : 0);
                          final locDisplay = (location.isNotEmpty && location != '未知') ? location : '台北市大安區';

                          return Text(
                            '$locDisplay • 今日累積 $stepDisplay 步',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 13,
                              color: const Color(0xFFCBD5E1),
                            ),
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05);
  }

  // ─── 1.5 📍 IPS prototype：長輩目前所在區域 ───
  //
  // 資料完全由父層 FamilyMainScreen 提供（monitorDevices / elderZone），本分頁
  // 只負責顯示與「開啟校準畫面」的導航，不在此呼叫任何 API。
  // 四種狀態（皆為平靜文案，不出現原始錯誤訊息、不留永遠轉圈的 loading）：
  //   1. monitorDevices 為空 → 尚未綁定監視機
  //   2. elderZone == null 或 elderZone.calibrated != true → 尚未設定區域範圍
  //      （`calibrated` 是後端 `GET /api/ips/current/{elder_id}` 的權威欄位，
  //      代表該監視機是否已有非空 zone 多邊形設定；elderZone == null 只代表
  //      「還沒拿到任何回應」，用同一張提示卡呈現、不另外做 loading 狀態）
  //   3. calibrated == true 且 elderZone.zone == 'unknown' → 目前不在已設定的區域內
  //   4. 其餘 → 正常顯示區域名稱與停留時間

  Widget _buildZoneCard(BuildContext context) {
    final Elder? elder = widget.currentElder;
    final List<dynamic> monitors = widget.monitorDevices;
    final dynamic firstMonitor = monitors.isNotEmpty ? monitors.first : null;
    final int? deviceId = firstMonitor is Map
        ? int.tryParse((firstMonitor['deviceId'] ?? firstMonitor['id'])?.toString() ?? '')
        : null;
    final String deviceName =
        firstMonitor is Map ? (firstMonitor['deviceName']?.toString() ?? '監視機') : '監視機';

    Widget header() {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Text(
            '長輩所在位置',
            style: GoogleFonts.notoSansTc(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ],
      );
    }

    Widget shell(Widget child) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.35), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05);
    }

    // 狀態 1：尚未綁定監視機——不呼叫任何 API，純粹依清單是否為空判斷。
    if (monitors.isEmpty || deviceId == null) {
      return shell(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(),
            const SizedBox(height: 14),
            Text(
              '尚未綁定監視機',
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                color: const Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '綁定監視機後即可查看長輩目前所在的區域',
              style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF64748B)),
            ),
          ],
        ),
      );
    }

    final Map<String, dynamic>? zone = widget.elderZone;
    // ★ 權威欄位：後端直接告訴我們「這台監視機是否已有非空 zone 多邊形設定」，
    //   不要再用 `zone == 'unknown'` 或 `last_seen == null` 反推（兩者都無法
    //   區分「尚未校準」與「已校準但目前沒偵測到人」）。elderZone 為 null
    //   （尚未拿到任何回應）比照未校準處理，同一張提示卡。
    final bool calibrated = zone != null && zone['calibrated'] == true;

    // 狀態 2：裝置已綁定，但尚未校準區域範圍 → 引導前往校準。
    if (!calibrated) {
      final int? uid = widget.userId;
      return shell(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(),
            const SizedBox(height: 14),
            Text(
              '尚未設定區域範圍',
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                color: const Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '請先為「$deviceName」畫出客廳、房間等區域範圍，才能顯示長輩目前所在位置',
              style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: (elder == null || uid == null)
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ZoneCalibrationScreen(
                            elderId: elder.elderId ?? elder.id.toString(),
                            deviceId: deviceId,
                            deviceName: deviceName,
                            userId: uid,
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.draw_rounded, size: 18),
              label: const Text('前往設定區域'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8).withValues(alpha: 0.16),
                foregroundColor: const Color(0xFF38BDF8),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    // 走到這裡代表 calibrated == true；Dart 的流程分析已經從上面
    // `zone != null && zone['calibrated'] == true` 的判斷式把 zone 提升為
    // 非空型別，這裡不需要（也不能再加，會被判定為多餘）`!`。
    final Map<String, dynamic> zoneData = zone;
    final String zoneName = (zoneData['zone'] ?? 'unknown').toString();
    final DateTime? enteredAt = zoneData['enteredAt'] as DateTime?;
    final DateTime? updatedAt = zoneData['updatedAt'] as DateTime?;

    // 狀態 3：目前不在任何已設定的區域內（人不在鏡頭範圍，或站在未畫定的區域）。
    if (zoneName == 'unknown') {
      return shell(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(),
            const SizedBox(height: 14),
            Text(
              '目前不在已設定的區域內',
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                color: const Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '（可能不在鏡頭範圍內，或站在尚未畫定的區域）',
              style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF64748B)),
            ),
            if (updatedAt != null) ...[
              const SizedBox(height: 10),
              _buildZoneUpdatedHint(updatedAt),
            ],
          ],
        ),
      );
    }

    // 狀態 4：正常顯示。
    return shell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header(),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF34D399)),
                ),
                child: Text(
                  zoneName,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF6EE7B7),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '已停留 ${_formatZoneDwell(enteredAt)}',
                  style: GoogleFonts.notoSansTc(fontSize: 13, color: const Color(0xFFCBD5E1)),
                ),
              ),
            ],
          ),
          if (updatedAt != null) ...[
            const SizedBox(height: 10),
            _buildZoneUpdatedHint(updatedAt),
          ],
        ],
      ),
    );
  }

  Widget _buildZoneUpdatedHint(DateTime updatedAt) {
    final Duration diff = DateTime.now().difference(updatedAt);
    final String text;
    if (diff.inMinutes < 1) {
      text = '最後更新：剛剛';
    } else if (diff.inMinutes < 60) {
      text = '最後更新：${diff.inMinutes} 分鐘前';
    } else if (diff.inHours < 24) {
      text = '最後更新：${diff.inHours} 小時前';
    } else {
      text = '最後更新：${diff.inDays} 天前';
    }
    return Text(
      text,
      style: GoogleFonts.notoSansTc(fontSize: 11, color: const Color(0xFF64748B)),
    );
  }

  /// 把停留秒數格式化成「剛剛 / N 分鐘 / N 小時 N 分」。
  String _formatZoneDwell(DateTime? enteredAt) {
    if (enteredAt == null) return '剛剛';
    final int seconds = DateTime.now().difference(enteredAt).inSeconds;
    if (seconds < 90) return '剛剛';
    final int minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes 分鐘';
    final int hours = minutes ~/ 60;
    final int remMinutes = minutes % 60;
    if (remMinutes == 0) return '$hours 小時';
    return '$hours 小時 $remMinutes 分';
  }

  // ─── 2. 🤖 AI 長輩情緒氣象台 & 破冰話題 (方案 B：第一人稱問候 + 快捷動作) ───

  Widget _buildAiMoodRadarCard(BuildContext context) {
    final name = widget.currentElder?.displayName ?? '長輩';
    final moodTitle = _moodInsightData?['mood_title'] ?? '溫馨平穩';
    final moodScore = _moodInsightData?['mood_score'] ?? 88;
    final moodIcon = _moodInsightData?['mood_icon'] ?? '🍵';

    final String summaryText;
    final String icebreakerTopic;

    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final todayLogs = _realLogs.where((log) => (log['timestamp']?.toString() ?? '').startsWith(todayStr)).toList();

    if (_moodInsightData != null && _moodInsightData!['summary'] != null && _moodInsightData!['summary'].toString().isNotEmpty) {
      summaryText = _moodInsightData!['summary'].toString();
      icebreakerTopic = _moodInsightData!['icebreaker_topic']?.toString() ?? '$name！今天過得好嗎？撥個電話聽聽長輩的聲音關心一下吧！';
    } else if (todayLogs.isNotEmpty) {
      final hasWalk = todayLogs.any((l) => (l['content']?.toString() ?? '').contains('散步') || (l['content']?.toString() ?? '').contains('步數'));
      final hasMed = todayLogs.any((l) => (l['content']?.toString() ?? '').contains('藥'));
      final hasNews = todayLogs.any((l) => (l['content']?.toString() ?? '').contains('新聞'));

      List<String> acts = [];
      if (hasMed) acts.add('按時完成了晨間用藥打卡');
      if (hasWalk) acts.add('完成了公園散步運動');
      if (hasNews) acts.add('點閱收聽了熱門新聞');

      final actStr = acts.isNotEmpty ? acts.join('，且') : '作息非常規律';
      summaryText = '$name 今天情緒非常穩定愉快，$actStr！';
      icebreakerTopic = hasNews
          ? '$name！我今天看到熱門賽事新聞，感覺超精彩的！您最近也有在關注戰況嗎？'
          : '$name！聽說您今天有出門散步，公園空氣感覺怎麼樣呢？';
    } else {
      final lastLogDate = _realLogs.isNotEmpty ? (_realLogs.first['timestamp']?.toString() ?? '').substring(0, 10) : '';
      if (lastLogDate.length >= 10) {
        final m = lastLogDate.substring(5, 7);
        final d = lastLogDate.substring(8, 10);
        summaryText = '$name 今天尚未產生新的動態紀錄。最近一次紀錄於 $m/$d，作息狀況平穩！';
      } else {
        summaryText = '$name 今日尚無活動紀錄，撥個電話問候關心一下長輩吧！';
      }
      icebreakerTopic = '$name！今天過得好嗎？已有段時間沒聽到您的聲音，撥個電話問候關心您！';
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E293B),
            Color(0xFF0F2942),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 頂部標題與極光情緒氣象發光球
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // ★ 2026-08-10 第二十輪（需求 2）：spaceBetween 的左側 Row 未包
              //   Expanded，右側情緒徽章的 $moodTitle 由 AI 產生、長度不可控，
              //   兩邊相加超過寬度就整條往右溢位。
              Expanded(
                child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI 情緒氣象台',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          '即時情緒趨勢分析',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 12,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                ),
              ),
              const SizedBox(width: 8),
              // 極光發光情緒指標 Badge
              // ★ 2026-08-10 第二十輪（需求 2）：mood_title 由 AI 產生，長度不可控。
              //   Row 會先用「無限寬」量非 flex 子元素，量出來多寬就佔多寬，
              //   左側 Expanded 只能拿剩下的（可能為 0）→ 溢位。故在此硬性設上限。
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.4),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$moodIcon ', style: const TextStyle(fontSize: 13)),
                      Flexible(
                        child: Text(
                          '$moodTitle ($moodScore%)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 情緒分析描述
          Text(
            summaryText,
            style: GoogleFonts.notoSansTc(
              fontSize: 15,
              height: 1.6,
              fontWeight: FontWeight.w500,
              color: const Color(0xFFE2E8F0),
            ),
          ),

          const SizedBox(height: 18),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.12)),
          const SizedBox(height: 16),

          // 💡 破冰話題建議標題
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFFF59E0B), size: 20),
              const SizedBox(width: 8),
              Text(
                '今日推薦關懷破冰話題：',
                style: GoogleFonts.notoSansTc(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFFCD34D),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 奢華亮金發光金句卡（第一人稱溫情問候）
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF261C05),
                  Color(0xFF1F1703),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.6), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '“',
                  style: TextStyle(
                    fontSize: 32,
                    height: 0.8,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFFDE68A),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    icebreakerTopic,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFFEF3C7),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 方案 B：直接動作按鈕 (Action Buttons)
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                        backgroundColor: const Color(0xFF1E293B),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        title: Text(
                          '📞 撥打關懷電話給$name',
                          style: GoogleFonts.notoSansTc(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '💡 推薦聊天開場白：',
                              style: GoogleFonts.notoSansTc(color: const Color(0xFFFCD34D), fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                icebreakerTopic,
                                style: GoogleFonts.notoSansTc(color: const Color(0xFFFEF3C7), height: 1.4),
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: Text('取消', style: GoogleFonts.notoSansTc(color: const Color(0xFF94A3B8))),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                            onPressed: () {
                              Navigator.pop(c);
                              // ★ 2026-08-10 第十九輪（需求 4）：原本只彈 SnackBar、
                              //   什麼都不做。改為交給父層注入的撥號路徑；
                              //   父層沒給（不該發生）才退回原本的提示，不要靜默。
                              final startCall = widget.onStartVideoCall;
                              if (startCall != null) {
                                startCall();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('目前無法發起通話，請稍後再試', style: GoogleFonts.notoSansTc()),
                                    backgroundColor: const Color(0xFFEF4444),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.phone_rounded, color: Colors.white, size: 18),
                            label: Text('開始撥號', style: GoogleFonts.notoSansTc(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.phone_in_talk_rounded, size: 18, color: Colors.white),
                  label: Text(
                    '撥打電話聊聊',
                    style: GoogleFonts.notoSansTc(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showSendCareCardModal(context, name),
                  icon: const Icon(Icons.mark_email_unread_rounded, size: 18, color: Color(0xFF78350F)),
                  label: Text(
                    '傳送關懷卡',
                    style: GoogleFonts.notoSansTc(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF78350F),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFDE68A),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.05);
  }

  // ─── 3. 📸 長輩生活動態時光牆 (動態擴充與折疊/展開機制 + 日期篩選) ───

  Widget _buildElderLifeFeedSection(BuildContext context) {
    final name = widget.currentElder?.displayName ?? '長輩';
    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr = "${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}";

    List<Map<String, dynamic>> rawFeedItems = [];

    if (_realLogs.isNotEmpty) {
      rawFeedItems = _realLogs.map((log) {
        final contentStr = log['content']?.toString() ?? '';
        final eventType = log['event_type']?.toString() ?? '';
        final tsStr = log['timestamp']?.toString() ?? '';

        String dateStr = todayStr;
        String timeStr = '12:00';
        if (tsStr.length >= 16) {
          dateStr = tsStr.substring(0, 10);
          final clockStr = tsStr.substring(11, 16);
          if (dateStr == todayStr) {
            timeStr = clockStr;
          } else if (dateStr == yesterdayStr) {
            timeStr = '昨天 $clockStr';
          } else {
            final m = dateStr.substring(5, 7);
            final d = dateStr.substring(8, 10);
            timeStr = '$m/$d $clockStr';
          }
        }

        String badge = 'LOG';
        Color col = const Color(0xFF38BDF8);
        Color glowCol = const Color(0xFF0284C7);
        IconData ic = Icons.auto_awesome_rounded;

        if (eventType == 'news_view' || eventType == 'news_query' || contentStr.contains('新聞') || contentStr.contains('NBA')) {
          badge = 'NEWS';
          col = const Color(0xFF38BDF8);
          glowCol = const Color(0xFF0284C7);
          ic = Icons.sports_basketball_rounded;
        } else if (eventType == 'youtube_query' || contentStr.contains('YouTube') || contentStr.contains('音樂') || contentStr.contains('影片') || contentStr.contains('歌曲')) {
          badge = 'MEDIA';
          col = const Color(0xFFF43F5E);
          glowCol = const Color(0xFFBE123C);
          ic = Icons.play_circle_fill_rounded;
        } else if (contentStr.contains('散步') || contentStr.contains('步數') || contentStr.contains('運動') || eventType == 'activity') {
          badge = 'WALK';
          col = const Color(0xFF34D399);
          glowCol = const Color(0xFF059669);
          ic = Icons.directions_run_rounded;
        } else if (contentStr.contains('藥') || contentStr.contains('打卡') || eventType == 'medication') {
          badge = 'MEDICINE';
          col = const Color(0xFFA78BFA);
          glowCol = const Color(0xFF7C3AED);
          ic = Icons.medication_rounded;
        } else if (contentStr.contains('對話') || contentStr.contains('聊天') || contentStr.contains('小嘎') || contentStr.contains('寂寞') || eventType == 'mood' || eventType == 'chat') {
          badge = 'AI CHAT';
          col = const Color(0xFFF59E0B);
          glowCol = const Color(0xFFD97706);
          ic = Icons.favorite_rounded;
        }

        return {
          'id': log['log_id'] ?? log.hashCode,
          'rawTimestamp': tsStr,
          'time': timeStr,
          'date': dateStr,
          'badge': badge,
          'title': contentStr.length > 15 ? '${contentStr.substring(0, 15)}...' : contentStr,
          'desc': contentStr,
          'fullQuery': '與 AI 長輩陪伴語音互動',
          'fullAi': contentStr,
          'isChat': badge == 'AI CHAT',
          'icon': ic,
          'color': col,
          'glow': glowCol,
        };
      }).toList();
    }

    // Filter by topic keyword if selected
    List<Map<String, dynamic>> itemsPool = rawFeedItems;
    if (_selectedTopicKeyword != null) {
      final kw = _selectedTopicKeyword!.trim().toLowerCase();
      itemsPool = rawFeedItems.where((i) {
        final b = i['badge']?.toString().toLowerCase() ?? '';
        final t = i['title']?.toString() ?? '';
        final d = i['desc']?.toString() ?? '';
        final fullText = '$b $t $d';

        if (fullText.contains(kw)) return true;

        // 語意相容與分類標籤匹配 (Semantic synonym matching so clicking tags NEVER loses items)
        if ((kw == '影音' || kw == '音樂' || kw.contains('音樂')) &&
            (fullText.contains('音樂') || fullText.contains('影音') || fullText.contains('歌曲') || fullText.contains('youtube') || b == 'media')) {
          return true;
        }
        if ((kw == '散步' || kw == '運動' || kw == '健走') &&
            (fullText.contains('散步') || fullText.contains('運動') || fullText.contains('步數') || b == 'walk')) {
          return true;
        }
        if ((kw == '新聞' || kw == '體育') &&
            (fullText.contains('新聞') || fullText.contains('體育') || fullText.contains('nba') || b == 'news')) {
          return true;
        }
        if ((kw == '對話' || kw == '故事' || kw == '聊天') &&
            (fullText.contains('對話') || fullText.contains('故事') || fullText.contains('聊天') || fullText.contains('小嘎') || b == 'ai chat')) {
          return true;
        }
        if ((kw == '藥' || kw == '血壓' || kw == '打卡') &&
            (fullText.contains('藥') || fullText.contains('血壓') || fullText.contains('打卡') || b == 'medicine')) {
          return true;
        }

        return false;
      }).toList();
    }

    final todayItems = itemsPool.where((i) => i['date'] == todayStr).toList();
    final yesterdayItems = itemsPool.where((i) => i['date'] == yesterdayStr).toList();

    List<Map<String, dynamic>> activeFilteredItems;
    if (_selectedDateFilterIndex == 0) {
      activeFilteredItems = itemsPool;
    } else if (_selectedDateFilterIndex == 1) {
      activeFilteredItems = todayItems;
    } else if (_selectedDateFilterIndex == 2) {
      activeFilteredItems = yesterdayItems;
    } else {
      if (_selectedHistoricalDate != null) {
        final targetStr = "${_selectedHistoricalDate!.year}-${_selectedHistoricalDate!.month.toString().padLeft(2, '0')}-${_selectedHistoricalDate!.day.toString().padLeft(2, '0')}";
        activeFilteredItems = itemsPool.where((i) => i['date'] == targetStr).toList();
      } else {
        activeFilteredItems = itemsPool;
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E293B),
            Color(0xFF0F172A),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題與即時連線標籤
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF38BDF8), Color(0xFF818CF8)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$name 動態時光牆',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '目前共 ${activeFilteredItems.length} 筆生活足跡',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 12,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    const _PulseDot(color: Color(0xFF38BDF8)),
                    const SizedBox(width: 6),
                    Text(
                      '即時同步',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF38BDF8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 🏷️ 特色功能 1：長輩熱情話題關鍵字雲 (Topic Pulse Cloud)
          _buildTopicPulseCloud(activeFilteredItems),

          const SizedBox(height: 12),

          // 日期篩選標籤
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDateChip(
                  '🌐 全部足跡 (${itemsPool.length})',
                  isSelected: _selectedDateFilterIndex == 0,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedDateFilterIndex = 0);
                  },
                ),
                const SizedBox(width: 8),
                _buildDateChip(
                  '📅 今天 (${todayItems.length})',
                  isSelected: _selectedDateFilterIndex == 1,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedDateFilterIndex = 1);
                  },
                ),
                const SizedBox(width: 8),
                _buildDateChip(
                  '昨天 (${yesterdayItems.length})',
                  isSelected: _selectedDateFilterIndex == 2,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedDateFilterIndex = 2);
                  },
                ),
                const SizedBox(width: 8),
                _buildDateChip(
                  _selectedHistoricalDate != null
                      ? '🗓️ ${_selectedHistoricalDate!.month}/${_selectedHistoricalDate!.day}'
                      : '歷史月曆 🗓️',
                  isSelected: _selectedDateFilterIndex == 3,
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedHistoricalDate ?? DateTime.now(),
                      firstDate: DateTime(2023),
                      lastDate: DateTime.now(),
                      builder: (context, child) {
                        return Theme(
                          data: ThemeData.dark().copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Color(0xFF38BDF8),
                              onPrimary: Colors.white,
                              surface: Color(0xFF1E293B),
                              onSurface: Colors.white,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedHistoricalDate = picked;
                        _selectedDateFilterIndex = 3;
                      });
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ─── 時間軸發光節點 + AI 主題卡片合二為一 ───
          if (activeFilteredItems.isEmpty) ...[
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  const Icon(Icons.event_note_rounded, color: Colors.white38, size: 44),
                  const SizedBox(height: 8),
                  Text(
                    '該搜尋條目尚無活動紀錄 🗓️',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      color: Colors.white60,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '點擊上方「🌐 全部足跡」觀看長輩完整歷史動態',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 12,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ] else ...[
            ..._buildUnifiedTimelineCategoryCards(context, activeFilteredItems),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }

  List<Map<String, dynamic>> _extractDynamicTopicTags(
    List<Map<String, dynamic>> rawFeedItems,
    dynamic moodInsightData,
    String elderInterests,
  ) {
    List<Map<String, dynamic>> tags = [];
    final Set<String> seenKeywords = {};

    void addTag(String tagLabel, String keyword, Color color) {
      final cleanKw = keyword.trim();
      if (cleanKw.isNotEmpty && !seenKeywords.contains(cleanKw)) {
        seenKeywords.add(cleanKw);
        tags.add({
          'tag': tagLabel,
          'keyword': cleanKw,
          'color': color,
        });
      }
    }

    // 1. 即時動態萃取：從長輩實際產生的日誌活動（rawFeedItems）中提煉真實關鍵字標籤
    if (rawFeedItems.isNotEmpty) {
      for (final item in rawFeedItems) {
        final desc = item['desc']?.toString() ?? '';
        final title = item['title']?.toString() ?? '';
        final badge = item['badge']?.toString() ?? '';
        final fullText = '$title $desc';

        // A0. 財經與台股投資
        if (fullText.contains('財經') || fullText.contains('台股') || fullText.contains('股票') || fullText.contains('股市') || fullText.contains('投資') || fullText.contains('理財')) {
          if (fullText.contains('台股')) {
            addTag('📈 #台股焦點', '台股', const Color(0xFF10B981));
          } else if (fullText.contains('股票') || fullText.contains('股市')) {
            addTag('📈 #股市觀點', '股市', const Color(0xFF10B981));
          } else {
            addTag('📈 #財經趨勢', '財經', const Color(0xFF10B981));
          }
        }

        // A0. 美食佳餚與料理食譜
        else if (fullText.contains('食譜') || fullText.contains('烹飪') || fullText.contains('做菜') || fullText.contains('美食') || fullText.contains('火鍋') || fullText.contains('料理')) {
          if (fullText.contains('火鍋')) {
            addTag('🍳 #火鍋佳餚', '火鍋', const Color(0xFFFB923C));
          } else if (fullText.contains('食譜') || fullText.contains('做菜')) {
            addTag('🍳 #烹飪食譜', '食譜', const Color(0xFFFB923C));
          } else {
            addTag('🍳 #美食料理', '美食', const Color(0xFFFB923C));
          }
        }

        // A. 影音點播 (YouTube / 歌名 / 歌手)
        else if (badge == 'MEDIA' || fullText.contains('YouTube') || fullText.contains('音樂') || fullText.contains('歌曲')) {
          final match = RegExp(r'(?:YouTube 音樂/影片|歌曲|音樂)[：:\s]*([^\s|｜]+)').firstMatch(fullText);
          if (match != null) {
            final kw = match.group(1)!.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]'), '');
            if (kw.length >= 2) {
              addTag('🎵 #$kw', kw, const Color(0xFFF43F5E));
              continue;
            }
          }
          addTag('🎵 #經典音樂', '音樂', const Color(0xFFF43F5E));
        }

        // B. 健康運動與作息
        else if (badge == 'WALK' || fullText.contains('運動') || fullText.contains('散步') || fullText.contains('步數')) {
          if (fullText.contains('散步')) {
            addTag('🌿 #戶外散步', '散步', const Color(0xFF34D399));
          } else if (fullText.contains('運動')) {
            addTag('🏃 #日常運動', '運動', const Color(0xFF34D399));
          } else if (fullText.contains('步數')) {
            addTag('👟 #健走步數', '步數', const Color(0xFF34D399));
          } else {
            addTag('🏃 #健康作息', '健康', const Color(0xFF34D399));
          }
        }

        // C. 熱門新聞點閱與關注
        else if (badge == 'NEWS' || fullText.contains('新聞')) {
          final match = RegExp(r'【([^】]+)】').firstMatch(fullText);
          if (match != null) {
            final cat = match.group(1)!;
            if (cat != 'all' && cat.isNotEmpty) {
              addTag('📰 #$cat新聞', cat, const Color(0xFF38BDF8));
              continue;
            }
          }
          if (fullText.contains('NBA') || fullText.contains('體育')) {
            addTag('🏀 #體育賽事新聞', '體育', const Color(0xFF38BDF8));
          } else {
            addTag('📰 #熱門新聞關注', '新聞', const Color(0xFF38BDF8));
          }
        }

        // D. 用藥提醒與健康打卡
        else if (badge == 'MEDICINE' || fullText.contains('藥') || fullText.contains('打卡')) {
          if (fullText.contains('血壓')) {
            addTag('💊 #血壓用藥', '血壓', const Color(0xFFA78BFA));
          } else if (fullText.contains('藥')) {
            addTag('💊 #按時服藥', '藥', const Color(0xFFA78BFA));
          } else {
            addTag('🌟 #晨間健康打卡', '打卡', const Color(0xFFA78BFA));
          }
        }

        // E. AI 陪伴與歷史回憶對話
        else if (badge == 'AI CHAT' || fullText.contains('對話') || fullText.contains('聊天') || fullText.contains('故事')) {
          if (fullText.contains('布莊') || fullText.contains('童年') || fullText.contains('往事')) {
            addTag('💬 #昔日記憶故事', '故事', const Color(0xFFF59E0B));
          } else if (fullText.contains('歌仔戲') || fullText.contains('戲曲')) {
            addTag('🎭 #歌仔戲曲', '歌仔戲', const Color(0xFFF59E0B));
          } else {
            addTag('💬 #AI親情對話', '對話', const Color(0xFFF59E0B));
          }
        }
      }
    }

    return tags;
  }

  Widget _buildTopicPulseCloud(List<Map<String, dynamic>> rawFeedItems) {
    if (rawFeedItems.isEmpty) return const SizedBox.shrink();
    final dynamicTopics = _extractDynamicTopicTags(rawFeedItems, _moodInsightData, '');

    if (dynamicTopics.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: dynamicTopics.map((t) {
          final isSelected = _selectedTopicKeyword == t['keyword'];
          final col = t['color'] as Color;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  if (_selectedTopicKeyword == t['keyword']) {
                    _selectedTopicKeyword = null;
                  } else {
                    _selectedTopicKeyword = t['keyword'] as String;
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected ? col.withValues(alpha: 0.3) : col.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? col : col.withValues(alpha: 0.3),
                    width: isSelected ? 1.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: col.withValues(alpha: 0.4),
                            blurRadius: 8,
                          ),
                        ]
                      : [],
                ),
                child: Text(
                  t['tag'] as String,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? Colors.white : col,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDateChip(String label, {required bool isSelected, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF38BDF8).withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF38BDF8) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansTc(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
            color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildUnifiedTimelineCategoryCards(BuildContext context, List<Map<String, dynamic>> activeFilteredItems) {
    final name = widget.currentElder?.displayName ?? '長輩';
    final apiClusters = _moodInsightData?['topic_clusters'] as List<dynamic>?;

    String makeDynamicTagline(List<Map<String, dynamic>> items, String fallback) {
      if (items.isEmpty) return fallback;
      final first = items.first;
      final t = first['title']?.toString() ?? '';
      final tm = first['time']?.toString() ?? '';
      return '最新紀錄：$t ($tm)';
    }

    String makeDynamicSummary(List<Map<String, dynamic>> items, String fallback) {
      if (items.isEmpty) return fallback;
      final descs = items.map((i) => i['desc']?.toString() ?? '').where((d) => d.isNotEmpty).toList();
      if (descs.isEmpty) return fallback;
      return descs.take(2).join('； ');
    }

    List<Map<String, dynamic>> categoriesToRender = [];

    if (apiClusters != null && apiClusters.isNotEmpty) {
      final Set<int> matchedItemIds = {};

      for (final cluster in apiClusters) {
        final title = cluster['title']?.toString() ?? '主題紀錄';
        final colorHexStr = cluster['color_hex']?.toString() ?? '0xFF38BDF8';
        final glowHexStr = cluster['glow_hex']?.toString() ?? '0xFF0284C7';
        final iconName = cluster['icon_name']?.toString() ?? '';
        final keywords = (cluster['match_keywords'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

        final colorHex = int.tryParse(colorHexStr) ?? 0xFF38BDF8;
        final glowHex = int.tryParse(glowHexStr) ?? 0xFF0284C7;

        IconData iconData = Icons.auto_awesome_rounded;
        if (iconName.contains('sports') || iconName.contains('basketball')) {
          iconData = Icons.sports_basketball_rounded;
        } else if (iconName.contains('run') || iconName.contains('directions')) {
          iconData = Icons.directions_run_rounded;
        } else if (iconName.contains('favorite') || iconName.contains('heart')) {
          iconData = Icons.favorite_rounded;
        } else if (iconName.contains('play') || iconName.contains('music')) {
          iconData = Icons.play_circle_fill_rounded;
        } else if (iconName.contains('trending') || iconName.contains('chart') || iconName.contains('finance')) {
          iconData = Icons.trending_up_rounded;
        } else if (iconName.contains('restaurant') || iconName.contains('food')) {
          iconData = Icons.restaurant_rounded;
        }

        final matchedItems = activeFilteredItems.where((item) {
          if (keywords.isEmpty) return true;
          final b = item['badge'].toString();
          final d = item['desc'].toString();
          final t = item['title'].toString();
          return keywords.any((k) => b.contains(k) || d.contains(k) || t.contains(k));
        }).toList();

        if (matchedItems.isNotEmpty) {
          for (final it in matchedItems) {
            final itemId = it['id'];
            if (itemId is int) {
              matchedItemIds.add(itemId);
            }
          }
          categoriesToRender.add({
            'title': title,
            'icon': iconData,
            'color': Color(colorHex),
            'glow': Color(glowHex),
            'tagline': makeDynamicTagline(matchedItems, '$title 相關動態'),
            'previewSummary': makeDynamicSummary(matchedItems, '$name今日關心 $title。'),
            'items': matchedItems,
          });
        }
      }

      // Catch any leftover items not matched by apiClusters so no items are ever lost
      final unmatchedItems = activeFilteredItems.where((item) {
        final id = item['id'];
        return id == null || (id is int && !matchedItemIds.contains(id));
      }).toList();

      if (unmatchedItems.isNotEmpty) {
        final mediaLeftovers = unmatchedItems.where((i) {
          final d = "${i['title']} ${i['desc']} ${i['badge']}";
          return d.contains('YouTube') || d.contains('影音') || d.contains('音樂') || d.contains('歌曲') || d.contains('歌') || d.contains('MEDIA');
        }).toList();

        if (mediaLeftovers.isNotEmpty) {
          categoriesToRender.add({
            'title': '🎵 音樂影音與娛樂點播',
            'icon': Icons.play_circle_fill_rounded,
            'color': const Color(0xFFF43F5E),
            'glow': const Color(0xFFBE123C),
            'tagline': makeDynamicTagline(mediaLeftovers, '影音娛樂：點播喜愛的經典歌曲與影音 🎶'),
            'previewSummary': makeDynamicSummary(mediaLeftovers, '$name點播收聽影音娛樂內容。'),
            'items': mediaLeftovers,
          });
        }

        final remaining = unmatchedItems.where((i) => !mediaLeftovers.contains(i)).toList();
        if (remaining.isNotEmpty) {
          categoriesToRender.add({
            'title': '🌟 每日生活足跡記錄',
            'icon': Icons.auto_awesome_rounded,
            'color': const Color(0xFF818CF8),
            'glow': const Color(0xFF4F46E5),
            'tagline': makeDynamicTagline(remaining, '生活狀態：保持健康互動 ✅'),
            'previewSummary': makeDynamicSummary(remaining, '$name今日生活足跡與活動紀錄。'),
            'items': remaining,
          });
        }
      }
    }

    if (categoriesToRender.isEmpty) {
      final financeItems = activeFilteredItems.where((i) {
        final d = "${i['title']} ${i['desc']} ${i['badge']}";
        return d.contains('財經') || d.contains('台股') || d.contains('股票') || d.contains('股市') || d.contains('投資') || d.contains('理財');
      }).toList();

      if (financeItems.isNotEmpty) {
        categoriesToRender.add({
          'title': '📈 財經觀點與台股投資',
          'icon': Icons.trending_up_rounded,
          'color': const Color(0xFF10B981),
          'glow': const Color(0xFF059669),
          'tagline': makeDynamicTagline(financeItems, '財經焦點：股市與財經資訊 📊'),
          'previewSummary': makeDynamicSummary(financeItems, '$name關心財經市場與台股動態。'),
          'items': financeItems,
        });
      }

      final foodItems = activeFilteredItems.where((i) {
        final d = "${i['title']} ${i['desc']} ${i['badge']}";
        return d.contains('食譜') || d.contains('烹飪') || d.contains('做菜') || d.contains('美食') || d.contains('火鍋') || d.contains('料理');
      }).toList();

      if (foodItems.isNotEmpty) {
        categoriesToRender.add({
          'title': '🍳 美食佳餚與餐飲食譜交流',
          'icon': Icons.restaurant_rounded,
          'color': const Color(0xFFFB923C),
          'glow': const Color(0xFFC2410C),
          'tagline': makeDynamicTagline(foodItems, '飲食點滴：美食與健康食譜 🥗'),
          'previewSummary': makeDynamicSummary(foodItems, '$name關注分享日常飲食料理。'),
          'items': foodItems,
        });
      }

      final sportsItems = activeFilteredItems.where((i) {
        final d = "${i['title']} ${i['desc']} ${i['badge']}";
        return d.contains('NBA') || d.contains('體育') || d.contains('新聞') || d.contains('賽事') || d.contains('詹姆斯');
      }).toList();

      if (sportsItems.isNotEmpty) {
        categoriesToRender.add({
          'title': '🏀 體育賽事與熱門新聞關注',
          'icon': Icons.sports_basketball_rounded,
          'color': const Color(0xFF38BDF8),
          'glow': const Color(0xFF0284C7),
          'tagline': makeDynamicTagline(sportsItems, '關注新聞：體育與球賽資訊 🏆'),
          'previewSummary': makeDynamicSummary(sportsItems, '$name收聽關注熱門新聞點閱紀錄。'),
          'items': sportsItems,
        });
      }

      final healthItems = activeFilteredItems.where((i) {
        final d = "${i['title']} ${i['desc']} ${i['badge']}";
        return d.contains('散步') || d.contains('步數') || d.contains('藥') || d.contains('打卡') || d.contains('作息') || d.contains('運動') || d.contains('活動') || d.contains('WALK');
      }).toList();

      if (healthItems.isNotEmpty) {
        categoriesToRender.add({
          'title': '🏃‍♂️ 健康運動與日常作息保養',
          'icon': Icons.directions_run_rounded,
          'color': const Color(0xFF34D399),
          'glow': const Color(0xFF059669),
          'tagline': makeDynamicTagline(healthItems, '作息狀態：健康打卡與運動 🏃‍♂️'),
          'previewSummary': makeDynamicSummary(healthItems, '$name按時完成晨間打卡與健康運動。'),
          'items': healthItems,
        });
      }

      final mediaItems = activeFilteredItems.where((i) {
        final d = "${i['title']} ${i['desc']} ${i['badge']}";
        return d.contains('YouTube') || d.contains('影音') || d.contains('音樂') || d.contains('歌曲') || d.contains('歌') || d.contains('MEDIA');
      }).toList();

      if (mediaItems.isNotEmpty) {
        categoriesToRender.add({
          'title': '🎵 音樂影音與娛樂點播',
          'icon': Icons.play_circle_fill_rounded,
          'color': const Color(0xFFF43F5E),
          'glow': const Color(0xFFBE123C),
          'tagline': makeDynamicTagline(mediaItems, '影音娛樂：點播喜愛的經典歌曲與影音 🎶'),
          'previewSummary': makeDynamicSummary(mediaItems, '$name點播收聽影音娛樂內容。'),
          'items': mediaItems,
        });
      }

      final chatItems = activeFilteredItems.where((i) {
        final d = "${i['title']} ${i['desc']} ${i['badge']}";
        return d.contains('對話') || d.contains('故事') || d.contains('女兒') || d.contains('關懷') || d.contains('聊天') || d.contains('說說話') || d.contains('AI CHAT');
      }).toList();

      if (chatItems.isNotEmpty) {
        categoriesToRender.add({
          'title': '💬 溫情陪伴與家族互動',
          'icon': Icons.favorite_rounded,
          'color': const Color(0xFFF59E0B),
          'glow': const Color(0xFFD97706),
          'tagline': makeDynamicTagline(chatItems, '家族互動：陪伴對話與語音卡片 💌'),
          'previewSummary': makeDynamicSummary(chatItems, '$name與 AI 進行語音陪伴對話交流。'),
          'items': chatItems,
        });
      }

      if (categoriesToRender.isEmpty) {
        categoriesToRender.add({
          'title': '🌟 每日生活足跡記錄',
          'icon': Icons.auto_awesome_rounded,
          'color': const Color(0xFF818CF8),
          'glow': const Color(0xFF4F46E5),
          'tagline': makeDynamicTagline(activeFilteredItems, '生活狀態：保持健康互動 ✅'),
          'previewSummary': makeDynamicSummary(activeFilteredItems, '$name今日穩定使用系統，作息規律與狀況平穩。'),
          'items': activeFilteredItems,
        });
      }
    }

    // 依據類別中最新一筆紀錄的時間戳記進行【由新到舊 (由上至下)】嚴格排序 (Top -> Bottom Descending)
    categoriesToRender.sort((a, b) {
      final itemsA = a['items'] as List<Map<String, dynamic>>?;
      final itemsB = b['items'] as List<Map<String, dynamic>>?;
      final tsA = (itemsA != null && itemsA.isNotEmpty) ? (itemsA.first['rawTimestamp'] ?? itemsA.first['time'] ?? '') : '';
      final tsB = (itemsB != null && itemsB.isNotEmpty) ? (itemsB.first['rawTimestamp'] ?? itemsB.first['time'] ?? '') : '';
      return tsB.toString().compareTo(tsA.toString());
    });

    final categoriesList = categoriesToRender.asMap().entries.toList();
    String lastRenderedTime = '';

    return categoriesList.map((entry) {
      final idx = entry.key;
      final cat = entry.value;
      final isLast = idx == categoriesList.length - 1;
      final items = cat['items'] as List<Map<String, dynamic>>;
      final latestTime = items.isNotEmpty ? (items.first['time'] as String? ?? '') : '';

      final bool showTimeLabel = latestTime.isNotEmpty && latestTime != lastRenderedTime;
      if (showTimeLabel) {
        lastRenderedTime = latestTime;
      }

      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: Column(
                children: [
                  if (showTimeLabel) ...[
                    Text(
                      latestTime,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: cat['color'] as Color,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ] else ...[
                    const SizedBox(height: 14),
                  ],
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0F172A),
                      border: Border.all(color: cat['color'] as Color, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: (cat['glow'] as Color).withValues(alpha: 0.4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Icon(cat['icon'] as IconData, color: cat['color'] as Color, size: 16),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              cat['color'] as Color,
                              Colors.white24,
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: _buildCategoryCard(
                  context,
                  categoryTitle: cat['title'] as String,
                  categoryIcon: cat['icon'] as IconData,
                  categoryColor: cat['color'] as Color,
                  glowColor: cat['glow'] as Color,
                  tagline: cat['tagline'] as String,
                  previewSummary: cat['previewSummary'] as String,
                  items: items,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildCategoryCard(
    BuildContext context, {
    required String categoryTitle,
    required IconData categoryIcon,
    required Color categoryColor,
    required Color glowColor,
    required String tagline,
    required String previewSummary,
    required List<Map<String, dynamic>> items,
  }) {
    final count = items.length;
    final name = widget.currentElder?.displayName ?? '長輩';

    // 判斷是否包含 AI 語音對話/故事
    final isChatCategory = categoryTitle.contains('陪伴') || categoryTitle.contains('對話') || items.any((i) => i['isChat'] == true);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: categoryColor.withValues(alpha: 0.28), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.12),
            blurRadius: 20,
            spreadRadius: 1,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題與數量標籤
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: categoryColor.withValues(alpha: 0.4)),
                ),
                child: Icon(categoryIcon, color: categoryColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      categoryTitle,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 11,
                        color: categoryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: categoryColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '$count 筆',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: categoryColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 💬 特色內容區塊：若為對話則渲染親情對話對白框，若為健康作息則渲染簡潔動態條目
          if (isChatCategory) ...[
            Builder(builder: (context) {
              final rawDesc = items.isNotEmpty ? items.first['desc'].toString() : previewSummary;
              final cleaned = _cleanAiLogText(rawDesc);
              final userTalk = cleaned['user'] ?? '';
              final aiTalk = cleaned['ai'] ?? '';

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (userTalk.isNotEmpty) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('💬 ', style: TextStyle(fontSize: 13)),
                          Expanded(
                            child: Text(
                              '$name：「$userTalk」',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFFDE68A),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('💌 ', style: TextStyle(fontSize: 13)),
                        Expanded(
                          child: Text(
                            '小嘎：「${aiTalk.length > 80 ? '${aiTalk.substring(0, 80)}...' : aiTalk}」',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 12,
                              height: 1.45,
                              color: const Color(0xFFE2E8F0),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: items.take(2).map((item) {
                  final titleStr = item['title']?.toString() ?? '';
                  final descStr = item['desc']?.toString() ?? '';
                  final cleanD = _cleanAiLogText(descStr)['ai'] ?? descStr;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(item['icon'] as IconData? ?? Icons.check_circle_rounded, color: categoryColor, size: 15),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$titleStr • $cleanD',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 12,
                              height: 1.4,
                              color: const Color(0xFFCBD5E1),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // ❤️ 雙向心意熱度互動按鈕與點讚標籤
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    _showCategoryDetailModal(
                      context,
                      categoryTitle: categoryTitle,
                      categoryIcon: categoryIcon,
                      categoryColor: categoryColor,
                      items: items,
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: categoryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: categoryColor.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_stories_rounded, color: categoryColor, size: 15),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '閱覽對話與新聞紀錄 ($count)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios_rounded, color: categoryColor, size: 10),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  setState(() {
                    if (_likedCategories.contains(categoryTitle)) {
                      _likedCategories.remove(categoryTitle);
                    } else {
                      _likedCategories.add(categoryTitle);
                    }
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.favorite_rounded, color: Color(0xFFEC4899), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '已傳送女兒的溫馨心意給 $name！❤️',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.notoSansTc(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: const Color(0xFF1E293B),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                  decoration: BoxDecoration(
                    color: _likedCategories.contains(categoryTitle)
                        ? const Color(0xFFEC4899).withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _likedCategories.contains(categoryTitle)
                          ? const Color(0xFFEC4899)
                          : Colors.white24,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _likedCategories.contains(categoryTitle) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: _likedCategories.contains(categoryTitle) ? const Color(0xFFEC4899) : Colors.white60,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _likedCategories.contains(categoryTitle) ? '已讚' : '給個心意',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _likedCategories.contains(categoryTitle) ? const Color(0xFFEC4899) : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

    // ─── 4. 警示預覽 ───
    // ★ 2026-08-17 第二十五輪（需求 7）：原本這裡有 `_mockAlerts`（硬編的假警示資料，
    //   例如「活動量偏低／今日步數僅800步」），三個真實來源都是空時就顯示給真實使用者看，
    //   等同對家屬謊報虛構的健康警訊。改為三個真實來源皆空時顯示明確的空狀態文案
    //   （見 `_buildAlertPreview` 尾端），故整個欄位已刪除且不再需要。

  Widget _buildAlertPreview(BuildContext context) {
    // ★ 整合即時跌倒／異常警報（activeAlerts）至首頁「最新警示」
    final List<Map<String, dynamic>> activeItems = [];
    final currentElderIdStr = widget.currentElder?.elderId ?? widget.currentElder?.id?.toString();
    for (final a in widget.activeAlerts) {
      final aElderId = (a['elder_id'] ?? a['elderId'])?.toString();
      if (currentElderIdStr != null && aElderId != null && aElderId != currentElderIdStr) {
        continue; // 隔離不同長輩的警報
      }
      final type = (a['alert_type'] ?? a['alertType'] ?? 'fall').toString();
      final conf = a['confidence'];
      final confText = conf != null ? ' (信心度 ${(conf * 100).toStringAsFixed(0)}%)' : '';
      String title = '🚨 跌倒緊急警報';
      String desc = '監視機偵測到長輩疑似跌倒$confText，請立即確認！';
      if (type == 'crawl') {
        title = '⚠️ 疑似爬行警報';
        desc = '監視機偵測到長輩異常爬行動作$confText，請多加留意。';
      } else if (type == 'lying_down') {
        title = '⚠️ 久躺未起警報';
        desc = '長輩在監視區域久躺不起$confText，建議關懷確認。';
      } else if (type == 'prolonged_inactivity') {
        title = '⚠️ 長時間無活動警報';
        desc = '長輩活動量異常偏低$confText，請留意長輩身體狀況。';
      }
      activeItems.add({
        'title': title,
        'desc': desc,
        'level': 'high',
        'icon': Icons.warning_amber_rounded,
      });
    }

    final alertItems = _realLogs.where((log) {
      final text = log['content']?.toString() ?? '';
      final etype = log['event_type']?.toString() ?? '';
      return etype == 'alert' || text.contains('警示') || text.contains('提醒') || text.contains('未確認');
    }).map((log) {
      final desc = log['content']?.toString() ?? '';
      final title = desc.split('|').first.replaceAll(RegExp(r'【.*?】'), '').trim();
      final level = desc.contains('用藥') || desc.contains('未確認') ? 'high' : 'medium';
      final icon = desc.contains('用藥') ? Icons.medication_rounded : Icons.directions_walk_rounded;
      return {'title': title.isNotEmpty ? title : '健康警示', 'desc': desc, 'level': level, 'icon': icon};
    }).toList();

    // ★ 2026-08-17 第二十五輪（需求 7）：把持久化的跌倒警報（_emergencyAlerts，來自
    //   emergency_alerts 表）也併入「最新警示」。根因見上方欄位宣告處的註解——
    //   activity_log 與 emergency_alerts 是兩張互不相交的表，故歷史跌倒過去永遠不會
    //   出現在這裡，只有觸發當下的 activeAlerts 即時 overlay 曾短暫顯示、一關掉/重開
    //   App 就消失。
    //   dedupe：同一筆跌倒若「現在仍是即時警報」會同時存在於 activeAlerts（上面的
    //   activeItems）與剛查回來的 _emergencyAlerts；後端對同一長輩+裝置+alert_type
    //   且 status='active' 的重複跌倒是 UPSERT、沿用同一個 alert_id（見
    //   uban-api/routers/alert.py 開頭註解），故用 alert_id 當去重鍵是可靠的。
    final Set<String> liveAlertIds = widget.activeAlerts
        .map((a) => (a['alert_id'] ?? a['alertId'])?.toString())
        .whereType<String>()
        .toSet();

    final persistedAlertItems = _emergencyAlerts.where((row) {
      // 沿用上方 activeItems 迴圈同一套「隔離不同長輩警報」規則
      final rElderId = (row['elder_id'] ?? row['elderId'])?.toString();
      if (currentElderIdStr != null && rElderId != null && rElderId != currentElderIdStr) {
        return false;
      }
      final rAlertId = (row['alert_id'] ?? row['alertId'])?.toString();
      if (rAlertId != null && liveAlertIds.contains(rAlertId)) {
        return false; // 目前仍是即時警報，已由 activeItems 顯示，避免同一筆跌倒重複兩則
      }
      return true;
    }).map((row) {
      final type = (row['alert_type'] ?? row['alertType'] ?? 'fall').toString();
      // detected_at 格式比照 `_buildElderLifeFeedSection` 對 timestamp 的處理方式
      // （substring 取日期/時間），維持全檔一致的時間格式風格。
      final detectedAt = (row['detected_at'] ?? row['detectedAt'] ?? '').toString();
      String whenStr = '';
      if (detectedAt.length >= 16) {
        whenStr = '${detectedAt.substring(5, 7)}/${detectedAt.substring(8, 10)} ${detectedAt.substring(11, 16)}';
      }
      String title = '🚨 跌倒緊急警報';
      String desc = '監視機曾偵測到長輩疑似跌倒。';
      if (type == 'crawl') {
        title = '⚠️ 疑似爬行警報';
        desc = '監視機曾偵測到長輩異常爬行動作。';
      } else if (type == 'lying_down') {
        title = '⚠️ 久躺未起警報';
        desc = '長輩曾在監視區域久躺不起。';
      } else if (type == 'prolonged_inactivity') {
        title = '⚠️ 長時間無活動警報';
        desc = '長輩曾出現活動量異常偏低。';
      }
      if (whenStr.isNotEmpty) {
        desc = '$desc（發生於 $whenStr）';
      }
      return {'title': title, 'desc': desc, 'level': 'high', 'icon': Icons.warning_amber_rounded};
    }).toList();

    final allCombinedAlerts = [...activeItems, ...persistedAlertItems, ...alertItems];
    // 上限比照同一支函式（_loadDynamicData）抓取 _realLogs 時已用過的 30 筆，
    // 避免清單隨歷史警報無限增長；沿用既有數字而非另外發明一個。
    final displayAlerts = allCombinedAlerts.take(30).toList();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E1015),
            Color(0xFF0F172A),
            Color(0xFF1A1325),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '最新警示',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Text(
                      '${displayAlerts.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  if (widget.onNavigateToAlerts != null) {
                    widget.onNavigateToAlerts!();
                  } else if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) => AlertCenterScreen(
                          elderName: widget.currentElder?.displayName ?? '長輩',
                          elderId: widget.currentElder?.id,
                        ),
                      ),
                    );
                  }
                },
                child: Row(
                  children: [
                    Text(
                      '查看全部',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF38BDF8),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFF38BDF8)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ★ 2026-08-17 第二十五輪（需求 7）：C3 — 三個真實來源（即時 activeAlerts、
          //   持久化 persistedAlertItems、activity_log 的 alertItems）都是空時，
          //   不再顯示 `_mockAlerts` 假資料，改用明確的空狀態文案，
          //   樣式比照 `_buildElderLifeFeedSection` 的空狀態（Icon + 提示文字）。
          if (displayAlerts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    const Icon(Icons.verified_rounded, color: Colors.white38, size: 44),
                    const SizedBox(height: 8),
                    Text(
                      '目前沒有任何警示',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 14,
                        color: Colors.white60,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...displayAlerts.asMap().entries.map((e) => Padding(
                  padding: EdgeInsets.only(bottom: e.key < displayAlerts.length - 1 ? 12 : 0),
                  child: _AlertItem(data: e.value, index: e.key),
                )),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 400.ms);
  }
}

class _PulseDot extends StatelessWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .fade(duration: 1200.ms, begin: 1.0, end: 0.3)
        .then()
        .fade(duration: 1200.ms, begin: 0.3, end: 1.0);
  }
}

class _AlertItem extends StatelessWidget {
  final Map<String, dynamic> data;
  final int index;
  const _AlertItem({required this.data, required this.index});

  @override
  Widget build(BuildContext context) {
    Color levelColor;
    Color iconBgColor;
    Color cardBgColor;
    Color titleColor;
    Color descColor;
    BorderSide borderSide;

    switch (data['level'] as String) {
      case 'high':
        levelColor = const Color(0xFFF87171);
        iconBgColor = const Color(0xFF7F1D1D);
        cardBgColor = const Color(0xFF231012);
        titleColor = const Color(0xFFFECACA);
        descColor = const Color(0xFFFCA5A5);
        borderSide = BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.5), width: 1.2);
        break;
      case 'medium':
        levelColor = const Color(0xFFFBBF24);
        iconBgColor = const Color(0xFF78350F);
        cardBgColor = const Color(0xFF221A08);
        titleColor = const Color(0xFFFEF08A);
        descColor = const Color(0xFFFDE68A);
        borderSide = BorderSide(color: const Color(0xFFF59E0B).withValues(alpha: 0.5), width: 1.2);
        break;
      default:
        levelColor = const Color(0xFF38BDF8);
        iconBgColor = const Color(0xFF075985);
        cardBgColor = const Color(0xFF091F2C);
        titleColor = const Color(0xFFBAE6FD);
        descColor = const Color(0xFF7DD3FC);
        borderSide = BorderSide(color: const Color(0xFF0284C7).withValues(alpha: 0.5), width: 1.2);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.fromBorderSide(borderSide),
        boxShadow: [
          BoxShadow(
            color: levelColor.withValues(alpha: 0.08),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              data['icon'] as IconData,
              color: levelColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['title'] as String,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data['desc'] as String,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 13.5,
                    color: descColor,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right_rounded,
            color: levelColor,
            size: 22,
          ),
        ],
      ),
    ).animate(delay: (index * 80).ms).fadeIn().slideX(begin: 0.05);
  }
}
