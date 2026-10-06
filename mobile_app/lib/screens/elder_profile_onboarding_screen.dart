import 'dart:async';

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/session_manager.dart';
import 'identification_screen.dart';
import '../widgets/age_stepper_field.dart';
import '../widgets/city_district_picker.dart';
import '../widgets/login_flow_parts.dart';
import '../widgets/locate_city_button.dart';
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
  final ValueNotifier<int> _locateReset = ValueNotifier<int>(0);
  String? _residenceDistrict;
  bool _isSaving = false;
  String? _errorMessage;
  // ★ 2026-10-06：年齡由「知道的那一方設一次」——家屬配對時若已填年齡，這裡不再詢問；
  //   profile 讀取完成前不渲染年齡區塊，避免步進器閃一下又消失。
  bool _profileLoaded = false;
  bool _ageFromProfile = false;

  @override
  void initState() {
    super.initState();
    _prefillAge();
  }

  /// 讀取長輩既有資料。已有年齡（家屬配對時填的）→ 隱藏年齡步進器、原值送出，
  /// 只問居住地；沒有年齡（家屬留空／自主模式）→ 顯示步進器必選。
  /// 讀取失敗 → 顯示步進器（fail-safe，仍可自行選擇）。
  Future<void> _prefillAge() async {
    int? age;
    try {
      final result = await ApiService.getElderProfile(widget.userId);
      if (result['status'] == 'success' && result['data'] is Map) {
        final data = result['data'] as Map<String, dynamic>;
        final ageVal = data['age'];
        if (ageVal is num) age = ageVal.toInt();
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _age = age;
      _ageFromProfile = age != null;
      _profileLoaded = true;
    });
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

  /// ★ 2026-10-06 登入流程審查：必填補填畫面擋住返回鍵，但不能讓人被鎖死在
  /// 錯的帳號上。比照 elder_tabs/elder_profile_tab.dart 長輩登出：
  /// preserveQuickLogin: true ＋ 回身分辨識頁。
  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('登出'),
        content: const Text('確定要登出並換一個帳號嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('登出'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await SessionManager.releaseSession(preserveQuickLogin: true);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const IdentificationScreen()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _locateReset.dispose();
    super.dispose();
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
                          (_profileLoaded && _ageFromProfile)
                              ? '${widget.userName} 您好，麻煩您選一下居住的縣市／地區，這樣才能繼續使用喔！'
                              : '${widget.userName} 您好，麻煩您確認一下年齡跟居住的縣市／地區，這樣才能繼續使用喔！',
                          style: ubanBody(context, size: 20),
                        ),
                        const SizedBox(height: 20),
                        if (_profileLoaded && !_ageFromProfile) ...[
                          AgeStepperField(
                            elderMode: true,
                            value: _age,
                            onChanged: (v) => setState(() {
                              _age = v;
                              _errorMessage = null;
                            }),
                          ),
                          const SizedBox(height: 20),
                        ],
                        // ★ 2026-10-06：一鍵定位按鈕放在縣市選單上方；
                        //   只在權限已授予時開頁自動帶入，不覆蓋手動選擇。
                        LocateCityButton(
                          resetNotifier: _locateReset,
                          elderMode: true,
                          autoLocateIfGranted: true,
                          canAutoFill: () =>
                              _residenceCity == null &&
                              _residenceDistrict == null,
                          onLocated: (city, district) => setState(() {
                            _residenceCity = city;
                            _residenceDistrict = district;
                            _errorMessage = null;
                          }),
                        ),
                        const SizedBox(height: 16),
                        CityDistrictPicker(
                          elderMode: true,
                          initialCity: _residenceCity,
                          initialDistrict: _residenceDistrict,
                          onChanged: (city, district) => setState(() {
                            _locateReset.value++; // 手動改選 → 清掉「已依位置填入」提示
                            _residenceCity = city;
                            _residenceDistrict = district;
                            _errorMessage = null;
                          }),
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
                      // ★ 2026-10-06：profile 讀取完成前停用，避免對看不見的年齡欄報錯
                      onPressed: (_isSaving || !_profileLoaded) ? null : _submit,
                    ),
                    const SizedBox(height: 12),
                    // ★ 2026-10-06：次要出口（≥18pt），避免被鎖在錯的帳號
                    TextButton(
                      onPressed: _isSaving ? null : _confirmLogout,
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      child: Text(
                        '登出，換一個帳號',
                        textAlign: TextAlign.center,
                        style: ubanText(20, FontWeight.w600, c.text2),
                      ),
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
