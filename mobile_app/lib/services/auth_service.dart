import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  // === Google 登入設定 ===
  // 注意：雖然 Android 上 Google Sign-in 可以自動透過 google-services.json 讀取 Client ID，
  // 但在 iOS 通常會在程式碼或 GoogleService-Info.plist 裡設定。
  // 若使用 Web 或是單獨的 serverAuthCode 可以在這裡傳入。
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    // clientId: 'YOUR_IOS_CLIENT_ID.apps.googleusercontent.com', // 未來 iOS 需補上
    scopes: [
      'email',
      'profile',
    ],
  );

  /// 執行 Google 登入並返回使用者的 ID Token (用於傳遞給後端驗證)
  static Future<Map<String, dynamic>?> signInWithGoogle() async {
    try {
      // 觸發原生 Google 登入畫面
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) {
        // 使用者取消登入
        return null;
      }
      
      // 獲取登入認證資訊 (含 Token)
      final GoogleSignInAuthentication auth = await account.authentication;
      debugPrint('Google Access Token: ${auth.accessToken}');
      debugPrint('Google ID Token: ${auth.idToken}');
      
      // 通常我們需要 idToken 回傳給後端去 JWT 解析
      return {
        'token': auth.idToken,
        'email': account.email,
        'uid': account.id,
      };
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      rethrow;
    }
  }

  /// 執行 Google 登出
  static Future<void> signOutGoogle() async {
    await _googleSignIn.signOut();
  }

  // === LINE 登入設定 ===
  
  /// 初始化 LINE SDK (應在 main 函式中呼叫)
  static Future<void> initLineSdk(String channelId) async {
    try {
      await LineSDK.instance.setup(channelId).then((_) {
        debugPrint('LineSDK Prepared');
      });
    } catch (e) {
      debugPrint('LineSDK Setup Error: $e');
    }
  }

  /// 執行 LINE 登入並返回 Access Token (可用於傳遞給後端驗證)
  static Future<Map<String, dynamic>?> signInWithLine() async {
    try {
      // 觸發原生 LINE 登入畫面
      // 注意：如果您需要 'email' 權限，必須先在 LINE Developers 後台申請「Email address permission」，否則會出現 400 錯誤。
      final result = await LineSDK.instance.login(
        scopes: ['profile', 'openid'],
      );
      
      debugPrint('LINE User ID: ${result.userProfile?.userId}');
      debugPrint('LINE Display Name: ${result.userProfile?.displayName}');
      
      return {
        'token': result.accessToken.value,
        'email': result.userProfile?.data['email'], // 注意：需申請權限
        'uid': result.userProfile?.userId,
      };
    } catch (e) {
      debugPrint('LINE Sign-In Error: $e');
      rethrow;
    }
  }

  /// 執行 LINE 登出
  static Future<void> signOutLine() async {
    try {
      await LineSDK.instance.logout();
    } catch (e) {
      debugPrint('LINE Sign-Out Error: $e');
    }
  }
}
