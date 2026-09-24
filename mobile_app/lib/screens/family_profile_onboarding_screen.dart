import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/age_stepper_field.dart';
import '../widgets/city_district_picker.dart';

/// 既有家屬帳號「年齡／居住地」強制補填畫面。
///
/// ★ 第五十三輪 onboard53（家 4）：使用者明確決定「我現在決定不再允許沒填過
/// 就不再跳，每個人一定都要填，由當初設計初衷的『選填』改為『必填』」——
/// 這個畫面沒有「以後再說」／「略過」按鈕，也沒有返回鍵。
///
/// 這個畫面只服務**既有帳號**：全新註冊的帳號已經在
/// `registration_screen.dart` 的表單裡一次收集完畢，登入時的完整度檢查
/// （見 `login_screen.dart::_handleLogin`）一定會判定為已完整，不會被導來
/// 這裡。這裡接住的是「這次改動上線之前就已經存在」的帳號。
///
/// ⚠️ fail-open 的責任在呼叫端（`login_screen.dart`）：呼叫端已經確認過
/// 「這是讀得到資料、且資料確實是空的」才會導來本畫面；本畫面本身不重複
/// 判斷，只負責收集與送出。
class FamilyProfileOnboardingScreen extends StatefulWidget {
  final int userId;
  final String userName;

  /// 補填完成後要導去哪個畫面，由呼叫端決定（依 hasPaired 不同，
  /// 可能是 FamilyMainScreen 或 FamilyOnboardingScreen）——本畫面刻意不
  /// import 那兩個畫面，避免耦合登入流程的分支邏輯。
  final WidgetBuilder nextScreenBuilder;

  const FamilyProfileOnboardingScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.nextScreenBuilder,
  });

  @override
  State<FamilyProfileOnboardingScreen> createState() =>
      _FamilyProfileOnboardingScreenState();
}

class _FamilyProfileOnboardingScreenState
    extends State<FamilyProfileOnboardingScreen> {
  int? _age;
  String? _residenceCity;
  String? _residenceDistrict;
  bool _isSaving = false;
  String? _errorMessage;

  Future<void> _submit() async {
    if (_age == null || _residenceCity == null || _residenceDistrict == null) {
      setState(() => _errorMessage = '請填寫年齡與居住地（縣市／行政區）');
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
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: widget.nextScreenBuilder),
        (route) => false,
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
    // ★ 不提供略過：擋掉系統手勢／實體返回鍵直接離開這個畫面。
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFFFFBF0),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const Icon(Icons.assignment_ind_rounded, size: 48, color: AppColors.accent),
                const SizedBox(height: 16),
                Text(
                  '請完成基本資料',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.userName} 您好，系統需要補齊年齡與居住地才能繼續使用，只要幾秒鐘。此資訊僅用於平台統計分析，不會對外公開。',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    color: Colors.grey[700],
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                AgeStepperField(
                  value: _age,
                  onChanged: (v) => setState(() {
                    _age = v;
                    _errorMessage = null;
                  }),
                ),
                const SizedBox(height: 20),
                CityDistrictPicker(
                  initialCity: _residenceCity,
                  initialDistrict: _residenceDistrict,
                  onChanged: (city, district) => setState(() {
                    _residenceCity = city;
                    _residenceDistrict = district;
                    _errorMessage = null;
                  }),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFDC2626)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF991B1B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            '確定並繼續',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
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
