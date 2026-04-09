import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/utils/app_logger.dart';

/// ⚡ 性能優化工具
class PerformanceOptimizer {
  /// 防抖動 (Debounce)
  /// 用於搜尋輸入等場景，避免頻繁觸發
  static Function debounce(
    Function func, {
    Duration delay = const Duration(milliseconds: 300),
  }) {
    Timer? timer;
    
    return () {
      timer?.cancel();
      timer = Timer(delay, () => func());
    };
  }

  /// 節流 (Throttle)
  /// 限制函數執行頻率
  static Function throttle(
    Function func, {
    Duration duration = const Duration(milliseconds: 300),
  }) {
    bool isThrottled = false;
    
    return () {
      if (isThrottled) return;
      
      isThrottled = true;
      func();
      
      Timer(duration, () {
        isThrottled = false;
      });
    };
  }

  /// 批量處理
  /// 將大量數據分批處理，避免阻塞 UI
  static Future<List<T>> batchProcess<T>(
    List<T> items,
    Future<T> Function(T) processor, {
    int batchSize = 10,
    Duration batchDelay = const Duration(milliseconds: 10),
  }) async {
    final results = <T>[];
    
    for (var i = 0; i < items.length; i += batchSize) {
      final end = (i + batchSize < items.length) ? i + batchSize : items.length;
      final batch = items.sublist(i, end);
      
      final batchResults = await Future.wait(
        batch.map((item) => processor(item)),
      );
      
      results.addAll(batchResults);
      
      // 給 UI 線程喘息的機會
      if (i + batchSize < items.length) {
        await Future.delayed(batchDelay);
      }
    }
    
    return results;
  }

  /// 延遲加載
  /// 用於大列表的分頁加載
  static Future<List<T>> lazyLoad<T>(
    Future<List<T>> Function(int page, int pageSize) loader, {
    int initialPage = 0,
    int pageSize = 20,
  }) async {
    return await loader(initialPage, pageSize);
  }

  /// 圖片優化 - 計算適當的緩存尺寸
  static Size calculateImageCacheSize(
    Size displaySize, {
    double devicePixelRatio = 1.0,
  }) {
    return Size(
      displaySize.width * devicePixelRatio,
      displaySize.height * devicePixelRatio,
    );
  }

  /// 記憶化 (Memoization)
  /// 緩存函數結果，避免重複計算
  static T Function(A) memoize<A, T>(T Function(A) func) {
    final cache = <A, T>{};
    
    return (A arg) {
      if (cache.containsKey(arg)) {
        return cache[arg]!;
      }
      
      final result = func(arg);
      cache[arg] = result;
      return result;
    };
  }

  /// 計算列表虛擬化參數
  static ({int firstVisibleIndex, int lastVisibleIndex}) calculateVisibleRange({
    required double scrollOffset,
    required double viewportHeight,
    required double itemHeight,
    required int totalItems,
    int bufferItems = 5,
  }) {
    final firstVisible = (scrollOffset / itemHeight).floor() - bufferItems;
    final lastVisible = ((scrollOffset + viewportHeight) / itemHeight).ceil() + bufferItems;
    
    return (
      firstVisibleIndex: firstVisible.clamp(0, totalItems - 1),
      lastVisibleIndex: lastVisible.clamp(0, totalItems - 1),
    );
  }
}



/// 性能監控工具
class PerformanceMonitor {
  static final Map<String, Stopwatch> _stopwatches = {};
  static final Map<String, List<int>> _metrics = {};

  /// 開始計時
  static void startTimer(String key) {
    _stopwatches[key] = Stopwatch()..start();
  }

  /// 停止計時並記錄
  static void stopTimer(String key) {
    final stopwatch = _stopwatches[key];
    if (stopwatch == null) return;
    
    stopwatch.stop();
    final elapsed = stopwatch.elapsedMilliseconds;
    
    _metrics[key] ??= [];
    _metrics[key]!.add(elapsed);
    
    if (kDebugMode) {
      appLogger.d('⏱️ $key: ${elapsed}ms');
    }
  }

  /// 獲取指標統計
  static Map<String, dynamic>? getMetrics(String key) {
    final values = _metrics[key];
    if (values == null || values.isEmpty) return null;
    
    final avg = values.reduce((a, b) => a + b) / values.length;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    
    return {
      'average': avg,
      'min': min,
      'max': max,
      'count': values.length,
    };
  }

  /// 清除指標
  static void clearMetrics([String? key]) {
    if (key != null) {
      _metrics.remove(key);
      _stopwatches.remove(key);
    } else {
      _metrics.clear();
      _stopwatches.clear();
    }
  }

  /// 打印所有指標
  static void printAllMetrics() {
    if (!kDebugMode) return;
    
    appLogger.d('\n📊 Performance Metrics:');
    _metrics.forEach((key, values) {
      final stats = getMetrics(key);
      if (stats != null) {
        appLogger.d('  $key:');
        appLogger.d('    Average: ${stats['average'].toStringAsFixed(2)}ms');
        appLogger.d('    Min: ${stats['min']}ms');
        appLogger.d('    Max: ${stats['max']}ms');
        appLogger.d('    Count: ${stats['count']}');
      }
    });
    appLogger.d('');
  }
}

/// 內存優化工具
class MemoryOptimizer {
  /// 清理圖片緩存
  static void clearImageCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  /// 設置圖片緩存大小
  static void setImageCacheSize({
    int maxCache = 100,
    int maxCacheBytes = 50 << 20, // 50 MB
  }) {
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSize = maxCache;
    imageCache.maximumSizeBytes = maxCacheBytes;
  }

  /// 獲取當前內存使用情況
  static Map<String, dynamic> getMemoryInfo() {
    final imageCache = PaintingBinding.instance.imageCache;
    
    return {
      'currentSize': imageCache.currentSize,
      'currentSizeBytes': imageCache.currentSizeBytes,
      'maximumSize': imageCache.maximumSize,
      'maximumSizeBytes': imageCache.maximumSizeBytes,
      'liveImageCount': imageCache.liveImageCount,
      'pendingImageCount': imageCache.pendingImageCount,
    };
  }
}

/// Widget 優化工具
class WidgetOptimizer {
  /// 創建 const Widget（提醒開發者使用 const）
  static const placeholder = const SizedBox.shrink();

  /// 是否應該重建 Widget
  static bool shouldRebuild<T>(T oldValue, T newValue) {
    return oldValue != newValue;
  }

  /// 批量更新狀態
  static void batchedUpdate(Function updates) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      updates();
    });
  }
}

/// 數據緩存管理
class CacheManager<K, V> {
  final Map<K, _CacheEntry<V>> _cache = {};
  final Duration _ttl;
  final int _maxSize;

  CacheManager({
    Duration ttl = const Duration(minutes: 5),
    int maxSize = 100,
  }) : _ttl = ttl, _maxSize = maxSize;

  /// 獲取緩存
  V? get(K key) {
    final entry = _cache[key];
    
    if (entry == null) return null;
    
    // 檢查是否過期
    if (DateTime.now().difference(entry.timestamp) > _ttl) {
      _cache.remove(key);
      return null;
    }
    
    return entry.value;
  }

  /// 設置緩存
  void set(K key, V value) {
    // 如果超過最大大小，移除最舊的
    if (_cache.length >= _maxSize) {
      final oldestKey = _cache.entries
        .reduce((a, b) => a.value.timestamp.isBefore(b.value.timestamp) ? a : b)
        .key;
      _cache.remove(oldestKey);
    }
    
    _cache[key] = _CacheEntry(value, DateTime.now());
  }

  /// 清除緩存
  void clear() {
    _cache.clear();
  }

  /// 清除過期緩存
  void clearExpired() {
    final now = DateTime.now();
    _cache.removeWhere((key, entry) => 
      now.difference(entry.timestamp) > _ttl
    );
  }

  /// 獲取緩存大小
  int get size => _cache.length;
}

class _CacheEntry<V> {
  final V value;
  final DateTime timestamp;

  _CacheEntry(this.value, this.timestamp);
}
