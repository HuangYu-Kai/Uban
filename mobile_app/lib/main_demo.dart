// 問卷體驗版（Flutter Web）進入點。
//
// 建置：flutter build web -t lib/main_demo.dart --base-href /demo/app/ ...
// 由 /demo/index.html（外殼）以兩個同源 iframe 載入：
//   /demo/app/index.html?role=elder 與 ?role=family
// 外殼把後端配好的 session 寫進 localStorage（demo_<role>.demo_session），
// 本檔據此預填 SharedPreferences，讓 SplashScreen 直接走「已登入」路徑；
// 並以 postMessage 把進度與少量事件回報給外殼。
//
// 只做「唯讀」橋接：不呼叫 Signaling 的任何連線／回呼設定，只讀欄位、掛 onAny。
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import 'globals.dart';
import 'main.dart' as app;
import 'screens/privacy_policy_screen.dart';
import 'services/signaling.dart';
import 'utils/demo_fake_firebase.dart';

/// 轉發給外殼的 socket 事件白名單。
const Set<String> _forwardEvents = {
  'elder-question',
  'elder-question-answered',
  'elder-checkin',
  'elder-checkin-missed',
  'checkin-cheer',
  'daily-answer',
  'daily-question-new',
  'pet-gift',
  'pet-gift-fed',
  'heartbeat-message',
  'family-share-new',
  'agent-task-done',
  'step-challenge',
  'call-request',
  'emergency-call',
  'call-accept',
  'cancel-call',
  'end-call',
  'call-busy',
  'location-alert',
  'cctv-alert',
};

String _role = 'elder';

void main() {
  runZonedGuarded(_boot, (e, s) => debugPrint('[demo] uncaught: $e'));
}

Future<void> _boot() async {
  WidgetsFlutterBinding.ensureInitialized();

  final r = Uri.base.queryParameters['role'];
  _role = r == 'family' ? 'family' : 'elder';

  // 必須在任何 getInstance 之前：兩端（同源）的 localStorage 才不會互相覆蓋。
  // Web 的舊版 API 以 localStorage[prefix + key] = JSON 字串 存放。
  SharedPreferences.setPrefix('demo_$_role.');

  // 字型：NotoSansTC 各字重由建置腳本對應到隨附的子集字型，不會下載；少數純英數字型
  // （開場 Poppins 等）未打包，允許 google_fonts 下載一次（每個約 150KB），避免反覆報錯重試。

  installDemoFakeFirebase();

  try {
    await _seedPrefs();
  } catch (e) {
    debugPrint('[demo] seed prefs failed: $e');
  }

  // ignore: discarded_futures
  app.main();

  _startBridge();
}

// ---------------------------------------------------------------------------
// 預填 SharedPreferences
// ---------------------------------------------------------------------------

Future<void> _seedPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('demo_session');
  if (raw == null || raw.isEmpty) return; // 外殼尚未寫入：交給 App 自己的登入流程
  final session = jsonDecode(raw);
  if (session is! Map) return;
  final token = session['token']?.toString() ?? '';
  if (token.isEmpty) return;

  if (prefs.getString('demo_token') != token) {
    await prefs.clear(); // 只清掉本角色前綴的鍵
    await prefs.setString('demo_session', raw); // clear 會把它也清掉，補回
    await prefs.setString('demo_token', token);
  }

  // 每次啟動都重寫（App 可能在上次執行中把鍵改掉／登出）。
  final family = (session['family'] as Map?) ?? const {};
  final elder = (session['elder'] as Map?) ?? const {};
  final elderUserId = _asInt(elder['user_id']);
  final elderName = (elder['name'] ?? '王奶奶').toString();
  final elderRoom = (elder['elder_id'] ?? '').toString();
  final familyUserId = _asInt(family['user_id']);
  final familyName = (family['name'] ?? '王小明').toString();

  await prefs.setBool(PrivacyPolicyScreen.prefsKey, true);
  await prefs.setBool('elder_all_tutorials_dismissed', true);
  await prefs.setBool('miui_permission_guide_seen', true);
  await prefs.setBool('wake_word_pref_reset_v52', true);
  await prefs.setBool(kWakeWordEnabledKey, false);

  if (_role == 'elder') {
    if (elderUserId == null) return;
    await prefs.setInt('caregiver_id', elderUserId);
    await prefs.setString('caregiver_name', elderName);
    await prefs.setString('user_role', 'elder');
    await prefs.setString('saved_role', 'elder');
    await prefs.setString('elder_room_id', elderRoom);
    await prefs.setBool('saved_is_cctv', false);
    await prefs.setString('saved_device_name', '$elderName的設備');
    await prefs.setString('device_role_$elderRoom', 'comm');
    await prefs.setInt('last_elder_id', elderUserId);
    await prefs.setString('last_elder_name', elderName);
    await prefs.setString('last_elder_room_id', elderRoom);
    await prefs.setString('last_elder_device_role', 'comm');
  } else {
    if (familyUserId == null) return;
    await prefs.setInt('caregiver_id', familyUserId);
    await prefs.setString('caregiver_name', familyName);
    await prefs.setString('user_role', 'family');
    await prefs.setString('saved_role', 'family');
    if (elderUserId != null) {
      await prefs.setInt('selected_elder_id', elderUserId);
      await prefs.setString('selected_elder_name', elderName);
      await prefs.setString('selected_elder_room_id', elderRoom);
    }
  }
}

int? _asInt(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}');

// ---------------------------------------------------------------------------
// 與外殼（parent window）的橋接
// ---------------------------------------------------------------------------

void _post(String type, [Map<String, Object?> extra = const {}]) {
  try {
    final parent = web.window.parent;
    if (parent == null) return;
    final msg = <String, Object?>{
      'src': 'uban-demo',
      'role': _role,
      'type': type,
      ...extra,
    };
    parent.postMessage(msg.jsify(), web.window.location.origin.toJS);
  } catch (_) {}
}

dynamic _safeValue(dynamic v) {
  if (v is String) return v.length > 120 ? v.substring(0, 120) : v;
  if (v is num || v is bool) return v;
  return null;
}

Map<String, Object?> _safeData(dynamic data) {
  final out = <String, Object?>{};
  try {
    dynamic d = data;
    if (d is List && d.isNotEmpty) d = d.first;
    if (d is Map) {
      for (final e in d.entries) {
        if (out.length >= 8) break;
        final v = _safeValue(e.value);
        if (v != null) out['${e.key}'] = v;
      }
    } else {
      final v = _safeValue(d);
      if (v != null) out['value'] = v;
    }
  } catch (_) {}
  return out;
}

bool _emergencyFlag = false;

void _startBridge() {
  // ready：runApp 之後的第一個影格
  Timer.periodic(const Duration(milliseconds: 200), (t) async {
    try {
      if (WidgetsBinding.instance.rootElement == null) return;
      t.cancel();
      await WidgetsBinding.instance.endOfFrame;
      _post('ready');
    } catch (_) {}
  });

  // home：Splash 結束
  var sawSplash = false;
  var homeSent = false;
  Timer.periodic(const Duration(milliseconds: 200), (t) {
    try {
      if (splashActive) {
        sawSplash = true;
      } else if (sawSplash && !homeSent) {
        homeSent = true;
        _post('home');
        t.cancel();
      }
    } catch (_) {}
  });

  // 通話狀態與緊急旗標
  try {
    pendingAcceptedCall.addListener(() {
      try {
        if (pendingAcceptedCall.value?['isEmergency'] == 'true') {
          _emergencyFlag = true;
        }
      } catch (_) {}
    });
  } catch (_) {}

  bool? lastActive;
  bool lastEmergency = false;
  Timer.periodic(const Duration(milliseconds: 300), (_) {
    try {
      final s = Signaling();
      // 只看 peerConnection：掛斷後 callId／localStream 可能殘留，會誤判成還在通話。
      final active = s.peerConnection != null;
      if (!active && lastActive == true) _emergencyFlag = false;
      if (active != lastActive || _emergencyFlag != lastEmergency) {
        lastActive = active;
        lastEmergency = _emergencyFlag;
        _post('call', {'active': active, 'emergency': _emergencyFlag});
      }
    } catch (_) {}
  });

  // socket 事件：每個 socket 實例只掛一次（重連會換新實例）
  final attached = Expando<bool>('demoAnyAttached');
  Timer.periodic(const Duration(milliseconds: 500), (_) {
    try {
      final sock = Signaling().socket;
      if (sock == null || attached[sock] == true) return;
      attached[sock] = true;
      sock.onAny((dynamic event, [dynamic data]) {
        try {
          final name = event?.toString() ?? '';
          if (!_forwardEvents.contains(name)) return;
          if (name == 'emergency-call') _emergencyFlag = true;
          _post('event', {'name': name, 'data': _safeData(data)});
        } catch (_) {}
      });
    } catch (_) {}
  });
}
