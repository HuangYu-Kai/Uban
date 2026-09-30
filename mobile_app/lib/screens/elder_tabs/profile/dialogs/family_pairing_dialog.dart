import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../services/api_service.dart';

/// 🔄 方案 C：隨時後續補綁定家人對話框（Late-Binding）
void showFamilyPairingDialog(BuildContext context, [int? explicitElderId]) {
  HapticFeedback.lightImpact();

  Future<Map<String, dynamic>> fetchCode() async {
    try {
      int? targetId = explicitElderId;
      if (targetId == null) {
        final prefs = await SharedPreferences.getInstance();
        targetId = prefs.getInt('caregiver_id') ?? prefs.getInt('last_elder_id');
      }
      return await ApiService.requestPairingCode(targetId);
    } catch (e) {
      return {'status': 'error', 'message': '取得配對碼失敗: $e'};
    }
  }

  // 對話框可能按「重新取得配對碼」重試多次；用可重指派的 Future 搭配
  // StatefulBuilder，讓每次重試都能重新觸發載入並 rebuild。
  Future<Map<String, dynamic>> pairingCodeFuture = fetchCode();

  showDialog(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (context, setDialogState) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          backgroundColor: Colors.white,
          elevation: 8,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. 標題列
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEA580C).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.family_restroom_rounded,
                          color: Color(0xFFEA580C),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '家人／照護者綁定',
                          style: GoogleFonts.notoSansTc(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            color: const Color(0xFF1E293B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 2. 說明文字
                  Text(
                    '請子女開啟手機上的 Uban App，掃描下方 QR Code 或輸入配對碼即可完成連線：',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 15,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '💡 這是給家人綁定用的臨時配對碼，過期即失效，和您的「好友 ID」不是同一組號碼喔',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 12.5,
                      color: const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. 非同步載入配對碼
                  FutureBuilder<Map<String, dynamic>>(
                    future: pairingCodeFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(
                                color: Color(0xFFEA580C),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                '正在產生安全配對碼...',
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 14,
                                  color: const Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final result = snapshot.data;
                      final data = result?['data'] as Map<String, dynamic>?;
                      final String? code = data?['pairing_code'] as String?;

                      // ★ 失敗處理
                      if (snapshot.hasError ||
                          result == null ||
                          result['status'] == 'error' ||
                          code == null ||
                          code.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFFECACA),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: Color(0xFFDC2626),
                                size: 32,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '暫時無法取得配對碼，請稍後再試',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFB91C1C),
                                ),
                              ),
                              const SizedBox(height: 14),
                              ElevatedButton.icon(
                                onPressed: () {
                                  setDialogState(() {
                                    pairingCodeFuture = fetchCode();
                                  });
                                },
                                icon: const Icon(Icons.refresh_rounded, size: 18),
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
                        padding: const EdgeInsets.symmetric(
                          vertical: 18,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: const Color(0xFFFDBA74),
                            width: 1.5,
                          ),
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
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFFEA580C),
                                letterSpacing: 6,
                              ),
                            ),
                            const SizedBox(height: 12),
                            // 使用 CustomPaint + QrPainter 取代 QrImageView，
                            // 徹底杜絕 LayoutBuilder 引起的對話框白屏問題
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFFED7AA),
                                  width: 1,
                                ),
                              ),
                              child: CustomPaint(
                                size: const Size(140, 140),
                                painter: QrPainter(
                                  data: code,
                                  version: QrVersions.auto,
                                  gapless: true,
                                  eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: Color(0xFF1E293B),
                                  ),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '配對倒數: $expiresInSeconds 秒',
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // 4. 效益提示條
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF059669),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '綁定後，子女可遠端排定吃藥，並即時關心您的每日健康與小豬！',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 13,
                              color: const Color(0xFF065F46),
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 5. 關閉按鈕
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                      child: Text(
                        '知道了',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF59B294),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
