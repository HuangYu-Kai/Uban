import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/age_stepper_field.dart';
import '../widgets/city_district_picker.dart';

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

  @override
  void initState() {
    super.initState();
    _prefillAge();
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
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFFFFBF0),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                const Icon(Icons.assignment_ind_rounded, size: 56, color: AppColors.primary),
                const SizedBox(height: 20),
                Text('請完成基本資料', style: ElderScale.sectionTitle),
                const SizedBox(height: 12),
                Text(
                  '${widget.userName} 您好，麻煩您確認一下年齡跟居住的縣市／地區，這樣才能繼續使用喔！',
                  style: ElderScale.body,
                ),
                const SizedBox(height: 32),
                AgeStepperField(
                  elderMode: true,
                  value: _age,
                  onChanged: (v) => setState(() {
                    _age = v;
                    _errorMessage = null;
                  }),
                ),
                const SizedBox(height: 28),
                CityDistrictPicker(
                  elderMode: true,
                  initialCity: _residenceCity,
                  initialDistrict: _residenceDistrict,
                  onChanged: (city, district) => setState(() {
                    _residenceCity = city;
                    _residenceDistrict = district;
                    _errorMessage = null;
                  }),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFDC2626), width: 1.5),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: ElderScale.body.copyWith(color: const Color(0xFF991B1B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: ElderScale.buttonHeight,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ElderScale.cardRadius)),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text('確定，開始使用', style: ElderScale.button.copyWith(color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
