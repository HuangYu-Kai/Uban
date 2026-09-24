> ⚠️ **本檔在兩個 repo 各有一份鏡像**：`Uban/CLAUDE_call-monitor-guardrails.md` 與 `uban-api/CLAUDE_call-monitor-guardrails.md`。
> 護欄正文另外拆成兩卷，同樣兩邊鏡像：`CLAUDE_call-monitor-guardrails-frontend.md`、
> `CLAUDE_call-monitor-guardrails-backend.md`（`Uban/` 與 `uban-api/` 各一份）。
> 因為 `Uban/` 與 `uban-api/` 是兩個獨立的 git repo（專案根目錄的 `.git` 是空目錄、無法運作），
> 這些跨前後端的權威文件必須在兩邊各留一份才會被版控。
> **修改任一份時，必須同步更新另一份**，否則兩邊會分歧。

# CLAUDE_call-monitor-guardrails.md — 通話與監控子系統 護欄清單（索引）

> 🗂️ **這是什麼**：通話與監控子系統全部 215 條護欄的**索引檔**。護欄正文（原
> `CLAUDE_call-monitor.md` §7 的完整內容）2026-09-04 第四十二輪從主文件獨立成本檔，之後隨
> 每輪真機故障持續累積；2026-09-24 第五十三輪本檔已達 200,175 bytes，再依前端／後端拆成兩卷：
> `CLAUDE_call-monitor-guardrails-frontend.md`（§7.1，115 條）與
> `CLAUDE_call-monitor-guardrails-backend.md`（§7.2，100 條）。本檔（索引）只保留表頭、
> §7.3／§7.4（跨前後端內容，合計僅 7KB）與下方「依任務類型的定向閱讀指引」；兩卷內容皆為
> **逐字搬移，未經改寫、未重新編號**。
>
> **為什麼再拆**：本檔雖然還沒摸到工具單次讀取上限（262,144 bytes），但已經出現另一種代價——
> 用關鍵字對整份護欄做 grep 時，前端與後端主題混雜在同一份輸出裡，命中率很低。第五十三輪
> 實測：以「鎖定」「背景」搜尋，7 條命中只有 1 條真正相關，CCTV 建構參數、權限對話框時序、
> 溢位判準都會誤中。依前端／後端主題拆成兩卷可以先把 grep 範圍縮小一半，再靠下方的
> 「依任務類型的定向閱讀指引」把「任務類型 → 護欄編號」直接對應起來，取代盲目關鍵字搜尋。
>
> ⚠️ **索引與兩卷正文都是動手前必讀的一部分，不是查證用的史料**——與純歷史存檔的
> `CLAUDE_call-monitor-history.md`（只在需要查證「這段程式碼為什麼長這樣」時才讀）性質不同。
> 任何要改視訊通話／來電通知／監控（CCTV）程式碼的人，`CLAUDE_call-monitor.md` 全文都要讀；
> 護欄正文改成**依任務類型定向閱讀**（見下表）——抓不準自己的改動屬於哪個任務類型，就兩卷
> 都讀，不要因為拆成索引＋兩卷就誤以為整體變成選讀。
>
> **收錄範圍**：全部 215 條護欄（G1–G215）分存兩卷——§7.1 前端護欄 115 條在
> `CLAUDE_call-monitor-guardrails-frontend.md`；§7.2 後端護欄 100 條在
> `CLAUDE_call-monitor-guardrails-backend.md`；§7.3 已知的文件錯誤（以程式碼為準）／
> §7.4 已知且刻意保留的安全缺口（跨前後端、合計僅 7KB）留在本檔（索引檔）尾端。
>
> **本文件中所有「§7」「G數字」的引用，一律先指向本檔（索引）**；`CLAUDE_call-monitor.md`、
> `CLAUDE_call-monitor-history.md`、`CLAUDE_call-monitor-ui-map.md` 與三份 `CLAUDE.md` 中出現的
> 既有「見 §7」「見 G12」等寫法不逐處改寫——本檔檔名不變，這些連結全部維持有效。抵達本檔後，
> 不確定某個 G 編號在哪一卷，直接對兩卷檔案下 `grep -n "^\*\*G<編號> —"` 即可，不需要整份讀取。

## 📖 依任務類型的定向閱讀指引

> 用途：與其對整份護欄盲目關鍵字 grep（前後端主題混雜、命中率低——見上方「為什麼再拆」的
> 實測案例），先查下表對應到哪一卷、哪些編號，再用 `grep -n "^\*\*G<編號> —"` 精準定位標題，
> 需要時才點開該條完整內文。**下列編號是 2026-09-24 第五十三輪的快照**，之後新增的護欄不會
> 自動出現在這裡——若懷疑清單不夠新，用「建議關鍵字」自行對兩卷重新 grep 一次，並人工複核
> 命中的標題是否真的語意相關（理由見下方每一類的 ⚠️ 備註，關鍵字誤中英文子字串是本輪拆卷
> 過程中實際踩到的坑）。

**改來電通知／CallKit／背景 isolate**
- 前端卷：G2, G9, G19, G73, G82, G83, G87, G107–G110, G146
- 後端卷：G33, G118
- 建議關鍵字：`CallKit|來電|fullScreenIntent|背景|isolate|FCM|headless|喚醒|鈴聲|channel`
- ⚠️ 「喚醒」也會命中語音助理喚醒詞相關護欄（如 G59），那與來電無關，出現時自行排除。

**改通話房 UI（接聽、掛斷、畫面跳轉）**
- 前端卷：G37, G38, G47, G50, G56, G60, G61, G69, G77, G81, G84, G87, G90
- 後端卷：G133, G199
- 建議關鍵字：`接聽|掛斷|ElderScreen|VideoCallScreen|導航|pushAndRemoveUntil|通話房|計時|onTrack`

**改 WebRTC 信令（SDP／ICE／TURN）**
- 前端卷：G1, G4, G5, G27, G39, G86, G102, G134（`Signaling` 單例相關幾乎都在前端卷）
- 後端卷：G34（後端對 SDP/ICE 只做不解讀內容的轉發，符合雙軌設計，故只有這一條）
- 建議關鍵字：`SDP|ICE|TURN|Offer|Answer|candidate|信令|targetId|createOffer|PeerConnection`
- ⚠️ 裸的 `ICE` 或 `Signaling` 會誤中英文字裡的子字串，例如 `ApiService`、`deviceMode`、
  `services/call_security.py`（`servICE`、`devICE` 都含 `ICE`）——這正是本輪拆卷想解決的問題
  本身，看到命中一定要確認標題語意是否真的相關，不要只看有沒有命中。

**改監控 CCTV／警報**
- 前端卷：G41, G42, G56, G60, G75, G76, G98, G105, G107, G138, G143, G146
- 後端卷：G43, G52, G53, G93, G95, G96, G97, G117, G135, G139, G169, G186, G191, G196
  （G186 條文內容是前端 `_viewingMonitorDeviceId` 狀態，但條文本體實際位於後端卷）
- 建議關鍵字：`CCTV|監控|監視|警報|跌倒|frame|YOLO|IPS|zone|校準`

**改 SharedPreferences 的來電相關鍵位**
- 前端卷：G7, G9, G11, G15, G24, G67（後端卷沒有——SharedPreferences 是純前端概念）
- 建議關鍵字：`SharedPreferences|prefs|pendingAcceptedCall|pendingRingCallData|timestamp|last_elder`

**改後端 Socket 事件轉發**
- 後端卷：G29, G34, G66, G91, G92
- 前端卷（呼叫端相關）：G157（`leaveRoom` 呼叫時機，與後端 `on_leave` 語意成對，建議一併看）
- 建議關鍵字：`socket_app|on_leave|emit|broadcast|room|disconnect`
- ⚠️ `emit` 會誤中 `--noEmit`（tsc 編譯參數，如 G173），與 Socket.IO 的 `emit()` 無關。

**改授權／權限檢查**
- 前端卷：G136（Android 執行期權限請求，跟後端幾條說的「授權」不是同一件事，但都叫「權限」）
- 後端卷：G44, G45, G127, G130, G151, G177
- 建議關鍵字：`授權|權限|JWT|get_current_user|401|404|call_security|認證`
- ⚠️ 不要用裸的 `IP` 當關鍵字——會誤中 `relationship`、`service`、`device` 等英文字尾（如
  `family_elder_relationsh IP`），G149／G95／G96 都曾被這樣誤掃進來，人工核對後已排除
  （G95／G96 實際內容是 CCTV IPS 掛鉤，已列在上方「監控 CCTV／警報」）。

**純版面／樣式調整**
- 前端卷：G63, G142, G159, G200（後端卷沒有——樣式是純前端概念）
- 建議關鍵字：`Row|Text|溢位|OVERFLOWED|Expanded|Flexible|寬度約束|字級|RenderFlex`

---


---

## 7. 護欄（合併後的唯一權威清單）

> 目前共 **215 條**（G1–G215）：G1–G36 合併自 `CLAUDE.md`（13 條）與 `Uban/CLAUDE.md`（26 條）並去重、
> 修正矛盾；G37–G46 為 2026-08-05 第十七輪新增（連線可靠性 4 條、監控警報 2 條、安全 4 條）；
> G47–G52 為 2026-08-05 第十八輪新增（前端 4 條：監控機連線、冷啟動衝刺、鎖屏覆蓋、掛斷提示；
> 後端 2 條：裝置清單同名去重、CCTV 端點部署）；
> G53–G57 為 2026-08-10 第十九輪新增（後端 3 條：綁定持久化、階段 0 只補洞、改名五處同步；
> 前端 2 條：`monitorViewOnly` 是 G8 的例外、監控自動接聽必須靜音但不得省略接聽動作）；
> G58–G66 為 2026-08-11 第二十輪新增（前端 6 條：session 統一釋放、語音喚醒預設關閉、
> 監控檢視無掛斷鍵、音量來源、撥出前等連線、家屬端動態文字寬度約束；
> 後端 3 條：配對碼持久化、`monitor-removed` 的 emit 順序、`on_end_call` 容忍 `room=None`）；
> **G67–G72 為 2026-08-11 第二十一輪新增**（前端 5 條：`pendingAcceptedCall` 的 `timestamp` 契約、
> `runApp()` 不得被開機初始化擋住、Splash 導航看門狗與互斥、長輩房名不得退回 `caregiver_id`、
> `_initElderMode` 的逾時與 `onError`；後端 1 條：`session/release` 只能以 `fcm_token` 為鍵）；
> **G73–G80 為 2026-08-11 第二十二輪新增**（前端 6 條：來電有效期收斂為 60s 且單一來源、
> `monitorViewOnly` 只隱藏顯示不停用計時、CCTV 推幀三層自癒、離開監控的釋放順序與 socket `dispose()`、
> 緊急通話無條件接聽＋7 秒提示音、「查詢失敗 ≠ 查無裝置」與層級主色單一來源；
> 後端 2 條：已取消 `call_id` 整通不發、兌換配對碼後必須廣播裝置清單）。
> **G81–G85 為 2026-08-12 第二十三輪新增**（全部前端：緊急通話自動接聽的四通路單一收斂點、
> FCM 背景 handler 保活到使用者決定（否則拒接鍵永遠無效）、來電備援通知的鈴聲與 channel
> 不可就地改音、無人接聽／連線逾時一律用 `showCallRetryDialog` 且重撥不得重跑媒體初始化、
> 不可取消的 `Future.delayed` 看門狗必須用世代編號守衛）。
> **G86–G91 為 2026-08-17 第二十五輪新增**（前端 5 條：SDP Offer 去重與 `call-request` 去重分離、
> 來電接聽路徑改用回呼帶入的 `roomId` 並套用冪等正規化、`request.send()` 必須消費回應串流、
> `SessionManager.releaseSession()` 呼叫需要逾時、`VideoCallScreen._initCall()` 需在提早 return 前
> 解析完使用者角色；後端 1 條：`elder-devices-update` 需帶 `elderId` 且 `on_disconnect` 須清除
> 該 sid 在所有房間的登記）。
> **G92–G95 為 2026-08-18 第二十六輪新增**（全部後端：Socket 房間定向離開語意（`on_leave`，
> 只離開指名房間、不斷 socket、不得做成「進新房間退所有舊房間」）、警報冷卻期只抑制推播不抑制
> 記錄、後端改動的驗證必須含 import 冒煙測試（`py_compile` 只驗語法抓不到 `NameError`）、
> IPS 掛鉤關閉時必須是零開銷的單一布林檢查、不得影響既有 CCTV/跌倒偵測路徑（**預設值已於
> 第二十七輪由關閉改為開啟**，見 G97）。
> **G96–G99 為 2026-08-18 第二十七輪新增**（IPS 由試做轉正式。後端 3 條：`/cctv/frame` 的
> IPS 掛鉤裡 `store_last_frame` 必須排在 `process_frame_for_zone` 之前、預設開啟後「未校準
> 即刻返回」的守衛不得移除、naive `datetime.utcnow()` 不可直接 `.timestamp()`（會在
> UTC+8 讓 epoch 倒退 8 小時，`elder-zone-update` 的 `timestamp` 欄位曾中招）；前端 1 條：
> 區域校準座標映射須用 `applyBoxFit(BoxFit.contain)` 配 `Image(fit: BoxFit.contain)`，
> 嚴禁 `BoxFit.cover`）。
> **G100 為 2026-08-18 拆檔稽核新增**（前端 1 條：全域音訊焦點必須維持 `none` 模式，
> 以利長輩端語音喚醒與媒體播放共存；本條原本只存在於 `Uban/CLAUDE.md` §6 第 27 條
> （2026-08-04 第十四輪），拆檔逐條核對 §7 時發現權威文件從未收錄，補列）。
> **G101 為 2026-08-18 第二十八輪新增**（前端 1 條：每一條「加入房間」的路徑都必須有對稱的
> 「離開房間」路徑，`joinRoom()` ↔ `leaveRoom()` ＋ `cancelPendingRoom()`）。
> **G102–G106 為 2026-08-19 第二十九輪新增**（全部前端：`Signaling` 單例回呼欄位須用
> `identical()` 守衛歸還、`onConnect` rejoin 須用當下 instance 欄位並逐一 fallback、緊急
> 通話路徑須主動 bring-to-front 喚醒螢幕、配對完成判定須查後端 `used_at` 而非猜測裝置清單、
> `sendCallAccept` 冷啟動情境須放寬等待窗並回傳成功與否）。
> **G107–G110 為 2026-08-20 第三十輪新增**（全部前端：跌倒警報 channel 改用
> `audioAttributesUsage: alarm` + `emergency_siren` 原生音效取代單純 `playSound: true`、
> Android notification channel 建立後不可修改故換聲音／`bypassDnd` 必須換 channel id、
> `setBypassDnd` 僅在建立當下已持有勿擾權限才生效故須雙 channel id 依授權狀態動態重選、
> FCM 背景 headless engine 拿不到 MethodChannel 故背景路徑所需的原生資訊須以
> `SharedPreferences` 橋接）。
> **G111–G118 為 2026-08-23 第三十一輪新增**（前端 G111–G115、後端 G116–G118，條文見
> §7.1／§7.2；本段落先前漏列，2026-08-25 補上）。
> **G119–G122 為 2026-08-25 第三十二輪新增**（前端 G119–G120、G122；後端 G121；內容見本輪
> 年表「新增護欄」小節與 §7.1／§7.2 條文）。
> **G123–G127 為 2026-08-25／2026-08-26 第三十三／三十四輪新增**（前端 G123–G125；後端
> G126–G127；內容見對應年表「新增護欄」小節與 §7.1／§7.2 條文）。
> **G128–G130 為 2026-08-26 第三十五輪新增**（後端 G128–G129；跨端 G130；內容見本輪
> 年表「新增護欄」小節與 §7.2 條文）。
> **G131–G134 為 2026-08-26 第三十六輪新增**（前端 G131、G134；跨端 G132；後端 G133；內容見
> 本輪年表「新增護欄」小節與 §7.1／§7.2 條文）。
> **G135–G137 為 2026-08-31 第三十七輪新增**（後端 G135；前端 G136；跨端 G137；內容見
> 本輪年表「新增護欄」小節與 §7.1／§7.2 條文）。
> **G138 為 2026-08-31 第三十八輪新增**（前端；內容見本輪年表「新增護欄」小節與 §7.1 條文）。
> **G139–G141 為 2026-09-01 第三十九輪新增**（後端 G139、G141；跨端 G140；內容見
> 本輪年表「新增護欄」小節與 §7.2 條文）。
> **G142–G145 為 2026-09-02 第四十輪新增**（全部前端：溢位判準改為「字級 × 同列元素
> 數」而非字串是否動態、CCTV 檢視「正在觀看哪一台」狀態只能放畫面 State、通話取消／
> 逾時必須同時清 CallKit／備援通知／pending prefs 三面、寫入 `user_role='elder'` 的
> 登入路徑必須同時寫 `last_elder_*`；內容見本輪年表「新增護欄」小節與 §7.1 條文）。
> **G146–G149 為 2026-09-04 第四十一輪新增**（前端 G146；跨端 G147；後端 G148–G149；內容見
> 本輪年表「新增護欄」小節與 §7.1／§7.2 條文）。
> **G150–G159 為 2026-09-04 第四十二輪新增**（後端 G150–G153、G155；跨端 G154；前端
> G156–G159；內容見本輪年表「新增護欄」小節與 §7.1／§7.2 條文）。
> **G160–G166 為 2026-09-05 第四十三輪新增**（後端 G160–G162、G164；跨端 G163、G165；
> 流程 G166；內容見本輪年表「新增護欄」小節與 §7.2 條文）。
> **G167–G172 為 2026-09-09 第四十四輪新增**（前端 G167、G170、G172；後端
> G168–G169；流程 G171；內容見本輪年表「新增護欄」小節與 §7.1／§7.2 條文）。
> **G173–G181 為 2026-09-11 第四十五輪新增**（流程 G173–G175、G179；管理端
> G176；後端 G177、G180；跨端 G178；前端 G181；內容見本輪年表「新增護欄」小
> 節與 §7.1／§7.2 條文）。
> **G182–G185 為 2026-09-13 第四十六／四十七輪新增**（後端 G182；流程
> G183–G184；跨端 G185；內容見本輪年表「新增護欄」小節與 §7.2 條文）。
> **G186–G190 為 2026-09-16 第四十八輪新增**（跨端 G186；前端 G187；流程
> G188；管理端 G189；流程／UI G190；內容見本輪年表「新增護欄」小節與 §7.2 條文）。
> **G191–G197 為 2026-09-17 第四十九輪新增**（後端 G191–G195；前端 G196–
> G197；內容見本輪年表「新增護欄」小節與 §7.2 條文）。
> **G23 已於第十八輪修訂**（改為只約束「要顯示提示時用什麼元件」，是否顯示交由 G50）。
> **G8 已於第十九輪加註例外**（`monitorViewOnly`，見 G55）。
> **G22 已於第二十二輪改寫**（緊急通話由「刻意不帶有效期、ttl 3600s」**反轉**為「兩條路都帶、ttl 60s」，見 G73）。
> **G67 已於第二十二輪修訂**（`pendingRingCallData` 窗口 120000 → 60000；並更正其中誤植的 G24 條號）。
> **G77 已於第二十三輪擴充**（自動接聽的範圍由「`ElderScreen` 內」擴大到**四條抵達通路**，見 G81；
> 提示音改為救護車雙音並搬進全域單例 `EmergencyTone`）。
> **G198–G199 為 2026-09-21／09-22 第五十一輪新增**（皆為前端：備援來電通知的
> `actionId == null` 不算「使用者已接聽」、全域語音助理浮動鈕在通話房／來電響鈴／
> 監控畫面必須讓位）。
> **G199 已於第五十二輪修訂**（原文只寫「在畫面自己的 widget 樹裡放一個
> `AssistantHiddenZone(child: SizedBox.shrink())`」，沒有明講該放在哪一層，
> 第五十一輪因此塞進 `elder_screen.dart` 通話房的 `Stack` children，導致
> `RenderStack` 塌成 0×0、長輩端通話房黑屏；已改為只能包住畫面根 widget，
> 並明文禁止塞進 `Stack`，見該條文）。
> **G200–G205 為 2026-09-23 第五十二輪新增**（前端 G200、G203、G204、G205；
> 後端 G201–G202；內容見本輪年表「新增護欄」小節與 §7.1／§7.2 條文）。
> **G206–G215 為 2026-09-24 第五十三輪新增**（前端 G206–G209；後端 G210–G215；內容見
> 本輪年表「新增護欄」小節與 §7.1／§7.2 條文）。
> **除非明確知道連鎖影響並能同步改完整條鏈路，不要單點修改。**


> 🗂️ **§7.1（前端護欄，115 條）與 §7.2（後端護欄，100 條）已搬到**
> `CLAUDE_call-monitor-guardrails-frontend.md` 與 `CLAUDE_call-monitor-guardrails-backend.md`，
> 條文全文請至該處查閱，或先看本檔開頭的「依任務類型的定向閱讀指引」。下面的 §7.3／§7.4
> 是跨前後端內容，留在本檔（索引）。

### 7.3 已知的文件錯誤（以程式碼為準）

> 這些是歷史文件與現行程式碼不符之處。已在本文件中修正，此處保留記錄以免後續 AI 又被舊敘述誤導。

| # | 舊文件說法 | 實際 | 佐證 |
|---|-----------|------|------|
| 1 | 後端路徑 `uban-api/uban-api/services/socket_app.py` 或 `Uban/uban-api/services/socket_app.py` | **`uban-api/services/socket_app.py`** | 檔案系統 |
| 2 | 根目錄護欄 #5：「前景 active Socket **不發** FCM（Layer B `continue` + Layer C 雙重過濾）」 | **會發**。前景在線 Socket 的 token 也併入 `fcm_send_map` | `socket_app.py`:1520-1523 |
| 3 | 前景不雙重彈窗是後端擋的 | **是前端擋的**：1500ms Socket 寬限期 + 3s callId 去重 | `main.dart::_setupForegroundMessaging` |
| 4 | 有效期 15 秒 / 45 秒；FCM `ttl=15s`/`45s`（更早的版本）；**120 秒**（第七～二十一輪） | **60 秒**（**2026-08-11 第二十二輪定案**；CallKit `duration` 仍為 45s，兩者無關） | `socket_app.py`、`globals.dart`:47 |
| 5 | 2026-06-07 記錄宣稱建立了 `MonitorViewScreen` | **不存在**。監控畫面是 `CameraScreen` | 全 `lib/` grep |
| 6 | 冷啟動預寫鍵是 `pendingRingCall` | **`pendingRingCallData`**。`pendingRingCall` 在 `main.dart` 中**只被清除、從無寫入**，是遺留鍵 | `main.dart` grep |
| 7 | 冷啟動兜底是「三層防線」 | **五層**（L0/L0'/L1/L2/L3/L4，見 §4.8） | `main.dart` |
| 8 | 緊急通話「FCM 不帶有效期」；第十七～二十一輪的正確答案是「**Socket 與 FCM 兩條路都不帶**」 | ⚠️ **2026-08-11 第二十二輪起兩條路都帶**（`expiresAt = issuedAt + 60000`），FCM `ttl` 由 3600s → 60s。舊敘述現在是錯的 | `socket_app.py` `on_emergency_call`；G22（已改寫）、G73 |
| 9 | `_parse_room_id` 只解析 `comm_`/`monitor_` 前綴 | 另有第三分支：純數字 room id 會查 `elder_profile` 反解，回傳 `(elder_id, 'comm')` | `socket_app.py`:537-568 |
| 10 | 長輩端登出只有 `elder_profile_tab::_handleLogout` 一處 | **另有 `elder_screen.dart`:674-680** | grep |
| 11 | `Uban/CLAUDE.md` 護欄 #5 同時寫「15 秒」與「120 秒」兩組矛盾條目 | 兩組**都已作廢**，以 **60 秒**為準 | 同 #4 |
| 12 | `Uban/CLAUDE.md` 第九輪（已遷至 `CLAUDE_call-monitor-history.md`）記錄中段插入了 `## 環境要求` + `## 🚫 絕對不可改動區塊` 片段 | 結構損毀，非有意內容 | `Uban/CLAUDE.md`:452-458 |
| 13 | `signaling.dart` 的 **`_configuration`** 看起來是 ICE / TURN 設定 | **死碼，完全沒有被使用**（`flutter analyze` 有 `unused_field` 警告）。真正生效的是 **`_generateDynamicTURNConfig()`**，由 `_createPeerConnection` 呼叫 | **2026-08-10 實測 :157**（第十七輪記的 :116 已漂移）；`_showCallkitIncoming` 死碼在 **:610**（原記 :542） |
| 14 | §3.1 / §6.6 / §6.7 稱「`elder-devices-update` **只在 join 時廣播**，disconnect 不廣播」 | **會廣播**。join(:1333)、`delete-device`(:1464)、`force-logout`(:1548)、**disconnect(:1628)**、改名(:2467) 都呼叫 `_broadcast_elder_devices_update` | `socket_app.py`:1628 |
| 15 | §6.6 宣稱有「**15 秒 staleness watchdog**」 | **從來不存在**（全 `lib/` grep 無此物）。前端只有 2.5 秒 Socket 輪詢 + 10 秒 HTTP 交叉驗證 | `family_main_screen.dart` grep |
| 16 | §6.6 宣稱有「每 10 秒 HTTP API 交叉驗證」 | 第十七／十八輪**確實不存在**（憑空記載）；**2026-08-10 第十九輪 A4 才真正實作出來** | `family_main_screen.dart`:338 `_refreshMonitorDevicesViaHttp` |
| 17 | §6.8 記 `_exitCCTVMode` 在 `elder_screen.dart`:795 | 實際在 **:910**（入口鈕 :1098） | grep |
| 18 | `uban-api/CLAUDE.md`：通話迴歸套件「須維持 **15 passed**」 | 實測為 **17 passed**——測試數量會隨改動增加而成長，這個數字本來就不是寫死的常數，權威依據永遠是套件當下的實際輸出，不是文件裡的舊快照。**2026-08-18 第二十六輪已就地更正** | `python -m pytest tests/test_call_signaling.py -q`；`uban-api/CLAUDE.md` |

> 🪤 **#13 是一個很容易踩的陷阱**：要改 TURN 憑證或 ICE 參數的人，第一眼會看到 `_configuration`
> 並改在那裡——**改了不會有任何效果**，而且它裡面的 `iceServers` 內容看起來還很合理。
> 一律改 `_generateDynamicTURNConfig()`。
> （`signaling.dart`:542 的 `_showCallkitIncoming` 同樣是未被引用的死碼，見 §7.3 的既有記錄脈絡。）

> ⚠️ `Uban/mobile_app/lib/main.dart.bak` 是**備份檔**，grep 會撈到它。永遠不要編輯它。

### 7.4 已知且**刻意保留**的安全缺口（2026-08-05 第十七輪稽核結論）

> 這些是稽核時看到、評估後**決定不改**的項目。寫在這裡是為了：
> (a) 後續 AI 不要以為是漏看的；(b) 真的要補時，知道代價在哪。

| # | 缺口 | 為什麼不補 | 真要補的話 |
|---|------|-----------|-----------|
| 1 | **整個 App API 實質上未認證**：後端**會發** JWT（`auth.py::create_access_token`，在 `routers/auth.py`:79 與 `routers/pairing.py`:91/339/486/883 呼叫），但 `get_current_user` **只在 `auth.py` / `auth_staff.py` 出現，沒有任何 router 把它當 dependency**；`api_service.dart` 也從不送 `Authorization` 標頭 | 硬上 `Depends(get_current_user)` 會讓**每一幀 CCTV 推流當場 401**，監控與通話全滅 | 前後端同時上線：`api_service.dart` 統一注入標頭 → 後端逐 router 加 dependency → 最後才移除本文件的關係驗證兜底 |
| 2 | `offer` / `answer` / `candidate` 依 `targetId` 轉發，**不檢查房間成員資格** | 要利用得先拿到受害者的**隨機 UUID sid**，而 sid 只在已受 `_verify_room_access` 保護的房間內揭露；反之在 SDP 路徑加嚴格成員檢查，極可能打斷冷啟動 join 競態——正是本子系統「單點修改幾乎必然造成回歸」的典型 | 要做就連同 §4 的 join 時序一起重測，並補進 `tests/test_call_signaling.py` |
| 3 | Socket 連線的 `userId` 是**自稱**的（socket 層同樣沒有 JWT） | 同 #1，是同一個根問題的不同切面 | 隨 #1 一起解 |
| 4 | **「同 IP 上限 5 台監視機」在反向代理後方實為「全球上限 5 台」**（2026-08-10 第十九輪查出） | 第十九輪已讓 `on_connect` 優先讀 `X-Forwarded-For` → `X-Real-IP` → TCP 對端位址（`_extract_client_ip`:1066）。但**若 Tailscale Funnel 不轉送這兩個標頭，仍會退化回單一 `ip_hash`**，第 6 台監視機起全球被拒 | 真機實測 Funnel 是否轉送 XFF。**在確認之前不要放寬上限**——放寬只會把「配不上」換成「濫用沒防線」。確認不轉送的話，改用 `elder_id` 而非 IP 作為配額鍵 |

**第十七輪實際補起來的洞**（都已上線，見 §8）：
`test-fall` 未授權觸發、`frame` 可偽造推流、音訊橋接可開進**任意裝置**（最嚴重）、
`acknowledge` 可偽造／消音、警報清單可列舉任意長輩、音訊橋接查詢洩漏 `from_id`/`to_device_id`、
`delete-device` 可遠端踢任意裝置。
