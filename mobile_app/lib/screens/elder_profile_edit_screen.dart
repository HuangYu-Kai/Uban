import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';

/// 🧓 編輯長輩資料頁面 (ElderProfileEditScreen)
/// 與子女端一致的深色極光主題 (Dark Aurora Theme)
class ElderProfileEditScreen extends StatefulWidget {
  final Map<String, dynamic> elderData;
  final int? familyId;
  final VoidCallback? onUnbind;

  const ElderProfileEditScreen({
    super.key,
    required this.elderData,
    this.familyId,
    this.onUnbind,
  });

  @override
  State<ElderProfileEditScreen> createState() => _ElderProfileEditScreenState();
}

class _ElderProfileEditScreenState extends State<ElderProfileEditScreen> {
  // 基本資料 Controller
  late TextEditingController _nameController;
  late TextEditingController _ageController;
  late TextEditingController _cityController;
  late TextEditingController _districtController;
  late TextEditingController _appellationController;

  late TextEditingController _chronicDiseasesController;
  late TextEditingController _medicationNotesController;
  late TextEditingController _interestsController;

  // 基本資料 - 性別
  String _currentGender = 'M';

  // AI 性格偏好 (滑桿版本)
  double _aiEmotionTone = 50;
  double _aiTextVerbosity = 50;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.elderData['user_name'] ?? widget.elderData['elder_name'] ?? '',
    );
    _ageController = TextEditingController(
      text: widget.elderData['age']?.toString() ?? '',
    );

    String location = widget.elderData['location']?.toString() ?? '';
    String initialCity = '';
    String initialDistrict = '';

    // 安全解析位置字串
    if (location.isNotEmpty) {
      try {
        int cityIndex = location.indexOf('市');
        int countyIndex = location.indexOf('縣');
        int splitIndex = -1;

        if (cityIndex != -1 && countyIndex != -1) {
          splitIndex = cityIndex < countyIndex ? cityIndex : countyIndex;
        } else if (cityIndex != -1) {
          splitIndex = cityIndex;
        } else if (countyIndex != -1) {
          splitIndex = countyIndex;
        }

        if (splitIndex != -1 && splitIndex + 1 < location.length) {
          initialCity = location.substring(0, splitIndex + 1);
          initialDistrict = location.substring(splitIndex + 1);
        } else if (splitIndex != -1) {
          initialCity = location.substring(0, splitIndex + 1);
        } else {
          initialCity = location;
        }
      } catch (_) {
        initialCity = '';
        initialDistrict = '';
      }
    }

    _cityController = TextEditingController(text: initialCity);
    _districtController = TextEditingController(text: initialDistrict);
    _appellationController = TextEditingController();
    _chronicDiseasesController = TextEditingController();
    _medicationNotesController = TextEditingController();
    _interestsController = TextEditingController();
    _currentGender = widget.elderData['gender'] ?? 'M';

    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final elderId = widget.elderData['user_id'] ?? widget.elderData['id'];
      if (elderId == null) {
        setState(() => _isLoading = false);
        return;
      }

      final profile = await ApiService.getElderProfile(elderId);
      if (mounted) {
        setState(() {
          _appellationController.text = profile['appellation'] ?? '';
          _aiEmotionTone = (profile['ai_emotion_tone'] ?? 50).toDouble();
          _aiTextVerbosity = (profile['ai_text_verbosity'] ?? 50).toDouble();
          
          String fullLocation = profile['location'] ?? '';
          if (fullLocation.isNotEmpty) {
            _parseLocation(fullLocation);
          }
          
          _chronicDiseasesController.text = profile['chronic_diseases'] ?? '';
          _medicationNotesController.text = profile['medication_notes'] ?? '';
          _interestsController.text = profile['interests'] ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load profile: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _parseLocation(String fullLocation) {
    int cityIndex = fullLocation.indexOf('市');
    int countyIndex = fullLocation.indexOf('縣');
    int splitIndex = -1;

    if (cityIndex != -1 && countyIndex != -1) {
      splitIndex = cityIndex < countyIndex ? cityIndex : countyIndex;
    } else if (cityIndex != -1) {
      splitIndex = cityIndex;
    } else if (countyIndex != -1) {
      splitIndex = countyIndex;
    }

    if (splitIndex != -1 && splitIndex + 1 < fullLocation.length) {
      _cityController.text = fullLocation.substring(0, splitIndex + 1);
      _districtController.text = fullLocation.substring(splitIndex + 1);
    } else {
      _cityController.text = fullLocation;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _appellationController.dispose();
    _chronicDiseasesController.dispose();
    _medicationNotesController.dispose();
    _interestsController.dispose();
    super.dispose();
  }

  void _saveProfile() async {
    final elderId = widget.elderData['user_id'] ?? widget.elderData['id'];
    if (elderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法儲存：無效的長輩 ID')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      if (widget.familyId != null) {
        await ApiService.updateElderInfo(
          familyId: widget.familyId!,
          elderId: elderId,
          userName: _nameController.text.trim(),
          age: int.tryParse(_ageController.text.trim()),
          gender: _currentGender,
        );
      }

      await ApiService.updateElderProfile(
        userId: elderId,
        location: '${_cityController.text.trim()}${_districtController.text.trim()}',
        appellation: _appellationController.text.trim(),
        aiEmotionTone: _aiEmotionTone.toInt(),
        aiTextVerbosity: _aiTextVerbosity.toInt(),
        chronicDiseases: _chronicDiseasesController.text.trim(),
        medicationNotes: _medicationNotesController.text.trim(),
        interests: _interestsController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✨ 長輩資料已成功更新，AI 將採用新設定！',
              style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('儲存失敗: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLocating = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('需要定位權限才能獲取位置');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('定位權限已被永久拒絕');
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        setState(() {
          _cityController.text = place.administrativeArea ?? '';
          _districtController.text = place.subAdministrativeArea ?? place.locality ?? '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('無法取得位置: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B132B),
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
            )
          : _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(
        '編輯長輩資料',
        style: GoogleFonts.notoSansTc(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
      ),
      backgroundColor: const Color(0xFF0F172A),
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        if (!_isLoading)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isSaving
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: _saveProfile,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF38BDF8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      '儲存',
                      style: GoogleFonts.notoSansTc(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: const Color(0xFF38BDF8),
                      ),
                    ),
                  ),
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: const Color(0xFF1E293B), height: 1),
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 基本身分資料
          _buildInfoCard(
            title: '基本身分資料',
            icon: Icons.person_rounded,
            color: const Color(0xFF38BDF8),
            children: [
              _buildInputLabel('真實姓名'),
              _buildModernTextField(
                controller: _nameController,
                hintText: '請輸入長輩真實姓名',
                icon: Icons.badge_outlined,
                accentColor: const Color(0xFF38BDF8),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInputLabel('年齡'),
                        _buildModernTextField(
                          controller: _ageController,
                          hintText: '歲數',
                          icon: Icons.cake_outlined,
                          keyboardType: TextInputType.number,
                          accentColor: const Color(0xFF38BDF8),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInputLabel('性別'),
                        _buildGenderToggle(),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ).animate().fadeIn(duration: 350.ms),

          const SizedBox(height: 18),

          // 2. 生活地區
          _buildInfoCard(
            title: '生活地區',
            icon: Icons.location_on_rounded,
            color: const Color(0xFF10B981),
            children: [
              _buildInputLabel('主要居住地 (用於天氣查詢與在地生活活動建議)'),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _buildModernTextField(
                          controller: _cityController,
                          hintText: '縣 / 市 (例：台北市)',
                          icon: Icons.location_city_rounded,
                          accentColor: const Color(0xFF10B981),
                        ),
                        const SizedBox(height: 10),
                        _buildModernTextField(
                          controller: _districtController,
                          hintText: '鄉鎮市區 (例：大安區)',
                          icon: Icons.map_rounded,
                          accentColor: const Color(0xFF10B981),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildLocateButton(),
                ],
              ),
            ],
          ).animate().fadeIn(delay: 50.ms, duration: 350.ms),

          const SizedBox(height: 18),

          // 3. AI 陪伴助手設定
          _buildInfoCard(
            title: 'AI 陪伴助手個性設定',
            icon: Icons.auto_awesome_rounded,
            color: const Color(0xFF8B5CF6),
            children: [
              _buildInputLabel('長輩對 AI 的稱呼 (例：奶奶、阿公、伯伯)'),
              _buildModernTextField(
                controller: _appellationController,
                hintText: 'AI 將以此親切稱呼長輩',
                icon: Icons.record_voice_over_rounded,
                accentColor: const Color(0xFF8B5CF6),
              ),
              const SizedBox(height: 20),
              _buildPersonalitySlider(
                label: '陪伴語氣風格',
                value: _aiEmotionTone,
                leftLabel: '客觀冷靜',
                rightLabel: '熱情親切 (推薦)',
                onChanged: (v) => setState(() => _aiEmotionTone = v),
                gradient: const [Color(0xFF6366F1), Color(0xFFEC4899)],
              ),
              const SizedBox(height: 20),
              _buildPersonalitySlider(
                label: '話匣子開關 (對話長度)',
                value: _aiTextVerbosity,
                leftLabel: '簡潔扼要',
                rightLabel: '滔滔不絕 (聊天陪伴)',
                onChanged: (v) => setState(() => _aiTextVerbosity = v),
                gradient: const [Color(0xFF10B981), Color(0xFF38BDF8)],
              ),
            ],
          ).animate().fadeIn(delay: 100.ms, duration: 350.ms),

          const SizedBox(height: 18),

          // 4. 健康與用藥備註
          _buildInfoCard(
            title: '健康與護理備註',
            icon: Icons.health_and_safety_rounded,
            color: const Color(0xFFF59E0B),
            children: [
              _buildInputLabel('慢性病史或特殊體質注意事項'),
              _buildModernTextArea(
                controller: _chronicDiseasesController,
                hintText: '例如：高血壓、糖尿病、對盤尼西林過敏...',
                accentColor: const Color(0xFFF59E0B),
              ),
              const SizedBox(height: 16),
              _buildInputLabel('每日用藥與照護提醒'),
              _buildModernTextArea(
                controller: _medicationNotesController,
                hintText: '例如：早晚飯後需服用降血壓藥、每日多喝溫開水...',
                accentColor: const Color(0xFFF59E0B),
              ),
            ],
          ).animate().fadeIn(delay: 150.ms, duration: 350.ms),

          const SizedBox(height: 18),

          // 5. 個人興趣與話題素材
          _buildInfoCard(
            title: '專屬興趣與家族回憶素材',
            icon: Icons.favorite_rounded,
            color: const Color(0xFFEC4899),
            children: [
              _buildInputLabel('讓 AI 更懂長輩 (年輕回憶、興趣、經歷等)'),
              _buildModernTextArea(
                controller: _interestsController,
                hintText: '例如：喜歡聽鄧麗君與經典老歌、年輕時在大稻埕經商、愛聊園藝與泡茶...',
                accentColor: const Color(0xFFEC4899),
              ),
            ],
          ).animate().fadeIn(delay: 200.ms, duration: 350.ms),

          const SizedBox(height: 32),

          // 6. 底部儲存按鈕
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveProfile,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_rounded, size: 20),
              label: Text(
                _isSaving ? '正在儲存變更...' : '確認並儲存長輩資料',
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: const Color(0xFF0F172A),
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ).animate().fadeIn(delay: 250.ms, duration: 350.ms),

          if (widget.onUnbind != null) ...[
            const SizedBox(height: 20),
            _buildUnbindButton().animate().fadeIn(delay: 300.ms, duration: 350.ms),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            color: const Color(0xFF334155).withValues(alpha: 0.6),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        label,
        style: GoogleFonts.notoSansTc(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF94A3B8),
        ),
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required Color accentColor,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B132B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: GoogleFonts.notoSansTc(
          fontSize: 15,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.notoSansTc(color: const Color(0xFF64748B), fontSize: 14),
          prefixIcon: Icon(icon, color: accentColor.withValues(alpha: 0.8), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildGenderToggle() {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0B132B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          _buildGenderBtn('男 👨', _currentGender == 'M', () => setState(() => _currentGender = 'M')),
          _buildGenderBtn('女 👩', _currentGender == 'F', () => setState(() => _currentGender = 'F')),
        ],
      ),
    );
  }

  Widget _buildGenderBtn(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Text(
            label,
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocateButton() {
    return GestureDetector(
      onTap: _isLocating ? null : _getCurrentLocation,
      child: Container(
        height: 104,
        width: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF059669), Color(0xFF10B981)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: _isLocating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Icon(Icons.gps_fixed_rounded, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _buildPersonalitySlider({
    required String label,
    required double value,
    required String leftLabel,
    required String rightLabel,
    required ValueChanged<double> onChanged,
    required List<Color> gradient,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${value.toInt()}%',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFA78BFA),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 10,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(colors: gradient),
          ),
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 10,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              overlayColor: Colors.white.withValues(alpha: 0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10, elevation: 4),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: 100,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              leftLabel,
              style: GoogleFonts.notoSansTc(
                fontSize: 11,
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              rightLabel,
              style: GoogleFonts.notoSansTc(
                fontSize: 11,
                color: const Color(0xFF38BDF8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModernTextArea({
    required TextEditingController controller,
    required String hintText,
    required Color accentColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B132B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: TextField(
        controller: controller,
        maxLines: 3,
        style: GoogleFonts.notoSansTc(
          fontSize: 14,
          color: Colors.white,
          height: 1.5,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.notoSansTc(color: const Color(0xFF64748B), fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
        ),
      ),
    );
  }

  Widget _buildUnbindButton() {
    return Center(
      child: InkWell(
        onTap: widget.onUnbind,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.1),
            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4), width: 1.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.link_off_rounded, color: Color(0xFFEF4444), size: 18),
              const SizedBox(width: 8),
              Text(
                '解除與此長輩的綁定關係',
                style: GoogleFonts.notoSansTc(
                  color: const Color(0xFFEF4444),
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
