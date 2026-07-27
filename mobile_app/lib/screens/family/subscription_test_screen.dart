// ============================================================================
// SubscriptionTestScreen — RevenueCat 訂閱測試頁（家屬端）
// ----------------------------------------------------------------------------
// 用途：家屬（子女端）替長輩開通進階照護方案的 Paywall 測試頁。
//       目前為 Mock / Sandbox 開發測試階段，用來驗證 RevenueCat 串接是否正常：
//       載入 Offering、選方案、模擬購買、恢復購買、切換測試 User、查詢權限。
//
// 依賴：pubspec.yaml → purchases_flutter: ^8.0.0
//
// ★ 測試方式：RevenueCat「Test Store」— 官方虛擬測試環境 -----------------------
//   不需 Google Play / App Store 設定、不綁信用卡、模擬器可直接測。
//   購買時會跳出模擬視窗，讓你選「成功 / 失敗 / 取消」，權限即時更新。
//
//   1) RevenueCat Dashboard → 左側「Apps and providers」→ Test configuration
//      → 建立 Test Store → 複製 API key（test_ 開頭）。
//   2) 本頁開啟時會自動 Purchases.configure()（見 _ensureConfigured），
//      金鑰用 --dart-define 傳入即可，「不必改 main.dart」：
//        flutter run --dart-define=REVENUECAT_API_KEY=test_你的金鑰 ...
//      （或直接填入下方 _apiKey 常數）
//   3) purchases_flutter 是 native plugin，加依賴後要「完全重跑」flutter run。
//
//   ⚠️ 安全警告：正式上架（Google Play / App Store）絕不能用 test_ 金鑰，
//      要換成平台金鑰（Android goog_ / iOS appl_）；正式版也建議把 configure()
//      移到 main.dart 啟動時做一次。
//
// ---- 導頁（從家屬端任何地方打開）--------------------------------------------
//   Navigator.of(context).push(
//     MaterialPageRoute(builder: (_) => const SubscriptionTestScreen()),
//   );
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

  /// RevenueCat Test Store 金鑰（test_ 開頭）。
  /// 建議用 --dart-define=REVENUECAT_API_KEY=test_xxx 傳入，或直接填在 defaultValue。
  static const String _apiKey = String.fromEnvironment(
    'REVENUECAT_API_KEY',
    defaultValue: '', // 例如 'test_xxxxxxxxxxxxxxxx'
  );

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

  /// 首次進頁：確保 SDK 已 configure → 讀權限狀態 + 抓 offering。
  Future<void> _bootstrap() async {
    setState(() {
      _initialLoading = true;
      _loadError = null;
    });
    try {
      await _ensureConfigured();
      await _syncCustomerInfo();
      await _loadOfferings();
    } catch (e) {
      _loadError = '初始化失敗：$e';
    } finally {
      if (mounted) setState(() => _initialLoading = false);
    }
  }

  /// 若尚未 configure，就用 Test Store 金鑰初始化。
  /// Test Store 是 RevenueCat 官方虛擬測試環境，不需 Google Play / App Store、不綁卡。
  Future<void> _ensureConfigured() async {
    if (await Purchases.isConfigured) return;
    if (_apiKey.isEmpty) {
      throw 'RevenueCat 尚未設定金鑰。請到 Dashboard → Apps and providers → '
          'Test configuration 建立 Test Store，取得 test_ 開頭金鑰後，用 '
          '--dart-define=REVENUECAT_API_KEY=test_xxx 啟動（或填入本檔 _apiKey 常數）。';
    }
    await Purchases.setLogLevel(LogLevel.debug);
    await Purchases.configure(
      PurchasesConfiguration(_apiKey)..appUserID = 'dev_test_user_001',
    );
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
