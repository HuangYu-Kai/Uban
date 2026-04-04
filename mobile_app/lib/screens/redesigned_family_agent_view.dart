import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';

/// 🎨 重新設計的 Agent 配置界面 - 高端簡約風格
/// 靈感來自 Figma、Discord、Notion 的現代設計
class RedesignedFamilyAgentView extends StatefulWidget {
  final int userId;
  const RedesignedFamilyAgentView({super.key, required this.userId});

  @override
  State<RedesignedFamilyAgentView> createState() =>
      _RedesignedFamilyAgentViewState();
}

class _RedesignedFamilyAgentViewState extends State<RedesignedFamilyAgentView> {
  List<dynamic> _elders = [];
  dynamic _selectedElder;
  bool _isLoading = true;
  bool _isSaving = false;

  // Form Controllers
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _cityController = TextEditingController();
  final _districtController = TextEditingController();
  final _appellationController = TextEditingController();
  final _chronicController = TextEditingController();
  final _medicationController = TextEditingController();
  final _personaController = TextEditingController();
  final _lifeStoryController = TextEditingController();
  final _interestsController = TextEditingController();

  // Form State
  String _gender = 'M';
  double _emotionTone = 50;
  double _textVerbosity = 50;
  int _heartbeatFrequency = 0;
  String _selectedPersona = 'gentle'; // AI 人格選擇

  // AI 人格配置 - 高端設計配置
  final Map<String, Map<String, dynamic>> aiPersonas = {
    'gentle': {
      'label': '溫柔陪伴',
      'emoji': '🤗',
      'description': '溫暖、體貼、耐心的對話風格',
      'color': Color(0xFF8B5CF6),
    },
    'friend': {
      'label': '老友益友',
      'emoji': '🧓',
      'description': '親切、幽默、充滿故事的陪伴',
      'color': Color(0xFFEA580C),
    },
    'butler': {
      'label': '專業管家',
      'emoji': '🎩',
      'description': '高效、專業、守護式的服務',
      'color': Color(0xFF16A34A),
    },
    'grandson': {
      'label': '活力孫兒',
      'emoji': '👦',
      'description': '年轻、活泼、充满能量的互动',
      'color': Color(0xFF3B82F6),
    },
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final c in [
      _nameController,
      _ageController,
      _cityController,
      _districtController,
      _appellationController,
      _chronicController,
      _medicationController,
      _personaController,
      _lifeStoryController,
      _interestsController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final elders = await ApiService.getPairedElders(widget.userId);
    if (!mounted) return;
    setState(() {
      _elders = elders;
      _isLoading = false;
    });
    if (elders.isNotEmpty) await _selectElder(elders[0]);
  }

  Future<void> _selectElder(dynamic elder) async {
    setState(() => _selectedElder = elder);
    final userId = elder['user_id'] ?? elder['id'];
    final profile = await ApiService.getElderProfile(userId);
    if (!mounted) return;

    final data = (profile['data'] is Map) ? profile['data'] : profile;
    setState(() {
      _nameController.text = data['elder_name'] ?? elder['user_name'] ?? '';
      _ageController.text = (data['age'] ?? elder['age'] ?? '').toString();
      _gender = data['gender'] ?? elder['gender'] ?? 'M';
      _appellationController.text = data['appellation'] ?? '';
      _chronicController.text = data['chronic_diseases'] ?? '';
      _medicationController.text = data['medication_notes'] ?? '';
      _interestsController.text = data['interests'] ?? '';
      _personaController.text = data['ai_persona'] ?? '溫柔的老年陪伴員';
      _lifeStoryController.text = data['life_story'] ?? '';
      _heartbeatFrequency = data['heartbeat_frequency'] ?? 0;
      _emotionTone = (data['ai_emotion_tone'] ?? 50).toDouble();
      _textVerbosity = (data['ai_text_verbosity'] ?? 50).toDouble();
      _parseLocation(data['location'] ?? elder['location'] ?? '');
    });
  }

  void _parseLocation(String loc) {
    if (loc.isEmpty) return;
    final parts = loc.split('/');
    if (parts.length >= 2) {
      _cityController.text = parts[0];
      _districtController.text = parts[1];
    }
  }

  Future<void> _saveElder() async {
    setState(() => _isSaving = true);
    HapticFeedback.lightImpact();

    try {
      final userId = int.parse((_selectedElder['user_id'] ?? _selectedElder['id'] ?? widget.userId).toString());
      await ApiService.updateElderProfile(
        userId: userId,
        appellation: _appellationController.text,
        chronicDiseases: _chronicController.text,
        medicationNotes: _medicationController.text,
        aiPersona: _selectedPersona,
        aiEmotionTone: _emotionTone.toInt(),
        aiTextVerbosity: _textVerbosity.toInt(),
        interests: _interestsController.text,
        lifeStory: _lifeStoryController.text,
        location: '${_cityController.text}/${_districtController.text}',
        heartbeatFrequency: _heartbeatFrequency,
      );

      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ 配置已保存'),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ 保存失敗: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '加載中...',
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildAppBar(),
      body: _elders.isEmpty
          ? _buildEmptyState()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                // Elder Selection Section
                _buildElderSelector(),
                const SizedBox(height: 32),

                // AI Persona Selection - 現代卡片風格
                _buildPersonaSelector(),
                const SizedBox(height: 32),

                // Basic Info Card
                _buildSectionCard(
                  title: '基本资料',
                  icon: Icons.person,
                  color: const Color(0xFF3B82F6),
                  children: [
                    _buildTextField('姓名', _nameController),
                    _buildNumberField('年齡', _ageController),
                    _buildGenderSelector(),
                    _buildTextField('稱呼', _appellationController),
                  ],
                ),
                const SizedBox(height: 24),

                // Location Card
                _buildSectionCard(
                  title: '居住地區',
                  icon: Icons.location_on,
                  color: const Color(0xFF10B981),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField('城市', _cityController),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField('地區', _districtController),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildLocationButton(),
                  ],
                ),
                const SizedBox(height: 24),

                // Health Card
                _buildSectionCard(
                  title: '健康資訊',
                  icon: Icons.favorite,
                  color: const Color(0xFFEF4444),
                  children: [
                    _buildTextField('慢性疾病', _chronicController,
                        maxLines: 2),
                    _buildTextField('用藥備註', _medicationController,
                        maxLines: 2),
                    _buildTextField('興趣愛好', _interestsController,
                        maxLines: 2),
                  ],
                ),
                const SizedBox(height: 24),

                // AI Personality Settings Card
                _buildSectionCard(
                  title: 'AI 個性設置',
                  icon: Icons.psychology,
                  color: const Color(0xFF8B5CF6),
                  children: [
                    _buildSlider('情感溫度', _emotionTone, (v) {
                      setState(() => _emotionTone = v);
                      HapticFeedback.lightImpact();
                    }),
                    const SizedBox(height: 20),
                    _buildSlider('詞語詳細度', _textVerbosity, (v) {
                      setState(() => _textVerbosity = v);
                      HapticFeedback.lightImpact();
                    }),
                  ],
                ),
                const SizedBox(height: 24),

                // Life Story Card
                _buildSectionCard(
                  title: '生活故事',
                  icon: Icons.book,
                  color: const Color(0xFFF59E0B),
                  children: [
                    _buildTextField('個人介紹', _lifeStoryController,
                        maxLines: 4),
                  ],
                ),
                const SizedBox(height: 32),

                // Save Button
                _buildSaveButton(),
              ],
            ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF0F172A), size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'AI 配置',
        style: GoogleFonts.notoSansTc(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF0F172A),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: Text(
              '保存',
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF667EEA),
              ),
            ),
          ),
        ),
      ],
      centerTitle: true,
    );
  }

  Widget _buildElderSelector() {
    if (_elders.length <= 1) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '選擇長者',
          style: GoogleFonts.notoSansTc(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF64748B),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _elders.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final elder = _elders[index];
              final isSelected = _selectedElder == elder;
              return GestureDetector(
                onTap: () => _selectElder(elder),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF667EEA)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF667EEA)
                          : const Color(0xFFE5E7EB),
                      width: 1.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color:
                                  const Color(0xFF667EEA).withOpacity(0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: Center(
                    child: Text(
                      elder['user_name'] ?? '長者',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPersonaSelector() {
    final personas = aiPersonas.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AI 人格',
          style: GoogleFonts.notoSansTc(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF64748B),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.1,
          children: personas.map((entry) {
            final key = entry.key;
            final persona = entry.value;
            final isSelected = _selectedPersona == key;

            return GestureDetector(
              onTap: () => setState(() {
                _selectedPersona = key;
                HapticFeedback.lightImpact();
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                decoration: BoxDecoration(
                  color: isSelected
                      ? persona['color'].withOpacity(0.1)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? persona['color']
                        : const Color(0xFFE5E7EB),
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: persona['color'].withOpacity(0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      persona['emoji'],
                      style: const TextStyle(fontSize: 32),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      persona['label'],
                      style: GoogleFonts.notoSansTc(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: persona['color'],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        persona['description'],
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 10,
                          color: const Color(0xFF94A3B8),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ).animate().scale(
                  begin: const Offset(0.8, 0.8),
                  duration: 300.ms,
                  curve: Curves.easeOutBack,
                );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0F1F3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: const Color(0xFFF0F1F3)),
          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1) const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1);
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.notoSansTc(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF64748B),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: '輸入 $label',
            hintStyle: GoogleFonts.notoSansTc(
              fontSize: 14,
              color: const Color(0xFFCBD5E1),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFFE5E7EB), width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFFE5E7EB), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFF667EEA), width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            filled: true,
            fillColor: const Color(0xFFFAFAFB),
          ),
          style: GoogleFonts.notoSansTc(
            fontSize: 14,
            color: const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildNumberField(String label, TextEditingController controller) {
    return _buildTextField(label, controller);
  }

  Widget _buildGenderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '性別',
          style: GoogleFonts.notoSansTc(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF64748B),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: ['M', 'F']
              .map((g) => Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _gender = g);
                        HapticFeedback.lightImpact();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _gender == g
                              ? const Color(0xFF667EEA)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _gender == g
                                ? const Color(0xFF667EEA)
                                : const Color(0xFFE5E7EB),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            g == 'M' ? '男' : '女',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _gender == g
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ))
              .toList()
              .cast<Widget>(),
        ),
      ],
    );
  }

  Widget _buildLocationButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          // 位置獲取逻辑
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        icon: const Icon(Icons.location_on, size: 18),
        label: Text(
          '獲取當前位置',
          style: GoogleFonts.notoSansTc(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    // 實時預覽文本生成
    String _getPreviewText(String label, double value) {
      if (label.contains('情感溫度')) {
        if (value < 30) return '「早安，請記得吃藥。」（簡潔專業）';
        if (value < 70) return '「早安呀！記得吃藥哦~」（溫暖友善）';
        return '「寶貝早安！一定要記得吃藥，我會擔心的！💝」（熱情親密）';
      } else if (label.contains('詞語詳細度')) {
        if (value < 30) return '「好的」（簡短）';
        if (value < 70) return '「好的，我明白了」（適中）';
        return '「好的，我完全明白您的意思了，這真是個很棒的想法！」（詳細）';
      }
      return '';
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.notoSansTc(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${value.toInt()}%',
                style: GoogleFonts.notoSansTc(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF667EEA),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 8,
              elevation: 2,
            ),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: 100,
            onChanged: onChanged,
            activeColor: const Color(0xFF667EEA),
            inactiveColor: const Color(0xFFE5E7EB),
          ),
        ),
        // 🎯 實時預覽（新增）
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.preview_rounded,
                  color: Color(0xFF667EEA),
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _getPreviewText(label, value),
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12,
                    color: const Color(0xFF475569),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ).animate(key: ValueKey('$label-$value'))
          .fadeIn(duration: 200.ms)
          .slideY(begin: -0.2, end: 0, duration: 200.ms),
      ],
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveElder,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF16A34A),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          disabledBackgroundColor: const Color(0xFFCBD5E1),
        ),
        child: _isSaving
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.8)),
                ),
              )
            : Text(
                '保存配置',
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA).withOpacity(0.1),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.person_add_alt_1,
              color: Color(0xFF667EEA),
              size: 40,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '暫無長者',
            style: GoogleFonts.notoSansTc(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '請先配對長者',
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}
