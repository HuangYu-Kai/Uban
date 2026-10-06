import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lunar/lunar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/almanac_data_helper.dart';
import '../../widgets/ui/ui.dart';
import 'elder_layout.dart';
import '../pet_companion_studio/models/pet_growth_state.dart';
import 'pet/pet_breed_store.dart';
import 'pet/pet_ear_anchors.dart';
import 'greeting/greeting_quotes.dart';
import 'greeting/greeting_template_manifest.dart';

/// 經典圖文成品範例（嚴格以「蓮花早安圖」為標準：定義安全避讓留白區）
class ClassicPhotoTemplate {
  final String id;
  final String name;
  final String bgAsset;
  final IconData icon;
  final Alignment textAlign;
  final EdgeInsets textPadding;
  final Color defaultColor;
  final List<Shadow> defaultShadows;
  final String defaultMain;
  final String defaultSub;
  final String categoryTag;
  final String category; // 'flower', 'tea', 'scenery', 'solar_term', 'festival'
  final bool isHolidaySpecial;
  final bool isSolarTermSpecial;

  const ClassicPhotoTemplate({
    required this.id,
    required this.name,
    required this.bgAsset,
    required this.icon,
    required this.textAlign,
    required this.textPadding,
    required this.defaultColor,
    required this.defaultShadows,
    required this.defaultMain,
    required this.defaultSub,
    required this.categoryTag,
    required this.category,
    this.isHolidaySpecial = false,
    this.isSolarTermSpecial = false,
  });
}

/// manifest 單筆 → 經典範本。`text_position` 決定預設文字落點（沿用既有的
/// Alignment＋padding 系統，之後仍可拖動），`dark_bg` 決定亮字（深色底）或
/// 招牌寶藍字＋白光暈（淺色底）。預設句依分類帶一句主題吉祥話。
ClassicPhotoTemplate classicTemplateFromEntry(GreetingTemplateEntry e,
    {DateTime? now}) {
  final Alignment align;
  final EdgeInsets padding;
  switch (e.textPosition) {
    case 'topCenter':
      align = Alignment.topCenter;
      padding = const EdgeInsets.only(left: 20, top: 28, right: 20, bottom: 40);
    case 'topRight':
      align = Alignment.topRight;
      padding = const EdgeInsets.only(left: 40, top: 28, right: 24, bottom: 40);
    case 'bottomLeft':
      align = Alignment.bottomLeft;
      padding = const EdgeInsets.only(left: 24, bottom: 26, right: 28, top: 30);
    default:
      align = Alignment.topLeft;
      padding = const EdgeInsets.only(left: 24, top: 28, right: 30, bottom: 40);
  }
  final Color color =
      e.darkBg ? const Color(0xFFFEF08A) : const Color(0xFF0052D4);
  final List<Shadow> shadows = e.darkBg
      ? const [
          Shadow(color: Color(0xFF78350F), blurRadius: 16),
          Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(2, 2)),
        ]
      : const [
          Shadow(color: Colors.white, blurRadius: 26),
          Shadow(color: Colors.white, blurRadius: 18),
          Shadow(color: Colors.white, blurRadius: 10),
          Shadow(color: Colors.white, blurRadius: 4),
          Shadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(2, 2)),
        ];
  return ClassicPhotoTemplate(
    id: e.id,
    name: e.title,
    bgAsset: e.assetPath,
    icon: _iconForCategory(e.category),
    categoryTag: kGreetingCategoryLabels[e.category] ?? e.category,
    category: e.category,
    textAlign: align,
    textPadding: padding,
    defaultColor: color,
    defaultShadows: shadows,
    defaultMain:
        GreetingQuoteGenerator.themedDefault(e.category, e.id, now: now),
    defaultSub: '心寬福就來，天天好心境。',
  );
}

IconData _iconForCategory(String c) {
  switch (c) {
    case 'lotus':
    case 'flower':
      return Icons.local_florist_rounded;
    case 'koi':
    case 'lake':
      return Icons.water_rounded;
    case 'sunrise':
      return Icons.wb_twilight_rounded;
    case 'bamboo':
      return Icons.grass_rounded;
    case 'mountain':
      return Icons.terrain_rounded;
    case 'tea':
      return Icons.emoji_food_beverage_rounded;
    default:
      return Icons.image_rounded;
  }
}

/// 👵 每日吉利長輩祝賀圖分頁（1:1 方形、成品範例主體避讓、金句排列組合、語音防呆排版）
class ElderGreetingTab extends StatefulWidget {
  final int userId;
  final String userName;

  /// 嵌入模式：作為「小豬」分頁下半部的子區塊使用（由外層的捲動容器負責捲動與
  /// 底部導覽列留白）。true 時不自帶 SafeArea／Expanded／內部捲動，一律用單欄
  /// 版面；其餘邏輯（範本、金句、分享、存圖）完全不變。
  final bool embedded;

  /// 外層（小豬分頁的 `_refreshAll`）通知「小豬品種／階段可能變了」的訊號；
  /// 每次通知時本分頁重讀品種與階段，祝賀圖上的小豬才會跟著更新。
  final Listenable? refreshSignal;

  /// 新手指引高光目標（掛在祝賀圖預覽卡片上，不含下方整排工具），由
  /// ElderHomeScreen 經 ElderPetTab 傳入。
  final GlobalKey? tutorialKey;

  /// 讀範本清單（manifest）用的 bundle；null＝`rootBundle`。測試用。
  final AssetBundle? assetBundle;

  const ElderGreetingTab({
    super.key,
    required this.userId,
    required this.userName,
    this.embedded = false,
    this.refreshSignal,
    this.tutorialKey,
    this.assetBundle,
  });

  @override
  State<ElderGreetingTab> createState() => _ElderGreetingTabState();
}

class _ElderGreetingTabState extends State<ElderGreetingTab> {
  final GlobalKey _cardRepaintKey = GlobalKey();

  // 狀態資料
  PetGrowthState? _petState;

  // 祝賀圖角落的「我的小豬」（預覽與輸出同一個 widget，輸出圖一定含小豬）
  static const String _kShowPigPrefKey = 'greeting_show_pig';
  bool _showPig = true;
  PetBreed _pigBreed = PetBreed.pink;
  int _pigStage = 1; // 1..5
  bool _wasVisible = false;
  late String _customSenderName;
  bool _isSharing = false;

  // 經典模式選中範本
  int _classicTemplateIndex = 0;
  // 經典字體樣式切換 (0: 招牌白光藍 1: 喜慶立體金 2: 暖陽純白)
  int _classicFontStyleIndex = 0;

  // ── 經典祝賀圖「拖動小豬／文字」自訂位置（依範本分別記憶）──
  // 值為「元素左上角 ÷ 方形邊長」的比例（0..1），null＝用範本預設位置。
  // 以比例儲存，換螢幕尺寸與 2.8 倍匯出都不會跑位。
  static const String _kLayoutHintPrefKey = 'greeting_layout_hint_seen';
  Offset? _pigFrac;
  // 小豬的預設落點（量測文字實際範圍後選出不重疊的角落）；null＝先用版面預設。
  Alignment? _pigCorner;
  // 預設落點四角都蓋到字時，把小豬縮小（1.0＝正常大小，最小 0.5）。
  double _pigScale = 1.0;
  Offset? _textFrac;
  _GreetingDragItem? _draggingItem; // 拖動中才顯示虛線外框（匯出前一定是 null）
  bool _layoutHintSeen = false;
  final GlobalKey _squareKey = GlobalKey();
  final GlobalKey _pigItemKey = GlobalKey();
  final GlobalKey _textItemKey = GlobalKey();
  // 單次拖動的起點資訊
  Offset _dragStartGlobal = Offset.zero;
  Offset _dragStartTopLeft = Offset.zero; // 方形座標（px）
  Size _dragChildSize = Size.zero;

  // 目前的祝福句（「換句好話」由排列組合產生器產生）
  final GreetingQuoteGenerator _quoteGen = GreetingQuoteGenerator();
  late GreetingQuote _currentQuote =
      GreetingQuote(_classicTemplates[0].defaultMain, GreetingQuoteGenerator.curated[0].subTitle);

  // 範本預設文字覆寫
  String? _customTemplateMainText;

  // 日期與節氣資訊（用於 LINE 分享文字）
  late DateTime _now;
  late String _solarTerm;
  late String _lunarDateStr;
  late DayAlmanacInfo _almanacInfo;

  // ════════════════════════════════════════════════════════════════
  // 1. 經典圖文成品範例庫（嚴格定義留白避讓區，1:1 方形標準）
  // ════════════════════════════════════════════════════════════════
  static const List<ClassicPhotoTemplate> _builtinTemplates = [
    // 01 蓮花圖（早安花卉）
    ClassicPhotoTemplate(
      id: 'classic_lotus',
      name: '出水芙蓉・蓮花仙韻',
      bgAsset: 'assets/images/classic_lotus.png',
      icon: Icons.local_florist_rounded,
      categoryTag: '長輩必傳首選',
      category: 'flower',
      textAlign: Alignment.bottomLeft,
      textPadding: EdgeInsets.only(left: 24, bottom: 26, right: 28, top: 30),
      defaultColor: Color(0xFF0052D4), // 招牌亮寶藍
      defaultShadows: [
        Shadow(color: Colors.white, blurRadius: 26),
        Shadow(color: Colors.white, blurRadius: 18),
        Shadow(color: Colors.white, blurRadius: 10),
        Shadow(color: Colors.white, blurRadius: 4),
        Shadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(2, 2)),
      ],
      defaultMain: '早安\n感謝\n祝您一天順利',
      defaultSub: '心寬福就來，天天好心境。',
    ),
    // 02 晨光茶几（晨光茶席）
    ClassicPhotoTemplate(
      id: 'classic_tea_table',
      name: '早茶歲月・一品清香',
      bgAsset: 'assets/images/classic_tea_table.jpg',
      icon: Icons.emoji_food_beverage_rounded,
      categoryTag: '晨光茶韻',
      category: 'tea',
      textAlign: Alignment.topLeft,
      textPadding: EdgeInsets.only(left: 24, top: 28, right: 30, bottom: 40),
      defaultColor: Color(0xFFFDE047), // 溫潤金黃
      defaultShadows: [
        Shadow(color: Color(0xFF78350F), offset: Offset(2, 3), blurRadius: 6),
        Shadow(color: Colors.black87, blurRadius: 12, offset: Offset(1, 2)),
      ],
      defaultMain: '早安 暖心\n喝杯好茶 順心吉祥',
      defaultSub: '一壺清茶迎旭日，淡泊從容福自來。',
    ),
    // 03 阿里山茶園（四季山水）
    ClassicPhotoTemplate(
      id: 'classic_tea_mountain',
      name: '阿里山茶香・晨曦朝陽',
      bgAsset: 'assets/images/classic_tea_mountain.jpg',
      icon: Icons.terrain_rounded,
      categoryTag: '高山破曉',
      category: 'scenery',
      textAlign: Alignment.topCenter,
      textPadding: EdgeInsets.only(left: 20, top: 28, right: 20, bottom: 40),
      defaultColor: Color(0xFFFFD54F), // 朝陽金色
      defaultShadows: [
        Shadow(color: Color(0xFF92400E), offset: Offset(2, 3), blurRadius: 8),
        Shadow(color: Colors.black87, blurRadius: 14, offset: Offset(1, 2)),
      ],
      defaultMain: '晨曦破曉・心寬福自來',
      defaultSub: '陽光穿透薄霧，祝好友新的一天步步高升！',
    ),
    // 04 富貴牡丹（早安花卉）
    ClassicPhotoTemplate(
      id: 'classic_peony',
      name: '花開富貴・牡丹迎春',
      bgAsset: 'assets/images/classic_peony_flower.jpg',
      icon: Icons.filter_vintage_rounded,
      categoryTag: '繁花富貴',
      category: 'flower',
      textAlign: Alignment.topRight,
      textPadding: EdgeInsets.only(left: 40, top: 28, right: 24, bottom: 40),
      defaultColor: Colors.white,
      defaultShadows: [
        Shadow(color: Color(0xFF9D174D), blurRadius: 18),
        Shadow(color: Colors.black, blurRadius: 10, offset: Offset(2, 2)),
      ],
      defaultMain: '花開富貴\n知足常樂 平安是福',
      defaultSub: '錦上添花人歡喜，願您笑口常開、福澤綿長。',
    ),
    // 05 節慶限定・中秋賞月團圓（節慶祝賀）
    ClassicPhotoTemplate(
      id: 'festival_moon',
      name: '節慶特選・中秋月圓',
      bgAsset: 'assets/images/festival_moon_cake.jpg',
      icon: Icons.nightlight_round,
      categoryTag: '節慶限定・中秋',
      category: 'festival',
      textAlign: Alignment.topLeft,
      textPadding: EdgeInsets.only(left: 24, top: 28, right: 30, bottom: 40),
      defaultColor: Color(0xFFFEF08A),
      defaultShadows: [
        Shadow(color: Color(0xFF991B1B), blurRadius: 18),
        Shadow(color: Colors.black, blurRadius: 12, offset: Offset(2, 2)),
      ],
      defaultMain: '中秋吉祥\n月圓人團圓 闔家安康',
      defaultSub: '柚見佳節人長久，千里嬋娟共祝願！',
      isHolidaySpecial: true,
    ),
    // 06 綠意禪心（晨光茶席 / 禪意）
    ClassicPhotoTemplate(
      id: 'zen_pond',
      name: '綠意禪心・靜水微瀾',
      bgAsset: 'assets/images/zen_pond_bg.png',
      icon: Icons.spa_rounded,
      categoryTag: '清幽禪意',
      category: 'tea',
      textAlign: Alignment.topLeft,
      textPadding: EdgeInsets.only(left: 24, top: 28, right: 30, bottom: 30),
      defaultColor: Color(0xFFFEF08A),
      defaultShadows: [
        Shadow(color: Color(0xFF065F46), blurRadius: 16),
        Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(2, 2)),
      ],
      defaultMain: '靜心常樂\n淡泊明志 福自來',
      defaultSub: '心如止水無憂慮，天天喜樂伴安康。',
    ),
    // 08 白露時令（時令節氣）
    ClassicPhotoTemplate(
      id: 'solar_autumn_cool',
      name: '時令節氣・白露凝涼',
      bgAsset: 'assets/images/classic_tea_mountain.jpg',
      icon: Icons.eco_rounded,
      categoryTag: '節氣今日特選',
      category: 'solar_term',
      textAlign: Alignment.topCenter,
      textPadding: EdgeInsets.only(left: 20, top: 28, right: 20, bottom: 30),
      defaultColor: Color(0xFFE0F2FE),
      defaultShadows: [
        Shadow(color: Color(0xFF0369A1), blurRadius: 16),
        Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(2, 2)),
      ],
      defaultMain: '時令添衣\n順天應時保安康',
      defaultSub: '節氣轉換早晚涼，記得多添薄衣裳。',
      isSolarTermSpecial: true,
    ),
    // 09 霜降時節（時令節氣）
    ClassicPhotoTemplate(
      id: 'solar_frost',
      name: '時令節氣・霜降福安',
      bgAsset: 'assets/images/classic_tea_table.jpg',
      icon: Icons.severe_cold_rounded,
      categoryTag: '節氣特選',
      category: 'solar_term',
      textAlign: Alignment.topLeft,
      textPadding: EdgeInsets.only(left: 24, top: 28, right: 30, bottom: 30),
      defaultColor: Color(0xFFFEF3C7),
      defaultShadows: [
        Shadow(color: Color(0xFF78350F), blurRadius: 16),
        Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(2, 2)),
      ],
      defaultMain: '霜降平安\n防寒保暖身心泰',
      defaultSub: '秋盡冬來迎新季，祝好友闔家幸福、四季平安。',
      isSolarTermSpecial: true,
    ),
    // 10 歲時年節（節慶祝賀）
    ClassicPhotoTemplate(
      id: 'festival_cny',
      name: '歲時年節・春滿乾坤',
      bgAsset: 'assets/images/classic_peony_flower.jpg',
      icon: Icons.celebration_rounded,
      categoryTag: '年節特選',
      category: 'festival',
      textAlign: Alignment.topRight,
      textPadding: EdgeInsets.only(left: 30, top: 28, right: 24, bottom: 30),
      defaultColor: Color(0xFFFEF08A),
      defaultShadows: [
        Shadow(color: Color(0xFF991B1B), blurRadius: 20),
        Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(2, 2)),
      ],
      defaultMain: '春滿人間\n福祿壽全富貴長',
      defaultSub: '歲序更替迎新春，全家老少福泰安康。',
      isHolidaySpecial: true,
    ),
  ];

  /// 目前可選的範本：內建 + manifest 載入的新範本（載入失敗就只有內建）。
  late List<ClassicPhotoTemplate> _classicTemplates =
      List.of(_builtinTemplates);

  @override
  void initState() {
    super.initState();
    _customSenderName = widget.userName.trim().isNotEmpty ? widget.userName : '萬發阿公';
    _customTemplateMainText = _classicTemplates[0].defaultMain;
    _initDateAndAlmanac();
    _loadPetState();
    unawaited(_loadPigPrefs());
    widget.refreshSignal?.addListener(_reloadPig);
    _checkAndPrioritizeHolidayTemplates();
    unawaited(_loadLayout());
    unawaited(_loadHintFlag());
    unawaited(_loadManifestTemplates());
  }

  /// 載入 manifest 的新範本並接在內建範本後面（索引不變、已選範本不受影響）。
  /// 清單不存在／壞掉／全重複時什麼都不做，維持只有內建範本。
  Future<void> _loadManifestTemplates() async {
    final entries =
        await loadGreetingManifest(widget.assetBundle ?? rootBundle);
    if (!mounted || entries.isEmpty) return;
    final existing = {for (final t in _classicTemplates) t.id};
    final added = [
      for (final e in entries)
        if (!existing.contains(e.id)) classicTemplateFromEntry(e),
    ];
    if (added.isEmpty) return;
    setState(() => _classicTemplates = [..._classicTemplates, ...added]);
  }

  @override
  void didUpdateWidget(covariant ElderGreetingTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_reloadPig);
      widget.refreshSignal?.addListener(_reloadPig);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 分頁由不可見變可見（IndexedStack 以 TickerMode 開關）時重讀小豬品種／階段。
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_wasVisible && mounted) unawaited(_reloadPig());
    _wasVisible = visible;
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_reloadPig);
    super.dispose();
  }

  /// 讀取「放上我的小豬」開關（預設開）＋品種／階段。
  Future<void> _loadPigPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final on = prefs.getBool(_kShowPigPrefKey) ?? true;
      if (mounted && on != _showPig) setState(() => _showPig = on);
    } catch (_) {}
    await _reloadPig();
  }

  /// 重讀小豬品種（PetBreedStore）與成長階段（1..5）；讀不到就維持粉紅豬第 1 階。
  Future<void> _reloadPig() async {
    PetBreed breed = PetBreed.pink;
    int stage = 1;
    try {
      breed = await PetBreedStore.load();
    } catch (_) {}
    try {
      stage = (await PetStorageService.loadState()).stage.index + 1;
    } catch (_) {}
    if (!mounted) return;
    if (breed != _pigBreed || stage != _pigStage) {
      setState(() {
        _pigBreed = breed;
        _pigStage = stage.clamp(1, 5);
      });
    }
  }

  Future<void> _setShowPig(bool v) async {
    HapticFeedback.lightImpact();
    setState(() => _showPig = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kShowPigPrefKey, v);
    } catch (_) {}
  }

  /// 祝賀圖上的小豬（疊在 RepaintBoundary 內，預覽與 toImage 輸出共用）。
  /// [corner] 由版面決定，避開大字標語。寬度約為圖寬的 22%，加淡陰影。
  Widget _buildPigOverlay(Alignment corner) {
    if (!_showPig) return const SizedBox.shrink();
    final img = Image.asset(
      'assets/images/pet_breeds/${_pigBreed.id}_front_$_pigStage.png',
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
    return Positioned.fill(
      key: const ValueKey('greeting_pig_overlay'),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth * 0.22 * _pigScale;
          final pad = box.maxWidth * 0.04;
          // 白邊半徑：約小豬寬的 3.5%，視覺上與大字標語的白描邊粗細相當
          final r = w * 0.035;
          // 貼紙式白邊：把純白剪影複製 16 份、繞圓周位移，疊在原圖下方，
          // 邊緣會沿著小豬的透明輪廓走（不是方框／圓形）。同一個 img 實例，圖片只解碼一次。
          const n = 16;
          final white = ColorFiltered(
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            child: img,
          );
          final outlined = Stack(
            key: const ValueKey('greeting_pig_outline'),
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < n; i++)
                Transform.translate(
                  offset: Offset(
                    r * math.cos(2 * math.pi * i / n),
                    r * math.sin(2 * math.pi * i / n),
                  ),
                  child: white,
                ),
              img,
            ],
          );
          return _buildDraggableItem(
            item: _GreetingDragItem.pig,
            itemKey: _pigItemKey,
            align: corner,
            padding: EdgeInsets.all(pad),
            child: SizedBox(
                width: w,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 淡陰影：套在「含白邊的整體」外側，黑色剪影模糊後下移，讓小豬「站」在圖上
                    Transform.translate(
                      offset: Offset(0, w * 0.04),
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                        child: Opacity(
                          opacity: 0.35,
                          child: ColorFiltered(
                            colorFilter: const ColorFilter.mode(
                                Colors.black, BlendMode.srcIn),
                            child: outlined,
                          ),
                        ),
                      ),
                    ),
                    outlined,
                  ],
                ),
              ),
          );
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 拖動小豬／文字（經典模式）：位置記憶、夾限、還原
  // ════════════════════════════════════════════════════════════════

  String get _layoutPrefKey =>
      'greeting_layout_${_classicTemplates[_classicTemplateIndex].id}';

  bool get _hasCustomLayout => _pigFrac != null || _textFrac != null;

  /// 載入目前範本的自訂位置；換範本時先同步清掉舊範本的位置，
  /// 以免讀檔期間短暫套用上一個範本的座標。
  Future<void> _loadLayout() async {
    final id = _classicTemplates[_classicTemplateIndex].id;
    _pigFrac = null;
    _textFrac = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('greeting_layout_$id');
      Offset? pig, text;
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        Offset? parse(Object? v) {
          if (v is! Map) return null;
          final x = v['x'], y = v['y'];
          if (x is! num || y is! num) return null;
          return Offset(
              x.toDouble().clamp(0.0, 1.0), y.toDouble().clamp(0.0, 1.0));
        }

        pig = parse(m['pig']);
        text = parse(m['text']);
      }
      // 讀檔期間又換了範本：丟棄這次結果
      if (!mounted || _classicTemplates[_classicTemplateIndex].id != id) return;
      setState(() {
        _pigFrac = pig;
        _textFrac = text;
      });
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveLayout() async {
    // 先在「同步段」取下範本鍵與位置：存檔是非同步的，若 await 之後才讀，
    // 使用者剛好切了範本就會把 A 範本的拖動寫進（或清掉）B 範本的鍵。
    final key = _layoutPrefKey;
    final pig = _pigFrac;
    final text = _textFrac;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (pig == null && text == null) {
        await prefs.remove(key);
        return;
      }
      Map<String, double> enc(Offset o) => {'x': o.dx, 'y': o.dy};
      await prefs.setString(
        key,
        jsonEncode({
          if (pig != null) 'pig': enc(pig),
          if (text != null) 'text': enc(text),
        }),
      );
    } catch (_) {}
  }

  Future<void> _resetLayout() async {
    HapticFeedback.lightImpact();
    setState(() {
      _pigFrac = null;
      _textFrac = null;
    });
    await _saveLayout(); // 沒有自訂位置 → 會清掉儲存的鍵
  }

  Future<void> _loadHintFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(_kLayoutHintPrefKey) ?? false;
      if (mounted && seen != _layoutHintSeen) {
        setState(() => _layoutHintSeen = seen);
      }
    } catch (_) {}
  }

  Future<void> _markHintSeen() async {
    if (_layoutHintSeen) return;
    setState(() => _layoutHintSeen = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kLayoutHintPrefKey, true);
    } catch (_) {}
  }

  Offset? _fracOf(_GreetingDragItem item) =>
      item == _GreetingDragItem.pig ? _pigFrac : _textFrac;

  void _dragStart(_GreetingDragItem item, Offset global) {
    final itemBox = (item == _GreetingDragItem.pig ? _pigItemKey : _textItemKey)
        .currentContext
        ?.findRenderObject() as RenderBox?;
    final squareBox =
        _squareKey.currentContext?.findRenderObject() as RenderBox?;
    if (itemBox == null || squareBox == null || !itemBox.hasSize) return;
    HapticFeedback.lightImpact();
    _dragStartGlobal = global;
    _dragChildSize = itemBox.size;
    _dragStartTopLeft = itemBox.localToGlobal(Offset.zero, ancestor: squareBox);
    setState(() => _draggingItem = item);
  }

  void _dragUpdate(_GreetingDragItem item, Offset global) {
    if (_draggingItem != item) return;
    final squareBox =
        _squareKey.currentContext?.findRenderObject() as RenderBox?;
    if (squareBox == null || !squareBox.hasSize) return;
    final side = squareBox.size.width;
    if (side <= 0) return;
    final raw = _dragStartTopLeft + (global - _dragStartGlobal);
    // 夾限：整個元素一律留在圖內
    final x = raw.dx.clamp(0.0, math.max(0.0, side - _dragChildSize.width));
    final y = raw.dy.clamp(0.0, math.max(0.0, side - _dragChildSize.height));
    setState(() {
      final f = Offset(x / side, y / side);
      if (item == _GreetingDragItem.pig) {
        _pigFrac = f;
      } else {
        _textFrac = f;
      }
    });
  }

  void _dragEnd(_GreetingDragItem item) {
    if (_draggingItem != item) return;
    setState(() => _draggingItem = null);
    unawaited(_saveLayout());
    unawaited(_markHintSeen());
  }

  /// 可拖動元素：觸碰即開始拖（不用長按），用「立即勝出」的手勢辨識器，
  /// 在手勢競技場贏過外層垂直捲動；沒碰到元素的地方仍可捲動頁面。
  /// [align]/[padding] 是「沒有自訂位置」時的預設落點（與舊版 Align+Padding 完全相同）。
  Widget _buildDraggableItem({
    required _GreetingDragItem item,
    required Key itemKey,
    required Alignment align,
    required EdgeInsets padding,
    required Widget child,
  }) {
    final dragging = _draggingItem == item;
    return CustomSingleChildLayout(
      delegate: _GreetingItemLayout(
        frac: _fracOf(item),
        align: align,
        padding: padding,
      ),
      child: RawGestureDetector(
        key: ValueKey('greeting_drag_${item.name}'),
        behavior: HitTestBehavior.opaque,
        gestures: {
          _ImmediateDragRecognizer:
              GestureRecognizerFactoryWithHandlers<_ImmediateDragRecognizer>(
            () => _ImmediateDragRecognizer(),
            (r) {
              r.onStart = (p) => _dragStart(item, p);
              r.onUpdate = (p) => _dragUpdate(item, p);
              r.onEnd = () => _dragEnd(item);
            },
          ),
        },
        child: Transform.scale(
          key: itemKey, // 量測用（尺寸＝元素本身，不含外層撐滿的版面）
          scale: dragging ? 1.03 : 1.0,
          child: dragging
              ? CustomPaint(
                  key: const ValueKey('greeting_drag_highlight'),
                  foregroundPainter: _DashedOutlinePainter(),
                  child: child,
                )
              : child,
        ),
      ),
    );
  }

  /// 「還原位置」按鈕（只有目前範本有自訂位置時才出現；UbanButton 最小高 60）。
  Widget _buildResetLayoutButton() {
    if (!_hasCustomLayout) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: UbanButton(
        key: const ValueKey('greeting_layout_reset'),
        label: '還原位置',
        icon: Icons.restart_alt_rounded,
        variant: UbanButtonVariant.outline,
        onPressed: _resetLayout,
      ),
    );
  }

  /// 圖下方的拖動提示（拖過一次就不再出現；不在匯出的 RepaintBoundary 內）。
  Widget _buildLayoutHint() {
    if (_layoutHintSeen) {
      return const SizedBox.shrink();
    }
    final c = UbanColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        key: const ValueKey('greeting_layout_hint'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.open_with_rounded, size: 20, color: c.text2),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '可以用手指拖動小豬和文字',
              style: ubanText(16, FontWeight.w700, c.text2),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 「放上我的小豬」開關列（整列可點、高度 ≥56，長輩好按）。
  Widget _buildPigToggle() {
    final c = UbanColors.of(context);
    return UbanCard(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: InkWell(
        key: const ValueKey('greeting_pig_toggle'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => _setShowPig(!_showPig),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Icon(Icons.pets_rounded, size: 28, color: c.brandStrong),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '放上我的小豬',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: c.text,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              UbanSwitch(value: _showPig, onChanged: _setShowPig),
            ],
          ),
        ),
      ),
    );
  }

  void _initDateAndAlmanac() {
    _now = DateTime.now();
    _almanacInfo = AlmanacDataHelper.calculateForDate(_now);
    final lunar = Lunar.fromDate(_now);
    _lunarDateStr = '農曆${lunar.getMonthInChinese()}月${lunar.getDayInChinese()}';

    String term = lunar.getJieQi();
    if (term.isEmpty) {
      try {
        term = lunar.getPrevJieQi(true).getName();
      } catch (_) {
        term = '秋分';
      }
    }
    _solarTerm = term;
  }

  /// 節日自動置頂機制：在特定節慶時自動優先推薦節慶卡片
  void _checkAndPrioritizeHolidayTemplates() {
    final lunar = Lunar.fromDate(_now);
    final lunarMonth = lunar.getMonth();
    final lunarDay = lunar.getDay();

    // 中秋節偵測（農曆八月十三至八月十七）
    final isMidAutumn = (lunarMonth == 8 && lunarDay >= 13 && lunarDay <= 17);
    if (isMidAutumn) {
      final idx = _classicTemplates.indexWhere((t) => t.id == 'festival_moon');
      if (idx != -1) {
        _classicTemplateIndex = idx;
        _customTemplateMainText = _classicTemplates[idx].defaultMain;
      }
    }
  }

  Future<void> _loadPetState() async {
    try {
      final state = await PetStorageService.loadState();
      if (mounted) {
        setState(() {
          _petState = state;
        });
      }
    } catch (e) {
      debugPrint('⚠️ 載入小豬狀態失敗: $e');
    }
  }

  /// 經典模式切換字體發光顏色
  void _cycleClassicFontStyle() {
    HapticFeedback.lightImpact();
    setState(() {
      _classicFontStyleIndex = (_classicFontStyleIndex + 1) % 3;
    });
  }

  /// 「換句好話」：排列組合產生新句（問候＋祝福＋結尾，依時段與範本主題）。
  void _nextQuote() {
    HapticFeedback.lightImpact();
    final tpl = _classicTemplates[_classicTemplateIndex];
    final shown = _getCurrentMainText();
    _quoteGen.markShown(shown); // 範本預設句也算「上一句」，不會連續重複
    setState(() {
      _customTemplateMainText = null;
      _currentQuote = _quoteGen.next(
        now: DateTime.now(),
        themeCategory: tpl.category,
        termName: _solarTerm,
      );
    });
  }

  String _getCurrentMainText() => _customTemplateMainText ?? _currentQuote.main;

  String _getCurrentSubText() => _currentQuote.sub;

  /// 擷取長輩圖畫布為 PNG
  Future<Uint8List?> _captureCardImage() async {
    try {
      // 保險：拖動虛線外框絕不進輸出圖（正常情況手指在螢幕上時按不到分享）
      if (_draggingItem != null) {
        setState(() => _draggingItem = null);
        await WidgetsBinding.instance.endOfFrame;
      }
      final boundary = _cardRepaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.8);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('❌ 截圖失敗: $e');
      return null;
    }
  }

  /// 一鍵分享至 LINE（支援圖片與附帶文字）
  Future<void> _shareToLine() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    HapticFeedback.heavyImpact();

    final pigTitle = _petState?.stage.title ?? '元氣小福豬';
    final vitality = _petState?.vitality ?? 95;
    final String mainText = _getCurrentMainText().replaceAll('\n', '，');
    final String subText = _getCurrentSubText();

    final shareText =
        '【$_customSenderName 的早安祝福】\n'
        '🌸 ${_now.month}月${_now.day}日 ($_lunarDateStr・$_solarTerm)\n'
        '📜 今日宜: ${_almanacInfo.yiList.take(3).join("、")}\n'
        '✨ $mainText\n'
        '💖 $subText\n'
        '🐷 元氣小豬【$pigTitle】活力$vitality% 伴大家吉祥！';

    try {
      final pngBytes = await _captureCardImage();

      if (pngBytes != null) {
        if (kIsWeb) {
          // ignore: deprecated_member_use
          await Share.shareXFiles(
            [
              XFile.fromData(
                pngBytes,
                mimeType: 'image/png',
                name: 'uban_greeting_${_now.millisecondsSinceEpoch}.png',
              ),
            ],
            text: shareText,
          );
        } else {
          final tempDir = await getTemporaryDirectory();
          final filePath =
              '${tempDir.path}/uban_greeting_${_now.millisecondsSinceEpoch}.png';
          final file = await io.File(filePath).create();
          await file.writeAsBytes(pngBytes);

          // ignore: deprecated_member_use
          await Share.shareXFiles(
            [XFile(file.path)],
            text: shareText,
          );
        }
      } else {
        final lineUrl = Uri.parse(
            'https://line.me/R/share?text=${Uri.encodeComponent(shareText)}');
        if (await canLaunchUrl(lineUrl)) {
          await launchUrl(lineUrl, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      debugPrint('分享異常: $e');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  /// 保存卡片至相簿
  Future<void> _saveToDevice() async {
    HapticFeedback.mediumImpact();
    setState(() => _isSharing = true);
    try {
      final pngBytes = await _captureCardImage();
      if (pngBytes != null && mounted) {
        final c = UbanColors.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: c.brandFill,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: c.onBrand, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '🎉 祝賀圖已準備好！隨時可以到 LINE 傳給親友群囉！',
                    style: GoogleFonts.notoSansTc(fontSize: 16.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  /// 編輯落款名稱
  void _editSenderName() {
    final c = UbanColors.of(context);
    final controller = TextEditingController(text: _customSenderName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          '✏️ 設定您的祝賀署名',
          style: GoogleFonts.notoSansTc(
              fontWeight: FontWeight.bold, fontSize: 20, color: c.text),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('這會印在長輩圖右下角的專屬標章上：',
                style: GoogleFonts.notoSansTc(color: c.text2, fontSize: 15)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 10,
              style: GoogleFonts.notoSansTc(
                  fontSize: 18, fontWeight: FontWeight.bold, color: c.text),
              decoration: InputDecoration(
                filled: true,
                fillColor: c.surface2,
                hintText: '例：萬發阿公、秀枝阿嬤',
                hintStyle: GoogleFonts.notoSansTc(color: c.text3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
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
                style: GoogleFonts.notoSansTc(fontSize: 16, color: c.text2)),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                setState(() => _customSenderName = newName);
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: c.brandFill,
              foregroundColor: c.onBrand,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text('確定', style: GoogleFonts.notoSansTc(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final bool embedded = widget.embedded;
    final Widget content = Column(
          mainAxisSize: embedded ? MainAxisSize.min : MainAxisSize.max,
          children: [
            // 頂部列：喜慶標題與朗讀
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: c.brandContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.wb_sunny_rounded, color: c.brandStrong, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '每日吉祥祝賀圖',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: c.text,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          '1:1 方形・結合節氣與小豬・一鍵傳 LINE',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: c.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 主內容視圖
            _expandUnlessEmbedded(
              Container(
                decoration: BoxDecoration(
                  color: c.bg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final bool isTablet =
                          !embedded && constraints.maxWidth >= 680;
                      if (isTablet) {
                        return _buildTabletLayout();
                      } else {
                        return _buildPhoneLayout();
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        );
    return ColoredBox(
      color: c.bg,
      child: embedded ? content : SafeArea(bottom: false, child: content),
    );
  }

  /// 嵌入模式不能用 Expanded（外層捲動容器給的是無限高度）。
  Widget _expandUnlessEmbedded(Widget child) =>
      widget.embedded ? child : Expanded(child: child);

  /// 📱 平板 / 寬螢幕雙欄佈局：左欄 1:1 卡片，右欄工具與一鍵傳 LINE，長輩不需滾動
  Widget _buildTabletLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左欄：卡片預覽區
        Expanded(
          flex: 5,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(24, 16, 16, elderNavClearance(context)),
            child: Column(
              children: [
                Center(
                  child: RepaintBoundary(
                    key: _cardRepaintKey,
                    child: _buildSquarePreviewCard(maxWidth: 480),
                  ),
                ),
                _buildLayoutHint(),
              ],
            ),
          ),
        ),
        // 右欄：控制面板、工具與分享按鈕（長輩不用滾動就能立刻看到按鈕）
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, 16, 24, elderNavClearance(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildClassicTemplateSelectorBar(),
                const SizedBox(height: 14),
                _buildClassicActionTools(),
                const SizedBox(height: 12),
                _buildPigToggle(),
                _buildResetLayoutButton(),
                const SizedBox(height: 18),
                _buildLineShareButton(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: UbanButton(
                        label: '保存到相簿',
                        icon: Icons.download_rounded,
                        variant: UbanButtonVariant.tonal,
                        onPressed: _saveToDevice,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: UbanButton(
                        label: '換我的名字',
                        icon: Icons.edit_note_rounded,
                        variant: UbanButtonVariant.tonal,
                        onPressed: _editSenderName,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 📱 手機直向單欄佈局
  Widget _buildPhoneLayout() {
    final Widget column = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            key: widget.tutorialKey,
            child: RepaintBoundary(
              key: _cardRepaintKey,
              child: _buildSquarePreviewCard(maxWidth: 400),
            ),
          ),
          _buildLayoutHint(),
          const SizedBox(height: 14),
          _buildClassicTemplateSelectorBar(),
          const SizedBox(height: 14),
          _buildClassicActionTools(),
          const SizedBox(height: 12),
          _buildPigToggle(),
          _buildResetLayoutButton(),
          const SizedBox(height: 16),
          _buildLineShareButton(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: UbanButton(
                  label: '保存到相簿',
                  icon: Icons.download_rounded,
                  variant: UbanButtonVariant.tonal,
                  onPressed: _saveToDevice,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: UbanButton(
                  label: '換我的名字',
                  icon: Icons.edit_note_rounded,
                  variant: UbanButtonVariant.tonal,
                  onPressed: _editSenderName,
                ),
              ),
            ],
          ),
        ],
      );
    // 嵌入模式：由外層（小豬分頁）捲動並負責導覽列留白，這裡只留 16 底距。
    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: column,
      );
    }
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 14, 16, elderNavClearance(context)),
      child: column,
    );
  }

  /// 1:1 方形預覽卡片
  Widget _buildSquarePreviewCard({double? maxWidth}) {
    final c = UbanColors.of(context);
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: maxWidth ?? 480),
      child: AspectRatio(
        aspectRatio: 1.0, // ★ 嚴格 1:1 方形，LINE 預覽最完美不被裁切
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(24),
            boxShadow: c.shadows.glass,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: _buildClassicSquareContent(),
          ),
        ),
      ),
    );
  }

  /// 經典圖文 1:1 方形內容（純粹大字！嚴格主體避讓排版）
  Widget _buildClassicSquareContent() {
    final tpl = _classicTemplates[_classicTemplateIndex];
    final String mainText = _getCurrentMainText();
    // 每次重建後量測文字範圍，替小豬挑不蓋到字的角落（只影響預設落點）
    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePigCorner());

    return Stack(
      key: _squareKey,
      children: [
        // 背景相片（1:1 滿版）
        Positioned.fill(
          child: Image.asset(
            tpl.bgAsset,
            fit: BoxFit.cover,
            cacheWidth: 1200, // 方形最大約 480dp，匯出 2.8 倍；超大原圖不整張解碼
            errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0F766E)),
          ),
        ),

        // ★ 輕柔透明遮罩（不破壞相片原色，僅微調字底對比）
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.10),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.22),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),

        // ★ 核心黃金律：純粹超大字！無任何日期、時間或多餘小字干擾
        // （可拖動；未自訂位置時落點與舊版 Align+Padding 相同）
        Positioned.fill(
          child: _buildDraggableItem(
            item: _GreetingDragItem.text,
            itemKey: _textItemKey,
            align: tpl.textAlign,
            padding: tpl.textPadding,
            child: _buildClassicTypography(mainText, tpl),
          ),
        ),

        // 小豬放在沒有大字的那一側：文字靠下 → 放右上，否則放右下
        _buildPigOverlay(_pigCorner ??
            (tpl.textAlign.y > 0 ? Alignment.topRight : Alignment.bottomRight)),
      ],
    );
  }

  /// 經典長輩圖招牌大字字效渲染（專注於超大字號、立體實心描邊 ＋ 招牌外發光）
  Widget _buildClassicTypography(String text, ClassicPhotoTemplate tpl) {
    Color textColor = tpl.defaultColor;
    Color strokeColor = Colors.white;
    List<Shadow> outerGlow = tpl.defaultShadows;

    if (_classicFontStyleIndex == 1) {
      textColor = const Color(0xFFFDE047);
      strokeColor = const Color(0xFF78350F);
      outerGlow = const [
        Shadow(color: Color(0xFF92400E), blurRadius: 16),
        Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(2, 2)),
      ];
    } else if (_classicFontStyleIndex == 2) {
      textColor = Colors.white;
      strokeColor = const Color(0xFF0369A1);
      outerGlow = const [
        Shadow(color: Color(0xFF38BDF8), blurRadius: 20),
        Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(2, 2)),
      ];
    }

    final lines = text.split('\n');

    CrossAxisAlignment columnAlign = CrossAxisAlignment.start;
    if (tpl.textAlign == Alignment.topRight || tpl.textAlign == Alignment.bottomRight) {
      columnAlign = CrossAxisAlignment.end;
    } else if (tpl.textAlign == Alignment.topCenter || tpl.textAlign == Alignment.bottomCenter || tpl.textAlign == Alignment.center) {
      columnAlign = CrossAxisAlignment.center;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: columnAlign,
      children: lines.map((line) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) return const SizedBox.shrink();

        // 根據字數精確計算超大字體尺寸：2字 72px、3~4字 58px、5~6字 46px
        double fontSize = 58.0;
        double letterSpacing = 2.0;
        double strokeWidth = 9.0;

        if (trimmed.length <= 2) {
          fontSize = 72.0;
          letterSpacing = 6.0;
          strokeWidth = 10.0;
        } else if (trimmed.length <= 4) {
          fontSize = 58.0;
          letterSpacing = 3.0;
          strokeWidth = 9.0;
        } else if (trimmed.length <= 6) {
          fontSize = 46.0;
          letterSpacing = 1.5;
          strokeWidth = 8.0;
        } else {
          fontSize = 38.0;
          letterSpacing = 1.0;
          strokeWidth = 7.0;
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: columnAlign == CrossAxisAlignment.end
                ? Alignment.centerRight
                : (columnAlign == CrossAxisAlignment.center ? Alignment.center : Alignment.centerLeft),
            child: Stack(
              children: [
                // 1. 底層：極粗圓潤實心描邊（打造長輩圖經典白邊字）
                Text(
                  trimmed,
                  style: GoogleFonts.notoSansTc(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                    letterSpacing: letterSpacing,
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = strokeWidth
                      ..strokeCap = StrokeCap.round
                      ..strokeJoin = StrokeJoin.round
                      ..color = strokeColor,
                  ),
                ),
                // 2. 表層：招牌寶藍/金黃/純白主色 ＋ 多重外散發光光暈
                Text(
                  trimmed,
                  style: GoogleFonts.notoSansTc(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                    letterSpacing: letterSpacing,
                    color: textColor,
                    shadows: outerGlow,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 經典模式下的「範本快捷導航列」（當前主題卡 ＋ 挑選圖庫大按鈕 ＋ 常用快捷）
  Widget _buildClassicTemplateSelectorBar() {
    final c = UbanColors.of(context);
    final currentTpl = _classicTemplates[_classicTemplateIndex];
    final quickPickIds = ['classic_lotus', 'classic_tea_table', 'classic_tea_mountain', 'classic_peony', 'festival_moon'];

    return UbanCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 頂部列：當前使用主題 ＋ 【挑選圖庫】大按鈕
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  currentTpl.bgAsset,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  cacheWidth: 150,
                  errorBuilder: (_, __, ___) =>
                      Container(width: 48, height: 48, color: c.brandContainer),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '目前範本',
                      style: ubanText(13, FontWeight.w600, c.text3),
                    ),
                    Text(
                      currentTpl.name,
                      style: ubanText(17, FontWeight.w900, c.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              UbanButton(
                label: '挑選圖庫',
                icon: Icons.photo_library_rounded,
                variant: UbanButtonVariant.tonal,
                expand: false,
                onPressed: _openGalleryModal,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, thickness: 1, color: c.line),
          const SizedBox(height: 10),

          // 常用快捷縮圖：長輩不用每次都進圖庫，直接點直接換！（比照設計稿 .thumbs 選中外框）
          Row(
            children: [
              Text(
                '常用',
                style: ubanText(14, FontWeight.w700, c.text3),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: quickPickIds.map((id) {
                      final idx = _classicTemplates.indexWhere((t) => t.id == id);
                      if (idx == -1) return const SizedBox.shrink();
                      final t = _classicTemplates[idx];
                      final isSelected = _classicTemplateIndex == idx;

                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: PressableScale(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _applyTemplate(idx);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isSelected ? c.brand : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.asset(
                                t.bgAsset,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                cacheWidth: 180,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 60,
                                  height: 60,
                                  color: c.brandContainer,
                                  child: Icon(t.icon, size: 22, color: c.brandStrong),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 依「文字實際範圍」替小豬挑預設角落：文字在上半 → 優先放下方（右、左），
  /// 文字在下半 → 優先放上方；取第一個完全不重疊的角落，都重疊就取重疊面積最小者。
  /// 使用者拖過小豬（`_pigFrac` 非 null）時不動。
  void _updatePigCorner() {
    if (!mounted || !_showPig || _pigFrac != null) return;
    final sq = _squareKey.currentContext?.findRenderObject() as RenderBox?;
    final tb = _textItemKey.currentContext?.findRenderObject() as RenderBox?;
    if (sq == null || tb == null || !sq.hasSize || !tb.hasSize) return;
    final side = sq.size.width;
    if (side <= 0) return;
    final textRect =
        (tb.localToGlobal(Offset.zero, ancestor: sq) & tb.size).inflate(4);
    final pb = _pigItemKey.currentContext?.findRenderObject() as RenderBox?;
    final w = side * 0.22;
    final h = (pb != null && pb.hasSize && pb.size.height > 0)
        ? pb.size.height / _pigScale
        : w;
    final pad = side * 0.04;
    final textOnTop = textRect.center.dy < side / 2;
    final order = textOnTop
        ? [Alignment.bottomRight, Alignment.bottomLeft, Alignment.topRight, Alignment.topLeft]
        : [Alignment.topRight, Alignment.topLeft, Alignment.bottomRight, Alignment.bottomLeft];
    Rect rectOf(Alignment a, double k) {
      final pw = w * k, ph = h * k;
      final left = a.x > 0 ? side - pad - pw : pad;
      final top = a.y > 0 ? side - pad - ph : pad;
      return Rect.fromLTWH(left, top, pw, ph);
    }

    double overlap(Rect r) {
      final i = r.intersect(textRect);
      return (i.width <= 0 || i.height <= 0) ? 0.0 : i.width * i.height;
    }

    // 先試「正常大小」的四個角，都不行再逐步縮小；最後取重疊最小者
    Alignment best = order.first;
    double bestScale = 1.0;
    double bestArea = double.infinity;
    for (final k in const [1.0, 0.85, 0.7, 0.6, 0.5]) {
      for (final a in order) {
        final area = overlap(rectOf(a, k));
        if (area < bestArea) {
          bestArea = area;
          best = a;
          bestScale = k;
        }
      }
      if (bestArea == 0) break;
    }
    if (best != _pigCorner || bestScale != _pigScale) {
      setState(() {
        _pigCorner = best;
        _pigScale = bestScale;
      });
    }
  }

  /// 套用範本：換背景、顯示該範本預設文字、載入該範本記住的拖動位置。
  void _applyTemplate(int idx) {
    if (idx < 0 || idx >= _classicTemplates.length) return;
    final t = _classicTemplates[idx];
    setState(() {
      _classicTemplateIndex = idx;
      _customTemplateMainText = t.defaultMain;
      _pigCorner = null;
      _pigScale = 1.0;
    });
    _quoteGen.markShown(t.defaultMain);
    unawaited(_loadLayout());
  }

  /// 📖 精選長輩圖庫全覽面板：依分類分組（各組有 zh-TW 標題），方形縮圖網格。
  void _openGalleryModal() {
    HapticFeedback.mediumImpact();
    String selectedCategory = 'all';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final uc = UbanColors.of(ctx);
            final sections = groupGalleryByCategory<ClassicPhotoTemplate>(
                _classicTemplates, (t) => t.category);
            final visibleSections = selectedCategory == 'all'
                ? sections
                : sections.where((s) => s.categoryId == selectedCategory).toList();

            final screenHeight = MediaQuery.of(context).size.height;
            final isTablet = MediaQuery.of(context).size.width >= 680;

            return Container(
              key: const ValueKey('greeting_gallery_sheet'),
              height: screenHeight * 0.88,
              decoration: BoxDecoration(
                color: uc.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: uc.shadows.glass,
              ),
              child: Column(
                children: [
                  // 頂部抓手與標題欄
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: uc.brandContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.photo_library_rounded, color: uc.brandStrong, size: 24),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '精選長輩圖庫 (${_classicTemplates.length} 款)',
                                style: ubanText(20, FontWeight.w900, uc.text),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '點選任一範本立即套用',
                                style: ubanText(13, FontWeight.w600, uc.text2),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetCtx),
                          icon: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: uc.surface2,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.close_rounded, size: 20, color: uc.text2),
                          ),
                          tooltip: '關閉返回',
                        ),
                      ],
                    ),
                  ),

                  // 分類篩選列（全部 ＋ 實際有範本的分類；字大、圓角舒適、易點選）
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final cat in [
                          ('all', '全部'),
                          for (final s in sections) (s.categoryId, s.label),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              key: ValueKey('greeting_gallery_chip_${cat.$1}'),
                              label: Text(
                                cat.$2,
                                style: ubanText(
                                  15,
                                  selectedCategory == cat.$1 ? FontWeight.w900 : FontWeight.w700,
                                  selectedCategory == cat.$1 ? uc.onBrand : uc.text2,
                                ),
                              ),
                              selected: selectedCategory == cat.$1,
                              selectedColor: uc.brandFill,
                              backgroundColor: uc.surface2,
                              side: BorderSide(
                                color: selectedCategory == cat.$1 ? uc.brandFill : uc.line,
                                width: 1.2,
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              onSelected: (val) {
                                if (val) {
                                  HapticFeedback.selectionClick();
                                  setModalState(() => selectedCategory = cat.$1);
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Divider(height: 1, thickness: 1, color: uc.line),

                  // 依分類分組的方形縮圖網格（lazy sliver，約 40 張也不卡）
                  Expanded(
                    child: CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        for (final sec in visibleSections) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(18, 16, 16, 8),
                              child: Text(
                                '${sec.label}（${sec.items.length}）',
                                key: ValueKey('greeting_gallery_header_${sec.categoryId}'),
                                style: ubanText(18, FontWeight.w900, uc.text),
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverGrid(
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: isTablet ? 4 : 3,
                                childAspectRatio: 0.72,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (c, i) => _buildGalleryTile(
                                    sec.items[i], uc, sheetCtx),
                                childCount: sec.items.length,
                              ),
                            ),
                          ),
                        ],
                        const SliverToBoxAdapter(child: SizedBox(height: 28)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 圖庫的一張方形縮圖（縮圖解碼寬度限制 300px，約 40 張也不吃記憶體）。
  Widget _buildGalleryTile(
      ClassicPhotoTemplate tpl, UbanColors uc, BuildContext sheetCtx) {
    final globalIdx = _classicTemplates.indexOf(tpl);
    final isSelected = _classicTemplateIndex == globalIdx;
    return GestureDetector(
      key: ValueKey('greeting_gallery_tile_${tpl.id}'),
      onTap: () {
        HapticFeedback.heavyImpact();
        _applyTemplate(globalIdx);
        Navigator.pop(sheetCtx);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: uc.brandFill,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Text(
              '已套用【${tpl.name}】',
              style: GoogleFonts.notoSansTc(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? uc.brand : uc.line,
                  width: isSelected ? 3.0 : 1.2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      tpl.bgAsset,
                      fit: BoxFit.cover,
                      cacheWidth: 300,
                      errorBuilder: (_, __, ___) => Container(
                        color: uc.brandContainer,
                        child: Icon(tpl.icon, size: 28, color: uc.brandStrong),
                      ),
                    ),
                    if (tpl.isHolidaySpecial || tpl.isSolarTermSpecial)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: uc.danger,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tpl.isHolidaySpecial ? '節慶' : '節氣',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    if (isSelected)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(color: uc.brand, shape: BoxShape.circle),
                          child: Icon(Icons.check_rounded, color: uc.onBrand, size: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Text(
              tpl.name,
              style: ubanText(13, FontWeight.w800, isSelected ? uc.brandStrong : uc.text),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// 經典模式操作工具列（換句好話 ＋ 換字體款式）
  Widget _buildClassicActionTools() {
    return Row(
      children: [
        // 換金句按鈕
        Expanded(
          flex: 3,
          child: UbanButton(
            label: '換句好話',
            icon: Icons.auto_awesome_rounded,
            variant: UbanButtonVariant.tonal,
            onPressed: _nextQuote,
          ),
        ),
        const SizedBox(width: 10),
        // 換字體款式按鈕
        Expanded(
          flex: 2,
          child: UbanButton(
            label: '換字體款式',
            icon: Icons.format_color_text_rounded,
            variant: UbanButtonVariant.outline,
            onPressed: _cycleClassicFontStyle,
          ),
        ),
      ],
    );
  }

  /// 一鍵傳給 LINE 好友之特大主按鈕（設計稿 `.btn line xl`）
  Widget _buildLineShareButton() {
    return UbanButton(
      label: _isSharing ? '正在準備祝賀圖…' : '傳給 LINE 好友 / 群組',
      icon: _isSharing ? null : Icons.send_rounded,
      variant: UbanButtonVariant.line,
      size: UbanButtonSize.xl,
      loading: _isSharing,
      onPressed: _isSharing ? null : _shareToLine,
    );
  }
}

/// 祝賀圖上可拖動的兩個元素。
enum _GreetingDragItem { pig, text }

/// 版面代理：沒有自訂位置時，落點與 `Align(alignment) + Padding(padding)` 完全相同；
/// 有自訂位置時以「方形邊長的比例」定位，並夾限讓元素整個留在圖內
/// （換句好話／換字體導致尺寸改變時會自動重新夾限）。
class _GreetingItemLayout extends SingleChildLayoutDelegate {
  final Offset? frac;
  final Alignment align;
  final EdgeInsets padding;

  const _GreetingItemLayout({
    required this.frac,
    required this.align,
    required this.padding,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(Size(
      math.max(0.0, constraints.maxWidth - padding.horizontal),
      math.max(0.0, constraints.maxHeight - padding.vertical),
    ));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final f = frac;
    if (f == null) {
      final inner = Size(
        math.max(0.0, size.width - padding.horizontal),
        math.max(0.0, size.height - padding.vertical),
      );
      return align.inscribe(childSize, Offset.zero & inner).topLeft +
          padding.topLeft;
    }
    return Offset(
      (f.dx * size.width).clamp(0.0, math.max(0.0, size.width - childSize.width)),
      (f.dy * size.height)
          .clamp(0.0, math.max(0.0, size.height - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(covariant _GreetingItemLayout old) =>
      old.frac != frac || old.align != align || old.padding != padding;
}

/// 「碰到就算」的單指拖動辨識器：pointer down 當下就宣告勝出，
/// 因此會贏過祖先 SingleChildScrollView 的垂直拖動（其門檻要先位移 18px）。
class _ImmediateDragRecognizer extends OneSequenceGestureRecognizer {
  void Function(Offset global)? onStart;
  void Function(Offset global)? onUpdate;
  VoidCallback? onEnd;
  int? _pointer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer != null) return; // 只處理第一根手指
    _pointer = event.pointer;
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    onStart?.call(event.position);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      onUpdate?.call(event.position);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _finish(event.pointer);
    }
  }

  void _finish(int pointer) {
    if (_pointer == null) return;
    _pointer = null;
    stopTrackingPointer(pointer);
    onEnd?.call();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'greeting immediate drag';
}

/// 拖動中的白色虛線圓角外框（只在拖動時才掛上，輸出圖不會有）。
class _DashedOutlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).inflate(4),
      const Radius.circular(12),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white;
    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = const Color(0x66000000);
    for (final m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        final seg = m.extractPath(d, math.min(d + 10, m.length));
        canvas.drawPath(seg, shadow);
        canvas.drawPath(seg, paint);
        d += 17;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
