library;

/// 台灣民間信仰與道教/佛教神明誕辰資料庫與推算引擎
/// 資料來源依據內政部全國宗教資訊網與全台代表性宮廟歲時祭儀表
/// 完全以農曆月日為依據，配合天文算法自動精準對照，終生無需手動更新。

class DeityInfo {
  final int lunarMonth;
  final int lunarDay;
  final String name;
  final String title;
  final String category;
  final String blessing;
  final String customNote;
  final bool isMajor;
  final String iconEmoji;

  const DeityInfo({
    required this.lunarMonth,
    required this.lunarDay,
    required this.name,
    required this.title,
    required this.category,
    required this.blessing,
    required this.customNote,
    this.isMajor = false,
    this.iconEmoji = '🏮',
  });
}

class TaiwanDeityCalendar {
  /// 全年台灣神明誕辰完整清單（按農曆月份排序）
  static const List<DeityInfo> allDeities = [
    // ── 正月 (農曆一月) ──
    DeityInfo(
      lunarMonth: 1,
      lunarDay: 1,
      name: '元始天尊萬壽 / 彌勒尊佛佛誕',
      title: '開春大吉・彌勒佛誕',
      category: '迎春納福',
      blessing: '新年行大運，笑口常開、闔家團圓大吉昌。',
      customNote: '開春到廟宇走春祈福、點光明燈安太歲。',
      isMajor: true,
      iconEmoji: '🎉',
    ),
    DeityInfo(
      lunarMonth: 1,
      lunarDay: 4,
      name: '接神日',
      title: '迎百神回人間',
      category: '迎神接福',
      blessing: '眾神下凡賜百福，迎祥納吉、平安順遂。',
      customNote: '家家戶戶備素果甜料，焚香恭迎灶君與諸神回宮。',
      isMajor: true,
      iconEmoji: '✨',
    ),
    DeityInfo(
      lunarMonth: 1,
      lunarDay: 6,
      name: '清水祖師聖誕',
      title: '三峽祖師公生',
      category: '消災解厄',
      blessing: '庇佑風調雨順、驅逐疫病、身體勇健無煩惱。',
      customNote: '三峽祖師廟賽神豬與祈福繞境。',
      isMajor: true,
      iconEmoji: '🙏',
    ),
    DeityInfo(
      lunarMonth: 1,
      lunarDay: 9,
      name: '玉皇上帝萬壽',
      title: '天公生',
      category: '天官賜福',
      blessing: '感念天公至高恩德，祈求闔家安康、福祿壽三星高照。',
      customNote: '子時起備清茶素果、天公金拜天公，隆重莊嚴。',
      isMajor: true,
      iconEmoji: '👑',
    ),
    DeityInfo(
      lunarMonth: 1,
      lunarDay: 13,
      name: '關聖帝君飛昇日',
      title: '恩主公飛昇紀念',
      category: '正氣護佑',
      blessing: '義薄雲天，護佑行事光明磊落、萬事順遂。',
      customNote: '行天宮與各地關帝廟舉行莊嚴祝聖法會。',
      iconEmoji: '⚔️',
    ),
    DeityInfo(
      lunarMonth: 1,
      lunarDay: 15,
      name: '上元天官大帝聖誕 / 臨水夫人千秋',
      title: '元宵節・上元天官賜福日',
      category: '賜福消災',
      blessing: '上元天官賜百福，圓圓滿滿、好運連連一整年。',
      customNote: '吃元宵湯圓、賞花燈猜燈謎、祈求婦幼平安。',
      isMajor: true,
      iconEmoji: '🏮',
    ),

    // ── 二月 ──
    DeityInfo(
      lunarMonth: 2,
      lunarDay: 2,
      name: '福德正神千秋 / 濟公活佛聖誕',
      title: '土地公生（頭牙）',
      category: '招財納福・保境安民',
      blessing: '土地公伯保佑閤家平安、事業興旺、財源廣進。',
      customNote: '準備麻糬（黏錢）、花生（好事發生）向土地公祝壽。',
      isMajor: true,
      iconEmoji: '💰',
    ),
    DeityInfo(
      lunarMonth: 2,
      lunarDay: 3,
      name: '文昌帝君聖誕',
      title: '文昌帝君生',
      category: '功名考運・增長智慧',
      blessing: '文昌開智慧，保佑金榜題名、思緒清明、學業事業皆通達。',
      customNote: '準備蔥（聰明）、芹菜（勤勞）、蘿蔔（好彩頭）拜文昌。',
      isMajor: true,
      iconEmoji: '📚',
    ),
    DeityInfo(
      lunarMonth: 2,
      lunarDay: 15,
      name: '太上老君萬壽 / 三山國王千秋',
      title: '道德天尊聖誕・客家三山國王生',
      category: '延年益壽・保境安民',
      blessing: '清靜無為增福壽，地方安寧、萬物欣欣向榮。',
      customNote: '道觀宮廟舉辦三清法會，祈求安泰。',
      iconEmoji: '☯️',
    ),
    DeityInfo(
      lunarMonth: 2,
      lunarDay: 19,
      name: '觀世音菩薩佛誕',
      title: '觀音佛祖佛誕',
      category: '大慈大悲・消災延壽',
      blessing: '觀音菩薩慈悲護佑，消災解厄、健康長壽、心想事成。',
      customNote: '今日宜茹素念佛，到觀音廟參香祈求全家安樂。',
      isMajor: true,
      iconEmoji: '🪷',
    ),

    // ── 三月 ──
    DeityInfo(
      lunarMonth: 3,
      lunarDay: 3,
      name: '玄天上帝萬壽',
      title: '帝爺公生',
      category: '驅邪鎮煞・消災保命',
      blessing: '玄天上帝神威顯赫，護佑家宅平安、掃除晦氣。',
      customNote: '松柏嶺受天宮等各地帝爺公廟進香盛會。',
      isMajor: true,
      iconEmoji: '🛡️',
    ),
    DeityInfo(
      lunarMonth: 3,
      lunarDay: 15,
      name: '保生大帝千秋 / 中路武財神趙公明聖誕',
      title: '大道公生・武財神生',
      category: '醫藥康健・招財進寶',
      blessing: '醫神護體百病不侵，武財神賜正偏財庫豐盈。',
      customNote: '求身體健康、喝保生大帝大悲水，迎財神補財庫。',
      isMajor: true,
      iconEmoji: '🌿',
    ),
    DeityInfo(
      lunarMonth: 3,
      lunarDay: 20,
      name: '註生娘娘千秋',
      title: '註生娘娘生',
      category: '求子添丁・護幼平安',
      blessing: '保佑早生貴子、母子均安、子孫孝順成才。',
      customNote: '婦女祈求懷孕求子常備百合花祝壽。',
      iconEmoji: '👶',
    ),
    DeityInfo(
      lunarMonth: 3,
      lunarDay: 23,
      name: '天上聖母聖誕',
      title: '媽祖生（三月瘋媽祖）',
      category: '全台護佑・出入平安',
      blessing: '天上聖母慈悲護國佑民，保佑行車出入平安、吉祥如意。',
      customNote: '全台媽祖廟大遶境（大甲鎮瀾宮、白沙屯、北港朝天宮）。',
      isMajor: true,
      iconEmoji: '🌊',
    ),

    // ── 四月 ──
    DeityInfo(
      lunarMonth: 4,
      lunarDay: 8,
      name: '釋迦牟尼佛佛誕',
      title: '浴佛節・佛誕日',
      category: '福慧雙修・心靈清淨',
      blessing: '佛光普照，洗淨塵勞，增長福德與智慧。',
      customNote: '寺院舉行浴佛大典，以香湯灌沐悉達多太子像。',
      isMajor: true,
      iconEmoji: '🌸',
    ),
    DeityInfo(
      lunarMonth: 4,
      lunarDay: 14,
      name: '呂純陽祖師聖誕',
      title: '孚佑帝君・呂仙祖生',
      category: '斬斷爛桃花・醫藥養生',
      blessing: '仙風道骨增福慧，去除煩惱與小人。',
      customNote: '木柵指南宮舉辦隆重祝壽法會。',
      iconEmoji: '🗡️',
    ),
    DeityInfo(
      lunarMonth: 4,
      lunarDay: 26,
      name: '神農大帝聖誕',
      title: '五穀先帝生・神農先帝生',
      category: '五穀豐收・醫藥健體',
      blessing: '五穀滿倉生活無憂，神農保佑飲食健康長壽。',
      customNote: '農民與中醫藥行虔誠敬拜感謝恩德。',
      iconEmoji: '🌾',
    ),

    // ── 五月 ──
    DeityInfo(
      lunarMonth: 5,
      lunarDay: 5,
      name: '端午節・屈原紀念日',
      title: '端午節・五毒辟邪日',
      category: '驅邪辟毒・消災安泰',
      blessing: '端午安康，掛艾草除穢氣，一家老小平安健康。',
      customNote: '吃粽子、掛菖蒲艾草、取午時水祈福淨身。',
      isMajor: true,
      iconEmoji: '🛶',
    ),
    DeityInfo(
      lunarMonth: 5,
      lunarDay: 13,
      name: '霞海城隍爺千秋 / 關平太子千秋',
      title: '城隍爺千秋（五月十三人看人）',
      category: '保境安民・求良緣',
      blessing: '城隍明察秋毫護家園，月老牽紅線姻緣美滿。',
      customNote: '大稻埕霞海城隍廟傳統大拜拜遶境。',
      isMajor: true,
      iconEmoji: '🏮',
    ),

    // ── 六月 ──
    DeityInfo(
      lunarMonth: 6,
      lunarDay: 19,
      name: '觀世音菩薩成道紀念日',
      title: '觀音成道日',
      category: '智慧圓滿・吉祥如意',
      blessing: '菩薩成道賜福祉，萬事順心、家庭和睦祥和。',
      customNote: '觀音信眾持齋茹素、誦普門品迴向家人。',
      isMajor: true,
      iconEmoji: '🪷',
    ),
    DeityInfo(
      lunarMonth: 6,
      lunarDay: 24,
      name: '關聖帝君聖誕 / 西秦王爺千秋',
      title: '恩主公生・關公生',
      category: '忠義仁勇・財星高照',
      blessing: '關公護身事業大展，財運亨通、鎮宅避凶保吉祥。',
      customNote: '行天宮、大溪普濟堂關聖帝君遶境大典。',
      isMajor: true,
      iconEmoji: '🦁',
    ),

    // ── 七月 ──
    DeityInfo(
      lunarMonth: 7,
      lunarDay: 7,
      name: '七星娘娘聖誕 / 魁星爺聖誕',
      title: '七夕・七娘媽生',
      category: '護幼開竅・夫妻和諧',
      blessing: '保佑孩童平安長大成人，夫妻恩愛、學子開竅。',
      customNote: '台南「做十六歲」成年禮、拜七娘媽油飯麻油雞。',
      isMajor: true,
      iconEmoji: '💖',
    ),
    DeityInfo(
      lunarMonth: 7,
      lunarDay: 15,
      name: '中元地官大帝聖誕',
      title: '中元節・地官赦罪日',
      category: '赦罪解厄・普度感恩',
      blessing: '地官大帝赦免過愆，普施十方、累積陰德百福臨。',
      customNote: '各宮廟與社區盛大舉辦中元普渡拜拜。',
      isMajor: true,
      iconEmoji: '🕯️',
    ),
    DeityInfo(
      lunarMonth: 7,
      lunarDay: 18,
      name: '瑤池金母聖誕',
      title: '王母娘娘生',
      category: '賜福消災・求壽求安',
      blessing: '母娘慈悲賜祥瑞，延年益壽、家運亨通。',
      customNote: '花蓮慈惠堂、勝安宮各大母娘廟香客雲集。',
      iconEmoji: '👑',
    ),
    DeityInfo(
      lunarMonth: 7,
      lunarDay: 30,
      name: '地藏王菩薩佛誕',
      title: '地藏菩薩生',
      category: '大願慈悲・超拔先祖',
      blessing: '地藏菩薩大願護佑，闔家身心安定、先人得度。',
      customNote: '誦地藏經、放生修善迴向父母親眷。',
      isMajor: true,
      iconEmoji: '☸️',
    ),

    // ── 八月 ──
    DeityInfo(
      lunarMonth: 8,
      lunarDay: 3,
      name: '九天司命灶君千秋',
      title: '灶君生',
      category: '守護家灶・飲食健康',
      blessing: '灶君保佑一家溫飽平安、無災無難。',
      customNote: '清理廚房瓦斯爐，保持乾淨拜灶神。',
      iconEmoji: '🍲',
    ),
    DeityInfo(
      lunarMonth: 8,
      lunarDay: 15,
      name: '福德正神千秋 / 太陰星君聖誕',
      title: '中秋節・土地公秋祭',
      category: '慶豐收・月圓人圓',
      blessing: '月圓人團圓，土地公賜五穀滿倉、招財納福。',
      customNote: '吃月餅柚子賞月，到土地公廟感謝一年護佑。',
      isMajor: true,
      iconEmoji: '🌕',
    ),

    // ── 九月 ──
    DeityInfo(
      lunarMonth: 9,
      lunarDay: 9,
      name: '中壇元帥千秋 / 斗姥元君聖誕 / 天上聖母飛昇日',
      title: '重陽節・太子爺生（哪吒三太子）',
      category: '敬老尊賢・孩童平安',
      blessing: '太子爺大展神威驅凶避邪，保佑長輩福壽綿長如南山。',
      customNote: '重陽敬老登高、新營太子宮三太子進香盛事。',
      isMajor: true,
      iconEmoji: '🔥',
    ),
    DeityInfo(
      lunarMonth: 9,
      lunarDay: 19,
      name: '觀世音菩薩出家紀念日',
      title: '觀音出家日',
      category: '精進修行・善緣廣聚',
      blessing: '放下罣礙得清涼自在，福田廣植、心胸開闊。',
      customNote: '寺院舉辦大悲懺法會，信眾茹素隨喜。',
      isMajor: true,
      iconEmoji: '🪷',
    ),
    DeityInfo(
      lunarMonth: 9,
      lunarDay: 30,
      name: '藥師琉璃光如來佛誕',
      title: '藥師佛佛誕',
      category: '消災延壽・身心康健',
      blessing: '藥師佛願力加持，病痛消弭、身心安康、延壽無量。',
      customNote: '點藥師佛延壽燈，祈求長輩身體健康。',
      isMajor: true,
      iconEmoji: '💎',
    ),

    // ── 十月 ──
    DeityInfo(
      lunarMonth: 10,
      lunarDay: 15,
      name: '下元水官大帝聖誕',
      title: '下元節・水官解厄日',
      category: '消災解厄・化解冤愆',
      blessing: '水官大帝解厄釋罪，掃除厄運、迎接來年好兆頭。',
      customNote: '三官大帝廟舉辦祈安醮典，化解一整年不順。',
      isMajor: true,
      iconEmoji: '🌊',
    ),

    // ── 十一月 ──
    DeityInfo(
      lunarMonth: 11,
      lunarDay: 17,
      name: '阿彌陀佛佛誕',
      title: '阿彌陀佛佛誕',
      category: '無量光壽・心神安泰',
      blessing: '南無阿彌陀佛，身心自在、福慧具足、平安喜樂。',
      customNote: '各大道場舉辦彌陀佛七念佛祈福法會。',
      isMajor: true,
      iconEmoji: '☀️',
    ),

    // ── 十二月 ──
    DeityInfo(
      lunarMonth: 12,
      lunarDay: 8,
      name: '釋迦牟尼佛成道日',
      title: '臘八節・佛成道日',
      category: '智慧圓滿・感恩惜福',
      blessing: '佛陀成道智慧開，闔家平安吉祥、福德無量。',
      customNote: '吃臘八粥結善緣，滋補養生慶吉祥。',
      isMajor: true,
      iconEmoji: '🥣',
    ),
    DeityInfo(
      lunarMonth: 12,
      lunarDay: 16,
      name: '福德正神千秋',
      title: '尾牙・謝土地公恩',
      category: '感謝賜福・聚財圓滿',
      blessing: '感謝土地公整年照顧，吃刈包潤餅、來年大發利市。',
      customNote: '公司行號與家庭拜土地公、享用尾牙刈包。',
      isMajor: true,
      iconEmoji: '🥟',
    ),
    DeityInfo(
      lunarMonth: 12,
      lunarDay: 24,
      name: '送神日',
      title: '恭送百神返天庭',
      category: '辭舊迎新・除舊佈新',
      blessing: '送神早接神晚，感謝諸神護佑一年平安。',
      customNote: '備甜湯圓甜糖拜灶君「上天言好事」，開始大掃除筅塵。',
      isMajor: true,
      iconEmoji: '🧹',
    ),
    DeityInfo(
      lunarMonth: 12,
      lunarDay: 30,
      name: '除夕・圍爐歲除',
      title: '大年除夕・歲除祈安',
      category: '辭舊迎新・闔家團圓',
      blessing: '辭舊歲迎新春，闔家團圓守歲、福壽安康一整年！',
      customNote: '全家吃團圓飯、發紅包、守歲迎接大年初一。',
      isMajor: true,
      iconEmoji: '🏮',
    ),
  ];

  /// 依農曆月日查詢當日神明誕辰
  static List<DeityInfo> getDeities(int lunarMonth, int lunarDay) {
    return allDeities
        .where((d) => d.lunarMonth == lunarMonth && d.lunarDay == lunarDay)
        .toList();
  }

  /// 搜尋自當前農曆日起，下一個即將到來的神明誕辰
  static ({DeityInfo deity, int daysAway})? getNextUpcomingDeity(
      int currentLunarMonth, int currentLunarDay) {
    // 先找本月未來的神明
    for (final deity in allDeities) {
      if (deity.lunarMonth == currentLunarMonth &&
          deity.lunarDay > currentLunarDay) {
        return (deity: deity, daysAway: deity.lunarDay - currentLunarDay);
      }
    }

    // 若本月無，找接下來月份的第一個神明
    for (int m = 1; m <= 12; m++) {
      final targetMonth = ((currentLunarMonth - 1 + m) % 12) + 1;
      for (final match in allDeities) {
        if (match.lunarMonth == targetMonth) {
          final approxDays = (30 - currentLunarDay) + ((m - 1) * 30) + match.lunarDay;
          return (deity: match, daysAway: approxDays);
        }
      }
    }

    return null;
  }
}