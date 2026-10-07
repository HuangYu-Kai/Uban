import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api/daily_question_api.dart';
import '../../services/memoir_service.dart';
import '../../theme/family_theme.dart';
import '../../widgets/ui/ui.dart';
import 'sheets/send_cheer_sheet.dart';
import 'widgets/fam_data_ui.dart';
import 'widgets/fam_interaction_ui.dart';
import 'widgets/fam_ui.dart';

/// 載入歷史的簽名（測試可注入；預設走 [DailyQuestionApi.getHistory]）。
typedef DailyHistoryLoader = Future<List<DailyQuestionItem>?> Function(
    String elderId, int familyId);

/// 出題的簽名（測試可注入；預設走 [DailyQuestionApi.ask]）。
typedef DailyAsker = Future<DailyAskResult> Function(
    {required String question, String? category});

/// 家屬 familyId：優先用呼叫端傳入，否則讀 `caregiver_id`（比照首頁打卡卡片）。
Future<int?> resolveFamilyId(int? fromWidget) async {
  if (fromWidget != null && fromWidget > 0) return fromWidget;
  try {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('caregiver_id');
    return (id != null && id > 0) ? id : null;
  } catch (_) {
    return null;
  }
}

/// ★ 2026-10-07 每日一問：家屬「出一題給長輩」對話框（題目 4–80 字＋推薦話題 chips）。
///
/// 成功回傳 [DailyAskResult]（`ok == true`，[DailyAskResult.message] 即要給家屬看的 SnackBar 文字）；
/// 取消回傳 null。送出中與錯誤訊息都留在對話框內，失敗可直接修改再送。
Future<DailyAskResult?> showAskDailyQuestionDialog(
  BuildContext context, {
  required String elderName,
  required DailyAsker ask,
}) {
  final controller = TextEditingController();
  // 狀態放在 builder 外，對話框因主題重建時也不會被重設。
  String? category;
  String? error;
  bool sending = false;
  final prompts = MemoirService.instance.getRecommendedPrompts();
  return showFamDialog<DailyAskResult>(context, (ctx) {
    return StatefulBuilder(builder: (context, setS) {
      final c = UbanColors.of(context);
      Future<void> submit() async {
        final q = controller.text.trim();
        if (q.length < DailyQuestionApi.minQuestionLength) {
          setS(() => error = '題目至少要 4 個字喔');
          return;
        }
        if (q.length > DailyQuestionApi.maxQuestionLength) {
          setS(() => error = '題目最多 80 個字，請再精簡一下');
          return;
        }
        setS(() {
          sending = true;
          error = null;
        });
        final r = await ask(question: q, category: category);
        if (!ctx.mounted) return;
        if (r.ok) {
          Navigator.of(ctx).pop(r);
        } else {
          setS(() {
            sending = false;
            error = r.message;
          });
        }
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 長輩姓名長度不可控：標題必須可收縮（規則 14）。
          Text(
            '出一題給$elderName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: famText(c.text, 18, weight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text('長輩會在首頁看到，用說的或打字都能回答', style: famText(c.text2, 13, height: 1.5)),
          const SizedBox(height: 12),
          // 推薦題可能很長：UbanDialog 本身是可捲動的，大字級小螢幕不會溢位（規則 14）。
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('點一個推薦題目：',
                  style: famText(c.text, 14, weight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in prompts.take(4))
                    _PromptChip(
                      key: ValueKey('dq_prompt_${p['question']}'),
                      text: p['question'] ?? '',
                      selected: controller.text == p['question'],
                      onTap: sending
                          ? null
                          : () => setS(() {
                                controller.text = p['question'] ?? '';
                                category = p['category'];
                                error = null;
                              }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('或自己寫一題：',
                  style: famText(c.text, 14, weight: FontWeight.w700)),
              const SizedBox(height: 6),
              UbanTextField(
                key: const ValueKey('dq_ask_text'),
                controller: controller,
                enabled: !sending,
                minLines: 2,
                maxLines: 3,
                maxLength: DailyQuestionApi.maxQuestionLength,
                hintText: '例如：您最難忘的一次旅行是去哪裡？',
                onChanged: (_) => setS(() => error = null),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    error!,
                    key: const ValueKey('dq_ask_error'),
                    style: famText(c.danger, 13.5,
                        weight: FontWeight.w700, height: 1.4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // 兩顆按鈕各佔一半、文字可收縮（FamButton 內建 Flexible＋ellipsis）。
          Row(
            children: [
              Expanded(
                child: FamButton(
                  label: '取消',
                  kind: FamButtonKind.ghost,
                  onPressed: sending ? null : () => Navigator.of(ctx).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FamButton(
                  key: const ValueKey('dq_ask_send'),
                  label: sending ? '送出中…' : '送出',
                  loading: sending,
                  onPressed: sending ? null : submit,
                ),
              ),
            ],
          ),
        ],
      );
    });
  });
}

class _PromptChip extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback? onTap;
  const _PromptChip(
      {super.key, required this.text, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.brandContainer : c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? Colors.transparent : c.line),
        ),
        // 推薦題長度不一：最多兩行、超出省略（規則 14）。
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: famText(
            selected ? c.brandStrong : c.text2,
            13.5,
            weight: selected ? FontWeight.w700 : FontWeight.w500,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

/// ★ 2026-10-07 每日一問：長輩語音回答的播放／暫停鈕（audioplayers，網路音檔）。
/// 播放器延後到第一次按下才建立（測試環境沒有平台通道）；失敗只顯示友善提示。
class DailyAudioButton extends StatefulWidget {
  final String url;
  const DailyAudioButton({super.key, required this.url});

  @override
  State<DailyAudioButton> createState() => _DailyAudioButtonState();
}

class _DailyAudioButtonState extends State<DailyAudioButton> {
  AudioPlayer? _player;
  StreamSubscription<void>? _doneSub;
  bool _playing = false;
  String? _error;

  @override
  void dispose() {
    _doneSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player?.pause();
        if (mounted) setState(() => _playing = false);
        return;
      }
      final p = _player ??= AudioPlayer();
      _doneSub ??= p.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = false);
      });
      setState(() {
        _playing = true;
        _error = null;
      });
      await p.play(UrlSource(widget.url));
    } catch (e) {
      debugPrint('⚠️ [DailyAudioButton] 播放失敗: $e');
      if (mounted) {
        setState(() {
          _playing = false;
          _error = '暫時無法播放這段錄音';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FamButton(
          key: const ValueKey('dq_audio_btn'),
          label: _playing ? '⏸ 暫停' : '🔊 聽長輩的回答',
          kind: FamButtonKind.tonal,
          height: 40,
          expand: false,
          onPressed: _toggle,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_error!, style: famText(c.danger, 12.5)),
          ),
      ],
    );
  }
}

/// ★ 2026-10-07 每日一問：歷史題目與長輩的回答。
///
/// 資料來自 `GET /daily_question/history`（新→舊，含已回答與家屬出的待答題）。
/// 已回答的題可「回覆」（開 [SendCheerSheet] 並帶 questionId）；家屬出的待答題顯示「等待長輩回答」。
/// 通知點擊會帶 [initialQuestionId]，載入後捲到該題並高亮。
class DailyQuestionScreen extends StatefulWidget {
  final String elderId;
  final String elderName;
  final int? familyId;
  final int? initialQuestionId;

  /// 測試注入點；null 時使用真實 API。
  final DailyHistoryLoader? historyLoader;
  final DailyAsker? asker;

  const DailyQuestionScreen({
    super.key,
    required this.elderId,
    required this.elderName,
    this.familyId,
    this.initialQuestionId,
    this.historyLoader,
    this.asker,
  });

  @override
  State<DailyQuestionScreen> createState() => _DailyQuestionScreenState();
}

class _DailyQuestionScreenState extends State<DailyQuestionScreen> {
  List<DailyQuestionItem> _items = [];
  bool _loading = true;
  bool _error = false;
  int? _familyId;
  int? _highlightId;
  bool _scrolled = false;
  final Map<int, GlobalKey> _keys = {};

  // State 自己的 context 在 FamilyThemeScope 之上：開 dialog／SnackBar 用主題內的 context。
  BuildContext? _themed;
  BuildContext get _themeCtx => _themed ?? context;

  @override
  void initState() {
    super.initState();
    _highlightId = widget.initialQuestionId;
    unawaited(_load());
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final fid = _familyId ??= await resolveFamilyId(widget.familyId);
    List<DailyQuestionItem>? list;
    if (fid != null) {
      list = widget.historyLoader != null
          ? await widget.historyLoader!(widget.elderId, fid)
          : await DailyQuestionApi.getHistory(
              elderId: widget.elderId, familyId: fid);
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = list == null;
      if (list != null) _items = list;
    });
    _scrollToInitial();
  }

  void _scrollToInitial() {
    final id = _highlightId;
    if (id == null || _scrolled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[id]?.currentContext;
      if (ctx != null && !_scrolled) {
        _scrolled = true;
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 300), alignment: .1);
      }
    });
  }

  Future<DailyAskResult> _ask(
      {required String question, String? category}) async {
    if (widget.asker != null) {
      return widget.asker!(question: question, category: category);
    }
    final fid = _familyId ??= await resolveFamilyId(widget.familyId);
    if (fid == null) return const DailyAskResult(false, '請重新登入後再試一次');
    return DailyQuestionApi.ask(
        familyId: fid,
        elderId: widget.elderId,
        question: question,
        category: category);
  }

  Future<void> _openAsk() async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await showAskDailyQuestionDialog(_themeCtx,
        elderName: widget.elderName, ask: _ask);
    if (r == null || !r.ok || !mounted) return;
    messenger.showSnackBar(famSnackBar(_themeCtx, r.message, success: true));
    unawaited(_load(silent: true));
  }

  Future<void> _reply(DailyQuestionItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final fid = _familyId ??= await resolveFamilyId(widget.familyId);
    if (!mounted) return;
    if (fid == null) {
      messenger.showSnackBar(famSnackBar(_themeCtx, '請重新登入後再試一次', error: true));
      return;
    }
    final ok = await SendCheerSheet.show(
      _themeCtx,
      elderName: widget.elderName,
      itemTitle: item.question,
      familyId: fid,
      elderId: widget.elderId,
      questionId: item.id,
      replyQuestion: item.question,
    );
    if (!ok || !mounted) return;
    setState(() {
      _items = [
        for (final e in _items)
          e.id == item.id ? e.copyWith(cheeredByMe: true) : e,
      ];
    });
    messenger
        .showSnackBar(famSnackBar(_themeCtx, '已送出，長輩那邊會聽到', success: true));
  }

  @override
  Widget build(BuildContext context) {
    return FamilyThemeScope(child: Builder(builder: _buildScreen));
  }

  Widget _buildScreen(BuildContext context) {
    _themed = context;
    final c = UbanColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: famSubBar(
        context,
        title: '每日一問',
        trailing: [
          FamSmallBtn(
            key: const ValueKey('dq_ask_open'),
            label: '出一題',
            filled: true,
            onTap: _openAsk,
          ),
        ],
      ),
      body: _buildBody(c),
    );
  }

  Widget _buildBody(UbanColors c) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error) {
      return _stateBlock(
        c,
        '暫時讀不到每日一問',
        '請確認網路後再試一次',
        action: FamButton(
          label: '重新載入',
          expand: false,
          onPressed: () => _load(),
        ),
      );
    }
    if (_items.isEmpty) {
      return _stateBlock(
        c,
        '還沒有每日一問的紀錄',
        '長輩回答後會出現在這裡，也可以點右上角「出一題」',
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in _items) ...[
              _buildItem(c, item),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stateBlock(UbanColors c, String title, String sub, {Widget? action}) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                textAlign: TextAlign.center,
                style:
                    famText(c.text, 18, weight: FontWeight.w900, height: 1.3)),
            const SizedBox(height: 6),
            Text(sub,
                textAlign: TextAlign.center,
                style: famText(c.text2, 14, height: 1.6)),
            if (action != null) ...[const SizedBox(height: 14), action],
          ],
        ),
      ),
    );
  }

  Widget _buildItem(UbanColors c, DailyQuestionItem item) {
    final key = _keys.putIfAbsent(item.id, () => GlobalKey());
    final highlighted = item.id == _highlightId;
    final who = item.askedByName.trim().isNotEmpty
        ? '${item.askedByName.trim()}出的題'
        : '小豬出的題';
    final date = item.assignedDate.replaceAll('-', '/');
    return KeyedSubtree(
      key: key,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: highlighted ? Border.all(color: c.brand, width: 2) : null,
        ),
        child: FamCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 日期／出題者長度不可控：同列都用 Expanded＋省略（規則 14）。
              Row(
                children: [
                  Expanded(
                    child: Text(
                      date.isEmpty ? who : '$date・$who',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: famText(c.text3, 12.5, weight: FontWeight.w600),
                    ),
                  ),
                  if (!item.answered) ...[
                    const SizedBox(width: 8),
                    const Flexible(
                        child: FamChip(label: '等待長輩回答', tone: FamTone.warm)),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.question,
                style:
                    famText(c.text, 16.5, weight: FontWeight.w800, height: 1.4),
              ),
              if (item.answered) ...[
                const SizedBox(height: 10),
                if (item.answerText.trim().isNotEmpty)
                  FamNote(text: item.answerText.trim(), tone: FamTone.brand),
                if (item.hasAudio) ...[
                  const SizedBox(height: 8),
                  DailyAudioButton(url: item.answerAudioUrl!),
                ],
                const SizedBox(height: 10),
                if (item.cheeredByMe)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: FamChip(label: '已回覆', tone: FamTone.brand),
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FamButton(
                      key: ValueKey('dq_reply_${item.id}'),
                      label: '回覆',
                      kind: FamButtonKind.tonal,
                      height: 40,
                      expand: false,
                      onPressed: () => _reply(item),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
