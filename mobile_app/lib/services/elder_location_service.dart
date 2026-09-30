// lib/services/elder_location_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'friend_service.dart';
import 'database_helper.dart';
import 'api/location_api.dart';

/// 長輩端「App 常駐前景服務」GPS 回報。
///
/// 與 `elder_profile_tab.dart` 裡那條為了融合計步器、算寵物成長用的
/// `Geolocator.getPositionStream()` 是**兩條獨立的串流**：那條是精細取樣
/// （2 公尺／1 秒）、Kalman 濾波、純本機用途；這條是較粗取樣（30 公尺／
/// 60 秒），專門把座標回報給後端供家屬端畫「每日移動軌跡」。兩者取樣目的
/// 不同，刻意不共用，避免把已上線調校過的步數邏輯牽扯進來。
///
/// 生命週期由 `elder_home_screen.dart`（長輩整個 session 只建立一次的畫面，
/// 不是會被 `IndexedStack` 保活的分頁）的 `initState`/`dispose` 控制，
/// 而不是綁定某一個特定分頁——這樣家屬才能看到長輩「整天」的軌跡，不會
/// 因為長輩沒開特定畫面而斷點。
///
/// 分享開關（`elder_profile.location_sharing_enabled`，系統預設開啟，僅長輩
/// 本人可關閉）是唯一
/// 決定家屬看不看得到資料的防線，且伺服器端讀取端也會再檢查一次
/// （defense-in-depth，見 `Uban-api/routers/location.py`）；這裡的開關只
/// 負責「長輩要不要讓裝置持續耗電回報」。
class ElderLocationService {
  ElderLocationService._internal();
  static final ElderLocationService instance = ElderLocationService._internal();

  static const double _maxAccuracyMeters = 50.0;
  static const double _maxReasonableJumpMeters = 300.0;
  static const int _distanceFilterMeters = 30;
  static const Duration _reportInterval = Duration(seconds: 60);
  static const int _maxQueueFlushBatch = 50;

  int? _userId;
  String? _elderId;
  StreamSubscription<Position>? _positionStream;
  Position? _lastAccepted;
  bool _isRunning = false;
  bool _isFlushingQueue = false;

  bool get isRunning => _isRunning;

  /// 供 `ElderHomeScreen.initState` 呼叫：讀取後端分享開關狀態，開啟時才
  /// 啟動背景串流；關閉時什麼都不做（不會憑空索取定位權限）。
  Future<void> startIfEnabled({required int userId}) async {
    if (_isRunning) return;
    _userId = userId;
    final elderId = await FriendService.resolveMyElderId(userId);
    if (elderId == null) return;
    _elderId = elderId;

    final enabled = await LocationApi.getSharingEnabled(elderId: elderId, userId: userId);
    if (enabled == true) {
      await _start();
    }
  }

  /// 供長輩端「我的」分頁的開關 UI 呼叫：切換分享狀態（含呼叫後端 PUT）。
  /// 回傳是否切換成功；失敗時 UI 應維持切換前的狀態，不要樂觀更新。
  Future<bool> setSharingEnabled(bool enabled) async {
    final userId = _userId;
    if (userId == null) return false;
    final elderId = _elderId ?? await FriendService.resolveMyElderId(userId);
    if (elderId == null) return false;
    _elderId = elderId;

    final ok = await LocationApi.setSharingEnabled(
      elderId: elderId,
      userId: userId,
      enabled: enabled,
    );
    if (!ok) return false;

    if (enabled) {
      await _start();
    } else {
      await stop();
    }
    return true;
  }

  Future<void> _start() async {
    if (_isRunning || _elderId == null) return;
    final granted = await _requestPermission();
    if (!granted) return;

    _isRunning = true;
    _positionStream = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(),
    ).listen(_onPosition, onError: (Object _) {});
  }

  /// 供 `ElderHomeScreen.dispose` 呼叫，以及切換開關關閉時使用。
  Future<void> stop() async {
    _isRunning = false;
    await _positionStream?.cancel();
    _positionStream = null;
    _lastAccepted = null;
  }

  Future<bool> _requestPermission() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.whileInUse) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
  }

  LocationSettings _buildLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilterMeters,
        intervalDuration: _reportInterval,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Uban 位置分享中',
          notificationText: '正在與家人分享您的位置',
          enableWakeLock: true,
        ),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilterMeters,
        activityType: ActivityType.other,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }

    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _distanceFilterMeters,
    );
  }

  void _onPosition(Position pos) {
    if (pos.accuracy <= 0 || pos.accuracy > _maxAccuracyMeters) return;

    final last = _lastAccepted;
    if (last != null) {
      final jumpMeters = Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        pos.latitude,
        pos.longitude,
      );
      final elapsed = pos.timestamp.difference(last.timestamp);
      if (jumpMeters > _maxReasonableJumpMeters && elapsed < const Duration(seconds: 10)) {
        // 短時間內的不合理跳躍（GPS 漂移／訊號反彈），丟棄不回報。
        return;
      }
    }
    _lastAccepted = pos;
    unawaited(_sendOrQueue(pos));
  }

  Future<void> _sendOrQueue(Position pos) async {
    final elderId = _elderId;
    final userId = _userId;
    if (elderId == null || userId == null) return;

    // 每次有新點位時，先嘗試把離線期間積壓的舊點依序補送，避免斷線期間
    // 的軌跡整段消失（新點仍照常送出，不因補送而延遲）。
    unawaited(_flushQueue(elderId: elderId, userId: userId));

    final ok = await LocationApi.sendPing(
      elderId: elderId,
      userId: userId,
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracyM: pos.accuracy,
      recordedAt: pos.timestamp,
    );
    if (!ok) {
      await DatabaseHelper.instance.insert('location_points', {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy_m': pos.accuracy,
        'recorded_at': pos.timestamp.toUtc().toIso8601String(),
        'synced': 0,
      });
    }
  }

  Future<void> _flushQueue({required String elderId, required int userId}) async {
    if (_isFlushingQueue) return;
    _isFlushingQueue = true;
    try {
      final pending = await DatabaseHelper.instance.query(
        'location_points',
        where: 'synced = 0',
        orderBy: 'recorded_at ASC',
        limit: _maxQueueFlushBatch,
      );
      for (final row in pending) {
        final ok = await LocationApi.sendPing(
          elderId: elderId,
          userId: userId,
          latitude: row['latitude'] as double,
          longitude: row['longitude'] as double,
          accuracyM: row['accuracy_m'] as double?,
          recordedAt: DateTime.tryParse(row['recorded_at'] as String),
        );
        if (ok) {
          await DatabaseHelper.instance.delete(
            'location_points',
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } else {
          // 仍然連不上，停止本輪補送，下一個新點到達時再試。
          break;
        }
      }
    } finally {
      _isFlushingQueue = false;
    }
  }
}
