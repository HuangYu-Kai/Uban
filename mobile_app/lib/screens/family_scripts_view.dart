import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'family_script_editor_screen.dart';
import 'family_marketplace_view.dart';
import '../services/script_data_service.dart';

class FamilyScriptsView extends StatefulWidget {
  const FamilyScriptsView({super.key});

  @override
  State<FamilyScriptsView> createState() => _FamilyScriptsViewState();
}

class _FamilyScriptsViewState extends State<FamilyScriptsView> {
  late List<ScriptMetadata> _scripts;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await ScriptDataService().ensureLoaded();
    _refreshScripts();
  }

  void _refreshScripts() {
    if (!mounted) return;
    setState(() {
      _scripts = List.from(ScriptDataService().getAllScripts());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF0),
      appBar: AppBar(
        title: Text(
          '劇本管理',
          style: GoogleFonts.notoSansTc(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.add_circle_outline,
              color: Color(0xFFFF9800),
              size: 30,
            ),
            onPressed: () => _showCreateScriptSheet(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 0. Marketplace Banner
            _buildMarketplaceBanner(context),
            const SizedBox(height: 32),

            // 1. 推薦模版 (Templates)
            Text(
              '推薦模版 (Templates)',
              style: GoogleFonts.notoSansTc(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 140,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildTemplateCard(
                    '☀️ 早安日報',
                    'AI 自動對話流',
                    Colors.blue[50]!,
                    Colors.blue[700]!,
                  ),
                  _buildTemplateCard(
                    '💊 吃藥提醒',
                    '多重通知邏輯',
                    Colors.orange[50]!,
                    Colors.orange[700]!,
                  ),
                  _buildTemplateCard(
                    '🎂 生日驚喜',
                    '多媒體自動推播',
                    Colors.red[50]!,
                    Colors.red[700]!,
                  ),
                  _buildTemplateCard(
                    '🧘 運動提醒',
                    '健康教練介入',
                    Colors.green[50]!,
                    Colors.green[700]!,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 2. 我的活躍劇本 (Active Flows)
            Text(
              '我的活躍劇本 (Active Flows)',
              style: GoogleFonts.notoSansTc(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 16),
            ..._scripts.map((script) => _buildFlowItem(context, script)),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateCard(
    String title,
    String subtitle,
    Color bg,
    Color textColor,
  ) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: textColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.notoSansTc(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.notoSansTc(
              fontSize: 12,
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowItem(BuildContext context, ScriptMetadata script) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                FamilyScriptEditorScreen(scriptTitle: script.title),
          ),
        ).then((_) => _refreshScripts());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
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
                Icon(script.statusIcon, color: script.statusColor, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    script.title,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: script.isActive ? Colors.black87 : Colors.grey,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                  onPressed: () => _showRenameDialog(context, script),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.redAccent,
                  ),
                  onPressed: () => _showDeleteConfirm(context, script),
                ),
                Switch(
                  value: script.isActive,
                  onChanged: (v) async {
                    await ScriptDataService().toggleScriptActive(
                      script.title,
                      v,
                    );
                    _refreshScripts();
                  },
                  activeThumbColor: const Color(0xFFFF9800),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildDetailRow(Icons.access_time, '觸發：', script.trigger),
            const SizedBox(height: 8),
            _buildDetailRow(Icons.play_circle_outline, '動作：', script.action),
            const SizedBox(height: 8),
            _buildDetailRow(Icons.psychology_outlined, '邏輯：', script.logic),
          ],
        ),
      ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.1, end: 0),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.notoSansTc(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMarketplaceBanner(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const FamilyMarketplaceView(),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          image: const DecorationImage(
            image: NetworkImage(
              'https://images.unsplash.com/photo-1516321318423-f06f85e504b3?q=80&w=2070&auto=format&fit=crop',
            ),
            fit: BoxFit.cover,
            opacity: 0.1,
          ),
          gradient: const LinearGradient(
            colors: [Color(0xFF212121), Color(0xFF424242)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront, color: Colors.amber, size: 28),
                const SizedBox(width: 12),
                Text(
                  '劇本市集',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white54,
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '探索由專家設計的專業陪伴流程\n失智關懷、健康提醒、情感導引...',
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                color: Colors.white70,
                height: 1.5,
              ),
            ),
          ],
        ),
      ).animate().shimmer(delay: 1.seconds, duration: 1500.ms),
    );
  }

  void _showCreateScriptSheet(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '新增智慧劇本',
                style: GoogleFonts.notoSansTc(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '為您的長輩量身打造專屬的 AI 互動流程',
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: controller,
                autofocus: true,
                style: GoogleFonts.notoSansTc(fontSize: 18),
                decoration: InputDecoration(
                  labelText: '劇本名稱',
                  hintText: '例如：寒流早晨關懷、吃藥後散步提醒...',
                  prefixIcon: const Icon(Icons.edit_note),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      child: Text(
                        '取消',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (controller.text.isNotEmpty) {
                          await ScriptDataService().addScript(
                            ScriptMetadata(title: controller.text),
                          );
                          _refreshScripts();
                          if (!context.mounted) return;
                          Navigator.pop(context); // Close sheet
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FamilyScriptEditorScreen(
                                scriptTitle: controller.text,
                                isNew: true,
                              ),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9800),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        '開啟編輯器',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, ScriptMetadata script) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除劇本'),
        content: Text('確定要刪除「${script.title}」嗎？此動作無法撤銷。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await ScriptDataService().deleteScript(script.title);
              if (context.mounted) {
                _refreshScripts();
                Navigator.pop(context);
              }
            },
            child: const Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, ScriptMetadata script) {
    final controller = TextEditingController(text: script.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新命名劇本'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '劇本名稱'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await ScriptDataService().updateScriptTitle(
                  script.title,
                  controller.text,
                );
                _refreshScripts();
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('更名'),
          ),
        ],
      ),
    );
  }
}
