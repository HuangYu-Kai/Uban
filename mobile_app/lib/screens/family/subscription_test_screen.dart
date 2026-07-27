// ============================================================================
// SubscriptionTestScreen — RevenueCat 訂閱測試頁（家屬端）
// ----------------------------------------------------------------------------
// 用途：家屬（子女端）替長輩開通進階照護方案的 Paywall 測試頁。
//       目前為 Mock / Sandbox 開發測試階段，用來驗證 RevenueCat 串接是否正常：
//       載入 Offering、選方案、模擬購買、恢復購買、切換測試 User、查詢權限。
//
// 依賴：pubspec.yaml → purchases_flutter: ^8.0.0
//
// ---- 一、main.dart 初始化（只需做一次）--------------------------------------
//   import 'dart:io' show Platform;
//   import 'package:purchases_flutter/purchases_flutter.dart';
//
//   Future<void> main() async {
//     WidgetsFlutterBinding.ensureInitialized();
//
//     // 測試階段開 debug log，方便在 console 看 RevenueCat 事件
//     await Purchases.setLogLevel(LogLevel.debug);
//
//     // ⚠️ 換成 RevenueCat 後台 → Project settings → API keys 的「公開 SDK 金鑰」
//     //    Android 用 goog_ 開頭、iOS 用 appl_ 開頭
//     final apiKey = Platform.isIOS ? 'appl_你的iOS金鑰' : 'goog_你的Android金鑰';
//
//     await Purchases.configure(
//       PurchasesConfiguration(apiKey)
//         // 測試用固定 User ID；正式版建議帶「家屬帳號 id」讓權限跟著家屬走。
//         // 也可整行拿掉，讓 SDK 自動產生匿名 ID。
//         ..appUserID = 'dev_test_user_001',
//     );
//
//     runApp(const MyApp());
//   }
//
// ---- 二、導頁（從家屬端任何地方打開）----------------------------------------
//   Navigator.of(context).push(
//     MaterialPageRoute(builder: (_) => const SubscriptionTestScreen()),
//   );
//
// 註：purchases_flutter 是 native plugin，加入依賴後需「完全重跑」App
//     （flutter run，非 hot reload）才會生效。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class SubscriptionTestScreen extends StatefulWidget {
  const SubscriptionTestScreen({super.key});

  @override
  State<SubscriptionTestScreen> createState() => _SubscriptionTestScreenState();
}

class _SubscriptionTestScreenState extends State<SubscriptionTestScreen> {
  /// RevenueCat 後台設定的 Entitlement Identifier。
  static const String _entitlementId = 'pro_access';

  // ---- 狀態 ----------------------------------------------------------------
  bool _initialLoading = true; // 首次載入 offerings / 權限
  bool _busy = false; // 購買 / 恢復 / 切換 User 等動作進行中
  String? _loadError; // 首次載入失敗訊息（顯示在頁面上）

  String _appUserId = '載入中…';
  bool _isPro = false;

  List<Package> _packages = [];
  Package? _selected;

  final TextEditingController _userIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  // ==========================================================================
  // 資料載入
  // ==========================================================================

  /// 首次進頁：讀權限狀態 + 抓 offering。
  Future<void> _bootstrap() async {
    setState(() {
      _initialLoading = true;
      _loadError = null;
    });
    try {
      await _syncCustomerInfo();
      await _loadOfferings();
    } catch (e) {
      _loadError = '初始化失敗：$e\n請確認 main.dart 已呼叫 Purchases.configure()、且金鑰正確。';
    } finally {
      if (mounted) setState(() => _initialLoading = false);
    }
  }

  /// 抓取 current offering 的三個方案（月 / 季 / 年）。
  Future<void> _loadOfferings() async {
    final offerings = await Purchases.getOfferings();
    final current = offerings.current;

    final list = <Package>[];
    if (current != null) {
      // 優先依「月 → 季 → 年」固定順序；若後台用了非標準 package，
      // 就退回 availablePackages 全部顯示，避免漏方案。
      final ordered = <Package?>[
        current.monthly,
        current.threeMonth,
        current.annual,
      ].whereType<Package>().toList();

      list.addAll(ordered.isNotEmpty ? ordered : current.availablePackages);
    }

    if (mounted) {
      setState(() {
        _packages = list;
        _selected = list.isNotEmpty ? list.first : null;
      });
    }
  }

  /// 讀取最新 CustomerInfo → 更新 PRO 狀態與 App User ID。
  Future<void> _syncCustomerInfo() async {
    final info = await Purchases.getCustomerInfo();
    _isPro = info.entitlements.active.containsKey(_entitlementId);
    _appUserId = await Purchases.appUserID;
    if (mounted) setState(() {});
  }

  // ==========================================================================
  // 使用者動作
  // ==========================================================================

  /// 「重新整理狀態」：重新查詢 pro_access 是否 active。
  Future<void> _refreshStatus() async {
    await _runGuarded(() async {
      await _syncCustomerInfo();
      _showSnack(_isPro ? '狀態已更新：目前為 PRO' : '狀態已更新：目前為 FREE');
    }, failMsg: '讀取狀態失敗');
  }

  /// 「模擬點擊購買」：purchasePackage(selectedPackage)。
  Future<void> _purchaseSelected() async {
    final pkg = _selected;
    if (pkg == null) {
      _showSnack('請先選擇一個方案');
      return;
    }
    await _runGuarded(() async {
      // 回傳型別在不同 purchases_flutter 版本略有差異，
      // 這裡購買後一律重新查詢 CustomerInfo，最穩定。
      await Purchases.purchasePackage(pkg);
      await _syncCustomerInfo();
      _showSnack(
        _isPro ? '購買成功，已為長輩解鎖 PRO 進階照護！' : '購買流程結束，但尚未偵測到 PRO 權限',
      );
    }, failMsg: '購買失敗');
  }

  /// 「恢復購買」：restorePurchases()。
  Future<void> _restorePurchases() async {
    await _runGuarded(() async {
      final info = await Purchases.restorePurchases();
      _isPro = info.entitlements.active.containsKey(_entitlementId);
      _appUserId = await Purchases.appUserID;
      if (mounted) setState(() {});
      _showSnack(_isPro ? '已恢復購買，PRO 已啟用' : '已執行恢復購買，但查無有效訂閱');
    }, failMsg: '恢復購買失敗');
  }

  /// 切換 / 登入自訂測試 User ID：logIn(newUserId)。
  Future<void> _switchUser() async {
    final newId = _userIdController.text.trim();
    if (newId.isEmpty) {
      _showSnack('請先輸入要切換的 User ID');
      return;
    }
    await _runGuarded(() async {
      final result = await Purchases.logIn(newId);
      _isPro = result.customerInfo.entitlements.active.containsKey(_entitlementId);
      _appUserId = await Purchases.appUserID;
      if (mounted) setState(() {});
      await _loadOfferings(); // 換 User 後方案可能不同，重抓一次
      _showSnack('已切換至 User：$newId');
    }, failMsg: '切換 User 失敗');
  }

  /// 統一的動作包裝：設 busy、catch RevenueCat 例外、確保不崩潰。
  Future<void> _runGuarded(
    Future<void> Function() action, {
    required String failMsg,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        _showSnack('已取消操作');
      } else {
        _showSnack('$failMsg：${e.message ?? code.toString()}');
      }
    } catch (e) {
      _showSnack('$failMsg：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg, style: GoogleFonts.notoSansTc(color: Colors.white)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E293B),
        ),
      );
  }

  // ==========================================================================
  // UI
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(
          '訂閱測試（RevenueCat）',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: Stack(
        children: [
          if (_initialLoading)
            const Center(child: CircularProgressIndicator())
          else
            _buildContent(),
          // 動作進行中的半透明遮罩 + 轉圈
          if (_busy)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loadError != null) _buildErrorBanner(),
          _buildStatusCard(),
          const SizedBox(height: 16),
          _buildUserSwitcher(),
          const SizedBox(height: 24),
          Text(
            '選擇方案（為長輩開通）',
            style: GoogleFonts.notoSansTc(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          _buildPlanList(),
          const SizedBox(height: 24),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEF4444)),
      ),
      child: Text(
        _loadError!,
        style: GoogleFonts.notoSansTc(color: const Color(0xFF991B1B), fontSize: 13),
      ),
    );
  }

  Widget _buildStatusCard() {
    final Color accent = _isPro ? const Color(0xFF16A34A) : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.badge_outlined, size: 18, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text(
                '測試 User ID',
                style: GoogleFonts.notoSansTc(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            _appUserId,
            style: GoogleFonts.robotoMono(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const Divider(height: 28),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isPro ? Icons.workspace_premium : Icons.lock_outline,
                      size: 18,
                      color: accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isPro ? '已解鎖 VIP (PRO)' : '未訂閱 (FREE)',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '重新整理狀態',
                onPressed: _busy ? null : _refreshStatus,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_isPro)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '長輩已享有 PRO 進階照護服務。',
                style: GoogleFonts.notoSansTc(fontSize: 13, color: accent),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUserSwitcher() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '切換測試 User',
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _userIdController,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '例如 dev_test_user_001',
                    hintStyle: GoogleFonts.notoSansTc(color: Colors.grey[400]),
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _busy ? null : _switchUser,
                child: Text('切換', style: GoogleFonts.notoSansTc()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlanList() {
    if (_packages.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '目前抓不到任何方案。\n請確認 RevenueCat 後台已建立 default Offering，並包含月/季/年方案。',
          style: GoogleFonts.notoSansTc(color: Colors.grey[600], fontSize: 13),
        ),
      );
    }

    // Flutter 3.32+ 建議用 RadioGroup 祖先統一管理選取值，
    // 個別 RadioListTile 只需給 value。busy 時把 onChanged 設 null 即整組停用。
    return RadioGroup<Package>(
      groupValue: _selected,
      // RadioGroup.onChanged 為必填且非 nullable，改在 callback 內判斷 busy。
      onChanged: (v) {
        if (_busy || v == null) return;
        setState(() => _selected = v);
      },
      child: Column(
        children: _packages.map(_buildPlanTile).toList(),
      ),
    );
  }

  Widget _buildPlanTile(Package pkg) {
    final bool selected = identical(pkg, _selected) ||
        (_selected != null && pkg.identifier == _selected!.identifier);
    final product = pkg.storeProduct;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? const Color(0xFF38BDF8) : const Color(0xFFE2E8F0),
          width: selected ? 2 : 1,
        ),
      ),
      child: RadioListTile<Package>(
        value: pkg,
        activeColor: const Color(0xFF0EA5E9),
        title: Row(
          children: [
            Expanded(
              child: Text(
                _planLabel(pkg),
                style: GoogleFonts.notoSansTc(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            Text(
              product.priceString,
              style: GoogleFonts.notoSansTc(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0EA5E9),
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${product.title}  ·  ${pkg.identifier}',
          style: GoogleFonts.notoSansTc(fontSize: 12, color: Colors.grey[600]),
        ),
      ),
    );
  }

  /// 依 packageType 給友善中文名稱（月 / 季 / 年）。
  String _planLabel(Package pkg) {
    switch (pkg.packageType) {
      case PackageType.monthly:
        return '月費方案';
      case PackageType.threeMonth:
        return '季費方案';
      case PackageType.annual:
        return '年費方案';
      default:
        return pkg.storeProduct.title;
    }
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (_busy || _selected == null) ? null : _purchaseSelected,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0EA5E9),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: const Icon(Icons.shopping_cart_checkout),
            label: Text(
              '模擬點擊購買',
              style: GoogleFonts.notoSansTc(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _restorePurchases,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.restore),
                label: Text('恢復購買', style: GoogleFonts.notoSansTc()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _refreshStatus,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.refresh),
                label: Text('重新整理狀態', style: GoogleFonts.notoSansTc()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
