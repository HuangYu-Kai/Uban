// ============================================================================
// SubscriptionService — 訂閱（PRO 進階照護）狀態查詢
// ----------------------------------------------------------------------------
// 設計文件：Uban/docs/technical/SUBSCRIPTION_ARCHITECTURE.md
//
// 後端為單一真相來源：RevenueCat 用 Webhook 把訂閱狀態推到 subscription_status，
// App 一律查 GET /api/subscription/{elder_id} 判斷 PRO，不看 SDK 本地快取
// （因為家屬買、長輩用，跨帳號跨裝置，SDK 快取在長輩那台根本不存在）。
//
// ⚠️ 本檔刻意「不」import purchases_flutter：
//    長輩端只需要讀狀態當功能鎖，不需要購買 SDK。
//    購買流程（Purchases.logIn / purchasePackage）留在家屬端的訂閱頁。
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/utils/app_logger.dart';

import 'api_service.dart';

/// 某位長輩目前的訂閱狀態快照。
class SubscriptionStatus {
  final String elderId;
  final bool isPro;
  final String? entitlement;
  final String? productId;
  final DateTime? expiresAt;

  const SubscriptionStatus({
    required this.elderId,
    required this.isPro,
    this.entitlement,
    this.productId,
    this.expiresAt,
  });

  /// 查不到 / 查詢失敗時的保底值：一律視為未訂閱。
  factory SubscriptionStatus.free(String elderId) =>
      SubscriptionStatus(elderId: elderId, isPro: false);

  factory SubscriptionStatus.fromJson(String elderId, Map<String, dynamic> data) {
    final rawExpires = data['expires_at'];
    return SubscriptionStatus(
      elderId: data['elder_id']?.toString() ?? elderId,
      isPro: data['is_pro'] == true,
      entitlement: data['entitlement']?.toString(),
      productId: data['product_id']?.toString(),
      expiresAt: rawExpires is String ? DateTime.tryParse(rawExpires) : null,
    );
  }

  @override
  String toString() =>
      'SubscriptionStatus(elder=$elderId, isPro=$isPro, '
      'entitlement=$entitlement, expiresAt=$expiresAt)';
}

class SubscriptionService {
  SubscriptionService._();

  static const Duration _timeout = Duration(seconds: 10);

  /// 短快取：功能鎖可能在同一頁被問很多次，避免每個 widget 都打一次 API。
  /// 剛購買完請用 forceRefresh，繞過快取。
  static const Duration _cacheTtl = Duration(seconds: 60);
  static final Map<String, _CacheEntry> _cache = {};

  /// RevenueCat 的 App User ID 格式，必須與後端 `_parse_elder_id` 一致。
  /// 家屬購買前呼叫 `Purchases.logIn(SubscriptionService.appUserIdFor(elderId))`，
  /// 訂閱才會掛在長輩身上，webhook 才解析得出 elder_id。
  static String appUserIdFor(String elderId) => 'elder_$elderId';

  /// 查詢某長輩的訂閱狀態。網路失敗一律回傳未訂閱（不擋 App 正常運作）。
  static Future<SubscriptionStatus> fetchStatus(
    String elderId, {
    bool forceRefresh = false,
  }) async {
    if (elderId.isEmpty) return SubscriptionStatus.free(elderId);

    if (!forceRefresh) {
      final cached = _cache[elderId];
      if (cached != null && !cached.isStale) return cached.status;
    }

    try {
      final response = await http
          .get(Uri.parse('${ApiService.baseUrl}/subscription/$elderId'))
          .timeout(_timeout);

      final Map<String, dynamic> body = jsonDecode(response.body);
      final data = body['data'];
      if (body['status'] != 'success' || data is! Map<String, dynamic>) {
        appLogger.w('⚠️ 訂閱狀態查詢回傳異常 (elder=$elderId): ${response.body}');
        return SubscriptionStatus.free(elderId);
      }

      final status = SubscriptionStatus.fromJson(elderId, data);
      _cache[elderId] = _CacheEntry(status);
      appLogger.d('💳 訂閱狀態：$status');
      return status;
    } on TimeoutException {
      appLogger.w('⚠️ 訂閱狀態查詢逾時 (elder=$elderId)');
      return SubscriptionStatus.free(elderId);
    } catch (e) {
      appLogger.w('⚠️ 訂閱狀態查詢失敗 (elder=$elderId): $e');
      return SubscriptionStatus.free(elderId);
    }
  }

  /// 只要一個 bool 的簡便版（功能鎖用）。
  static Future<bool> isPro(String elderId, {bool forceRefresh = false}) async {
    final status = await fetchStatus(elderId, forceRefresh: forceRefresh);
    return status.isPro;
  }

  /// 清除快取。購買完成 / 切換長輩 / 登出時呼叫。
  static void invalidate([String? elderId]) {
    if (elderId == null) {
      _cache.clear();
    } else {
      _cache.remove(elderId);
    }
  }
}

class _CacheEntry {
  final SubscriptionStatus status;
  final DateTime fetchedAt;

  _CacheEntry(this.status) : fetchedAt = DateTime.now();

  bool get isStale =>
      DateTime.now().difference(fetchedAt) > SubscriptionService._cacheTtl;
}
