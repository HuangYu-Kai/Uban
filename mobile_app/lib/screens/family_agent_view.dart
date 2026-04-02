import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';

class FamilyAgentView extends StatefulWidget {
  final int userId;
  const FamilyAgentView({super.key, required this.userId});

  @override
  State<FamilyAgentView> createState() => _FamilyAgentViewState();
}

class _FamilyAgentViewState extends State<FamilyAgentView> {
  List<dynamic> _elders = [];
  List<dynamic> _templates = [];
  dynamic _selectedElder;
  bool _isLoading = true;
  bool _isSaving = false;

  // Editable fields
  final _personaController = TextEditingController();
  final _lifeStoryController = TextEditingController();
  int _heartbeatFrequency = 0;
  String? _selectedTemplateId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _personaController.dispose();
    _lifeStoryController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final futures = await Future.wait([
      ApiService.getPairedElders(widget.userId),
      ApiService.getPersonaTemplates(),
    ]);
    final elders = futures[0];
    final templates = futures[1];

    if (mounted) {
      setState(() {
        _elders = elders;
        _templates = templates;
        if (elders.isNotEmpty) _selectElder(elders[0]);
        _isLoading = false;
      });
    }
  }

  Future<void> _selectElder(dynamic elder) async {
    setState(() {
      _selectedElder = elder;
      _selectedTemplateId = null;
    });

    // Load this elder's agent profile
    final elderId = int.tryParse(elder['elder_id']?.toString() ?? '') ?? elder['id'];
    final profile = await ApiService.getElderAgentProfile(elderId);

    if (mounted && profile['status'] == 'success') {
      final data = profile['data'];
      setState(() {
        _personaController.text = data['ai_persona'] ?? '親切的老年陪伴員';
        _lifeStoryController.text = data['life_story'] ?? '';
        _heartbeatFrequency = data['heartbeat_frequency'] ?? 0;
      });
    }
  }

  Future<void> _save() async {
    if (_selectedElder == null) return;
    setState(() => _isSaving = true);

    final elderId = _selectedElder['user_id'] ?? _selectedElder['id'];
    final result = await ApiService.updateElderProfile(
      userId: elderId,
      aiPersona: _personaController.text,
      lifeStory: _lifeStoryController.text,
      heartbeatFrequency: _heartbeatFrequency,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['status'] == 'success' ? '✅ Agent 設定已儲存！' : '❌ 儲存失敗，請稍後再試',
          style: GoogleFonts.notoSansTc(),
        ),
        backgroundColor: result['status'] == 'success' ? const Color(0xFF16A34A) : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _applyTemplate(dynamic template) {
    setState(() {
      _selectedTemplateId = template['id'];
      _personaController.text = template['persona'];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: Text(
          'AI 陪伴設定',
          style: GoogleFonts.notoSansTc(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_selectedElder != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _isSaving
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check_circle, color: Color(0xFF2563EB)),
                      label: Text(
                        '儲存',
                        style: GoogleFonts.notoSansTc(
                          color: const Color(0xFF2563EB),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _elders.isEmpty
              ? _buildEmptyState()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Elder Selector (if multiple elders)
                      if (_elders.length > 1) ...[
                        _buildSectionLabel('選擇長輩'),
                        _buildElderSelector(),
                        const SizedBox(height: 24),
                      ],

                      // Persona Templates
                      _buildSectionLabel('快速套用人格範本'),
                      const SizedBox(height: 4),
                      Text(
                        '選擇一種角色，AI 會以此調性與長輩互動',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildTemplateCards(),
                      const SizedBox(height: 28),

                      // Custom Persona
                      _buildSectionLabel('自訂角色說明'),
                      const SizedBox(height: 8),
                      _buildTextField(
                        controller: _personaController,
                        hint: '例如：你是一個貼心的孫子，喜歡關心長輩...',
                        maxLines: 4,
                        icon: Icons.face_retouching_natural,
                      ),
                      const SizedBox(height: 24),

                      // Life Story
                      _buildSectionLabel('長輩生命故事'),
                      const SizedBox(height: 4),
                      Text(
                        '讓 AI 了解長輩的背景，聊天時更自然貼心',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildTextField(
                        controller: _lifeStoryController,
                        hint: '例如：年輕時在台南務農，喜歡看戲劇，有三個孩子...',
                        maxLines: 5,
                        icon: Icons.auto_stories,
                      ),
                      const SizedBox(height: 28),

                      // Heartbeat Frequency
                      _buildSectionLabel('自然心跳關懷頻率'),
                      const SizedBox(height: 4),
                      Text(
                        'AI 會在長輩安靜一段時間後，主動以語音關心',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildHeartbeatSlider(),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.notoSansTc(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildElderSelector() {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _elders.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final elder = _elders[index];
          final isSelected = _selectedElder?['id'] == elder['id'];
          return GestureDetector(
            onTap: () => _selectElder(elder),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF2563EB) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade300,
                ),
              ),
              child: Text(
                elder['user_name'] ?? '未知長輩',
                style: GoogleFonts.notoSansTc(
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.black87,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTemplateCards() {
    if (_templates.isEmpty) {
      return const SizedBox.shrink();
    }

    final templateIcons = {
      'grandson': ('👦', const Color(0xFFEFF6FF), const Color(0xFF2563EB)),
      'old_friend': ('🧓', const Color(0xFFFFF7ED), const Color(0xFFEA580C)),
      'butler': ('🎩', const Color(0xFFF0FDF4), const Color(0xFF16A34A)),
    };

    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _templates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final t = _templates[index];
          final id = t['id'] as String;
          final isSelected = _selectedTemplateId == id;
          final style = templateIcons[id] ?? ('🤖', const Color(0xFFF5F5F5), Colors.grey);

          return GestureDetector(
            onTap: () => _applyTemplate(t),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 130,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected ? style.$3 : style.$2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? style.$3 : style.$3.withOpacity(0.2),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [BoxShadow(color: style.$3.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))]
                    : [],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(style.$1, style: const TextStyle(fontSize: 28)),
                  const SizedBox(height: 8),
                  Text(
                    t['name'],
                    style: GoogleFonts.notoSansTc(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : style.$3,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required int maxLines,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: GoogleFonts.notoSansTc(fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.notoSansTc(color: Colors.grey[400], fontSize: 14),
          prefixIcon: Icon(icon, color: const Color(0xFF2563EB)),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  Widget _buildHeartbeatSlider() {
    final options = [0, 30, 60, 120, 180];
    final labels = ['關閉', '30 分', '1 小時', '2 小時', '3 小時'];
    final idx = options.indexOf(_heartbeatFrequency).clamp(0, options.length - 1);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💓', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _heartbeatFrequency == 0 ? '目前關閉' : '每 ${labels[idx]} 關心一次',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _heartbeatFrequency == 0 ? Colors.grey : const Color(0xFF2563EB),
                    ),
                  ),
                  Text(
                    _heartbeatFrequency == 0
                        ? 'AI 不會主動發話'
                        : 'AI 會在長輩安靜 ${labels[idx]}後主動關心',
                    style: GoogleFonts.notoSansTc(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
              activeTrackColor: const Color(0xFF2563EB),
              inactiveTrackColor: Colors.grey.shade200,
              thumbColor: const Color(0xFF2563EB),
              overlayColor: const Color(0xFF2563EB).withOpacity(0.1),
            ),
            child: Slider(
              value: idx.toDouble(),
              min: 0,
              max: (options.length - 1).toDouble(),
              divisions: options.length - 1,
              onChanged: (v) {
                setState(() {
                  _heartbeatFrequency = options[v.round()];
                });
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: labels
                .map(
                  (l) => Text(
                    l,
                    style: GoogleFonts.notoSansTc(fontSize: 11, color: Colors.grey[500]),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🤖', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 20),
          Text(
            '尚未配對任何長輩',
            style: GoogleFonts.notoSansTc(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '請先到「設定」頁面配對長輩設備',
            style: GoogleFonts.notoSansTc(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
