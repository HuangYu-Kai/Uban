import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

class FamilySubscriptionScreen extends StatelessWidget {
  const FamilySubscriptionScreen({super.key});

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
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
              style: GoogleFonts.notoSansTc(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            _buildPlanCard(
              context,
              title: '免費版',
              price: 'NT\$ 0',
              subtitle: '基礎陪伴與體驗',
              color: Colors.grey[400]!,
              features: ['每日限次 AI 對話', '標準電台頻道', '3 天活動紀錄'],
              buttonLabel: '當前方案',
              isCurrent: true,
            ),
            const SizedBox(height: 16),
            _buildPlanCard(
              context,
              title: '個人進階版',
              price: 'NT\$ 199',
              period: '/ 月',
              subtitle: '深度情緒分析與長期記憶',
              color: const Color(0xFFFF9800),
              features: ['無限 AI 對話', '完整的劇本編輯器', 'AI 深度月報', '優先處理權'],
              buttonLabel: '立即升級',
              isPopular: true,
            ),
            const SizedBox(height: 16),
            _buildPlanCard(
              context,
              title: '家庭專業版',
              price: 'NT\$ 499',
              period: '/ 月',
              subtitle: '多設備管理與 24/7 緊急救助',
              color: const Color(0xFF3F51B5),
              features: ['多達 3 台設備管理', '家屬端帳號無上限', '終身回憶錄雲端備份', '24/7 緊急救助連線'],
              buttonLabel: '聯絡客服或訂閱',
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(
    BuildContext context, {
    required String title,
    required String price,
    String period = '',
    required String subtitle,
    required Color color,
    required List<String> features,
    required String buttonLabel,
    bool isPopular = false,
    bool isCurrent = false,
  }) {
    return Container(
      width: double.infinity,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
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
                    onPressed: isCurrent ? null : () {},
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
                      buttonLabel,
                      style: GoogleFonts.notoSansTc(
                        fontWeight: FontWeight.bold,
                      ),
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
}
