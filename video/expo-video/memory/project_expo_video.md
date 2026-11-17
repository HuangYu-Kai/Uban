---
name: project-expo-video
description: 專題展 20 分鐘介紹長片：計畫書位置、已定決策、明天（11-15）從 P0 開工的接手點
metadata:
  node_type: memory
  type: project
  originSessionId: cfe2cd8b-8035-48a9-90ea-ab40a09f2331
  modified: 2026-11-17T01:29:38.580Z
---

專題展要一支約 20 分鐘的 Uban 介紹長片。計畫書（詳盡版）在 `expo-video/docs/designs/00-production-plan.md`，11-14 寫完；使用者說「明天再開始做」，所以**下次從計畫書第 17 節 P0 開工**。

已定（11-13）：照 mg-styles-15 程式渲染（HTML/Three.js/GSAP＋無頭 Chrome＋ffmpeg，不用 AI 影片模型）；五種風格一章一主風格；Fable 做的 60 秒原片 `Downloads/ad_60s.mp4` 直接當開場或片尾；重點是鏡頭運動與段落拼接；配樂是營火旁鄉村民謠（斑鳩琴＋口琴＋鋼琴），**必須原創，不模仿星際拓荒原曲**。

**11-15 進度：** 使用者要「先做前五分鐘看效果」（原片 0–60＋第 1–3 章）。已完成：ffmpeg 改用 imageio 內建版（`~/AppData/Roaming/Python/Python314/site-packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v9.0.2.exe`，不用 winget）；`harness/render.mjs` Windows 化（d3d11，0.04 秒／格）；繁體字型在 `shared/fonts/`；`shared/` 有 tokens、easing、camera、dot、overlay、seeded；接縫規格 `seams/J0–J3.json`；共用派工說明 `docs/designs/01-first5min-brief.md`；組裝 `tools/assemble_preview.py` → `out/preview_first5min.mp4`。原片規格 1920×1080 30fps，結尾淡到 mint #E9F4EF。**使用者 11-15 指定全片 60 fps**（原片在組裝時複製格補到 60；章節 DEMO.fps=60，格數以 30fps 換算成秒）。配音、展期等 D1–D8 仍未問。

**11-15 樣片完成：** `expo-video/out/preview_first5min.mp4`（5:00、60fps、−14 LUFS，三道接縫已驗）。配樂 `audio/score_preview.py`（斑鳩琴 KS 合成＋VCSL 口琴＋mgaudio 鋼琴，未經人耳驗證）。下一輪待修：ch1 問號群擠、ch3 記憶庫／求救段太空、3-6 黑直條、開頭手機框粗、「記得你」重複；ch2 營火木柴已改 5.4 秒才出現（J1 修正）。中間檔 out/*.mkv 約 13 GB。等使用者看片回饋。

**11-15 使用者回饋（第二輪）：** ①合成配樂難聽、下載的 Kevin MacLeod 曲也不要 → **自己作曲，以〈Timber Hearth〉為範例**（只取氛圍編制、旋律和聲原創），用 FluidSynth 2.6.2 免安裝版（`audio/tools/fluidsynth/`）＋MuseScore_General.sf2（MIT，`audio/soundfonts/`）渲染，使用者明確授權下載；②第 1 章抖動太多看了不舒服 → 已移除紙片逐格抖動、手持晃動、鏡頭步進；**全片持續微動要克制**；③App 畫面要用**實際截圖**與真實 App 圖示（模擬器長輩帳號 user_id=2，截圖在 `chapters/ch03-motion/assets/screens/`，避開組員真名與新聞人物照）；④~~島上動物要用 App 的 2D 小豬圖~~ → **11-16 改：小豬一律用 App 現用的手繪去背版 `Uban/mobile_app/assets/images/pet_breeds/pink_front_1–5.png`＋耳標 `ear_tag_1–5.png`（錨點 `ear_anchors.json`）**；`pet_stages/pig_stage_*` 有白毛邊別用（使用者：「豬用我畫的」）。

**11-16 凌晨收工狀態（明天從這裡接）：**
- 第 1 章（去抖動）、第 2 章（App 小豬）、第 3 章（真實截圖＋修正）的 `out/ch01–03.mkv` 都是最新版，接縫已驗。
- **待辦 1：配樂試聽**——原創配樂（D 大調，FluidSynth＋MuseScore_General）**11-16 凌晨已完成**：`out/score2_0-300.wav`、試聽 `out/score2_clip_ch1.wav`(112–132s)／`_ch2`(174–194s 全編制主題)／`_ch3`(220–240s)；說明 `audio/score2/NOTES.md`，可調參數在 `harmonica()` 的 depth/rate/scoop 與 `render.py` 的 transient_shape、EQS。**先請使用者聽三段，點頭才組片。**
- **待辦 2：組片**——把 `tools/assemble_preview.py` 的 `SCORE` 改指 `out/score2_0-300.wav`（目前指向使用者已否決的 Kevin MacLeod 版 `music_0-300.wav`），跑 `python tools/assemble_preview.py` → `out/preview_first5min.mp4`；`CREDITS.md` 的配樂段也要改成原創＋MuseScore_General（MIT）。
- 第 3 章已知小問題：3-6 手機偏小、3-1 推近時掃過手機右側黑框約 0.3 秒。
- 模擬器長輩截圖法：`DEV_BYPASS_ROLE=elder DEV_BYPASS_USER_ID=2`，先 `pm clear`；系統列用 demo mode 設 09:00。

**11-16 白天：風格轉向（取代「五種風格一章一主風格」）**——使用者要**全片統一 Motion 風格**（強調「整體要改，不是只有第三章」）。參考 Whop AE Motion Design Masterclass 第 1 集成品廣告（bilibili BV1Sax46xELC）與 video-shotcraft（只讀規則，不安裝：Remotion 授權＋第三方程式）。草案 `expo-video/docs/designs/02-motion-style-pivot.md`（逐格拆解、視覺語言、各章對照、待決 D1–D4），**等使用者核准才動工**；下一步是 7 個共用模組＋15 秒風格樣片。配樂試聽仍未做。

**11-16 下午：改照 video-shotcraft 流程（共同創作模式）**——使用者要求「真的用那個 repo」：skill 以 junction 裝在 `expo-video/.claude/skills/video-shotcraft`（**只限 expo-video，不裝全域**，使用者要求只用於做影片）；模式選「共同創作」，五關（產品簡報→需求決策→視覺方向→鏡頭對照→分鏡）逐關給使用者確認，紀錄在 `docs/designs/04-shotcraft-guided.md`（第 1 關 11-16 已確認，下次從第 2 關開始）。60 秒原片**另外用、不放進本片**，本片自己滿 20 分鐘。配樂改**原創電子節拍 112.5 BPM**（一拍 16 格@30fps），背景子代理在 `audio/score3/` 作第 0 章。Remotion 專案 `expo-video/remotion/`（60 fps，`src/remotion30.tsx` 讓卡片 30 fps 參數不必改）；第 0 章樣片 `remotion/out/ch00.mp4` 只當方向參考。**用鏡頭卡要複製 demo 原檔再換皮，不要自己重寫**（使用者 11-16 指出我沒真的用 repo）。

**Why:** 開工前要知道哪些已拍板、哪些還沒問。
**How to apply:**
- 11-14 自動模式擋下 `winget install ffmpeg`，要請使用者自己用 `!` 執行。
- 待決 D1–D8 與風險 R7（小豬可否簡化成剪紙風）見計畫書第 2.2、16 節。
- mgaudio 沒有斑鳩琴與口琴；口琴用 VCSL（CC0），斑鳩琴需合成，**先做 30 秒試聽讓使用者點頭**。
- mg-styles-15 的中文字型是簡體，影片要改用繁體字型。
- 依 EGM 規則與 Uban/CLAUDE.md 第 8 條：Opus 規劃驗收、Sonnet 子代理執行；設計核准前不量產。

**11-16 晚：第 2 關已確認**（章節秒數照 03 第 4 節、左上常駐章標籤要）；使用者新增「**配樂要跟畫面連動**」→ Remotion 輸出 cues.json、作曲程式讀它下音（規則在 04 檔第 2 關確認結果）。預檢：現有 5 張長輩截圖夠做 styleframe，其他畫面延到最終採集。**第 3 關文字方向 A 暖瓷／B 薄荷玻璃／C 日夜循環已給，等使用者選**（我推薦 C 為主＋A 骨架）。

**11-16 晚（續）：第 3 關方向定為 C 一天的光＋A 骨架**；styleframe 5 張在 `expo-video/styleframes/out/sf1–5.png`（原始檔 index.html＋shoot.mjs），**等使用者確認樣稿**；確認後進第 4 關「功能→鏡頭對照」。

**11-16 晚 styleframe 回饋：** 豬用手繪 pig_stage；App 圖示用 `assets/images/app_icon.png`；手機螢幕要剛好 1:2、圓角與框同心；**不要時鐘**；樣稿必須看得出鏡頭卡 → 改成 4 張卡 demo 換皮（SF1 brace-expand／SF2 radial-ripple-phone-chips／SF3 icon-performance-moves·attention-bounce／SF4 logo-shrink-wordmark-lockup），派工說明 `docs/designs/05-styleframe-card-brief.md`，輸出 `remotion/out/sf/`。

**11-16 晚 手機截圖重做：** 舊截圖 1080×2160 是裁過的（導覽列被切一半），已重截完整 1080×2424（含狀態列 9:00 與手勢條）在 `remotion/public/screens_full/`（首頁、國語聊天、台語聊天）；手機螢幕比例一律 1080:2424。聊天紀錄有真實歌手影片縮圖 → **使用者指示「打碼」**（馬賽克 32px），**不要清空 user_id=2 的聊天紀錄**（可能是組員實際帳號）。重截需 flutter run 帶 `DEV_BYPASS_ROLE=elder DEV_BYPASS_USER_ID=2 DEV_BYPASS_USER_NAME=阿公`（模擬器上舊安裝版沒有 bypass）；Git Bash 下 adb shell 路徑要 `MSYS_NO_PATHCONV=1`。

**11-16 晚 第 3 關回饋：** 小豬改 pet_breeds 乾淨版（毛邊消失）＋掛使用者設計的耳標吊牌（取代 demo 的數字角標，隨跳躍擺動）；片尾綠方塊跟著轉**不用改**。總覽 `remotion/out/sf/overview_v3.png`，等使用者確認後進第 4 關。

**11-16 晚 第 3 關確認、第 4 關起草：** 功能→鏡頭對照表寫在 04 檔「第 4 關」（章名卡系統用 title-demote-to-label、夜段用暗場原生卡），等使用者接受／替換；確認後進第 5–6 關分鏡。

**11-16 晚 第 4 關擴充：** 使用者指出每章鏡頭太少、要設計轉場 → 04 檔新增「四類鏡頭（★主角／◆工作／▲字卡／●章名＋轉場，全片約 220 鏡）」與「轉場系統」（章內 R 元素接力／C 連續運鏡／W 甩鏡／P 穿窗／H 前景遮擋／M 圓對圓；章間 14 接縫逐一指定；光效藏切全片只在 9→10 漏光一次）；第 3 章 19 鏡樣本含「接下一鏡」欄，等使用者確認後展開其餘章。

**11-16 晚 使用者「都可以」：** 轉場系統＋四類鏡頭確認；第 1 章可用 2–3 鏡 CC0 人物剪影；高齡數據用政府公開統計註明出處。其餘 14 章由 4 個子代理平行起草到 `docs/designs/storyboard/chNN.md`（派工 `06-storyboard-brief.md`，含各章專屬卡與轉場配額），檢查器 `tools/check_storyboard.py`。

**11-16 晚 模型：** 使用者把主對話切到 Fable 5.2，並要求子代理也「用 fable 去跑」（他說 Fable 好像只能用到 11-16 當天）；分鏡 4 個子代理已改用 `model: fable` 重派。之後若 Fable 不可用，退回 Sonnet 子代理。

**11-16 23:15 模型分工改定：** 使用者：「只有主要的才跑 fable，其他子代理用 opus」（4 個 Fable 子代理同時跑兩度撞 5 小時用量上限）。之後派子代理一律 `model: opus`。分鏡進度：Fable 已寫完 ch04、07、08、11–14（連第 3 章樣本共 8 章 130 鏡，檢查器全過）；ch00–02、05–06、09–10 由 3 個 Opus 子代理起草中。全部回來後：跑 `python -I tools/check_storyboard.py` → 我逐章審 → 交使用者確認（第 5–6 關）。

**11-16 深夜 全片分鏡起草完成（待使用者確認＝制作放行）：** `expo-video/docs/designs/storyboard/ch00–ch14.md`＋總表 `storyboard/README.md`（15 章 241 鏡、★67 張不重複卡、檢查器全過）；待確認事項彙整在 04 檔「第 5–6 關」（展示版本功能確認、警報紅規則、SF1 副標改「AI 跨世代感知照護系統」、跌倒呈現、片尾名單、高齡統計查證）。起草時發現：**久坐提醒沒實作、小嘎不會跨天主動問起、PRO 只有金豬徽章接上**（分鏡已照實寫）。確認後下一步：最終素材採集（約 90 張截圖）→ Film.tsx 逐格時間表＋cues.json → Opus 子代理逐章換皮 → 配樂 → 終檢。模擬器 Pixel_9a 可能還開著（flutter run 背景程序）。

**11-16 深夜 制作放行：** 使用者確認分鏡（「其他都可以」；祝賀圖＝存手機後可傳 LINE，程式查證也能從相簿發到社群）。已做：`tools/build_timeline.py` → `remotion/src/film/shots.json`（241 鏡對拍、章起點在小節頭、2250 拍）；量產說明 `docs/designs/07-production-brief.md`；素材清單 `08-asset-checklist.md`；SF1 副標改「AI 跨世代感知照護系統」、SF2/SF3 章標籤改短名。**進行中：1 個 Opus 子代理建共用骨架（remotion/src/film/）＋完整第 0 章 → `remotion/out/ch00.mp4`**，回來後我驗收、給使用者看，再分章量產。**待問使用者：補截需要寫入假資料（社群貼文、提醒、GPS 軌跡、排行榜）的測試帳號——user_id=2 可能是組員真帳號，不可亂寫／清；要請他指定可寫的長輩＋家屬測試帳號。** 片尾名單內容仍待提供。

**11-16 深夜 第 10 章不符實際 App（待使用者裁示）：** 使用者提醒「社群沒有用了吧」，模擬器實看：長輩端沒有家庭社群頁，只有「電話→朋友→朋友圈」（分享到朋友圈、讚、留言）；家屬端互動頁有「家庭近況」卡（僅程式查證）。`storyboard/ch10.md` 是照死碼 `ElderCommunityScreen` 長輩模式寫的，要改寫成「朋友圈」或刪章；連帶 13-9、合照元素、10→11 接縫。**教訓：分鏡引用的畫面一律先在模擬器實際走到，不能只憑程式碼**（見 [[project-thesis-ch5to8-dead-code]]）。另：user_id=2 的朋友圈貼文作者顯示真名「宇璿」，更確定要用專用測試帳號。

## ★ 11-16 收工狀態（使用者做到 00:10；下次從這裡接）

**流程位置：** shotcraft 共同創作第 1–6 關全部確認、已放行量產。主對話 Fable、子代理一律 Opus（見 [[feedback-subagent-model-opus]]）。

**已完成：** 全片分鏡 `expo-video/docs/designs/storyboard/ch00–14.md`（241 鏡，檢查 `python -I tools/check_storyboard.py`）；逐格時間表 `tools/build_timeline.py` → `remotion/src/film/shots.json`；量產說明 `docs/designs/07-production-brief.md`；素材清單 `08-asset-checklist.md`；四張樣稿 SF1–4（`remotion/src/shots/sf/`、`remotion/out/sf/`）。

**背景還在跑（下次先確認結果）：** 1 個 Opus 子代理在建共用骨架 `remotion/src/film/`＋完整第 0 章 → 應輸出 `remotion/out/ch00.mp4` 與 `out/qa/ch00/`。回來後由我驗收（看靜幀）、給使用者看，通過才分章量產。若 11-17 找不到結果，檢查 `remotion/src/film/` 做到哪，重派一個 Opus 接手。

**使用者已裁示：第 10 章改寫成「朋友圈」**（長輩端真實畫面：電話→朋友→朋友圈；分享到朋友圈＝文字＋選填照片、讚、留言、好友都看得到；也有加好友、和朋友視訊）。**還沒動筆**：要重寫 `storyboard/ch10.md`（90 秒、入夜、章標籤改「10 朋友圈」，原主角卡 deck-deal-flyin／impact-feedback／spotlight-sweep-moves／page-waterfall-wall 可沿用），並連帶改 13-9、13-13 合照的第 10 章元素、9→10 與 10→11 接縫、`tools/build_timeline.py` 的 LABEL[10]、04 檔對照表；改完重跑檢查器與 build_timeline。

**11-16 模擬器實看家屬端（BoYo，user_id=1，只看不寫）：**
- 預設**深色**（資料頁有「深色模式」開關，可切淺色；拍片要先決定家屬端用深或淺）。底部三分頁：首頁／互動／資料。
- 首頁：今日打卡（0/6＋下一件）、近況分析（健康／外出／情緒與回憶錄）、長輩所在位置（要綁監視機）、GPS 移動軌跡卡、長輩身心觀察、「今天可以聊」（撥打電話聊聊／傳送關懷卡）、動態時光牆（生活足跡）、最新警示。
- 互動：視訊通話／語音通話、**AI 照護秘書**（分享近況／問近況／想問長輩一個問題／近況速報／吃藥提醒／散步提醒）、家庭近況 →「家庭社群」（分享我的近況、大家的近況、朗讀貼文與留言、讚、留言；**家庭社群只在家屬端**）、小豬共養（送點心給小豬）、全家一起走、遠端視訊監控（設備 0/2）、遠端提醒（新增／編輯／立即廣播／刪除）。
- 資料：帳號與方案、受關照長輩檔案、長輩互動與對話偏好、通知開關、訂閱方案與設備上限管理、配對新長輩裝置、長輩移機與免密重裝助手。
- 訂閱頁：「幫○○升級，多一份安心」＋月／季／年價格（片中不顯示價格）＋特色清單。
- 移動軌跡：真實地圖（台北信義區街名，**不可入鏡**，照分鏡換自繪底圖）；常去地點＋安心提醒（晚歸／失聯／遠離家）與第 8 章相符。
- **分鏡沒寫到但家屬端有的：AI 照護秘書、小豬共養、全家一起走、近況分析／身心觀察**（第 9 章可考慮納入 AI 照護秘書；待使用者決定）。第 9 章的「爸媽問你的問題」收件匣這次沒走到，下次要找入口確認。
- 長輩名稱到處顯示組員真名（宇璿），長輩帳號 ID 6160／user_id=2 是真人資料 → **補截圖一定要專用測試帳號，使用者尚未回答用哪一組**（選項：給我可寫的測試帳號／新建拍片專用帳號／確認 1 與 2 可直接寫）。

**模擬器現況：** Pixel_9a 開著，裝的是**家屬端 bypass 版**（flutter run 背景程序可能還在）；切回長輩端要重跑 `DEV_BYPASS_ROLE=elder DEV_BYPASS_USER_ID=2 DEV_BYPASS_USER_NAME=阿公`（先 `pm clear`）。巡覽工具 `scratchpad/emu.py`（session 暫存，會被清掉；用法：cap／tap／swipe／back／sheet／texts）。**巡覽時不撥電話、不發文、不刪除、不按「立即廣播」。**

**仍待使用者：** 測試帳號（上）、片尾名單（組員／指導老師／致謝）、家屬端深色或淺色、要不要把 AI 照護秘書放進第 9 章。

**11-16 23:41 最後快照（使用者提醒 5 小時用量上限，先告一段落）：** 兩個 Opus 子代理仍在背景跑，可能被用量上限中斷——**下次開工第一件事是檢查這兩件有沒有做完**：
1. **骨架＋第 0 章：** 23:41 時 `remotion/src/film/` 已有 Film.tsx、timeline.ts、chapters.tsx、shared/（DayStage、GreenDot、Phone、CaptionCard、ShotCaption、TitleDemote、seams、ChapterRoot、ShotSeq、BlurWords、Placeholder），`ch00/` 只寫到 S00_01。**注意 `remotion/out/ch00.mp4` 若時間戳是 11-16 17:59 就是舊樣片，不是新版。** 沒做完就重派 Opus 接著做 ch00 的 S00_02–S00_10（照 `07-production-brief.md`）。
2. **第 10 章改寫成朋友圈：** 23:41 時 `storyboard/ch10.md` 標題還是「家庭社群時光牆」＝尚未改完。判斷方式：標題變成朋友圈、`python -I tools/check_storyboard.py` 全過、`tools/build_timeline.py` 的 LABEL[10] 是「朋友圈」、ch13 的 13-9 與合照名單已改。沒做完就照上面「使用者已裁示」那段重派。

**11-17 開工：** 確認骨架＋第 0 章子代理 11-16 23:44 被用量上限打斷（ch00 只有 S00_01/03/04/06、缺 Ch00.tsx 與 S00_02/05/07–10；ch00.mp4 仍是 17:59 舊樣片）→ 已重派 1 個 Opus 子代理接手做完第 0 章並照 07 檔驗收。回來後我看 qa 靜幀，再給使用者看。

**11-17 09:40 使用者裁示：** ①**新建拍片專用帳號**（阿公＋女兒配對＋三個好友），Fable 子代理先調查註冊／配對流程、出計畫，**建帳號前要使用者核准**；②**家屬端用深色**；③**AI 照護秘書放進第 9 章**（Fable 子代理改寫 ch09＋重跑 shots.json）；④片尾名單取自《系統簡介(複審)》封面，已寫進 `storyboard/ch14.md`（組長周宇璿、組員童柏祐／黃于愷／陳紹宇、指導林育志老師；特別感謝含 Claude（Anthropic），使用者要求；不放學號）；⑤**11-17 下午 3 點前把 Fable 額度用完**→ 這段時間子代理可用 `model: fable`，3 點後回到 Opus。

**11-17 拍片帳號核准：** 家屬改「**兒子**」（顯示名王志豪，email 11436013@ntub.edu.tw）、長輩「王金水」（字卡仍稱阿公／兒子）、好友老陳／阿鳳姨／棋友阿土；用腳本 `expo-video/tools/create_filming_accounts.py` 打正式站公開 API，清單（含密碼）在 `expo-video/accounts/filming_accounts.json`（gitignore）。**12-14 小豬賽季結算前要刪這些帳號**（/admin 刪除帳號）。模擬器 bypass 沒帶 USER_ID 會登入宇璿、run.ps1 預設 BoYo → 一律手打四個 define。**分鏡全片「女兒」→「兒子」待統一改**（ch09 子代理已告知）。

**11-17 12:55：第 0 章完成待使用者看片**：`remotion/out/ch00.mp4`（44.84 秒 60fps，10 鏡＋Ch00.tsx，Root 已註冊 Film／Ch00–Ch14），qa 52 張在 `out/qa/ch00/`、聯絡表 `out/qa/ch00_sheet1–5.png`。**渲染要加 `--timeout=180000 --concurrency=4`**（字型載入逾時）。已知：0-8 標題壓在圖示上、0-3→0-4 光點遮「說」、0-10 脹動疊加、結尾冷色只轉一半。兩個 Fable 子代理（ch09 秘書、建帳號）09:50 撞 5 小時上限，12:51 已續跑。

**11-17 13:10：** ①第 9 章已加 AI 照護秘書（7 鏡、2 主角鏡；補截清單在 08 檔第 9 章；待決 6 點在 ch09.md 檔尾）；②全片分鏡「女兒」→「兒子」已統一改、07 檔改成**家屬端深色**、shots.json 已重跑；③**建帳號卡住**：11436013@ntub.edu.tw 已被 user_id 489「Yukai」（疑黃于愷真帳號）占用，正式站未寫入任何東西，**等使用者給別的信箱**，之後跑 `python -I tools/create_filming_accounts.py`（要驗證碼就加 `--email-code`）。

**11-17 13:20：** 使用者堅持用 11436013@ntub.edu.tw（489 很可能是他本人帳號，不碰）→ 改用加號別名 `11436013+film@ntub.edu.tw` 建兒子帳號（子代理續跑中）。使用者說「這種小事你決定就好」→ 9-7 劃線保留（主角卡的改變節拍＝AI 解析的視覺化）、9-6 維持近況速報。

**11-17 13:33 拍片帳號建好、驗收全過：** 兒子王志豪 user_id=493（11436013+film@ntub.edu.tw，密碼在 `expo-video/accounts/filming_accounts.json`）；阿公王金水 494（elder_id XBZ4，已和 493 配對）；好友老陳 495／阿鳳姨 496／棋友阿土 497（elder_id 3EXW／GMED／SE7B 三選一對應見清單檔），只和阿公互加。**12-14 前刪除。** 同時在背景：Fable 子代理量產第 1 章、第 14 章（13:25 派出）。使用者外出，第 0 章影片回家再看。

**11-16 23:50 更新：第 10 章「朋友圈」改寫已完成並通過檢查**（上面第 2 點作廢）：`storyboard/ch10.md` 18 鏡（主角卡同原 4 張）、ch13 的 13-8／13-9／合照名單、README、`build_timeline.py` LABEL、ch02 2-9 的葉子、06 秒數表都已改成朋友圈；`shots.json` 已重跑。還沒實際看過、量產前要截的：「分享到朋友圈」發文畫面、留言畫面、和朋友視訊的通話畫面；要先有三個好友測試帳號（老陳、阿鳳姨、棋友阿土）。04 檔 14 接縫表的 10→11 文字仍寫「照片牆推近其中一張」，實際做法是「推近朋友圈貼文裡祝賀圖角落的小豬」。**骨架＋第 0 章那個子代理仍未回報**（照上面第 1 點檢查）。

**11-17 18:07：** 13:25 派的第 1、14 章 Fable 子代理沒留下任何檔案（`src/film/ch01`、`ch14` 不存在），判定中斷 → 已重派 2 個 Opus 子代理平行量產第 1 章、第 14 章（照 07 檔，渲染帶 `--timeout=180000 --concurrency=4`）。第 0 章影片 `remotion/out/ch00.mp4` 使用者仍未看。

**11-17 18:40 App 圖示加場（使用者：「icon 出現頻率要多一點」）：** 分鏡已改 0-3（圖示＋字標定妝，**程式已做**：`sf1Layers.tsx` 的 `iconIn`、S00_03 第 24–48 格滑入）、4-1（桌面按 Uban 圖示→App 啟動）、6-13（桌面看得到圖示）、7-8／8-12（通知來源列顯示 Uban 圖示）；第 14 章原本就有。第 1 章刻意不放品牌。清單與待查（Android 通知小圖示是否真的是 Uban 圖示）寫在 `08-asset-checklist.md` 檔尾。

**11-17 18:25：** 使用者授權「根據鏡頭卡自己決定」→ 第 0 章已知問題修完並重渲：0-4 光點改 3 次方淡出、0-8 柔光幕加一條貼標題的橫帶、0-10 脹動改取最大值；「結尾冷色只轉一半」是 07 檔規定的跨章過渡（第 1 章前 2 小節走完），不改。**第 14 章完成**：`out/ch14.mp4` 60.84 秒，循環接縫與 Ch00 第一格逐像素相同；待確認：13→14 大環要照 `S14_01.tsx` 的 `RING_ROT0`、名單底列貼近 y918、「照片 CC0 授權」要看最後是否真有用到 CC0。第 1 章 Opus 子代理仍在跑。

**11-17 18:45 第 1 章完成**：`out/ch01.mp4` 89.64 秒，qa 63 張在 `out/qa/ch01/`，我抽看 4 張無誤。人物剪影自繪 SVG（第 14 章不必列 CC0 剪影）；高齡數據已查證（內政部戶政司，2025-12 底 20.06%）；1-7 獨居比例查不到可靠原始數字→只留字卡。**第 2 章量產時要接手** 1-18 留在畫面上的「現在，有 Uban」（用 `S01_18.tsx` 的 `S01_18Handoff` 退焦淡出）＋中央光點（TitleDemote introDot）。待使用者：1-9 五通未接來電時間是虛構的。已完成章：0、1、14。

**11-17 18:55 第 1 章回饋：** 使用者：剪影頭身比例怪、阿公與兒子看不出差別；1-3→1-4 跳「台灣，已經是超高齡社會」太突兀。使用者選「順序不動，只改過場」→ 分鏡已改：1-3 兒子翻手機看到和阿公的合照桌布、1-4 字卡改「像阿公這樣的長輩，越來越多」（shots.json 已重跑）。已派 Opus 子代理重畫剪影（阿公駝背／帽／手杖；兒子挺直／襯衫）並實作過場、重渲 ch01。
**11-17 19:30：** 第 1 章剪影重畫＋1-3→1-4 新過場完成（`art.tsx` 關節式人形；阿公駝背扁帽手杖、兒子挺直短髮襯衫；鎖屏合照桌布 08:05）；我另把兒子正面半身的脖子改短；ch01.mp4 已重渲，待使用者看。
**11-17 19:45 第 1 章 1-4→1-5 再改（使用者）：** 「人形複製成一排」像殘影、「越來越多」移到左欄後又被換掉＝無意義位移 → 都拿掉，1-4 整句＋人形在 80–94 格原地退焦淡出，1-5 照原卡起。**通則：交接動作要有後續用途，移過去又馬上被換掉的位移不要做；複製排列的淡影會被看成殘影。**
**11-17 19:50：** 使用者確認第 1 章 OK（「好可以，你繼續下一個」）。已派 Opus 子代理量產第 2 章（缺截圖用佔位圖；先查程式驗證分鏡風險 1、4，必要時改分鏡＋重跑時間表）。已完成章：0、1、14。之後要集中一次在模擬器用拍片帳號補截所有佔位圖。
**11-17 20:00 圓點→App 圖示（使用者：「圓球用太多，大部分換成 app icon」）：** 新元件 `shared/AppMark.tsx`（960,540、邊長 128）；分工寫進 07 檔尾「圖示與光點分工」：AppMark＝接力／匯聚／收束／開場片尾；GreenDot 只留小嘎說話被點名、SF1 游標、章標籤小圓點。已派 Opus 子代理改 ch00/01/14＋TitleDemote 加 `introMark`＋分鏡文字；第 2 章子代理已收到同一規則。循環接縫改成「標準 AppMark 靜止」。
**11-17 20:20：** 第 0、1、14 章 AppMark 改造完成並重渲；`TitleDemote` 有 `introMark`（`shared/MarkMorph.tsx` 圖示↔圓點形變）；循環接縫逐位元組相同。0-7 字卡仍是「小嘎在中間，牽起兩代」（小嘎點 12–30f 形變成 App 圖示）。追加：0-3 尾段改成字標組的圖示本身移到中央當接力物（子代理續做中）。
**11-17 23:10 第 2 章完成**：`out/ch02.mp4`、qa 41 張；程式查證：打卡與吃藥提醒不經小嘎 → 2-5「全部匯進 Uban」、2-6 匯聚點＝App 圖示、字卡「說的、做的，Uban 都收到」；對話不推播給家屬 → 2-7 改家屬端生活動態「和小嘎聊天」明細、字卡「阿公說的話，家人也看得到」（與 9-3 意思略重疊）。佔位圖 3 張：`elder_assistant_full`、`family_home_dark`、`family_chat_feed_dark`。0-3 尾段已改成字標組圖示移到中央當接力物。已派 Opus 量產第 3 章（分鏡在 04 檔樣本）。已完成：0、1、2、14。
**11-17 23:35 開始補截圖（使用者：「你不先去把截圖補齊嗎?」）：** 模擬器 Pixel_9a 已開、App 以拍片長輩 494（顯示名阿公）跑著；巡覽工具 scratchpad/emu.py。拍片帳號是空的（無提醒、無動態），需先建假資料。已派 Opus 子代理採集：先截第 2 章 3 張並直接覆寫 `public/placeholders/` 同名檔，再照 08 清單逐章截、在 08 檔標「已截→路徑」；只准寫 493–497。**教訓：佔位圖累積前應先集中補截。**
**11-17 23:35 素材採集第一輪結果：** 第 2 章 3 張佔位已覆寫（小嘎面板＝首頁「怎麼用？」開的「阿公阿嬤安心救生圈」面板；`family_home_dark`、`family_chat_feed_dark` 是**暫代**，要 11-18 且 AI 恢復後重截：打卡卡要 4/6、小嘎回覆不能是道歉後備句、動態時間別停在深夜）。另截 ch04／ch05／ch09／ch11 共 17 張在 `public/screens_full/`，08 檔已標已截/未截＋檔尾「採集狀態」。**正式站 AI 聊天故障（回覆全是後備道歉句）**，天氣 open-meteo 逾時。假資料（12-14 前刪）：阿公提醒 id 54–59、11-18 打卡 54–57、2 句聊天、家地點 place 13、494 個人資料、主動關懷頻率改 1 小時。模擬器現跑家屬 493（深色），時區改 Asia/Taipei、GPS 25.0330,121.5434。**待使用者：** 長輩端電話名冊顯示帳號名「王志豪」vs 字卡要「兒子」怎麼取捨。

## ★ 11-17 收工狀態（使用者做到 00:00；下次從這裡接）

**已完成章（mp4 在 `remotion/out/`）：** 0、1、2、3、14。使用者已看過並認可第 1 章；0、2、3、14 待他看片。全片接力物＝App 圖示（`shared/AppMark`，見 07 檔尾），章名卡用 `TitleDemote introMark`。
**第 3 章（11-17 23:45）：** 19 鏡完成、tsc 過、已渲染；程式查證後的改動（待使用者看片時確認）：3-13「頭有點暈」→「頭好暈」（關鍵字清單）、3-14 沒有通知家人按鈕→改成口說「要」、3-9 無台語截圖改卡片推近、3-4 接「幫我打給兒子」、小幫手一次只帶一步。qa 只看了 12/25 張，接縫 2→3 未在 Film 並排比對、3-14 後段未截圖檢查 → **下次先補驗**。佔位圖：`elder_chat_weather`、`helper_step1/2/done`（換真圖後要改 S03_03 `BUBBLE_SRC/MIC_SRC`、helper.tsx `TARGET_SRC`）。
**下次待辦順序：** ①補驗第 3 章 qa；②11-18 白天＋正式站 AI 恢復後重截 `family_home_dark`（打卡 4/6）、`family_chat_feed_dark`（正常回覆）＋聊天類素材，然後重渲第 2、3 章；③繼續補截 08 清單（小幫手、GPS 軌跡、通話類先問使用者）；④量產第 4 章起。
**使用者 23:50 裁示：** App 畫面裡兒子帳號名一律顯示「王志豪」（字卡仍稱「兒子」），08 檔第 4 章「兒子」的要求作廢。AI 聊天故障是因為跑本地 AI 的電腦沒開——**重截聊天類素材前先請使用者開 AI 那台電腦**。
