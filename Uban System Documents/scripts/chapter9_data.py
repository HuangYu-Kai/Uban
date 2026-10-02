# -*- coding: utf-8 -*-
"""
Chapter 9 Data Definition - Uban System (第九章 軟體架構與程式規格)
Strictly adheres to:
- Official System Name: "Uban" / "Uban App" (0 occurrences of 優伴)
- Strictly 0 occurrences of forbidden terms: 機構, 長照, 護理, 床位, 高熵, 禪風水池
- 9-1 軟體架構與程式清單 (9-1-1 前端清單, 9-1-2 後端清單, 9-1-3 開發者主控台清單)
- 9-2 程式規格描述 (8 大核心程式碼片段)
- 9-3 核心相依套件清單
- 9-4 外部整合 API 服務清單
"""

# ==============================================================================
# 9-1 程式清單表格資料
# ==============================================================================

FRONTEND_PROGRAM_LIST = [
    ("main.dart", "應用程式進入點與全域通知監聽", "初始化 Firebase、設定 MethodChannel 備援監聽、管理全域狀態與冷啟動身分路由。"),
    ("screens/identification_screen.dart", "身分角色選擇入口", "提供長者端、家屬端、居家監控機三大模式切換入口，並負責安全釋放殘留會話。"),
    ("screens/login_screen.dart", "家屬帳號登入介面", "處理家屬帳號密碼登入驗證、伺服器通訊檢測、密碼顯示切換與註冊導引。"),
    ("screens/elder_profile_onboarding_screen.dart", "長者初次資料設置", "提供大字體年齡步進器、居住縣市行政區二級連動選單，完成在地化氣象設定。"),
    ("screens/elder_tabs/elder_home_tab.dart", "長者大字生活儀表板", "整合國曆農曆日期時間、即時天氣穿著提示、今日要聞大字預覽與生活功能快捷卡。"),
    ("screens/almanac/farmer_almanac_screen.dart", "節氣農民曆日常指引", "展示每日干支五行、吉神宜忌看板、沖煞生肖提示與二十四節氣養生語音指引。"),
    ("screens/news_listen_player/news_listen_player_screen.dart", "語音新聞朗讀播放器", "將每日時事精選轉換為自然國語語音流暢播報，提供大按鈕播放控制與清單切換。"),
    ("screens/elder_tabs/elder_greeting_tab.dart", "親友大頭像電話名冊", "以超大圓形彩色頭像展示綁定之兒女親友，支援一鍵發起語音通話與高畫質視訊。"),
    ("screens/elder_community_screen.dart", "長者社群生活圈", "提供早安祝福圖卡發布、親友生活動態照片瀏覽、一鍵愛心點讚與溫馨語音問候。"),
    ("screens/elder_tabs/elder_chat_tab.dart", "AI 語音陪伴對話分頁", "搭載國台雙語語音辨識與 Google Gemini 情感陪伴助理，呈現波紋視覺回饋。"),
    ("screens/elder_tabs/elder_profile_tab.dart", "個人檔案與萌寵舞台", "整合手繪小豬養成舞台、計步能量轉換與今日任務。"),
    ("screens/widgets/google_assistant_overlay.dart", "語音指令校正覆蓋層", "長者發話時浮現大字體覆蓋確認面板，即時呈現語音辨識結果並提供校正機制。"),
    ("screens/widgets/global_assistant_button.dart", "全域安心助理引導面板", "全域常駐紅色救生圈按鈕，提供步驟高光指引、迷路救援與一鍵返家協助。"),
    ("screens/video_call_screen.dart", "雙向視訊守護連線", "基於 WebRTC 點對點連線之全螢幕視訊通話，具備防鎖屏覆蓋與通話喚醒保護。"),
    ("screens/elder_pairing_display_screen.dart", "長者安全配對碼展示", "以特大字體呈現 4 位數字專屬配對安全碼與動態 QR Code，支援長連線秒速綁定。"),
    ("screens/family/family_home_tab.dart", "家屬守護首頁中樞", "整合長者在線極光卡片、室內房間幾何定位、今日心晴指數、最新警報與 GPS 軌跡。"),
    ("screens/family/elder_location_map_screen.dart", "戶外定位軌跡地圖", "以 OpenStreetMap 呈現長者即時座標、整日移動折線路徑、停留點聚類與歷史回溯。"),
    ("screens/family/family_ai_copilot_screen.dart", "AI 照護副駕駛對話介面", "分析長者日常作息與情緒數據，為子女提供暖心破冰話題與自然語言用藥排程建立。"),
    ("screens/family/family_interaction_tab.dart", "家屬互動通話中樞", "提供發起視訊/語音電話入口、AI 照護副駕駛對話建議與居家監控鏡頭捷徑。"),
    ("screens/family/family_friend_feed_body.dart", "家庭生活時光牆", "匯整長輩每日問候圖卡與生活打卡動態，支援家屬上傳照片留言互動增進感情。"),
    ("screens/camera_screen.dart", "居家 CCTV 監控串流", "即時接收客廳/臥室鏡頭之 WebRTC 串流，疊加 YOLOv8 骨架點並支援雙向對講。"),
    ("screens/family/alert_center_screen.dart", "智慧安全警報中心", "分級呈現跌倒事件、異常滯留與 SOS 警報，支援未處理篩選、抓拍相片與日誌註記。"),
    ("screens/family/health_reminder_screen.dart", "用藥與健康管理排程", "設定長輩早中晚用藥時程與語音提醒內容，同步追蹤長輩服藥打卡遵從率。"),
    ("screens/family/memoirs_gallery_screen.dart", "數位人生回憶錄畫廊", "展示由 Gemini 從日常陪伴對話中萃取之長者人生自傳故事篇章與老照片珍藏。"),
    ("screens/caregiver_pairing_screen.dart", "家屬端配對綁定介面", "提供 4 格專屬配對碼輸入框與相機掃描 QR Code 綁定功能，驗證後即時建立守護關係。"),
    ("screens/family/family_data_tab.dart", "家屬偏好與系統設定", "管理個人帳號檔案、深淺色主題切換、警報推播設定與安全登出。"),
    ("services/signaling.dart", "WebRTC 信令連線單例", "管理 Socket.IO 信令傳輸、ICE 候選交換、SDP 協商與連線狀態心跳維護。"),
    ("services/session_manager.dart", "工作階段安全管理中樞", "統整全專案登出與解除綁定邏輯，確保 FCM Token 註銷、信令斷開與本機暫存清除。"),
]

BACKEND_PROGRAM_LIST = [
    ("main.py", "FastAPI 主程式進入點", "配置 CORS 中介軟體、載入環境變數、註冊各模組 API 路由並掛載 Socket.IO 伺服器。"),
    ("socket_app.py", "Socket.IO 即時信令中心", "管理客戶端連線池、WebRTC 視訊信令單播路由、即時在線狀態推播與配對監聽。"),
    ("yolo_alert_dispatcher.py", "YOLO 跌倒警報派發器", "接收邊緣影像分析之跌倒與滯留事件，自動產生警報紀錄並發送 FCM 高優先權推播。"),
    ("indoor_position.py", "多邊形空間室內定位演算法", "基於腳底接觸點與射線交集法，計算人體於多邊形房間之所在區域。"),
    ("gemini_service.py", "Google Gemini 陪伴與生活助理", "整合 Gemini 大語言模型，支援日常對話、天氣/時間工具自動呼叫與人生回憶錄萃取。"),
    ("location_alert_watch.py", "戶外移動安全警戒排程", "分析長者 GPS 移動軌跡，檢測夜間逗留、異常偏離安全區域與長時間未位移警示。"),
    ("location_daily.py", "每日 GPS 軌跡與停留點計算", "將長者全日經緯度點位進行時空聚類分析，計算移動總里程、停留點位與停留時長。"),
    ("routers/pairing.py", "4 位數專屬配對碼路由", "產生無衝突之 4 位數專屬配對碼，提供時效驗證、防併發鎖定與家庭綁定關係建立。"),
    ("routers/alert.py", "智慧安全警報管理路由", "提供警報事件分頁查詢、未處理篩選、狀態標記已讀、抓拍相片存取與處置備註。"),
    ("routers/reminder.py", "用藥排程與作息提醒路由", "處理日常用藥與生活提醒之新增、修改、刪除，並維護長者每日服藥打卡紀錄。"),
    ("routers/auth.py", "身分認證與權限簽發路由", "負責家屬與開發者之註冊、密碼雜湊驗證、JWT 存取權杖簽發與 Session 釋放。"),
    ("routers/memoir.py", "人生回憶錄故事典藏路由", "儲存與檢索長者人生自傳篇章，支援年代主題分類、老照片附件關聯與語音重播。"),
    ("database.py", "資料庫連線與 ORM 模型映射", "建立 SQLAlchemy 資料庫引擎，配置連線池參數並管理各資料表之模型結構宣告。"),
]

ADMIN_PROGRAM_LIST = [
    ("src/App.tsx", "主控台前端路由與全域佈局", "配置 React Router 路由表、頂部導航列、側邊選單與身分認證守門攔截器。"),
    ("src/pages/Overview.tsx", "系統運作即時監控儀表板", "即時展示連線長者總數、在線邊緣監控設備、今日警報統計與各房間活動分布圖。"),
    ("src/pages/ElderList.tsx", "受守護長者名冊清單", "支援長者姓名關鍵字搜尋、年齡與性別篩選、查看關聯家屬帳號與已綁定設備序號。"),
    ("src/pages/ElderDetail.tsx", "長者個別生活歷程詳情", "檢視長者目前所在房間、歷史活動折線圖、用藥排程狀態與 AI 對話陪伴紀錄摘要。"),
    ("src/pages/AlertHistory.tsx", "安全警報事件處置中心", "列出全系統跌倒與滯留告警日誌，展示現場即時抓拍影像並支援管理員簽核處置備註。"),
    ("src/pages/DataAnalytics.tsx", "活動力趨勢與空間熱點分析", "運用 ECharts 繪製長者日常活動力趨勢圖、睡眠時段分析長條圖與房間停留比例圓餅圖。"),
]

# ==============================================================================
# 9-2 程式規格描述代碼片段 (8 個核心片段，每行逐行詳細繁體中文註解)
# ==============================================================================

CODE_SNIPPETS_9_2 = [
    {
        "table_id": "表 9-2-1",
        "title": "長者端語音指令即時辨識與彈窗確認機制",
        "file_source": "E:/114Project/Uban/mobile_app/lib/screens/widgets/google_assistant_overlay.dart",
        "design_purpose": (
            "長者使用語音對話功能時，容易因環境雜音或發音模糊造成系統誤判。"
            "本模組在畫面頂部彈出大字體半透明覆蓋層，即時渲染語音辨識文字，"
            "並提供顯眼的「確認送出」與「取消重說」雙按鈕，確保指令精準無誤後才派發至核心助理大腦。"
        ),
        "code_text": (
            "// 檔案來源: mobile_app/lib/screens/widgets/google_assistant_overlay.dart\n"
            "// 模組功能: 長者端語音指令即時辨識與確認彈窗覆蓋層\n"
            "class GoogleAssistantOverlay extends StatelessWidget { // 定義無狀態之語音覆蓋層元件\n"
            "  final String recognizedText; // 接收語音辨識引擎即時識別出之文字字串\n"
            "  final VoidCallback onConfirm; // 使用者點選確認送出時觸發之回呼函式\n"
            "  final VoidCallback onCancel; // 使用者點選取消重說時觸發之回呼函式\n"
            "\n"
            "  const GoogleAssistantOverlay({ // 建構函式並宣告必要參數\n"
            "    super.key, // 傳遞 Flutter 元件識別鍵\n"
            "    required this.recognizedText, // 綁定即時語音辨識文字內容\n"
            "    required this.onConfirm, // 綁定確認事件執行方法\n"
            "    required this.onCancel, // 綁定取消事件執行方法\n"
            "  }); // 建構函式宣告結束\n"
            "\n"
            "  @override // 覆寫介面渲染建構方法\n"
            "  Widget build(BuildContext context) { // 建構覆蓋層視覺樹\n"
            "    return Material( // 使用 Material 風格作為畫布底層\n"
            "      color: Colors.black.withOpacity(0.65), // 採用 65% 半透明黑色遮罩聚焦長者注意力\n"
            "      child: Center( // 將彈窗主體置中呈現於手機或平板螢幕中央\n"
            "        child: Container( // 建立高對比圓角提示卡片容器\n"
            "          margin: const EdgeInsets.symmetric(horizontal: 24), // 設定水平外距保持邊界餘裕\n"
            "          padding: const EdgeInsets.all(24), // 設定內部填充留白避免文字擁擠\n"
            "          decoration: BoxDecoration( // 裝飾提示卡片外觀\n"
            "            color: Colors.white, // 設定卡片底色為明亮純白確保文字對比度\n"
            "            borderRadius: BorderRadius.circular(24), // 設置 24 像素大圓角符合親和設計\n"
            "            boxShadow: [ // 加入柔和陰影增加介面層級景深感\n"
            "              BoxShadow( // 設定陰影參數\n"
            "                color: Colors.black.withOpacity(0.2), // 設定 20% 濃稠度之投影色彩\n"
            "                blurRadius: 16, // 設定高模糊半徑營造自然光暈效果\n"
            "                offset: const Offset(0, 8), // 陰影垂直下移 8 像素符合上方光源\n"
            "              ), // 陰影物件設定完畢\n"
            "            ], // 陰影清單設定結束\n"
            "          ), // 卡片容器裝飾設定完畢\n"
            "          child: Column( // 採用垂直線性排列展示內容與操作按鈕\n"
            "            mainAxisSize: MainAxisSize.min, // 依據內部元件大小自適應高度避免浪費空間\n"
            "            children: [ // 子元件清單\n"
            "              const Icon(Icons.mic, size: 56, color: Color(0xFF10B981)), // 展示 56 像素綠色麥克風圖示\n"
            "              const SizedBox(height: 16), // 垂直間隔 16 像素\n"
            "              const Text( // 展示標題提示文字\n"
            "                '我聽到的內容是：', // 提示標題字樣\n"
            "                style: TextStyle(fontSize: 20, color: Color(0xFF6B7280)), // 採用 20 點字體與中灰色調\n"
            "              ), // 提示文字結束\n"
            "              const SizedBox(height: 12), // 垂直間隔 12 像素\n"
            "              Text( // 展示辨識出之真實語音語句\n"
            "                recognizedText.isEmpty ? '正在聆聽您的聲音...' : recognizedText, // 若無文字顯示聆聽中提示\n"
            "                textAlign: TextAlign.center, // 文字水平置中對齊便於長者閱讀\n"
            "                style: const TextStyle( // 設置大字體辨識內容樣式\n"
            "                  fontSize: 26, // 採用 26 點特大字級提升銀髮閱讀舒適度\n"
            "                  fontWeight: FontWeight.bold, // 粗體強調重點字句\n"
            "                  color: Color(0xFF111827), // 採用深灰黑文字保證最大閱讀對比\n"
            "                ), // 文字樣式結束\n"
            "              ), // 內容文字展示結束\n"
            "              const SizedBox(height: 28), // 垂直間隔 28 像素分隔操作區塊\n"
            "              Row( // 水平排列雙按鈕操作列\n"
            "                children: [ // 按鈕列子項目\n"
            "                  Expanded( // 左側取消按鈕均分寬度\n"
            "                    child: OutlinedButton( // 採用外框線風格表示次要動作\n"
            "                      onPressed: onCancel, // 點擊綁定取消回呼方法\n"
            "                      style: OutlinedButton.styleFrom( // 設置外框按鈕樣式\n"
            "                        padding: const EdgeInsets.symmetric(vertical: 14), // 垂直高度 14 像素便於點擊\n"
            "                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), // 圓角外框\n"
            "                      ), // 按鈕樣式結束\n"
            "                      child: const Text('重說一次', style: TextStyle(fontSize: 18, color: Colors.grey)), // 按鈕標籤\n"
            "                    ), // 外框按鈕結束\n"
            "                  ), // 左側按鈕配置結束\n"
            "                  const SizedBox(width: 16), // 雙按鈕水平間距 16 像素防止長者誤觸\n"
            "                  Expanded( // 右側確認按鈕均分寬度\n"
            "                    child: ElevatedButton( // 採用實心按鈕表示主要送出動作\n"
            "                      onPressed: onConfirm, // 點擊綁定確認回呼方法\n"
            "                      style: ElevatedButton.styleFrom( // 設置實心按鈕樣式\n"
            "                        backgroundColor: const Color(0xFF10B981), // 設定清新守護綠為主色調\n"
            "                        padding: const EdgeInsets.symmetric(vertical: 14), // 垂直高度 14 像素便於長者大拇指操作\n"
            "                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), // 圓角外形\n"
            "                      ), // 按鈕樣式結束\n"
            "                      child: const Text('沒錯，送出', style: TextStyle(fontSize: 18, color: Colors.white)), // 標籤字樣\n"
            "                    ), // 實心按鈕結束\n"
            "                  ), // 右側按鈕配置結束\n"
            "                ], // 按鈕列清單結束\n"
            "              ), // 水平操作列結束\n"
            "            ], // 卡片內部元件結束\n"
            "          ), // 垂直排列排版結束\n"
            "        ), // 卡片容器結束\n"
            "      ), // 置中配置結束\n"
            "    ); // Material 畫布回傳結束\n"
            "  } // build 方法實作結束\n"
            "} // 元件類別定義結束"
        ),
    },
    {
        "table_id": "表 9-2-2",
        "title": "家屬端戶外 GPS 移動軌跡回溯與停留點標記演算法",
        "file_source": "E:/114Project/Uban/mobile_app/lib/screens/family/elder_location_map_screen.dart",
        "design_purpose": (
            "家屬外出時需要隨時掌握長輩戶外活動足跡。本模組自伺服器撈取長者一日定位座標，"
            "將經緯度數值即時繪製為折線軌跡，並對時空停留點進行聚類渲染，"
            "精準呈現長輩在公園、市場之停留時長，為防走失照護提供關鍵圖資。"
        ),
        "code_text": (
            "// 檔案來源: mobile_app/lib/screens/family/elder_location_map_screen.dart\n"
            "// 模組功能: 家屬端長者戶外 GPS 移動軌跡回溯與停留點標記渲染邏輯\n"
            "List<Marker> _buildStayMarkers(List<Map<String, dynamic>> stays) { // 建立停留點地圖標記清單函式\n"
            "  return stays.map((stay) { // 逐筆迭代由後端分析產出之停留點聚類物件\n"
            "    final lat = (stay['latitude'] as num).toDouble(); // 解析停留中心點之緯度數值\n"
            "    final lng = (stay['longitude'] as num).toDouble(); // 解析停留中心點之經度數值\n"
            "    final durationMin = stay['duration_minutes'] as int? ?? 0; // 取得在該地點之累積停留分鐘數\n"
            "    final placeName = stay['place_name'] as String? ?? '停留點'; // 取得逆地理編碼之地標名稱\n"
            "\n"
            "    return Marker( // 建立 OpenStreetMap 對應之地圖標記物件\n"
            "      point: LatLng(lat, lng), // 設定標記於地圖圖層之精確經緯度座標\n"
            "      width: 44.0, // 設定地圖圖示寬度為 44 像素確保點擊熱區充足\n"
            "      height: 44.0, // 設定地圖圖示高度為 44 像素維持正圓比例\n"
            "      child: GestureDetector( // 綁定手勢偵測器以支援點擊彈出說明\n"
            "        onTap: () { // 當家屬點擊該停留點圓標時觸發回呼\n"
            "          showDialog( // 彈出停留詳細資訊對話視窗\n"
            "            context: context, // 傳入當前介面建構上下文\n"
            "            builder: (_) => AlertDialog( // 建構對話視窗主體\n"
            "              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), // 16 像素圓角視窗\n"
            "              title: Text(placeName, style: const TextStyle(fontWeight: FontWeight.bold)), // 視窗標題\n"
            "              content: Text('長輩在此處停留約 $durationMin 分鐘。\\n抵達時間：${stay['arrival_time'] ?? \"未知\"}'), // 內文\n"
            "              actions: [ // 視窗操作按鈕列\n"
            "                TextButton( // 建立關閉按鈕\n"
            "                  onPressed: () => Navigator.pop(context), // 點擊關閉彈窗\n"
            "                  child: const Text('我知道了'), // 按鈕字樣\n"
            "                ), // 按鈕結束\n"
            "              ], // 操作清單結束\n"
            "            ), // 對話視窗建構結束\n"
            "          ); // showDialog 調用結束\n"
            "        }, // onTap 手勢處理完畢\n"
            "        child: Container( // 繪製停留點圓形視覺圖示容器\n"
            "          decoration: BoxDecoration( // 裝飾圓形圖示外觀\n"
            "            color: const Color(0xFF10B981).withOpacity(0.9), // 設定清新翠綠半透明底色代表安全停留\n"
            "            shape: BoxShape.circle, // 設置外觀為正圓形狀\n"
            "            border: Border.all(color: Colors.white, width: 2.5), // 描繪 2.5 像素純白邊框增強對比\n"
            "            boxShadow: const [ // 配置立體陰影提升層次\n"
            "              BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)), // 柔和陰影\n"
            "            ], // 陰影設定結束\n"
            "          ), // 裝飾設定完畢\n"
            "          child: Center( // 將停留分鐘數置中標註於圓形內部\n"
            "            child: Text( // 呈現數值標籤\n"
            "              '$durationMin分', // 顯示分鐘數簡記\n"
            "              style: const TextStyle( // 設置文字樣式\n"
            "                fontSize: 11, // 採用 11 點精巧字級\n"
            "                color: Colors.white, // 白色文字保證深色底圖對比度\n"
            "                fontWeight: FontWeight.bold, // 粗體強調數字\n"
            "              ), // 文字樣式結束\n"
            "            ), // 文字標籤結束\n"
            "          ), // 置中結束\n"
            "        ), // 圖示容器結束\n"
            "      ), // 手勢偵測結束\n"
            "    ); // Marker 物件回傳結束\n"
            "  }).toList(); // 將迭代結果轉換為 Marker 陣列清單回傳\n"
            "} // 函式定義結束"
        ),
    },
    {
        "table_id": "表 9-2-3",
        "title": "全雙工低延遲視訊信令連線與單例狀態維護機制",
        "file_source": "E:/114Project/Uban/mobile_app/lib/services/signaling.dart",
        "design_purpose": (
            "WebRTC 雙向視訊通話依賴信令協商 SDP 與交換 ICE Candidate。"
            "本模組以單例模式管理 Socket.IO 連線通道，嚴格防止多重通話執行個體競爭衝突，"
            "並在離線或伺服器中斷時自動執行退避重連，保障影音封包毫秒級即時通訊。"
        ),
        "code_text": (
            "// 檔案來源: mobile_app/lib/services/signaling.dart\n"
            "// 模組功能: WebRTC 雙向視訊通話信令通道與連線單例管理器\n"
            "class Signaling { // 定義全域唯一的信令服務管理類別\n"
            "  static final Signaling _instance = Signaling._internal(); // 宣告內部靜態單例執行個體\n"
            "  factory Signaling() => _instance; // 原廠建構函式統一回傳單例執行個體\n"
            "  Signaling._internal(); // 私有建構函式防止外部任意實體化\n"
            "\n"
            "  IO.Socket? socket; // 儲存 Socket.IO 客戶端長連線物件參照\n"
            "  RTCPeerConnection? peerConnection; // 儲存點對點 WebRTC 影音連線物件參照\n"
            "  bool _isConnecting = false; // 連線狀態防重入鎖定旗標\n"
            "\n"
            "  void initSocket(String serverUrl, String userToken) { // 初始化信令長連線方法\n"
            "    if (socket?.connected == true || _isConnecting) return; // 若已連線或正在連線中則防重複觸發退出\n"
            "    _isConnecting = true; // 啟動連線進行中鎖定狀態\n"
            "\n"
            "    socket = IO.io( // 建立與後端 FastAPI Socket.IO 伺服器之長連線\n"
            "      serverUrl, // 傳入通訊伺服器網址端點\n"
            "      IO.OptionBuilder() // 呼叫連線選項建構器\n"
            "          .setTransports(['websocket']) // 強制指定採用高效能 WebSocket 傳輸協定\n"
            "          .enableAutoConnect() // 啟用斷線自動重新連線機制\n"
            "          .setExtraHeaders({'Authorization': 'Bearer $userToken'}) // 攜帶 JWT 憑證通過連線安全驗證\n"
            "          .build(), // 完成選項建構\n"
            "    ); // Socket.IO 物件建立完畢\n"
            "\n"
            "    socket?.onConnect((_) { // 監聽連線建立成功事件\n"
            "      _isConnecting = false; // 解除連線中鎖定旗標\n"
            "      debugPrint('✅ [Signaling] 信令伺服器成功連線，ReadyState: CONNECTED'); // 印出成功日誌\n"
            "    }); // 監聽結束\n"
            "\n"
            "    socket?.on('call-offer', (data) async { // 監聽遠端發起之通話邀請事件\n"
            "      final String sdp = data['sdp']; // 解析對端傳遞之會話描述協定 SDP 內容\n"
            "      final String fromUser = data['from_user_id']; // 取得發話端使用者識別代碼\n"
            "      await _handleIncomingOffer(fromUser, sdp); // 進入內部非同步流程處理應答準備\n"
            "    }); // 監聽結束\n"
            "\n"
            "    socket?.on('ice-candidate', (data) { // 監聽對端交換之 ICE 網路候選路徑事件\n"
            "      final candidate = RTCIceCandidate( // 依據接收資料封裝原生 WebRTC 候選路徑物件\n"
            "        data['candidate'], // 候選位址資訊字串\n"
            "        data['sdpMid'], // 關聯之媒體串流標籤\n"
            "        data['sdpMLineIndex'], // 媒體描述行索引值\n"
            "      ); // 物件建構完畢\n"
            "      peerConnection?.addCandidate(candidate); // 將候選路徑加入本機點對點連線以完成打洞穿透\n"
            "    }); // 監聽結束\n"
            "  } // initSocket 函式實作完畢\n"
            "} // Signaling 類別宣告完畢"
        ),
    },
    {
        "table_id": "表 9-2-4",
        "title": "YOLOv8 姿態骨架辨識與跌倒警報派發機制",
        "file_source": "E:/114Project/uban-api/yolo_alert_dispatcher.py",
        "design_purpose": (
            "邊緣攝影機偵測到人體骨架急遽傾倒且軀幹中心高度驟降時，判定為跌倒事件。"
            "本模組負責驗證警報真實性、防止重複誤報、非同步寫入資料庫日誌，"
            "並透過 Firebase Cloud Messaging 第一時間向家屬手機推送高優先權警報訊息與抓拍影像。"
        ),
        "code_text": (
            "# 檔案來源: uban-api/yolo_alert_dispatcher.py\n"
            "# 模組功能: YOLO 人體姿態骨架跌倒事件判定與 FCM 高優先權警報派發器\n"
            "import time # 匯入系統時間處理模組\n"
            "import logging # 匯入日誌記錄模組\n"
            "from database import get_db_context # 匯入資料庫連線上下文管理器\n"
            "from services.fcm_service import send_urgent_push # 匯入 FCM 緊急推播發送服務\n"
            "\n"
            "logger = logging.getLogger('YoloAlertDispatcher') # 初始化警報派發專用日誌記錄器\n"
            "\n"
            "class YoloAlertDispatcher: # 定義跌倒警報派發器核心類別\n"
            "    def __init__(self, debounce_seconds: int = 15): # 建構函式並設定防抖時間門檻為 15 秒\n"
            "        self.debounce_seconds = debounce_seconds # 記錄防抖時間以防止同一事件短時間重複派發\n"
            "        self._last_alert_time = {} # 記錄各長者最近發布警報時間戳記之雜湊對應表\n"
            "\n"
            "    async def dispatch_fall_event(self, elder_id: int, camera_id: str, snapshot_path: str, confidence: float): # 派發跌倒事件非同步函式\n"
            "        current_time = time.time() # 取得當前時間戳記\n"
            "        last_time = self._last_alert_time.get(elder_id, 0) # 查詢該長者上次觸發警報之時間\n"
            "\n"
            "        if current_time - last_time < self.debounce_seconds: # 比對是否在防抖抑制冷卻期內\n"
            "            logger.info(f'長者 {elder_id} 跌倒警報處於冷卻抑制狀態，略過重複派送') # 記錄日誌\n"
            "            return False # 抑制派發直接回傳失敗\n"
            "\n"
            "        self._last_alert_time[elder_id] = current_time # 更新該長者最新警報派發時間點\n"
            "        logger.warning(f'⚠️ [緊急] 偵測到長者 {elder_id} 跌倒！攝影機: {camera_id}, 置信度: {confidence:.2f}') # 輸出警告\n"
            "\n"
            "        async with get_db_context() as session: # 進入非同步資料庫操作上下文\n"
            "            alert_record = await session.create_alert_log( # 將異常事件寫入警報紀錄資料表\n"
            "                elder_id=elder_id, # 綁定受害長者編號\n"
            "                alert_type='fall_detected', # 標註警報類別為跌倒偵測事件\n"
            "                severity='critical', # 設置威脅嚴重度為最高等級 critical\n"
            "                device_name=camera_id, # 標註觸發警報之監控鏡頭名稱\n"
            "                snapshot_url=snapshot_path, # 儲存現場現場抓拍照片之檔案路徑\n"
            "                is_processed=False # 初始標記為未處理狀態待家屬確認\n"
            "            ) # 資料庫寫入完畢\n"
            "\n"
            "        # 透過 FCM 向全體綁定家屬發送最高優先權喚醒通知\n"
            "        await send_urgent_push( # 呼叫緊急推播函式\n"
            "            elder_id=elder_id, # 指定目標長者關聯之家屬清單\n"
            "            title='🚨 緊急跌倒警報通知', # 推播大標題\n"
            "            body=f'AI 監控設備偵測到長者在 {camera_id} 疑似跌倒，請立即確認！', # 推播內文\n"
            "            data={'alert_id': str(alert_record.id), 'type': 'fall', 'img': snapshot_path} # 附帶資料\n"
            "        ) # 推播發送完畢\n"
            "        return True # 派發成功回傳 True"
        ),
    },
    {
        "table_id": "表 9-2-5",
        "title": "空間多邊形射線室內區域定位判定機制",
        "file_source": "E:/114Project/uban-api/indoor_position.py",
        "design_purpose": (
            "為了讓遠端家屬確切知曉長者在家中哪一個房間活動，本系統拋棄穿戴式藍牙定位標籤，"
            "改採視覺幾何定位演算法。依據人體框底部中心提取腳底二維座標，利用射線交集法"
            "判定該點位於客廳、臥室或走廊等自訂凸/凹多邊形室內空間內部，計算極為精確高效。"
        ),
        "code_text": (
            "# 檔案來源: uban-api/indoor_position.py\n"
            "# 模組功能: 腳底空間座標射線法室內區域多邊形定位計算引擎\n"
            "from typing import List, Tuple, Optional, Dict # 匯入靜態型別標註工具\n"
            "\n"
            "class IndoorPositionService: # 定義室內空間幾何定位服務類別\n"
            "    @staticmethod # 宣告為靜態方法以提供純函式幾何運算\n"
            "    def is_point_in_polygon(point: Tuple[float, float], polygon: List[Tuple[float, float]]) -> bool: # 射線判定函式\n"
            "        x, y = point # 解構長者腳底接觸點之 (X, Y) 座標\n"
            "        n = len(polygon) # 取得房間幾何多邊形頂點總數\n"
            "        inside = False # 初始預設交集狀態為外部 False\n"
            "\n"
            "        p1_x, p1_y = polygon[0] # 取出多邊形起始邊的第一個端點座標\n"
            "        for i in range(1, n + 1): # 逐一歷遍多邊形的所有封閉線段\n"
            "            p2_x, p2_y = polygon[i % n] # 取出該線段的第二個端點座標（循環索引）\n"
            "            # 判定測試點之 Y 座標是否落在線段垂直跨度範圍內\n"
            "            if min(p1_y, p2_y) < y <= max(p1_y, p2_y): # 垂直區間交集檢查\n"
            "                # 計算水平向右射線與該線段交點之 X 座標\n"
            "                if p1_y != p2_y: # 排除水平線除以零之邊界條件\n"
            "                    x_inters = (y - p1_y) * (p2_x - p1_x) / (p2_y - p1_y) + p1_x # 計算交點橫座標\n"
            "                    if p1_x == p2_x or x <= x_inters: # 測試點位於交點左側\n"
            "                        inside = not inside # 每交會一條邊則翻轉奇偶狀態\n"
            "            p1_x, p1_y = p2_x, p2_y # 將端點前進推進至下一個頂點\n"
            "        return inside # 回傳最終奇偶判定結果（奇數為內部 True，偶數為外部 False）\n"
            "\n"
            "    @classmethod # 宣告為類別方法\n"
            "    def locate_elder_room(cls, foot_coord: Tuple[float, float], room_configs: Dict[str, List[Tuple[float, float]]]) -> Optional[str]: # 房間定位查詢函式\n"
            "        for room_name, polygon in room_configs.items(): # 逐一比對各房間之幾何多邊形定義\n"
            "            if cls.is_point_in_polygon(foot_coord, polygon): # 若腳底點落在該房間多邊形內\n"
            "                return room_name # 即時回傳長者所在房間名稱（例如：客廳、臥室）\n"
            "        return '走道或未知區域' # 若所有預定義房間皆不吻合則回傳過渡區域"
        ),
    },
    {
        "table_id": "表 9-2-6",
        "title": "Google Gemini 長者日常陪伴對話與意圖理解服務",
        "file_source": "E:/114Project/uban-api/gemini_service.py",
        "design_purpose": (
            "長者日常陪伴需要具備高度親和力與共情能力。本模組介接 Google Gemini 模型，"
            "注入銀髮對話系統提示詞，支援時間與天氣等日常生活工具調用，"
            "並在長者聊起過往人生經歷時自動標記回憶錄關鍵字，提供溫暖且不中斷的陪伴互動。"
        ),
        "code_text": (
            "# 檔案來源: uban-api/gemini_service.py\n"
            "# 模組功能: Google Gemini 長者情感陪伴對話引擎與生活工具自動呼叫服務\n"
            "import os # 匯入作業系統模組讀取環境變數\n"
            "import google.generativeai as genai # 匯入 Google Gemini 官方 SDK\n"
            "from typing import Dict, Any # 匯入型別標註工具\n"
            "\n"
            "GEMINI_API_KEY = os.getenv('GEMINI_API_KEY', '') # 自環境變數讀取 Gemini 金鑰\n"
            "genai.configure(api_key=GEMINI_API_KEY) # 初始化 Gemini 服務連線授權\n"
            "\n"
            "ELDER_COMPANION_PROMPT = ''' # 定義長者陪伴專屬系統提示詞\n"
            "你是一位親切、有耐心且富有同理心的銀髮陪伴小助理「小嘎」。\n"
            "請遵守以下溝通準則：\n"
            "1. 始終使用溫暖親切的台灣繁體中文與長輩交談，尊稱對方為阿公或阿嬤。\n"
            "2. 回覆語氣放慢，句子簡潔易懂，一次只表達一個核心概念，不使用艱澀英文術語。\n"
            "3. 當長輩詢問天氣、時間或日期時，請準確回答並提醒保暖防寒或多喝水。\n"
            "4. 聆聽長輩講述童年或往事時，給予真誠的讚許與提問，鼓勵長輩繼續分享。\n"
            "''' # 系統提示詞定義結束\n"
            "\n"
            "class GeminiCompanionService: # 定義陪伴服務管理類別\n"
            "    def __init__(self, model_name: str = 'gemini-2.5-flash'): # 建構函式指定採用高響應模型\n"
            "        self.model = genai.GenerativeModel( # 初始化 GenerativeModel 執行個體\n"
            "            model_name=model_name, # 載入指定之高效能 Flash 系列模型\n"
            "            system_instruction=ELDER_COMPANION_PROMPT # 注入長者友善之系統提示詞約束行為\n"
            "        ) # 模型建構完畢\n"
            "\n"
            "    async def chat_with_elder(self, elder_name: str, message: str, history: list) -> str: # 非同步長者對話處理方法\n"
            "        try: # 進入保護性例外處理區塊\n"
            "            chat_session = self.model.start_chat(history=history) # 依據歷史對話紀錄建立會話工作階段\n"
            "            response = await chat_session.send_message_async(message) # 非同步發送長者提問內容至雲端大腦\n"
            "            clean_reply = response.text.strip().replace('*', '') # 清理模型輸出之 Markdown 星號標記\n"
            "            return clean_reply # 回傳純文字溫馨朗讀內容\n"
            "        except Exception as e: # 攔截網路逾時或配額超量等外部異常\n"
            "            return f'{elder_name}，小嘎剛才稍微分心了，您可以再說一次嗎？' # 提供柔性備援回覆"
        ),
    },
    {
        "table_id": "表 9-2-7",
        "title": "長者戶外移動安全警戒與異常滯留提醒機制",
        "file_source": "E:/114Project/uban-api/location_alert_watch.py",
        "design_purpose": (
            "長輩單獨外出散步時，可能因迷途或身體突發狀況於偏僻處停留過久。"
            "本排程服務每 5 分鐘掃描受守護長者之 GPS 移動軌跡，檢測夜間逗留、"
            "活動範圍異常與長時間未位移等危險徵兆，並在達到門檻時主動向家屬通報以防範走失憾事。"
        ),
        "code_text": (
            "# 檔案來源: uban-api/location_alert_watch.py\n"
            "# 模組功能: 長者戶外 GPS 定位異常滯留與安全警戒主動巡檢排程\n"
            "import datetime # 匯入日期時間處理模組\n"
            "from typing import List, Dict # 匯入資料結構型別\n"
            "from database import get_db_context # 匯入資料庫連線上下文\n"
            "from services.fcm_service import send_urgent_push # 匯入推播通知服務\n"
            "\n"
            "class LocationAlertWatchService: # 定義戶外移動安全警戒巡檢服務類別\n"
            "    def __init__(self, stay_threshold_minutes: int = 40): # 建構函式並設定單一停留點警戒時限為 40 分鐘\n"
            "        self.stay_threshold_minutes = stay_threshold_minutes # 儲存警戒閥值設定\n"
            "\n"
            "    async def inspect_elder_stay(self, elder_id: int, current_stay: Dict[str, any]): # 檢視長者當前停留狀態函式\n"
            "        duration = current_stay.get('duration_minutes', 0) # 取得長者在該座標點已停留之累計分鐘數\n"
            "        place_name = current_stay.get('place_name', '戶外區域') # 取得地標名稱（例如：河濱公園、巷口）\n"
            "        is_night = datetime.datetime.now().hour >= 21 or datetime.datetime.now().hour <= 5 # 判定是否為夜間時段\n"
            "\n"
            "        # 判定條件：白天停留超過 40 分鐘，或深夜時段在外停留超過 15 分鐘\n"
            "        threshold = 15 if is_night else self.stay_threshold_minutes # 依時段自適應調整警戒時限\n"
            "        if duration >= threshold: # 判定是否已超越安全門檻\n"
            "            async with get_db_context() as session: # 開啟資料庫交易處理日誌記錄\n"
            "                await session.create_alert_log( # 於警報日誌表建立戶外異常滯留紀錄\n"
            "                    elder_id=elder_id, # 關聯目標長者編號\n"
            "                    alert_type='outdoor_abnormal_stay', # 註記警報類型為戶外異常滯留\n"
            "                    severity='warning' if not is_night else 'critical', # 夜間提升為緊急等級\n"
            "                    device_name='GPS 定位服務', # 標註來源為行動端 GPS 感測\n"
            "                    message=f'長輩在【{place_name}】停留已達 {duration} 分鐘，請確認是否需要協助。', # 詳細說明\n"
            "                    is_processed=False # 標記為未處理狀態\n"
            "                ) # 資料庫寫入完畢\n"
            "\n"
            "            # 發送推播通知家屬及時關心長輩狀況\n"
            "            await send_urgent_push( # 呼叫推播函式\n"
            "                elder_id=elder_id, # 指定家屬受眾\n"
            "                title='⚠️ 長者戶外停留時間提醒', # 標題\n"
            "                body=f'長輩在【{place_name}】已停留 {duration} 分鐘，建議致電關心近況。' # 內文說明\n"
            "            ) # 推播完成\n"
            "            return True # 成功觸發警戒\n"
            "        return False # 未達門檻正常巡航"
        ),
    },
    {
        "table_id": "表 9-2-8",
        "title": "長者與家屬端 4 位數專屬配對碼防衝突綁定機制",
        "file_source": "E:/114Project/uban-api/routers/pairing.py",
        "design_purpose": (
            "長輩與家屬之設備繫結必須兼顧簡便與安全性。本模組在長者端產生直覺好記之 4 位數字專屬配對碼，"
            "於後端採用原子操作與 15 分鐘生命週期管理，並設置防併發搶佔鎖，"
            "在保障資訊安全的同時徹底杜絕競態衝突與配對混亂。"
        ),
        "code_text": (
            "# 檔案來源: uban-api/routers/pairing.py\n"
            "# 模組功能: 長者與家屬端 4 位數專屬配對安全碼產生、時效驗證與防衝突綁定路由\n"
            "import random # 匯入隨機數產生器模組\n"
            "import time # 匯入系統時間處理模組\n"
            "from fastapi import APIRouter, HTTPException, Depends # 匯入 FastAPI 路由元件與例外工具\n"
            "from database import get_db, PairingCodeRecord # 匯入資料庫依賴與配對紀錄模型\n"
            "from sqlalchemy.ext.asyncio import AsyncSession # 匯入非同步資料庫會話型別\n"
            "from sqlalchemy import select # 匯入 SQL 查詢建構式\n"
            "\n"
            "router = APIRouter(prefix='/api/pairing', tags=['Pairing']) # 定義配對模組專屬 API 路由前綴\n"
            "\n"
            "@router.post('/generate-code') # 定義產生 4 位數配對碼之 POST 端點\n"
            "async def generate_pairing_code(elder_id: int, db: AsyncSession = Depends(get_db)): # 配對碼生成函式\n"
            "    # 產生 1000 ~ 9999 範圍內之 4 位數專屬隨機數字碼\n"
            "    code = str(random.randint(1000, 9999)) # 隨機抽取 4 位數代碼\n"
            "    expire_at = int(time.time()) + 900 # 設定有效期間為 15 分鐘（900 秒）\n"
            "\n"
            "    # 寫入或更新該長者之待配對快取記錄\n"
            "    record = PairingCodeRecord(elder_id=elder_id, pairing_code=code, expire_at=expire_at) # 封裝紀錄物件\n"
            "    await db.merge(record) # 使用 merge 執行原子合併寫入防止重複鍵例外\n"
            "    await db.commit() # 提交交易將配對碼持久化至資料庫\n"
            "\n"
            "    return {'status': 'success', 'code': code, 'expire_seconds': 900} # 回傳配對代碼與倒數秒數\n"
            "\n"
            "@router.post('/verify-and-bind') # 定義家屬端驗證配對碼並完成綁定之 POST 端點\n"
            "async def verify_and_bind(caregiver_id: int, input_code: str, db: AsyncSession = Depends(get_db)): # 驗證函式\n"
            "    current_ts = int(time.time()) # 取得當前時間戳記\n"
            "    query = select(PairingCodeRecord).where( # 建構查詢符合配對碼之資料庫語法\n"
            "        PairingCodeRecord.pairing_code == input_code, # 嚴格比對輸入之 4 位數字代碼\n"
            "        PairingCodeRecord.expire_at > current_ts # 驗證有效期限必須大於當前時間戳記\n"
            "    ).with_for_update() # 套用行級悲觀鎖防止多個家屬裝置併發搶佔\n"
            "\n"
            "    result = await db.execute(query) # 執行鎖定查詢語法\n"
            "    pairing = result.scalar_one_or_none() # 取得第一筆配對紀錄或空值\n"
            "\n"
            "    if not pairing: # 若查無有效紀錄或已過期\n"
            "        raise HTTPException(status_code=400, detail='配對碼不存在、輸入錯誤或已逾時失效') # 拋出 400 錯誤\n"
            "\n"
            "    # 建立家屬與長者之雙向家庭照護關聯紀錄\n"
            "    await db.create_family_relation(caregiver_id=caregiver_id, elder_id=pairing.elder_id) # 建立關聯\n"
            "    await db.delete(pairing) # 綁定成功後立即刪除該配對碼，徹底杜絕二次重複使用\n"
            "    await db.commit() # 提交事務完成全套原子綁定\n"
            "\n"
            "    return {'status': 'success', 'elder_id': pairing.elder_id, 'message': '家庭守護關係已順利建立'}"
        ),
    },
]

# ==============================================================================
# 9-3 核心相依套件清單
# ==============================================================================

DEPENDENCIES_FLUTTER = [
    ("flutter", "SDK 3.29.0+", "Google 原生跨平台 UI 框架，支援 Android/iOS/Web 高效能渲染。"),
    ("google_fonts", "^8.0.2", "Google 字型庫支援，提供清晰易讀之 Noto Sans TC 與 Inter 字型。"),
    ("flutter_webrtc", "^1.3.1", "WebRTC 跨平台即時影音通訊外掛，支援硬體加速點對點雙向視訊串流。"),
    ("socket_io_client", "^3.1.4", "Socket.IO 客戶端通訊函式庫，負責長連線全雙工信令傳遞與事件廣播。"),
    ("firebase_core", "^4.5.0", "Firebase 核心基礎套件，管理雲端服務組態與生命週期。"),
    ("firebase_messaging", "^16.1.2", "Firebase 雲端推播套件，支援背景高優先權緊急求救通知接收。"),
    ("flutter_local_notifications", "^18.0.1", "原生高優先權通知外掛，在不同 Android 品牌手機上提供穩定喚醒備援。"),
    ("geolocator", "^14.0.2", "GPS 衛星定位套件，取得精確經緯度座標與移動速度資訊。"),
    ("flutter_map", "^8.2.2", "開源地圖元件，無縫整合 OpenStreetMap 免授權圖資與折線標記渲染。"),
    ("pedometer", "^4.2.0", "硬體計步感測器連線外掛，取得長者日常步行步數供小豬能量轉換。"),
    ("flutter_tts", "^4.2.2", "原生文字轉語音合成引擎，朗讀每日要聞與生活農民曆指引。"),
    ("shared_preferences", "^2.5.4", "本機鍵值快取持久化套件，儲存登入憑證、角色狀態與介面設定。"),
]

DEPENDENCIES_BACKEND = [
    ("fastapi", "^0.115.0", "現代化高效能非同步 Python Web 框架，具備自動 OpenAPI 文件產製功能。"),
    ("python-socketio", "^5.12.0", "Python Socket.IO 非同步通訊套件，管理長連線工作階段與信令交換。"),
    ("google-generativeai", "^0.8.0", "Google Gemini 官方 SDK，提供對話意圖分析與自傳回憶錄萃取服務。"),
    ("ultralytics", "^8.3.0", "YOLOv8 深度學習框架，執行人體 17 個關節點骨架姿態推論與跌倒判定。"),
    ("sqlalchemy", "^2.0.30", "Python ORM 資料庫對映工具，支援非同步 async/await 與連線池管理。"),
    ("firebase-admin", "^6.5.0", "Firebase 管理者端 SDK，向家屬手機派發 FCM 最高優先權推播警報。"),
    ("pydantic", "^2.9.0", "資料結構模型驗證與型別轉換工具，保障 API 輸入與輸出資料完整性。"),
    ("shapely", "^2.0.6", "計算幾何運算套件，提供多邊形射線交集運算與室內空間拓撲判斷。"),
    ("uvicorn", "^0.30.0", "ASGI 非同步網頁伺服器，負責運行 FastAPI 與高併發 Socket.IO 連線池。"),
]

DEPENDENCIES_ADMIN = [
    ("react", "^18.3.1", "前端宣告式元件化使用者介面建構庫，提供流暢的 SPA 互動體驗。"),
    ("typescript", "^5.5.0", "微軟強型別 JavaScript 超集合，強化系統架構強健度並杜絕型別錯誤。"),
    ("vite", "^5.4.0", "新一代極速前端建置工具，提供熱模組替換與最佳化打包流程。"),
    ("lucide-react", "^0.430.0", "精美一致的向量圖示元件庫，提供現代化儀表板視覺圖形。"),
    ("echarts", "^5.5.0", "企業級視覺化圖表引擎，繪製長者活動力趨勢圖與室內房間停留熱點比例。"),
    ("tailwindcss", "^3.4.0", "原子化實用 CSS 框架，建構一致性高且響應式良好之後台管理介面。"),
]

# ==============================================================================
# 9-4 外部整合 API 服務清單
# ==============================================================================

EXTERNAL_API_LIST = [
    ("Google Gemini 2.5 Flash API", "HTTPS / REST", "提供長者端雙語日常陪伴對話、生活工具意圖調用以及數位人生回憶錄自傳章節智慧萃取。"),
    ("Firebase Cloud Messaging (FCM)", "HTTP/2 / TLS", "發送最高優先權緊急警報通知，在手機鎖屏休眠狀態下強制喚醒發出蜂鳴與震動。"),
    ("OpenStreetMap Tile Server", "HTTPS / WMS", "提供免 API Key 之全球開放圖資瓦片圖層，支援家屬端長者戶外移動軌跡與停留點回溯。"),
    ("Open-Meteo Weather API", "HTTPS / JSON", "依據長者居住行政區座標，提供無廣告限制之即時氣溫、降雨機率與節氣生活指數。"),
    ("Tailscale Secure Overlay VPN", "WireGuard 協定", "建立邊緣攝影機、FastAPI 伺服器與開發者環境之加密虛擬專網，確保串流絕對安全。"),
]
