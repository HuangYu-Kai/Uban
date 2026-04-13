# CNA News Flask Demo

## 功能
- 爬中央社新聞
- 每篇回傳 `分類`、`標題`、`內文`、`圖片(image)`
- 提供簡單前端頁面呼叫 API
- 每天凌晨 `00:00`（台北時間）自動重爬一次
- 當日資料會落地在 `news/data/daily_news.json`

## 啟動方式
```bash
cd news
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

開啟瀏覽器：`http://127.0.0.1:5000`

## API
- `GET /api/categories`
- `GET /api/news?category=politics&limit=5`

`/api/news` 回傳：
- `data_date`: 這批資料的日期
- `generated_at`: 這批資料最後產生時間
- `items[].image`: 新聞圖片網址
- 若該篇沒有實際新聞圖片，`items[].image` 會是空字串

`category` 可用值：
- politics
- international
- china
- finance
- technology
- life
- society
- local
- culture
- sports
- entertainment
