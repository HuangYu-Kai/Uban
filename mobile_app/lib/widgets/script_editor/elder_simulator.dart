import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:io';
import '../../models/script_node.dart';

class ElderSimulator extends StatelessWidget {
  final List<ScriptNode> allNodes;
  final String? currentSimulatorNodeId;
  final Function(String) onNodeChange;
  final VoidCallback onReset;

  const ElderSimulator({
    super.key,
    required this.allNodes,
    required this.currentSimulatorNodeId,
    required this.onNodeChange,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final currentNode = allNodes.any((n) => n.id == currentSimulatorNodeId)
        ? allNodes.firstWhere((n) => n.id == currentSimulatorNodeId)
        : allNodes.isNotEmpty
        ? allNodes.first
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
                onPressed: onReset,
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF0),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: Colors.grey[800]!, width: 8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: currentNode == null
                  ? const Center(child: Text('尚未定義腳本節點'))
                  : Column(
                      children: [
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
                                        if (currentNode.mediaUrl != null &&
                                            currentNode
                                                .mediaUrl!
                                                .isNotEmpty) ...[
                                          const SizedBox(height: 16),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            child:
                                                currentNode.mediaUrl!
                                                    .startsWith('http')
                                                ? Image.network(
                                                    currentNode.mediaUrl!,
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) => const Icon(
                                                          Icons.broken_image,
                                                          color: Colors.grey,
                                                        ),
                                                  )
                                                : Image.file(
                                                    File(currentNode.mediaUrl!),
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) => const Icon(
                                                          Icons.broken_image,
                                                          color: Colors.grey,
                                                        ),
                                                  ),
                                          ),
                                        ],
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
        _buildEventSimulationPanel(context),
        _buildSimulatorStatus(currentNode),
      ],
    );
  }

  Widget _buildEventSimulationPanel(BuildContext context) {
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
              _buildSimEventChip(
                context,
                '語音偵測',
                Icons.mic,
                'voice',
                Colors.blue,
              ),
              _buildSimEventChip(
                context,
                '定時到達',
                Icons.timer,
                'time',
                Colors.indigoAccent,
              ),
              _buildSimEventChip(
                context,
                '天氣變化',
                Icons.wb_cloudy,
                'weather',
                Colors.cyan,
              ),
              _buildSimEventChip(
                context,
                '健康數據',
                Icons.favorite,
                'health',
                Colors.redAccent,
              ),
              _buildSimEventChip(
                context,
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
    BuildContext context,
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
        final triggerNode =
            allNodes
                .where(
                  (n) =>
                      (n.title == '觸發' || n.triggerType != 'voice') &&
                      n.triggerType == type,
                )
                .firstOrNull ??
            allNodes.where((n) => n.id == 'start').firstOrNull;

        if (triggerNode != null) {
          onNodeChange(triggerNode.id);
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
        color: Colors.white.withValues(alpha: 0.1),
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

    final isChoiceNode =
        currentNode.title == '多項選擇' ||
        (currentNode.choiceLabels?.isNotEmpty ?? false);

    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white.withValues(alpha: 0.1),
      child: Column(
        children: List.generate(currentNode.childrenIds.length, (index) {
          final cid = currentNode.childrenIds[index];
          final nextNodes = allNodes.where((n) => n.id == cid).toList();
          if (nextNodes.isEmpty) return const SizedBox.shrink();
          final nextNode = nextNodes.first;

          String buttonLabel = '下一步：${nextNode.title}';
          if (isChoiceNode &&
              currentNode.choiceLabels != null &&
              index < currentNode.choiceLabels!.length) {
            buttonLabel = currentNode.choiceLabels![index];
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () => onNodeChange(cid),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      nextNode.color,
                      nextNode.color.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: nextNode.color.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(nextNode.icon, color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        buttonLabel,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansTc(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
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
}
