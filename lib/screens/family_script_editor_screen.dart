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

  ScriptNode({
    required this.id,
    required this.title,
    required this.content,
    required this.position,
    required this.icon,
    required this.color,
    this.childrenIds = const [],
  });
}

class _FamilyScriptEditorScreenState extends State<FamilyScriptEditorScreen> {
  final List<ScriptNode> _nodes = [];
  String? _selectedNodeId;
  bool _showSimulator = false;

  @override
  void initState() {
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
                  constrained: false,
                  minScale: 0.1,
                  maxScale: 2.0,
                  child: SizedBox(
                    width: 2000,
                    height: 2000,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(painter: GridPainter()),
                        ),
                        Positioned.fill(
                          child: CustomPaint(painter: NodeLinkPainter(_nodes)),
                        ),
                        ..._nodes.map((node) => _buildNodeCard(node)),
                      ],
                    ),
                  ),
                ),
                Positioned(left: 20, top: 20, child: _buildToolbar()),
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: _buildToggleSimulatorButton(),
                ),
              ],
            ),
          ),

          // 右側模擬器面板 (Simulator)
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
    ).animate().scale(delay: 500.ms);
  }

  Widget _buildNodeCard(ScriptNode node) {
    bool isSelected = _selectedNodeId == node.id;
    return Positioned(
      left: node.position.dx,
      top: node.position.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => node.position += d.delta),
        onTap: () => setState(() => _selectedNodeId = node.id),
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF252525),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? Colors.white
                  : node.color.withValues(alpha: 0.3),
              width: isSelected ? 3 : 1,
            ),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: node.color.withValues(alpha: 0.3),
                  blurRadius: 20,
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
              Text(
                node.content,
                style: GoogleFonts.notoSansTc(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildElderSimulator() {
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
              child: Column(
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
                                    backgroundColor: Colors.blue[100],
                                    child: const Icon(
                                      Icons.smart_toy,
                                      size: 40,
                                      color: Colors.blue,
                                    ),
                                  )
                                  .animate(
                                    onPlay: (c) => c.repeat(reverse: true),
                                  )
                                  .scale(
                                    duration: 2.seconds,
                                    begin: const Offset(1, 1),
                                    end: const Offset(1.1, 1.1),
                                  ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: const Text(
                                '長輩：我今天好無聊...\n\nAI：聽起來您今天想聊聊天呢！要不要來聽聽關於阿里山的老故事？',
                                style: TextStyle(
                                  fontSize: 18,
                                  height: 1.5,
                                  color: Colors.black87,
                                ),
                              ),
                            )
                            .animate()
                            .fadeIn(delay: 500.ms)
                            .slideY(begin: 0.1, end: 0),
                      ],
                    ),
                  ),
                  _buildMockElderButtons(),
                ],
              ),
            ),
          ),
        ),
        _buildSimulatorStatus(),
      ],
    );
  }

  Widget _buildMockElderButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white70,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Text(
                  '好啊！',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Text('先不要', style: TextStyle(color: Colors.black54)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulatorStatus() {
    return Container(
      padding: const EdgeInsets.all(24),
      color: Colors.blueAccent.withValues(alpha: 0.1),
      child: Row(
        children: [
          const Icon(Icons.flash_on, color: Colors.blueAccent, size: 16),
          const SizedBox(width: 8),
          Text(
            '正在根據當前動作節點運算...',
            style: GoogleFonts.notoSansTc(
              color: Colors.blueAccent,
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
      ),
      child: Column(
        children: [
          IconButton(
            icon: const Icon(Icons.add_box_outlined, color: Colors.white70),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.smart_button, color: Colors.purpleAccent),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () {},
          ),
        ],
      ),
    ).animate().slideX(begin: -1.0, end: 0);
  }
}

class NodeLinkPainter extends CustomPainter {
  final List<ScriptNode> nodes;
  NodeLinkPainter(this.nodes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var node in nodes) {
      if (node.childrenIds.isEmpty) continue;
      final start = node.position + const Offset(110, 80);
      for (var cid in node.childrenIds) {
        final childNode = nodes.firstWhere((n) => n.id == cid);
        final end = childNode.position + const Offset(110, 0);
        final path = Path()..moveTo(start.dx, start.dy);
        path.cubicTo(
          start.dx,
          start.dy + 60,
          end.dx,
          end.dy - 60,
          end.dx,
          end.dy,
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
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
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
