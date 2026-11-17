# 拍片專用測試帳號

2026-11-17 在正式站（`https://localhost-0.tail5abf5e.ts.net`）建立，只用來截影片素材。
**12-14 小豬賽季結算前要從 /admin 刪除這 5 個帳號**（連同下方「已建的假資料」）。

截圖、寫假資料只准用這 5 個帳號；組員的真帳號（user_id 1、2、489 等）一律不碰。

## 帳號

| 片中角色 | App 顯示名 | user_id | 登入方式 | 密碼／識別碼 |
|---|---|---|---|---|
| 兒子（家屬端） | 王志豪 | 493 | Email：`11436013+film@ntub.edu.tw` | 密碼：`iYtyNWm-q8yVSeMHoJFZ` |
| 阿公（長輩端，主角） | 王金水 | 494 | 長輩端沒有密碼，用長輩代碼識別 | elder_id：`XBZ4`（用配對碼 0243 與兒子配對） |
| 好友 老陳 | 老陳 | 495 | 同上 | elder_id：`SE7B` |
| 好友 阿鳳姨 | 阿鳳姨 | 496 | 同上 | elder_id：`3EXW` |
| 好友 棋友阿土 | 棋友阿土 | 497 | 同上 | elder_id：`GMED` |

- 三位好友只和阿公互加好友，沒有和其他人配對。
- 字卡上稱「阿公」「兒子」；App 畫面裡兒子帳號一律顯示「王志豪」。

## 在模擬器登入（`Uban/mobile_app` 底下）

先清掉舊登入：`adb shell pm clear com.example.flutter_application_1`，再跑：

```bash
# 阿公（長輩端）
flutter run --dart-define=SERVER_IP=localhost-0.tail5abf5e.ts.net --dart-define=DEV_BYPASS_LOGIN=true --dart-define=DEV_BYPASS_ROLE=elder --dart-define=DEV_BYPASS_USER_ID=494 --dart-define=DEV_BYPASS_USER_NAME=阿公 -d emulator-5554

# 兒子（家屬端，深色）
flutter run --dart-define=SERVER_IP=localhost-0.tail5abf5e.ts.net --dart-define=DEV_BYPASS_LOGIN=true --dart-define=DEV_BYPASS_ROLE=family --dart-define=DEV_BYPASS_USER_ID=493 --dart-define=DEV_BYPASS_USER_NAME=王志豪 -d emulator-5554
```

⚠️ 四個 `DEV_BYPASS_*` 參數一定要打齊：少了 `USER_ID` 會登入到組員的真帳號；`run.ps1` 的預設值也不是這組帳號。

## 已建的假資料（刪帳號時一起清）

- 阿公每天 6 筆提醒（id 54–59，建立者記為兒子 493）：08:00 吃藥、10:00 出門散步、12:00 吃午餐、15:00 喝一杯水、18:00 吃晚餐、21:00 量血壓。
- 4 筆打卡（提醒 54–57，日期 2026-11-18），連帶 4 筆打卡紀錄並通知了兒子。
- 阿公對小嘎說的 2 句話：「小嘎早安，我剛散步回來」、「今天膝蓋有點痛，走路有點吃力」（當時 AI 電腦沒開，小嘎回的是後備道歉句）。
- 阿公的「家」地點：place id 13，座標 25.0330, 121.5434，半徑 150 公尺。
- 阿公的個人資料：稱呼「阿公」；興趣「老歌、泡茶、園藝、下象棋」；慢性病「高血壓、膝蓋退化」；用藥備註「早晚飯後各一次降血壓藥」。
- 主動關懷頻率從「關閉」改成「1 小時」（阿公一段時間沒互動，小嘎會主動傳訊息；22:00–07:00 除外）。
