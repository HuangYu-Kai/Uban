import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  late TextEditingController _locationController;
  late TextEditingController _phoneController;

  late TextEditingController _chronicDiseasesController;
  late TextEditingController _medicationNotesController;
  late TextEditingController _interestsController;

  // 基本資料 - 性別
  String _currentGender = 'M';

  // AI 性格偏好
  String _aiPersona = '溫暖孫子';
  final List<String> _personaOptions = ['溫暖孫子', '專業護理師', '老朋友', '細心女兒'];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.elderData['user_name'] ?? widget.elderData['name'],
    );
    _ageController = TextEditingController(
      text: widget.elderData['age']?.toString(),
    );
    _locationController = TextEditingController();
    _phoneController = TextEditingController();
    _chronicDiseasesController = TextEditingController();
    _medicationNotesController = TextEditingController();
    _interestsController = TextEditingController();
    _currentGender = widget.elderData['gender'] ?? 'M';

    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final elderId = widget.elderData['id'];
      if (elderId == null) {
        setState(() => _isLoading = false);
        return;
      }

      final profile = await ApiService.getElderProfile(elderId);
      if (mounted) {
        setState(() {
          _phoneController.text = profile['phone'] ?? '';
          _locationController.text = profile['location'] ?? '台北市士林區';
          _aiPersona = profile['ai_persona'] ?? '溫暖孫子';
          if (!_personaOptions.contains(_aiPersona)) {
            _aiPersona = '溫暖孫子';
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

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _locationController.dispose();
    _phoneController.dispose();
    _chronicDiseasesController.dispose();
    _medicationNotesController.dispose();
    _interestsController.dispose();
    super.dispose();
  }

  void _saveProfile() async {
    final elderId = widget.elderData['id'];
    if (elderId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('無法儲存：無效的長輩 ID')));
      return;
    }

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
        phone: _phoneController.text,
        location: _locationController.text,
        aiPersona: _aiPersona,
        chronicDiseases: _chronicDiseasesController.text,
        medicationNotes: _medicationNotesController.text,
        interests: _interestsController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('資料已成功更新，AI 將採用新的設定與性格。')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('儲存失敗: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(
            '編輯長輩資料',
            style: GoogleFonts.notoSansTc(
              color: const Color(0xFF1E293B),
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          '編輯長輩資料',
          style: GoogleFonts.notoSansTc(
            color: const Color(0xFF1E293B),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
        actions: [
          TextButton(
            onPressed: _saveProfile,
            child: Text(
              '儲存',
              style: GoogleFonts.notoSansTc(
                color: const Color(0xFF2563EB),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('基本身分資料'),
            _buildTextField(
              controller: _nameController,
              label: '稱呼 (AI 將如何稱呼長輩)',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _ageController,
                    label: '年齡',
                    icon: Icons.cake_outlined,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        _genderChoice(
                          label: '男',
                          isSelected: _currentGender == 'M',
                          onTap: () => setState(() => _currentGender = 'M'),
                        ),
                        _genderChoice(
                          label: '女',
                          isSelected: _currentGender == 'F',
                          onTap: () => setState(() => _currentGender = 'F'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _phoneController,
              label: '聯絡電話',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _locationController,
              label: '居住地區 (用於精準天氣預報)',
              icon: Icons.location_on_outlined,
            ),
            const SizedBox(height: 32),

            _buildSectionTitle('健康與護理備註'),
            _buildTextArea(
              controller: _chronicDiseasesController,
              label: '慢性病史或過敏史',
              hint: '例如：高血壓、對盤尼西林過敏...',
            ),
            const SizedBox(height: 16),
            _buildTextArea(
              controller: _medicationNotesController,
              label: '每日用藥提醒備註',
              hint: '例如：早晚飯後需服用高血壓藥...',
            ),
            const SizedBox(height: 32),

            _buildSectionTitle('AI 性格與陪伴偏好'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI 陪伴角色設定',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _aiPersona,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                    items: _personaOptions.map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value, style: GoogleFonts.notoSansTc()),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      setState(() {
                        _aiPersona = newValue!;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'AI 將採用此人設的說話方式與長輩互動，例如「溫暖孫子」會更常撒嬌與關心，「專業護理師」會更著重健康提醒。',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 13,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildTextArea(
              controller: _interestsController,
              label: '專屬話題與興趣',
              hint: '例如：喜歡聽鄧麗君的歌、以前是老師、愛聊園藝...',
            ),
            if (widget.familyId != null && widget.onUnbind != null) ...[
              const SizedBox(height: 32),
              Center(
                child: TextButton.icon(
                  onPressed: widget.onUnbind,
                  icon: const Icon(
                    Icons.delete_forever,
                    color: Colors.redAccent,
                  ),
                  label: Text(
                    '解除綁定並刪除資料',
                    style: GoogleFonts.notoSansTc(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 48), // Bottom padding
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title,
        style: GoogleFonts.notoSansTc(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF1E293B),
        ),
      ),
    );
  }

  Widget _genderChoice({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.notoSansTc(color: Colors.grey[600]),
        prefixIcon: Icon(icon, color: const Color(0xFF2563EB)),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
        ),
      ),
    );
  }

  Widget _buildTextArea({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.notoSansTc(color: Colors.grey[600]),
        alignLabelWithHint: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
        ),
      ),
    );
  }
}
