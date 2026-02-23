import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import 'qr_scanner_screen.dart';
import 'elder_selection_screen.dart';

class CaregiverPairingScreen extends StatefulWidget {
  final int familyId;
  final String familyName;

  const CaregiverPairingScreen({
    super.key,
    required this.familyId,
    required this.familyName,
  });

  @override
  State<CaregiverPairingScreen> createState() => _CaregiverPairingScreenState();
}

class _CaregiverPairingScreenState extends State<CaregiverPairingScreen> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController(
    text: '70',
  );
  String _gender = 'M';
  bool _isLoading = false;

  Future<void> _handleConfirmPairing() async {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    final age = int.tryParse(_ageController.text.trim()) ?? 70;

    if (code.length != 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請輸入 4 位配對碼')));
      return;
    }

    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請輸入長輩姓名')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await ApiService.confirmPairing(
        familyId: widget.familyId,
        code: code,
        elderName: name,
        gender: _gender,
        age: age,
      );

      if (!mounted) return;

      if (result.containsKey('elder_id')) {
        // 配對成功！
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('配對成功！已建立守護關係 ✨'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            backgroundColor: Colors.green[600],
          ),
        );

        // 配對完成後，導向長輩選擇頁面（子女端首頁）
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => ElderSelectionScreen(
              userId: widget.familyId,
              userName: widget.familyName,
            ),
          ),
          (route) => false, // 清除所有舊頁面，防止回到配對或引導頁
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('配對失敗：${result['error']}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('連線錯誤：$e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '新增長輩連結',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF1E293B),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  const Icon(
                    Icons.favorite,
                    size: 64,
                    color: Color(0xFF2563EB),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '建立守護關係',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '請查看長輩平板/電視上的 4 位數配對碼\n並填寫長輩的資訊開始守護',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansTc(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            _buildSectionLabel('1. 輸入配對碼'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    style: GoogleFonts.inter(
                      letterSpacing: 4,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: _inputDecoration(
                      Icons.vpn_key_rounded,
                      '4 位數字',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 56,
                  width: 56,
                  child: IconButton.filled(
                    onPressed: () async {
                      final result = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const QrScannerScreen(),
                        ),
                      );
                      if (result != null && mounted) {
                        setState(() => _codeController.text = result);
                      }
                    },
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSectionLabel('2. 長輩基本資訊'),
            TextField(
              controller: _nameController,
              decoration: _inputDecoration(
                Icons.person_add_rounded,
                '長輩名稱 (例如：王大明)',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration(Icons.cake_rounded, '年齡'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        _genderChoice(
                          label: '男',
                          isSelected: _gender == 'M',
                          onTap: () => setState(() => _gender = 'M'),
                        ),
                        _genderChoice(
                          label: '女',
                          isSelected: _gender == 'F',
                          onTap: () => setState(() => _gender = 'F'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleConfirmPairing,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        '開始配對',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        label,
        style: GoogleFonts.notoSansTc(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF1E293B),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(IconData icon, String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.notoSansTc(color: Colors.grey[600], fontSize: 14),
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF64748B)),
      filled: true,
      fillColor: Colors.grey[100],
      counterText: "",
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
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
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? const Color(0xFF2563EB) : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }
}
