import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../widgets/age_stepper_field.dart';
import '../widgets/city_district_picker.dart';
import '../widgets/login_flow_parts.dart';
import '../utils/taiwan_districts.dart';
import '../widgets/ui/ui.dart';

/// 長輩帳號「年齡／居住地」強制補填畫面（長輩尺規）。
///
/// ★ 第五十三輪 onboard53（長 9）：長輩端第一次登入時強制收集年齡與居住地
/// （縣市／行政區，不含街道門牌），用於開發者統計。使用者明確決定
/// 「由選填改為必填，不再允許沒填過就不再跳」，故本畫面沒有「以後再說」
/// 按鈕，`PopScope(canPop:false)` 也擋掉返回鍵／手勢。
///
/// 涵蓋三條長輩端入口（皆在 `elder_pairing_display_screen.dart` 呼叫，見該檔
/// 的 `_goToElderHome`）：
/// 1. 家屬掃碼配對成功、建立的全新長輩帳號
/// 2. 「我自己使用」自主模式建立的全新長輩帳號
/// 3. 「登入上次長輩」還原既有 session 時，若該長輩資料仍缺這些欄位
///
/// ⚠️ 只覆蓋「通話機」(comm) 這條路徑，導向 `ElderHomeScreen`；監控機
/// (isMonitor) 路徑刻意不經過這裡——監控機只會在「已經有一台通話機存在」
/// 時才可能被指派，代表這位長輩的資料多半已經在那台通話機上補過了；
/// 更重要的是不希望在 `ElderScreen`（通話／CCTV 生命週期最複雜、風險最高
/// 的畫面）前面插入任何新邏輯，以免干擾它自己對背景來電狀態的處理——
/// 這是本輪任務明確劃出的紅線（CLAUDE_call-monitor.md 相關檔案不得更動）。
class ElderProfileOnboardingScreen extends StatefulWidget {
  final int userId;
  final String userName;
  final String roomId;

  /// 補填完成後要導去哪個畫面，由呼叫端（`elder_pairing_display_screen.dart`）
  /// 決定——一律是 `ElderHomeScreen`，但本畫面刻意不直接 import 該畫面，
  /// 讓呼叫端保留組裝 userId/userName/roomId 的權責，本畫面只管收集與送出。
  final WidgetBuilder nextScreenBuilder;

  const ElderProfileOnboardingScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.roomId,
    required this.nextScreenBuilder,
  });

  @override
  State<ElderProfileOnboardingScreen> createState() =>
      _ElderProfileOnboardingScreenState();
}

class _ElderProfileOnboardingScreenState
    extends State<ElderProfileOnboardingScreen> {
  int? _age;
  String? _residenceCity;
  String? _residenceDistrict;
  bool _isSaving = false;
  String? _errorMessage;
  bool _isLocating = false;
  bool _autoFilled = false;

  @override
  void initState() {
    super.initState();
    _prefillAge();
    _autoLocate();
  }

  /// 「台」→「臺」後才能對上白名單（kTaiwanCities 一律用「臺」）。
  String _normalizeRegion(String? s) => (s ?? '').trim().replaceAll('台', '臺');

  /// 自動定位帶入縣市／區。任何失敗（拒絕權限、逾時、查不到、不在白名單）
  /// 一律靜默，維持手動選擇；也不覆蓋長輩已經自己選好的值（[force] 除外）。
  Future<void> _autoLocate({bool force = false}) async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 8));
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 8));
      if (placemarks.isEmpty || !mounted) return;
      final place = placemarks.first;
      final city = _normalizeRegion(place.administrativeArea);
      String? district;
      for (final cand in [
        place.subAdministrativeArea,
        place.locality,
        place.subLocality,
      ]) {
        final d = _normalizeRegion(cand);
        if (d.isNotEmpty && isValidCityDistrict(city, d)) {
          district = d;
          break;
        }
      }
      if (district == null) return;
      // 定位期間長輩若已手動選好，就不要覆蓋。
      if (!force && (_residenceCity != null || _residenceDistrict != null)) {
        return;
      }
      setState(() {
        _residenceCity = city;
        _residenceDistrict = district;
        _autoFilled = true;
        _errorMessage = null;
      });
    } catch (_) {
      // 靜默：保留手動選擇
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  /// 長輩帳號建立時（自主模式預設 75 歲，或家屬配對時手動輸入）多半已經有
  /// 一個年齡值，預先帶入讓長輩用「-／+」確認或調整，不必從空白重新選——
  /// 讀取失敗就維持空白，長輩仍可自行用 +／- 選擇，不影響這個畫面本身的
  /// 必填要求（提交前仍會檢查 _age 是否已選）。
  Future<void> _prefillAge() async {
    final result = await ApiService.getElderProfile(widget.userId);
    if (!mounted) return;
    if (result['status'] == 'success' && result['data'] is Map) {
      final data = result['data'] as Map<String, dynamic>;
      final ageVal = data['age'];
      if (ageVal is num) {
        setState(() => _age = ageVal.toInt());
      }
    }
  }

  Future<void> _submit() async {
    if (_age == null || _residenceCity == null || _residenceDistrict == null) {
      setState(() => _errorMessage = '請選擇年齡與居住地喔');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final result = await ApiService.updateElderProfile(
      userId: widget.userId,
      age: _age,
      residenceCity: _residenceCity,
      residenceDistrict: _residenceDistrict,
    );

    if (!mounted) return;

    if (result['status'] == 'success') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: widget.nextScreenBuilder),
      );
      return;
    }

    setState(() {
      _isSaving = false;
      _errorMessage =
          (result['message'] ?? result['error'] ?? result['detail'] ?? '儲存失敗，請稍後再試')
              .toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
              child: ConstrainedBox(
                // 內容不足一屏時 CTA 沉到底；超出（小螢幕／大字級）則整頁可捲。
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 56).clamp(0.0, double.infinity),
                  maxWidth: 560,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: UbanMarkBox(
                            size: 64,
                            radius: 20,
                            color: c.brandContainer,
                            child: Icon(Icons.person_outline_rounded,
                                size: 34, color: c.brandStrong),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text('請完成基本資料', style: ubanH1(context)),
                        const SizedBox(height: 20),
                        Text(
                          '${widget.userName} 您好，麻煩您確認一下年齡跟居住的縣市／地區，這樣才能繼續使用喔！',
                          style: ubanBody(context, size: 20),
                        ),
                        const SizedBox(height: 20),
                        AgeStepperField(
                          elderMode: true,
                          value: _age,
                          onChanged: (v) => setState(() {
                            _age = v;
                            _errorMessage = null;
                          }),
                        ),
                        const SizedBox(height: 20),
                        CityDistrictPicker(
                          elderMode: true,
                          initialCity: _residenceCity,
                          initialDistrict: _residenceDistrict,
                          onChanged: (city, district) => setState(() {
                            _residenceCity = city;
                            _residenceDistrict = district;
                            _autoFilled = false; // 手動改過就不再宣稱是自動帶入
                            _errorMessage = null;
                          }),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (_autoFilled)
                              Expanded(
                                child: Row(
                                  children: [
                                    Icon(Icons.my_location_rounded,
                                        size: 20, color: c.brandStrong),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '已依您目前位置自動帶入',
                                        style: ubanText(
                                            17, FontWeight.w600, c.text2),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              const Spacer(),
                            TextButton.icon(
                              onPressed: _isLocating
                                  ? null
                                  : () => _autoLocate(force: true),
                              icon: _isLocating
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.refresh_rounded, size: 20),
                              label: Text(_isLocating ? '定位中…' : '重新定位',
                                  style: ubanText(
                                      17, FontWeight.w700, c.brandStrong)),
                            ),
                          ],
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: c.dangerContainer,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: c.danger, width: 1.5),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.error_outline_rounded,
                                    color: c.danger, size: 28),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: ubanText(20, FontWeight.w600, c.text,
                                        height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                      ],
                    ),
                    UbanButton(
                      label: '確定，開始使用',
                      size: UbanButtonSize.xl,
                      loading: _isSaving,
                      onPressed: _isSaving ? null : _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
