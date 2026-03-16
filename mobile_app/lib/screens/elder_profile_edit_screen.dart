import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../services/api_service.dart';

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

    String location = widget.elderData['location'] ?? '';
    String initialCity = '';
    String initialDistrict = '';

    if (location.isNotEmpty) {
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
      } else {
        initialCity = location;
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
          const SnackBar(content: Text('資料已成功更新 ✨ AI 將採用新的設定')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('儲存失敗: $e')),
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
          SnackBar(content: Text('無法取得位置: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(
        '編輯長輩資料',
        style: GoogleFonts.notoSansTc(
          color: const Color(0xFF1F2937),
          fontWeight: FontWeight.w800,
          fontSize: 20,
        ),
      ),
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: Color(0xFF4B5563)),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        if (!_isLoading)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isSaving ? null : _saveProfile,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      '儲存',
                      style: GoogleFonts.notoSansTc(
                        color: const Color(0xFF3B82F6),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
      ],
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            title: '基本身分資料',
            icon: Icons.person_rounded,
            color: const Color(0xFF3B82F6),
            children: [
              _buildInputLabel('真實姓名'),
              _buildModernTextField(
                controller: _nameController,
                hintText: '請輸入長輩姓名',
                icon: Icons.badge_outlined,
              ),
              const SizedBox(height: 20),
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
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
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
          ),
          
          const SizedBox(height: 24),
          
          _buildInfoCard(
            title: '生活地區',
            icon: Icons.location_on_rounded,
            color: const Color(0xFF10B981),
            children: [
              _buildInputLabel('主要居住地 (用於天氣與活動建議)'),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _buildModernTextField(
                          controller: _cityController,
                          hintText: '縣/市',
                          icon: Icons.location_city_rounded,
                        ),
                        const SizedBox(height: 12),
                        _buildModernTextField(
                          controller: _districtController,
                          hintText: '鄉鎮市區',
                          icon: Icons.map_rounded,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildLocateButton(),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          _buildInfoCard(
            title: 'AI 陪伴助手設定',
            icon: Icons.auto_awesome_rounded,
            color: const Color(0xFF8B5CF6),
            children: [
              _buildInputLabel('長輩對 AI 的稱呼 (例：奶奶)'),
              _buildModernTextField(
                controller: _appellationController,
                hintText: 'AI 將以此稱呼長輩',
                icon: Icons.record_voice_over_rounded,
              ),
              const SizedBox(height: 24),
              _buildPersonalitySlider(
                label: '陪伴語氣',
                value: _aiEmotionTone,
                leftLabel: '客觀專業',
                rightLabel: '熱情親切',
                onChanged: (v) => setState(() => _aiEmotionTone = v),
                gradient: const [Color(0xFF6366F1), Color(0xFFEC4899)],
              ),
              const SizedBox(height: 24),
              _buildPersonalitySlider(
                label: '話匣子開關',
                value: _aiTextVerbosity,
                leftLabel: '簡潔扼要',
                rightLabel: '滔滔不絕',
                onChanged: (v) => setState(() => _aiTextVerbosity = v),
                gradient: const [Color(0xFF10B981), Color(0xFF3B82F6)],
              ),
            ],
          ),

          const SizedBox(height: 24),

          _buildInfoCard(
            title: '健康與護理備註',
            icon: Icons.health_and_safety_rounded,
            color: const Color(0xFFF59E0B),
            children: [
              _buildInputLabel('慢性病史或過敏史'),
              _buildModernTextArea(
                controller: _chronicDiseasesController,
                hintText: '例如：高血壓、對盤尼西林過敏...',
              ),
              const SizedBox(height: 20),
              _buildInputLabel('每日用藥提醒'),
              _buildModernTextArea(
                controller: _medicationNotesController,
                hintText: '例如：早晚飯後需服用高血壓藥...',
              ),
            ],
          ),

          const SizedBox(height: 24),

          _buildInfoCard(
            title: '個人興趣與記憶',
            icon: Icons.favorite_rounded,
            color: const Color(0xFFEF4444),
            children: [
              _buildInputLabel('讓 AI 更懂他 (興趣、教職經歷等)'),
              _buildModernTextArea(
                controller: _interestsController,
                hintText: '例如：喜歡聽鄧麗君、愛聊園藝...',
              ),
            ],
          ),

          if (widget.onUnbind != null) ...[
            const SizedBox(height: 40),
            _buildUnbindButton(),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.1)),
          Padding(
            padding: const EdgeInsets.all(20),
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
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: GoogleFonts.notoSansTc(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF6B7280),
        ),
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: GoogleFonts.inter(fontSize: 16, color: const Color(0xFF111827), fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.notoSansTc(color: const Color(0xFF9CA3AF), fontSize: 15),
          prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 20),
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
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          _buildGenderBtn('男', _currentGender == 'M', () => setState(() => _currentGender = 'M')),
          _buildGenderBtn('女', _currentGender == 'F', () => setState(() => _currentGender = 'F')),
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
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))]
                : [],
          ),
          child: Text(
            label,
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF6B7280),
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
        height: 108,
        width: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF10B981), Color(0xFF059669)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: _isLocating
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
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
        Text(
          label,
          style: GoogleFonts.notoSansTc(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(colors: gradient),
          ),
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 12,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              overlayColor: Colors.white.withValues(alpha: 0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12, elevation: 4),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: 100,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(leftLabel, style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF9CA3AF), fontWeight: FontWeight.w600)),
            Text(rightLabel, style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF9CA3AF), fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _buildModernTextArea({
    required TextEditingController controller,
    required String hintText,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: TextField(
        controller: controller,
        maxLines: 4,
        style: GoogleFonts.notoSansTc(fontSize: 15, color: const Color(0xFF111827), height: 1.5),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.notoSansTc(color: const Color(0xFF9CA3AF), fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFFEE2E2)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.link_off_rounded, color: Color(0xFFEF4444), size: 20),
              const SizedBox(width: 8),
              Text(
                '解除與此長輩的綁定關係',
                style: GoogleFonts.notoSansTc(
                  color: const Color(0xFFEF4444),
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
