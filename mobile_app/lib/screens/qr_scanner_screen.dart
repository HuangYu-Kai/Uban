import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../widgets/ui/ui.dart';

class QrScannerScreen extends StatelessWidget {
  const QrScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 相機邏輯維持原樣，只在外面加疊層。
          MobileScanner(
            controller: MobileScannerController(
              detectionSpeed: DetectionSpeed.noDuplicates,
              facing: CameraFacing.back,
            ),
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  Navigator.pop(context, barcode.rawValue);
                  break;
                }
              }
            },
          ),
          // 對準框（不吃觸控）
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: .85), width: 4),
                ),
              ),
            ),
          ),
          // 頂部玻璃列：返回＋標題
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.glass,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: c.glassLine),
                    boxShadow: c.shadows.glass,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(6, 6, 18, 6),
                    child: UbanTopBar(title: '掃描配對碼'),
                  ),
                ),
              ),
            ),
          ),
          // 底部提示
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.glass,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.glassLine),
                    boxShadow: c.shadows.glass,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Text(
                      '把配對條碼放進框內',
                      textAlign: TextAlign.center,
                      style: ubanText(16, FontWeight.w700, c.text),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
