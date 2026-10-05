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
//   採「官網 Pricing 頁」骨架：
//     Hero 標題 → 目前狀態列 → 月/季/年方案卡（自算每月均價與省下 %）
//     → 「所有方案都包含」特色清單 → CTA → 小字條款 → 開發者選項（收合）
//   除錯用的 App User ID、切換測試 User、後端狀態對照，全部收進最下方
//   ExpansionTile「開發者選項」，正式使用者不會第一眼看到。
//   ⚠️ 特色清單目前是 UI 文案，尚未對應真正被鎖住的功能
//      （見 docs/technical/SUBSCRIPTION_ARCHITECTURE.md ❽「功能鎖尚未接上」）。
//
// ★ 2026-10 外觀改版：換成家屬端新設計系統（海灣藍 ocean，見 theme/family_theme.dart
//   與 theme/app_theme.dart 的 UbanColors.familyLight/familyDark）。本輪**純 UI 換皮**：
//   所有 RevenueCat 邏輯、callback、Navigator、API、SharedPreferences、免費試用揭露
//   文字與邏輯皆與改版前相同，只換顏色／版面／元件外觀。
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
import '../../theme/app_theme.dart';
import '../../theme/family_theme.dart';
import 'widgets/fam_data_ui.dart';
import 'widgets/fam_interaction_ui.dart';
import 'widgets/fam_ui.dart';

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

  // 家屬主題之下的 context（State 自己的 context 在 FamilyThemeScope 之上）：
  // 取色與開 dialog／SnackBar 都用它，才吃得到家屬色票；每次 build 更新。
  BuildContext? _themed;
  BuildContext get _themeCtx => _themed ?? context;
  UbanColors get _c => UbanColors.of(_themeCtx);

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

    final confirmed = await showFamDialog<bool>(
      _themeCtx,
      (dialogContext) {
        final dc = UbanColors.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            famDialogTitle(dc, '重設為未訂閱？'),
            const SizedBox(height: 10),
            Text(
              '會對後端補送一則 EXPIRATION 事件，把 $_elderLabel（elder_$elderId）的訂閱狀態'
              '翻成未開通。\n\n'
              '這是寫進正式資料庫的操作，不是只改本機畫面；也不會真的取消商店那邊的訂閱。',
              style: famText(dc.text2, 14, height: 1.7),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: FamButton(
                    label: '取消',
                    kind: FamButtonKind.ghost,
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FamButton(
                    label: '確定重設',
                    kind: FamButtonKind.danger,
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                  ),
                ),
              ],
            ),
          ],
        );
      },
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
      ..showSnackBar(famSnackBar(_themeCtx, msg));
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

  // ---- 免費試用 / 優惠期揭露 ------------------------------------------------
  //
  // Apple 與 Google 都要求「購買前」就明確揭露試用期長度與試用結束後的價格，
  // 沒揭露會被退件。資料有兩個來源，取決於平台：
  //
  //   Google Play：`StoreProduct.defaultOption` 的 pricing phases
  //                （`freePhase` = 金額 0 的那段、`introPhase` = 折扣價那段）
  //   App Store  ：`StoreProduct.introductoryPrice`
  //                （`price == 0` 代表免費試用，> 0 代表優惠價）
  //
  // 兩邊擇一有值即可；都沒有就完全不顯示，不要憑空生出「無試用」的字樣。

  /// `PeriodUnit` → 中文量詞。抓不到就回空字串，讓呼叫端整段放棄顯示。
  String _unitText(PeriodUnit unit) {
    switch (unit) {
      case PeriodUnit.day:
        return '天';
      case PeriodUnit.week:
        return '週';
      case PeriodUnit.month:
        return '個月';
      case PeriodUnit.year:
        return '年';
      case PeriodUnit.unknown:
        return '';
    }
  }

  /// `Period`（Google Play）→「1 週」。單位不明時回 null。
  String? _periodText(Period period) {
    final unit = _unitText(period.unit);
    if (unit.isEmpty || period.value <= 0) return null;
    return '${period.value} $unit';
  }

  /// 免費試用長度，例如「1 週」；沒有試用就回 null。
  String? _freeTrialText(Package pkg) {
    final product = pkg.storeProduct;

    // Google Play：金額 0 的 pricing phase。
    final freePhase = product.defaultOption?.freePhase;
    final freePeriod = freePhase?.billingPeriod;
    if (freePeriod != null) {
      final text = _periodText(freePeriod);
      if (text != null) return text;
    }

    // App Store：introductoryPrice 且金額為 0。
    final intro = product.introductoryPrice;
    if (intro != null && intro.price <= 0) {
      final unit = _unitText(intro.periodUnit);
      // cycles 是「以此價格計費幾期」，單位相同故可直接相乘。
      final cycles = intro.cycles <= 0 ? 1 : intro.cycles;
      final total = intro.periodNumberOfUnits * cycles;
      if (unit.isNotEmpty && total > 0) return '$total $unit';
    }
    return null;
  }

  /// 優惠價期間，例如「首 3 個月 NT$99」；沒有優惠價就回 null。
  String? _introOfferText(Package pkg) {
    final product = pkg.storeProduct;

    // Google Play：金額 > 0 的 introPhase。
    final introPhase = product.defaultOption?.introPhase;
    if (introPhase != null) {
      final period = introPhase.billingPeriod;
      final periodText = period == null ? null : _periodText(period);
      final cycles = introPhase.billingCycleCount ?? 1;
      if (periodText != null) {
        final span = cycles > 1 ? '$periodText × $cycles 期' : periodText;
        return '首 $span ${introPhase.price.formatted}';
      }
    }

    // App Store：introductoryPrice 且金額 > 0。
    final intro = product.introductoryPrice;
    if (intro != null && intro.price > 0) {
      final unit = _unitText(intro.periodUnit);
      final cycles = intro.cycles <= 0 ? 1 : intro.cycles;
      final total = intro.periodNumberOfUnits * cycles;
      if (unit.isNotEmpty && total > 0) {
        return '首 $total $unit ${intro.priceString}';
      }
    }
    return null;
  }

  /// 方案卡上的短標籤，例如「免費試用 1 週」。沒有優惠就回 null。
  String? _offerBadgeText(Package pkg) {
    final free = _freeTrialText(pkg);
    if (free != null) return '免費試用 $free';
    final intro = _introOfferText(pkg);
    if (intro != null) return intro;
    return null;
  }

  /// CTA 上方的完整揭露句：試用多久、結束後多少錢、怎麼取消。
  /// 這是 Apple／Google 審核要看的那一句，沒有優惠期時回 null（整塊不顯示）。
  String? _offerDisclosure(Package pkg) {
    final free = _freeTrialText(pkg);
    final intro = _introOfferText(pkg);
    if (free == null && intro == null) return null;

    final after = '${pkg.storeProduct.priceString}${_periodSuffix(pkg)}';
    final head = [
      if (free != null) '免費試用 $free',
      if (intro != null) intro,
    ].join('，接著 ');

    return '$head，之後自動以 $after 續訂。'
        '可在到期前隨時於 Google Play / App Store 取消，取消後不會扣款。';
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
  // UI（2026-10 起外觀改家屬新設計，海灣藍 ocean；僅換視覺，邏輯與改版前相同）
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    // push 出去的家屬頁不在主殼的 Theme 之下，需在 build 最外層包一層。
    return FamilyThemeScope(
      child: Builder(builder: _buildScreen),
    );
  }

  Widget _buildScreen(BuildContext context) {
    _themed = context;
    final c = _c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: famSubBar(context, title: '訂閱方案'),
      body: Stack(
        children: [
          if (_initialLoading)
            Center(child: CircularProgressIndicator(color: c.brandFill))
          else
            _buildContent(),
          if (_busy) _buildBusyOverlay(),
        ],
      ),
    );
  }

  Widget _buildBusyOverlay() {
    final c = _c;
    return Container(
      color: c.scrim,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: c.shadows.glass,
          ),
          child: CircularProgressIndicator(color: c.brandFill),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loadError != null) ...[
            _buildErrorBanner(),
            const SizedBox(height: 16),
          ],
          _buildHero(),
          const SizedBox(height: 20),
          _buildStatusStrip(),
          const SizedBox(height: 24),
          _buildPlanList(),
          const SizedBox(height: 20),
          _buildFeatureCard(),
          const SizedBox(height: 24),
          _buildOfferDisclosure(),
          _buildCta(),
          const SizedBox(height: 12),
          _buildRestoreRow(),
          const SizedBox(height: 20),
          _buildFinePrint(),
          const SizedBox(height: 28),
          _buildDeveloperPanel(),
        ],
      ),
    );
  }

  // ---- Hero（對應 design_prototype `.prohero`）-------------------------------

  Widget _buildHero() {
    final c = _c;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.brandContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FamChip(label: 'PRO', tone: FamTone.warm),
          const SizedBox(height: 12),
          Text(
            '幫$_elderLabel升級，多一份安心',
            style: famText(c.brandStrong, 24, weight: FontWeight.w900, height: 1.3),
          ),
          const SizedBox(height: 8),
          Text(
            '不限次數的 AI 陪聊、每月深度洞察報告，以及長久保存的回憶錄備份。'
            '選一個適合的計費週期即可，隨時能取消。',
            style: famText(c.text2, 14.5, height: 1.6),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 380.ms).slideY(begin: 0.06, curve: Curves.easeOut);
  }

  // ---- 目前狀態列 ------------------------------------------------------------

  Widget _buildStatusStrip() {
    final c = _c;
    final bool pro = _effectiveIsPro;
    final FamTone tone = pro ? FamTone.brand : FamTone.neutral;
    final Color fg = famToneFg(c, tone);

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

    return FamCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          FamDot(color: fg, size: 8),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: famText(c.text2, 13.5),
                children: [
                  TextSpan(
                    text: widget.elderId == null ? '目前狀態　' : '$_elderLabel 目前　',
                  ),
                  TextSpan(
                    text: detail,
                    style: famText(fg, 13.5, weight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          FamIconButton(
            icon: Icons.refresh_rounded,
            tooltip: '重新整理狀態',
            onTap: _busy ? null : _refreshStatus,
          ),
        ],
      ),
    );
  }

  // ---- 方案卡 ---------------------------------------------------------------

  Widget _buildPlanList() {
    final c = _c;
    if (_packages.isEmpty) {
      return FamNote(
        text: '目前抓不到任何方案。\n請確認 RevenueCat 後台已建立 default Offering，並包含月/季/年方案。',
      );
    }

    final best = _bestValuePackage(_packages);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '選擇計費週期',
          style: famText(c.text3, 13, weight: FontWeight.w700, letterSpacing: 1.2),
        ),
        const SizedBox(height: 12),
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
    final c = _c;
    final bool selected = _isSelected(pkg);
    final product = pkg.storeProduct;
    final saving = _savingPercent(pkg);
    final perMonth = _perMonthText(pkg);
    final offerBadge = _offerBadgeText(pkg);
    final br = BorderRadius.circular(24);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : () => setState(() => _selected = pkg),
        borderRadius: br,
        child: AnimatedContainer(
          duration: 160.ms,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: br,
            boxShadow: c.shadows.card,
            border: Border.all(
              color: selected ? c.brand : Colors.transparent,
              width: 2,
            ),
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: famText(c.text, 16, weight: FontWeight.w900),
                          ),
                        ),
                        if (isBestValue) ...[
                          const SizedBox(width: 8),
                          FamChip(
                            label: saving == null ? '最划算' : '省 $saving%',
                            tone: FamTone.brand,
                          ),
                        ],
                      ],
                    ),
                    if (perMonth != null) ...[
                      const SizedBox(height: 4),
                      Text(perMonth, style: famText(c.text3, 12.5)),
                    ],
                    if (offerBadge != null) ...[
                      const SizedBox(height: 6),
                      FamChip(label: offerBadge, tone: FamTone.warm, dot: true),
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
                    style: famText(c.text, 19, weight: FontWeight.w900, tabular: true),
                  ),
                  if (_periodSuffix(pkg).isNotEmpty)
                    Text(
                      _periodSuffix(pkg),
                      style: famText(c.text3, 12),
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
    final c = _c;
    return AnimatedContainer(
      duration: 160.ms,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? c.brandFill : Colors.transparent,
        border: Border.all(
          color: selected ? c.brandFill : c.line,
          width: 1.6,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 14, color: c.onBrand)
          : null,
    );
  }

  // ---- 特色清單 -------------------------------------------------------------

  Widget _buildFeatureCard() {
    final c = _c;
    return FamCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '所有方案都包含',
            style: famText(c.text3, 13, weight: FontWeight.w700, letterSpacing: 1.2),
          ),
          const SizedBox(height: 16),
          for (final f in _features)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_rounded, size: 17, color: c.brandStrong),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      f,
                      style: famText(c.text, 14.5, height: 1.55),
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

  /// 購買前的試用／優惠揭露。Apple 與 Google 都要求在購買按鈕**之前**
  /// 說明試用期長度與試用後價格，否則審核會被退件。
  /// 已經是 PRO 或選取的方案沒有優惠期時整塊不顯示（不佔版面）。
  Widget _buildOfferDisclosure() {
    final pkg = _selected;
    if (pkg == null || _effectiveIsPro) return const SizedBox.shrink();
    final text = _offerDisclosure(pkg);
    if (text == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FamNote(text: text, tone: FamTone.warm),
    );
  }

  Widget _buildCta() {
    final bool alreadyPro = _effectiveIsPro;
    final pkg = _selected;

    final String label;
    if (alreadyPro) {
      label = '進階照護已開通';
    } else if (pkg == null) {
      label = '請先選擇方案';
    } else {
      // 有免費試用時，按鈕不能只寫價格——那會讓人以為當下就要付這筆錢。
      final free = _freeTrialText(pkg);
      label = free != null
          ? '開始免費試用 $free'
          : '為$_elderLabel開通 · ${pkg.storeProduct.priceString}';
    }

    return FamButton(
      label: label,
      height: 56,
      kind: alreadyPro ? FamButtonKind.tonal : FamButtonKind.filled,
      onPressed: (_busy || pkg == null || alreadyPro) ? null : _purchaseSelected,
    );
  }

  Widget _buildRestoreRow() {
    final c = _c;
    return Center(
      child: TextButton(
        onPressed: _busy ? null : _restorePurchases,
        style: TextButton.styleFrom(foregroundColor: c.text2),
        child: Text(
          '已經買過了？恢復購買',
          style: famText(c.text2, 13.5, weight: FontWeight.w600).copyWith(
            decoration: TextDecoration.underline,
            decorationColor: c.text3,
          ),
        ),
      ),
    );
  }

  Widget _buildFinePrint() {
    final c = _c;
    final pkg = _selected;
    final free = pkg == null ? null : _freeTrialText(pkg);

    return Text(
      '訂閱會自動續期，可隨時於 Google Play / App Store 取消。'
      '${free != null ? '免費試用期結束前取消不會被扣款；未取消則自動轉為付費訂閱。' : ''}'
      '開通後由$_elderLabel的裝置自動解鎖進階功能，不需另外操作。\n'
      '目前為 RevenueCat Test Store 模擬環境，不會實際扣款。',
      textAlign: TextAlign.center,
      style: famText(c.text3, 11.5, height: 1.8),
    );
  }

  Widget _buildErrorBanner() {
    return FamNote(text: _loadError!, tone: FamTone.danger);
  }

  // ---- 開發者選項（除錯工具，預設收合）---------------------------------------

  Widget _buildDeveloperPanel() {
    final c = _c;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: c.shadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
          // ExpansionTile 的 children 預設置中，這裡全是標籤與說明文字，要靠左。
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: Icon(Icons.tune_rounded, size: 18, color: c.text3),
          iconColor: c.text3,
          collapsedIconColor: c.text3,
          title: Text(
            '開發者選項',
            style: famText(c.text2, 13.5, weight: FontWeight.w700),
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
                color: c.text,
              ),
            ),
            const SizedBox(height: 16),
            _buildDevLabel('RevenueCat SDK 權限（僅供對照）'),
            const SizedBox(height: 4),
            Text(
              _isPro ? 'PRO（entitlement: $_entitlementId）' : 'FREE',
              style: famText(_isPro ? c.brandStrong : c.text2, 14, weight: FontWeight.w700),
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
                style: famText(
                  _backendIsPro ? c.brandStrong : c.text2,
                  14,
                  weight: FontWeight.w700,
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
                      hintStyle: famText(c.text3, 13),
                      filled: true,
                      fillColor: c.surface2,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: c.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: c.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: c.brandFill),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FamButton(
                  label: '切換',
                  kind: FamButtonKind.outline,
                  expand: false,
                  height: 46,
                  onPressed: _busy ? null : _switchUser,
                ),
              ],
            ),
            const SizedBox(height: 12),
            FamButton(
              label: '重新整理狀態',
              kind: FamButtonKind.outline,
              height: 46,
              onPressed: _busy ? null : _refreshStatus,
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
                    foregroundColor: c.danger,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: BorderSide(color: c.danger.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  icon: const Icon(Icons.lock_reset_rounded, size: 18),
                  label: Text(
                    '重設為未訂閱（測試用）',
                    style: famText(c.danger, 15, weight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '送一則 EXPIRATION 到後端，把這位長輩翻回未開通，方便重測 FREE 畫面。'
                '不會真的取消商店訂閱——真正的取消要使用者自己到 Google Play / App Store 操作。',
                style: famText(c.text3, 11.5, height: 1.6),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDevLabel(String text) {
    final c = _c;
    return Text(text, style: famText(c.text3, 12));
  }
}
