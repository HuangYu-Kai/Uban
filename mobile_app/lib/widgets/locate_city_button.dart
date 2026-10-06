import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/taiwan_districts.dart';
import 'ui/ui.dart';

/// 「用我現在的位置自動填入」按鈕（縣市／行政區一鍵定位）。
///
/// ★ 2026-10-06 登入流程改善：把原本只藏在長輩資料補填畫面、失敗時靜默的
/// `_autoLocate()` 抽成共用元件，長輩補填／家屬補填／註冊三個畫面都放在
/// [CityDistrictPicker] 上方。
///
/// 行為：
/// - 使用者點擊（明確操作）：必要時跳權限對話框，成功一律覆蓋；失敗在按鈕下方
///   顯示明確的行內訊息（權限被拒、永久拒絕可「前往設定」、定位服務關閉可
///   「開啟定位設定」、找不到縣市）。
/// - 開頁自動執行（[autoLocateIfGranted]）：**只有權限已經授予**才會跑，絕不
///   在使用者沒操作時跳權限對話框；失敗一律靜默；且 [canAutoFill] 回傳 false
///   （使用者已手動選過）時不覆蓋。
///
/// 定位成功後呼叫 [onLocated]（縣市／區已正規化「台→臺」並通過
/// [isValidCityDistrict] 白名單驗證）。
class LocateCityButton extends StatefulWidget {
  final void Function(String city, String district) onLocated;

  /// 長輩尺規（字級 ≥20、按鈕高度加大）。
  final bool elderMode;

  /// 開頁時若定位權限已授予，自動定位一次（不會跳權限對話框）。
  final bool autoLocateIfGranted;

  /// 自動定位完成當下是否允許填入；回傳 false 代表使用者已自行選擇，不覆蓋。
  /// 只影響自動執行，不影響使用者明確點擊。
  final bool Function()? canAutoFill;

  /// ★ 2026-10-06：父層在使用者手動改選縣市／區時呼叫 `notifier.value++`，
  /// 清掉「已依您目前位置填入」提示（不傳則不清）。
  final ValueNotifier<int>? resetNotifier;

  const LocateCityButton({
    super.key,
    required this.onLocated,
    this.elderMode = false,
    this.autoLocateIfGranted = false,
    this.canAutoFill,
    this.resetNotifier,
  });

  @override
  State<LocateCityButton> createState() => _LocateCityButtonState();
}

enum _LocateIssue { denied, deniedForever, serviceOff, notFound, unavailable }

class _LocateCityButtonState extends State<LocateCityButton> {
  bool _isLocating = false;
  bool _success = false;
  _LocateIssue? _issue;

  @override
  void initState() {
    super.initState();
    widget.resetNotifier?.addListener(_onReset);
    if (widget.autoLocateIfGranted) _autoRunIfGranted();
  }

  void _onReset() {
    if (mounted && _success) setState(() => _success = false);
  }

  @override
  void dispose() {
    widget.resetNotifier?.removeListener(_onReset);
    super.dispose();
  }

  Future<void> _autoRunIfGranted() async {
    try {
      final p = await Geolocator.checkPermission();
      if (p != LocationPermission.whileInUse &&
          p != LocationPermission.always) {
        return;
      }
    } catch (_) {
      return;
    }
    if (!mounted) return;
    await _locate(userInitiated: false);
  }

  /// 「台」→「臺」後才能對上白名單（kTaiwanCities 一律用「臺」）。
  String _normalizeRegion(String? s) => (s ?? '').trim().replaceAll('台', '臺');

  Future<void> _locate({required bool userInitiated}) async {
    if (_isLocating) return;
    setState(() {
      _isLocating = true;
      _issue = null;
    });
    _LocateIssue? issue;
    String? city;
    String? district;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && userInitiated) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        issue = _LocateIssue.deniedForever;
      } else if (permission == LocationPermission.denied) {
        issue = _LocateIssue.denied;
      } else if (!await Geolocator.isLocationServiceEnabled()) {
        issue = _LocateIssue.serviceOff;
      } else {
        final position = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.medium),
        ).timeout(const Duration(seconds: 8));
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        ).timeout(const Duration(seconds: 8));
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final c = _normalizeRegion(place.administrativeArea);
          for (final cand in [
            place.subAdministrativeArea,
            place.locality,
            place.subLocality,
          ]) {
            final d = _normalizeRegion(cand);
            if (d.isNotEmpty && isValidCityDistrict(c, d)) {
              city = c;
              district = d;
              break;
            }
          }
        }
        if (city == null) issue = _LocateIssue.notFound;
      }
    } catch (_) {
      // 逾時／網路或定位／地理編碼例外：與「定位到了但不在白名單」分開提示
      issue = _LocateIssue.unavailable;
    }
    if (!mounted) return;
    // 自動執行：定位期間若使用者已手動選好就不覆蓋；失敗也靜默不顯示訊息。
    final auto = !userInitiated;
    if (auto && (issue != null || !(widget.canAutoFill?.call() ?? true))) {
      setState(() => _isLocating = false);
      return;
    }
    setState(() {
      _isLocating = false;
      _issue = issue;
      _success = issue == null;
    });
    if (issue == null) widget.onLocated(city!, district!);
  }

  String _issueText(_LocateIssue i) {
    switch (i) {
      case _LocateIssue.denied:
      case _LocateIssue.deniedForever:
        return '需要定位權限才能自動填入，您也可以直接從下方選擇';
      case _LocateIssue.serviceOff:
        return '請先開啟手機的定位功能';
      case _LocateIssue.notFound:
        return '找不到您所在的縣市，請直接從下方選擇';
      case _LocateIssue.unavailable:
        return '目前無法取得位置，請確認網路與定位後再試，或直接從下方選擇';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final elder = widget.elderMode;
    final double fs = elder ? 20 : 16;

    Widget? action;
    if (_issue == _LocateIssue.deniedForever) {
      action = TextButton(
        onPressed: () => Geolocator.openAppSettings(),
        child: Text('前往設定',
            style: ubanText(fs, FontWeight.w700, c.brandStrong)),
      );
    } else if (_issue == _LocateIssue.serviceOff) {
      action = TextButton(
        onPressed: () => Geolocator.openLocationSettings(),
        child: Text('開啟定位設定',
            style: ubanText(fs, FontWeight.w700, c.brandStrong)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          onPressed: _isLocating ? null : () => _locate(userInitiated: true),
          style: OutlinedButton.styleFrom(
            minimumSize: Size.fromHeight(elder ? 68 : 54),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            side: BorderSide(color: c.brandStrong, width: 1.5),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLocating)
                SizedBox(
                  width: elder ? 24 : 20,
                  height: elder ? 24 : 20,
                  child: const CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                Icon(Icons.my_location_rounded,
                    size: elder ? 28 : 22, color: c.brandStrong),
              const SizedBox(width: 10),
              // Row 內動態文字（定位中／正常切換）＋大字級，需可收縮（規則 14）
              Flexible(
                child: Text(
                  _isLocating ? '定位中…' : '用我現在的位置自動填入',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: ubanText(fs, FontWeight.w700, c.brandStrong),
                ),
              ),
            ],
          ),
        ),
        if (_issue != null) ...[
          const SizedBox(height: 8),
          Text(_issueText(_issue!),
              style: ubanText(elder ? 18 : 14, FontWeight.w600, c.danger,
                  height: 1.4)),
          if (action != null)
            Align(alignment: Alignment.centerLeft, child: action),
        ] else if (_success && !_isLocating) ...[
          const SizedBox(height: 8),
          Text('已依您目前位置填入',
              style: ubanText(elder ? 18 : 14, FontWeight.w600, c.text2)),
        ],
      ],
    );
  }
}
