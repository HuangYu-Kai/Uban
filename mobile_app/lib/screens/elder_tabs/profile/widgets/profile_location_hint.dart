import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../services/location_device_status.dart';
import '../../../../widgets/ui/ui.dart';

/// 位置分享列下方的「手機沒開定位」提示：白話說明原因＋一顆大按鈕直接帶長輩去修。
///
/// 沒有 Row——文字與按鈕都是整列寬度、可自動換行，不會溢位（鐵律 #14）。
/// 長輩從設定頁回來後由 `ElderProfileTab.didChangeAppLifecycleState` 重查，
/// 修好了提示就會自己消失（那邊負責隱藏，本 widget 只負責畫出來）。
class LocationStatusHint extends StatelessWidget {
  /// `LocationDeviceStatus` 的狀態字串。
  final String status;

  const LocationStatusHint({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final String message;
    final String buttonLabel;
    final Future<bool> Function() onPressed;
    switch (status) {
      case LocationDeviceStatus.serviceDisabled:
        message = '手機的定位功能關閉了';
        buttonLabel = '打開定位';
        onPressed = Geolocator.openLocationSettings;
        break;
      case LocationDeviceStatus.foregroundOnly:
        message = '位置權限只開了「使用 App 時」，請改成「一律允許」，家人才看得到';
        buttonLabel = '前往設定';
        onPressed = Geolocator.openAppSettings;
        break;
      default: // permission_denied／permission_denied_forever
        message = '還沒允許 Uban 使用位置';
        buttonLabel = '前往設定';
        onPressed = Geolocator.openAppSettings;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.warmContainer,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.warm, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '⚠️ $message',
            style: ubanText(19, FontWeight.w900, c.warm, height: 1.4),
          ),
          const SizedBox(height: 12),
          UbanButton(
            label: buttonLabel,
            onPressed: () async {
              try {
                await onPressed();
              } catch (e) {
                debugPrint('⚠️ [ElderProfileTab] 開啟手機設定失敗: $e');
              }
            },
          ),
        ],
      ),
    );
  }
}
