import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

class FamilyScriptEditorScreen extends StatefulWidget {
  final String scriptTitle;
  const FamilyScriptEditorScreen({super.key, required this.scriptTitle});

  @override
  State<FamilyScriptEditorScreen> createState() =>
      _FamilyScriptEditorScreenState();
}

class ScriptNode {
  final String id;
  String title;
  String content;
  Offset position;
  final IconData icon;
  final Color color;
  final List<String> childrenIds;

  // Trigger Settings
  String triggerType; // 'voice', 'time', 'weather', 'health', 'iot'
  List<String>? keywords;
  double? moodThreshold;
  String? triggerTime;
  String? weatherCondition;
  String? healthMetric;
  double? healthThreshold;
  String? iotDevice;
  String? iotEvent;

  // Action Settings
  String? voiceTone;
  int delaySeconds;
  String? mediaUrl;

  // Condition Settings
  String? timeRange;

  ScriptNode({
    required this.id,
    required this.title,
    required this.content,
    required this.position,
    required this.icon,
    required this.color,
    this.childrenIds = const [],
    this.triggerType = 'voice',
    this.keywords,
    this.moodThreshold = 0.5,
    this.triggerTime,
    this.weatherCondition = '雨天',
    this.healthMetric = '心率',
    this.healthThreshold = 100,
    this.iotDevice = '門窗感測器',
    this.iotEvent = '開啟',
    this.voiceTone = '溫暖',
    this.delaySeconds = 0,
    this.mediaUrl,
    this.timeRange = '全天',
  });
}

class _FamilyScriptEditorScreenState extends State<FamilyScriptEditorScreen> {
  final List<ScriptNode> _nodes = [];
  String? _selectedNodeId;
  bool _showSimulator = false;
  final TransformationController _transformationController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    // Start zoomed out slightly or centered
    _transformationController.value = Matrix4.identity();
    super.initState();
    _nodes.addAll([
      ScriptNode(
        id: 'start',
        title: '觸發',
        content: '當長輩說「我今天好無聊」',
        position: const Offset(400, 100),
        icon: Icons.mic,
        color: Colors.blueAccent,
        childrenIds: ['action_1'],
      ),
      ScriptNode(
        id: 'action_1',
        title: '動作',
        content: 'AI 自動生成關於「懷舊廣播」的對話',
        position: const Offset(400, 300),
        icon: Icons.auto_awesome,
        color: Colors.purpleAccent,
        childrenIds: ['end'],
      ),
      ScriptNode(
        id: 'end',
        title: '結束',
        content: '記錄話題到照顧日誌',
        position: const Offset(400, 500),
        icon: Icons.check_circle,
        color: Colors.greenAccent,
      ),
    ]);
    _currentSimulatorNodeId = 'start';
  }

  String? _currentSimulatorNodeId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: Text(
          widget.scriptTitle,
          style: GoogleFonts.notoSansTc(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.save, color: Colors.blueAccent),
            label: Text(
              '儲存',
              style: GoogleFonts.notoSansTc(color: Colors.blueAccent),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          // 左側編輯畫布 (Canvas)
          Expanded(
            flex: 2,
            child: Stack(
              children: [
                InteractiveViewer(
                  transformationController: _transformationController,
                  constrained: false,
                  minScale: 0.1,
                  maxScale: 2.0,
                  child: SizedBox(
                    width: 4000,
                    height: 4000,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(painter: GridPainter()),
                        ),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: NodeLinkPainter(
                              _nodes,
                              _currentSimulatorNodeId,
                            ),
                          ),
                        ),
                        ..._nodes.map((node) => _buildNodeCard(node)),
                      ],
                    ),
                  ),
                ),
                Positioned(left: 20, top: 20, child: _buildToolbar()),
                Positioned(left: 20, bottom: 20, child: _buildCanvasControls()),
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: _buildToggleSimulatorButton(),
                ),
              ],
            ),
          ),

          // 右側面板：屬性編輯器或模擬器
          if (_selectedNodeId != null && !_showSimulator)
            AnimatedContainer(
              duration: 300.ms,
              width: 380,
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                border: Border(left: BorderSide(color: Colors.white10)),
              ),
              child: _buildPropertyPanel(),
            ).animate().slideX(begin: 1.0, end: 0, curve: Curves.easeOutCubic),

          if (_showSimulator)
            AnimatedContainer(
              duration: 300.ms,
              width: 380,
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                border: Border(left: BorderSide(color: Colors.white10)),
              ),
              child: _buildElderSimulator(),
            ).animate().slideX(begin: 1.0, end: 0, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }

  void _addNode(String type) {
    final id = 'node_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _nodes.add(
        ScriptNode(
          id: id,
          triggerType: type == 'trigger' ? 'voice' : 'voice',
          title: type == 'trigger' ? '觸發' : (type == 'condition' ? '條件' : '動作'),
          content: type == 'trigger'
              ? '新觸發事件...'
              : (type == 'condition' ? '如果...' : 'AI 執行...'),
          position: const Offset(100, 100),
          icon: type == 'trigger'
              ? Icons.mic
              : (type == 'condition' ? Icons.call_split : Icons.auto_awesome),
          color: type == 'trigger'
              ? Colors.blueAccent
              : (type == 'condition'
                    ? Colors.orangeAccent
                    : Colors.purpleAccent),
        ),
      );
      _selectedNodeId = id;
    });
  }

  void _deleteSelectedNode() {
    if (_selectedNodeId == null) return;
    setState(() {
      _nodes.removeWhere((n) => n.id == _selectedNodeId);
      // Clean up references in other nodes
      for (var node in _nodes) {
        node.childrenIds.remove(_selectedNodeId);
      }
      _selectedNodeId = null;
    });
  }

  void _tidyUpNodes() {
    if (_nodes.isEmpty) return;

    // Simple tree-based layout
    // Find roots (nodes that are not children of any other node)
    final childIds = _nodes.expand((n) => n.childrenIds).toSet();
    final roots = _nodes.where((n) => !childIds.contains(n.id)).toList();

    if (roots.isEmpty && _nodes.isNotEmpty) {
      roots.add(_nodes.first); // Fallback if it's a cycle or something
    }

    setState(() {
      double startX = 400.0;
      double startY = 100.0;
      double horizontalSpacing = 300.0;
      double verticalSpacing = 200.0;

      Map<String, int> visitedLevels = {};

      void layoutNode(ScriptNode node, int level, int indexInLevel) {
        if (visitedLevels.containsKey(node.id)) return;
        visitedLevels[node.id] = level;

        node.position = Offset(
          startX + (indexInLevel - 0.5) * horizontalSpacing,
          startY + level * verticalSpacing,
        );

        for (int i = 0; i < node.childrenIds.length; i++) {
          final child = _nodes.firstWhere((n) => n.id == node.childrenIds[i]);
          layoutNode(child, level + 1, i);
        }
      }

      for (int i = 0; i < roots.length; i++) {
        layoutNode(roots[i], 0, i);
      }
    });
  }

  Widget _buildPropertyPanel() {
    final node = _nodes.firstWhere((n) => n.id == _selectedNodeId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '節點屬性',
                style: GoogleFonts.notoSansTc(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => setState(() => _selectedNodeId = null),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildPanelField(
                '標題',
                node.title,
                (val) => setState(() => node.title = val),
              ),
              const SizedBox(height: 20),
              _buildPanelField(
                '內容 / 腳本',
                node.content,
                (val) => setState(() => node.content = val),
                maxLines: 5,
              ),
              const SizedBox(height: 24),

              // Conditional Fields based on node type
              if (node.title == '觸發' || node.icon == Icons.mic) ...[
                _buildSectionTitle('觸發來源設定'),
                _buildDropdownField(
                  '觸發類型',
                  node.triggerType,
                  ['voice', 'time', 'weather', 'health', 'iot'],
                  (val) => setState(() {
                    node.triggerType = val;
                    // Update content/icon based on type for better visual feedback
                    if (val == 'voice') {
                      node.content = '語音觸發...';
                    } else if (val == 'time') {
                      node.content = '定時觸發...';
                      node.triggerTime ??= '08:00';
                    } else if (val == 'weather') {
                      node.content = '當天氣變為...時';
                    } else if (val == 'health') {
                      node.content = '當監測到健康數據異常...';
                    } else if (val == 'iot') {
                      node.content = '當居家感測器偵測到...';
                    }
                  }),
                ),
                const SizedBox(height: 16),

                if (node.triggerType == 'voice') ...[
                  _buildPanelField(
                    '關鍵字 (用逗號隔開)',
                    (node.keywords ?? []).join(','),
                    (val) {
                      setState(
                        () => node.keywords = val
                            .split(',')
                            .map((e) => e.trim())
                            .toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildSliderField(
                    '情緒門檻 (低於此值觸發)',
                    node.moodThreshold ?? 0.5,
                    0,
                    1,
                    (val) => setState(() => node.moodThreshold = val),
                  ),
                ],

                if (node.triggerType == 'time') ...[
                  _buildPanelField(
                    '觸發時間 (HH:mm)',
                    node.triggerTime ?? '08:00',
                    (val) => setState(() => node.triggerTime = val),
                  ),
                ],

                if (node.triggerType == 'weather') ...[
                  _buildDropdownField(
                    '天氣狀況',
                    node.weatherCondition ?? '雨天',
                    ['雨天', '高溫', '低溫', '颱風', '強風'],
                    (val) => setState(() => node.weatherCondition = val),
                  ),
                ],

                if (node.triggerType == 'health') ...[
                  _buildDropdownField(
                    '監測清單',
                    node.healthMetric ?? '心率',
                    ['心率', '步數', '異常靜止', '血壓'],
                    (val) => setState(() => node.healthMetric = val),
                  ),
                  const SizedBox(height: 16),
                  _buildPanelField(
                    '異常數值設定',
                    node.healthThreshold.toString(),
                    (val) => setState(
                      () => node.healthThreshold = double.tryParse(val) ?? 100,
                    ),
                  ),
                ],

                if (node.triggerType == 'iot') ...[
                  _buildDropdownField(
                    '設備類型',
                    node.iotDevice ?? '門窗感測器',
                    ['門窗感測器', '藥盒感測器', '跌倒偵測器', '瓦斯偵測', '床墊感測器'],
                    (val) => setState(() => node.iotDevice = val),
                  ),
                  const SizedBox(height: 16),
                  _buildDropdownField(
                    '事件動作',
                    node.iotEvent ?? '開啟',
                    ['開啟', '關閉', '觸發', '未動作', '低電量'],
                    (val) => setState(() => node.iotEvent = val),
                  ),
                ],
                const SizedBox(height: 16),
              ],

              if (node.title == '動作' || node.icon == Icons.auto_awesome) ...[
                _buildSectionTitle('AI 調音'),
                _buildDropdownField(
                  '語氣選擇',
                  node.voiceTone ?? '溫暖',
                  ['溫暖', '幽默', '理性', '活力'],
                  (val) {
                    setState(() => node.voiceTone = val);
                  },
                ),
                const SizedBox(height: 16),
                _buildSliderField(
                  '延遲發送 (秒)',
                  node.delaySeconds.toDouble(),
                  0,
                  60,
                  (val) {
                    setState(() => node.delaySeconds = val.toInt());
                  },
                ),
                const SizedBox(height: 16),
                _buildPanelField('附件圖片/影片 URL', node.mediaUrl ?? '', (val) {
                  setState(() => node.mediaUrl = val);
                }),
                const SizedBox(height: 16),
              ],

              if (node.title == '條件' || node.icon == Icons.call_split) ...[
                _buildSectionTitle('進階判斷'),
                _buildSliderField(
                  '心情預值 (0~1)',
                  node.moodThreshold ?? 0.5,
                  0,
                  1,
                  (val) {
                    setState(() => node.moodThreshold = val);
                  },
                ),
                const SizedBox(height: 16),
                _buildDropdownField(
                  '適用時段',
                  node.timeRange ?? '全天',
                  ['全天', '早上', '下午', '晚上'],
                  (val) {
                    setState(() => node.timeRange = val);
                  },
                ),
                const SizedBox(height: 16),
              ],

              const SizedBox(height: 8),
              _buildSectionTitle('連接設置'),
              const SizedBox(height: 12),
              _buildConnectionList(node),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Colors.white10)),
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _deleteSelectedNode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('刪除此節點'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: GoogleFonts.notoSansTc(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDropdownField(
    String label,
    String value,
    List<String> options,
    Function(String) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.notoSansTc(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF2A2A2A),
              style: GoogleFonts.notoSansTc(color: Colors.white),
              items: options.map((String val) {
                return DropdownMenuItem<String>(value: val, child: Text(val));
              }).toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSliderField(
    String label,
    double value,
    double min,
    double max,
    Function(double) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.notoSansTc(
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
            Text(
              value.toStringAsFixed(1),
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          activeColor: Colors.blueAccent,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildPanelField(
    String label,
    String value,
    Function(String) onChanged, {
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.notoSansTc(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: TextEditingController(text: value)
            ..selection = TextSelection.collapsed(offset: value.length),
          onChanged: onChanged,
          maxLines: maxLines,
          style: GoogleFonts.notoSansTc(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionList(ScriptNode node) {
    return Column(
      children: [
        ...node.childrenIds.map((cid) {
          final child = _nodes.firstWhere((n) => n.id == cid);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(child.icon, color: child.color, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    child.title,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.link_off,
                    size: 18,
                    color: Colors.white30,
                  ),
                  onPressed: () => setState(() => node.childrenIds.remove(cid)),
                ),
              ],
            ),
          );
        }),
        OutlinedButton.icon(
          onPressed: () => _showConnectDialog(node),
          icon: const Icon(Icons.add_link, size: 18),
          label: const Text('新增連接節點'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.blueAccent,
            side: const BorderSide(color: Colors.blueAccent),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  void _showConnectDialog(ScriptNode parent) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
        title: Text(
          '連結到節點',
          style: GoogleFonts.notoSansTc(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: 320,
          child: ListView(
            shrinkWrap: true,
            children: _nodes
                .where(
                  (n) =>
                      n.id != parent.id && !parent.childrenIds.contains(n.id),
                )
                .map(
                  (n) => ListTile(
                    leading: Icon(n.icon, color: n.color),
                    title: Text(
                      n.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      n.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    onTap: () {
                      setState(() => parent.childrenIds.add(n.id));
                      Navigator.pop(context);
                    },
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleSimulatorButton() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: (_showSimulator ? Colors.grey : Colors.indigo).withValues(
              alpha: 0.4,
            ),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: () => setState(() => _showSimulator = !_showSimulator),
        icon: Icon(
          _showSimulator ? Icons.visibility_off : Icons.visibility,
          size: 20,
        ),
        label: Text(
          _showSimulator ? '隱藏模擬器' : '即時模擬預覽',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _showSimulator
              ? const Color(0xFF2A2A2A)
              : const Color(0xFF3F51B5),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
      ),
    ).animate().fadeIn(delay: 500.ms);
  }

  Widget _buildNodeCard(ScriptNode node) {
    bool isSelected = _selectedNodeId == node.id;
    bool isActive = _currentSimulatorNodeId == node.id;

    return Positioned(
      left: node.position.dx,
      top: node.position.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            node.position += d.delta;
          });
        },
        onTap: () => setState(() => _selectedNodeId = node.id),
        child: AnimatedScale(
          scale: isActive ? 1.05 : 1.0,
          duration: 300.ms,
          curve: Curves.easeOutBack,
          child: Container(
            width: 220,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF252525),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isActive
                    ? Colors.blueAccent
                    : (isSelected
                          ? Colors.white
                          : node.color.withValues(alpha: 0.3)),
                width: (isActive || isSelected) ? 3 : 1,
              ),
              boxShadow: [
                if (isActive || isSelected)
                  BoxShadow(
                    color: (isActive ? Colors.blueAccent : node.color)
                        .withValues(alpha: 0.4),
                    blurRadius: isActive ? 30 : 20,
                    spreadRadius: isActive ? 2 : 0,
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(node.icon, color: node.color, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      node.title,
                      style: GoogleFonts.notoSansTc(
                        color: node.color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white10),
                GestureDetector(
                  onDoubleTap: () => _showInlineEditDialog(node),
                  child: Text(
                    node.content,
                    style: GoogleFonts.notoSansTc(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                    ),
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildQuickAddSocket(
                        node,
                        'action',
                        Icons.auto_awesome,
                        Colors.purpleAccent,
                      ),
                      const SizedBox(width: 8),
                      _buildQuickAddSocket(
                        node,
                        'condition',
                        Icons.call_split,
                        Colors.orangeAccent,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAddSocket(
    ScriptNode parent,
    String type,
    IconData icon,
    Color color,
  ) {
    return InkWell(
      onTap: () {
        final id = 'node_${DateTime.now().millisecondsSinceEpoch}';
        final newNode = ScriptNode(
          id: id,
          title: type == 'action' ? '動作' : '條件',
          content: type == 'action' ? '新動作...' : '新條件...',
          position: parent.position + const Offset(0, 200),
          icon: icon,
          color: color,
        );
        setState(() {
          _nodes.add(newNode);
          parent.childrenIds.add(id);
          _selectedNodeId = id;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(Icons.add, size: 14, color: color),
      ),
    );
  }

  void _showInlineEditDialog(ScriptNode node) {
    final controller = TextEditingController(text: node.content);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('快速編輯', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 5,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '輸入腳本內容...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => node.content = controller.text);
              Navigator.pop(context);
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }

  Widget _buildElderSimulator() {
    final currentNode = _nodes.any((n) => n.id == _currentSimulatorNodeId)
        ? _nodes.firstWhere((n) => n.id == _currentSimulatorNodeId)
        : _nodes.isNotEmpty
        ? _nodes.first
        : null;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              const Icon(Icons.smartphone, color: Colors.blueAccent),
              const SizedBox(width: 12),
              Text(
                '長輩端即時對話模擬',
                style: GoogleFonts.notoSansTc(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.refresh,
                  color: Colors.white54,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _currentSimulatorNodeId = 'start'),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF0), // 長輩端典型的溫暖背景色
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: Colors.grey[800]!, width: 8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: currentNode == null
                  ? const Center(child: Text('尚未定義腳本節點'))
                  : Column(
                      children: [
                        // 模擬長輩端介面內容
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              const SizedBox(height: 40),
                              Center(
                                child:
                                    CircleAvatar(
                                          radius: 40,
                                          backgroundColor: currentNode.color
                                              .withValues(alpha: 0.2),
                                          child: Icon(
                                            currentNode.icon,
                                            size: 40,
                                            color: currentNode.color,
                                          ),
                                        )
                                        .animate(
                                          onPlay: (c) =>
                                              c.repeat(reverse: true),
                                        )
                                        .shimmer(duration: 2.seconds),
                              ),
                              const SizedBox(height: 24),
                              Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(24),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.05,
                                          ),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          currentNode.title,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: currentNode.color,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          currentNode.content,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            height: 1.5,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                  .animate(key: ValueKey(currentNode.id))
                                  .fadeIn(duration: 400.ms)
                                  .slideY(begin: 0.1, end: 0),
                            ],
                          ),
                        ),
                        _buildMockElderButtons(currentNode),
                      ],
                    ),
            ),
          ),
        ),
        // 在手機外殼下方加入模擬事件面板
        _buildEventSimulationPanel(),
        _buildSimulatorStatus(currentNode),
      ],
    );
  }

  Widget _buildEventSimulationPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flash_on, size: 14, color: Colors.amber),
              const SizedBox(width: 4),
              Text(
                '測試模擬：點擊對應事件',
                style: GoogleFonts.notoSansTc(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSimEventChip('語音偵測', Icons.mic, 'voice', Colors.blue),
              _buildSimEventChip(
                '定時到達',
                Icons.timer,
                'time',
                Colors.indigoAccent,
              ),
              _buildSimEventChip(
                '天氣變化',
                Icons.wb_cloudy,
                'weather',
                Colors.cyan,
              ),
              _buildSimEventChip(
                '健康數據',
                Icons.favorite,
                'health',
                Colors.redAccent,
              ),
              _buildSimEventChip(
                '感測器觸發',
                Icons.sensors,
                'iot',
                Colors.orangeAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimEventChip(
    String label,
    IconData icon,
    String type,
    Color color,
  ) {
    return ActionChip(
      avatar: Icon(icon, size: 14, color: Colors.white),
      label: Text(
        label,
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
      backgroundColor: color.withValues(alpha: 0.3),
      side: BorderSide(color: color.withValues(alpha: 0.5)),
      padding: EdgeInsets.zero,
      onPressed: () {
        // Find the first trigger node of this type
        final triggerNode =
            _nodes
                .where(
                  (n) =>
                      (n.title == '觸發' || n.triggerType != 'voice') &&
                      n.triggerType == type,
                )
                .firstOrNull ??
            _nodes.where((n) => n.id == 'start').firstOrNull;

        if (triggerNode != null) {
          setState(() => _currentSimulatorNodeId = triggerNode.id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已模擬發送「$label」事件'),
              duration: 1.seconds,
              behavior: SnackBarBehavior.floating,
              width: 250,
              backgroundColor: color.withValues(alpha: 0.8),
            ),
          );
        }
      },
    );
  }

  Widget _buildMockElderButtons(ScriptNode currentNode) {
    if (currentNode.childrenIds.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        color: Colors.white70,
        child: Center(
          child: Text(
            '腳本結束',
            style: GoogleFonts.notoSansTc(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white70,
      child: Column(
        children: currentNode.childrenIds.map((cid) {
          final nextNode = _nodes.firstWhere((n) => n.id == cid);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => setState(() => _currentSimulatorNodeId = cid),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: nextNode.color,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    '下一步：${nextNode.title}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSimulatorStatus(ScriptNode? currentNode) {
    return Container(
      padding: const EdgeInsets.all(24),
      color: (currentNode?.color ?? Colors.blueAccent).withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(
            Icons.flash_on,
            color: currentNode?.color ?? Colors.blueAccent,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            currentNode != null ? '正在模擬「${currentNode.title}」階段...' : '無活動節點',
            style: GoogleFonts.notoSansTc(
              color: currentNode?.color ?? Colors.blueAccent,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          IconButton(
            icon: const Icon(Icons.add_box_outlined, color: Colors.blueAccent),
            tooltip: '新增觸發',
            onPressed: () => _addNode('trigger'),
          ),
          IconButton(
            icon: const Icon(Icons.smart_button, color: Colors.purpleAccent),
            tooltip: '新增動作',
            onPressed: () => _addNode('action'),
          ),
          IconButton(
            icon: const Icon(Icons.call_split, color: Colors.orangeAccent),
            tooltip: '新增條件',
            onPressed: () => _addNode('condition'),
          ),
          const Divider(color: Colors.white10),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: '刪除節點',
            onPressed: _deleteSelectedNode,
          ),
          const Divider(color: Colors.white10),
          IconButton(
            icon: const Icon(Icons.auto_fix_high, color: Colors.amberAccent),
            tooltip: '自動對齊',
            onPressed: _tidyUpNodes,
          ),
        ],
      ),
    ).animate().slideX(begin: -1.0, end: 0);
  }

  Widget _buildCanvasControls() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.center_focus_strong, color: Colors.white70),
            tooltip: '重置視角',
            onPressed: () {
              _transformationController.value = Matrix4.identity();
              setState(() {});
            },
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.zoom_in, color: Colors.white70),
            onPressed: () {
              final val = _transformationController.value.clone();
              val.multiply(Matrix4.diagonal3Values(1.2, 1.2, 1.0));
              _transformationController.value = val;
            },
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out, color: Colors.white70),
            onPressed: () {
              final val = _transformationController.value.clone();
              val.multiply(Matrix4.diagonal3Values(0.8, 0.8, 1.0));
              _transformationController.value = val;
            },
          ),
        ],
      ),
    ).animate().slideX(begin: -1.0, end: 0);
  }
}

class NodeLinkPainter extends CustomPainter {
  final List<ScriptNode> nodes;
  final String? activeNodeId;
  NodeLinkPainter(this.nodes, this.activeNodeId);

  @override
  void paint(Canvas canvas, Size size) {
    for (var node in nodes) {
      if (node.childrenIds.isEmpty) continue;
      final start = node.position + const Offset(110, 80);

      bool isNodeActive = activeNodeId == node.id;

      for (var cid in node.childrenIds) {
        final childNode = nodes.any((n) => n.id == cid)
            ? nodes.firstWhere((n) => n.id == cid)
            : null;
        if (childNode == null) continue;

        final end = childNode.position + const Offset(110, 0);
        bool isPathActive =
            isNodeActive &&
            (activeNodeId !=
                null); // Simplification: highlight all outgoing from active

        final paint = Paint()
          ..color = isPathActive
              ? Colors.blueAccent.withValues(alpha: 0.6)
              : Colors.white24
          ..strokeWidth = isPathActive ? 3 : 2
          ..style = PaintingStyle.stroke;

        final arrowPaint = Paint()
          ..color = isPathActive
              ? Colors.blueAccent.withValues(alpha: 0.8)
              : Colors.white24
          ..style = PaintingStyle.fill;

        final path = Path()..moveTo(start.dx, start.dy);
        path.cubicTo(
          start.dx,
          start.dy + 60,
          end.dx,
          end.dy - 60,
          end.dx,
          end.dy,
        );

        if (isPathActive) {
          // Glow effect for active path
          canvas.drawPath(
            path,
            Paint()
              ..color = Colors.blueAccent.withValues(alpha: 0.2)
              ..strokeWidth = 8
              ..style = PaintingStyle.stroke
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
          );
        }

        canvas.drawPath(path, paint);

        // Draw Arrowhead
        final arrowPath = Path();
        arrowPath.moveTo(end.dx, end.dy);
        arrowPath.lineTo(end.dx - 6, end.dy - 10);
        arrowPath.lineTo(end.dx + 6, end.dy - 10);
        arrowPath.close();
        canvas.drawPath(arrowPath, arrowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.02)
      ..strokeWidth = 0.5;
    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
