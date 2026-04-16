# CLAUDE.md — Uban 專案開發指引 (Flutter 前端)

> 本文件供 Claude / Anthropic AI 助手閱讀，用於理解 Uban 專案的架構與開發約束。

## 專案概述
Uban 是一套 AI 跨世代感知照護系統，包含 Flutter 行動端（本 Repo）與 FastAPI 後端（`uban-api/` 獨立 Repo）。

## 第一步：閱讀 README.md
在進行任何修改前，**必須閱讀 `README.md`** 以了解完整架構。

---

## 架構定義

```
Flutter App (本 Repo)
├── lib/services/signaling.dart   ← WebRTC + Socket.IO 信令 (Singleton)
├── lib/services/api_service.dart ← REST API 呼叫
├── lib/main.dart                 ← App 入口 + FCM + CallKit
├── lib/globals.dart              ← 全域狀態 (pendingAcceptedCall)
├── lib/screens/elder_screen.dart ← 長輩端通話
├── lib/screens/video_call_screen.dart ← 家屬端通話
└── lib/screens/family_main_screen.dart ← 家屬主畫面

FastAPI 後端 (uban-api/ 獨立 Repo)
├── main.py                       ← FastAPI 入口 + Socket.IO ASGI
├── services/socket_app.py        ← 信令轉發伺服器
└── services/ollama_service.py    ← AI 引擎 (Gemma 4)
```

## 絕對禁止 (Hard Rules)

1. **不要硬編碼 IP** — 使用 `--dart-define=SERVER_IP=`
2. **Signaling 必須 Singleton** — 不要 `Signaling()` 多次初始化
3. **長輩端不直接用 VideoCallScreen** — 長輩端通話入口是 `ElderScreen`
4. **不要在 openUserMedia 之前 createOffer** — 必須先拿到 localStream
5. **ICE Candidate 必須排隊** — 在 `setRemoteDescription` 完成前收到的 candidate 必須排隊，完成後再 flush

## WebRTC 通話流程 (Critical)

```
家屬發起通話:
  1. 家屬 emit('call-request')
  2. 長輩收到 → CallKit 彈出來電
  3. 長輩接聽 → emit('call-accept', {accepterId: 自己的socketId})
  4. 家屬收到 call-accept → createOffer(targetId: 長輩的socketId)  ← 唯一 Offer 入口
  5. 長輩收到 offer → setRemoteDescription → 立即 flush 排隊的 ICE candidates → createAnswer → emit('answer')
  6. 雙方交換 ice-candidate（尚未 setRemoteDescription 的一方需排隊）
  7. 家屬收到 answer → setRemoteDescription → flush 排隊的 ICE candidates
  8. P2P 建立

長輩發起通話:
  1. 長輩 emit('call-request', {role: 'elder'})
  2. 家屬收到 → Dialog 彈出
  3. 家屬接聽 → emit('call-accept')
  4. 長輩收到 call-accept → createOffer(targetId: 家屬的socketId)
  5. 後續同上

⚠️ 重要：ICE candidate 是異步產生的，可能在 setRemoteDescription 之前到達。
   必須用 queue 機制暫存，否則 addIceCandidate 會失敗導致遠端影像黑屏。
```

## 雙軌制架構 (Critical)

> ⚠️ 信令與媒體伺服器在不同主機上，**禁止合併**。

| 軌道 | 用途 | 主機 | 協定 |
|------|------|------|------|
| 第一軌：信令 | SDP/ICE 文字交換 | Tailscale Funnel → 本地 Fedora | TCP/WSS |
| 第二軌：媒體 | 影音串流中繼 | Oracle Cloud (日本大阪) | UDP |

**原因**：Tailscale Funnel 免費提供 HTTPS（開鏡頭必須），但不支援 UDP（影像需要）。

## ICE 伺服器配置

```dart
// signaling.dart 內建預設值（Oracle Cloud TURN）
// TURN URI: turn:152.69.196.5:3478 (UDP)
// TURN User: uban
// TURN Pass: 115207
// 也可透過 --dart-define 覆蓋：
// --dart-define=TURN_SERVER=152.69.196.5:3478
// --dart-define=TURN_USER=uban
// --dart-define=TURN_PASS=115207
// 已內建 Google STUN + Oracle coturn TURN (含 TCP 備援)
```

## 角色差異對照表

| | 長輩端 (Elder) | 家屬端 (Family) |
|--|---|---|
| 通話入口 | `ElderScreen` | `VideoCallScreen` |
| Socket 角色 | `role: 'elder'` | `role: 'family'` |
| 來電處理 | CallKit → pendingAcceptedCall → ElderScreen 接手 | Dialog in FamilyMainScreen |
| 語音模式 | `isVideoCall: false` 可關閉攝影機 | 預設視訊 |
| UI 風格 | 全螢幕沉浸 + 超大按鈕 | 標準 Glassmorphism 控制列 |
| onCallAccepted | 長輩自己是 Callee，由家屬 createOffer | 家屬自己是 Callee 或 Caller |

## 關鍵狀態變數

```dart
// globals.dart
ValueNotifier<Map<String, String?>?> pendingAcceptedCall  // CallKit 接聽後的通話資訊
bool isAppReady                                            // App 是否已初始化
String? appRole                                            // 當前角色 (elder/family)
```

## 測試工具

| 工具 | 用途 |
|------|------|
| `test_call_simulator.py` | Socket.IO 信令自動化測試 |
| `webrtc_test.html` | 瀏覽器版 WebRTC 測試 v1.1（含 TURN 驗證 + ICE 排隊修正） |
| `flutter analyze` | Dart 靜態分析 |

## 環境要求
- Flutter SDK (latest stable)
- Python 3.12 (後端，不支援 3.13+)
- Android Studio (模擬器)
- 後端通過 Tailscale Funnel 對外開放
