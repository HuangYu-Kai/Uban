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
  final String type; // 'trigger', 'action', 'logic', 'rag'

  ScriptNode({
    required this.id,
    required this.title,
    required this.content,
    required this.position,
    required this.icon,
    required this.color,
    this.childrenIds = const [],
    this.type = 'action',
  });
}

class _FamilyScriptEditorScreenState extends State<FamilyScriptEditorScreen> {
  final List<ScriptNode> _nodes = [];
  String? _selectedNodeId;
  bool _isGeneratingAI = false;
  final TransformationController _transformationController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    _resetToDefault();
  }

  void _resetToDefault() {
    _nodes.clear();
    _nodes.addAll([
      ScriptNode(
        id: 'start',
        title: '觸發時機',
        content: '當長輩提到「以前的事情」',
        position: const Offset(400, 100),
        icon: Icons.mic_none_rounded,
        color: Colors.blueAccent,
        childrenIds: ['rag_search'],
        type: 'trigger',
      ),
      ScriptNode(
        id: 'rag_search',
        title: '知識庫檢索 (RAG)',
        content: '檢索關鍵字：#1970年代 #阿里山 #老照片',
        position: const Offset(400, 300),
        icon: Icons.search_rounded,
        color: Colors.cyanAccent,
        childrenIds: ['ai_reply'],
        type: 'rag',
      ),
      ScriptNode(
        id: 'ai_reply',
        title: 'AI 情感回應',
        content: '語音引導：\n「哇！這張照片是在阿里山拍的嗎？那天很涼爽吧？」',
        position: const Offset(400, 500),
        icon: Icons.auto_awesome_rounded,
        color: Colors.purpleAccent,
        type: 'action',
      ),
    ]);
  }

  void _addNode(String type) {
    setState(() {
      final id = 'node_${DateTime.now().millisecondsSinceEpoch}';
      Color color = Colors.grey;
      IconData icon = Icons.help_outline;
      String title = '新節點';

      if (type == 'action') {
        color = Colors.purpleAccent;
        icon = Icons.play_arrow_rounded;
        title = '執行動作';
      } else if (type == 'rag') {
        color = Colors.cyanAccent;
        icon = Icons.storage_rounded;
        title = '檢索記憶環節';
      }

      _nodes.add(
        ScriptNode(
          id: id,
          title: title,
          content: '點擊編輯內容...',
          position: const Offset(200, 200),
          icon: icon,
          color: color,
          type: type,
        ),
      );
    });
  }

  Future<void> _generateWithAI() async {
    setState(() => _isGeneratingAI = true);
    await Future.delayed(2.seconds); // 模擬 AI 思考

    setState(() {
      _isGeneratingAI = false;
      // AI 幫忙增加一個分叉：如果長輩沒回應，則推播一張老照片
      if (!_nodes.any((n) => n.id == 'ai_branch')) {
        final last = _nodes.lastWhere((n) => n.id == 'ai_reply');

        final branchId = 'ai_branch_logic';
        _nodes.add(
          ScriptNode(
            id: branchId,
            title: 'AI 智慧分叉',
            content: '如果長輩沈默超過 10 秒',
            position: const Offset(650, 600),
            icon: Icons.alt_route_rounded,
            color: Colors.orangeAccent,
            childrenIds: ['photo_push'],
            type: 'logic',
          ),
        );

        _nodes.add(
          ScriptNode(
            id: 'photo_push',
            title: '視覺引導',
            content: '推播老照片集至電視/螢幕',
            position: const Offset(650, 800),
            icon: Icons.image_rounded,
            color: Colors.pinkAccent,
            type: 'action',
          ),
        );

        // 建立連接
        final index = _nodes.indexOf(last);
        _nodes[index] = ScriptNode(
          id: last.id,
          title: last.title,
          content: last.content,
          position: last.position,
          icon: last.icon,
          color: last.color,
          type: last.type,
          childrenIds: [branchId],
        );
      }
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('✨ AI 已為您優化劇本邏輯：新增了沈默時的視覺引導')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: Text(
          widget.scriptTitle,
          style: GoogleFonts.notoSansTc(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          _buildAIButton(),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.save, color: Colors.blueAccent),
            label: Text(
              '儲存編輯',
              style: GoogleFonts.notoSansTc(color: Colors.blueAccent),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Stack(
        children: [
          InteractiveViewer(
            transformationController: _transformationController,
            constrained: false,
            minScale: 0.1,
            maxScale: 2.5,
            child: SizedBox(
              width: 3000,
              height: 3000,
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: GridPainter())),
                  Positioned.fill(
                    child: CustomPaint(painter: NodeLinkPainter(_nodes)),
                  ),
                  ..._nodes.map((node) => _buildNodeCard(node)),
                ],
              ),
            ),
          ),

          if (_isGeneratingAI)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.purpleAccent),
                    const SizedBox(height: 16),
                    Text(
                      'UniFlow AI 正在生成智慧邏輯...',
                      style: GoogleFonts.notoSansTc(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Positioned(left: 20, top: 20, child: _buildEditorToolbar()),
        ],
      ),
    );
  }

  Widget _buildAIButton() {
    return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ElevatedButton.icon(
            onPressed: _isGeneratingAI ? null : _generateWithAI,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('AI 生成輔助'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple[700],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        )
        .animate(onPlay: (controller) => controller.repeat(reverse: true))
        .shimmer(duration: 2.seconds, color: Colors.white24);
  }

  Widget _buildNodeCard(ScriptNode node) {
    final bool isSelected = _selectedNodeId == node.id;

    return Positioned(
      left: node.position.dx,
      top: node.position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final index = _nodes.indexOf(node);
            _nodes[index].position += details.delta;
          });
        },
        onTap: () => setState(() => _selectedNodeId = node.id),
        child:
            Container(
                  width: 260,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? Colors.white
                          : node.color.withValues(alpha: 0.4),
                      width: isSelected ? 3 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: node.color.withValues(
                          alpha: isSelected ? 0.3 : 0.05,
                        ),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(node.icon, color: node.color, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            node.title,
                            style: GoogleFonts.notoSansTc(
                              color: node.color,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white10, height: 24),
                      Text(
                        node.content,
                        style: GoogleFonts.notoSansTc(
                          color: Colors.white,
                          fontSize: 17,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                )
                .animate(target: isSelected ? 1 : 0)
                .scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.03, 1.03),
                ),
      ),
    );
  }

  Widget _buildEditorToolbar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          _toolbarIcon(
            Icons.add_task_rounded,
            '新增動作',
            () => _addNode('action'),
          ),
          _toolbarIcon(Icons.cloud_sync_rounded, '新增檢索', () => _addNode('rag')),
          _toolbarIcon(Icons.alt_route_rounded, '新增判斷', () {}),
          const Divider(color: Colors.white10),
          _toolbarIcon(Icons.refresh_rounded, '重置劇本', _resetToDefault),
        ],
      ),
    );
  }

  Widget _toolbarIcon(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: Colors.white70, size: 24),
      onPressed: onTap,
      tooltip: tooltip,
    );
  }
}

class NodeLinkPainter extends CustomPainter {
  final List<ScriptNode> nodes;
  NodeLinkPainter(this.nodes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (var node in nodes) {
      if (node.childrenIds.isEmpty) continue;

      final startPoint = node.position + const Offset(130, 110);

      for (var childId in node.childrenIds) {
        final findChild = nodes.where((n) => n.id == childId);
        if (findChild.isEmpty) continue;

        final childNode = findChild.first;
        final endPoint = childNode.position + const Offset(130, 0);

        final path = Path();
        path.moveTo(startPoint.dx, startPoint.dy);

        final controlPoint1 = Offset(startPoint.dx, startPoint.dy + 80);
        final controlPoint2 = Offset(endPoint.dx, endPoint.dy - 80);

        path.cubicTo(
          controlPoint1.dx,
          controlPoint1.dy,
          controlPoint2.dx,
          controlPoint2.dy,
          endPoint.dx,
          endPoint.dy,
        );

        canvas.drawPath(path, paint);
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
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 1;

    const spacing = 50.0;
    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
