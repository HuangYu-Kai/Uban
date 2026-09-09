import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../services/api_service.dart';

/// 🔄 方案 C：隨時後續補綁定家人對話框（Late-Binding）
void showFamilyPairingDialog(BuildContext context) {
  HapticFeedback.lightImpact();

  // 對話框可能按「重新取得配對碼」重試多次；用可重指派的 Future 搭配
  // StatefulBuilder，讓每次重試都能重新觸發載入並 rebuild。
  Future<Map<String, dynamic>> pairingCodeFuture =
      ApiService.requestPairingCode();

  showDialog(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEA580C).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.family_restroom_rounded,
                    color: Color(0xFFEA580C), size: 28),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  '家人／照護者綁定',
                  style: GoogleFonts.notoSansTc(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '請子女開啟手機上的 Uban App，掃描下方 QR Code 或輸入配對碼即可完成連線：',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '💡 這是給家人綁定用的臨時配對碼，過期即失效，和您的「好友 ID」不是同一組號碼喔',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 13,
                    color: const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                FutureBuilder<Map<String, dynamic>>(
                  future: pairingCodeFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final result = snapshot.data;
                    final data = result?['data'] as Map<String, dynamic>?;
                    final String? code = data?['pairing_code'] as String?;

                    // ★ 失敗（連線失敗／逾時／後端回傳 error／欄位缺漏）一律
                    //   顯示白話錯誤＋重試鍵，絕不用猜測值兜底。
                    if (snapshot.hasError ||
                        result == null ||
                        result['status'] == 'error' ||
                        code == null ||
                        code.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: const Color(0xFFFECACA), width: 1.5),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: Color(0xFFDC2626), size: 32),
                            const SizedBox(height: 8),
                            Text(
                              '暫時無法取得配對碼，請稍後再試',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.notoSansTc(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFB91C1C),
                              ),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: () {
                                setDialogState(() {
                                  pairingCodeFuture =
                                      ApiService.requestPairingCode();
                                });
                              },
                              icon: const Icon(Icons.refresh_rounded,
                                  size: 18),
                              label: Text(
                                '重新取得配對碼',
                                style: GoogleFonts.notoSansTc(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final int expiresInSeconds =
                        (data?['expires_in_seconds'] as int?) ?? 600;
                    return Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: const Color(0xFFFDBA74), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withValues(alpha: 0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            code,
                            style: GoogleFonts.inter(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFEA580C),
                              letterSpacing: 6,
                            ),
                          ),
                          const SizedBox(height: 12),
                          QrImageView(
                            data: code,
                            version: QrVersions.auto,
                            size: 140.0,
                            backgroundColor: Colors.white,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '配對倒數: $expiresInSeconds 秒',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: Color(0xFF059669), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '綁定後，子女可遠端排定吃藥，並即時關心您的每日健康與小豬！',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 13.5,
                            color: const Color(0xFF065F46),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                '知道了',
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF59B294),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
