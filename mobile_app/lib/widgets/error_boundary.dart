import 'package:flutter/material.dart';

/// ★ 第五十一輪（任務 2）：泛用的「一張卡片壞掉不能拖垮整頁」防護罩。
///
/// 背景：`FamilyDataTab` 的卡片是在父層 `build()` 內同步、eager 呼叫一整串
/// `_buildXxxCard()` 建出來的（`SliverChildListDelegate`），任何一個
/// builder 丟例外都會讓例外一路往上炸穿整個 `_FamilyDataTabState.build()`
/// 這一次的 Dart 函式呼叫，Flutter 完全來不及在單一卡片的層級攔截——結果
/// 是整個分頁被換成 `ErrorWidget`；而且因為這個 State 活在 `IndexedStack`
/// 下被保活，父層每 2.5 秒的裝置／警報輪詢又會持續 `setState()` 觸發重建，
/// 同一個例外會一路重現到使用者關掉整個 App 為止（同類案例見
/// `CLAUDE_call-monitor-guardrails.md` G78：後端字串沒有 default 分支，
/// 「拋出去整個分頁白畫面」）。
///
/// **用法（務必用 builder，不能傳已經建好的 Widget）**：
/// ```dart
/// ErrorBoundary(name: '照顧者卡片', builder: () => _buildCaregiverCard())
/// ```
/// 若改成 `ErrorBoundary(child: _buildCaregiverCard())`，`_buildCaregiverCard()`
/// 這個呼叫會在建構 `ErrorBoundary` 這個物件之前、當作參數求值的一部分先
/// 執行——例外早在 `ErrorBoundary` 存在之前就已經拋出並往外傳播，這個
/// widget 完全看不到、攔不到。用 `Widget Function()` 把「呼叫」本身包成
/// 一個延遲執行的 closure，才能確保 `_buildCaregiverCard()` 是在
/// `ErrorBoundary` 自己的 `build()`（框架逐一建構每個 Element 時才會呼叫，
/// 天然與其他卡片的建構分屬不同的呼叫堆疊）裡面才真正執行，讓下面的
/// try/catch 攔得到。
///
/// 建構期間丟例外時，只有這一張卡片換成精簡的「載入失敗＋重試」提示，
/// 其餘卡片與整個分頁不受影響；`debugPrint` 會印出 [name] 與完整的
/// error/stack，方便之後定位真正的根因——本輪任務明確要求「沒有指認出
/// 單一會拋出的行，不要臆測沒證據的成因」，因此這裡只做韌性與可診斷性，
/// 不對任何特定卡片動手術。
///
/// 刻意設計成與 `FamilyDataTab` 無關的通用元件（不依賴任何家屬端／長輩端
/// 專屬的型別或 State）：往後任何一個「單張卡片壞掉不該拖垮整頁」的場景，
/// 都可以直接重用，不必再寫一份。
class ErrorBoundary extends StatefulWidget {
  /// 產生卡片內容的 callback。**必須是 `Widget Function()`，不能是先建好的
  /// `Widget`**——理由見本類別頂端的說明。
  final Widget Function() builder;

  /// 卡片名稱，只用於 `debugPrint` 的錯誤紀錄，方便從 log 定位是哪一張卡片。
  final String name;

  const ErrorBoundary({
    super.key,
    required this.builder,
    required this.name,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  /// 使用者按下「重試」時遞增，逼底下的 `Builder` 換一個 key、重新呼叫一次
  /// `widget.builder()`。單純 `setState(() {})` 理論上也會重建，但 `Builder`
  /// 換 key 能保證整個子樹（包含任何已經處於壞狀態的內部 State）真正重建，
  /// 而不是被誤判成「同一個 widget，跳過重建」。
  int _retryToken = 0;

  @override
  Widget build(BuildContext context) {
    return Builder(
      key: ValueKey(_retryToken),
      builder: (context) {
        try {
          return widget.builder();
        } catch (error, stack) {
          debugPrint(
              '❌ [ErrorBoundary:${widget.name}] 卡片建構失敗，已攔截、其餘卡片不受影響: $error');
          debugPrint('$stack');
          return _buildFallback(context);
        }
      },
    );
  }

  /// 精簡的「載入失敗＋重試」卡片，風格上比照一般設定卡片（圓角、細邊框），
  /// 但用錯誤色系提示這張卡片目前不正常——不做成看起來很嚴重的滿版紅色
  /// 警示，避免長輩／家屬端使用者誤以為是緊急通知。
  Widget _buildFallback(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.error.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: cs.error, size: 22),
          const SizedBox(width: 10),
          // ⚠️ 鐵律 #14：固定文案但同列還有重試按鈕，仍包 Flexible／ellipsis
          // 防禦系統字級放大時溢位。
          Flexible(
            child: Text(
              '這張卡片載入失敗',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: cs.onErrorContainer,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => setState(() => _retryToken++),
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('重試'),
          ),
        ],
      ),
    );
  }
}
