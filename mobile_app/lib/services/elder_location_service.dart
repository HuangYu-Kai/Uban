// lib/services/elder_location_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'friend_service.dart';
import 'database_helper.dart';
import 'api/location_api.dart';
import 'location_device_status.dart';

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

  /// 心跳：distanceFilter 讓靜止的長輩完全不送點，後端的「長時間沒有位置」
  /// 提醒會因此誤報；所以每 10 分鐘檢查一次，若已超過 9 分鐘沒送過任何點，
  /// 就主動取一次當下位置補送。
  static const Duration _heartbeatInterval = Duration(minutes: 10);
  static const Duration _heartbeatStaleAfter = Duration(minutes: 9);
  static const Duration _heartbeatFixTimeout = Duration(seconds: 30);

  int? _userId;
  String? _elderId;
  StreamSubscription<Position>? _positionStream;
  Position? _lastAccepted;
  bool _isRunning = false;
  bool _isFlushingQueue = false;
  Timer? _heartbeatTimer;
  bool _isHeartbeating = false;
  DateTime? _lastSentAt;

  /// 裝置狀態重複回報的最短間隔：狀態沒變且上次回報成功時，這段時間內不再
  /// 重送，避免每次回到 App 都打一次後端；狀態一變就立刻回報。
  static const Duration _statusReportRefresh = Duration(minutes: 30);

  bool _sharingEnabled = false;
  bool _isStarting = false;
  String? _lastReportedStatus;
  DateTime? _lastReportedAt;

  /// 目前手機定位權限／定位服務的狀態（值見 [LocationDeviceStatus]），供長輩端
  /// 「我的」分頁在權限不足時顯示提示與前往設定的按鈕。`null` 代表尚未檢查
  /// 或分享已關閉；Web 一律為 `ok`（無法判斷，不誤報）。
  final ValueNotifier<String?> deviceStatus = ValueNotifier<String?>(null);

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
    _sharingEnabled = enabled == true;
    if (enabled == true) {
      await _start();
    }
  }

  /// 讀取手機目前的定位服務／權限並換算成回報用狀態（對應表見
  /// [LocationDeviceStatus.fromDevice]）。**不會跳出任何權限對話框**，任何
  /// 例外都回傳 `ok`（寧可不警示也不誤報）；Web 一律 `ok`。
  Future<String> checkDeviceStatus() async {
    if (kIsWeb) return LocationDeviceStatus.ok;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      return LocationDeviceStatus.fromDevice(
        serviceEnabled: serviceEnabled,
        permission: permission,
      );
    } catch (e) {
      debugPrint('⚠️ ElderLocationService.checkDeviceStatus error: $e');
      return LocationDeviceStatus.ok;
    }
  }

  /// 檢查並更新 [deviceStatus]，再「背景」回報後端（fire-and-forget，不等網路、
  /// 絕不拋例外、不阻擋定位啟動）。Web 不回報。回傳檢查到的狀態。
  Future<String> _refreshAndReportStatus() async {
    final status = await checkDeviceStatus();
    deviceStatus.value = status;
    if (kIsWeb) return status;

    final elderId = _elderId;
    final userId = _userId;
    if (elderId == null || userId == null) return status;

    final lastAt = _lastReportedAt;
    final unchanged = _lastReportedStatus == status &&
        lastAt != null &&
        DateTime.now().difference(lastAt) < _statusReportRefresh;
    if (unchanged) return status;

    unawaited(() async {
      final ok = await LocationApi.reportDeviceStatus(
        elderId: elderId,
        userId: userId,
        status: status,
      );
      if (ok) {
        _lastReportedStatus = status;
        _lastReportedAt = DateTime.now();
      }
    }());
    return status;
  }

  /// 供長輩端畫面「回到 App」時呼叫（例如從手機設定頁回來）：分享開啟時重新
  /// 檢查權限、更新提示並回報；若已經補好權限而串流還沒跑，順便啟動串流。
  /// **不會再次跳出權限對話框**（只用 `checkPermission`），避免長輩一回來
  /// 又被詢問。分享關閉、尚未初始化或正在啟動中時什麼都不做。
  Future<void> recheckDeviceStatus() async {
    if (!_sharingEnabled || _isStarting || _elderId == null || _userId == null) return;
    final status = await _refreshAndReportStatus();
    if (!_isRunning &&
        _sharingEnabled &&
        (status == LocationDeviceStatus.ok ||
            status == LocationDeviceStatus.foregroundOnly)) {
      _beginStream();
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

    _sharingEnabled = enabled;
    if (enabled) {
      // 重新開啟分享：不論之前回報過什麼，都重新回報一次最新狀態。
      _lastReportedStatus = null;
      _lastReportedAt = null;
      await _start();
    } else {
      await stop();
      deviceStatus.value = null;
    }
    return true;
  }

  Future<void> _start() async {
    if (_isRunning || _isStarting || _elderId == null) return;
    _isStarting = true;
    try {
      final granted = await _requestPermission();
      // 走完權限流程後，不論成功與否都回報最新狀態（背景送出，不阻擋啟動）。
      // 沒拿到權限時串流不會啟動，家屬端靠這筆回報才知道原因。
      unawaited(_refreshAndReportStatus());
      if (!granted) return;
      _beginStream();
    } finally {
      _isStarting = false;
    }
  }

  /// 實際建立位置串流與心跳（已取得權限後呼叫）；重複呼叫無害。
  void _beginStream() {
    if (_isRunning || _elderId == null) return;
    _isRunning = true;
    _positionStream = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(),
    ).listen(_onPosition, onError: (Object _) {});
    _lastSentAt = DateTime.now();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _heartbeat());
  }

  /// 心跳補點：靜止時串流不會有新點，超過 [_heartbeatStaleAfter] 沒送過就
  /// 主動取一次定位，走與串流相同的 [_sendOrQueue]。逾時或任何錯誤一律
  /// 靜默略過，等下一輪再試；精確度不合格（[_maxAccuracyMeters]）也不送。
  Future<void> _heartbeat() async {
    if (!_isRunning || _isHeartbeating) return;
    final last = _lastSentAt;
    if (last != null && DateTime.now().difference(last) < _heartbeatStaleAfter) {
      return;
    }
    _isHeartbeating = true;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _heartbeatFixTimeout,
        ),
      );
      // 等待定位期間可能已被 stop()，此時不應再送出。
      if (!_isRunning) return;
      if (pos.accuracy <= 0 || pos.accuracy > _maxAccuracyMeters) return;
      await _sendOrQueue(pos);
    } catch (_) {
      // 逾時（TimeoutException）、權限或定位服務關閉：靜默略過。
    } finally {
      _isHeartbeating = false;
    }
  }

  /// 供 `ElderHomeScreen.dispose` 呼叫，以及切換開關關閉時使用。
  Future<void> stop() async {
    _isRunning = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _positionStream?.cancel();
    _positionStream = null;
    _lastAccepted = null;
    _lastSentAt = null;
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
    // 記錄最近一次「送出（或排入離線佇列）」的時間，供心跳判斷是否太久沒送。
    _lastSentAt = DateTime.now();

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
