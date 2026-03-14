import 'package:flutter/foundation.dart';

ValueNotifier<Map<String, String?>?> pendingAcceptedCall = ValueNotifier(null);
bool isAppReady = false;
String? appRole;
