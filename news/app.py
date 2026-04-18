from __future__ import annotations

import json
import os
import re
import threading
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
import base64

import requests
from bs4 import BeautifulSoup
from flask import Flask, jsonify, render_template, request, send_from_directory

app = Flask(__name__)

FEEDS: dict[str, dict[str, str]] = {
    "politics": {"label": "政治", "url": "https://feeds.feedburner.com/rsscna/politics"},
    "international": {"label": "國際", "url": "https://feeds.feedburner.com/rsscna/intworld"},
    "china": {"label": "兩岸", "url": "https://feeds.feedburner.com/rsscna/mainland"},
    "finance": {"label": "財經", "url": "https://feeds.feedburner.com/rsscna/finance"},
    "technology": {"label": "科技", "url": "https://feeds.feedburner.com/rsscna/technology"},
    "life": {"label": "生活", "url": "https://feeds.feedburner.com/rsscna/lifehealth"},
    "society": {"label": "社會", "url": "https://feeds.feedburner.com/rsscna/social"},
    "local": {"label": "地方", "url": "https://feeds.feedburner.com/rsscna/local"},
    "culture": {"label": "文化", "url": "https://feeds.feedburner.com/rsscna/culture"},
    "sports": {"label": "運動", "url": "https://feeds.feedburner.com/rsscna/sport"},
    "entertainment": {"label": "娛樂", "url": "https://feeds.feedburner.com/rsscna/stars"},
}

DEFAULT_CATEGORY = "politics"
REQUEST_TIMEOUT = 15
MAX_LIMIT = 30
CRAWL_LIMIT_PER_CATEGORY = 30
DAILY_CRAWL_HOUR = 5
DAILY_CRAWL_MINUTE = 0

TAIPEI_TZ = timezone(timedelta(hours=8))
DATA_FILE = Path(__file__).resolve().parent / "data" / "daily_news.json"
AUDIO_DIR = Path(__file__).resolve().parent / "data" / "audio"

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/125.0.0.0 Safari/537.36"
    )
}

_daily_news_lock = threading.Lock()
_daily_news: dict[str, Any] | None = None

_scheduler_lock = threading.Lock()
_scheduler_started = False
_scheduler_stop_event = threading.Event()


def now_taipei() -> datetime:
    return datetime.now(TAIPEI_TZ)


def now_iso() -> str:
    return now_taipei().replace(microsecond=0).isoformat()


def today_str() -> str:
    return now_taipei().date().isoformat()


def normalize_text(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def normalize_url(url: str) -> str:
    clean = url.strip()
    if clean.startswith("//"):
        return f"https:{clean}"
    return clean


def is_valid_news_image_url(url: str) -> bool:
    if not url:
        return False

    lower = url.lower()
    if lower.endswith(".svg"):
        return False

    invalid_keywords = (
        "/www/images/pic_fb.jpg",
        "/www/website/img/",
        "/www/website/images/",
        "googleplay",
        "appstore",
        "fav-icon",
    )
    return not any(keyword in lower for keyword in invalid_keywords)


def sanitize_news_items(items: list[dict[str, Any]]) -> list[dict[str, str]]:
    sanitized: list[dict[str, str]] = []
    for item in items:
        category = normalize_text(str(item.get("category") or ""))
        title = normalize_text(str(item.get("title") or ""))
        content = normalize_text(str(item.get("content") or ""))

        raw_image = str(item.get("image") or "")
        normalized_image = normalize_url(raw_image) if raw_image else ""
        image = normalized_image if is_valid_news_image_url(normalized_image) else ""

        if not title or not content:
            continue

        sanitized.append(
            {
                "category": category,
                "title": title,
                "content": content,
                "image": image,
            }
        )
    return sanitized


def fetch_text(url: str) -> str:
    response = requests.get(url, headers=HEADERS, timeout=REQUEST_TIMEOUT)
    response.raise_for_status()
    return response.text


def parse_rss_items(xml_text: str) -> list[dict[str, str]]:
    xml_text = xml_text.lstrip("\ufeff").strip()
    root = ET.fromstring(xml_text)
    channel = root.find("channel")
    if channel is None:
        return []

    items: list[dict[str, str]] = []
    for item in channel.findall("item"):
        title = (item.findtext("title") or "").strip()
        link = (item.findtext("link") or "").strip()
        if not link:
            continue
        items.append({"title": title, "link": link})
    return items


def find_news_article_jsonld(soup: BeautifulSoup) -> dict[str, Any] | None:
    scripts = soup.find_all("script", attrs={"type": "application/ld+json"})

    for script in scripts:
        raw = (script.string or script.get_text() or "").strip()
        if not raw:
            continue

        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            continue

        candidates = data if isinstance(data, list) else [data]
        for candidate in candidates:
            if not isinstance(candidate, dict):
                continue
            candidate_type = candidate.get("@type")
            if isinstance(candidate_type, list):
                if "NewsArticle" in candidate_type:
                    return candidate
            elif candidate_type == "NewsArticle":
                return candidate
    return None


def pick_image_url(value: Any) -> str:
    if isinstance(value, str):
        normalized = normalize_url(value)
        return normalized if is_valid_news_image_url(normalized) else ""

    if isinstance(value, dict):
        url = value.get("url")
        if isinstance(url, str):
            normalized = normalize_url(url)
            return normalized if is_valid_news_image_url(normalized) else ""

    if isinstance(value, list):
        for item in value:
            candidate = pick_image_url(item)
            if candidate:
                return candidate

    return ""


def extract_image_url(article: dict[str, Any] | None) -> str:
    if not article:
        return ""

    thumbnail = pick_image_url(article.get("thumbnailUrl"))
    if thumbnail:
        return thumbnail

    image = pick_image_url(article.get("image"))
    if image:
        return image

    return ""


def extract_article(url: str, fallback_category: str, fallback_title: str) -> dict[str, str] | None:
    try:
        html = fetch_text(url)
    except requests.RequestException:
        return None

    soup = BeautifulSoup(html, "html.parser")
    article = find_news_article_jsonld(soup)
    image = extract_image_url(article)

    if article:
        category = normalize_text(str(article.get("articleSection") or fallback_category))
        title = normalize_text(str(article.get("headline") or fallback_title))
        content = normalize_text(str(article.get("articleBody") or ""))

        if title and content:
            return {
                "category": category or fallback_category,
                "title": title,
                "content": content,
                "image": image,
            }

    title = fallback_title
    desc = ""

    og_title = soup.find("meta", attrs={"property": "og:title"})
    if og_title and og_title.get("content"):
        title = normalize_text(og_title["content"].split("|")[0])

    meta_desc = soup.find("meta", attrs={"name": "description"})
    if meta_desc and meta_desc.get("content"):
        desc = normalize_text(meta_desc["content"])

    if title and desc:
        return {
            "category": fallback_category,
            "title": title,
            "content": desc,
            "image": image,
        }

    return None


def crawl_news(category_key: str, limit: int) -> list[dict[str, str]]:
    feed_info = FEEDS[category_key]

    rss_text = fetch_text(feed_info["url"])
    rss_items = parse_rss_items(rss_text)
    if not rss_items:
        return []

    seen_links: set[str] = set()
    unique_items: list[dict[str, str]] = []
    for item in rss_items:
        link = item["link"]
        if link in seen_links:
            continue
        seen_links.add(link)
        unique_items.append(item)

    target_items = unique_items[: max(limit * 2, limit)]

    article_inputs = [
        (item["link"], feed_info["label"], item["title"])
        for item in target_items
    ]

    results: list[dict[str, str]] = []
    with ThreadPoolExecutor(max_workers=6) as executor:
        for article in executor.map(lambda args: extract_article(*args), article_inputs):
            if article:
                results.append(article)
            if len(results) >= limit:
                break

    return results[:limit]


def load_daily_payload_from_disk() -> dict[str, Any] | None:
    if not DATA_FILE.exists():
        return None

    try:
        payload = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None

    if not isinstance(payload, dict):
        return None
    if "news" not in payload or not isinstance(payload["news"], dict):
        return None

    return payload


def save_daily_payload_to_disk(payload: dict[str, Any]) -> None:
    DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
    DATA_FILE.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def make_empty_daily_payload() -> dict[str, Any]:
    return {
        "date": today_str(),
        "generated_at": now_iso(),
        "news": {},
    }


def ensure_today_payload_locked() -> dict[str, Any]:
    global _daily_news

    if _daily_news is None:
        _daily_news = load_daily_payload_from_disk() or make_empty_daily_payload()

    if _daily_news.get("date") != today_str():
        _daily_news = make_empty_daily_payload()

    if not isinstance(_daily_news.get("news"), dict):
        _daily_news["news"] = {}

    return _daily_news


def get_or_create_category_news(category_key: str) -> tuple[list[dict[str, str]], dict[str, Any]]:
    with _daily_news_lock:
        payload = ensure_today_payload_locked()
        existing = payload["news"].get(category_key)
        if isinstance(existing, list) and existing:
            sanitized_existing = sanitize_news_items(existing)
            if sanitized_existing != existing:
                payload["news"][category_key] = sanitized_existing
                payload["generated_at"] = now_iso()
                save_daily_payload_to_disk(payload)
            return list(sanitized_existing), dict(payload)

    items = sanitize_news_items(crawl_news(category_key, CRAWL_LIMIT_PER_CATEGORY))

    with _daily_news_lock:
        payload = ensure_today_payload_locked()
        payload["news"][category_key] = items
        payload["generated_at"] = now_iso()
        save_daily_payload_to_disk(payload)
        return list(items), dict(payload)


def crawl_all_categories() -> None:
    crawled: dict[str, list[dict[str, str]]] = {}

    for key in FEEDS:
        try:
            crawled[key] = sanitize_news_items(crawl_news(key, CRAWL_LIMIT_PER_CATEGORY))
        except Exception:  # noqa: BLE001
            app.logger.exception("Daily crawl failed for category=%s", key)
            crawled[key] = []

    payload = {
        "date": today_str(),
        "generated_at": now_iso(),
        "news": crawled,
    }

    with _daily_news_lock:
        global _daily_news
        _daily_news = payload
        save_daily_payload_to_disk(payload)
        
    def pre_generate_audio():
        AUDIO_DIR.mkdir(parents=True, exist_ok=True)
        today = today_str()
        for category_key, items in crawled.items():
            cat_label = FEEDS[category_key]["label"]
            for i, item in enumerate(items):
                if item.get("audio_url"):
                    continue
                speech_text = f"以下為您播報{cat_label}新聞：{item['title']}。{item['content']}。新聞播報完畢。"
                try:
                    res = requests.post(
                        "https://localhost-0.tail5abf5e.ts.net/api/voice/tts/test",
                        params={"text": speech_text, "engine": "cosyvoice"},
                        timeout=180
                    )
                    res.raise_for_status()
                    data = res.json()
                    if data.get("status") == "success" and data.get("audio_base64"):
                        audio_b64 = data["audio_base64"]
                        audio_b64 = ''.join(audio_b64.split())
                        missing_padding = len(audio_b64) % 4
                        if missing_padding:
                            audio_b64 += '='* (4 - missing_padding)
                        audio_bytes = base64.b64decode(audio_b64)
                        
                        filename = f"{today}_{category_key}_{i}.wav"
                        file_path = AUDIO_DIR / filename
                        file_path.write_bytes(audio_bytes)
                        item["audio_url"] = f"/api/news/audio/{filename}"
                except Exception as e:
                    app.logger.exception(f"Failed to pre-generate audio for {category_key} index {i}: {e}")
        
        # Save again after audio processing
        with _daily_news_lock:
            payload["news"] = crawled
            _daily_news = payload
            save_daily_payload_to_disk(payload)
            
    threading.Thread(target=pre_generate_audio, daemon=True).start()


def seconds_until_next_daily_run() -> float:
    now = now_taipei()
    next_run = now.replace(
        hour=DAILY_CRAWL_HOUR,
        minute=DAILY_CRAWL_MINUTE,
        second=0,
        microsecond=0,
    )
    if now >= next_run:
        next_run += timedelta(days=1)
    return max((next_run - now).total_seconds(), 1.0)


def daily_scheduler_loop() -> None:
    while not _scheduler_stop_event.is_set():
        wait_seconds = seconds_until_next_daily_run()
        if _scheduler_stop_event.wait(wait_seconds):
            return

        try:
            crawl_all_categories()
            app.logger.info("Daily crawl completed at %s", now_iso())
        except Exception:  # noqa: BLE001
            app.logger.exception("Daily scheduled crawl failed")


def should_start_scheduler_in_this_process() -> bool:
    # 在 Flask debug reloader 下，避免父進程也啟排程
    if os.environ.get("FLASK_DEBUG") == "1":
        return os.environ.get("WERKZEUG_RUN_MAIN") == "true"
    return True


def start_scheduler_once() -> None:
    global _scheduler_started

    if not should_start_scheduler_in_this_process():
        return

    with _scheduler_lock:
        if _scheduler_started:
            return
        _scheduler_started = True

        # 啟動時先確保當天資料結構存在（真正爬取可由 API 按需觸發）
        with _daily_news_lock:
            payload = ensure_today_payload_locked()
            save_daily_payload_to_disk(payload)

        thread = threading.Thread(
            target=daily_scheduler_loop,
            name="cna-daily-scheduler",
            daemon=True,
        )
        thread.start()


@app.before_request
def bootstrap_scheduler() -> None:
    start_scheduler_once()


@app.route("/")
def index() -> str:
    return render_template("index.html")


@app.route("/api/news/audio/<path:filename>")
def serve_audio(filename) -> Any:
    return send_from_directory(str(AUDIO_DIR), filename)


@app.route("/api/categories")
def categories() -> Any:
    payload = [
        {"key": key, "label": info["label"]}
        for key, info in FEEDS.items()
    ]
    return jsonify({"categories": payload})


@app.route("/api/news")
def api_news() -> Any:
    category = request.args.get("category", DEFAULT_CATEGORY).strip().lower()
    if category not in FEEDS:
        return (
            jsonify(
                {
                    "error": "Invalid category.",
                    "available_categories": list(FEEDS.keys()),
                }
            ),
            400,
        )

    limit_raw = request.args.get("limit", "10").strip()
    try:
        limit = int(limit_raw)
    except ValueError:
        return jsonify({"error": "limit must be an integer."}), 400

    limit = max(1, min(limit, MAX_LIMIT))

    try:
        items, payload = get_or_create_category_news(category)
    except Exception as exc:  # noqa: BLE001
        return jsonify({"error": f"Failed to crawl CNA news: {exc}"}), 500

    sliced = items[:limit]

    return jsonify(
        {
            "category": category,
            "count": len(sliced),
            "data_date": payload.get("date"),
            "generated_at": payload.get("generated_at"),
            "items": sliced,
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5050, debug=True)
