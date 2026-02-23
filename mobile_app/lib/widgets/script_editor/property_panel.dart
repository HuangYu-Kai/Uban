import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../models/script_node.dart';

class PropertyPanel extends StatelessWidget {
  final ScriptNode node;
  final List<ScriptNode> allNodes;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;
  final VoidCallback onClose;
  final VoidCallback onAddConnection;

  const PropertyPanel({
    super.key,
    required this.node,
    required this.allNodes,
    required this.onUpdate,
    required this.onDelete,
    required this.onClose,
    required this.onAddConnection,
  });

  @override
  Widget build(BuildContext context) {
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
                onPressed: onClose,
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildPanelField('標題', node.title, (val) {
                node.title = val;
                onUpdate();
              }),
              const SizedBox(height: 20),
              _buildPanelField('內容 / 腳本', node.content, (val) {
                node.content = val;
                onUpdate();
              }, maxLines: 5),
              const SizedBox(height: 24),

              // Conditional Fields based on node type
              if (node.title == '觸發' || node.icon == Icons.mic) ...[
                _buildSectionTitle('觸發來源設定'),
                _buildDropdownField(
                  '觸發類型',
                  node.triggerType,
                  ['voice', 'time', 'weather', 'health', 'iot'],
                  (val) {
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
                    onUpdate();
                  },
                  displayNames: {
                    'voice': '語音偵測',
                    'time': '定時觸發',
                    'weather': '天氣變化',
                    'health': '健康數據',
                    'iot': '感測器觸發',
                  },
                ),
                const SizedBox(height: 16),

                if (node.triggerType == 'voice') ...[
                  _buildPanelField(
                    '關鍵字 (用逗號隔開)',
                    (node.keywords ?? []).join(','),
                    (val) {
                      node.keywords = val
                          .split(',')
                          .map((e) => e.trim())
                          .toList();
                      onUpdate();
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildSliderField(
                    '情緒門檻 (低於此值觸發)',
                    node.moodThreshold ?? 0.5,
                    0,
                    1,
                    (val) {
                      node.moodThreshold = val;
                      onUpdate();
                    },
                  ),
                ],

                if (node.triggerType == 'time') ...[
                  _buildTimeField(
                    context,
                    '觸發時間',
                    node.triggerTime ?? '08:00',
                    (val) {
                      node.triggerTime = val;
                      onUpdate();
                    },
                  ),
                ],

                if (node.triggerType == 'weather') ...[
                  _buildDropdownField(
                    '天氣狀況',
                    node.weatherCondition ?? '雨天',
                    ['雨天', '高溫', '低溫', '颱風', '強風'],
                    (val) {
                      node.weatherCondition = val;
                      onUpdate();
                    },
                  ),
                ],

                if (node.triggerType == 'health') ...[
                  _buildDropdownField(
                    '監測清單',
                    node.healthMetric ?? '心率',
                    ['心率', '步數', '異常靜止', '血壓'],
                    (val) {
                      node.healthMetric = val;
                      onUpdate();
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildPanelField('異常數值設定', node.healthThreshold.toString(), (
                    val,
                  ) {
                    node.healthThreshold = double.tryParse(val) ?? 100;
                    onUpdate();
                  }),
                ],

                if (node.triggerType == 'iot') ...[
                  _buildDropdownField(
                    '設備類型',
                    node.iotDevice ?? '門窗感測器',
                    ['門窗感測器', '藥盒感測器', '跌倒偵測器', '瓦斯偵測', '床墊感測器'],
                    (val) {
                      node.iotDevice = val;
                      onUpdate();
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildDropdownField(
                    '事件動作',
                    node.iotEvent ?? '開啟',
                    ['開啟', '關閉', '觸發', '未動作', '低電量'],
                    (val) {
                      node.iotEvent = val;
                      onUpdate();
                    },
                  ),
                ],
                const SizedBox(height: 16),
              ],

              if (node.title == '動作' || node.icon == Icons.auto_awesome) ...[
                _buildSectionTitle('動作設定'),
                _buildDropdownField(
                  '語氣選擇',
                  node.voiceTone ?? '溫暖',
                  ['溫暖', '幽默', '理性', '活力'],
                  (val) {
                    node.voiceTone = val;
                    onUpdate();
                  },
                ),
                const SizedBox(height: 16),
                _buildSliderField(
                  '延遲發送 (秒)',
                  node.delaySeconds.toDouble(),
                  0,
                  60,
                  (val) {
                    node.delaySeconds = val.toInt();
                    onUpdate();
                  },
                ),
                const SizedBox(height: 16),
                _buildPanelField('附件圖片/影片 URL', node.mediaUrl ?? '', (val) {
                  node.mediaUrl = val;
                  onUpdate();
                }),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picker = ImagePicker();
                          final XFile? image = await picker.pickImage(
                            source: ImageSource.gallery,
                          );
                          if (image != null) {
                            node.mediaUrl = image.path;
                            onUpdate();
                          }
                        },
                        icon: const Icon(Icons.image_search, size: 18),
                        label: const Text('從相簿選擇'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.tealAccent,
                          side: const BorderSide(color: Colors.tealAccent),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picker = ImagePicker();
                          final XFile? image = await picker.pickImage(
                            source: ImageSource.camera,
                          );
                          if (image != null) {
                            node.mediaUrl = image.path;
                            onUpdate();
                          }
                        },
                        icon: const Icon(Icons.camera_alt, size: 18),
                        label: const Text('開啟相機'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.tealAccent,
                          side: const BorderSide(color: Colors.tealAccent),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (node.mediaUrl != null && node.mediaUrl!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: node.mediaUrl!.startsWith('http')
                        ? Image.network(
                            node.mediaUrl!,
                            height: 120,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.broken_image,
                                  color: Colors.white24,
                                ),
                          )
                        : Image.file(
                            File(node.mediaUrl!),
                            height: 120,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.broken_image,
                                  color: Colors.white24,
                                ),
                          ),
                  ),
                ],
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
                    node.moodThreshold = val;
                    onUpdate();
                  },
                ),
                const SizedBox(height: 16),
                _buildDropdownField(
                  '適用時段',
                  node.timeRange ?? '全天',
                  ['全天', '早上', '下午', '晚上'],
                  (val) {
                    node.timeRange = val;
                    onUpdate();
                  },
                ),
                const SizedBox(height: 16),
              ],

              if (node.title == 'AI 人格' || node.icon == Icons.face) ...[
                _buildSectionTitle('人格設定'),
                _buildPanelField('人格名稱', node.personaName ?? '小助手', (val) {
                  node.personaName = val;
                  onUpdate();
                }),
                const SizedBox(height: 16),
                _buildPanelField(
                  '人格提示詞 (System Prompt)',
                  node.personaPrompt ?? '',
                  (val) {
                    node.personaPrompt = val;
                    onUpdate();
                  },
                  maxLines: 5,
                ),
                const SizedBox(height: 16),
              ],

              if (node.title == 'AI 記憶' || node.icon == Icons.memory) ...[
                _buildSectionTitle('記憶存根'),
                _buildPanelField('記憶鍵 (Key)', node.memoryKey ?? '', (val) {
                  node.memoryKey = val;
                  onUpdate();
                }),
                const SizedBox(height: 16),
                _buildPanelField('記憶值 (Value)', node.memoryValue ?? '', (val) {
                  node.memoryValue = val;
                  onUpdate();
                }),
                const SizedBox(height: 16),
              ],

              if (node.title == '多項選擇' || node.icon == Icons.list) ...[
                _buildSectionTitle('分支出口'),
                _buildPanelField(
                  '選項 (用逗號隔開)',
                  (node.choiceLabels ?? []).join(','),
                  (val) {
                    node.choiceLabels = val
                        .split(',')
                        .map((e) => e.trim())
                        .toList();
                    onUpdate();
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
              onPressed: node.id == 'start' ? null : onDelete,
              style: ElevatedButton.styleFrom(
                backgroundColor: node.id == 'start'
                    ? Colors.grey.withValues(alpha: 0.1)
                    : Colors.redAccent.withValues(alpha: 0.1),
                foregroundColor: node.id == 'start'
                    ? Colors.grey
                    : Colors.redAccent,
                side: BorderSide(
                  color: node.id == 'start' ? Colors.grey : Colors.redAccent,
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(node.id == 'start' ? '起始節點不可刪除' : '刪除此節點'),
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
    String? value,
    List<String> options,
    Function(String) onChanged, {
    Map<String, String>? displayNames,
  }) {
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
                return DropdownMenuItem<String>(
                  value: val,
                  child: Text(displayNames?[val] ?? val),
                );
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
          final child = allNodes.firstWhere((n) => n.id == cid);
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
                  onPressed: () {
                    node.childrenIds.remove(cid);
                    onUpdate();
                  },
                ),
              ],
            ),
          );
        }),
        OutlinedButton.icon(
          onPressed: onAddConnection,
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

  Widget _buildTimeField(
    BuildContext context,
    String label,
    String value,
    Function(String) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            label,
            style: GoogleFonts.notoSansTc(color: Colors.white54, fontSize: 13),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: InkWell(
            onTap: () async {
              final timeParts = value.split(':');
              final initialTime = TimeOfDay(
                hour: int.tryParse(timeParts[0]) ?? 8,
                minute: timeParts.length > 1
                    ? (int.tryParse(timeParts[1]) ?? 0)
                    : 0,
              );
              final pickedTime = await showTimePicker(
                context: context,
                initialTime: initialTime,
              );
              if (pickedTime != null) {
                final formattedTime =
                    '${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}';
                onChanged(formattedTime);
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.access_time,
                    color: Colors.blueAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    value,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const Spacer(),
                  const Icon(Icons.edit, color: Colors.white24, size: 16),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
