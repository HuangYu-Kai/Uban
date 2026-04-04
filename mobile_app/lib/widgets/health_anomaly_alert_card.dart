import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/health_anomaly_detector.dart';

/// 健康異常警告卡片 - 展示異常檢測結果
class HealthAnomalyAlertCard extends StatelessWidget {
  final HealthAnomalyResult result;
  final VoidCallback? onDismiss;

  const HealthAnomalyAlertCard({
    super.key,
    required this.result,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (!result.hasAnomalies && result.overallStatus == 'healthy') {
      return const SizedBox.shrink();
    }

    final statusColor = _parseColor(result.getStatusColor());

    return GestureDetector(
      onTap: () => _showDetailedAlert(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: statusColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: statusColor.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 背景脈衝動畫
            if (result.overallStatus == 'critical' || result.overallStatus == 'warning')
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                )
                    .animate(onPlay: (controller) => controller.repeat())
                    .fadeIn(duration: 1000.ms)
                    .then()
                    .fadeOut(duration: 1000.ms),
              ),
            // 內容
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 標題
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          result.getStatusMessage(),
                          style: GoogleFonts.notoSansTc(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (onDismiss != null)
                        GestureDetector(
                          onTap: onDismiss,
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withValues(alpha: 0.7),
                            size: 20,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 異常清單
                  ...result.anomalies.take(2).map((anomaly) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Text(
                            anomaly.getSeverityIcon(),
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${anomaly.title}: ${anomaly.description}',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (result.anomalies.length > 2)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '+ ${result.anomalies.length - 2} 個其他異常',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.7),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  // 風險評分條
                  _buildRiskScoreBar(result.riskScore),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().slideY(begin: -0.1, duration: 500.ms).fadeIn();
  }

  /// 風險評分進度條
  Widget _buildRiskScoreBar(int score) {
    final percentage = score / 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '健康風險評分',
              style: GoogleFonts.notoSansTc(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$score / 100',
              style: GoogleFonts.notoSansTc(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.3),
            valueColor: AlwaysStoppedAnimation<Color>(
              percentage > 0.7
                  ? Colors.red[300]!
                  : percentage > 0.5
                      ? Colors.orange[300]!
                      : Colors.green[300]!,
            ),
          ),
        ),
      ],
    );
  }

  /// 將十六進制顏色字符串轉換為 Color
  Color _parseColor(String hexColor) {
    return Color(int.parse('0xFF' + hexColor.replaceFirst('#', '')));
  }

  /// 顯示詳細警告對話
  void _showDetailedAlert(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // 標題
              Center(
                child: Text(
                  result.getStatusMessage(),
                  style: GoogleFonts.notoSansTc(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // 詳細異常列表
              ...result.anomalies.map((anomaly) {
                final anomalyColor = _parseColor(anomaly.getSeverityColor());
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border(
                      left: BorderSide(
                        color: anomalyColor,
                        width: 4,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${anomaly.getSeverityIcon()} ${anomaly.title}',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        anomaly.description,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 13,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: anomalyColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '💡 ${anomaly.recommendation}',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 12,
                            color: anomalyColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

/// 健康狀態指示器 - 顯示在 AppBar
class HealthStatusIndicator extends StatelessWidget {
  final HealthAnomalyResult result;

  const HealthStatusIndicator({
    super.key,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _parseColor(result.getStatusColor());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: statusColor,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            result.overallStatus == 'healthy' ? '✅' : '⚠️',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(width: 8),
          Text(
            'Risk: ${result.riskScore}',
            style: GoogleFonts.notoSansTc(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String hexColor) {
    return Color(int.parse('0xFF' + hexColor.replaceFirst('#', '')));
  }
}
