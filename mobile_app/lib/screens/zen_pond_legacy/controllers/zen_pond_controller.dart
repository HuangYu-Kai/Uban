import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../services/api_service.dart';

// 錦鯉花紋品種分類
enum KoiPattern {
  kohaku,   // 紅白 (經典橘紅底白斑)
  showa,    // 昭和三色 (深黑底紅白斑)
  yamabuki, // 黃金 (金黃閃爍鱗片)
  benigoi,  // 紅鯉 (深紅底金沙斑)
}

// 錦鯉專屬外觀款式參數
class KoiStyle {
  final List<Color> bodyColors; // 漸層魚身顏色
  final Color finColor;        // 魚鰭半透明顏色
  final List<Color> spotColors; // 花紋斑點顏色
  final KoiPattern pattern;     // 花紋品種
  final double scale;           // 縮放比例 (體型大小差異)

  KoiStyle({
    required this.bodyColors,
    required this.finColor,
    required this.spotColors,
    required this.pattern,
    required this.scale,
  });

  // 隨機生成花色與體型樣式
  factory KoiStyle.random(int seed) {
    final random = math.Random(seed);
    final types = KoiPattern.values;
    final pattern = types[random.nextInt(types.length)];
    
    // 隨機體型大小 (0.85 到 1.15 倍縮放)
    double scale = 0.85 + random.nextDouble() * 0.3;

    switch (pattern) {
      case KoiPattern.showa:
        return KoiStyle(
          bodyColors: [const Color(0xFF212121), const Color(0xFF424242)],
          finColor: const Color(0xCC000000),
          spotColors: [const Color(0xFFD32F2F), const Color(0xFFFFFFFF)],
          pattern: pattern,
          scale: scale,
        );
      case KoiPattern.yamabuki:
        return KoiStyle(
          bodyColors: [const Color(0xFFFFB300), const Color(0xFFFFE082)],
          finColor: const Color(0xCCFFF59D),
          spotColors: [const Color(0xFFFFFDE7)],
          pattern: pattern,
          scale: scale,
        );
      case KoiPattern.benigoi:
        return KoiStyle(
          bodyColors: [const Color(0xFFB71C1C), const Color(0xFFD32F2F)],
          finColor: const Color(0xCCEF5350),
          spotColors: [const Color(0xFFFFD54F)],
          pattern: pattern,
          scale: scale,
        );
      case KoiPattern.kohaku:
      default:
        return KoiStyle(
          bodyColors: [const Color(0xFFE64A19), const Color(0xFFFF8A65)],
          finColor: const Color(0xCCFFCCBC),
          spotColors: [const Color(0xFFFFFFFF)],
          pattern: KoiPattern.kohaku,
          scale: scale,
        );
    }
  }
}

// 單個錦鯉通知項目模型
class KoiNotificationItem {
  final String id;
  final String message;
  final KoiStyle koiStyle;
  bool isLotusVisible;
  final String? imageUrl;

  KoiNotificationItem({
    required this.id,
    required this.message,
    required this.koiStyle,
    this.isLotusVisible = false,
    this.imageUrl,
  });
}

// 三色落葉對話所屬分類
enum LeafColorType { yellow, red, green }

// 單個落葉對話模型 (支援 SharedPreferences JSON 序列化)
class LeafMessageItem {
  final String id;
  final String text;
  final LeafColorType colorType;
  final String? imageUrl;
  final String? videoId; // 支援影片 ID 播放
  final double restingX; // 水面隨機 X 座標比例 (0.15 ~ 0.85)
  final double restingY; // 水面隨機 Y 座標比例 (0.20 ~ 0.70)
  final int createdAt;   // 生成微秒時間戳
  bool isCardVisible;    // 對話卡是否彈出展示

  LeafMessageItem({
    required this.id,
    required this.text,
    required this.colorType,
    this.imageUrl,
    this.videoId,
    required this.restingX,
    required this.restingY,
    required this.createdAt,
    this.isCardVisible = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'colorType': colorType.name,
      'imageUrl': imageUrl,
      'videoId': videoId,
      'restingX': restingX,
      'restingY': restingY,
      'createdAt': createdAt,
      'isCardVisible': isCardVisible,
    };
  }

  factory LeafMessageItem.fromJson(Map<String, dynamic> json) {
    return LeafMessageItem(
      id: json['id'] as String,
      text: json['text'] as String,
      colorType: LeafColorType.values.byName(json['colorType'] as String),
      imageUrl: json['imageUrl'] as String?,
      videoId: json['videoId'] as String?,
      restingX: (json['restingX'] as num).toDouble(),
      restingY: (json['restingY'] as num).toDouble(),
      createdAt: json['createdAt'] as int,
      isCardVisible: json['isCardVisible'] as bool? ?? false,
    );
  }
}

class ZenPondController extends ChangeNotifier {
  // 時光日記對話歷史紀錄
  List<Map<String, dynamic>> history = [];

  // TTS 播放狀態 (存在 Controller 讓日記 Dialog 的 Consumer 能同步刷新)
  String? ttsPlayingId;
  bool ttsLoading = false;
  bool isAiThinking = false;

  void setTtsState({String? playingId, bool loading = false}) {
    ttsPlayingId = playingId;
    ttsLoading = loading;
    notifyListeners();
  }

  void setAiThinking(bool thinking) {
    isAiThinking = thinking;
    notifyListeners();
  }

  // 測試用：模擬當前小時 (null 表示使用真實時間)
  int? mockHour;

  void setMockTime(int hour) {
    mockHour = hour;
    notifyListeners();
  }

  // SOS 相關狀態
  int _tapCount = 0;
  Timer? _tapTimer;
  Timer? _singleTapTimer; // 單擊延遲計時器 (350ms)
  bool isSOSMode = false;
  bool isAiOverlayVisible = false; // 對話 Overlay 彈出狀態

  // 檢查是否有任何對話卡片、語音 Overlay 或祈福水燈卡片處於打開狀態 (用以動態隱藏外層底部導覽列，防遮擋與誤觸)
  bool get isAnyOverlayVisible =>
      isAiOverlayVisible ||
      leaves.any((l) => l.isCardVisible) ||
      notifications.any((n) => n.isLotusVisible);

  // 錦鯉通知清單 (第二階段常態錦鯉)
  final List<KoiNotificationItem> notifications = [];
  int _notificationCounter = 0;

  // 落葉對話清單 (第三階段新功能)
  final List<LeafMessageItem> leaves = [];
  final AudioPlayer _controllerAudioPlayer = AudioPlayer();

  // 讀取時光日記歷史紀錄
  Future<void> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('zen_pond_history');
      if (list != null) {
        history = list.map((str) {
          final item = jsonDecode(str) as Map<String, dynamic>;
          if (item['imageUrl'] == 'https://images.unsplash.com/photo-1516321318423-f06f85e504b3?q=80&w=2070&auto=format&fit=crop') {
            item['imageUrl'] = 'https://upload.wikimedia.org/wikipedia/commons/8/86/Flower_Clock,_Yangmingshan.jpg';
          }
          return item;
        }).toList();
      } else {
        // 初始歷史：加入一個迎賓訊息
        history = [
          {
            'sender': 'ai',
            'text': '爺爺午安！我是您的貼心小幫手。今天感覺怎麼樣？需要我為您放首音樂，或者聊聊天嗎？',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }
        ];
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading history: $e');
    }
  }

  // 儲存時光日記歷史紀錄
  Future<void> saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = history.map((h) => jsonEncode(h)).toList();
      await prefs.setStringList('zen_pond_history', list);
    } catch (e) {
      debugPrint('Error saving history: $e');
    }
  }

  // 新增時光日記歷史紀錄
  void addHistory({
    required String sender,
    required String text,
    String? imageUrl,
    String? videoId,
  }) {
    history.add({
      'sender': sender,
      'text': text,
      'imageUrl': imageUrl,
      'videoId': videoId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    saveHistory();
    notifyListeners();
  }

  // 清空時光日記歷史紀錄
  void clearHistory() {
    history = [
      {
        'sender': 'ai',
        'text': '時光日記已清空，開始我們新的對話吧 😊',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }
    ];
    saveHistory();
    notifyListeners();
  }

  // 刪除特定日期的歷史紀錄
  void deleteHistoryByDate(String dateStr) {
    history.removeWhere((item) {
      final int timestamp = item['timestamp'] ?? 0;
      if (timestamp == 0) return false;
      final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final dStr = "${dt.year}年${dt.month}月${dt.day}日";
      return dStr == dateStr;
    });

    if (history.isEmpty) {
      history.add({
        'sender': 'ai',
        'text': '時光日記已清空，開始我們新的對話吧 😊',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }

    saveHistory();
    notifyListeners();
  }

  // 初始化並讀取本地歷史落葉
  Future<void> loadLeaves() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('zen_pond_leaves');
      if (list != null && list.isNotEmpty) {
        leaves.clear();
        final imgRegExp = RegExp(r'!\[.*?\]\((.*?)\)');
        final videoRegExp = RegExp(r'\[VIDEO_ID:([^\]]+)\]');
        for (var str in list) {
          final leaf = LeafMessageItem.fromJson(jsonDecode(str));
          String? imageUrl = leaf.imageUrl;
          if (imageUrl == 'https://images.unsplash.com/photo-1516321318423-f06f85e504b3?q=80&w=2070&auto=format&fit=crop') {
            imageUrl = 'https://upload.wikimedia.org/wikipedia/commons/8/86/Flower_Clock,_Yangmingshan.jpg';
          }
          // 修復舊快取資料中未解析的 Markdown 圖片語法
          final rawText = leaf.text;
          if (imgRegExp.hasMatch(rawText) || videoRegExp.hasMatch(rawText)) {
            String? parsedImageUrl = imageUrl;
            String? videoId = leaf.videoId;
            // 若 imageUrl 欄位為空但 text 含 Markdown 圖片，解析出來
            if (parsedImageUrl == null) {
              final imgMatch = imgRegExp.firstMatch(rawText);
              if (imgMatch != null) parsedImageUrl = imgMatch.group(1);
            }
            if (parsedImageUrl == 'https://images.unsplash.com/photo-1516321318423-f06f85e504b3?q=80&w=2070&auto=format&fit=crop') {
              parsedImageUrl = 'https://upload.wikimedia.org/wikipedia/commons/8/86/Flower_Clock,_Yangmingshan.jpg';
            }
            if (videoId == null) {
              final videoMatch = videoRegExp.firstMatch(rawText);
              if (videoMatch != null) videoId = videoMatch.group(1);
            }
            String cleanText = rawText
                .replaceAll(imgRegExp, '')
                .replaceAll(videoRegExp, '')
                .trim();
            if (cleanText.isEmpty) {
              cleanText = videoId != null
                  ? '這是為您推薦的影片'
                  : (parsedImageUrl != null ? '為您分享了一張照片' : rawText);
            }
            leaves.add(LeafMessageItem(
              id: leaf.id,
              text: cleanText,
              colorType: leaf.colorType,
              imageUrl: parsedImageUrl,
              videoId: videoId,
              restingX: leaf.restingX,
              restingY: leaf.restingY,
              createdAt: leaf.createdAt,
              isCardVisible: leaf.isCardVisible,
            ));
          } else {
            leaves.add(LeafMessageItem(
              id: leaf.id,
              text: leaf.text,
              colorType: leaf.colorType,
              imageUrl: imageUrl,
              videoId: leaf.videoId,
              restingX: leaf.restingX,
              restingY: leaf.restingY,
              createdAt: leaf.createdAt,
              isCardVisible: leaf.isCardVisible,
            ));
          }
        }
        notifyListeners();
      } else {
        // 本地無歷史，代表首次進入池塘，排程 1秒 與 5秒 經典對話開頭落葉
        triggerFirstPondSequence();
      }
    } catch (e) {
      debugPrint('Error loading leaves: $e');
    }
  }


  // 寫入本地歷史持久化
  Future<void> saveLeaves() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = leaves.map((l) => jsonEncode(l.toJson())).toList();
      await prefs.setStringList('zen_pond_leaves', list);
    } catch (e) {
      debugPrint('Error saving leaves: $e');
    }
  }

  // 新增落葉 (隨機分佈在池塘中央安全區)
  void addLeaf({
    required String text,
    required LeafColorType colorType,
    String? imageUrl,
    String? videoId,
    bool playTts = false,
    bool isCardVisible = false,
  }) {
    final random = math.Random();
    // X 範圍在 0.15 到 0.85 之間，Y 範圍在 0.2 到 0.7 之間，避免太靠近邊緣石頭
    final double rx = 0.15 + random.nextDouble() * 0.7;
    final double ry = 0.2 + random.nextDouble() * 0.5;

    final newLeaf = LeafMessageItem(
      id: 'leaf_${DateTime.now().millisecondsSinceEpoch}_${random.nextInt(1000)}',
      text: text,
      colorType: colorType,
      imageUrl: imageUrl,
      videoId: videoId,
      restingX: rx,
      restingY: ry,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      isCardVisible: isCardVisible,
    );

    // 如果把當前卡片設為開啟，則先關閉其他卡片
    if (isCardVisible) {
      for (var l in leaves) {
        l.isCardVisible = false;
      }
    }

    leaves.add(newLeaf);
    saveLeaves();
    notifyListeners();

    if (playTts) {
      _speakTtsAuto(text);
    }
  }

  // 點擊落葉展開卡片
  void tapLeaf(LeafMessageItem item) {
    _singleTapTimer?.cancel();
    _singleTapTimer = null;
    // 先收起其他所有落葉卡片
    for (var l in leaves) {
      l.isCardVisible = false;
    }
    item.isCardVisible = true;
    notifyListeners();
    _speakTtsAuto(item.text); // 點開落葉時播放語音
  }

  // 收起落葉卡片 (從池塘中溶解移除)
  void dismissLeaf(LeafMessageItem item) {
    leaves.remove(item);
    _controllerAudioPlayer.stop(); // 捨棄或聊天時停止播放落葉語音
    saveLeaves();
    notifyListeners();
  }

  // 停止落葉語音播報
  void stopLeafTts() {
    _controllerAudioPlayer.stop();
  }

  // 首次進入池塘事件排程 (1秒飄落金黃歡迎葉，5秒飄落秀珠紅葉並自動 edge-tts 朗讀)
  void triggerFirstPondSequence() {
    Timer(const Duration(seconds: 1), () {
      addLeaf(
        text: '爺爺午安！我是您的貼心小幫手。今天感覺怎麼樣？需要我為您放首音樂，或者聊聊天嗎？點擊我可以再聽一次喔！',
        colorType: LeafColorType.yellow,
        playTts: false,
      );
      addHistory(
        sender: 'ai',
        text: '爺爺午安！我是您的貼心小幫手。今天感覺怎麼樣？需要我為您放首音樂，或者聊聊天嗎？',
      );
    });

    Timer(const Duration(seconds: 5), () {
      showNotification(
        '爺爺，秀珠傳了一張照片來。她說這是上次去陽明山看花鐘拍的，您還記得嗎？',
        imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/8/86/Flower_Clock,_Yangmingshan.jpg',
      );
      addHistory(
        sender: 'ai',
        text: '爺爺，秀珠傳了一張照片來。她說這是上次去陽明山看花鐘拍的，您還記得嗎？',
        imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/8/86/Flower_Clock,_Yangmingshan.jpg',
      );
    });
  }

  // 從後端 RAG (Pinecone) 接口生成並推播一片話題落葉
  Future<bool> generateAndAddRagLeaf(int userId) async {
    try {
      final res = await ApiService.generatePondLeaf(userId);
      final isSuccess = res['status'] == 'success' || res['success'] == true;
      if (isSuccess && res['data'] != null) {
        final leafText = res['data']['leaf_text'] as String?;
        if (leafText != null && leafText.isNotEmpty) {
          // 解析 Markdown 圖片: ![alt](url)
          String? imageUrl;
          final imgRegExp = RegExp(r'!\[.*?\]\((.*?)\)');
          final imgMatch = imgRegExp.firstMatch(leafText);
          if (imgMatch != null) {
            imageUrl = imgMatch.group(1);
          }

          // 解析影片 ID: [VIDEO_ID:xxxx]
          String? videoId;
          final videoRegExp = RegExp(r'\[VIDEO_ID:([^\]]+)\]');
          final videoMatch = videoRegExp.firstMatch(leafText);
          if (videoMatch != null) {
            videoId = videoMatch.group(1);
          }

          // 移除 Markdown 語法標記，只留乾淨對話文字
          String cleanText = leafText
              .replaceAll(imgRegExp, '')
              .replaceAll(videoRegExp, '')
              .trim();
          if (cleanText.isEmpty) {
            cleanText = videoId != null
                ? '這是為您推薦的影片'
                : (imageUrl != null ? '為您分享了一張照片' : leafText);
          }

          addLeaf(
            text: cleanText,
            colorType: LeafColorType.yellow, // 黃色：長期記憶/回憶落葉
            imageUrl: imageUrl,
            videoId: videoId,
            playTts: false,
          );
          // 同時也加入時光日記
          addHistory(
            sender: 'ai',
            text: cleanText,
            imageUrl: imageUrl,
            videoId: videoId,
          );
          return true;
        }
      }
    } catch (e) {
      debugPrint('ZenPondController generateAndAddRagLeaf error: $e');
    }
    return false;
  }

  // 自動 edge-tts 播報合成器
  Future<void> _speakTtsAuto(String messageText) async {
    try {
      // 過濾可能存在的 [VIDEO_ID] 技術標記
      String speakText = messageText.replaceAll(RegExp(r'\[VIDEO_ID:[^\]]+\]'), '').trim();
      final response = await ApiService.synthesizeTts(text: speakText);
      final isSuccess = response['success'] == true || response['status'] == 'success';
      if (isSuccess) {
        final audioBase64 = (response['audio'] ?? response['audio_base64'] ?? '').toString();
        if (audioBase64.isNotEmpty) {
          // 解碼音訊
          String text = audioBase64.trim();
          if (text.startsWith('data:')) {
            final commaIndex = text.indexOf(',');
            if (commaIndex >= 0 && commaIndex < text.length - 1) {
              text = text.substring(commaIndex + 1);
            }
          }
          text = text.replaceAll(RegExp(r'\s+'), '');
          final missingPadding = text.length % 4;
          if (missingPadding > 0) {
            text += '=' * (4 - missingPadding);
          }
          final audioBytes = base64Decode(text);
          
          await _controllerAudioPlayer.stop();
          await _controllerAudioPlayer.play(BytesSource(audioBytes));
        }
      }
    } catch (e) {
      debugPrint('ZenPondController speakTtsAuto error: $e');
    }
  }

  // --- 錦鯉通知功能 (保留 Phase 2 完整度) ---
  void showNotification(String message, {String? imageUrl}) {
    _notificationCounter++;
    final id = '${DateTime.now().millisecondsSinceEpoch}_$_notificationCounter';
    final koiStyle = KoiStyle.random(DateTime.now().microsecondsSinceEpoch);
    
    final newItem = KoiNotificationItem(
      id: id,
      message: message,
      koiStyle: koiStyle,
      imageUrl: imageUrl,
    );
    
    notifications.add(newItem);
    notifyListeners();
  }

  void tapKoi(KoiNotificationItem item) {
    _singleTapTimer?.cancel();
    _singleTapTimer = null;
    // 收起其他所有蓮花卡
    for (var n in notifications) {
      n.isLotusVisible = false;
    }
    item.isLotusVisible = true;
    notifyListeners();
  }

  void dismissLotus(KoiNotificationItem item) {
    notifications.remove(item);
    notifyListeners();
  }

  // --- 手勢點擊分流防線 (350ms 雙擊/多擊 vs 5擊 SOS) ---
  void handleTap() {
    _tapCount++;
    _tapTimer?.cancel();
    
    if (_tapCount >= 5) {
      _singleTapTimer?.cancel();
      _singleTapTimer = null;
      _triggerSOS();
      _tapCount = 0;
      return;
    }

    // 1 秒沒點擊重置計數
    _tapTimer = Timer(const Duration(seconds: 1), () {
      _tapCount = 0;
    });
    
    // 如果是第一次點擊，啟動 350ms 雙擊延遲防線
    if (_tapCount == 1) {
      _singleTapTimer = Timer(const Duration(milliseconds: 350), () {
        if (_tapCount >= 2 && _tapCount < 5 && !isSOSMode) {
          // 雙擊（或3-4擊）水面，打開 AI 對話 Overlay
          isAiOverlayVisible = true;
          notifyListeners();
        }
        _singleTapTimer = null;
        _tapCount = 0;
      });
    }

    notifyListeners();
  }

  void closeAiOverlay() {
    isAiOverlayVisible = false;
    notifyListeners();
  }

  void _triggerSOS() {
    isSOSMode = true;
    notifyListeners();
    
    debugPrint('🚨 觸發緊急 SOS 求救！(連續點擊 5 次)');
    
    Timer(const Duration(seconds: 5), () {
      isSOSMode = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    _singleTapTimer?.cancel();
    _controllerAudioPlayer.dispose();
    super.dispose();
  }

  // 供外部呼叫的 notifyListeners (用於非 controller 狀態需強制刷新 Dialog 時)
  void forceRefresh() => notifyListeners();
}
