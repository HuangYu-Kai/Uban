import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:permission_handler/permission_handler.dart';

class VideoCallPermissionService {
  static const String _warning =
      '視訊通話需要相機、麥克風、通知、鎖定螢幕顯示、後台彈出介面與浮動資訊框權限。若未開啟，APP 在背景或鎖定螢幕時可能無法接收或建立通話。';

  static Future<void> requestOnFirstUse(BuildContext context) async {
    if (kIsWeb) return;

    final statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.notification,
      Permission.systemAlertWindow,
      Permission.ignoreBatteryOptimizations,
    ].request();

    bool fullScreenAllowed = true;
    try {
      fullScreenAllowed = await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (!fullScreenAllowed) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
        fullScreenAllowed = await FlutterCallkitIncoming.canUseFullScreenIntent();
      }
    } catch (_) {}

    final missingCritical =
        statuses[Permission.camera] != PermissionStatus.granted ||
        statuses[Permission.microphone] != PermissionStatus.granted ||
        statuses[Permission.notification] != PermissionStatus.granted ||
        statuses[Permission.systemAlertWindow] != PermissionStatus.granted ||
        !fullScreenAllowed;

    if (!missingCritical || !context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('視訊通話權限不足'),
        content: const Text(_warning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('稍後處理'),
          ),
          ElevatedButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(dialogContext);
            },
            child: const Text('前往設定'),
          ),
        ],
      ),
    );
  }
}
