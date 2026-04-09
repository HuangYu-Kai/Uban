import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';

class FamilyAgentView extends StatefulWidget {
  final int userId;
  const FamilyAgentView({super.key, required this.userId});

  @override
  State<FamilyAgentView> createState() => _FamilyAgentViewState();
}

class _FamilyAgentViewState extends State<FamilyAgentView> {
  List<dynamic> _elders    = [];
  List<dynamic> _templates = [];
  dynamic _selectedElder;
  bool _isLoading  = true;
  bool _isSaving   = false;
  bool _isLocating = false;
  String? _selectedTemplateId;

  // Controllers
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

  String _gender             = 'M';
  double _emotionTone        = 50;
  double _textVerbosity      = 50;
  int    _heartbeatFrequency = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final c in [
      _nameController, _ageController, _cityController, _districtController,
      _appellationController, _chronicController, _medicationController,
      _personaController, _lifeStoryController, _interestsController,
    ]) { c.dispose(); }
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────
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

    final userId  = elder['user_id'] ?? elder['id'];
    final profile = await ApiService.getElderProfile(userId);
    if (!mounted) return;

    final data = (profile['data'] is Map) ? profile['data'] : profile;
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
      _parseLocation(data['location'] ?? elder['location'] ?? '');
      _selectedTemplateId         = null;
    });
  }

  void _parseLocation(String loc) {
    if (loc.isEmpty) return;
    final splitIdx = [loc.indexOf('市'), loc.indexOf('縣')]
        .where((i) => i != -1)
        .fold<int>(-1, (p, e) => p == -1 ? e : (e < p ? e : p));
    if (splitIdx != -1) {
      _cityController.text     = loc.substring(0, splitIdx + 1);
      _districtController.text = loc.substring(splitIdx + 1);
    } else {
      _cityController.text = loc;
    }
  }

  // ── Save ──────────────────────────────────────────────
  Future<void> _save() async {
    if (_selectedElder == null) return;
    setState(() => _isSaving = true);
    final userId   = _selectedElder['user_id'] ?? _selectedElder['id'];

    try {
      await ApiService.updateElderInfo(
        familyId: widget.userId,
        elderId:  userId,
        userName: _nameController.text.trim(),
        age:      int.tryParse(_ageController.text.trim()),
        gender:   _gender,
      );
      await ApiService.updateElderProfile(
        userId:             userId,
        location:           '${_cityController.text.trim()}${_districtController.text.trim()}',
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ 資料已儲存，AI 將即時採用新設定！',
            style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('儲存失敗: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _locateMe() async {
    setState(() => _isLocating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos   = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
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

  void _applyTemplate(dynamic t) {
    setState(() {
      _selectedTemplateId     = t['id'] as String;
      _personaController.text = t['persona'] as String;
    });
    HapticFeedback.selectionClick();
  }

  // =========================================================
  // BUILD
  // =========================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
          : _elders.isEmpty
              ? _emptyState()
              : _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final name = _selectedElder?['user_name'] ?? _selectedElder?['elder_name'] ?? '長輩';
    return AppBar(
      backgroundColor: Colors.white,
      centerTitle: true,
      elevation: 0,
      surfaceTintColor: Colors.white,
      title: Column(
        children: [
          Text('AI 陪伴設定',
              style: GoogleFonts.notoSansTc(
                  fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
          if (_selectedElder != null)
            Text('正在設定：$name',
                style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF2563EB),
                    fontWeight: FontWeight.w600)),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _isSaving
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2563EB)),
                  ))
              : TextButton(
                  onPressed: _selectedElder != null ? _save : null,
                  child: Text('儲存',
                      style: GoogleFonts.notoSansTc(
                          color: const Color(0xFF2563EB),
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Elder selector ─────────────────────────────────
          if (_elders.length > 1) ...[
            _elderSelector(),
            const SizedBox(height: 20),
          ],

          // ── 1. 基本資料 ────────────────────────────────────
          _infoCard(
            title: '基本資料',
            icon: Icons.person_rounded,
            accent: const Color(0xFF3B82F6),
            children: [
              _label('真實姓名'),
              _field(_nameController, '請輸入長輩姓名', Icons.badge_outlined),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('年齡'),
                  _field(_ageController, '歲數', Icons.cake_outlined,
                      inputType: TextInputType.number),
                ])),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('性別'),
                  _genderToggle(),
                ])),
              ]),
            ],
          ).animate().fadeIn(delay: 50.ms).slideY(begin: 0.06, end: 0),

          const SizedBox(height: 20),

          // ── 2. 居住地區 ────────────────────────────────────
          _infoCard(
            title: '居住地區',
            icon: Icons.location_on_rounded,
            accent: const Color(0xFF10B981),
            children: [
              _label('主要居住地 (天氣與 AI 關懷參考)'),
              Row(children: [
                Expanded(child: Column(children: [
                  _field(_cityController, '縣 / 市', Icons.location_city_rounded),
                  const SizedBox(height: 10),
                  _field(_districtController, '鄉鎮市區', Icons.map_rounded),
                ])),
                const SizedBox(width: 12),
                _locateButton(),
              ]),
            ],
          ).animate().fadeIn(delay: 80.ms).slideY(begin: 0.06, end: 0),

          const SizedBox(height: 20),

          // ── 3. 健康備註 ─────────────────────────────────────
          _infoCard(
            title: '健康備註',
            icon: Icons.health_and_safety_rounded,
            accent: const Color(0xFFF59E0B),
            children: [
              _label('慢性病史或過敏史'),
              _area(_chronicController, '例如：高血壓、對盤尼西林過敏...'),
              const SizedBox(height: 18),
              _label('每日用藥提醒'),
              _area(_medicationController, '例如：早晚飯後需服用高血壓藥...'),
            ],
          ).animate().fadeIn(delay: 110.ms).slideY(begin: 0.06, end: 0),

          const SizedBox(height: 20),

          // ── 4. AI 角色設定 ──────────────────────────────────
          _infoCard(
            title: 'AI 陪伴角色',
            icon: Icons.smart_toy_rounded,
            accent: const Color(0xFF8B5CF6),
            children: [
              _label('快速套用人格範本'),
              const SizedBox(height: 10),
              _templateCards(),
              const SizedBox(height: 18),
              _label('自訂角色描述（可在套用範本後微調）'),
              _area(_personaController,
                  '例如：你是一個調皮的孫子，喜歡分享生活小事...', maxLines: 4),
              const SizedBox(height: 18),
              _label('AI 對長輩的稱呼'),
              _field(_appellationController, '例如：奶奶、王伯伯',
                  Icons.record_voice_over_rounded),
              const SizedBox(height: 24),
              _gradientSlider(
                label: '陪伴語氣',
                value: _emotionTone,
                leftLabel: '客觀專業',
                rightLabel: '熱情親切',
                onChanged: (v) => setState(() => _emotionTone = v),
                colors: const [Color(0xFF6366F1), Color(0xFFEC4899)],
              ),
              const SizedBox(height: 20),
              _gradientSlider(
                label: '回覆話量',
                value: _textVerbosity,
                leftLabel: '簡潔扼要',
                rightLabel: '滔滔不絕',
                onChanged: (v) => setState(() => _textVerbosity = v),
                colors: const [Color(0xFF10B981), Color(0xFF3B82F6)],
              ),
            ],
          ).animate().fadeIn(delay: 140.ms).slideY(begin: 0.06, end: 0),

          const SizedBox(height: 20),

          // ── 5. 記憶庫 ──────────────────────────────────────
          _infoCard(
            title: '個人記憶庫',
            icon: Icons.auto_stories_rounded,
            accent: const Color(0xFFEC4899),
            children: [
              _label('長輩的生命故事'),
              Text('讓 AI 了解背景，聊天時更能找到共鳴話題',
                  style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF94A3B8))),
              const SizedBox(height: 10),
              _area(_lifeStoryController,
                  '例如：年輕時在台南務農，退休後愛看戲曲，有三個孩子...', maxLines: 5),
              const SizedBox(height: 18),
              _label('興趣與喜好'),
              _area(_interestsController, '例如：喜歡聽鄧麗君、愛看連續劇、喜歡下棋...'),
            ],
          ).animate().fadeIn(delay: 170.ms).slideY(begin: 0.06, end: 0),

          const SizedBox(height: 20),

          // ── 6. 心跳設定 ────────────────────────────────────
          _infoCard(
            title: '自然心跳關懷',
            icon: Icons.favorite_rounded,
            accent: const Color(0xFFEF4444),
            children: [
              Text('AI 會在長輩安靜一段時間後，主動以語音送上關心（深夜或剛結束對話時 AI 會選擇不打擾）',
                  style: GoogleFonts.notoSansTc(
                      fontSize: 12, color: const Color(0xFF64748B), height: 1.5)),
              const SizedBox(height: 20),
              _heartbeatWidget(),
            ],
          ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.06, end: 0),
        ],
      ),
    );
  }

  // =========================================================
  // COMPONENTS
  // =========================================================

  Widget _infoCard({
    required String title,
    required IconData icon,
    required Color accent,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.07), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 10),
            Text(title, style: GoogleFonts.notoSansTc(
                fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF111827))),
          ]),
        ),
        Divider(height: 1, color: Colors.grey.shade100),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ]),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: GoogleFonts.notoSansTc(
                fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF6B7280))),
      );

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType inputType = TextInputType.text,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: TextField(
          controller: ctrl,
          keyboardType: inputType,
          style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF111827), fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.notoSansTc(color: const Color(0xFF9CA3AF), fontSize: 14),
            prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      );

  Widget _area(TextEditingController ctrl, String hint, {int maxLines = 3}) =>
      Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: GoogleFonts.notoSansTc(fontSize: 14, color: const Color(0xFF111827), height: 1.6),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.notoSansTc(color: const Color(0xFF9CA3AF), fontSize: 13),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      );

  Widget _genderToggle() => Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(children: [
          _gBtn('男', _gender == 'M', () => setState(() => _gender = 'M')),
          _gBtn('女', _gender == 'F', () => setState(() => _gender = 'F')),
        ]),
      );

  Widget _gBtn(String label, bool active, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: active
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]
                  : [],
            ),
            child: Text(label,
                style: GoogleFonts.notoSansTc(
                    fontWeight: active ? FontWeight.bold : FontWeight.w500,
                    color: active ? const Color(0xFF3B82F6) : const Color(0xFF6B7280))),
          ),
        ),
      );

  Widget _locateButton() => GestureDetector(
        onTap: _isLocating ? null : _locateMe,
        child: Container(
          height: 108,
          width: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF10B981), Color(0xFF059669)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: 0.3),
                blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Center(child: _isLocating
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.gps_fixed_rounded, color: Colors.white, size: 24)),
        ),
      );

  Widget _templateCards() {
    if (_templates.isEmpty) return const SizedBox.shrink();

    final styles = {
      'grandson':   ('👦', const Color(0xFFEFF6FF), const Color(0xFF2563EB)),
      'old_friend': ('🧓', const Color(0xFFFFF7ED), const Color(0xFFEA580C)),
      'butler':     ('🎩', const Color(0xFFF0FDF4), const Color(0xFF16A34A)),
    };

    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _templates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (ctx, i) {
          final t       = _templates[i];
          final id      = t['id'] as String;
          final active  = _selectedTemplateId == id;
          final style   = styles[id] ?? ('🤖', const Color(0xFFF5F5F5), Colors.blueGrey);

          return GestureDetector(
            onTap: () => _applyTemplate(t),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 110,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: active ? style.$3 : style.$2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: style.$3.withValues(alpha: active ? 1 : 0.2),
                    width: active ? 2 : 1),
                boxShadow: active
                    ? [BoxShadow(
                        color: style.$3.withValues(alpha: 0.3),
                        blurRadius: 10, offset: const Offset(0, 4))]
                    : [],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(style.$1, style: const TextStyle(fontSize: 28)),
                  const SizedBox(height: 6),
                  Text(t['name'],
                      style: GoogleFonts.notoSansTc(
                          fontSize: 12, fontWeight: FontWeight.bold,
                          color: active ? Colors.white : style.$3)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _gradientSlider({
    required String label,
    required double value,
    required String leftLabel,
    required String rightLabel,
    required ValueChanged<double> onChanged,
    required List<Color> colors,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: GoogleFonts.notoSansTc(
                fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF374151))),
        const SizedBox(height: 10),
        Container(
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(colors: colors),
          ),
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 12,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              overlayColor: Colors.white.withValues(alpha: 0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11, elevation: 4),
            ),
            child: Slider(value: value, min: 0, max: 100, onChanged: onChanged),
          ),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(leftLabel,
              style: GoogleFonts.notoSansTc(fontSize: 11, color: const Color(0xFF9CA3AF))),
          Text(rightLabel,
              style: GoogleFonts.notoSansTc(fontSize: 11, color: const Color(0xFF9CA3AF))),
        ]),
      ]);

  Widget _heartbeatWidget() {
    final opts   = [0, 30, 60, 120, 180];
    final labels = ['關閉', '30 分', '1 小時', '2 小時', '3 小時'];
    int idx = opts.indexOf(_heartbeatFrequency);
    if (idx == -1) idx = 0;
    final isOn = _heartbeatFrequency > 0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Status badge
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isOn
                ? const [Color(0xFFDC2626), Color(0xFFEF4444)]
                : [Colors.grey.shade300, Colors.grey.shade400],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Text(isOn ? '💓' : '💤', style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isOn ? '主動關懷 已開啟' : '主動關懷 已關閉',
                style: GoogleFonts.notoSansTc(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            Text(isOn ? '每 ${labels[idx]} 主動問候一次' : 'AI 只會被動回應',
                style: GoogleFonts.notoSansTc(color: Colors.white70, fontSize: 12)),
          ]),
        ]),
      ),
      const SizedBox(height: 20),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 6,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
          activeTrackColor: const Color(0xFFEF4444),
          inactiveTrackColor: const Color(0xFFE5E7EB),
          thumbColor: const Color(0xFFEF4444),
          overlayColor: const Color(0xFFEF4444).withValues(alpha: 0.1),
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
    ]);
  }

  Widget _elderSelector() => SizedBox(
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _elders.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (ctx, i) {
            final e      = _elders[i];
            final active = _selectedElder?['id'] == e['id'];
            return GestureDetector(
              onTap: () => _selectElder(e),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF2563EB) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: active ? const Color(0xFF2563EB) : Colors.grey.shade300),
                ),
                child: Text(e['user_name'] ?? '長輩',
                    style: GoogleFonts.notoSansTc(
                        fontWeight: FontWeight.bold,
                        color: active ? Colors.white : Colors.black87)),
              ),
            );
          },
        ),
      );

  Widget _emptyState() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('🤖', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text('尚未配對任何長輩',
              style: GoogleFonts.notoSansTc(
                  fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black54)),
          const SizedBox(height: 8),
          Text('請到「設定」頁面配對長輩設備',
              style: GoogleFonts.notoSansTc(color: Colors.grey)),
        ]),
      );
}
