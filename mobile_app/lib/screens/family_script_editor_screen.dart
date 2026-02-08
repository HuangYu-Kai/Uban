import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/script_data_service.dart';
import '../models/script_node.dart';
import '../widgets/script_editor/script_editor_painters.dart';
import '../widgets/script_editor/node_card.dart';
import '../widgets/script_editor/property_panel.dart';
import '../widgets/script_editor/elder_simulator.dart';

class FamilyScriptEditorScreen extends StatefulWidget {
  final String scriptTitle;
  final bool isNew;
  const FamilyScriptEditorScreen({
    super.key,
    required this.scriptTitle,
    this.isNew = false,
  });

  @override
  State<FamilyScriptEditorScreen> createState() =>
      _FamilyScriptEditorScreenState();
}

class _FamilyScriptEditorScreenState extends State<FamilyScriptEditorScreen> {
  String? _currentSimulatorNodeId;
  bool _showComponentBox = false;
  final List<ScriptNode> _nodes = [];
  String? _selectedNodeId;
  bool _showSimulator = false;
  bool _isTimelineMode = true;
  final TransformationController _transformationController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    // Start zoomed out slightly or centered
    _transformationController.value = Matrix4.identity();

    // Load persisted nodes if available
    final persistedNodes = ScriptDataService().getNodes(widget.scriptTitle);
    if (persistedNodes.isNotEmpty) {
      _nodes.addAll(
        persistedNodes
            .map(
              (d) => ScriptNode(
                id: d.id,
                title: d.title,
                content: d.content,
                position: d.position,
                icon: d.icon,
                color: d.color,
                childrenIds: List.from(d.childrenIds),
                triggerType: d.triggerType ?? 'voice',
                keywords: d.keywords,
                moodThreshold: d.moodThreshold,
                triggerTime: d.triggerTime,
                weatherCondition: d.weatherCondition ?? '雨天',
                healthMetric: d.healthMetric ?? '心率',
                healthThreshold: d.healthThreshold ?? 100,
                iotDevice: d.iotDevice ?? '門窗感測器',
                iotEvent: d.iotEvent ?? '開啟',
                voiceTone: d.voiceTone ?? '溫暖',
                delaySeconds: d.delaySeconds,
                mediaUrl: d.mediaUrl,
                choiceLabels: d.choiceLabels,
                personaName: d.personaName,
                personaPrompt: d.personaPrompt,
                memoryKey: d.memoryKey,
                memoryValue: d.memoryValue,
                timeRange: d.timeRange ?? '全天',
              ),
            )
            .toList(),
      );
      _currentSimulatorNodeId = _nodes.firstOrNull?.id;
    } else if (!widget.isNew) {
      _nodes.addAll([
        ScriptNode(
          id: 'start',
          title: '觸發',
          content: '當長輩說「我今天好無聊」...',
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
          content: '記錄話題到照顧日誌...',
          position: const Offset(400, 500),
          icon: Icons.check_circle,
          color: Colors.greenAccent,
        ),
      ]);
      _currentSimulatorNodeId = 'start';
    }
  }

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
          IconButton(
            onPressed: () => setState(() => _isTimelineMode = !_isTimelineMode),
            icon: Icon(
              _isTimelineMode
                  ? Icons.account_tree_outlined
                  : Icons.view_timeline,
              color: Colors.white70,
            ),
            tooltip: _isTimelineMode ? '切換至畫布' : '切換至時間軸',
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () async {
              // Save nodes to service
              await ScriptDataService().saveNodes(
                widget.scriptTitle,
                _nodes
                    .map(
                      (n) => ScriptNodeData(
                        id: n.id,
                        title: n.title,
                        content: n.content,
                        position: n.position,
                        icon: n.icon,
                        color: n.color,
                        childrenIds: List.from(n.childrenIds),
                        triggerType: n.triggerType,
                        keywords: n.keywords,
                        moodThreshold: n.moodThreshold,
                        triggerTime: n.triggerTime,
                        weatherCondition: n.weatherCondition,
                        healthMetric: n.healthMetric,
                        healthThreshold: n.healthThreshold,
                        iotDevice: n.iotDevice,
                        iotEvent: n.iotEvent,
                        voiceTone: n.voiceTone,
                        delaySeconds: n.delaySeconds,
                        mediaUrl: n.mediaUrl,
                        choiceLabels: n.choiceLabels,
                        personaName: n.personaName,
                        personaPrompt: n.personaPrompt,
                        memoryKey: n.memoryKey,
                        memoryValue: n.memoryValue,
                        timeRange: n.timeRange,
                      ),
                    )
                    .toList(),
              );
              if (context.mounted) Navigator.pop(context);
            },
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
            child: _isTimelineMode ? _buildTimelineView() : _buildCanvasView(),
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
              child: PropertyPanel(
                node: _nodes.firstWhere((n) => n.id == _selectedNodeId),
                allNodes: _nodes,
                onUpdate: () => setState(() {}),
                onDelete: _deleteSelectedNode,
                onClose: () => setState(() => _selectedNodeId = null),
                onAddConnection: () => _showConnectDialog(
                  _nodes.firstWhere((n) => n.id == _selectedNodeId),
                ),
              ),
            ).animate().slideX(begin: 1.0, end: 0, curve: Curves.easeOutCubic),

          if (_showSimulator)
            AnimatedContainer(
              duration: 300.ms,
              width: 380,
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                border: Border(left: BorderSide(color: Colors.white10)),
              ),
              child: ElderSimulator(
                allNodes: _nodes,
                currentSimulatorNodeId: _currentSimulatorNodeId,
                onNodeChange: (id) =>
                    setState(() => _currentSimulatorNodeId = id),
                onReset: () =>
                    setState(() => _currentSimulatorNodeId = 'start'),
              ),
            ).animate().slideX(begin: 1.0, end: 0, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }

  Widget _buildCanvasView() {
    return Stack(
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
                Positioned.fill(child: CustomPaint(painter: GridPainter())),
                Positioned.fill(
                  child: CustomPaint(
                    painter: NodeLinkPainter(_nodes, _currentSimulatorNodeId),
                  ),
                ),
                ..._nodes.map(
                  (node) => NodeCard(
                    node: node,
                    isSelected: _selectedNodeId == node.id,
                    isActive: _currentSimulatorNodeId == node.id,
                    onTap: () => setState(() => _selectedNodeId = node.id),
                    onPanUpdate: (d) =>
                        setState(() => node.position += d.delta),
                    onDoubleTap: () => _showInlineEditDialog(node),
                    onQuickAdd: () => _showQuickAddMenu(node),
                  ),
                ),
                if (_nodes.isEmpty) _buildEmptyCanvasPlaceholder(),
              ],
            ),
          ),
        ),
        Positioned(left: 20, top: 20, child: _buildCanvasControls()),
        Positioned(left: 20, bottom: 20, child: _buildComponentBox()),
        Positioned(right: 20, bottom: 20, child: _buildToggleSimulatorButton()),
      ],
    );
  }

  Widget _buildEmptyCanvasPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_fix_high,
            size: 64,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 24),
          Text(
            '畫布還是空的',
            style: GoogleFonts.notoSansTc(color: Colors.white24, fontSize: 18),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              final id = 'start';
              setState(() {
                _nodes.add(
                  ScriptNode(
                    id: id,
                    title: '開始觸發',
                    content: '當長輩對我說...',
                    position: const Offset(1900, 1900),
                    icon: Icons.mic,
                    color: Colors.blueAccent,
                  ),
                );
                _selectedNodeId = id;
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('開始建立第一步'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _loadBreadBakingTemplate,
            icon: const Icon(Icons.auto_stories, size: 20),
            label: const Text('載入範例：麵包烘焙橋樑'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.purpleAccent,
              side: const BorderSide(color: Colors.purpleAccent),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineView() {
    final orderedNodes = _getOrderedNodes();
    return Stack(
      children: [
        if (orderedNodes.isEmpty)
          _buildEmptyCanvasPlaceholder()
        else
          ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 120),
            itemCount: orderedNodes.length,
            itemBuilder: (context, index) {
              final node = orderedNodes[index];
              final isLast = index == orderedNodes.length - 1;
              return Column(
                children: [
                  _buildTimelineNode(node),
                  if (!isLast)
                    _buildTimelineConnector(node, orderedNodes[index + 1]),
                  if (isLast) _buildTimelineEndGuide(node),
                ],
              );
            },
          ),
        Positioned(right: 20, bottom: 20, child: _buildToggleSimulatorButton()),
      ],
    );
  }

  List<ScriptNode> _getOrderedNodes() {
    if (_nodes.isEmpty) return [];
    List<ScriptNode> result = [];
    Set<String> visited = {};

    void traverse(String id) {
      if (visited.contains(id)) return;
      final node = _nodes.where((n) => n.id == id).firstOrNull;
      if (node != null) {
        visited.add(id);
        result.add(node);
        // In timeline mode, we just follow the first branch for simplicity
        if (node.childrenIds.isNotEmpty) {
          traverse(node.childrenIds.first);
        }
      }
    }

    final startNode =
        _nodes.where((n) => n.id == 'start').firstOrNull ?? _nodes.firstOrNull;
    if (startNode != null) {
      traverse(startNode.id);
    }

    return result;
  }

  Widget _buildTimelineConnector(ScriptNode from, ScriptNode to) {
    return Column(
      children: [
        Container(
          height: 20,
          width: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [from.color, to.color],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        IconButton(
              onPressed: () => _showInsertMenu(from, to),
              icon: const Icon(Icons.add_circle_outline, size: 24),
              color: Colors.white24,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(
              duration: 2.seconds,
              begin: const Offset(0.9, 0.9),
              end: const Offset(1.1, 1.1),
            ),
        Container(
          height: 20,
          width: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [from.color, to.color],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineEndGuide(ScriptNode lastNode) {
    return Column(
      children: [
        Container(
          height: 30,
          width: 2,
          color: lastNode.color.withValues(alpha: 0.3),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ElevatedButton.icon(
            onPressed: () => _showQuickAddMenu(lastNode),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('接續下一步'),
            style: ElevatedButton.styleFrom(
              backgroundColor: lastNode.color.withValues(alpha: 0.1),
              foregroundColor: lastNode.color,
              side: BorderSide(color: lastNode.color.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineNode(ScriptNode node) {
    final isSelected = _selectedNodeId == node.id;
    final isActive = _currentSimulatorNodeId == node.id;

    return GestureDetector(
      onTap: () => setState(() => _selectedNodeId = node.id),
      child: AnimatedScale(
        scale: isSelected ? 1.02 : 1.0,
        duration: 200.ms,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AnimatedContainer(
              duration: 300.ms,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF252525).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isActive
                      ? Colors.blueAccent
                      : (isSelected
                            ? Colors.white
                            : node.color.withValues(alpha: 0.2)),
                  width: (isActive || isSelected) ? 2 : 1,
                ),
                boxShadow: [
                  if (isActive || isSelected)
                    BoxShadow(
                      color: (isActive ? Colors.blueAccent : node.color)
                          .withValues(alpha: 0.2),
                      blurRadius: 15,
                    ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: node.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(node.icon, color: node.color, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.title,
                          style: GoogleFonts.notoSansTc(
                            color: node.color,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          node.content,
                          style: GoogleFonts.notoSansTc(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _addNode(String type) {
    final id = 'node_${DateTime.now().millisecondsSinceEpoch}';
    // Offset slightly based on node count to avoid exact overlap
    final offset = Offset(
      100.0 + (_nodes.length % 5) * 40,
      100.0 + (_nodes.length % 5) * 40,
    );

    setState(() {
      _nodes.add(
        ScriptNode(
          id: id,
          triggerType: type == 'trigger' ? 'voice' : 'voice',
          title: type == 'trigger' ? '觸發' : (type == 'condition' ? '條件' : '動作'),
          content: type == 'trigger'
              ? '新觸發事件...'
              : (type == 'condition' ? '如果...' : 'AI 執行...'),
          position: offset,
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
    if (_selectedNodeId == null || _selectedNodeId == 'start') return;
    setState(() {
      _nodes.removeWhere((n) => n.id == _selectedNodeId);
      // Clean up references in other nodes
      for (var node in _nodes) {
        node.childrenIds.remove(_selectedNodeId);
      }
      _selectedNodeId = null;
    });
  }

  bool _hasCycle(String startNodeId, String targetNodeId) {
    if (startNodeId == targetNodeId) return true;

    final visited = <String>{};
    final queue = <String>[targetNodeId];

    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);
      if (currentId == startNodeId) return true;

      if (!visited.contains(currentId)) {
        visited.add(currentId);
        final currentNode = _nodes.where((n) => n.id == currentId).firstOrNull;
        if (currentNode != null) {
          queue.addAll(currentNode.childrenIds);
        }
      }
    }
    return false;
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
                      n.id != parent.id &&
                      !parent.childrenIds.contains(n.id) &&
                      !_hasCycle(parent.id, n.id),
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

  void _showQuickAddMenu(ScriptNode parent) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '快速延伸節點',
              style: GoogleFonts.notoSansTc(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildQuickAddItem(
                  context,
                  parent,
                  '觸發',
                  Icons.mic,
                  Colors.blueAccent,
                  'trigger',
                ),
                _buildQuickAddItem(
                  context,
                  parent,
                  '動作',
                  Icons.auto_awesome,
                  Colors.purpleAccent,
                  'action',
                ),
                _buildQuickAddItem(
                  context,
                  parent,
                  '條件',
                  Icons.call_split,
                  Colors.orangeAccent,
                  'condition',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildQuickAddItem(
                  context,
                  parent,
                  '人格',
                  Icons.face,
                  Colors.tealAccent,
                  'persona',
                ),
                _buildQuickAddItem(
                  context,
                  parent,
                  '記憶',
                  Icons.memory,
                  Colors.amberAccent,
                  'memory',
                ),
                _buildQuickAddItem(
                  context,
                  parent,
                  '多擇',
                  Icons.list,
                  Colors.pinkAccent,
                  'choice',
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showInsertMenu(ScriptNode from, ScriptNode to) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '在中間插入節點',
              style: GoogleFonts.notoSansTc(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                _buildQuickAddItem(
                  context,
                  from,
                  '觸發',
                  Icons.mic,
                  Colors.blueAccent,
                  'trigger',
                  insertTo: to,
                ),
                _buildQuickAddItem(
                  context,
                  from,
                  '動作',
                  Icons.auto_awesome,
                  Colors.purpleAccent,
                  'action',
                  insertTo: to,
                ),
                _buildQuickAddItem(
                  context,
                  from,
                  '條件',
                  Icons.call_split,
                  Colors.orangeAccent,
                  'condition',
                  insertTo: to,
                ),
                _buildQuickAddItem(
                  context,
                  from,
                  '人格',
                  Icons.face,
                  Colors.tealAccent,
                  'persona',
                  insertTo: to,
                ),
                _buildQuickAddItem(
                  context,
                  from,
                  '記憶',
                  Icons.memory,
                  Colors.amberAccent,
                  'memory',
                  insertTo: to,
                ),
                _buildQuickAddItem(
                  context,
                  from,
                  '多擇',
                  Icons.list,
                  Colors.pinkAccent,
                  'choice',
                  insertTo: to,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAddItem(
    BuildContext context,
    ScriptNode parent,
    String label,
    IconData icon,
    Color color,
    String type, {
    ScriptNode? insertTo,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _addNodeLinked(parent, type, insertTo: insertTo);
      },
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.notoSansTc(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _addNodeLinked(ScriptNode parent, String type, {ScriptNode? insertTo}) {
    final id = 'node_${DateTime.now().millisecondsSinceEpoch}';
    IconData icon = Icons.help;
    Color color = Colors.grey;
    String title = '新節點';
    String content = '請點擊設定內容...';

    switch (type) {
      case 'trigger':
        icon = Icons.mic;
        color = Colors.blueAccent;
        title = '觸發';
        break;
      case 'action':
        icon = Icons.auto_awesome;
        color = Colors.purpleAccent;
        title = '動作';
        break;
      case 'condition':
        icon = Icons.call_split;
        color = Colors.orangeAccent;
        title = '條件';
        break;
      case 'persona':
        icon = Icons.face;
        color = Colors.tealAccent;
        title = 'AI 人格';
        break;
      case 'memory':
        icon = Icons.memory;
        color = Colors.amberAccent;
        title = 'AI 記憶';
        break;
      case 'choice':
        icon = Icons.list;
        color = Colors.pinkAccent;
        title = '多項選擇';
        break;
    }

    // Position new node below the parent with a slight horizontal offset if it's the 2nd/3rd child
    final horizontalOffset = (parent.childrenIds.length * 50.0) - 50.0;
    final newNode = ScriptNode(
      id: id,
      title: title,
      content: content,
      position: parent.position + Offset(horizontalOffset, 220),
      icon: icon,
      color: color,
    );

    setState(() {
      if (insertTo != null) {
        // Insert node in sequence: parent -> newNode -> insertTo
        parent.childrenIds.remove(insertTo.id);
        parent.childrenIds.add(id);
        newNode.childrenIds.add(insertTo.id);
      } else {
        parent.childrenIds.add(id);
      }
      _nodes.add(newNode);
      _selectedNodeId = id;
    });
  }

  Widget _buildComponentBox() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showComponentBox)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 15,
                ),
              ],
            ),
            child: Column(
              children: [
                _buildComponentIcon(
                  Icons.mic,
                  Colors.blueAccent,
                  '觸發',
                  () => _addNode('trigger'),
                ),
                _buildComponentIcon(
                  Icons.auto_awesome,
                  Colors.purpleAccent,
                  '動作',
                  () => _addNode('action'),
                ),
                _buildComponentIcon(
                  Icons.call_split,
                  Colors.orangeAccent,
                  '條件',
                  () => _addNode('condition'),
                ),
                const Divider(color: Colors.white10),
                if (_selectedNodeId != null)
                  _buildComponentIcon(
                    Icons.delete_outline,
                    Colors.redAccent,
                    '刪除',
                    _deleteSelectedNode,
                  ),
                _buildComponentIcon(
                  Icons.auto_fix_high,
                  Colors.amberAccent,
                  '對齊',
                  _tidyUpNodes,
                ),
              ],
            ),
          ).animate().slideY(begin: 0.2, end: 0).fadeIn(),
        FloatingActionButton(
          onPressed: () =>
              setState(() => _showComponentBox = !_showComponentBox),
          backgroundColor: Colors.blueAccent,
          child: Icon(
            _showComponentBox ? Icons.close : Icons.add,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildComponentIcon(
    IconData icon,
    Color color,
    String tooltip,
    VoidCallback onTap,
  ) {
    return IconButton(
      icon: Icon(icon, color: color),
      tooltip: tooltip,
      onPressed: () {
        onTap();
        setState(() => _showComponentBox = false);
      },
    );
  }

  Widget _buildCanvasControls() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(
              Icons.center_focus_strong,
              color: Colors.white70,
              size: 20,
            ),
            tooltip: '重置視角',
            onPressed: () {
              _transformationController.value = Matrix4.identity();
              setState(() {});
            },
          ),
          Container(width: 1, height: 20, color: Colors.white10),
          IconButton(
            icon: const Icon(Icons.zoom_in, color: Colors.white70, size: 20),
            onPressed: () {
              final val = _transformationController.value.clone();
              val.multiply(Matrix4.diagonal3Values(1.2, 1.2, 1.0));
              _transformationController.value = val;
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out, color: Colors.white70, size: 20),
            onPressed: () {
              final val = _transformationController.value.clone();
              val.multiply(Matrix4.diagonal3Values(0.8, 0.8, 1.0));
              _transformationController.value = val;
              setState(() {});
            },
          ),
        ],
      ),
    ).animate().slideY(begin: -0.5, end: 0).fadeIn();
  }

  void _loadBreadBakingTemplate() {
    setState(() {
      _nodes.clear();
      _nodes.addAll([
        ScriptNode(
          id: 'start',
          title: '每天 10:00',
          content: '定時自動開啟對話',
          position: const Offset(400, 100),
          icon: Icons.timer,
          color: Colors.blueAccent,
          triggerType: 'time',
          triggerTime: '10:00',
          childrenIds: ['node_search'],
        ),
        ScriptNode(
          id: 'node_search',
          title: '搜尋食譜',
          content: '搜尋簡單麵包食譜，並用溫暖語氣改寫',
          position: const Offset(400, 300),
          icon: Icons.auto_awesome,
          color: Colors.purpleAccent,
          childrenIds: ['node_reply'],
        ),
        ScriptNode(
          id: 'node_reply',
          title: '偵測媽媽反應',
          content: '系統將偵測：[負面/困難] 或是 [正面/有趣]',
          position: const Offset(400, 500),
          icon: Icons.list,
          color: Colors.pinkAccent,
          choiceLabels: ['這好像很難...', '太棒了，來試試！'],
          childrenIds: ['node_encourage', 'node_happy'],
        ),
        ScriptNode(
          id: 'node_encourage',
          title: 'AI 鼓勵模式',
          content: '不會啦！小明（孫子）上次說想吃耶，妳試試看？',
          position: const Offset(200, 750),
          icon: Icons.face,
          color: Colors.tealAccent,
          childrenIds: ['node_bridge'],
        ),
        ScriptNode(
          id: 'node_happy',
          title: 'AI 讚賞模式',
          content: '媽妳太厲害了！做完記得傳照片給我看喔！',
          position: const Offset(600, 750),
          icon: Icons.celebration,
          color: Colors.orangeAccent,
          childrenIds: ['node_bridge'],
        ),
        ScriptNode(
          id: 'node_bridge',
          title: '世代連結橋樑',
          content: '截圖通話摘要並發送給兒子：媽媽今天對做麵包很有興趣',
          position: const Offset(400, 1000),
          icon: Icons.family_restroom,
          color: Colors.greenAccent,
        ),
      ]);
      _selectedNodeId = 'start';
      _currentSimulatorNodeId = 'start';
    });
  }
}
