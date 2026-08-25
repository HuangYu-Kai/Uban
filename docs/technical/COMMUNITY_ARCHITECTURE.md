# 家庭親友圈社群時光牆 (Community Wall) 技術設計與實作紀錄
* 建立日期：2026-08-24
* 最近更新：2026-08-24
* 適用版本：v2.4.0
* 負責組件：[前端/後端/資料庫]

---

## ❶ 元數據 (Metadata Header)
* **功能名稱**：長輩與家庭生活社群時光牆（雙向動態與照片分享）
* **前後端存放路徑**：
  * 前端模型：[`mobile_app/lib/models/community_post.dart`](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/models/community_post.dart)
  * 前端服務：[`mobile_app/lib/services/community_service.dart`](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/services/community_service.dart)、[`mobile_app/lib/services/api_service.dart`](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/services/api_service.dart)
  * 前端頁面：[`mobile_app/lib/screens/elder_community_screen.dart`](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/elder_community_screen.dart)、[`mobile_app/lib/screens/family/family_interaction_tab.dart`](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/family/family_interaction_tab.dart)
  * 後端路由：[`Uban-api/routers/community.py`](file:///c:/Users/tung0/Desktop/Uban/Uban-api/routers/community.py)
  * 資料庫定義：[`Uban-api/database.py`](file:///c:/Users/tung0/Desktop/Uban/Uban-api/database.py)

---

## ❷ 功能背景與設計初衷 (Objectives & Background)

### 痛點與挑戰
1. **長輩日常傾訴管道單一**：過去長輩僅能透過被動的視訊通話或 AI 聊天表達情緒，缺乏隨手記錄「今天散步看到花開」、「今天煮了美味好料」等生活微碎事的非同步家庭動態管道。
2. **家屬難以即時給予情感正反饋**：子女平時工作忙碌無法長時間視訊，需要一個「一鍵送關心 ❤️」、「傳張工作午餐/孫子生活照」的輕量互動橋樑。
3. **銀髮族無障礙與隱私考量**：公眾社群（如 Facebook/IG）介面繁雜且長輩易產生個資或陌生人詐騙焦慮。Uban 堅持**「封閉式家庭親友圈」**原則，只允許配對成功的家庭成員與特定熟人彼此可見。

---

## ❸ 系統架構與資料流向 (System Architecture & Data Flow)

### 3.1 架構拓撲與雙軌交互

```mermaid
flowchart TD
    subgraph Clients ["📱 用戶端 App"]
        ElderApp["👵 長輩端 App<br/>(導覽列第 3 頁 [社群])"]
        FamilyApp["👨‍👩‍👧 家屬端 App<br/>(互動分頁 [家庭生活時光牆])"]
    end

    subgraph Backend ["⚡ FastAPI 後端服務 (Port 8000)"]
        Router["Community Router<br/>(/api/community/*)"]
        UploadHandler["Multipart 圖片處理<br/>(/uploads/community/)"]
        FamilyResolver["智慧親屬關聯解析器<br/>(Family Elder Resolver)"]
    end

    subgraph Storage ["💾 資料儲存層"]
        MySQL[("MySQL / SQLite<br/>community_posts<br/>community_comments<br/>community_post_likes")]
        StaticFiles[("本機靜態目錄<br/>/uploads/community/*.png")]
    end

    ElderApp -->|GET /posts?user_id=X| Router
    ElderApp -->|POST /upload 拍照上傳| UploadHandler
    ElderApp -->|POST /posts 發送心情| Router

    FamilyApp -->|GET /posts?user_id=Y| Router
    FamilyApp -->|POST /posts/{id}/like 點讚關心| Router
    FamilyApp -->|POST /posts/{id}/comments 回覆留言| Router

    Router --> FamilyResolver
    FamilyResolver --> MySQL
    UploadHandler --> StaticFiles
```

### 3.2 REST API 傳輸規格

| 路由 | 方法 | 用途 | 請求主體 (Payload) | 回傳資料 (Data) |
|---|---|---|---|---|
| `/api/community/posts` | `GET` | 查詢家庭生活貼文 | Query: `user_id`, `family_id`, `limit` | 貼文陣列（含留言陣列與 `is_liked` 狀態） |
| `/api/community/posts` | `POST` | 發佈新近況貼文 | `PostCreate` (JSON) | `{ id, message, created_at }` |
| `/api/community/posts/{id}/like` | `POST` | 切換關心 ❤️ 狀態 | `LikeToggleRequest` (JSON) | `{ post_id, is_liked, like_count }` |
| `/api/community/posts/{id}/comments` | `POST` | 新增貼文留言 | `CommentCreate` (JSON) | 留言物件（含 `id`, `created_at`） |
| `/api/community/upload` | `POST` | 上傳生活照片 | Multipart File (`image/*`) | `{ url, filename, size }` |

---

## ❹ 代碼修改與路徑定義 (Implementation & File References)

### 4.1 資料庫表結構 (Database Schema)

* **`community_posts` 表**：
```sql
CREATE TABLE IF NOT EXISTS community_posts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    family_id INT NOT NULL,
    author_id INT NOT NULL,
    author_name VARCHAR(100) NOT NULL,
    author_role VARCHAR(20) NOT NULL,
    content TEXT NOT NULL,
    mood VARCHAR(20) DEFAULT '😊',
    image_url VARCHAR(500) DEFAULT NULL,
    like_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

* **`community_comments` 表**：
```sql
CREATE TABLE IF NOT EXISTS community_comments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    post_id INT NOT NULL,
    author_id INT NOT NULL,
    author_name VARCHAR(100) NOT NULL,
    author_role VARCHAR(20) NOT NULL,
    message TEXT NOT NULL,
    image_url VARCHAR(500) DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

* **`community_post_likes` 表**：
```sql
CREATE TABLE IF NOT EXISTS community_post_likes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    post_id INT NOT NULL,
    user_id INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_post_user (post_id, user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

---

## ❺ 核心演算法與親屬解析邏輯 (Core Mathematical Models & Logic)

### 自動親屬圈動態關聯演算法 (Family Resolution Algorithm)

為減輕前端傳參負擔並保證長輩與家屬永遠看到所屬家庭的貼文，後端採用**「動態雙向親屬集合解析」**：

$$S_{\text{family}} = \{ \text{family\_id} \} \cup \{ \text{family\_id} \mid (\text{elder\_id} = U \lor \text{family\_id} = U) \in \text{family\_elder\_relationship} \}$$

查詢條件為：
$$\text{Query} = (\text{family\_id} \in S_{\text{family}}) \lor (\text{author\_id} = U)$$

確保即使未傳遞 `family_id`，系統亦能透過長輩或家屬之登入 `user_id` $U$，在 $O(1)$ 時間內即時拉取家庭親友圈所有成員之生活動態。

---

## ❻ UI/UX 視覺美學與無障礙規範 (Aesthetics & Accessibility)

1. **適老化大字體排版**：
   - 貼文內文：`ElderScale.title` (24pt, 粗體黑字，行高 1.45)。
   - 快捷心情標籤：大尺寸 Emoji (34pt) + 觸覺震動。
   - 快捷常用短句：「今天吃飽了 🍲」、「去公園散步 🌳」、「天氣真好 ☀️」、「想念大家 💕」。
2. **雙角色視覺識別**：
   - 長輩身份徽章：翠綠色底 + `🌿 長輩`。
   - 家人身份徽章：粉紅色底 + `💖 家人`。
3. **無障礙高對比操作**：
   - 「關心 ❤️」大膠囊按鈕：寬敞點擊熱區（高度 48dp+），未點讚為淡灰底、已點讚切換為活力深紅粉底與彈跳微動畫。

---

## ❼ 安全性防護與離線韌性 (Safety & Debouncing)

1. **混合雙模持久化 (Hybrid Fallback Cache)**：
   - 聯網時：優先同步請求後端 MySQL / SQLite，並將最新 50 則貼文異步快取於 `SharedPreferences`。
   - 離線/弱網時：無縫退守本機快取渲染，發文支援本地預寫，聯網後自動更新。
2. **唯一性防重按機制**：
   - `community_post_likes` 設有 `UNIQUE KEY (post_id, user_id)`，資料庫層級保證同一使用者不可重複刷讚。

---

## ❽ 測試與驗證計畫 (Test Plan & Checklist)

- [x] **後端端點測試**：`python scratch/test_community_backend.py`（6 項 API 全數 200 OK 通過）。
- [x] **前端代碼靜態分析**：`dart analyze` 檢查 0 errors / 0 warnings。
- [x] **單元測試套件**：`flutter test`（36 項測試全數通過）。
- [x] **實機 MySQL 寫入測試**：真實用戶 (User 1 金水阿公 & User 2 志明) 貼文、按讚與留言即時連線測試通過。
