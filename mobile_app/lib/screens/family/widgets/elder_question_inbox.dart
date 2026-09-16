import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/api/elder_question_api.dart';

/// 💬 長輩提問收件匣（數位助理升級機制的家屬端）
///
/// 小嘎遇到沒把握的問題——尤其是詐騙、匯款、帳號密碼這類一律不自行回答的
/// 主題——會把問題連同「長輩當下在哪一頁」轉交到這裡。子女看到的不是
/// 第五次的同一個問題，而是一則有上下文、一次就能解決的請求。
///
/// 沒有待回覆問題時整個區塊不顯示，避免在家屬首頁佔位。
class ElderQuestionInbox extends StatefulWidget {
  final int familyId;

  /// 由父層在收到 Socket `elder-question` 時遞增，用來觸發重新整理。
  /// 家屬首頁在 IndexedStack 底下會被保活，initState 只跑一次，
  /// 因此必須靠這個訊號才能即時反映新問題。
  final int refreshToken;

  const ElderQuestionInbox({
    super.key,
    required this.familyId,
    this.refreshToken = 0,
  });

  @override
  State<ElderQuestionInbox> createState() => _ElderQuestionInboxState();
}

class _ElderQuestionInboxState extends State<ElderQuestionInbox> {
  List<Map<String, dynamic>> _questions = [];
  bool _isLoading = true;
  final Set<int> _sending = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ElderQuestionInbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.familyId != widget.familyId) {
      _load();
    }
  }

  Future<void> _load() async {
    final list = await ElderQuestionApi.listForFamily(widget.familyId);
    if (!mounted) return;
    setState(() {
      _questions = list;
      _isLoading = false;
    });
  }

  Future<void> _answer(Map<String, dynamic> q) async {
    final qid = int.tryParse('${q['question_id']}');
    if (qid == null) return;

    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '回覆 ${q['elder_name'] ?? '長輩'}',
          style: GoogleFonts.notoSansTc(
            color: const Color(0xFFE2E8F0),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '「${q['question'] ?? ''}」',
              style: GoogleFonts.notoSansTc(
                color: const Color(0xFF94A3B8),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              style: GoogleFonts.notoSansTc(color: const Color(0xFFE2E8F0)),
              decoration: InputDecoration(
                // 提示子女用長輩聽得懂的說法——「滑出通知欄、點齒輪圖標」
                // 這種講法長輩聽不懂，回了也等於沒回。
                hintText: '用爸媽聽得懂的話說，例如「按螢幕最下面那排左邊第二個」',
                hintStyle: GoogleFonts.notoSansTc(
                  color: const Color(0xFF64748B),
                  fontSize: 13,
                ),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消',
                style: GoogleFonts.notoSansTc(color: const Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text('送出',
                style: GoogleFonts.notoSansTc(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (text == null || text.isEmpty || !mounted) return;

    setState(() => _sending.add(qid));
    final ok = await ElderQuestionApi.answer(
      questionId: qid,
      familyId: widget.familyId,
      answer: text,
    );
    if (!mounted) return;
    setState(() => _sending.remove(qid));

    // ⚠️ 依實際結果回報，送失敗時絕不顯示「已回覆」。
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已回覆，爸媽的小嘎會轉達' : '送出失敗，請稍後再試一次'),
        backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFDC2626),
      ),
    );
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    // 載入中或沒有待回覆問題時完全不顯示，不在家屬首頁佔位。
    if (_isLoading || _questions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💬', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              // ⚠️ 同列有徽章，標題需可收縮（鐵律 #14）
              Expanded(
                child: Text(
                  '爸媽問你的問題',
                  style: GoogleFonts.notoSansTc(
                    color: const Color(0xFFE2E8F0),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_questions.length} 則待回覆',
                  style: GoogleFonts.notoSansTc(
                    color: const Color(0xFFF59E0B),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._questions.map(_buildQuestionCard),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(Map<String, dynamic> q) {
    final qid = int.tryParse('${q['question_id']}') ?? -1;
    final isSending = _sending.contains(qid);
    final context_ = (q['screen_context'] ?? '').toString();
    final isBlockedTopic = (q['reason'] ?? '') == 'blocked_topic';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          // 詐騙／金錢類問題用警示色標出來：這類問題小嘎一律不自行回答，
          // 子女要知道這不是普通的操作疑問。
          color: isBlockedTopic
              ? const Color(0xFFDC2626).withValues(alpha: 0.5)
              : const Color(0xFF334155),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isBlockedTopic) ...[
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 15, color: Color(0xFFDC2626)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '涉及金錢或安全，小嘎沒有自行回答',
                    style: GoogleFonts.notoSansTc(
                      color: const Color(0xFFDC2626),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
          ],
          Text(
            '${q['elder_name'] ?? '長輩'}：「${q['question'] ?? ''}」',
            style: GoogleFonts.notoSansTc(
              color: const Color(0xFFE2E8F0),
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
          if (context_.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '當時在：$context_',
              style: GoogleFonts.notoSansTc(
                color: const Color(0xFF94A3B8),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
              ),
              onPressed: isSending ? null : () => _answer(q),
              icon: isSending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.reply_rounded, size: 17),
              label: Text(
                isSending ? '送出中…' : '回覆',
                style: GoogleFonts.notoSansTc(
                    fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
