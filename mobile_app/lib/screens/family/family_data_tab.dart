import 'package:flutter/material.dart';
import '../../widgets/ui/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/elder.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../theme/family_theme.dart';
import '../elder_profile_edit_screen.dart';
import '../caregiver_pairing_screen.dart';
import '../identification_screen.dart';
import 'family_subscription_screen.dart';
import 'family_bug_report_screen.dart';
import '../../models/memoir_story.dart';
import '../../services/memoir_service.dart';
import '../../widgets/memoir_detail_sheet.dart';
import 'memoirs_gallery_screen.dart';
// ★ 第五十輪：健康趨勢與情緒關注卡片做好了卻沒有入口（`AiHubScreen` 從未被
// 建構或導覽到，見該檔），本輪把這兩個「真的有資料」的畫面接回本分頁。
// `VitalSignsWidget`（心率/步數/卡路里/睡眠）刻意不接——它的資料 100% 是
// initState 硬編的假數字，`_loadVitalSigns()` 只是 delay 後填回同樣的常數，
// 接進來等於在誠實的分頁裡塞一張假資料卡片，違反本輪誠實性要求，故留待
// 之後真的接上裝置資料再處理。
import 'health_trends_screen.dart';
import 'outing_trends_screen.dart';
import 'widgets/emotion_preview_card.dart';
import 'widgets/fam_data_ui.dart';
import 'widgets/fam_interaction_ui.dart';
import 'widgets/fam_ui.dart';
import '../../widgets/error_boundary.dart';

/// ⚙️ 子女端「資料與設定」Tab (FamilyDataTab)
/// 包含：照顧者資訊、關照長輩完整檔案、AI 陪伴偏好、人生故事膠囊、安全通知設定、裝置與訂閱管理
///
/// 2026-10 起外觀改家屬新設計（海灣藍）：`.me-card`、`.group2`／`.setrow`（不放圖示方塊）、
/// `.entry`、`.story`；對話框改 [UbanDialog]（經 [showFamDialog]，內容與回傳值不變）。
/// **純 UI 改版**：所有 callback、Navigator 目的地、API 與 SharedPreferences 讀寫都與改版前相同。
class FamilyDataTab extends StatefulWidget {
  final Elder? currentElder;
  final int userId;
  final String userName;
  final VoidCallback? onElderUpdated;
  final bool isDarkMode;
  final ValueChanged<bool>? onToggleDarkMode;

  // ★ 第四十一輪 item 2（第二階段）：新手指引用的高光目標 GlobalKey。全部
  //   選填、預設 null——GlobalKey 必須由上層 FamilyMainScreen 持有並傳入，
  //   理由與傳遞方式比照 family_home_tab.dart 同名欄位群組的說明。不傳就
  //   等同沒有目標，`SpotlightTutorial` 會自動退化為無挖洞的置中卡片。
  final GlobalKey? caregiverCardKey;
  final GlobalKey? elderSummaryKey;
  final GlobalKey? memoirsKey;
  final GlobalKey? aiHelperKey;

  /// ★ 第五十一輪（任務 2）：由父層 `FamilyMainScreen` 在使用者切換到「資料」
  /// 分頁（`IndexedStack` index 2）時遞增，觸發本分頁重新整理。比照本專案
  /// 既有的 `ElderQuestionInbox.refreshToken` 作法（見該檔
  /// `didUpdateWidget`）——本分頁活在 `IndexedStack` 底下被保活，`initState`
  /// 只跑一次、原本的 `didUpdateWidget` 只在切換長輩時才會重載，使用者切到
  /// 別的分頁再切回來完全不會重新載入資料，這正是「資料分頁有時整片空白，
  /// 切分頁再回來仍然一樣」的成因之一（另一半是本輪同時補上的
  /// `ErrorBoundary`，見 `build()` 內的說明）。
  final int refreshToken;

  const FamilyDataTab({
    super.key,
    required this.currentElder,
    required this.userId,
    required this.userName,
    this.onElderUpdated,
    this.isDarkMode = false,
    this.onToggleDarkMode,
    this.caregiverCardKey,
    this.elderSummaryKey,
    this.memoirsKey,
    this.aiHelperKey,
    this.refreshToken = 0,
  });

  @override
  State<FamilyDataTab> createState() => _FamilyDataTabState();
}

class _FamilyDataTabState extends State<FamilyDataTab>
    with WidgetsBindingObserver {
  // 家屬主題之下的 context（State 自己的 context 在 FamilyThemeScope 之上）：
  // 取色與開 dialog／sheet／SnackBar 都用它，才吃得到家屬色票；每次 build 更新。
  BuildContext? _themed;
  BuildContext get _themeCtx => _themed ?? context;
  UbanColors get _c => UbanColors.of(_themeCtx);

  String _caregiverName = '';
  String _subscriptionDisplay = '一般會員';

  // 智慧防護與通知開關
  bool _isEmergencyOn = true;
  bool _isDailySummaryOn = true;
  bool _isAiInsightOn = true;
  bool _isMedicationPushOn = true;
  bool _isGeneratingRecovery = false;

  // AI 與長輩資料狀態
  bool _isLoadingAiProfile = false;
  Map<String, dynamic>? _elderProfileData;

  // 📖 人生故事膠囊資料狀態
  List<MemoirStory> _memoirStories = [];
  bool _isLoadingMemoirs = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _caregiverName = widget.userName;
    _loadCaregiverName();
    _loadSubscriptionInfo();
    _loadAiProfile();
    MemoirService.instance.addListener(_onMemoirsChanged);
    _loadMemoirs();
  }

  // ── 重新整理三種觸發（下拉／切回此分頁／App 回前景）共用 ──
  // 本分頁在家屬主畫面的 IndexedStack 底下被保活；離屏時 TickerMode 為 false，
  // 用它判斷「目前是否可見」。父層另有 refreshToken（切分頁時遞增），同樣導向
  // _refreshAll，由 _isRefreshing 擋掉同時抵達的重複請求。
  /// 上一次記錄的可見狀態；null 代表第一次 didChangeDependencies（initState 已載入，不重複載）。
  bool? _wasVisible;
  bool _visible = true;
  bool _isRefreshing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    final was = _wasVisible;
    _wasVisible = _visible;
    // 不可見 → 可見：切回此分頁就重讀（不節流）
    if (was == false && _visible) _refreshAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回前景時只刷新目前可見的分頁
    if (state == AppLifecycleState.resumed && _visible && mounted) {
      _refreshAll();
    }
  }

  /// 統一的重新整理入口：只呼叫本分頁既有的四個載入函式。
  Future<void> _refreshAll() async {
    if (_isRefreshing || !mounted) return;
    _isRefreshing = true;
    try {
      await Future.wait([
        _loadCaregiverName(),
        _loadSubscriptionInfo(),
        _loadAiProfile(),
        _loadMemoirs(),
      ]);
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MemoirService.instance.removeListener(_onMemoirsChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(FamilyDataTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentElder?.id != oldWidget.currentElder?.id ||
        widget.currentElder?.elderId != oldWidget.currentElder?.elderId) {
      _loadAiProfile();
      _loadMemoirs();
    }
    // ★ 第五十一輪（任務 2）：使用者從別的分頁切回「資料」分頁時，父層會
    //   遞增 `refreshToken`（見欄位宣告的完整理由），這裡跟著重新載入全部
    //   會過期的資料來源——不只是長輩相關的兩項，`_loadCaregiverName` 讀的
    //   SharedPreferences 與 `_loadSubscriptionInfo` 打的訂閱查詢 API 一樣
    //   可能在使用者切走的這段時間內變了（例如在別的畫面改了訂閱方案）。
    //   用 `!=` 比對而不是每次 build 都重載——只有父層真的判定「這是一次
    //   分頁切換」才會遞增該 token，2.5 秒輪詢造成的其餘重建不會誤觸發。
    if (widget.refreshToken != oldWidget.refreshToken) {
      _refreshAll();
    }
  }

  void _onMemoirsChanged() {
    if (mounted) _loadMemoirs();
  }

  Future<void> _loadMemoirs() async {
    final elderId = widget.currentElder?.elderId ?? widget.currentElder?.id.toString() ?? 'default_elder';
    final stories = await MemoirService.instance.getMemoirs(elderId);
    if (mounted) {
      setState(() {
        _memoirStories = stories;
        _isLoadingMemoirs = false;
      });
    }
  }

  Future<void> _loadCaregiverName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('caregiver_name');
    if (name != null && name.isNotEmpty && mounted) {
      setState(() {
        _caregiverName = name;
      });
    }
  }

  Future<void> _loadSubscriptionInfo() async {
    try {
      final res = await ApiService.getSubscriptionTier(widget.userId);
      if (mounted && (res['status'] == 'success' || res['tier_level'] != null)) {
        final tier = (res['tier_level'] ?? 'free').toString();
        setState(() {
          if (tier == 'diamond') {
            _subscriptionDisplay = '鑽石守護版';
          } else if (tier == 'gold') {
            _subscriptionDisplay = '黃金尊榮版';
          } else {
            _subscriptionDisplay = '一般會員';
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadAiProfile() async {
    if (widget.currentElder == null) return;
    setState(() => _isLoadingAiProfile = true);
    try {
      final profile = await ApiService.getElderProfile(widget.currentElder!.id);
      if (mounted) {
        setState(() {
          // 後端回傳 {status, data}，只取 data；失敗（status != success）則視為沒資料
          _elderProfileData = profile['status'] == 'success' && profile['data'] is Map
              ? Map<String, dynamic>.from(profile['data'] as Map)
              : null;
          _isLoadingAiProfile = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAiProfile = false);
      }
    }
  }

  void _openSubscription() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FamilySubscriptionScreen()),
    ).then((_) => _loadSubscriptionInfo());
  }

  void _openMemoirsGallery(String elderId, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemoirsGalleryScreen(
          elderId: elderId,
          elderName: name,
          familyUserName: widget.userName,
        ),
      ),
    );
  }

  void _handleEditProfile() {
    final TextEditingController controller = TextEditingController(text: _caregiverName);
    showFamDialog<void>(
      _themeCtx,
      (dialogContext) {
        final c = UbanColors.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            famDialogTitle(c, '編輯我的顯示名稱'),
            const SizedBox(height: 14),
            UbanTextField(
              controller: controller,
              autofocus: true,
              hintText: '輸入您的稱呼 (例: 大兒子、小女兒)',
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: FamButton(
                    label: '取消',
                    kind: FamButtonKind.ghost,
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FamButton(
                    label: '儲存',
                    onPressed: () async {
                      final newName = controller.text.trim();
                      if (newName.isNotEmpty) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('caregiver_name', newName);
                        if (mounted) {
                          setState(() {
                            _caregiverName = newName;
                          });
                        }
                      }
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _handleLogout() {
    showFamDialog<void>(
      _themeCtx,
      (dialogContext) {
        final c = UbanColors.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            famDialogTitle(c, '安全登出'),
            const SizedBox(height: 10),
            Text(
              '確定要登出當前帳號並回到身分選擇頁面嗎？',
              style: famText(c.text2, 15, height: 1.5),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: FamButton(
                    label: '取消',
                    kind: FamButtonKind.ghost,
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FamButton(
                    label: '確認登出',
                    kind: FamButtonKind.danger,
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      await SessionManager.releaseSession();
                      if (!mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const IdentificationScreen()),
                        (route) => false,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _navigateToElderEdit() {
    if (widget.currentElder == null) return;

    final elderData = {
      'id': widget.currentElder!.id,
      'user_id': widget.currentElder!.id,
      'user_name': widget.currentElder!.name,
      'gender': widget.currentElder!.gender ?? 'M',
      'age': widget.currentElder!.age,
      'location': widget.currentElder!.location,
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ElderProfileEditScreen(
          elderData: elderData,
          familyId: widget.userId,
          onUnbind: () {
            Navigator.pop(context);
            _showUnbindConfirmDialog();
          },
        ),
      ),
    ).then((_) {
      _loadAiProfile();
      if (widget.onElderUpdated != null) {
        widget.onElderUpdated!();
      }
    });
  }

  void _showUnbindConfirmDialog() {
    if (widget.currentElder == null) return;
    final elder = widget.currentElder!;
    // 在對話框關閉、畫面可能已換頁之前先取得 messenger（原本就是這個順序）。
    final messenger = ScaffoldMessenger.of(context);

    showFamDialog<void>(
      _themeCtx,
      (dialogContext) {
        final c = UbanColors.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            famDialogTitle(c, '解除綁定確認'),
            const SizedBox(height: 10),
            Text(
              '確定要解除與「${elder.name}」的照護配對嗎？\n\n解除後您將無法再接收該長輩的健康警報與即時狀態。',
              style: famText(c.danger, 15, height: 1.5, weight: FontWeight.w600),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: FamButton(
                    label: '取消',
                    kind: FamButtonKind.ghost,
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FamButton(
                    label: '確定解除',
                    kind: FamButtonKind.danger,
                    onPressed: () async {
                      final navigator = Navigator.of(dialogContext);
                      final result = await ApiService.unbindElder(widget.userId, elder.id);
                      if (!mounted) return;
                      if (result['status'] == 'success') {
                        navigator.pop();
                        if (widget.onElderUpdated != null) {
                          widget.onElderUpdated!();
                        }
                        messenger.showSnackBar(
                          famSnackBar(_themeCtx, '已成功解除與該長輩的綁定', success: true),
                        );
                      } else {
                        navigator.pop();
                        messenger.showSnackBar(
                          famSnackBar(_themeCtx, '解除失敗: ${result['error']}', error: true),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _showRecoveryAssistantDialog() {
    if (widget.currentElder == null) return;

    showFamDialog<void>(
      _themeCtx,
      (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final c = UbanColors.of(context);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                famDialogTitle(c, '長輩移機與重裝助手'),
                const SizedBox(height: 10),
                Text(
                  '如果長輩（${widget.currentElder!.displayName}）更換了新手機，或是不小心解除安裝了 Uban App，您可以在這裡為長輩產生一個具有時效性（15分鐘內有效）的快速登入連結，並傳送給長輩。',
                  style: famText(c.text2, 14.5, height: 1.55),
                ),
                const SizedBox(height: 14),
                const FamNote(
                  text: '注意：連結於 15 分鐘內有效，點擊後長輩設備即可自動免密登入回原本帳號。',
                  tone: FamTone.warm,
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: FamButton(
                        label: '取消',
                        kind: FamButtonKind.ghost,
                        onPressed: _isGeneratingRecovery ? null : () => Navigator.pop(dialogContext),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FamButton(
                        label: '產生並分享',
                        loading: _isGeneratingRecovery,
                        onPressed: _isGeneratingRecovery
                            ? null
                            : () async {
                                final shortId = _elderProfileData?['elder_id'] ?? widget.currentElder?.elderId;
                                final familyId = widget.userId;

                                if (shortId == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    famSnackBar(context, '無法產生連結：缺少長輩的配對身分資訊', error: true),
                                  );
                                  return;
                                }

                                setDialogState(() => _isGeneratingRecovery = true);
                                setState(() => _isGeneratingRecovery = true);

                                try {
                                  final result = await ApiService.generateRecoveryLink(
                                    familyId: familyId,
                                    elderId: shortId.toString(),
                                  );

                                  if (result['status'] == 'success' && result['data'] != null) {
                                    final recoveryUrl = result['data']['recovery_url'];
                                    final shareText = '【Uban 長輩快速登入】\n'
                                        '哈囉，這是您的專屬登入連結。請在新手機點擊此連結，即可自動登入回原本的帳號喔！\n\n'
                                        '$recoveryUrl\n\n'
                                        '⚠️ 注意：連結僅於 15 分鐘內有效。';

                                    await SharePlus.instance.share(
                                      ShareParams(
                                        text: shareText,
                                        subject: 'Uban 快速移機連結',
                                      ),
                                    );
                                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                                  } else {
                                    final errorMsg = result['error'] ?? result['message'] ?? result['detail'] ?? '產生連結失敗';
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        famSnackBar(context, errorMsg.toString(), error: true),
                                      );
                                    }
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      famSnackBar(context, '連線失敗: $e', error: true),
                                    );
                                  }
                                } finally {
                                  // dialog 可能已被關閉（分享成功後 pop），此時 StatefulBuilder 已 dispose。
                                  if (context.mounted) {
                                    setDialogState(() => _isGeneratingRecovery = false);
                                  }
                                  if (mounted) {
                                    setState(() => _isGeneratingRecovery = false);
                                  }
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 卡片進場淡入（與改版前相同的節奏）。
  Widget _fadeIn(Widget w, int delayMs) =>
      w.animate().fadeIn(delay: delayMs.ms, duration: 350.ms);

  @override
  Widget build(BuildContext context) {
    // 2026-10：資料分頁自己掛家屬主題（深色開關即時套用）；Builder 讓下方 context 位於主題之內。
    return FamilyThemeScope(
      child: Builder(builder: _buildScreen),
    );
  }

  Widget _buildScreen(BuildContext context) {
    _themed = context;
    return RefreshIndicator(
      color: _c.brandFill,
      backgroundColor: _c.surface,
      onRefresh: _refreshAll,
      child: CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, UbanGlassNavBar.totalHeight + MediaQuery.paddingOf(context).bottom + 16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // ★ 第五十一輪（任務 2）：以下每一張動態卡片都包了一層
              //   `ErrorBoundary`——原本這裡是直接呼叫 `_buildXxxCard()`，
              //   任一個 builder 內部丟例外都會炸穿本方法（`build()` 這一次
              //   Dart 函式呼叫），Flutter 沒有機會在單一卡片的層級攔截，
              //   結果是整個分頁被換成 `ErrorWidget`；本頁又活在
              //   `IndexedStack` 底下被保活、父層每 2.5 秒的輪詢會不斷觸發
              //   重建，同一個例外會一路重現到使用者重開 App 為止（完整
              //   機制說明見 `../../widgets/error_boundary.dart` 檔頭）。
              //   目前沒有指認出單一會拋出的行，因此這裡不臆測成因去改動
              //   任何卡片本身的邏輯，只讓失敗可以被侵限在一張卡片內、
              //   並透過 `debugPrint` 留下診斷線索。

              // 1. 家屬個人卡片 (Caregiver Identity)
              ErrorBoundary(name: '家屬個人卡片', builder: () => _buildCaregiverCard()),
              const SizedBox(height: 14),

              // 介面主題風格設定（資料 Tab 切換淺色/深色模式，預設為淺色）
              ErrorBoundary(
                name: '外觀風格與色彩主題',
                builder: () => _fadeIn(
                  FamGroup(title: '外觀', children: [
                    FamSetRow(
                      title: '深色模式',
                      subtitle: widget.isDarkMode ? '目前使用深色模式' : '目前使用淺色模式（預設），晚上看比較不刺眼',
                      trailing: UbanSwitch(
                        value: widget.isDarkMode,
                        onChanged: (val) => widget.onToggleDarkMode?.call(val),
                      ),
                    ),
                  ]),
                  200,
                ),
              ),
              const SizedBox(height: 14),

              // 2. 當前受關照長輩詳細健康資料 (Elder Profile Summary)
              if (widget.currentElder != null) ...[
                ErrorBoundary(name: '長輩檔案摘要卡片', builder: () => _buildElderSummaryCard()),
                const SizedBox(height: 14),

                // 2.5 健康趨勢入口 + 情緒關注預覽卡（第五十輪：接回導覽，見檔頭註解）
                // 2.6 外出趨勢入口（移動軌跡延伸第三階段）
                ErrorBoundary(name: '趨勢入口卡片', builder: () => _buildTrendsEntries()),
                const SizedBox(height: 14),
                ErrorBoundary(
                  name: '情緒關注預覽卡片',
                  builder: () => EmotionPreviewCard(
                    elderName: widget.currentElder!.displayName,
                    elderId: widget.currentElder!.id,
                  ),
                ),
                const SizedBox(height: 14),

                // 3. 長輩人生故事膠囊 (Memoirs & Family Legacy)
                ErrorBoundary(name: '人生故事膠囊卡片', builder: () => _buildMemoirsCard()),
                const SizedBox(height: 14),

                // 4. 長輩互動與對話偏好 (Companion Preferences)
                ErrorBoundary(name: 'AI 互動偏好卡片', builder: () => _buildAiHelperCard()),
                const SizedBox(height: 14),
              ] else ...[
                // 未選擇長輩引導卡片
                ErrorBoundary(name: '未選擇長輩引導卡片', builder: () => _buildNoElderSelectedCard()),
                const SizedBox(height: 14),
              ],

              // 5. 智慧照護與即時通知設定 (Care & Notification)
              ErrorBoundary(
                name: '安全防護與日常通知設定',
                builder: () => _fadeIn(
                  FamGroup(title: '通知', children: [
                    _switchRow(
                      '跌倒與緊急求救',
                      '長輩端觸發緊急警報時，第一時間彈窗並強制響鈴提醒',
                      _isEmergencyOn,
                      (val) => setState(() => _isEmergencyOn = val),
                    ),
                    _switchRow(
                      '吃藥打卡',
                      '長輩完成吃藥打卡或未按時服藥時，即時推播回報',
                      _isMedicationPushOn,
                      (val) => setState(() => _isMedicationPushOn = val),
                    ),
                    _switchRow(
                      '每天 18:00 健康日誌',
                      '每日 18:00 推播長輩今日活動紀錄與心情簡報',
                      _isDailySummaryOn,
                      (val) => setState(() => _isDailySummaryOn = val),
                    ),
                    _switchRow(
                      '作息與情緒預警',
                      '長輩生活作息不規律或情緒低落時的主動關懷建議',
                      _isAiInsightOn,
                      (val) => setState(() => _isAiInsightOn = val),
                    ),
                  ]),
                  200,
                ),
              ),
              const SizedBox(height: 14),

              // 6. 裝置配對、移機與訂閱管理 (Devices & Subscriptions)
              ErrorBoundary(
                name: '裝置配對與加值服務',
                builder: () => _fadeIn(
                  FamGroup(title: '裝置與加值', children: [
                    FamSetRow(
                      title: '訂閱方案與設備上限管理',
                      subtitle: '當前方案：$_subscriptionDisplay，管理監視設備數量與雲端功能',
                      chevron: true,
                      onTap: _openSubscription,
                    ),
                    FamSetRow(
                      title: '配對新長輩裝置',
                      subtitle: '掃描 QR Code 或輸入配對碼，連結其他長輩平板或手機',
                      chevron: true,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CaregiverPairingScreen(
                              familyId: widget.userId,
                              familyName: _caregiverName,
                            ),
                          ),
                        ).then((_) {
                          if (widget.onElderUpdated != null) {
                            widget.onElderUpdated!();
                          }
                        });
                      },
                    ),
                    if (widget.currentElder != null)
                      FamSetRow(
                        title: '長輩移機與免密重裝助手',
                        subtitle: '產生 15 分鐘專屬登入連結，長輩換手機或重裝時一鍵復原',
                        chevron: true,
                        onTap: _showRecoveryAssistantDialog,
                      ),
                  ]),
                  200,
                ),
              ),
              const SizedBox(height: 14),

              // 6.5 支援與意見回饋 (Support & Feedback)
              // ★ BUG 回報功能：低頻但重要，刻意不放頂層分頁、不放首頁／互動
              //   這種高頻畫面，比照裝置配對／訂閱等次級設定放在「資料」分頁。
              ErrorBoundary(
                name: '支援與意見回饋',
                builder: () => _fadeIn(
                  FamGroup(title: '支援', children: [
                    FamSetRow(
                      title: '回報問題 / 意見反饋',
                      subtitle: '遇到問題或有建議？點此回報，我們會盡快處理',
                      chevron: true,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FamilyBugReportScreen(familyId: widget.userId),
                          ),
                        );
                      },
                    ),
                  ]),
                  200,
                ),
              ),
              const SizedBox(height: 18),

              // 7. 系統資訊 (System Info)
              ErrorBoundary(name: '系統資訊卡片', builder: () => _buildSystemInfoCard()),
            ]),
          ),
        ),
      ],
      ),
    );
  }

  // ─── 1. 家屬個人卡片 (Caregiver Card，`.me-card`) ───

  Widget _buildCaregiverCard() {
    final c = _c;
    final name = _caregiverName.isNotEmpty ? _caregiverName : '主要照護家屬';

    return _fadeIn(
      FamCard(
        key: widget.caregiverCardKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                FamAvatar(name: _caregiverName.isNotEmpty ? _caregiverName : 'U', size: 52),
                const SizedBox(width: 12),
                // 名稱是使用者自訂字串，必須可收縮（鐵律 #14）。
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: famText(c.text, 17, weight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '家屬管理員・帳號 ID: ${widget.userId}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: famText(c.text2, 13, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FamIconButton(
                  icon: Icons.edit_outlined,
                  tooltip: '編輯名稱',
                  onTap: _handleEditProfile,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(height: 1, color: c.line),
            // 快速方案狀態：整列可點，進訂閱頁。
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openSubscription,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Text('方案等級', style: famText(c.text2, 13)),
                    const SizedBox(width: 8),
                    Flexible(child: FamTier(label: _subscriptionDisplay)),
                    const Spacer(),
                    Text('管理方案',
                        style: famText(c.brandStrong, 14, weight: FontWeight.w700)),
                    Icon(Icons.chevron_right_rounded, size: 20, color: c.text3),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FamSmallBtn(
                label: '登出目前帳號',
                danger: true,
                onTap: _handleLogout,
              ),
            ),
          ],
        ),
      ),
      0,
    );
  }

  // ─── 2. 長輩基本資料與健康摘要卡 ───

  Widget _buildElderSummaryCard() {
    if (widget.currentElder == null) return const SizedBox.shrink();
    final elder = widget.currentElder!;
    final c = _c;

    final chronicDiseases = (_elderProfileData?['chronic_diseases'] ?? '尚未填寫').toString();
    final medicationNotes = (_elderProfileData?['medication_notes'] ?? '尚未填寫').toString();

    return _fadeIn(
      FamCard(
        key: widget.elderSummaryKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ★ 鐵律 #14 例行檢查（第四十九輪）：標題與同列「編輯資料」按鈕，標題在 Expanded
            // 內（FamSecHead）可收縮。
            FamSecHead(
              title: '受關照長輩檔案',
              trailing: FamMore(label: '編輯資料', onTap: _navigateToElderEdit),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FamAvatar(name: elder.displayName, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ★ 第四十五輪（例行溢位檢查）：displayName 是長輩顯示名稱，長度不可控，
                      // 可收縮並加 ellipsis，避免 RenderFlex 溢位。
                      Text(
                        elder.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: famText(c.text, 17, weight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '長輩端: ${elder.elderId ?? "E00${elder.id}"}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: famText(c.text3, 12.5, tabular: true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${elder.age != null ? "${elder.age} 歲" : "年齡未填"}・${elder.gender == "F" ? "女性" : "男性"}・居於 ${(elder.location != null && elder.location!.isNotEmpty) ? elder.location : "台北市"}',
              style: famText(c.text2, 14, height: 1.5),
            ),
            const SizedBox(height: 12),
            // 健康摘要：兩條標籤＋內容（內容可換行，長字串不溢位）。
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('慢性病與健康注意', style: famText(c.text2, 12, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    chronicDiseases,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: famText(c.text, 14.5, weight: FontWeight.w600, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  Text('用藥備註', style: famText(c.text2, 12, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    medicationNotes,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: famText(c.text, 14.5, weight: FontWeight.w600, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      50,
    );
  }

  // ─── 2.5／2.6 健康趨勢與外出趨勢入口（`.twin` + `.entry`） ───
  // 第五十輪新增：`HealthTrendsScreen` 早就做好真實資料串接（步數/體重/身高），
  // 但全專案沒有任何入口導覽過去，屬於死碼。這裡補入口卡，點下去進
  // `HealthTrendsScreen`；心率/血壓/血糖仍會顯示 `--`，那是該畫面自己誠實
  // 標示「需穿戴裝置，目前無法偵測」，不在本卡片重複描述細節。
  // 外出趨勢入口：刻意用靜態文字、不在本分頁預先打 `getDaily`——本頁已有多支
  // 啟動即呼叫的 API，而且父層輪詢會頻繁重建；數字都在點進去的畫面裡，所以也沒有
  // 迷你走勢（設計稿的 `.spark` 在此沒有可用資料，不假造）。
  // 版面注意（第五十二輪）：Flexible／Expanded 只能是 Row／Column「有界主軸」的直接子節點，
  // 不可在無界高度的 Column 底下再包 Flexible。這裡的 Expanded 都在 Row 內。

  Widget _buildTrendsEntries() {
    if (widget.currentElder == null) return const SizedBox.shrink();
    final elder = widget.currentElder!;

    return _fadeIn(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: FamEntryCard(
              title: '健康趨勢',
              subtitle: '步數、體重、身高',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HealthTrendsScreen(
                      elderName: elder.displayName,
                      elderId: elder.id,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FamEntryCard(
              title: '外出趨勢',
              subtitle: '外出次數、距離、在外時間',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OutingTrendsScreen(
                      // 與首頁 GPS 軌跡卡片一致：優先用長輩的 elderId 字串，缺漏才退回資料庫 id。
                      elderId: elder.elderId ?? elder.id.toString(),
                      userId: widget.userId,
                      elderName: elder.displayName,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      75,
    );
  }

  // ─── 3. 人生故事膠囊 (Memoirs & Family Legacy) ───

  Widget _buildMemoirsCard() {
    final name = widget.currentElder?.displayName ?? '長輩';
    final c = _c;

    final stories = _memoirStories;
    final elderId = widget.currentElder?.elderId ?? widget.currentElder?.id.toString() ?? 'default_elder';

    String two(int n) => n.toString().padLeft(2, '0');

    return _fadeIn(
      FamCard(
        key: widget.memoirsKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 卡片頂部標題列（點擊「珍藏 N 篇」可進入完整回憶錄畫廊）
            FamSecHead(
              title: '$name的人生故事',
              trailing: FamMore(
                label: '珍藏 ${stories.length} 篇',
                onTap: () => _openMemoirsGallery(elderId, name),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '由日常對話口述整理紀錄，珍藏長輩的人生智慧與家族回憶',
              style: famText(c.text2, 13, height: 1.5),
            ),
            const SizedBox(height: 8),

            // 故事列表（最多展示前 3 篇，點擊可開啟原聲聆聽詳情彈窗）
            if (_isLoadingMemoirs)
              const FamStateBlock(
                height: 80,
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (stories.isEmpty)
              const FamNote(
                text: '長輩尚未與小豬分享故事，點擊下方「委託小豬提問」讓小豬主動發問吧！',
              )
            else
              for (var i = 0; i < stories.take(3).length; i++)
                FamStoryRow(
                  first: i == 0,
                  title: stories[i].title,
                  meta:
                      '${two(stories[i].recordedDate.month)}/${two(stories[i].recordedDate.day)}・${stories[i].tag}${stories[i].familyNotes.isNotEmpty ? '・${stories[i].familyNotes.length} 則筆記' : ''}',
                  onTap: () => MemoirDetailSheet.show(
                    _themeCtx,
                    story: stories[i],
                    elderName: name,
                    familyUserName: widget.userName,
                  ),
                ),

            const SizedBox(height: 10),

            // 底部快捷按鈕：進入回憶錄畫廊與委託小豬提問（兩者原本就都導向畫廊）
            FamButton(
              label: '翻閱自傳畫廊 (${stories.length})',
              kind: FamButtonKind.tonal,
              height: 46,
              onPressed: () => _openMemoirsGallery(elderId, name),
            ),
            const SizedBox(height: 8),
            FamButton(
              label: '委託小豬提問',
              kind: FamButtonKind.outline,
              height: 46,
              onPressed: () => _openMemoirsGallery(elderId, name),
            ),
          ],
        ),
      ),
      100,
    );
  }

  // ─── 4. AI 陪伴助理設定狀態與偏好 ───

  Widget _buildAiHelperCard() {
    if (widget.currentElder == null) return const SizedBox.shrink();

    if (_isLoadingAiProfile) {
      return FamCard(
        key: widget.aiHelperKey,
        child: const FamStateBlock(
          height: 68,
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    const unset = '尚未設定';
    final appRaw = (_elderProfileData?['appellation'] ?? widget.currentElder?.appellation)?.toString().trim();
    final appellation = (appRaw == null || appRaw.isEmpty) ? unset : appRaw;
    final tone = num.tryParse('${_elderProfileData?['ai_emotion_tone'] ?? ''}');
    final verbosity = num.tryParse('${_elderProfileData?['ai_text_verbosity'] ?? ''}');
    final rawInterests = _elderProfileData?['interests'];
    final interests = rawInterests is List
        ? rawInterests.map((e) => '$e').where((e) => e.trim().isNotEmpty).join('、')
        : (rawInterests?.toString().trim() ?? '');

    String level(num? v, String hi, String lo, String mid) {
      if (v == null) return unset;
      final pct = '${v.round()}%';
      return '${v > 60 ? hi : v < 40 ? lo : mid} ($pct)';
    }

    return _fadeIn(
      FamCard(
        key: widget.aiHelperKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FamSecHead(title: '長輩互動與對話偏好'),
            const SizedBox(height: 10),
            _buildInfoRow('互動稱呼長輩', appellation, first: true),
            _buildInfoRow('陪伴語氣風格', level(tone, '活潑熱情', '沉穩客觀', '溫和適中')),
            _buildInfoRow('對話回覆篇幅', level(verbosity, '詳細會聊天', '簡潔扼要', '適度互動')),
            _buildInfoRow('記憶與話題偏好', interests.isEmpty ? unset : interests),
            const SizedBox(height: 12),
            FamButton(
              label: '調整互動對話設定',
              kind: FamButtonKind.tonal,
              height: 46,
              onPressed: _navigateToElderEdit,
            ),
          ],
        ),
      ),
      150,
    );
  }

  Widget _buildInfoRow(String label, String value, {bool first = false}) {
    final c = _c;

    // 標籤與內容都在 Expanded 內（2:3），放大字級與長內容都可收縮（鐵律 #14）。
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: famText(c.text2, 14, weight: FontWeight.w600, height: 1.4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: famText(c.text, 14.5, weight: FontWeight.w700, height: 1.4),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 5. 設定項目（`.setrow` + `UbanSwitch`） ───

  Widget _switchRow(
    String title,
    String description,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return FamSetRow(
      title: title,
      subtitle: description,
      trailing: UbanSwitch(value: value, onChanged: onChanged),
    );
  }

  // ─── 6. 未選擇長輩引導卡片 ───

  Widget _buildNoElderSelectedCard() {
    final c = _c;

    return FamCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '尚未選擇要關照的長輩',
            textAlign: TextAlign.center,
            style: famText(c.text, 18, weight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            '請在上方切換長輩，或點擊下方按鈕配對新的長輩端設備',
            textAlign: TextAlign.center,
            style: famText(c.text2, 14, height: 1.5),
          ),
          const SizedBox(height: 18),
          FamButton(
            label: '配對新長輩裝置',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CaregiverPairingScreen(
                    familyId: widget.userId,
                    familyName: _caregiverName,
                  ),
                ),
              ).then((_) {
                if (widget.onElderUpdated != null) {
                  widget.onElderUpdated!();
                }
              });
            },
          ),
        ],
      ),
    );
  }

  // ─── 7. 系統資訊 ───

  Widget _buildSystemInfoCard() {
    final c = _c;

    return Text(
      'Uban 智慧伴老照護系統・v2.4.0 (Build 2026.08)',
      textAlign: TextAlign.center,
      style: famText(c.text3, 12, tabular: true, height: 1.5),
    );
  }
}
