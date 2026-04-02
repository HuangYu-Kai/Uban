import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';

// =========================================================
// Section descriptor for the left-rail navigation
// =========================================================
class _Section {
  final IconData icon;
  final String label;
  final Color accent;
  const _Section(this.icon, this.label, this.accent);
}

const _sections = [
  _Section(Icons.person_rounded, '基本資料', Color(0xFF3B82F6)),
  _Section(Icons.health_and_safety_rounded, '健康備註', Color(0xFFF59E0B)),
  _Section(Icons.smart_toy_rounded, 'AI 人格', Color(0xFF8B5CF6)),
  _Section(Icons.auto_stories_rounded, '記憶庫', Color(0xFFEC4899)),
  _Section(Icons.favorite_rounded, '心跳關懷', Color(0xFFEF4444)),
];

// =========================================================
// Main Widget
// =========================================================
class FamilyAgentView extends StatefulWidget {
  final int userId;
  const FamilyAgentView({super.key, required this.userId});

  @override
  State<FamilyAgentView> createState() => _FamilyAgentViewState();
}

class _FamilyAgentViewState extends State<FamilyAgentView>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────
  List<dynamic> _elders = [];
  List<dynamic> _templates = [];
  dynamic _selectedElder;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isLocating = false;
  int _activeSection = 0;
  String? _selectedTemplateId;

  late final PageController _pageController;

  // ── Controllers ────────────────────────────────────────
  final _nameController        = TextEditingController();
  final _ageController         = TextEditingController();
  final _cityController        = TextEditingController();
  final _districtController    = TextEditingController();
  final _appellationController = TextEditingController();
  final _chronicController     = TextEditingController();
  final _medicationController  = TextEditingController();
  final _personaController     = TextEditingController();
  final _lifeStoryController   = TextEditingController();
  final _interestsController   = TextEditingController();

  // ── Sliders ────────────────────────────────────────────
  String _gender            = 'M';
  double _emotionTone       = 50;
  double _textVerbosity     = 50;
  int    _heartbeatFrequency = 0;

  // ──────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in [
      _nameController, _ageController, _cityController, _districtController,
      _appellationController, _chronicController, _medicationController,
      _personaController, _lifeStoryController, _interestsController,
    ]) { c.dispose(); }
    super.dispose();
  }

  // ── Data Loading ───────────────────────────────────────
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final elders    = await ApiService.getPairedElders(widget.userId);
    final templates = await ApiService.getPersonaTemplates();

    if (!mounted) return;
    setState(() {
      _elders    = elders;
      _templates = templates;
      _isLoading = false;
    });

    if (elders.isNotEmpty) await _selectElder(elders[0]);
  }

  Future<void> _selectElder(dynamic elder) async {
    setState(() => _selectedElder = elder);

    final userId = elder['user_id'] ?? elder['id'];
    final profile = await ApiService.getElderProfile(userId);
    if (!mounted) return;

    final data = profile['data'] ?? profile;
    setState(() {
      _nameController.text        = data['elder_name'] ?? elder['user_name'] ?? '';
      _ageController.text         = (data['age'] ?? elder['age'] ?? '').toString();
      _gender                     = data['gender'] ?? elder['gender'] ?? 'M';
      _appellationController.text = data['appellation'] ?? '';
      _chronicController.text     = data['chronic_diseases'] ?? '';
      _medicationController.text  = data['medication_notes'] ?? '';
      _interestsController.text   = data['interests'] ?? '';
      _personaController.text     = data['ai_persona'] ?? '親切的老年陪伴員';
      _lifeStoryController.text   = data['life_story'] ?? '';
      _heartbeatFrequency         = data['heartbeat_frequency'] ?? 0;
      _emotionTone                = (data['ai_emotion_tone'] ?? 50).toDouble();
      _textVerbosity              = (data['ai_text_verbosity'] ?? 50).toDouble();

      final fullLoc = data['location'] ?? elder['location'] ?? '';
      _parseLocation(fullLoc);
    });
  }

  void _parseLocation(String loc) {
    if (loc.isEmpty) return;
    final splitIdx = [loc.indexOf('市'), loc.indexOf('縣')]
        .where((i) => i != -1)
        .fold<int>(-1, (prev, e) => prev == -1 ? e : (e < prev ? e : prev));
    if (splitIdx != -1) {
      _cityController.text     = loc.substring(0, splitIdx + 1);
      _districtController.text = loc.substring(splitIdx + 1);
    } else {
      _cityController.text = loc;
    }
  }

  // ── Save ───────────────────────────────────────────────
  Future<void> _save() async {
    if (_selectedElder == null) return;
    setState(() => _isSaving = true);

    final userId   = _selectedElder['user_id'] ?? _selectedElder['id'];
    final familyId = widget.userId;
    final location = '${_cityController.text.trim()}${_districtController.text.trim()}';

    try {
      await ApiService.updateElderInfo(
        familyId: familyId,
        elderId:  userId,
        userName: _nameController.text.trim(),
        age:      int.tryParse(_ageController.text.trim()),
        gender:   _gender,
      );

      await ApiService.updateElderProfile(
        userId:             userId,
        location:           location,
        appellation:        _appellationController.text.trim(),
        aiEmotionTone:      _emotionTone.toInt(),
        aiTextVerbosity:    _textVerbosity.toInt(),
        chronicDiseases:    _chronicController.text.trim(),
        medicationNotes:    _medicationController.text.trim(),
        interests:          _interestsController.text.trim(),
        aiPersona:          _personaController.text.trim(),
        lifeStory:          _lifeStoryController.text.trim(),
        heartbeatFrequency: _heartbeatFrequency,
      );

      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ 設定已儲存，AI 將即時採用新的人格！',
              style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w700)),
          backgroundColor: const Color(0xFF16A34A),
          behavior:        SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('儲存失敗: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── GPS locate ─────────────────────────────────────────
  Future<void> _locateMe() async {
    setState(() => _isLocating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isNotEmpty && mounted) {
        setState(() {
          _cityController.text     = marks[0].administrativeArea ?? '';
          _districtController.text = marks[0].subAdministrativeArea ?? marks[0].locality ?? '';
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  // ── Navigate section ───────────────────────────────────
  void _jumpTo(int idx) {
    setState(() => _activeSection = idx);
    _pageController.animateToPage(
      idx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _applyTemplate(dynamic t) {
    setState(() {
      _selectedTemplateId  = t['id'] as String;
      _personaController.text = t['persona'] as String;
    });
  }

  // =========================================================
  // BUILD
  // =========================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _elders.isEmpty
              ? _emptyState()
              : _buildMain(),
    );
  }

  // ── Main layout ────────────────────────────────────────
  Widget _buildMain() {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: Row(
            children: [
              _buildRail(),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ],
    );
  }

  // ── Top Header ─────────────────────────────────────────
  Widget _buildHeader() {
    final elder = _selectedElder;
    final name  = elder?['user_name'] ?? elder?['elder_name'] ?? '長輩';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF334155)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 16, right: 16, bottom: 16,
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 2),
              image: DecorationImage(
                image: NetworkImage('${ApiService.baseUrl}/user/${elder?['id']}/avatar'),
                onError: (_, __) {},
                fit: BoxFit.cover,
              ),
              color: Colors.blueGrey[700],
            ),
            child: Center(
              child: Text(name.isNotEmpty ? name[0] : 'U',
                style: GoogleFonts.notoSansTc(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI 設定中心',
                  style: GoogleFonts.notoSansTc(color: Colors.white54, fontSize: 12)),
                Text(name,
                  style: GoogleFonts.notoSansTc(color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // Elder picker (if multiple)
          if (_elders.length > 1)
            GestureDetector(
              onTap: _showElderPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.swap_horiz, color: Colors.white70, size: 16),
                    const SizedBox(width: 4),
                    Text('切換', style: GoogleFonts.notoSansTc(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 8),
          // Save button
          GestureDetector(
            onTap: _isSaving ? null : _save,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF6366F1)]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Row(children: [
                      const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Text('儲存', style: GoogleFonts.notoSansTc(color: Colors.white, fontWeight: FontWeight.bold)),
                    ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Left Rail ──────────────────────────────────────────
  Widget _buildRail() {
    return Container(
      width: 72,
      color: const Color(0xFF1E293B),
      child: Column(
        children: List.generate(_sections.length, (i) {
          final sec       = _sections[i];
          final isActive  = _activeSection == i;
          return GestureDetector(
            onTap: () => _jumpTo(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: isActive ? sec.accent.withOpacity(0.15) : Colors.transparent,
                border: Border(
                  left: BorderSide(
                    color: isActive ? sec.accent : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Icon(sec.icon,
                    color: isActive ? sec.accent : Colors.white38,
                    size: 22),
                  const SizedBox(height: 4),
                  Text(sec.label,
                    style: GoogleFonts.notoSansTc(
                      color: isActive ? sec.accent : Colors.white38,
                      fontSize: 9.5,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.w400,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Content PageView ───────────────────────────────────
  Widget _buildContent() {
    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _pageBasic(),
        _pageHealth(),
        _pagePersona(),
        _pageMemory(),
        _pageHeartbeat(),
      ],
    );
  }

  // =========================================================
  // PAGES
  // =========================================================

  // — Page 0: Basic Info ————————————————————————————————
  Widget _pageBasic() => _scrollPage([
    _cardSection('真實姓名', Icons.badge_rounded, const Color(0xFF3B82F6), [
      _inputField(_nameController, '長輩姓名', Icons.person_outline),
    ]),
    _cardSection('性別 & 年齡', Icons.wc_rounded, const Color(0xFF3B82F6), [
      Row(children: [
        Expanded(child: _genderToggle()),
        const SizedBox(width: 12),
        Expanded(child: _inputField(
          _ageController, '年齡', Icons.cake_outlined,
          inputType: TextInputType.number,
        )),
      ]),
    ]),
    _cardSection('居住地區', Icons.location_on_rounded, const Color(0xFF10B981), [
      Row(children: [
        Expanded(child: Column(children: [
          _inputField(_cityController, '縣 / 市', Icons.location_city_rounded),
          const SizedBox(height: 8),
          _inputField(_districtController, '鄉鎮市區', Icons.map_rounded),
        ])),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: _isLocating ? null : _locateMe,
          child: Container(
            height: 108, width: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF059669)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Center(child: _isLocating
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.gps_fixed_rounded, color: Colors.white, size: 24)),
          ),
        ),
      ]),
    ]),
    _cardSection('AI 稱呼設定', Icons.record_voice_over_rounded, const Color(0xFF6366F1), [
      Text('AI 將如何稱呼長輩？（例：奶奶、爺爺、王伯伯）',
        style: GoogleFonts.notoSansTc(color: Colors.grey[600], fontSize: 12)),
      const SizedBox(height: 10),
      _inputField(_appellationController, 'AI 對長輩的稱呼', Icons.record_voice_over_outlined),
    ]),
  ]);

  // — Page 1: Health ————————————————————————————————————
  Widget _pageHealth() => _scrollPage([
    _cardSection('慢性病史與過敏', Icons.medical_information_rounded, const Color(0xFFF59E0B), [
      _textArea(_chronicController, '例如：高血壓、對盤尼西林過敏...'),
    ]),
    _cardSection('每日用藥提醒', Icons.medication_rounded, const Color(0xFFEF4444), [
      _textArea(_medicationController, '例如：早晚飯後需服用高血壓藥...'),
    ]),
  ]);

  // — Page 2: AI Persona ————————————————————————————————
  Widget _pagePersona() => _scrollPage([
    _cardSection('快速套用人格範本', Icons.style_rounded, const Color(0xFF8B5CF6), [
      Text('選擇一個預設風格，AI 就會以此角色與長輩互動',
        style: GoogleFonts.notoSansTc(color: Colors.grey[600], fontSize: 12)),
      const SizedBox(height: 12),
      _templateGrid(),
    ]),
    _cardSection('自訂人格說明', Icons.edit_note_rounded, const Color(0xFF8B5CF6), [
      Text('點擊範本後可在此修改微調，讓 AI 更像你設想的角色',
        style: GoogleFonts.notoSansTc(color: Colors.grey[600], fontSize: 12)),
      const SizedBox(height: 10),
      _textArea(_personaController, '例如：你是一個調皮的孫子，喜歡分享生活小事...', maxLines: 5),
    ]),
    _cardSection('語氣與話量調整', Icons.tune_rounded, const Color(0xFF6366F1), [
      _gradientSlider(
        label: '陪伴語氣',
        value: _emotionTone,
        leftLabel: '客觀專業',
        rightLabel: '熱情親切',
        onChanged: (v) => setState(() => _emotionTone = v),
        gradColors: const [Color(0xFF6366F1), Color(0xFFEC4899)],
      ),
      const SizedBox(height: 24),
      _gradientSlider(
        label: '回覆話量',
        value: _textVerbosity,
        leftLabel: '簡潔扼要',
        rightLabel: '滔滔不絕',
        onChanged: (v) => setState(() => _textVerbosity = v),
        gradColors: const [Color(0xFF10B981), Color(0xFF3B82F6)],
      ),
    ]),
  ]);

  // — Page 3: Memory ————————————————————————————————————
  Widget _pageMemory() => _scrollPage([
    _cardSection('長輩的生命故事', Icons.auto_stories_rounded, const Color(0xFFEC4899), [
      Text('讓 AI 知道長輩的過去，對話時更能找到共鳴的話題',
        style: GoogleFonts.notoSansTc(color: Colors.grey[600], fontSize: 12)),
      const SizedBox(height: 10),
      _textArea(_lifeStoryController, '例如：年輕時在台南務農，退休後愛看戲曲，有三個孩子...', maxLines: 6),
    ]),
    _cardSection('興趣與喜好', Icons.favorite_rounded, const Color(0xFFEC4899), [
      Text('讓 AI 能主動聊起長輩感興趣的話題',
        style: GoogleFonts.notoSansTc(color: Colors.grey[600], fontSize: 12)),
      const SizedBox(height: 10),
      _textArea(_interestsController, '例如：喜歡聽鄧麗君、愛看連續劇、喜歡下棋...'),
    ]),
  ]);

  // — Page 4: Heartbeat ─────────────────────────────────
  Widget _pageHeartbeat() => _scrollPage([
    _cardSection('自然心跳關懷', Icons.favorite_rounded, const Color(0xFFEF4444), [
      Text('AI 會在長輩安靜一段時間後，主動以語音傳送關心話語',
        style: GoogleFonts.notoSansTc(color: Colors.grey[600], fontSize: 12)),
      const SizedBox(height: 20),
      _heartbeatSlider(),
    ]),
    _infoCard(
      '💡 運作方式',
      '系統每分鐘偵測長輩是否長時間安靜。當超過設定時間，AI 將根據當下時間與天氣，'
      '判斷是否適合主動問候（深夜或剛結束對話的時候 AI 會選擇保持安靜）。',
    ),
  ]);

  // =========================================================
  // REUSABLE COMPONENTS
  // =========================================================

  Widget _scrollPage(List<Widget> children) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _sections[_activeSection].accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_sections[_activeSection].icon,
                color: _sections[_activeSection].accent, size: 20),
            ),
            const SizedBox(width: 10),
            Text(_sections[_activeSection].label,
              style: GoogleFonts.notoSansTc(
                fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
          ]),
          const SizedBox(height: 16),
          ...children,
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _cardSection(String title, IconData icon, Color accent, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: accent.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: accent, size: 18),
                ),
                const SizedBox(width: 10),
                Text(title, style: GoogleFonts.notoSansTc(
                  fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade100),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(String title, String body) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF475569))),
          const SizedBox(height: 8),
          Text(body, style: GoogleFonts.notoSansTc(color: const Color(0xFF64748B), fontSize: 13, height: 1.6)),
        ],
      ),
    );
  }

  Widget _inputField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType inputType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: inputType,
        style: GoogleFonts.notoSansTc(fontSize: 15, color: const Color(0xFF1E293B)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.notoSansTc(color: const Color(0xFF94A3B8), fontSize: 14),
          prefixIcon: Icon(icon, color: const Color(0xFF94A3B8), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        ),
      ),
    );
  }

  Widget _genderToggle() {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(children: [
        _genderBtn('男', _gender == 'M', () => setState(() => _gender = 'M')),
        _genderBtn('女', _gender == 'F', () => setState(() => _gender = 'F')),
      ]),
    );
  }

  Widget _genderBtn(String label, bool isActive, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)] : [],
          ),
          child: Text(label, style: GoogleFonts.notoSansTc(
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: isActive ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8),
          )),
        ),
      ),
    );
  }

  Widget _textArea(TextEditingController ctrl, String hint, {int maxLines = 4}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: GoogleFonts.notoSansTc(fontSize: 14, color: const Color(0xFF1E293B), height: 1.6),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.notoSansTc(color: const Color(0xFF94A3B8), fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
        ),
      ),
    );
  }

  Widget _templateGrid() {
    if (_templates.isEmpty) return const SizedBox.shrink();

    final icons = {
      'grandson': ('👦', const Color(0xFFEFF6FF), const Color(0xFF2563EB)),
      'old_friend': ('🧓', const Color(0xFFFFF7ED), const Color(0xFFEA580C)),
      'butler': ('🎩', const Color(0xFFF0FDF4), const Color(0xFF16A34A)),
    };

    return GridView.count(
      crossAxisCount: 3,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 0.9,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: _templates.map((t) {
        final id       = t['id'] as String;
        final isActive = _selectedTemplateId == id;
        final style    = icons[id] ?? ('🤖', const Color(0xFFF5F5F5), Colors.blueGrey);
        return GestureDetector(
          onTap: () => _applyTemplate(t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isActive ? style.$3 : style.$2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: style.$3.withOpacity(isActive ? 1 : 0.2), width: isActive ? 2 : 1),
              boxShadow: isActive ? [BoxShadow(color: style.$3.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))] : [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(style.$1, style: const TextStyle(fontSize: 30)),
                const SizedBox(height: 6),
                Text(t['name'], style: GoogleFonts.notoSansTc(
                  fontSize: 13, fontWeight: FontWeight.bold,
                  color: isActive ? Colors.white : style.$3)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _gradientSlider({
    required String label,
    required double value,
    required String leftLabel,
    required String rightLabel,
    required ValueChanged<double> onChanged,
    required List<Color> gradColors,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.notoSansTc(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF374151))),
        const SizedBox(height: 10),
        Container(
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(colors: gradColors),
          ),
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 12,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              overlayColor: Colors.white.withOpacity(0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11, elevation: 4),
            ),
            child: Slider(value: value, min: 0, max: 100, onChanged: onChanged),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(leftLabel,  style: GoogleFonts.notoSansTc(fontSize: 11, color: const Color(0xFF9CA3AF))),
            Text(rightLabel, style: GoogleFonts.notoSansTc(fontSize: 11, color: const Color(0xFF9CA3AF))),
          ],
        ),
      ],
    );
  }

  Widget _heartbeatSlider() {
    final opts   = [0, 30, 60, 120, 180];
    final labels = ['關閉', '30 分', '1 小時', '2 小時', '3 小時'];
    int idx = opts.indexOf(_heartbeatFrequency);
    if (idx == -1) idx = 0;

    final isOn = _heartbeatFrequency > 0;

    return Column(
      children: [
        // Status badge
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isOn
                  ? const [Color(0xFFDC2626), Color(0xFFEF4444)]
                  : const [Color(0xFF94A3B8), Color(0xFF64748B)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            Text(isOn ? '💓' : '💤', style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(isOn ? '主動關懷已開啟' : '主動關懷已關閉',
                style: GoogleFonts.notoSansTc(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              Text(isOn ? '每 ${labels[idx]} 主動問候長輩' : 'AI 只會被動回應',
                style: GoogleFonts.notoSansTc(color: Colors.white70, fontSize: 12)),
            ]),
          ]),
        ),
        const SizedBox(height: 24),

        // Slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 8,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 13),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
            activeTrackColor: const Color(0xFFEF4444),
            inactiveTrackColor: Colors.grey.shade200,
            thumbColor: const Color(0xFFEF4444),
            overlayColor: const Color(0xFFEF4444).withOpacity(0.1),
          ),
          child: Slider(
            value: idx.toDouble(),
            min: 0,
            max: (opts.length - 1).toDouble(),
            divisions: opts.length - 1,
            onChanged: (v) => setState(() => _heartbeatFrequency = opts[v.round()]),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: labels.map((l) =>
            Text(l, style: GoogleFonts.notoSansTc(fontSize: 11, color: Colors.grey[500]))
          ).toList(),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🤖', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text('尚未配對任何長輩', style: GoogleFonts.notoSansTc(
            fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black54)),
          const SizedBox(height: 8),
          Text('請到「設定」頁面配對長輩設備', style: GoogleFonts.notoSansTc(color: Colors.grey)),
        ],
      ),
    );
  }

  void _showElderPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(20),
        children: [
          Text('選擇長輩', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 12),
          ..._elders.map((e) => ListTile(
            title: Text(e['user_name'] ?? ''),
            onTap: () { Navigator.pop(ctx); _selectElder(e); },
          )),
        ],
      ),
    );
  }
}
