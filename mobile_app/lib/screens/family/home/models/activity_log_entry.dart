import 'package:flutter/material.dart';

/// 長輩動態解析後的結構化模型
class ActivityLogEntry {
  final String timeText;
  final String title;
  final String? subtitle;
  final String categoryTag;
  final String statusText;
  final IconData icon;
  final Color themeColor;
  final bool isChat;
  final String fullQuery;
  final String fullAi;

  const ActivityLogEntry({
    required this.timeText,
    required this.title,
    this.subtitle,
    required this.categoryTag,
    required this.statusText,
    required this.icon,
    required this.themeColor,
    this.isChat = false,
    this.fullQuery = '',
    this.fullAi = '',
  });
}

/// 動態文字清洗與解析工具
class ActivityLogParser {
  static Map<String, String> cleanAiLogText(String rawText) {
    if (!rawText.contains('長者詢問：') && !rawText.contains('AI 回應：')) {
      return {'user': '', 'ai': rawText};
    }
    String userPart = '';
    String aiPart = rawText;

    if (rawText.contains('| AI 回應：')) {
      final parts = rawText.split('| AI 回應：');
      userPart = parts[0].replaceAll('長者詢問：', '').trim();
      aiPart = parts.length > 1 ? parts[1].trim() : '';
    } else if (rawText.contains('AI 回應：')) {
      final parts = rawText.split('AI 回應：');
      userPart = parts[0].replaceAll('長者詢問：', '').trim();
      aiPart = parts.length > 1 ? parts[1].trim() : '';
    } else {
      userPart = rawText.replaceAll('長者詢問：', '').trim();
    }
    return {'user': userPart, 'ai': aiPart};
  }

  static ActivityLogEntry parseActivityLogItem(Map<String, dynamic> item, ColorScheme cs) {
    final rawDesc = item['desc']?.toString() ?? item['content']?.toString() ?? '';
    final rawTitle = item['title']?.toString() ?? '';
    final rawTime = item['time']?.toString() ?? '';
    final badge = item['badge']?.toString() ?? '';
    final eventType = item['eventType']?.toString() ?? item['event_type']?.toString() ?? '';
    final fullText = '$rawTitle $rawDesc';

    String timeDisplay = rawTime;
    if (timeDisplay.isEmpty && item['rawTimestamp'] != null) {
      final ts = item['rawTimestamp'].toString();
      if (ts.length >= 16) {
        timeDisplay = ts.substring(11, 16);
      }
    }

    // 1. 新聞類 (News)
    if (rawDesc.contains('【新聞點閱】') || badge == 'NEWS' || eventType == 'news_view' || eventType == 'news_query' || fullText.contains('新聞')) {
      String cleanTitle = rawDesc;
      String categoryName = '熱門新聞';
      IconData newsIcon = Icons.newspaper_rounded;

      final catMatch = RegExp(r'類別:\s*([^\s|｜]+)').firstMatch(rawDesc);
      if (catMatch != null) {
        final rawCat = catMatch.group(1)!.trim().toLowerCase();
        if (rawCat.contains('sport') || rawCat.contains('體育') || rawCat.contains('nba') || rawCat.contains('棒球')) {
          categoryName = '體育賽事';
          newsIcon = Icons.sports_baseball_rounded;
        } else if (rawCat.contains('finance') || rawCat.contains('財經') || rawCat.contains('股市') || rawCat.contains('stock')) {
          categoryName = '財經生活';
          newsIcon = Icons.trending_up_rounded;
        } else if (rawCat.contains('entertain') || rawCat.contains('娛樂') || rawCat.contains('藝人')) {
          categoryName = '影視娛樂';
          newsIcon = Icons.movie_rounded;
        } else if (rawCat.contains('health') || rawCat.contains('健康') || rawCat.contains('醫療')) {
          categoryName = '健康時事';
          newsIcon = Icons.favorite_rounded;
        } else {
          categoryName = '焦點新聞';
        }
      }

      final titleMatch = RegExp(r'標題:\s*(.*)').firstMatch(rawDesc);
      if (titleMatch != null) {
        cleanTitle = titleMatch.group(1)!.trim();
      } else {
        cleanTitle = rawDesc
            .replaceAll(RegExp(r'【新聞點閱】\s*'), '')
            .replaceAll(RegExp(r'類別:\s*[^\s|｜]+\s*[|｜]?\s*'), '')
            .replaceAll('標題:', '')
            .trim();
      }
      if (cleanTitle.isEmpty) cleanTitle = '閱覽時事焦點新聞';

      return ActivityLogEntry(
        timeText: timeDisplay,
        title: cleanTitle,
        categoryTag: categoryName,
        statusText: '已閱覽',
        icon: newsIcon,
        themeColor: const Color(0xFF38BDF8),
      );
    }

    // 2. 散步與運動伸展類 (Walk / Activity / Exercise / Stretch)
    if (fullText.contains('散步') || fullText.contains('步數') || fullText.contains('運動') || fullText.contains('伸展') || fullText.contains('體操') || fullText.contains('健身') || badge == 'WALK' || eventType == 'activity') {
      String stepCountStr = '';
      final numMatch = RegExp(r'(\d+)\s*步').firstMatch(fullText);
      if (numMatch != null) {
        stepCountStr = '${numMatch.group(1)} 步';
      }

      String actName = '';
      final quoteMatch = RegExp(r'「([^」\n]{1,25})」').firstMatch(fullText);
      if (quoteMatch != null) {
        actName = quoteMatch.group(1)!.trim();
        if (actName.contains('「')) {
          actName = actName.split('「').last.trim();
        }
        if (actName.contains('...')) {
          actName = actName.replaceAll('...', '').trim();
        }
        actName = actName.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]+$'), '').trim();
        actName = actName.replaceAll(RegExp(r'^[^\w\u4e00-\u9fa5]+'), '').trim();
        if (actName.startsWith('做')) actName = actName.substring(1);
      }
      if (actName.isEmpty) {
        final m = RegExp(r'(傍晚伸展|伸展運動|晨間散步|健康體操|太極拳|深蹲|抬腿|瑜珈|散步|運動)').firstMatch(fullText);
        actName = m != null ? m.group(1)! : '';
      }

      String title = stepCountStr.isNotEmpty
          ? '戶外散步累計 $stepCountStr'
          : (actName.isNotEmpty ? '完成「$actName」' : '完成日常運動打卡');
      return ActivityLogEntry(
        timeText: timeDisplay,
        title: title,
        categoryTag: '健康運動',
        statusText: '已完成',
        icon: (actName.contains('伸展') || fullText.contains('伸展')) ? Icons.self_improvement_rounded : Icons.directions_walk_rounded,
        themeColor: const Color(0xFF10B981),
      );
    }

    // 3. 用藥類 (Medication)
    if (fullText.contains('藥') || badge == 'MEDICINE' || eventType == 'medication') {
      String medName = '';
      final quoteMatch = RegExp(r'「([^」\n]{1,25})」').firstMatch(fullText);
      if (quoteMatch != null) {
        medName = quoteMatch.group(1)!.trim();
        if (medName.contains('「')) {
          medName = medName.split('「').last.trim();
        }
        if (medName.contains('...')) {
          medName = medName.replaceAll('...', '').trim();
        }
        medName = medName.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]+$'), '').trim();
        medName = medName.replaceAll(RegExp(r'^[^\w\u4e00-\u9fa5]+'), '').trim();
        if (medName.startsWith('吃')) medName = medName.substring(1);
        if (medName.startsWith('服用')) medName = medName.substring(2);
      }
      if (medName.isEmpty) {
        final m = RegExp(r'(高血壓藥|降血壓藥|胃藥|止痛藥|慢性病藥|維他命|綜合維他命|感冒藥|心臟藥|血糖藥|糖尿病藥|中藥)').firstMatch(fullText);
        medName = m != null ? m.group(1)! : '指定用藥';
      }

      return ActivityLogEntry(
        timeText: timeDisplay,
        title: '服用「$medName」',
        categoryTag: '準時服藥',
        statusText: '已完成',
        icon: Icons.medication_rounded,
        themeColor: const Color(0xFF06B6D4),
      );
    }

    // 4. 影音與音樂類 (YouTube / Media)
    if (fullText.contains('YouTube') || fullText.contains('音樂') || fullText.contains('歌曲') || badge == 'MEDIA' || eventType == 'youtube_query') {
      String mediaName = '';
      final quoteMatch = RegExp(r'《(.*?)》|「(.*?)」').firstMatch(fullText);
      if (quoteMatch != null) {
        mediaName = quoteMatch.group(1) ?? quoteMatch.group(2) ?? '';
      } else {
        final match = RegExp(r'(?:YouTube 音樂/影片|歌曲|音樂|播放|點播)[：:\s]*([^\s|｜]+)').firstMatch(fullText);
        if (match != null) {
          mediaName = match.group(1)!;
        }
      }
      if (mediaName.isEmpty) mediaName = '熱門影音內容';

      return ActivityLogEntry(
        timeText: timeDisplay,
        title: '點播收聽《$mediaName》',
        categoryTag: '經典影音',
        statusText: '已播放',
        icon: Icons.play_circle_fill_rounded,
        themeColor: const Color(0xFFF43F5E),
      );
    }

    // 5. AI 陪伴與日常對話 (AI Chat)
    if (item['isChat'] == true || badge == 'AI CHAT' || fullText.contains('長者詢問') || (fullText.contains('長輩') && fullText.contains('AI')) || eventType == 'chat' || eventType == 'mood') {
      final cleaned = cleanAiLogText(rawDesc);
      final userTalk = cleaned['user']?.trim() ?? '';
      final aiTalk = cleaned['ai']?.trim() ?? '';

      String displayTitle = userTalk.isNotEmpty ? '長輩：「$userTalk」' : '語音互動與陪伴關懷';
      String displaySub = aiTalk.isNotEmpty ? '小嘎：「${aiTalk.length > 50 ? '${aiTalk.substring(0, 50)}...' : aiTalk}」' : '';

      return ActivityLogEntry(
        timeText: timeDisplay,
        title: displayTitle,
        subtitle: displaySub.isNotEmpty ? displaySub : null,
        categoryTag: 'AI 陪伴',
        statusText: '陪伴對話',
        icon: Icons.chat_bubble_rounded,
        themeColor: const Color(0xFFF59E0B),
        isChat: true,
        fullQuery: userTalk.isNotEmpty ? userTalk : (item['fullQuery']?.toString() ?? ''),
        fullAi: aiTalk.isNotEmpty ? aiTalk : (item['fullAi']?.toString() ?? ''),
      );
    }

    // 6. 其他通用動態
    String cleanText = rawDesc.replaceAll(RegExp(r'【.*?】'), '').trim();
    if (cleanText.isEmpty) cleanText = rawTitle;
    if (cleanText.length > 30) cleanText = '${cleanText.substring(0, 30)}...';

    return ActivityLogEntry(
      timeText: timeDisplay,
      title: cleanText,
      categoryTag: '生活足跡',
      statusText: '已記錄',
      icon: Icons.check_circle_rounded,
      themeColor: cs.primary,
    );
  }
}
