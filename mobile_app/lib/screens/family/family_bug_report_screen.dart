import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../services/bug_report_service.dart';
import '../../theme/app_theme.dart';

/// 家屬端「回報問題 / 意見反饋」畫面。
///
/// 對接後端 `uban-api/routers/admin.py::submit_bug_report`
/// （`POST /api/bug-report`，未認證，成功回 201）。入口放在
/// `FamilyDataTab`（「資料」分頁）「📱 裝置配對與加值服務」群組之後、
/// 系統資訊卡片之前的新群組——BUG 回報是低頻但重要的功能，不適合放在
/// 首頁／互動這種高頻畫面，也不值得為它新增一個頂層分頁，「資料」分頁本來
/// 就是其他次級設定（訂閱、通知、裝置配對）的集散地。
///
/// 刻意不用 `ElderScale`：家屬是一般使用者，沿用一般字級 [AppTextStyles]／
/// [AppColors]，寫法比照同資料夾的 `family_add_friend_screen.dart`。
///
/// 錯誤處理與白話文案交給 [BugReportService]（見該檔說明），本畫面只負責：
/// - 送出前的長度／非空白驗證（`TextField.maxLength` 已擋住超長輸入，這裡
///   再做一次防呆截斷＋trim 後的非空檢查，避免打一堆空白就送出）。
/// - 組出 `device_info`／`app_version` 並截斷到後端上限（200／32 字元）。
///   專案未導入 `package_info_plus` 之類套件，依指示改用 `dart:io` 的
///   `Platform` 取作業系統資訊；App 版本沒有可讀的執行期來源，沿用
///   `family_data_tab.dart::_buildSystemInfoCard()` 已經顯示給使用者看的
///   版本字串（見 [_appVersionDisplay]），不是 pubspec.yaml 的 `version:`
///   （那個值目前沒有對使用者顯示過，兩者不保證一致）。
/// - 送出成功／429 限流／404 查無回報者／網路失敗四種情況的畫面回饋。
class FamilyBugReportScreen extends StatefulWidget {
  final int familyId;

  const FamilyBugReportScreen({
    super.key,
    required this.familyId,
  });

  @override
  State<FamilyBugReportScreen> createState() => _FamilyBugReportScreenState();
}

class _FamilyBugReportScreenState extends State<FamilyBugReportScreen> {
  /// 與 `family_data_tab.dart::_buildSystemInfoCard()` 顯示給使用者看的
  /// 版本字串保持一致——見本檔檔頭說明。
  static const String _appVersionDisplay = 'v2.4.0 (Build 2026.08)';

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  late final String _deviceInfo;
  late final String _appVersion;

  @override
  void initState() {
    super.initState();
    _deviceInfo = _buildDeviceInfo();
    _appVersion = _clamp(_appVersionDisplay, 32);
    _titleController.addListener(_handleFieldsChanged);
    _contentController.addListener(_handleFieldsChanged);
  }

  @override
  void dispose() {
    _titleController.removeListener(_handleFieldsChanged);
    _contentController.removeListener(_handleFieldsChanged);
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _handleFieldsChanged() {
    // 只是為了讓送出鍵的 enabled 狀態即時反映「是否已填寫」，不做其他事。
    if (mounted) setState(() {});
  }

  String _clamp(String value, int maxLength) =>
      value.length > maxLength ? value.substring(0, maxLength) : value;

  String _buildDeviceInfo() {
    String raw;
    try {
      raw = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      // 理論上手機平台不會走到這裡，純粹防呆。
      raw = 'unknown';
    }
    return _clamp(raw, 200);
  }

  bool get _canSubmit =>
      !_isSubmitting &&
      _titleController.text.trim().isNotEmpty &&
      _contentController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    // TextField 的 maxLength 已經擋住超長輸入，這裡再做一次防呆截斷。
    final title = _clamp(_titleController.text.trim(), 100);
    final content = _clamp(_contentController.text.trim(), 2000);

    final reportId = await BugReportService.submit(
      reporterType: 'family',
      reporterId: widget.familyId.toString(),
      title: title,
      content: content,
      deviceInfo: _deviceInfo,
      appVersion: _appVersion,
    );

    if (!mounted) return;

    if (reportId != null) {
      setState(() => _isSubmitting = false);
      await _showSuccessDialog(reportId);
      return;
    }

    // 送出失敗（404／429／422／網路連線失敗皆已在 BugReportService 轉成白話
    // 文案）——刻意不清空 _titleController / _contentController，讓使用者
    // 可以直接重試而不必重新輸入。
    setState(() {
      _isSubmitting = false;
      _errorMessage = BugReportService.lastError ?? '送出失敗，請稍後再試';
    });
  }

  Future<void> _showSuccessDialog(int reportId) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 40),
        title: Text('回報已送出', style: AppTextStyles.heading, textAlign: TextAlign.center),
        content: Text(
          '回報編號 #$reportId\n感謝您協助我們改善服務，我們會盡快處理。',
          style: AppTextStyles.body,
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext); // 關閉對話框
              if (mounted) Navigator.pop(context); // 回到「資料」分頁
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text('回報問題', style: AppTextStyles.title),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '遇到問題，或有想告訴我們的建議嗎？請填寫下方表單，我們會盡快處理。',
                style: AppTextStyles.secondary,
              ),
              const SizedBox(height: 18),
              if (_errorMessage != null) ...[
                _buildErrorBanner(_errorMessage!),
                const SizedBox(height: 16),
              ],
              Text('標題', style: AppTextStyles.heading),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                maxLength: 100,
                maxLines: 1,
                enabled: !_isSubmitting,
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: '簡短描述問題，例如：無法撥打視訊電話',
                  hintStyle: AppTextStyles.secondary,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('詳細內容', style: AppTextStyles.heading),
              const SizedBox(height: 8),
              TextField(
                controller: _contentController,
                maxLength: 2000,
                minLines: 6,
                maxLines: 12,
                enabled: !_isSubmitting,
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: '請描述發生的狀況、操作步驟，以及您原本預期的結果',
                  hintStyle: AppTextStyles.secondary,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildAttachedInfoRow(),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _canSubmit ? _submit : null,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                  label: Text(_isSubmitting ? '送出中...' : '送出回報'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.textHint,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 送出前先讓使用者知道會一併附上什麼——後端刻意不記錄任何未經使用者
  /// 輸入的個資，這裡也對稱地把「唯二會附加的資訊」攤開給使用者看。
  /// Row 內是 Icon + Expanded(Text)，長字串（裝置資訊組出來的長度不固定）
  /// 可收縮，符合鐵律 #14 / 護欄 G159。
  Widget _buildAttachedInfoRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.primaryDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '將一併傳送裝置資訊（$_deviceInfo）與 App 版本（$_appVersion），協助我們排查問題',
              style: AppTextStyles.secondary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 樣式比照 `family_add_friend_screen.dart::_buildErrorBanner`，維持家屬端
  /// 錯誤提示的一致視覺語言。
  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.secondary.copyWith(color: const Color(0xFFB91C1C)),
            ),
          ),
        ],
      ),
    );
  }
}
