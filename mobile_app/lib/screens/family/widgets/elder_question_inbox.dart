import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api/elder_question_api.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ui/uban_dialog.dart';
import 'fam_ui.dart';

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

  /// 家屬登入 JWT（SharedPreferences `access_token`）。截圖端點必須帶
  /// Bearer，`Image.network` 不會自動帶，所以要先非同步讀出來。
  String? _token;
  bool _tokenLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadToken();
    _load();
  }

  Future<void> _loadToken() async {
    String? token;
    try {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString('access_token');
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _token = (token != null && token.isNotEmpty) ? token : null;
      _tokenLoaded = true;
    });
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
    // 外觀照設計稿 `.dialog`；行為不變：取消 → null、送出 → 去頭尾空白的文字。
    final text = await showDialog<String>(
      context: context,
      barrierColor: UbanColors.of(context).scrim,
      builder: (ctx) {
        final c = UbanColors.of(ctx);
        return UbanDialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '回覆 ${q['elder_name'] ?? '長輩'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: famText(c.text, 18, weight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: c.brandSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '「${q['question'] ?? ''}」',
                  style: famText(c.text, 14.5, height: 1.5),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                style: famText(c.text, 15, height: 1.45),
                decoration: InputDecoration(
                  // 提示子女用長輩聽得懂的說法——「滑出通知欄、點齒輪圖標」
                  // 這種講法長輩聽不懂，回了也等於沒回。
                  hintText: '用爸媽聽得懂的話說，例如「按螢幕最下面那排左邊第二個」',
                  hintStyle: famText(c.text3, 13.5, height: 1.4),
                  filled: true,
                  fillColor: c.surface2,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: c.brand, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FamButton(
                      label: '取消',
                      kind: FamButtonKind.tonal,
                      height: 48,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FamButton(
                      label: '送出',
                      height: 48,
                      onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
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
    final cSnack = UbanColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已回覆，爸媽的小嘎會轉達' : '送出失敗，請稍後再試一次',
            style: famText(cSnack.surface, 14, weight: FontWeight.w700)),
        // 成功沿用家屬 snackBarTheme；失敗用 danger 底。
        backgroundColor: ok ? null : cSnack.danger,
      ),
    );
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    // 載入中或沒有待回覆問題時完全不顯示，不在家屬首頁佔位。
    if (_isLoading || _questions.isEmpty) return const SizedBox.shrink();

    final c = UbanColors.of(context);

    // 設計稿 `.card.ask`：標題＋「待回覆」徽章（待處理 → 暖色），其下每則問題一塊引用。
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FamCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ⚠️ 同列有徽章，標題需可收縮（鐵律 #14；FamSecHead 內為 Expanded＋ellipsis）
            FamSecHead(
              title: '爸媽問你的問題',
              trailing: FamChip(
                label: '${_questions.length} 則待回覆',
                tone: FamTone.warm,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _questions.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _buildQuestionCard(c, _questions[i]),
            ],
          ],
        ),
      ),
    );
  }

  /// 截圖過期（後端保留 7 天）或載入失敗時的替代文字。
  Widget _screenshotExpired(UbanColors c, {double height = 60}) {
    return Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('截圖已過期', style: famText(c.text2, 12.5)),
    );
  }

  /// 讀不到登入憑證時：截圖端點需要登入才能看。
  Widget _screenshotNeedLogin(UbanColors c) {
    return Container(
      height: 60,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('請重新登入才能看截圖',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: famText(c.text2, 12.5)),
    );
  }

  Widget _screenshotLoading(UbanColors c, ImageChunkEvent? progress) {
    return Container(
      height: 120,
      alignment: Alignment.center,
      color: c.surface2,
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: c.brand,
          value: progress?.expectedTotalBytes != null
              ? progress!.cumulativeBytesLoaded / progress.expectedTotalBytes!
              : null,
        ),
      ),
    );
  }

  Widget _buildScreenshotThumb(UbanColors c, int qid) {
    final url = ElderQuestionApi.screenshotUrl(qid, widget.familyId);
    if (!_tokenLoaded) return _screenshotLoading(c, null);
    if (_token == null) return _screenshotNeedLogin(c);
    final headers = {'Authorization': 'Bearer $_token'};
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => _showScreenshot(url, headers),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: Image.network(
              url,
              headers: headers,
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, progress) =>
                  progress == null ? child : _screenshotLoading(c, progress),
              errorBuilder: (ctx, _, __) => _screenshotExpired(c),
            ),
          ),
        ),
      ),
    );
  }

  /// 全螢幕檢視截圖（可雙指縮放）。
  void _showScreenshot(String url, Map<String, String> headers) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        final c = UbanColors.of(ctx);
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Image.network(
                      url,
                      headers: headers,
                      fit: BoxFit.contain,
                      loadingBuilder: (ctx, child, progress) => progress == null
                          ? child
                          : _screenshotLoading(c, progress),
                      errorBuilder: (ctx, _, __) => _screenshotExpired(c),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(ctx).padding.top + 8,
                right: 8,
                child: IconButton(
                  tooltip: '關閉',
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 30),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    minimumSize: const Size(48, 48),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuestionCard(UbanColors c, Map<String, dynamic> q) {
    final qid = int.tryParse('${q['question_id']}') ?? -1;
    final isSending = _sending.contains(qid);
    final context_ = (q['screen_context'] ?? '').toString();
    final isBlockedTopic = (q['reason'] ?? '') == 'blocked_topic';
    final isScreenHelper = (q['reason'] ?? '') == 'screen_helper';
    final hasScreenshot = (q['screenshot_path'] ?? '').toString().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 詐騙／金錢類問題用警示色標出來：這類問題小嘎一律不自行回答，
        // 子女要知道這不是普通的操作疑問。
        if (isBlockedTopic) ...[
          Row(
            children: [
              FamDot(color: c.danger, size: 8),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '涉及金錢或安全，小嘎沒有自行回答',
                  style: famText(c.danger, 13, weight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        // 手機小幫手轉來的問題：中性色標籤，讓子女知道附帶的是長輩手機畫面。
        if (isScreenHelper) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '📱 從手機小幫手傳來',
                  style: famText(c.text2, 13, weight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        // `.ask blockquote`
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.brandSoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '${q['elder_name'] ?? '長輩'}：「${q['question'] ?? ''}」',
            style: famText(c.text, 15, height: 1.5),
          ),
        ),
        if (context_.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '當時在：$context_',
            style: famText(c.text2, 12.5, height: 1.4),
          ),
        ],
        // 小幫手附的畫面截圖：縮圖，點開可放大檢視。
        if (hasScreenshot) ...[
          const SizedBox(height: 10),
          _buildScreenshotThumb(c, qid),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FamButton(
            label: isSending ? '送出中…' : '回覆',
            height: 44,
            expand: false,
            loading: isSending,
            onPressed: isSending ? null : () => _answer(q),
          ),
        ),
      ],
    );
  }
}
