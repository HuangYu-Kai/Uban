import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/elder.dart';
import '../../services/signaling.dart';
import '../../services/api_service.dart';
import '../video_call_screen.dart';
import 'family_subscription_screen.dart';

class FamilyInteractionTab extends StatefulWidget {
  final Elder? currentElder;
  final Signaling signaling;
  final List<dynamic> monitorDevices;
  final List<Map<String, dynamic>> activeAlerts;
  final int devicesMax;
  final String tierDisplayName;

  /// ★ 2026-08-04 第 6 項：訂閱層級代號（free / gold / diamond），
  /// 供徽章依層級套用不同顏色。顯示文字仍一律使用 [tierDisplayName]
  /// （一般會員／黃金會員／鑽石會員），代號不直接曝露給使用者。
  final String tierLevel;
  final int? userId;

  const FamilyInteractionTab({
    super.key,
    required this.currentElder,
    required this.signaling,
    this.monitorDevices = const [],
    this.activeAlerts = const [],
    this.devicesMax = 2,
    this.tierDisplayName = '一般會員',
    this.tierLevel = 'free',
    this.userId,
  });

  @override
  State<FamilyInteractionTab> createState() => _FamilyInteractionTabState();
}

class _FamilyInteractionTabState extends State<FamilyInteractionTab> {
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;

  /// ★ 2026-08-04 第 7 項：警報語音橋狀態。key = alert_id，value = expire_at 字串。
  /// 後端在派送警報時（`yolo_alert_dispatcher._insert_alert`）就已自動為每位家屬
  /// 建立 30 分鐘權限，所以這裡多半是「查到已開啟」而不是由家屬手動開通；
  /// 按鈕的主要用途是**延長**（再按一次 = 從現在起重新算 30 分鐘）與顯示狀態。
  final Map<int, String> _audioBridgeExpire = {};

  /// 正在送出開通請求的 alert_id，避免連點造成重複請求。
  final Set<int> _audioBridgePending = {};

  /// 已查詢過語音橋狀態的 alert_id，避免每次 rebuild 都打一次 API。
  final Set<int> _audioBridgeChecked = {};

  final List<String> _quickMessages = [
    '記得吃藥喔！💊',
    '今天過得好嗎？🌸',
    '吃飽了沒？🍚',
    '等一下打電話給您！📞',
    '今天天氣變冷了，多穿點衣服！🧣',
    '注意多喝水喔！🥤',
  ];

  @override
  void initState() {
    super.initState();
    _syncAudioBridgeForAlerts();
  }

  @override
  void didUpdateWidget(covariant FamilyInteractionTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 新警報進來時才查一次語音橋狀態（_audioBridgeChecked 保證同一 alert 只查一次）
    if (widget.activeAlerts.length != oldWidget.activeAlerts.length) {
      _syncAudioBridgeForAlerts();
    }
  }

  /// ★ 2026-08-04 第 7 項：為尚未查過的警報查詢語音橋狀態。
  /// 任何一筆查詢失敗都只略過該筆，不影響其餘警報，也不彈任何錯誤給使用者——
  /// 語音權限是輔助功能，不能讓它的網路問題干擾警報本身的顯示。
  Future<void> _syncAudioBridgeForAlerts() async {
    for (final alert in widget.activeAlerts) {
      final alertId = int.tryParse(
        (alert['alert_id'] ?? alert['alertId'])?.toString() ?? '',
      );
      if (alertId == null || _audioBridgeChecked.contains(alertId)) continue;
      _audioBridgeChecked.add(alertId);
      try {
        // ★ 2026-08-05 第十七輪（安全）：帶上 userId，讓後端走完整關係驗證分支
        final data = await ApiService.checkAudioBridge(
          alertId,
          userId: widget.userId,
        );
        if (!mounted) return;
        if (data != null && data['has_audio_bridge'] == true) {
          setState(() {
            _audioBridgeExpire[alertId] = (data['expire_at'] ?? '').toString();
          });
        }
      } catch (_) {
        // 略過此筆，下次有新警報時不會重試（已記入 _audioBridgeChecked），
        // 家屬仍可手動按下按鈕主動開通。
      }
    }
  }

  /// ★ 2026-08-04 第 7 項：開通／延長 30 分鐘單向語音（家屬 → 監視機）。
  Future<void> _openAudioBridge(int alertId, int deviceId) async {
    final userId = widget.userId;
    if (userId == null || _audioBridgePending.contains(alertId)) return;

    setState(() => _audioBridgePending.add(alertId));
    try {
      final data = await ApiService.openAudioBridge(
        alertId: alertId,
        fromId: userId,
        toDeviceId: deviceId,
      );
      if (!mounted) return;
      if (data != null) {
        setState(() {
          _audioBridgeExpire[alertId] = (data['expire_at'] ?? '').toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已開啟語音通道，30 分鐘內可對該監視機說話'),
            backgroundColor: Color(0xFF59B294),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('開啟語音通道失敗，請稍後再試')),
        );
      }
    } finally {
      if (mounted) setState(() => _audioBridgePending.remove(alertId));
    }
  }

  /// 把後端回傳的 expire_at（ISO 字串）轉成「剩 N 分鐘」。解析失敗就不顯示時間。
  String? _audioBridgeRemainText(String? expireAt) {
    if (expireAt == null || expireAt.isEmpty) return null;
    final expire = DateTime.tryParse(expireAt);
    if (expire == null) return null;
    final remain = expire.difference(DateTime.now()).inMinutes;
    if (remain <= 0) return null;
    return '剩 $remain 分鐘';
  }

  /// ★ 2026-08-04 第 7 項：警報卡片上的語音通道按鈕。
  Widget _buildAudioBridgeButton(int alertId, int deviceId) {
    final isPending = _audioBridgePending.contains(alertId);
    final remainText = _audioBridgeRemainText(_audioBridgeExpire[alertId]);
    final isOpen = remainText != null;

    return SizedBox(
      height: 32,
      child: OutlinedButton.icon(
        onPressed: isPending ? null : () => _openAudioBridge(alertId, deviceId),
        icon: Icon(
          isOpen ? Icons.volume_up_rounded : Icons.mic_none_rounded,
          size: 16,
        ),
        label: Text(
          isPending
              ? '開啟中…'
              : isOpen
                  ? '語音通道已開啟（$remainText）'
                  : '開啟語音通道 30 分鐘',
          style: GoogleFonts.notoSansTc(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: isOpen ? const Color(0xFF59B294) : Colors.red.shade700,
          side: BorderSide(
            color: isOpen ? const Color(0xFF59B294) : Colors.red.shade300,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _showAddMonitorDialog() async {
    if (widget.currentElder == null) return;
    final prefs = await SharedPreferences.getInstance();
    final familyId = prefs.getInt('caregiver_id');
    if (!mounted) return;   // await 期間畫面可能已被銷毀，先確認再碰 context
    if (familyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('無法取得您的帳號 ID')));
      return;
    }

    final String rawId = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();
    final TextEditingController nameCtrl = TextEditingController(text: '客廳攝影機');
    
    if (!mounted) return;
    
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增監控設備'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('請輸入此監控設備的名稱：'),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '例如: 客廳、臥室',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('產生代碼'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final data = await ApiService.createMonitorSetup(familyId, rawId, nameCtrl.text);
    if (!mounted) return;
    Navigator.pop(context); // close loading

    // ★ issue 6：後端 /api/pairing/monitor_setup 回傳的欄位名為 'code'，非 'pairing_code'
    if (data != null && data['code'] != null) {
      final code = data['code'];
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('設備配對碼已產生'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('請在要作為攝影機的備用手機上，安裝 Uban 長輩版並選擇「作為監控設備登入」，然後輸入以下 6 位數代碼：'),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  code,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: Colors.blue.shade700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '此代碼將在 15 分鐘後失效。',
                style: TextStyle(color: Colors.red.shade400, fontSize: 12),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('完成'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('產生配對碼失敗，請稍後再試')),
      );
    }
  }

  void _makeVideoCall() {
    if (widget.currentElder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先在頂部選擇要關照的長輩')),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final String rawId = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '選擇通話方式',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 24),
                // 一般通話按鈕
                _buildCallOptionButton(
                  title: '一般視訊通話',
                  subtitle: '長輩需手動接聽後建立連線',
                  icon: Icons.video_call_rounded,
                  color: const Color(0xFF3B82F6),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VideoCallScreen(
                          roomId: 'comm_elder_$rawId',
                          autoStart: true,
                          isEmergency: false,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                // 緊急強制通話按鈕
                _buildCallOptionButton(
                  title: '緊急強制通話',
                  subtitle: '強制喚醒長輩設備並自動接聽',
                  icon: Icons.warning_rounded,
                  color: const Color(0xFFEF4444),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VideoCallScreen(
                          roomId: 'comm_elder_$rawId',
                          autoStart: true,
                          isEmergency: true,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCallOptionButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.7), size: 24),
          ],
        ),
      ),
    );
  }

  void _sendMessage(String text) async {
    if (widget.currentElder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先在頂部選擇要關照的長輩')),
      );
      return;
    }

    final messageText = text.trim();
    if (messageText.isEmpty) return;

    setState(() => _isSending = true);
    HapticFeedback.lightImpact();

    try {
      await widget.signaling.sendHeartbeat(
        widget.currentElder!.id,
        messageText,
        playSound: true,
      );

      if (mounted) {
        _messageController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已傳送留言給 ${widget.currentElder!.displayName} ✨'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('傳送失敗: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentElder == null) {
      return _buildNoElderPlaceholder();
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // 1. 視訊呼叫區（大按鈕，顯眼）
              _buildCallSection(),
              const SizedBox(height: 20),

              // 2. 留言發送區（快速短句 + 自訂輸入）
              _buildMessageSection(),
              const SizedBox(height: 20),

              // 3. 遠端監控區（方案 B：未連接獨立攝影機設備預留）
              _buildMonitorSection(),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildNoElderPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_alt_rounded, size: 64, color: Color(0xFF94A3B8)),
            const SizedBox(height: 16),
            Text(
              '尚未選擇長輩',
              style: GoogleFonts.notoSansTc(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '請點擊頂部長輩選單來載入長輩的互動功能',
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                color: const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms),
    );
  }

  Widget _buildCallSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _makeVideoCall,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.videocam_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '視訊通話',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '與長輩開啟雙向視訊與音訊對話',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05);
  }

  Widget _buildMessageSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.chat_bubble_rounded,
                  color: Color(0xFFF59E0B),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '留言給長輩',
                style: GoogleFonts.notoSansTc(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 快速留言
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickMessages.map((msg) {
              return ActionChip(
                label: Text(
                  msg,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF475569),
                  ),
                ),
                backgroundColor: const Color(0xFFF1F5F9),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                onPressed: () => _sendMessage(msg),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // 自訂留言
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    controller: _messageController,
                    maxLines: null,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 16,
                      color: const Color(0xFF0F172A),
                    ),
                    decoration: InputDecoration(
                      hintText: '輸入自訂溫馨小留言...',
                      hintStyle: GoogleFonts.notoSansTc(
                        fontSize: 16,
                        color: const Color(0xFF94A3B8),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _isSending
                    ? null
                    : () => _sendMessage(_messageController.text),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _isSending ? const Color(0xFF94A3B8) : const Color(0xFF3B82F6),
                    shape: BoxShape.circle,
                  ),
                  child: _isSending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms);
  }

  Widget _buildMonitorSection() {
    final reachedLimit = widget.monitorDevices.length >= widget.devicesMax;
    final String rawId = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();
    final String monitorRoomId = 'monitor_elder_$rawId';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ★ Task B4：訂閱層級徽章（點擊進入訂閱頁）
        _buildTierBadge(),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.videocam_off_rounded,
                        color: Color(0xFF10B981),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '遠端視訊監控',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const Spacer(),
                    // ★ 移植自 family_dashboard_view.dart 第 1280-1303 行：活躍警報計數 badge
                    if (widget.activeAlerts.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade500,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.activeAlerts.length} 警報',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // 設備計數 badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: reachedLimit ? Colors.orange.shade50 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${widget.monitorDevices.length} / ${widget.devicesMax}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: reachedLimit ? Colors.orange : Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // ── 設備列表 or 空狀態 ──
                if (widget.monitorDevices.isEmpty)
                  _buildNoMonitorDevice()
                else ...[
                  ...widget.monitorDevices.map(
                    (device) => _buildMonitorDeviceCard(device, monitorRoomId: monitorRoomId),
                  ),
                  // 達到上限提示
                  if (reachedLimit)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildDeviceLimitWarning(),
                    ),
                ],
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _showAddMonitorDialog();
                    },
                    icon: const Icon(Icons.add_a_photo_rounded, size: 20),
                    label: const Text('新增並連接監控設備'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF1F5F9),
                      foregroundColor: const Color(0xFF475569),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: GoogleFonts.notoSansTc(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }

  /// 空狀態：尚未連接任何監視機設備（移植自 family_dashboard_view.dart 第 1345 行 _buildNoMonitorDevice）
  Widget _buildNoMonitorDevice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_off_rounded, color: Colors.grey.shade400, size: 48),
          const SizedBox(height: 12),
          Text(
            '尚未連接任何監視機設備',
            style: GoogleFonts.notoSansTc(
              color: Colors.grey.shade600,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '請至「設定」配對家庭監控裝置',
            style: GoogleFonts.notoSansTc(
              color: Colors.grey.shade400,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// 單一監視機裝置卡片（移植自 family_dashboard_view.dart 第 1382 行 _buildMonitorDeviceCard，
  /// 含依 hasActiveAlert 判定的紅框跌倒警報高亮樣式）
  Widget _buildMonitorDeviceCard(Map device, {required String monitorRoomId}) {
    final name = device['deviceName'] ?? 'Unnamed';
    final socketId = device['id'] as String? ?? '';
    final isOnline = device['isOnline'] == true;
    final deviceId = device['deviceId'] ?? device['id'];

    // ★ 是否有作用中警報
    final deviceAlerts = widget.activeAlerts
        .where((a) => (a['device_id'] ?? a['deviceId'])?.toString() == deviceId.toString())
        .toList();
    final hasActiveAlert = deviceAlerts.isNotEmpty;
    final mostSevereAlert = hasActiveAlert ? deviceAlerts.first : null;

    // ★ 2026-08-04 第 7 項：語音通道按鈕所需的兩個數值。
    //   任一個解析不出來就不顯示按鈕——寧可少一個功能鍵，也不能送出錯誤的
    //   alert_id / device_id 而把語音權限開到別台監視機上。
    final int? alertId = hasActiveAlert
        ? int.tryParse(
            (mostSevereAlert?['alert_id'] ?? mostSevereAlert?['alertId'])?.toString() ?? '')
        : null;
    final int? numericDeviceId = int.tryParse(deviceId.toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: hasActiveAlert ? Colors.red.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasActiveAlert ? Colors.red.shade400 : Colors.grey.shade200,
          width: hasActiveAlert ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: hasActiveAlert
                ? Colors.red.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: hasActiveAlert ? 12 : 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 設備狀態指示燈
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isOnline ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
              boxShadow: isOnline
                  ? [
                      BoxShadow(
                        color: Colors.green.withValues(alpha: 0.4),
                        blurRadius: 6,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 14),
          // 設備名稱
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isOnline ? name : '(離線) $name',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isOnline ? Colors.black87 : Colors.grey,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (hasActiveAlert) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade500,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _alertTypeLabel(mostSevereAlert?['alert_type'] ?? 'fall'),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  hasActiveAlert
                      ? '⚠️ ${_alertTypeLabel(mostSevereAlert?['alert_type'] ?? '')}（信心: ${((mostSevereAlert?['confidence'] ?? 0) * 100).toStringAsFixed(0)}%）'
                      : '監視機模式',
                  style: TextStyle(
                    fontSize: 12,
                    color: hasActiveAlert ? Colors.red.shade700 : Colors.grey.shade500,
                    fontWeight: hasActiveAlert ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                // ★ 2026-08-04 第 7 項：僅在有作用中警報時才出現語音通道按鈕。
                //   平時不顯示 = 權限平時關閉（需求明訂）。
                if (hasActiveAlert && alertId != null && numericDeviceId != null) ...[
                  const SizedBox(height: 8),
                  _buildAudioBridgeButton(alertId, numericDeviceId),
                ],
              ],
            ),
          ),
          // 觀看 CCTV 按鈕
          ElevatedButton.icon(
            onPressed: isOnline
                ? () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoCallScreen(
                          roomId: monitorRoomId,
                          targetSocketId: socketId,
                          isEmergency: true,
                          autoStart: true,
                          // ★ 2026-08-05 第十七輪：CCTV 監控檢視改用 pop() 返回本頁
                          //   （互動分頁），不再整個重建 FamilyMainScreen。
                          returnByPop: true,
                        ),
                      ),
                    );
                  }
                : null,
            icon: const Icon(Icons.videocam_rounded, size: 18),
            label: const Text('觀看 CCTV'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isOnline
                  ? const Color(0xFF59B294).withValues(alpha: 0.1)
                  : Colors.grey.shade200,
              foregroundColor: isOnline ? const Color(0xFF59B294) : Colors.grey,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ★ 警報類型中文標籤（移植自 family_dashboard_view.dart 第 1526 行 _alertTypeLabel）
  String _alertTypeLabel(String type) {
    const map = {
      'fall': '跌倒',
      'prolonged_inactivity': '久未活動',
      'lying_down': '倒地',
      'crawl': '爬行',
    };
    return map[type] ?? type;
  }

  /// 設備數量達上限時的警告卡片（移植自 family_dashboard_view.dart 第 1537 行 _buildDeviceLimitWarning）
  Widget _buildDeviceLimitWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已達 ${widget.tierDisplayName} 設備上限 (${widget.devicesMax} 台)',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '升級方案以新增更多監視機',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12,
                    color: Colors.orange.shade600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FamilySubscriptionScreen()),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange.shade800,
            ),
            child: Text(
              '升級',
              style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  /// ★ Task B4：訂閱層級徽章 — 點擊導向訂閱頁（參考 family_dashboard_view.dart
  /// 第 649 行 _buildTierBadge 與第 1578 行 _buildDeviceLimitWarning 的既有導航寫法）。
  Widget _buildTierBadge() {
    // ★ 2026-08-04 第 6 項：三個層級要一眼分得出來，否則使用者無從得知自己是哪一級。
    //   未知層級一律退回一般會員的顏色，不可拋例外。
    final Color color = switch (widget.tierLevel) {
      'gold' => const Color(0xFFC9911B),    // 黃金會員
      'diamond' => const Color(0xFF4A7FD9), // 鑽石會員
      _ => const Color(0xFF59B294),         // 一般會員（免費）
    };
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FamilySubscriptionScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspace_premium_rounded, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              widget.tierDisplayName,
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 16, color: color),
          ],
        ),
      ),
    );
  }
}
