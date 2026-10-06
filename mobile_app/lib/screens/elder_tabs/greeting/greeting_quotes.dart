import 'dart:math' as math;

/// 每日精選長輩金句（人工撰寫的整句，早安情境用）。
class GoldenQuote {
  final String mainTitle;
  final String subTitle;
  final String category;

  const GoldenQuote({
    required this.mainTitle,
    required this.subTitle,
    required this.category,
  });
}

/// 一次產生的祝福：[main] 是圖上大字（以換行分行），[sub] 只用在 LINE 分享文字。
class GreetingQuote {
  final String main;
  final String sub;
  const GreetingQuote(this.main, this.sub);
}

enum GreetingTimeBand { morning, afternoon, evening }

/// 「換句好話」的排列組合產生器。
///
/// 圖上大字 = 問候語（依時段，通用開場）＋ 主祝福（4 字）＋ 結尾語。
/// 有主題的範本（蓮花、錦鯉、日出、竹林…）主祝福與結尾一律取自該主題的詞池，
/// 所以每按一次都與圖片內容相關；沒有主題才用通用詞池。
/// 每個欄位都有字數上限（圖是 1:1 方形、一行過長會被縮小），見 [maxGreetingChars] 等常數，
/// 單元測試會逐一檢查。連續兩次不會產生同一句。
class GreetingQuoteGenerator {
  GreetingQuoteGenerator({math.Random? random})
      : _random = random ?? math.Random();

  final math.Random _random;
  String? _lastMain;

  // ── 字數上限（每欄一個規則）──
  static const int maxGreetingChars = 5;
  static const int maxBlessingChars = 4;
  static const int maxClosingChars = 8;
  static const int maxThemeChars = 9; // 含一個空格的對句「福如東海 壽比南山」
  static const int maxLines = 3;

  static GreetingTimeBand bandOf(DateTime t) {
    final h = t.hour;
    if (h >= 5 && h < 11) return GreetingTimeBand.morning;
    if (h >= 11 && h < 17) return GreetingTimeBand.afternoon;
    return GreetingTimeBand.evening;
  }

  // ── 欄位一：問候語（依時段，每時段 16 句）──
  static const Map<GreetingTimeBand, List<String>> greetings = {
    GreetingTimeBand.morning: [
      '早安', '早安您好', '早安吉祥', '早安平安', '早安喜樂', '早安順心',
      '早安安康', '早安如意', '晨光問候', '清晨問候', '早安好運', '早安好心情',
      '早安福氣', '早安健康', '早安感謝', '早安幸福',
    ],
    GreetingTimeBand.afternoon: [
      '午安', '午安您好', '午安吉祥', '午安平安', '午安喜樂', '午安順心',
      '午安安康', '午安如意', '午後問候', '午安好運', '午安福氣', '午安健康',
      '午安幸福', '午安愉快', '午安感謝', '午安好心情',
    ],
    GreetingTimeBand.evening: [
      '晚安', '晚安您好', '晚安吉祥', '晚安平安', '晚安喜樂', '晚安順心',
      '晚安安康', '晚安如意', '夜晚問候', '晚安好運', '晚安福氣', '晚安健康',
      '晚安幸福', '晚安好夢', '晚安感謝', '晚安甜夢',
    ],
  };

  // ── 欄位二：主祝福（4 字，26 句）──
  static const List<String> blessings = [
    '身體健康', '萬事如意', '福氣滿滿', '心想事成', '天天開心', '闔家平安',
    '平安喜樂', '笑口常開', '吉祥如意', '福壽安康', '家庭和樂', '健康長壽',
    '好運連連', '喜樂安康', '心寬福至', '順心順意', '事事順利', '平安是福',
    '知足常樂', '精神飽滿', '幸福美滿', '笑容滿面', '一切順心', '福祿雙全',
    '安康自在', '歲歲平安',
  ];

  // ── 欄位三：結尾語（≤8 字，18 句；刻意不含任何主祝福的 4 字詞，避免唸起來重複）──
  static const List<String> closings = [
    '祝您一天順利', '好運跟著您', '祝您天天好心情', '願您每天都舒心',
    '健康平安相伴', '福氣常伴左右', '祝您諸事順遂', '開心過好每一天',
    '喜樂圍繞著您', '心情好身體好', '祝您順心自在', '願您吉祥平順',
    '一路平安順心', '日日歡喜自在', '祝您平安順遂', '溫暖陪伴您每天',
    '願您笑看每一天', '願您天天安好',
  ];

  // ── 主題主祝福（每分類 ≥15 句，剛好 4 字；key 與圖庫分類 id 相同）──
  // 有主題的範本，圖上每一句的主線都從這裡抽，保證句子與圖片內容相關。
  static const Map<String, List<String>> themedMains = {
    'lotus': [
      '清淨自在', '蓮開富貴', '心如蓮淨', '出淤不染', '荷風送爽', '荷香滿塘',
      '清香滿懷', '蓮蓮有福', '一品清蓮', '清雅安然', '靜心自在', '心曠神怡',
      '淡雅清幽', '蓮心如意', '清風徐來', '心靜自然',
    ],
    'koi': [
      '年年有餘', '鯉躍龍門', '魚水和樂', '吉慶有餘', '錦鯉納福', '魚躍福來',
      '鴻運當頭', '魚游自在', '富貴有餘', '財源廣進', '福滿池塘', '好運躍來',
      '前程似錦', '步步高升', '祥魚獻瑞', '悠游自得',
    ],
    'sunrise': [
      '旭日東昇', '朝氣蓬勃', '光明在前', '日日向陽', '朝陽燦爛', '晨光美好',
      '曙光乍現', '前程光明', '陽光滿懷', '紅日高照', '精神煥發', '活力滿滿',
      '嶄新一天', '希望滿滿', '晴空萬里', '溫暖陽光',
    ],
    'bamboo': [
      '竹報平安', '節節高升', '虛心有節', '清風竹影', '青竹常翠', '步步高升',
      '氣節高雅', '竹林清幽', '剛柔並濟', '四季常青', '平安喜樂', '勁節長青',
      '翠竹迎風', '君子之風', '歲歲平安', '高風亮節',
    ],
    'mountain': [
      '福如東海', '壽比南山', '穩如泰山', '雲開見日', '青山常在', '山高水長',
      '雲淡風輕', '氣象萬千', '登高望遠', '步步登高', '松鶴延年', '福壽綿長',
      '山明水秀', '心胸開闊', '平步青雲', '仁者樂山',
    ],
    'tea': [
      '茶香滿園', '清心品茗', '一壺好茶', '甘醇回味', '茶香四溢', '品茗閒適',
      '清茶一盞', '以茶會友', '溫潤甘甜', '回甘無窮', '悠然品茶', '茶韻悠長',
      '熱茶暖心', '閒適自在', '茶敘時光', '清香撲鼻',
    ],
    'flower': [
      '花開富貴', '梅開五福', '傲雪迎春', '花好月圓', '繁花似錦', '春暖花開',
      '花團錦簇', '國色天香', '滿園春色', '芬芳滿園', '錦上添花', '笑顏如花',
      '百花盛開', '花香宜人', '生機盎然', '吉祥如意',
    ],
    'lake': [
      '心靜如水', '湖光山色', '悠然自得', '波平如鏡', '風平浪靜', '碧波萬頃',
      '水天一色', '清澈見底', '寧靜致遠', '柔波蕩漾', '水清心靜', '靜水流深',
      '山水相依', '湖面如鏡', '悠遊自在', '心平氣和',
    ],
    'festival': [
      '佳節愉快', '闔家團圓', '喜氣洋洋', '歡喜過節', '團圓美滿', '吉慶團圓',
      '佳節安康', '福滿人間', '笑語滿堂', '其樂融融', '張燈結綵', '喜迎佳節',
      '福氣臨門', '歡聚一堂', '好事成雙', '萬家歡慶',
    ],
    'solar_term': [
      '順應時節', '節氣平安', '天時順遂', '保暖保健', '起居有常', '飲食清淡',
      '順時養生', '四季平安', '身心舒暢', '神清氣爽', '注意保暖', '多喝溫水',
      '適度運動', '作息規律', '氣候宜人', '冷暖自知',
    ],
    'scenery': [
      '山清水秀', '風和日麗', '景色宜人', '四季如畫', '春暖秋涼', '天朗氣清',
      '青山綠水', '雲淡天高', '山川秀麗', '晴空萬里', '好景常在', '心曠神怡',
      '自然美好', '美景相伴', '清新自在', '悠然閒適',
    ],
  };

  // ── 主題結尾語（每分類 ≥10 句，≤8 字，同樣緊扣圖片主題）──
  static const Map<String, List<String>> themedClosings = {
    'lotus': [
      '願您心清自在', '如蓮花般安然', '荷香伴您一天', '清清爽爽每一天',
      '願您身心清淨', '日子清雅如荷', '靜好歲月常在', '清風荷香相伴',
      '願您淡然自在', '心如蓮花安穩',
    ],
    'koi': [
      '好運像錦鯉游來', '願您年年有福', '福氣滿池來', '願您日日有餘',
      '願好運游向您', '吉祥魚兒相伴', '祝您鯉躍高升', '願您喜事連連',
      '祝您有餘有福', '願您歲歲如意',
    ],
    'sunrise': [
      '願您天天朝氣十足', '迎著朝陽好心情', '陽光灑滿您的心', '新的一天新希望',
      '願您一天活力十足', '笑迎每個晨光', '祝您日日光明順遂', '好心情從朝陽開始',
      '願您步步迎光明', '暖陽相伴好運來',
    ],
    'bamboo': [
      '願您如竹常青', '竹影清風相伴', '願您平安挺拔', '祝您生活清雅',
      '願您堅韌又從容', '願您一年四季安康', '翠竹伴您平安', '願您身心安穩',
      '願您日日清風', '願您步履穩健',
    ],
    'mountain': [
      '願您福壽綿延', '願您身體硬朗如山', '雲海相伴好心情', '祝您腳步穩健',
      '願您心境高遠', '祝您健步如飛', '山靈水秀伴您', '祝您平安康泰',
      '高山雲海相伴', '願您一天開闊順心',
    ],
    'tea': [
      '喝杯熱茶暖暖身', '願您日子回甘', '願您心情如茶香', '慢慢品茶慢慢過',
      '一杯清茶好心情', '願您生活甘甜如茶', '清茶一杯伴您', '祝您茶香人安康',
      '祝您天天有好茶', '與好茶共度好時光',
    ],
    'flower': [
      '願您日子如花綻放', '花香陪伴每一天', '祝您笑容像花朵', '願您生活多彩多姿',
      '願您心情花開', '祝您福氣滿枝頭', '花兒開處皆歡喜', '祝您春風滿面',
      '願您常有好心情', '祝您富貴平安',
    ],
    'lake': [
      '願您心如湖水安', '湖光相伴好心情', '願您日子平順安穩', '願您風浪不驚',
      '清風湖水伴您', '願您身心輕盈自在', '祝您悠閒又自在', '願您平靜喜樂',
      '願您安然度每天', '願您常保平常心',
    ],
    'festival': [
      '願您佳節平順開心', '祝您與家人歡聚', '願您節日暖心溫馨', '祝您佳節心情好',
      '願您全家都平安', '祝您佳節多添福氣', '願您喜氣伴一整年', '祝您節日吃好睡好',
      '願您節日溫暖愉快', '祝您節日笑呵呵',
    ],
    'solar_term': [
      '天氣變化多保重', '記得添衣保暖', '願您身體硬朗安康', '祝您一路順暢',
      '早晚溫差要留意', '願您順著時節安康', '喝點溫開水多休息', '睡得安穩吃得香',
      '出門散步慢慢走', '願您四季都舒心',
    ],
    'scenery': [
      '願您天天好風景', '美景當前好心情', '祝您日日好心境', '願您看見好風景',
      '大自然伴您平安', '願您出門有好天氣', '祝您身心都舒暢', '願您賞景好心情',
      '願您四季都美好', '祝您步步有美景',
    ],
  };

  /// 沒有主題時的「純排列組合」總數（問候 × 主祝福 × 結尾）。
  static int plainComboCount(GreetingTimeBand band) =>
      greetings[band]!.length * blessings.length * closings.length;

  static String compose(String greeting, String middle, String closing) =>
      '$greeting\n$middle\n$closing';

  /// 新範本的預設句：依 [seed]（範本 id）穩定地選出「問候＋主題主祝福＋主題結尾」，
  /// 同一範本每次開啟看到同一句，不同範本各不相同。
  static String themedDefault(String category, String seed, {DateTime? now}) {
    final h = seed.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7fffffff);
    final gs = greetings[bandOf(now ?? DateTime.now())]!;
    final mains = themedMains[category] ?? blessings;
    final ends = themedClosings[category] ?? closings;
    return compose(
      gs[h % gs.length],
      mains[(h ~/ 3) % mains.length],
      ends[(h ~/ 5) % ends.length],
    );
  }

  /// 某分類在某時段的排列組合數（問候 × 主題主祝福 × 主題結尾）。
  static int themedComboCount(String category, GreetingTimeBand band) =>
      greetings[band]!.length *
      themedMains[category]!.length *
      themedClosings[category]!.length;

  /// 列舉某時段所有純排列組合（測試用，不在 UI 路徑上呼叫）。
  static Iterable<String> allPlainCombos(GreetingTimeBand band) sync* {
    for (final g in greetings[band]!) {
      for (final b in blessings) {
        for (final c in closings) {
          yield compose(g, b, c);
        }
      }
    }
  }

  /// 下一句。[themeCategory] 傳目前範本的分類：有對應主題池時，主祝福與結尾
  /// **一律**取自該分類（每一次都與圖片內容相關）；沒有分類才用通用祝福。
  /// 時令節氣範本可傳 [termName]（例：白露），結尾有一半機率改成「白露時節保重」。
  GreetingQuote next({DateTime? now, String? themeCategory, String? termName}) {
    final band = bandOf(now ?? DateTime.now());
    late GreetingQuote q;
    for (var i = 0; i < 12; i++) {
      q = _pick(band, themeCategory, termName);
      if (q.main != _lastMain) break;
    }
    _lastMain = q.main;
    return q;
  }

  /// 讓外部（換範本時顯示的預設句）也納入「不連續重複」的判斷。
  void markShown(String main) => _lastMain = main;

  GreetingQuote _pick(
      GreetingTimeBand band, String? themeCategory, String? termName) {
    final sub = _oneOf(curated).subTitle; // LINE 分享用的副標題維持通用
    final g = _oneOf(greetings[band]!);
    final mains = themeCategory == null ? null : themedMains[themeCategory];
    final ends = themeCategory == null ? null : themedClosings[themeCategory];
    if (mains == null || ends == null) {
      return GreetingQuote(
          compose(g, _oneOf(blessings), _oneOf(closings)), sub);
    }
    var end = _oneOf(ends);
    if (themeCategory == 'solar_term' &&
        termName != null &&
        termName.isNotEmpty &&
        termName.length <= 3 &&
        _random.nextBool()) {
      end = '$termName時節保重';
    }
    return GreetingQuote(compose(g, _oneOf(mains), end), sub);
  }

  T _oneOf<T>(List<T> l) => l[_random.nextInt(l.length)];

  // ── 人工整句（原 50 句；只用於 LINE 分享文字的副標題）──
  static const List<GoldenQuote> curated = [
    // 🌸 一、早安感謝 (10 句)
    GoldenQuote(category: '早安感謝', mainTitle: '早安\n感謝\n祝您一天順利', subTitle: '心寬福就來，天天好心境，身心安康萬事興。'),
    GoldenQuote(category: '早安感謝', mainTitle: '晨光送暖\n祝好友事事順心', subTitle: '一縷清風送吉祥，願今天所有的美好都與您相伴。'),
    GoldenQuote(category: '早安感謝', mainTitle: '早安吉祥\n微笑迎接新的一天', subTitle: '開心度過每一天，心寬病不來，平安是真福。'),
    GoldenQuote(category: '早安感謝', mainTitle: '清晨問候\n願您喜樂安康', subTitle: '千言萬語道一聲早，深深祝福朋友身體健步如飛！'),
    GoldenQuote(category: '早安感謝', mainTitle: '早安如意\n心中有愛日日晴', subTitle: '世間萬物皆美好，只要心境寬廣，天天都是艷陽天。'),
    GoldenQuote(category: '早安感謝', mainTitle: '朝陽迎福\n祝您精神百倍', subTitle: '開啟朝氣滿滿的一天，走走路、喝口茶，逍遙自在。'),
    GoldenQuote(category: '早安感謝', mainTitle: '早安道好\n天天平安天天好', subTitle: '問候隨晨風而來，願好友健康快樂、笑口常開。'),
    GoldenQuote(category: '早安感謝', mainTitle: '晨曦微風\n送上滿滿的祝福', subTitle: '走過歲月珍惜緣分，祝願老友生活甜甜、幸福綿綿。'),
    GoldenQuote(category: '早安感謝', mainTitle: '早晨好心情\n幸福快樂隨身行', subTitle: '感謝生命中的每一位好友，願大家平安喜樂每一天。'),
    GoldenQuote(category: '早安感謝', mainTitle: '開門見喜\n祝大家順風順水', subTitle: '早起深呼吸，精神好、身體好，好運自然跟著到。'),

    // 🌿 二、平安健康 (10 句)
    GoldenQuote(category: '平安健康', mainTitle: '知足常樂\n平安就是福', subTitle: '人生最大的財富是健康，最好的境界是平安。'),
    GoldenQuote(category: '平安健康', mainTitle: '身心安康\n無病無痛樂逍遙', subTitle: '粗茶淡飯皆滋味，健步如飛身骨強，祝好友長壽安康。'),
    GoldenQuote(category: '平安健康', mainTitle: '走路強身\n日日健步活力旺', subTitle: '每天動一動、心情放輕鬆，小豬伴阿公天天散步去！'),
    GoldenQuote(category: '平安健康', mainTitle: '健康第一\n平安才是真富貴', subTitle: '不攀比、不焦慮，身心舒暢、兒女爭氣便是好福氣。'),
    GoldenQuote(category: '平安健康', mainTitle: '心寬壽長\n笑看人生萬事安', subTitle: '萬事隨緣心自在，少生悶氣多歡笑，松柏長青壽綿延。'),
    GoldenQuote(category: '平安健康', mainTitle: '飲水暖胃\n保重身體迎朝陽', subTitle: '清晨一杯溫開水，滋潤身心氣色好，祝您活力四射。'),
    GoldenQuote(category: '平安健康', mainTitle: '福壽雙全\n松柏長青樂陶陶', subTitle: '願您福如東海浩瀚長，壽比南山不老松！'),
    GoldenQuote(category: '平安健康', mainTitle: '神清氣爽\n安泰祥和福氣來', subTitle: '心平氣和百病消，早起活動手腳健，祝您元氣滿分。'),
    GoldenQuote(category: '平安健康', mainTitle: '歲月靜好\n身體硬朗最快活', subTitle: '粗茶淡飯養天年，逍遙自在心無憂，早安吉祥。'),
    GoldenQuote(category: '平安健康', mainTitle: '福星高照\n長命百歲喜盈門', subTitle: '家有老者如獲至寶，願長輩身強體健、闔府安泰。'),

    // 🍵 三、知足禪意 (10 句)
    GoldenQuote(category: '知足禪意', mainTitle: '心寬福就來\n天天順心如意', subTitle: '心有多寬，福有多深。凡事看開，天地自然寬闊。'),
    GoldenQuote(category: '知足禪意', mainTitle: '一壺清茶\n淡看世事皆美好', subTitle: '品一口清茶，留一片心香，願好友天天順風順水。'),
    GoldenQuote(category: '知足禪意', mainTitle: '日日是好日\n時時好心情', subTitle: '不為往事憂，只為餘生笑，每一天都是最好的安排。'),
    GoldenQuote(category: '知足禪意', mainTitle: '隨緣自得\n心中無事勝神仙', subTitle: '春有百花秋有月，若無閒事掛心頭，便是人間好時節。'),
    GoldenQuote(category: '知足禪意', mainTitle: '看淡得失\n平安知足即是福', subTitle: '少計較多感恩，珍惜眼前擁有的，幸福就在身邊。'),
    GoldenQuote(category: '知足禪意', mainTitle: '厚德載物\n善心常在福自生', subTitle: '善念如春風，福報自然來，祝好友天天心花怒放。'),
    GoldenQuote(category: '知足禪意', mainTitle: '花開見佛\n心靜處處有清香', subTitle: '心清神自寧，淡泊名與利，平安吉祥常相伴。'),
    GoldenQuote(category: '知足禪意', mainTitle: '放下執念\n天地寬廣任逍遙', subTitle: '人生是一場修行，看透得失心自在，祝您喜樂安詳。'),
    GoldenQuote(category: '知足禪意', mainTitle: '珍惜當下\n平凡日子最溫暖', subTitle: '每天能吃能走能歡笑，就是人間最美好的幸福。'),
    GoldenQuote(category: '知足禪意', mainTitle: '心善語柔\n廣結善緣納千祥', subTitle: '一言一句皆是福，和顏悅色迎親友，早安大吉。'),

    // 🍂 四、時令節氣 (10 句)
    GoldenQuote(category: '時令節氣', mainTitle: '時令添衣\n順應天時保安康', subTitle: '節氣轉換早晚涼，記得多添薄衣裳，溫水暖胃保平安。'),
    GoldenQuote(category: '時令節氣', mainTitle: '秋意漸濃\n早晚溫差多保重', subTitle: '微涼秋風送清爽，出門散步多小心，祝好友順遂。'),
    GoldenQuote(category: '時令節氣', mainTitle: '立秋納福\n五穀豐收身心泰', subTitle: '秋水長天共一色，祝好友秋日收穫滿滿、吉祥如意。'),
    GoldenQuote(category: '時令節氣', mainTitle: '白露凝霜\n莫貪清涼多添衣', subTitle: '節氣提醒您多保重，溫潤飲食少寒涼，早安吉祥。'),
    GoldenQuote(category: '時令節氣', mainTitle: '寒露添暖\n願您溫暖過秋冬', subTitle: '添衣加被保身體，暖心問候傳老友，順心安康。'),
    GoldenQuote(category: '時令節氣', mainTitle: '霜降平安\n防寒保暖心自寬', subTitle: '秋盡冬來迎新季，祝好友闔家幸福、四季平安。'),
    GoldenQuote(category: '時令節氣', mainTitle: '冬至安康\n紅白湯圓添歲福', subTitle: '一碗甜湯圓，全家大團圓，祝您福氣滿滿多喜樂。'),
    GoldenQuote(category: '時令節氣', mainTitle: '春暖花開\n萬物復甦迎好運', subTitle: '春風送暖百花開，新的一季氣象新，萬事勝意。'),
    GoldenQuote(category: '時令節氣', mainTitle: '清明安泰\n春光明媚順心意', subTitle: '春雨綿綿潤萬物，思親念故享清福，早安安好。'),
    GoldenQuote(category: '時令節氣', mainTitle: '歲時輪轉\n節氣平安伴身邊', subTitle: '春去秋來四季好，歲月沉澱情意真，祝好友長壽康泰。'),

    // 👨‍👩‍👧‍👦 五、家庭親情 (10 句)
    GoldenQuote(category: '家庭親情', mainTitle: '一家和睦\n富貴吉祥萬事成', subTitle: '家和萬事興，心中常存感恩心，祝全家老少平安。'),
    GoldenQuote(category: '家庭親情', mainTitle: '兒孫滿堂\n福祿綿延天賜祥', subTitle: '晚輩孝順、長輩安泰，一家其樂融融是最大福氣。'),
    GoldenQuote(category: '家庭親情', mainTitle: '感謝有您\n真摯友情長相隨', subTitle: '相遇是緣分，相知是幸福，祝老同學、老朋友天天快樂！'),
    GoldenQuote(category: '家庭親情', mainTitle: '走過歲月\n珍惜每一位老友', subTitle: '常聯繫心不遠，一杯茶話當年，願彼此長命百歲。'),
    GoldenQuote(category: '家庭親情', mainTitle: '親情無價\n一家平安樂融融', subTitle: '孩子在外平安工作，長輩在家身體安康，全家美滿。'),
    GoldenQuote(category: '家庭親情', mainTitle: '心繫晚輩\n願孩子出門皆平安', subTitle: '老父親、老母親的牽掛，祝兒女在外順心、身體強壯。'),
    GoldenQuote(category: '家庭親情', mainTitle: '老伴同行\n相知相守幸福長', subTitle: '少年夫妻老來伴，平平淡淡才是真，祝天天開心。'),
    GoldenQuote(category: '家庭親情', mainTitle: '好友同樂\n常常聯繫情意深', subTitle: '天氣好出門走走，泡茶聊天敘舊情，早安順遂。'),
    GoldenQuote(category: '家庭親情', mainTitle: '福澤子孫\n世代和諧家道昌', subTitle: '言傳身教留美德，一家祥和福澤厚，祝大家富貴安康。'),
    GoldenQuote(category: '家庭親情', mainTitle: '同舟共濟\n歲月深處有溫情', subTitle: '感恩身邊所有陪伴我們的人，願幸福永遠圍繞您。'),
  ];
}
