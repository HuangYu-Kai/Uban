// 僅供問卷體驗版（lib/main_demo.dart）使用，正式 App 不會引用。
//
// 網頁版沒有初始化 Firebase，`FirebaseMessaging.instance` 會直接丟例外，使
// family_main_screen／video_call_screen 在取得推播 token 那一行中斷、連不上即時通道。
// 那些檔案屬於通話保護範圍，不為體驗版修改；改在入口掛上「沒有推播」的假平台：
// getToken 一律回 null，其餘照常走 Socket。
// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_messaging_platform_interface/firebase_messaging_platform_interface.dart';

void installDemoFakeFirebase() {
  FirebasePlatform.instance = _FakeFirebase();
  FirebaseMessagingPlatform.instance = _FakeMessaging();
}

class _FakeFirebase extends FirebasePlatform {
  static final FirebaseAppPlatform _app = FirebaseAppPlatform(
    defaultFirebaseAppName,
    const FirebaseOptions(
        apiKey: 'demo', appId: 'demo', messagingSenderId: 'demo', projectId: 'demo'),
  );

  @override
  List<FirebaseAppPlatform> get apps => [_app];

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _app;

  @override
  Future<FirebaseAppPlatform> initializeApp(
          {String? name, FirebaseOptions? options}) async =>
      _app;
}

class _FakeMessaging extends FirebaseMessagingPlatform {
  @override
  FirebaseMessagingPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseMessagingPlatform setInitialValues({bool? isAutoInitEnabled}) => this;

  @override
  bool get isAutoInitEnabled => false;

  @override
  Future<String?> getToken(
          {String? vapidKey, String? serviceWorkerScriptPath}) async =>
      null;

  @override
  Future<void> deleteToken() async {}

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Future<RemoteMessage?> getInitialMessage() async => null;

  @override
  Future<bool> isSupported() async => false;
}
