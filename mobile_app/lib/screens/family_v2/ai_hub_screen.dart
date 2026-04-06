import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../family_v2/widgets/ai_suggestion_card.dart';
import '../family_v2/widgets/emotion_preview_card.dart';
import '../family_v2/widgets/vital_signs_widget.dart';
import '../family_v2/alert_center_screen.dart';
import '../family_v2/health_trends_screen.dart';
import '../family_v2/family_collaboration_screen.dart';
import '../family/family_settings_view.dart';
import '../video_call_screen.dart';

/// 🎯 AI 智能中樞 - 全新子女端首頁
/// 
/// 設計理念：AI 是主動的照護夥伴，而非被動的工具
/// 三大核心：今日智能建議 + 情緒時間軸預覽 + 實時生命徵象
class AiHubScreen extends StatefulWidget {
  const AiHubScreen({super.key});

  @override
  State<AiHubScreen> createState() => _AiHubScreenState();
}

class _AiHubScreenState extends State<AiHubScreen> {
  String? _elderName;
  int? _elderId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // 優化：延遲載入，讓 UI 先渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadElderInfo();
    });
  }

  Future<void> _loadElderInfo() async {
    // TODO: 從 SharedPreferences 或 API 加載選定的長輩信息
    // 優化：減少延遲時間
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) {
      setState(() {
        _elderName = '李奶奶'; // 模擬數據
        _elderId = 1;
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshData() async {
    HapticFeedback.lightImpact();
    setState(() => _isLoading = true);
    // 優化：減少刷新延遲
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _handleQuickAccessTap(String route) {
    HapticFeedback.lightImpact();
    
    Widget? destination;
    
    switch (route) {
      case 'health_trends':
        destination = HealthTrendsScreen(
          elderName: _elderName ?? '長輩',
          elderId: _elderId,
        );
        break;
      case 'collaboration':
        destination = FamilyCollaborationScreen(
          elderName: _elderName ?? '長輩',
          elderId: _elderId,
        );
        break;
      case 'alerts':
        destination = AlertCenterScreen(
          elderName: _elderName ?? '長輩',
          elderId: _elderId,
        );
        break;
      case 'video':
        // 啟動視訊通話
        destination = VideoCallScreen(
          roomId: _elderId?.toString() ?? '1',
          autoStart: true,
        );
        break;
    }
    
    if (destination != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => destination!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _refreshData,
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    // 🎨 頂部 AppBar
                    _buildAppBar(),
                    
                    // 📋 主要內容區
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          // ⭐ 今日智能建議卡
                          AiSuggestionCard(
                            elderName: _elderName ?? '長輩',
                            elderId: _elderId,
                          ).animate()
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.1, end: 0),
                          
                          const SizedBox(height: 16),
                          
                          // 📊 情緒時間軸預覽
                          EmotionPreviewCard(
                            elderName: _elderName ?? '長輩',
                            elderId: _elderId,
                          ).animate()
                            .fadeIn(delay: 100.ms, duration: 400.ms)
                            .slideY(begin: 0.1, end: 0),
                          
                          const SizedBox(height: 16),
                          
                          // 💓 實時生命徵象
                          VitalSignsWidget(
                            elderName: _elderName ?? '長輩',
                            elderId: _elderId,
                          ).animate()
                            .fadeIn(delay: 200.ms, duration: 400.ms)
                            .slideY(begin: 0.1, end: 0),
                          
                          const SizedBox(height: 32),
                          
                          // 🔗 快速訪問區
                          _buildQuickAccessSection(),
                          
                          const SizedBox(height: 80), // 底部導航留白
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  /// 頂部 AppBar
  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      backgroundColor: Colors.white,
      elevation: 0,
      actions: [
        // 設定按鈕
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            icon: Icon(
              Icons.settings_rounded,
              color: Color(0xFF64748B),
              size: 26,
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FamilySettingsView(
                    userId: 0, // TODO: 從context取得真實userId
                    userName: _elderName ?? '用戶',
                  ),
                ),
              );
            },
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF3B82F6).withValues(alpha: 0.1),
                const Color(0xFF8B5CF6).withValues(alpha: 0.1),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'AI 智能中樞',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF1E293B),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '正在關照：',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 14,
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _elderName ?? '未選擇',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 14,
                          color: const Color(0xFF3B82F6),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 快速訪問區
  Widget _buildQuickAccessSection() {
    final items = [
      {
        'icon': Icons.show_chart_rounded,
        'label': '健康趨勢',
        'color': const Color(0xFF10B981),
        'route': 'health_trends',
      },
      {
        'icon': Icons.people_rounded,
        'label': '家庭協作',
        'color': const Color(0xFF8B5CF6),
        'route': 'collaboration',
      },
      {
        'icon': Icons.videocam_rounded,
        'label': '視訊關懷',
        'color': const Color(0xFF3B82F6),
        'route': 'video',
      },
      {
        'icon': Icons.notifications_active_rounded,
        'label': '警示中心',
        'color': const Color(0xFFF59E0B),
        'route': 'alerts',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            '快速訪問',
            style: GoogleFonts.notoSansTc(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
            ),
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: items.map((item) {
            return GestureDetector(
              onTap: () => _handleQuickAccessTap(item['route'] as String),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (item['color'] as Color).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        item['icon'] as IconData,
                        color: item['color'] as Color,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item['label'] as String,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
              ),
            ).animate()
              .fadeIn(delay: (300 + items.indexOf(item) * 50).ms)
              .scale(begin: const Offset(0.9, 0.9));
          }).toList(),
        ),
      ],
    );
  }
}
