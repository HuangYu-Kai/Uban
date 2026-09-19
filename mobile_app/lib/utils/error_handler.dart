import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 🛡️ 全局錯誤處理器
class ErrorHandler {
  /// 顯示錯誤訊息
  static void showError(
    BuildContext context,
    String message, {
    String? title,
    VoidCallback? onRetry,
  }) {
    showDialog(
      context: context,
      builder: (context) => ErrorDialog(
        title: title ?? '發生錯誤',
        message: message,
        onRetry: onRetry,
      ),
    );
  }

  // ★ 第五十輪（適老化）：以下三個 SnackBar 共用同一套「長輩讀得到」的樣式
  // 常數，字級／圖示／配色／時長都比照 `ElderScale`（見 `lib/theme/app_theme.dart`）
  // 的精神一次調整，不要各自為政再度分裂出不一致的樣式。
  //
  // - 字級：14 → 20pt，粗體，行高加大，讀起來像一句話而不是一行小字。
  // - 配色：原本 白字配 #EF4444/#10B981/#F59E0B 三色，飽和度高但對白色文字的
  //   對比不足（#10B981、#F59E0B 對白字的對比度都低於 WCAG AA 大字最低要求
  //   3:1）。改用更深的同色系（red-700 / emerald-700 / amber-800），對白字
  //   對比度都在 5:1 以上，長輩與色弱使用者都看得清楚。
  // - 圖示：24 → 32pt，跟文字一樣放大，不是只放大文字忘記圖示。
  // - 時長：長輩讀字慢，預設 3~4 秒對一句話而言太短；錯誤/警告類需要使用者
  //   看懂並決定下一步，拉到 5 秒，成功類只是確認訊息，拉到 4 秒即可。
  // - Padding：內距加大，觸控與視覺呼吸空間都比照大字版面。
  static const double _kSnackBarFontSize = 20;
  static const double _kSnackBarIconSize = 32;

  static TextStyle _snackBarTextStyle() => GoogleFonts.notoSansTc(
        fontSize: _kSnackBarFontSize,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        height: 1.3,
      );

  /// SnackBar 內容共用版面：圖示 + 文字。
  /// ⚠️ 鐵律 #14：訊息字串長度不可控（後端錯誤訊息、使用者輸入回顯等），
  /// 字級放大後更容易溢位，`Text` 一律包 `Flexible` 並允許最多 3 行 + 省略
  /// 號，不能假設一行放得下。
  static Widget _snackBarContent(IconData icon, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: _kSnackBarIconSize),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              message,
              style: _snackBarTextStyle(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 顯示錯誤 SnackBar
  static void showErrorSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 5),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: _snackBarContent(Icons.error_outline_rounded, message),
        backgroundColor: const Color(0xFFB91C1C),
        behavior: SnackBarBehavior.floating,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: duration,
      ),
    );
  }

  /// 顯示成功訊息
  static void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: _snackBarContent(Icons.check_circle_rounded, message),
        backgroundColor: const Color(0xFF047857),
        behavior: SnackBarBehavior.floating,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: duration,
      ),
    );
  }

  /// 顯示警告訊息
  /// [action] 選填：部分警告需要提供操作捷徑（例如「前往設定」開啟權限），
  /// 呼叫端可自行組一個 `SnackBarAction` 傳進來，不必為此另外寫一個原生
  /// SnackBar 繞過本封裝，才能讓樣式維持統一。
  static void showWarning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 5),
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: _snackBarContent(Icons.warning_amber_rounded, message),
        backgroundColor: const Color(0xFF92400E),
        behavior: SnackBarBehavior.floating,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: duration,
        action: action,
      ),
    );
  }

  /// 處理異常並顯示適當訊息
  static void handleException(
    BuildContext context,
    dynamic error, {
    VoidCallback? onRetry,
  }) {
    String message;
    
    if (error is NetworkException) {
      message = '網路連線失敗，請檢查網路設定';
    } else if (error is AuthenticationException) {
      message = '身份驗證失敗，請重新登入';
    } else if (error is TimeoutException) {
      message = '連線逾時，請稍後再試';
    } else if (error is ServerException) {
      message = '伺服器錯誤，請稍後再試';
    } else {
      message = '發生未預期的錯誤';
    }
    
    showError(context, message, onRetry: onRetry);
  }
}

/// 錯誤對話框
class ErrorDialog extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const ErrorDialog({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFEF4444),
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: GoogleFonts.notoSansTc(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1E293B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    child: Text(
                      '關閉',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        onRetry!();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        '重試',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 自定義異常類型
class NetworkException implements Exception {
  final String message;
  NetworkException([this.message = 'Network error']);
}

class AuthenticationException implements Exception {
  final String message;
  AuthenticationException([this.message = 'Authentication failed']);
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException([this.message = 'Request timeout']);
}

class ServerException implements Exception {
  final String message;
  ServerException([this.message = 'Server error']);
}

/// 載入狀態管理 Widget
class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;
  final String? loadingText;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.loadingText,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.black.withValues(alpha: 0.3),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    if (loadingText != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        loadingText!,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 空狀態 Widget
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 64,
                color: const Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: GoogleFonts.notoSansTc(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1E293B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
