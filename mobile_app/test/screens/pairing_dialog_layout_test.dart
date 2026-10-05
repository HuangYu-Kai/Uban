import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 回歸測試：family_pairing_dialog 的配對碼 QR 必須包在「固定尺寸的框」裡。
///
/// 背景（自主長輩補綁家人時「配對碼跳不出來、卡片變空白」的根因）：
/// AlertDialog 會對內容做 intrinsic 高度測量，而 qr_flutter 的 QrImageView
/// 不支援 intrinsic 尺寸，裸放（沒有外層固定尺寸 Container）會在
/// performLayout 的 getMaxIntrinsicHeight 直接拋例外——debug 顯紅框、release
/// 整張卡靜默變空白。包進固定尺寸 Container 可擋住往下的 intrinsic 測量。
///
/// 這支測試重現「對話框內有 QR 的成功卡片」結構，確保它不再拋版面例外；
/// 若日後有人把 QR 外層的固定框拿掉，這支會立刻紅起來。
void main() {
  Widget dialogHost(Widget qr) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog(
                  context: ctx,
                  builder: (_) => AlertDialog(
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('請子女掃描下方 QR Code',
                              style: GoogleFonts.notoSansTc(fontSize: 16)),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Column(
                              children: [
                                Text('1495',
                                    style: GoogleFonts.inter(fontSize: 48)),
                                const SizedBox(height: 12),
                                qr,
                                const SizedBox(height: 12),
                                const Text('配對倒數: 600 秒'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  testWidgets('配對碼 QR 包固定框時，對話框不拋版面例外', (tester) async {
    await tester.pumpWidget(dialogHost(
      Container(
        width: 160,
        height: 160,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: QrImageView(
          data: '1495',
          version: QrVersions.auto,
          size: 140.0,
          backgroundColor: Colors.white,
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('1495'), findsOneWidget);
  });
}
