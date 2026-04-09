# CNA News Flask Demo

## 功能
- 爬中央社新聞
- 每篇只回傳 `分類`、`標題`、`內文`
- 提供簡單前端頁面呼叫 API

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
