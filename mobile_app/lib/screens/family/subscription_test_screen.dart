// ============================================================================
// SubscriptionTestScreen — RevenueCat 訂閱頁（家屬端 Paywall）
// ----------------------------------------------------------------------------
// 用途：家屬（子女端）替長輩開通進階照護方案的付費頁。
//       金流走 RevenueCat，目前為 Mock / Sandbox 開發測試階段：
//       載入 Offering、選方案、模擬購買、恢復購買、查詢權限。
//
// 依賴：pubspec.yaml → purchases_flutter: ^8.0.0
//
// ★ 版面（2026-08-10 改版）--------------------------------------------------
//   採「官網 Pricing 頁」骨架、Uban 既有配色（slate + sky #0284C7 / #38BDF8）：
//     Hero 標題 → 目前狀態列 → 月/季/年方案卡（自算每月均價與省下 %）
//     → 「所有方案都包含」特色清單 → 深色 CTA → 小字條款 → 開發者選項（收合）
//   除錯用的 App User ID、切換測試 User、後端狀態對照，全部收進最下方
//   ExpansionTile「開發者選項」，正式使用者不會第一眼看到。
//   ⚠️ 特色清單目前是 UI 文案，尚未對應真正被鎖住的功能
//      （見 docs/technical/SUBSCRIPTION_ARCHITECTURE.md ❽「功能鎖尚未接上」）。
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
// ---- 綁定長輩（正式流程的核心）----------------------------------------------
//   傳入 elderId 後，本頁會把 RevenueCat App User ID 設為 elder_<elderId>，
//   購買才會掛在長輩身上；RevenueCat webhook 收到 app_user_id="elder_xxxx"，
//   後端才寫得進 subscription_status，長輩端才查得到 PRO。
//   → 真相以後端 GET /api/subscription/{elderId} 為準（SDK 狀態僅供對照）。
//
// ---- 導頁（從家屬端任何地方打開）--------------------------------------------
//   Navigator.of(context).push(
//     MaterialPageRoute(builder: (_) => SubscriptionTestScreen(
//       elderId: elder.elderId, elderName: elder.displayName,
//     )),
//   );
// ============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../services/api_service.dart';
import '../../services/subscription_service.dart';

/// 版面配色：沿用 App 家屬端既有的 slate + sky 色階，不另開一套。
class _Palette {
  static const canvas = Color(0xFFF8FAFC); // 頁面底
  static const surface = Colors.white; // 卡片
  static const ink = Color(0xFF0F172A); // 主文字 / 深色 CTA
  static const slate = Color(0xFF64748B); // 次要文字
  static const mist = Color(0xFF94A3B8); // 說明小字
  static const line = Color(0xFFE2E8F0); // 邊框
  static const accent = Color(0xFF0284C7); // 強調（選中、勾選）
  static const accentSoft = Color(0xFF38BDF8); // 強調亮色
  static const success = Color(0xFF16A34A); // 已開通
  static const danger = Color(0xFFEF4444);
}

class SubscriptionTestScreen extends StatefulWidget {
  /// 要開通的長輩 elder_id（elder_profile.elder_id，四碼字串）。
  /// 給 null 時退回匿名測試 User，購買不會落到任何長輩身上。
  final String? elderId;
  final String? elderName;

  const SubscriptionTestScreen({super.key, this.elderId, this.elderName});

  @override
  State<SubscriptionTestScreen> createState() => _SubscriptionTestScreenState();
}

class _SubscriptionTestScreenState extends State<SubscriptionTestScreen> {
  /// RevenueCat 後台設定的 Entitlement Identifier。
  /// ⚠️ 實測後台用的是 'Uban-pro'（非最初提到的 pro_access）。可用 dart-define 覆寫。
  static const String _entitlementId = String.fromEnvironment(
    'REVENUECAT_ENTITLEMENT',
    defaultValue: 'Uban-pro',
  );

  /// RevenueCat Test Store 金鑰（test_ 開頭）。
  /// 這是 Test Store 的 **public SDK key**，不是 secret（`sk_`），放前端沒有外洩風險；
  /// 仍可用 --dart-define=REVENUECAT_API_KEY=test_xxx 覆寫。
  /// ⚠️ 正式上架必須換成平台金鑰（Android `goog_` / iOS `appl_`）。
  static const String _apiKey = String.fromEnvironment(
    'REVENUECAT_API_KEY',
    defaultValue: 'test_hGxZbuGwjlZtvuMQthnZPGZPYAk',
  );

  /// 後端 `.env` 的 `REVENUECAT_WEBHOOK_SECRET`，只給「重設為未訂閱」除錯鈕用。
  ///
  /// ⚠️ **預設為空，且絕對不要填進 defaultValue**：這把密鑰是後端用來擋偽造開通的，
  /// 一旦編進 APK，任何人反編譯後就能替任意長輩開通 PRO（見設計文件 ❼-2）。
  /// 要用時才在啟動指令帶：`--dart-define=REVENUECAT_WEBHOOK_SECRET=xxx`。
  /// 後端 `.env` 沒設這個變數時不驗證授權，不帶也能用。
  static const String _webhookSecret = String.fromEnvironment(
    'REVENUECAT_WEBHOOK_SECRET',
    defaultValue: '',
  );

  /// 進階照護的賣點清單。三個方案（月/季/年）內容相同，只差計費週期，
  /// 所以做成「所有方案都包含」的共用區塊，而非每張卡各列一次。
  static const List<String> _features = [
    '不限次數的 AI 陪伴對話',
    '每月 AI 深度情緒與作息洞察報告',
    '完整回憶錄雲端備份，長久保存',
    '專屬劇本編輯器，客製長輩的日常引導',
    '家屬端優先處理與即時關懷通知',
  ];

  // ---- 狀態 ----------------------------------------------------------------
  bool _initialLoading = true; // 首次載入 offerings / 權限
  bool _busy = false; // 購買 / 恢復 / 切換 User 等動作進行中
  String? _loadError; // 首次載入失敗訊息（顯示在頁面上）

  String _appUserId = '載入中…';
  bool _isPro = false; // RevenueCat SDK 端的權限（僅供對照）

  // 後端真相（GET /api/subscription/{elderId}）
  bool _backendIsPro = false;
  bool _backendChecking = false;
  String? _backendExpiresText;

  List<Package> _packages = [];
  Package? _selected;

  /// 沒帶 elderId 時退回匿名測試 User（購買不會落到任何長輩身上）。
  String get _targetAppUserId => widget.elderId == null
      ? 'dev_test_user_001'
      : SubscriptionService.appUserIdFor(widget.elderId!);

  /// 畫面上稱呼長輩的方式；沒帶名字就用泛稱。
  String get _elderLabel => widget.elderName?.trim().isNotEmpty == true
      ? widget.elderName!.trim()
      : '長輩';

  /// 長輩端實際吃的是後端狀態；沒綁長輩（匿名測試）時只好看 SDK。
  bool get _effectiveIsPro => widget.elderId == null ? _isPro : _backendIsPro;

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
      await _refreshBackendStatus();
    } catch (e) {
      _loadError = '初始化失敗：$e';
    } finally {
      if (mounted) setState(() => _initialLoading = false);
    }
  }

  /// 若尚未 configure，就用 Test Store 金鑰初始化，並把身分綁到目標長輩。
  /// Test Store 是 RevenueCat 官方虛擬測試環境，不需 Google Play / App Store、不綁卡。
  ///
  /// 已 configure 的情況（例如從別頁進來、或切換了長輩）→ 用 logIn 換成正確身分，
  /// 否則購買會掛到上一位長輩身上。
  Future<void> _ensureConfigured() async {
    if (await Purchases.isConfigured) {
      final current = await Purchases.appUserID;
      if (current != _targetAppUserId) {
        await Purchases.logIn(_targetAppUserId);
      }
      return;
    }
    if (_apiKey.isEmpty) {
      throw 'RevenueCat 尚未設定金鑰。請到 Dashboard → Apps and providers → '
          'Test configuration 建立 Test Store，取得 test_ 開頭金鑰後，用 '
          '--dart-define=REVENUECAT_API_KEY=test_xxx 啟動（或填入本檔 _apiKey 常數）。';
    }
    await Purchases.setLogLevel(LogLevel.debug);
    await Purchases.configure(
      PurchasesConfiguration(_apiKey)..appUserID = _targetAppUserId,
    );
  }

  /// 查後端真相。webhook 是非同步送達，購買後可能要等幾秒才寫進 DB，
  /// 所以提供 retries：每次間隔 2 秒重查，直到後端也看到 PRO。
  Future<void> _refreshBackendStatus({int retries = 0}) async {
    final elderId = widget.elderId;
    if (elderId == null) return;

    if (mounted) setState(() => _backendChecking = true);
    try {
      for (int attempt = 0; attempt <= retries; attempt++) {
        if (attempt > 0) {
          await Future.delayed(const Duration(seconds: 2));
        }
        final status = await SubscriptionService.fetchStatus(
          elderId,
          forceRefresh: true,
        );
        _backendIsPro = status.isPro;
        _backendExpiresText = status.expiresAt
            ?.toLocal()
            .toString()
            .substring(0, 16);
        if (_backendIsPro) break; // 後端已收到 webhook，不用再等
      }
    } finally {
      if (mounted) setState(() => _backendChecking = false);
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
        // 預設選最划算的一個（通常是年繳），沒有可比價資訊就選第一個。
        _selected = _bestValuePackage(list) ?? (list.isNotEmpty ? list.first : null);
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

  /// 「重新整理狀態」：SDK 與後端各查一次。
  Future<void> _refreshStatus() async {
    await _runGuarded(() async {
      await _syncCustomerInfo();
      await _refreshBackendStatus();
      _showSnack(_effectiveIsPro ? '狀態已更新：目前為 PRO' : '狀態已更新：目前為 FREE');
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
      // 購買前再確認一次身分沒被別頁換掉，否則會開通到別的長輩。
      await _ensureConfigured();
      // 回傳型別在不同 purchases_flutter 版本略有差異，
      // 這裡購買後一律重新查詢 CustomerInfo，最穩定。
      await Purchases.purchasePackage(pkg);
      await _syncCustomerInfo();

      if (widget.elderId == null) {
        _showSnack(_isPro ? '購買成功（未綁定長輩）' : '購買流程結束，但尚未偵測到 PRO 權限');
        return;
      }

      // 等 RevenueCat webhook 打到後端並寫入 subscription_status。
      await _refreshBackendStatus(retries: 4);
      _showSnack(
        _backendIsPro
            ? '購買成功，已為$_elderLabel解鎖 PRO 進階照護！'
            : '購買已完成，但後端尚未收到 webhook（可稍後按重新整理）',
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
      await _refreshBackendStatus(retries: 2);
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

  /// 【除錯專用】把這位長輩的後端訂閱狀態重設為未訂閱。
  ///
  /// ⚠️ **這不是真的取消訂閱**。商店（Google Play / App Store）不允許 App 以程式
  /// 取消訂閱，真正的取消只能由使用者到商店的「訂閱管理」自行操作。本功能是
  /// 直接對後端補送一則 `EXPIRATION` webhook，把 `subscription_status` 翻成未開通，
  /// 好讓你不必等 Test Store 自然到期（約 5 分鐘）就能重測 FREE 狀態。
  ///
  /// 因此：RevenueCat 那邊的訂閱仍然存在，下次續訂 webhook 進來就會再變回 PRO。
  Future<void> _devResetToFree() async {
    final elderId = widget.elderId;
    if (elderId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('重設為未訂閱？', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold)),
        content: Text(
          '會對後端補送一則 EXPIRATION 事件，把 $_elderLabel（elder_$elderId）的訂閱狀態'
          '翻成未開通。\n\n'
          '這是寫進正式資料庫的操作，不是只改本機畫面；也不會真的取消商店那邊的訂閱。',
          style: GoogleFonts.notoSansTc(fontSize: 14, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: GoogleFonts.notoSansTc()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _Palette.danger),
            child: Text('確定重設', style: GoogleFonts.notoSansTc()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _runGuarded(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/revenuecat/webhook'),
        headers: {
          'Content-Type': 'application/json',
          // 後端 .env 沒設 REVENUECAT_WEBHOOK_SECRET 時不驗證，帶空字串也無妨。
          if (_webhookSecret.isNotEmpty) 'Authorization': _webhookSecret,
        },
        body: jsonEncode({
          'event': {
            'type': 'EXPIRATION',
            'id': 'devtool-$now',
            'app_user_id': _targetAppUserId,
            'entitlement_ids': [_entitlementId],
            'product_id': _selected?.storeProduct.identifier,
            'store': 'TEST_STORE',
            'expiration_at_ms': now,
          },
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        _showSnack('後端拒絕（401）：需要用 --dart-define=REVENUECAT_WEBHOOK_SECRET 帶密鑰');
        return;
      }
      if (response.statusCode != 200) {
        _showSnack('重設失敗（HTTP ${response.statusCode}）：${response.body}');
        return;
      }

      SubscriptionService.invalidate(elderId);
      await _refreshBackendStatus();
      _showSnack(_backendIsPro ? '後端仍回報 PRO，請確認事件是否被略過' : '已重設為未訂閱');
    }, failMsg: '重設失敗');
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
          backgroundColor: _Palette.ink,
        ),
      );
  }

  // ==========================================================================
  // 方案比價（每月均價 / 省下多少）
  // ==========================================================================

  /// 一個 package 相當於幾個月；抓不到對應週期回 0（代表不參與比價）。
  int _monthsOf(Package pkg) {
    switch (pkg.packageType) {
      case PackageType.monthly:
        return 1;
      case PackageType.twoMonth:
        return 2;
      case PackageType.threeMonth:
        return 3;
      case PackageType.sixMonth:
        return 6;
      case PackageType.annual:
        return 12;
      default:
        return 0;
    }
  }

  /// 月繳價，作為「省下 %」的比較基準；沒有月繳方案就不做比價。
  double? get _monthlyBaseline {
    for (final p in _packages) {
      if (p.packageType == PackageType.monthly) return p.storeProduct.price;
    }
    return null;
  }

  /// 相對月繳省下的百分比（整數）；不適用時回 null。
  int? _savingPercent(Package pkg) {
    final baseline = _monthlyBaseline;
    final months = _monthsOf(pkg);
    if (baseline == null || baseline <= 0 || months <= 1) return null;
    final perMonth = pkg.storeProduct.price / months;
    final percent = ((1 - perMonth / baseline) * 100).round();
    return percent >= 1 ? percent : null;
  }

  /// 省最多的方案，用來預設選取並掛「最划算」標籤。
  Package? _bestValuePackage(List<Package> list) {
    Package? best;
    int bestSaving = 0;
    for (final p in list) {
      final s = _savingPercent(p) ?? 0;
      if (s > bestSaving) {
        bestSaving = s;
        best = p;
      }
    }
    return best;
  }

  /// 從 priceString 取出幣別前綴（例如 'NT\$'）；取不到就退回 currencyCode。
  String _currencySymbol(StoreProduct product) {
    final prefix = RegExp(r'^[^\d]*').firstMatch(product.priceString)?.group(0) ?? '';
    return prefix.trim().isEmpty ? '${product.currencyCode} ' : prefix;
  }

  /// 「平均每月 NT$166」；不適用（週期不明或就是月繳）時回 null。
  String? _perMonthText(Package pkg) {
    final months = _monthsOf(pkg);
    if (months <= 1) return null;
    final perMonth = pkg.storeProduct.price / months;
    final digits = perMonth >= 10 ? 0 : 2;
    return '平均每月 ${_currencySymbol(pkg.storeProduct)}${perMonth.toStringAsFixed(digits)}';
  }

  /// 依 packageType 給友善中文名稱（月 / 季 / 年）。
  String _planLabel(Package pkg) {
    switch (pkg.packageType) {
      case PackageType.monthly:
        return '月繳方案';
      case PackageType.twoMonth:
        return '雙月方案';
      case PackageType.threeMonth:
        return '季繳方案';
      case PackageType.sixMonth:
        return '半年方案';
      case PackageType.annual:
        return '年繳方案';
      case PackageType.lifetime:
        return '永久方案';
      default:
        return pkg.storeProduct.title;
    }
  }

  /// 價格後綴（/月、/季、/年…）。
  String _periodSuffix(Package pkg) {
    switch (pkg.packageType) {
      case PackageType.monthly:
        return '/月';
      case PackageType.twoMonth:
        return '/2 個月';
      case PackageType.threeMonth:
        return '/季';
      case PackageType.sixMonth:
        return '/半年';
      case PackageType.annual:
        return '/年';
      default:
        return '';
    }
  }

  bool _isSelected(Package pkg) =>
      identical(pkg, _selected) ||
      (_selected != null && pkg.identifier == _selected!.identifier);

  // ==========================================================================
  // UI
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.canvas,
      appBar: AppBar(
        backgroundColor: _Palette.canvas,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        foregroundColor: _Palette.ink,
      ),
      body: Stack(
        children: [
          if (_initialLoading)
            const Center(
              child: CircularProgressIndicator(color: _Palette.accent),
            )
          else
            _buildContent(),
          if (_busy) _buildBusyOverlay(),
        ],
      ),
    );
  }

  Widget _buildBusyOverlay() {
    return Container(
      color: _Palette.ink.withValues(alpha: 0.25),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: _Palette.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const CircularProgressIndicator(color: _Palette.accent),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loadError != null) ...[
            _buildErrorBanner(),
            const SizedBox(height: 20),
          ],
          _buildHero(),
          const SizedBox(height: 24),
          _buildStatusStrip(),
          const SizedBox(height: 28),
          _buildPlanList(),
          const SizedBox(height: 24),
          _buildFeatureCard(),
          const SizedBox(height: 28),
          _buildCta(),
          const SizedBox(height: 12),
          _buildRestoreRow(),
          const SizedBox(height: 20),
          _buildFinePrint(),
          const SizedBox(height: 32),
          _buildDeveloperPanel(),
        ],
      ),
    );
  }

  // ---- Hero -----------------------------------------------------------------

  Widget _buildHero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'UBAN 進階照護',
          style: GoogleFonts.notoSansTc(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.4,
            color: _Palette.accent,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '把最好的陪伴，\n留給$_elderLabel。',
          style: GoogleFonts.notoSansTc(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            height: 1.35,
            letterSpacing: -0.4,
            color: _Palette.ink,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '不限次數的 AI 陪聊、每月深度洞察報告，以及長久保存的回憶錄備份。'
          '選一個適合的計費週期即可，隨時能取消。',
          style: GoogleFonts.notoSansTc(
            fontSize: 15,
            height: 1.75,
            color: _Palette.slate,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 380.ms).slideY(begin: 0.06, curve: Curves.easeOut);
  }

  // ---- 目前狀態列 ------------------------------------------------------------

  Widget _buildStatusStrip() {
    final bool pro = _effectiveIsPro;
    final Color accent = pro ? _Palette.success : _Palette.slate;

    final String detail;
    if (_backendChecking) {
      detail = '查詢中…';
    } else if (pro) {
      detail = _backendExpiresText == null
          ? '進階照護已開通'
          : '進階照護已開通 · 到期 $_backendExpiresText';
    } else {
      detail = '一般方案';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Palette.line),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.notoSansTc(fontSize: 13.5, color: _Palette.slate),
                children: [
                  TextSpan(
                    text: widget.elderId == null ? '目前狀態　' : '$_elderLabel 目前　',
                  ),
                  TextSpan(
                    text: detail,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: _busy ? null : _refreshStatus,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.refresh_rounded, size: 18, color: _Palette.mist),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 方案卡 ---------------------------------------------------------------

  Widget _buildPlanList() {
    if (_packages.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _Palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _Palette.line),
        ),
        child: Text(
          '目前抓不到任何方案。\n請確認 RevenueCat 後台已建立 default Offering，並包含月/季/年方案。',
          style: GoogleFonts.notoSansTc(
            color: _Palette.slate,
            fontSize: 13.5,
            height: 1.7,
          ),
        ),
      );
    }

    final best = _bestValuePackage(_packages);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '選擇計費週期',
          style: GoogleFonts.notoSansTc(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: _Palette.slate,
          ),
        ),
        const SizedBox(height: 14),
        for (int i = 0; i < _packages.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildPlanCard(
              _packages[i],
              isBestValue: best != null && _packages[i].identifier == best.identifier,
            ).animate(delay: (60 * i).ms).fadeIn(duration: 320.ms).slideY(
                  begin: 0.08,
                  curve: Curves.easeOut,
                ),
          ),
      ],
    );
  }

  Widget _buildPlanCard(Package pkg, {required bool isBestValue}) {
    final bool selected = _isSelected(pkg);
    final product = pkg.storeProduct;
    final saving = _savingPercent(pkg);
    final perMonth = _perMonthText(pkg);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : () => setState(() => _selected = pkg),
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: 160.ms,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            color: _Palette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? _Palette.accent : _Palette.line,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _Palette.accent.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildSelectDot(selected),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _planLabel(pkg),
                            style: GoogleFonts.notoSansTc(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _Palette.ink,
                            ),
                          ),
                        ),
                        if (isBestValue) ...[
                          const SizedBox(width: 8),
                          _buildBadge(saving == null ? '最划算' : '省 $saving%'),
                        ],
                      ],
                    ),
                    if (perMonth != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        perMonth,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 12.5,
                          color: _Palette.mist,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    product.priceString,
                    style: GoogleFonts.inter(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: _Palette.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (_periodSuffix(pkg).isNotEmpty)
                    Text(
                      _periodSuffix(pkg),
                      style: GoogleFonts.notoSansTc(
                        fontSize: 12,
                        color: _Palette.mist,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 自繪的選取圓點，比 Radio 更貼合卡片視覺。
  Widget _buildSelectDot(bool selected) {
    return AnimatedContainer(
      duration: 160.ms,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? _Palette.accent : Colors.transparent,
        border: Border.all(
          color: selected ? _Palette.accent : const Color(0xFFCBD5E1),
          width: 1.6,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _Palette.accentSoft.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: GoogleFonts.notoSansTc(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _Palette.accent,
        ),
      ),
    );
  }

  // ---- 特色清單 -------------------------------------------------------------

  Widget _buildFeatureCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '所有方案都包含',
            style: GoogleFonts.notoSansTc(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: _Palette.slate,
            ),
          ),
          const SizedBox(height: 18),
          for (final f in _features)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(Icons.check_rounded, size: 17, color: _Palette.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      f,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 14.5,
                        height: 1.55,
                        color: _Palette.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---- CTA -----------------------------------------------------------------

  Widget _buildCta() {
    final bool alreadyPro = _effectiveIsPro;
    final pkg = _selected;

    final String label;
    if (alreadyPro) {
      label = '進階照護已開通';
    } else if (pkg == null) {
      label = '請先選擇方案';
    } else {
      label = '為$_elderLabel開通 · ${pkg.storeProduct.priceString}';
    }

    return SizedBox(
      height: 56,
      child: FilledButton(
        onPressed: (_busy || pkg == null || alreadyPro) ? null : _purchaseSelected,
        style: FilledButton.styleFrom(
          backgroundColor: _Palette.ink,
          foregroundColor: Colors.white,
          disabledBackgroundColor: alreadyPro
              ? _Palette.success.withValues(alpha: 0.12)
              : const Color(0xFFE2E8F0),
          disabledForegroundColor:
              alreadyPro ? _Palette.success : _Palette.mist,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (alreadyPro) ...[
              const Icon(Icons.verified_rounded, size: 19),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestoreRow() {
    return Center(
      child: TextButton(
        onPressed: _busy ? null : _restorePurchases,
        style: TextButton.styleFrom(foregroundColor: _Palette.slate),
        child: Text(
          '已經買過了？恢復購買',
          style: GoogleFonts.notoSansTc(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: _Palette.mist,
          ),
        ),
      ),
    );
  }

  Widget _buildFinePrint() {
    return Text(
      '訂閱會自動續期，可隨時於 Google Play / App Store 取消。'
      '開通後由$_elderLabel的裝置自動解鎖進階功能，不需另外操作。\n'
      '目前為 RevenueCat Test Store 模擬環境，不會實際扣款。',
      textAlign: TextAlign.center,
      style: GoogleFonts.notoSansTc(
        fontSize: 11.5,
        height: 1.8,
        color: _Palette.mist,
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Palette.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFB91C1C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _loadError!,
              style: GoogleFonts.notoSansTc(
                color: const Color(0xFF991B1B),
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 開發者選項（除錯工具，預設收合）---------------------------------------

  Widget _buildDeveloperPanel() {
    return Container(
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Palette.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
          // ExpansionTile 的 children 預設置中，這裡全是標籤與說明文字，要靠左。
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: const Icon(Icons.tune_rounded, size: 18, color: _Palette.mist),
          iconColor: _Palette.mist,
          collapsedIconColor: _Palette.mist,
          title: Text(
            '開發者選項',
            style: GoogleFonts.notoSansTc(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: _Palette.slate,
            ),
          ),
          children: [
            _buildDevLabel(
              widget.elderId == null
                  ? '測試 User ID（未綁定長輩）'
                  : '綁定長輩：$_elderLabel',
            ),
            const SizedBox(height: 4),
            SelectableText(
              _appUserId,
              style: GoogleFonts.robotoMono(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _Palette.ink,
              ),
            ),
            const SizedBox(height: 16),
            _buildDevLabel('RevenueCat SDK 權限（僅供對照）'),
            const SizedBox(height: 4),
            Text(
              _isPro ? 'PRO（entitlement: $_entitlementId）' : 'FREE',
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _isPro ? _Palette.success : _Palette.slate,
              ),
            ),
            if (widget.elderId != null) ...[
              const SizedBox(height: 16),
              _buildDevLabel('後端訂閱狀態（長輩端依此解鎖）'),
              const SizedBox(height: 4),
              Text(
                _backendChecking
                    ? '查詢中…'
                    : _backendIsPro
                        ? 'PRO 已開通${_backendExpiresText == null ? '' : '（到期 $_backendExpiresText）'}'
                        : '尚未開通',
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _backendIsPro ? _Palette.success : _Palette.slate,
                ),
              ),
            ],
            const SizedBox(height: 18),
            _buildDevLabel('切換測試 User'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _userIdController,
                    enabled: !_busy,
                    style: GoogleFonts.robotoMono(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '例如 dev_test_user_001',
                      hintStyle: GoogleFonts.notoSansTc(
                        color: _Palette.mist,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: _Palette.canvas,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _Palette.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _Palette.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _Palette.accent),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _busy ? null : _switchUser,
                  style: FilledButton.styleFrom(
                    backgroundColor: _Palette.canvas,
                    foregroundColor: _Palette.ink,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: _Palette.line),
                    ),
                  ),
                  child: Text(
                    '切換',
                    style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _refreshStatus,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _Palette.slate,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: const BorderSide(color: _Palette.line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  '重新整理狀態',
                  style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            // 重設鈕只在 debug build 出現：kDebugMode 是編譯期常數，
            // release 版整段會被 tree-shake 掉，不會流到使用者手上。
            if (kDebugMode && widget.elderId != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _devResetToFree,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _Palette.danger,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: BorderSide(color: _Palette.danger.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.lock_reset_rounded, size: 18),
                  label: Text(
                    '重設為未訂閱（測試用）',
                    style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '送一則 EXPIRATION 到後端，把這位長輩翻回未開通，方便重測 FREE 畫面。'
                '不會真的取消商店訂閱——真正的取消要使用者自己到 Google Play / App Store 操作。',
                style: GoogleFonts.notoSansTc(
                  fontSize: 11.5,
                  height: 1.6,
                  color: _Palette.mist,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDevLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.notoSansTc(fontSize: 12, color: _Palette.mist),
    );
  }
}
