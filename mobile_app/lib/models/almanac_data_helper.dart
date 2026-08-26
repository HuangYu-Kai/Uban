import 'package:lunar/lunar.dart';
import 'chinese_converter.dart';
import 'taiwan_deity_calendar.dart';

/// 單日完整農民曆與吉凶資訊模型
class DayAlmanacInfo {
  final DateTime solarDate;
  final Lunar lunar;
  final String solarString;
  final String solarWeekDay;
  final String lunarString;
  final String lunarShort;
  final String solarTerm;
  final List<DeityInfo> deities;
  final ({DeityInfo deity, int daysAway})? upcomingDeity;
  final List<String> yiList;
  final List<String> jiList;
  final String caiShen;
  final String xiShen;
  final String fuShen;
  final String chongDesc;
  final String pengZu;
  final String shengXiao;
  final String ganZhiYear;
  final String ganZhiMonth;
  final String ganZhiDay;

  const DayAlmanacInfo({
    required this.solarDate,
    required this.lunar,
    required this.solarString,
    required this.solarWeekDay,
    required this.lunarString,
    required this.lunarShort,
    required this.solarTerm,
    required this.deities,
    this.upcomingDeity,
    required this.yiList,
    required this.jiList,
    required this.caiShen,
    required this.xiShen,
    required this.fuShen,
    required this.chongDesc,
    required this.pengZu,
    required this.shengXiao,
    required this.ganZhiYear,
    required this.ganZhiMonth,
    required this.ganZhiDay,
  });

  /// 是否有神明生日
  bool get hasDeityBirthday => deities.isNotEmpty;

  /// 生成適合長輩聽的語音朗讀文字
  String toSpeechString() {
    final buffer = StringBuffer();
    buffer.write('今天是國曆 ${solarDate.month} 月 ${solarDate.day} 日，$solarWeekDay。');
    buffer.write('農曆是 $lunarShort，歲次 $ganZhiYear 年。');
    if (solarTerm.isNotEmpty) {
      buffer.write('節氣是 $solarTerm。');
    }

    if (hasDeityBirthday) {
      final names = deities.map((d) => d.name).join('、');
      buffer.write('今日吉祥神明聖誕：$names。祝您闔家平安！');
    } else if (upcomingDeity != null) {
      buffer.write('距離下一個節日，${upcomingDeity!.deity.title}，還有 ${upcomingDeity!.daysAway} 天。');
    }

    if (yiList.isNotEmpty) {
      final topYi = yiList.take(4).join('、');
      buffer.write('今日宜：$topYi。');
    }
    if (jiList.isNotEmpty) {
      final topJi = jiList.take(3).join('、');
      buffer.write('今日忌：$topJi。');
    }

    buffer.write('財神在 $caiShen 方，喜神在 $xiShen 方。$chongDesc。祝您今天心情愉快、身體勇健！');
    return buffer.toString();
  }
}

/// 農民曆資料計算與白話輔助工具
class AlmanacDataHelper {
  /// 宜忌傳統術語之長輩白話小字典（100% 台灣繁體正體中文）
  static const Map<String, String> _yiJiMeanings = {
    '祭祀': '祭拜祖先、到宮廟參香拜拜或向神明祈福',
    '祈福': '祈求神明賜福保佑、消災解厄或許願',
    '求嗣': '祈求懷孕添丁、生兒育女或子孫昌盛',
    '出行': '出遠門旅遊、搭長途車船或外出公幹',
    '嫁娶': '舉行婚禮、迎娶新娘或登記結婚',
    '納采': '訂婚、下聘禮或提親納吉',
    '訂盟': '訂定婚約、訂婚儀式或立約互誓',
    '動土': '建築陽宅動工、開挖地基或大翻修',
    '安葬': '舉行喪葬儀式、入土為安或骨灰安厝',
    '破土': '陰宅（墓地）破土動工安葬',
    '開市': '商店公司開張營業、開業或新春開工',
    '立券': '簽訂合約契約、訂立買賣憑證或簽字',
    '交易': '大宗商品買賣、房產過戶或簽約交割',
    '納財': '收帳收租、進財入庫或儲蓄存錢',
    '開倉': '打開倉庫出貨、盤點物資或出糧',
    '安床': '安裝安置新床鋪、移動睡床位置',
    '裁衣': '裁製新衣服或製作新禮服壽衣',
    '冠笄': '古代成年禮，現代象徵孩子成年或開竅',
    '修造': '房屋修繕、室內裝潢翻新或油漆木作',
    '豎柱': '建築立起大柱框架',
    '上樑': '建築蓋頂安放正樑之重要吉日',
    '移徙': '搬家、搬遷到新住所',
    '入宅': '遷入新居舉行入厝拜拜儀式',
    '栽種': '播種農作物、栽種花草樹木或整園',
    '牧養': '放牧家禽家畜或開始飼養',
    '納畜': '買進寵物家禽、領養動物',
    '破屋': '拆除老舊破敗危險房屋',
    '壞垣': '拆除舊圍牆或矮牆',
    '治病': '看醫生治療頑疾、動手術或調養身體',
    '伐木': '砍伐樹木或大型林木修剪',
    '作灶': '安裝安放廚房瓦斯爐或整修灶台',
    '齋醮': '設壇舉行道教或佛教祈福法會',
    '探病': '前往醫院或親友家探望病患',
    '開渠': '開闢灌溉水渠或疏通水道溝渠',
    '補垣': '修補破舊牆面或防水補漏',
    '塞穴': '填補蟻穴鼠洞或堵塞漏孔',
    '平治道途': '鋪平道路、整修路面通行',
    '理髮': '修剪頭髮、剃頭理容、換新髮型',
    '整手足甲': '修剪手指甲腳趾甲（初生兒或老人）',
    '沐浴': '洗澡沐浴、溫泉淨身除穢',
    '求醫': '尋找名醫、請教養生健康之道',
    '掃舍': '大掃除、清理家裡灰塵蜘蛛網',
    '安門': '安裝大門或房門',
    '分居': '大家庭分家各自獨立門戶生活',
    '出火': '將神佛或祖先牌位請出暫時安置',
    '合帳': '製作或安裝蚊帳、床簾',
    '安香': '在家中安設神明與祖先香爐',
    '拆卸': '拆除舊建築物、屋舍或裝潢',
    '起基': '建築工程挖地基、奠基動土',
    '定磉': '固定建築柱子下方的柱基石',
    '蓋屋': '搭建房頂、覆蓋屋瓦或上頂',
    '掛匾': '懸掛商店招牌或題字匾額',
    '開池': '開挖魚池、水池或蓄水池',
    '築堤': '修建防洪堤壩或田埂擋水',
    '捕魚': '下水捕撈魚蝦海產',
    '取漁': '收捕魚塭池塘中的漁獲',
    '乘船': '出海捕魚、渡船或水上遊覽',
    '渡水': '橫渡江河水域出行',
    '穿井': '開鑿新水井或鑽深水井',
    '開生墳': '為健在長輩預先修築壽墳福地',
    '合壽木': '為長輩預製吉祥壽棺',
    '修墳': '修繕整理祖先墳墓或修墓碑',
    '立碑': '為祖先墓地立紀念石碑',
    '遷墳': '拾骨遷葬或將祖墳遷移新址',
    '移柩': '出殯前移動靈柩棺木',
    '啟攢': '拾金撿骨、開棺整理遺骸',
    '啟鑽': '啟棺拾骨或開穴撿骨安厝',
    '入殮': '為逝者更衣入棺舉行入殮禮',
    '成服': '喪家親屬穿上孝服守孝',
    '除服': '守孝期滿脫去孝服恢復平常',
    '畋獵': '到野外狩獵或捕獵野生動物',
    '捕捉': '撲滅農田害蟲或捕捉有害生物',
    '結網': '編織漁網或修補捕鳥捕魚器具',
    '割蜜': '採集蜂巢蜂蜜或養蜂取蜜',
    '掘井': '開挖水井以取得甘泉水源',
    '設醮': '建醮設壇祈安謝恩大法會',
    '解除': '沖洗潔淨住宅、禳災解厄化煞',
    '置產': '購買房屋地皮、添購田產物業',
    '會親友': '拜訪親戚朋友、宴請嘉賓聚會',
    '進人口': '收養義子義女、增添家庭成員',
    '經絡': '安裝紡織機經線、織布作業',
    '醞釀': '釀造美酒、製作醬油或發酵食品',
    '問名': '古代六禮之一，詢問女方生辰八字合婚',
  };

  /// 取得特定宜忌術語的白話說明
  static String getMeaning(String term) {
    final traditionalTerm = ChineseConverter.toTraditional(term);
    if (_yiJiMeanings.containsKey(traditionalTerm)) {
      return _yiJiMeanings[traditionalTerm]!;
    }
    return '傳統民俗記事，適宜或應謹慎之吉凶事項。';
  }

  /// 根據指定日期計算出完整的 DayAlmanacInfo（全繁體正體）
  static DayAlmanacInfo calculateForDate(DateTime date) {
    final lunar = Lunar.fromDate(date);

    final lunarMonth = lunar.getMonth();
    final lunarDay = lunar.getDay();

    // 1. 神明誕辰比對
    final deities = TaiwanDeityCalendar.getDeities(lunarMonth, lunarDay);
    final upcoming = deities.isEmpty
        ? TaiwanDeityCalendar.getNextUpcomingDeity(lunarMonth, lunarDay)
        : null;

    // 2. 宜忌清單（100% 繁體化）
    final yi = ChineseConverter.toTraditionalList(lunar.getDayYi());
    final ji = ChineseConverter.toTraditionalList(lunar.getDayJi());

    // 3. 節氣與干支（100% 繁體化）
    String jieQi = lunar.getJieQi();
    if (jieQi.isEmpty) {
      // 取得前後最近節氣
      jieQi = lunar.getCurrentJieQi()?.getName() ?? '';
    }
    final solarTerm = ChineseConverter.toTraditional(jieQi);

    final solarWeekDayNames = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final weekDayStr = solarWeekDayNames[date.weekday - 1];

    final pengZuStr = ChineseConverter.toTraditional('${lunar.getPengZuGan()} ${lunar.getPengZuZhi()}');

    final shengXiao = ChineseConverter.toTraditional(lunar.getYearShengXiao());
    final ganZhiYear = ChineseConverter.toTraditional(lunar.getYearInGanZhi());
    final ganZhiMonth = ChineseConverter.toTraditional(lunar.getMonthInGanZhi());
    final ganZhiDay = ChineseConverter.toTraditional(lunar.getDayInGanZhi());

    final monthInChinese = ChineseConverter.toTraditional(lunar.getMonthInChinese());
    final dayInChinese = ChineseConverter.toTraditional(lunar.getDayInChinese());

    final lunarShort = '$monthInChinese月$dayInChinese';
    final lunarString = '$ganZhiYear($shengXiao)年 農曆$lunarShort';

    return DayAlmanacInfo(
      solarDate: date,
      lunar: lunar,
      solarString: '${date.year}年${date.month}月${date.day}日',
      solarWeekDay: weekDayStr,
      lunarString: lunarString,
      lunarShort: lunarShort,
      solarTerm: solarTerm,
      deities: deities,
      upcomingDeity: upcoming,
      yiList: yi,
      jiList: ji,
      caiShen: ChineseConverter.toTraditional(lunar.getDayPositionCaiDesc()),
      xiShen: ChineseConverter.toTraditional(lunar.getDayPositionXiDesc()),
      fuShen: ChineseConverter.toTraditional(lunar.getDayPositionFuDesc()),
      chongDesc: ChineseConverter.toTraditional(lunar.getDayChongDesc()),
      pengZu: pengZuStr,
      shengXiao: shengXiao,
      ganZhiYear: ganZhiYear,
      ganZhiMonth: ganZhiMonth,
      ganZhiDay: ganZhiDay,
    );
  }
}