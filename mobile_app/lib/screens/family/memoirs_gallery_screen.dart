import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../models/memoir_story.dart';
import '../../services/api/daily_question_api.dart';
import '../../services/memoir_service.dart';
import '../../theme/family_theme.dart';
import '../../widgets/memoir_detail_sheet.dart';
import '../../widgets/ui/ui.dart';
import 'daily_question_screen.dart' show resolveFamilyId;
import 'widgets/fam_data_ui.dart';
import 'widgets/fam_interaction_ui.dart';
import 'widgets/fam_ui.dart';

/// 長輩專屬數位自傳與人生回憶錄畫廊 (MemoirsGalleryScreen)
///
/// 支援標籤篩選、時間軸列表模式、手作自傳繪本翻頁模式 (Storybook Mode)、
/// 以及「委託小豬向長輩提問」互動。
///
/// 2026-10 起外觀改家屬新設計：篩選 `.fchip`（[FamFilterChip]）、列表模式為 `.memgrid` 兩欄
/// `.mem` 方塊（[FamMemCard]）、繪本模式為單張 surface 卡；委託提問改 [UbanDialog]。
/// 資料、篩選規則與 [MemoirService] 呼叫與改版前相同。
class MemoirsGalleryScreen extends StatefulWidget {
  final String elderId;
  final String elderName;
  final String familyUserName;

  /// ★ 2026-10-07 每日一問：家屬 user id（出題用）；null 時讀 `caregiver_id`。
  final int? familyId;

  /// 測試注入點：取得每日一問歷史；null 時走真實 API。
  final Future<List<DailyQuestionItem>?> Function(String elderId, int familyId)?
      dailyLoader;

  /// 測試注入點：出題；null 時走真實 API。
  final Future<DailyAskResult> Function(
      {required String question, String? category})? dailyAsker;

  const MemoirsGalleryScreen({
    super.key,
    required this.elderId,
    required this.elderName,
    this.familyUserName = '家屬',
    this.familyId,
    this.dailyLoader,
    this.dailyAsker,
  });

  @override
  State<MemoirsGalleryScreen> createState() => _MemoirsGalleryScreenState();
}

class _MemoirsGalleryScreenState extends State<MemoirsGalleryScreen> {
  final MemoirService _service = MemoirService.instance;
  List<MemoirStory> _stories = [];
  // ★ 2026-10-07 每日一問：長輩已回答的每日一問（來自後端 /history），與本機故事合併顯示。
  List<MemoirStory> _dailyStories = [];
  List<MemoirStory> _localStories = [];
  bool _isLoading = true;
  String _selectedTag = '全部';
  bool _isStorybookMode = false; // 是否切換至自傳翻頁書模式
  late PageController _pageController;
  int _currentBookPage = 0;

  // 家屬主題之下的 context（State 自己的 context 在 FamilyThemeScope 之上）：
  // 開 dialog／sheet／SnackBar 用它，才吃得到家屬色票；每次 build 更新。
  BuildContext? _themed;
  BuildContext get _themeCtx => _themed ?? context;
  UbanColors get _c => UbanColors.of(_themeCtx);

  static const String _favTag = '珍藏';
  static const String _dailyTag = '每日一問';
  final List<String> _tags = ['全部', '經典回憶', '美食記憶', '溫馨寄語', '奮鬥歲月', _dailyTag, _favTag];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _service.addListener(_onServiceUpdate);
    _loadStories();
    _loadDailyStories();
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _pageController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      _loadStories();
    }
  }

  Future<void> _loadStories() async {
    final list = await _service.getMemoirs(widget.elderId);
    if (mounted) {
      setState(() {
        _localStories = list;
        _stories = _merge(list, _dailyStories);
        _isLoading = false;
      });
    }
  }

  /// 本機故事＋每日一問，新→舊。每日一問的 id 以 `dq_` 開頭，不會與本機 id 衝突。
  List<MemoirStory> _merge(List<MemoirStory> local, List<MemoirStory> daily) {
    if (daily.isEmpty) return local;
    return [...local, ...daily]
      ..sort((a, b) => b.recordedDate.compareTo(a.recordedDate));
  }

  /// 讀取長輩已回答的每日一問並轉成故事卡片；失敗時靜默略過（本機故事照常顯示）。
  Future<void> _loadDailyStories() async {
    try {
      final fid = await resolveFamilyId(widget.familyId);
      if (fid == null) return;
      final items = widget.dailyLoader != null
          ? await widget.dailyLoader!(widget.elderId, fid)
          : await DailyQuestionApi.getHistory(elderId: widget.elderId, familyId: fid);
      if (items == null || !mounted) return;
      final stories = <MemoirStory>[
        for (final q in items)
          if (q.answered)
            MemoirStory(
              id: 'dq_${q.id}',
              elderId: widget.elderId,
              title: q.question,
              tag: _dailyTag,
              preview: q.answerSnippet,
              fullStory: q.answerSnippet,
              promptQuestion: q.question,
              audioAssetOrUrl: q.answerAudioUrl,
              recordedDate: DateTime.tryParse(q.answeredAt)?.toLocal() ??
                  DateTime.tryParse(q.assignedDate) ??
                  DateTime.now(),
            ),
      ];
      setState(() {
        _dailyStories = stories;
        _stories = _merge(_localStories, stories);
      });
    } catch (e) {
      debugPrint('⚠️ [MemoirsGallery] 讀取每日一問失敗: $e');
    }
  }

  List<MemoirStory> get _filteredStories {
    if (_selectedTag == '全部') return _stories;
    if (_selectedTag == _favTag) {
      return _stories.where((s) => s.isFavorite).toList();
    }
    return _stories.where((s) => s.tag == _selectedTag).toList();
  }

  void _showDelegatePromptDialog() {
    final textController = TextEditingController();
    final recommended = _service.getRecommendedPrompts();
    String selectedCategory = '經典回憶';
    bool submitting = false; // 避免連點重複出題
    final messenger = ScaffoldMessenger.of(context);

    showFamDialog<void>(
      _themeCtx,
      (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final c = UbanColors.of(context);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              famDialogTitle(c, '委託小豬向${widget.elderName}提問'),
              const SizedBox(height: 2),
              Text('題目會送到長輩的手機首頁，長輩可用說的回答',
                  style: famText(c.text2, 13, height: 1.5)),
              const SizedBox(height: 14),
              Text('點選推薦問題：',
                  style: famText(c.text, 14, weight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: recommended.take(4).map((item) {
                  final q = item['question']!;
                  final selected = textController.text == q;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setDialogState(() {
                        textController.text = q;
                        selectedCategory = item['tag'] ?? '經典回憶';
                      });
                    },
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 36),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? c.brandContainer : c.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: selected ? Colors.transparent : c.line,
                        ),
                      ),
                      // 推薦問題長度不一：最多兩行、超出省略（鐵律 #14）。
                      child: Text(
                        q,
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
                }).toList(),
              ),
              const SizedBox(height: 14),
              Text('或是自訂想問的話題：',
                  style: famText(c.text, 14, weight: FontWeight.w700)),
              const SizedBox(height: 6),
              UbanTextField(
                controller: textController,
                minLines: 3,
                maxLines: 3,
                hintText: '例如：想聽阿公聊聊年輕時怎麼追到阿嬤的？',
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: FamButton(
                      label: '取消',
                      kind: FamButtonKind.ghost,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FamButton(
                      label: '託付給小豬',
                      onPressed: () async {
                        final q = textController.text.trim();
                        if (q.isEmpty || submitting) return;

                        // ★ 2026-10-07 每日一問：改走後端 /daily_question/ask，題目才會真的
                        //   送到長輩手機（舊的 delegatePrompt 只寫本機，長輩永遠看不到）。
                        if (q.length < DailyQuestionApi.minQuestionLength ||
                            q.length > DailyQuestionApi.maxQuestionLength) {
                          messenger.showSnackBar(famSnackBar(
                              _themeCtx, '題目請寫 4 到 80 個字', error: true));
                          return;
                        }
                        submitting = true;
                        final fid = await resolveFamilyId(widget.familyId);
                        final DailyAskResult r;
                        if (widget.dailyAsker != null) {
                          r = await widget.dailyAsker!(
                              question: q, category: selectedCategory);
                        } else if (fid == null) {
                          r = const DailyAskResult(false, '請重新登入後再試一次');
                        } else {
                          r = await DailyQuestionApi.ask(
                            familyId: fid,
                            elderId: widget.elderId,
                            question: q,
                            category: selectedCategory,
                          );
                        }
                        submitting = false;
                        if (!mounted) return;
                        if (!r.ok) {
                          // 失敗時保留對話框，讓使用者可直接再送一次。
                          messenger.showSnackBar(
                              famSnackBar(_themeCtx, r.message, error: true));
                          return;
                        }
                        if (ctx.mounted) Navigator.pop(ctx);

                        if (mounted) {
                          messenger.showSnackBar(
                            famSnackBar(_themeCtx, r.message, success: true),
                          );
                          unawaited(_loadDailyStories());
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 2026-10：push 出來的家屬頁要自己掛家屬主題；Builder 讓下方 context 位於主題之內。
    return FamilyThemeScope(
      child: Builder(builder: _buildScreen),
    );
  }

  Widget _buildScreen(BuildContext context) {
    _themed = context;
    final c = _c;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: famSubBar(
        context,
        title: '${widget.elderName}的回憶錄',
        trailing: [
          // 模式切換（列表 vs 翻頁自傳書）
          FamIconButton(
            tooltip: _isStorybookMode ? '切換列表模式' : '切換繪本翻頁模式',
            icon: _isStorybookMode
                ? Icons.view_agenda_rounded
                : Icons.auto_stories_rounded,
            onTap: () {
              setState(() {
                _isStorybookMode = !_isStorybookMode;
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 副標＋委託提問：副標可收縮（鐵律 #14）。
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '珍藏 ${_stories.length} 篇口述回憶・世代傳承',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: famText(c.text2, 13, height: 1.4),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FamSmallBtn(
                        label: '委託提問',
                        filled: true,
                        onTap: _showDelegatePromptDialog,
                      ),
                    ],
                  ),
                ),

                // 標籤篩選列
                if (!_isStorybookMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: FamFilterRow(
                      children: [
                        for (final tag in _tags)
                          FamFilterChip(
                            label: tag == '全部' ? '全部 ${_stories.length}' : tag,
                            selected: tag == _selectedTag,
                            onTap: () => setState(() => _selectedTag = tag),
                          ),
                      ],
                    ),
                  ),

                // 內容視圖：翻頁書模式 or 列表模式
                Expanded(
                  child: _isStorybookMode ? _buildStorybookView() : _buildListView(),
                ),
              ],
            ),
    );
  }

  Widget _emptyBlock(String title) {
    final c = _c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: famText(c.text, 18, weight: FontWeight.w900, height: 1.3),
            ),
            const SizedBox(height: 6),
            Text(
              '點擊「委託提問」，讓小豬今天就問長輩吧！',
              textAlign: TextAlign.center,
              style: famText(c.text2, 14, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  // 標籤 → 方塊底色（只用中性／品牌／資訊色；暖色留給待處理）。
  FamTone _toneFor(String tag) {
    const tones = [FamTone.brand, FamTone.info, FamTone.neutral];
    return tones[tag.runes.fold<int>(0, (a, b) => a + b) % tones.length];
  }

  // ── 1. 列表模式（`.memgrid` 兩欄） ──
  Widget _buildListView() {
    final list = _filteredStories;

    if (list.isEmpty) {
      return _emptyBlock('目前此分類尚無故事');
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < list.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildStoryCard(list[i], i)),
                const SizedBox(width: 10),
                Expanded(
                  child: i + 1 < list.length
                      ? _buildStoryCard(list[i + 1], i + 1)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStoryCard(MemoirStory story, int index) {
    return FamMemCard(
      title: story.title,
      meta: '${DateFormat('yyyy/MM/dd').format(story.recordedDate)}・${story.tag}',
      tone: _toneFor(story.tag),
      favorite: story.isFavorite,
      onFavorite: () => _service.toggleFavorite(widget.elderId, story.id),
      onTap: () => MemoirDetailSheet.show(
        _themeCtx,
        story: story,
        elderName: widget.elderName,
        familyUserName: widget.familyUserName,
      ),
    ).animate().fadeIn(delay: (index * 60).ms, duration: 250.ms);
  }

  // ── 2. 繪本翻頁自傳書模式 (Storybook Mode) ──
  Widget _buildStorybookView() {
    final c = _c;
    if (_stories.isEmpty) {
      return _emptyBlock('目前尚無故事回憶');
    }

    return Column(
      children: [
        // 頁碼提示
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            '第 ${_currentBookPage + 1} / ${_stories.length} 章',
            style: famText(c.brandStrong, 13.5, weight: FontWeight.w700, tabular: true),
          ),
        ),

        // 翻頁書主體卡片
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _stories.length,
            onPageChanged: (i) => setState(() => _currentBookPage = i),
            physics: const BouncingScrollPhysics(),
            itemBuilder: (ctx, index) {
              final story = _stories[index];
              return Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: c.shadows.card,
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 章節標籤
                      Center(child: FamChip(label: story.tag, tone: FamTone.brand)),

                      const SizedBox(height: 14),

                      // 故事標題
                      Text(
                        story.title,
                        textAlign: TextAlign.center,
                        style: famText(c.text, 20, weight: FontWeight.w900, height: 1.35),
                      ),

                      const SizedBox(height: 14),

                      // 引導提問引文框
                      FamNote(text: '小豬提問：「${story.promptQuestion}」'),

                      const SizedBox(height: 18),

                      // 口述全文
                      Text(
                        story.fullStory,
                        style: famText(c.text, 16, height: 1.8),
                      ),

                      const SizedBox(height: 22),

                      // 底部原聲試聽按鈕
                      FamButton(
                        label: '聆聽長輩口述原聲 & 留言',
                        kind: FamButtonKind.tonal,
                        onPressed: () => MemoirDetailSheet.show(
                          _themeCtx,
                          story: story,
                          elderName: widget.elderName,
                          familyUserName: widget.familyUserName,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
