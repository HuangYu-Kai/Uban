from __future__ import annotations

import json
import re
import threading
import time
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from typing import Any

import requests
from bs4 import BeautifulSoup
from flask import Flask, jsonify, render_template, request

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
CACHE_TTL_SECONDS = 300

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/125.0.0.0 Safari/537.36"
    )
}

_cache_lock = threading.Lock()
_cache: dict[tuple[str, int], tuple[float, list[dict[str, str]]]] = {}


def normalize_text(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


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


def find_news_article_jsonld(html: str) -> dict[str, Any] | None:
    soup = BeautifulSoup(html, "html.parser")
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


def extract_article(url: str, fallback_category: str, fallback_title: str) -> dict[str, str] | None:
    try:
        html = fetch_text(url)
    except requests.RequestException:
        return None

    article = find_news_article_jsonld(html)
    if article:
        category = normalize_text(str(article.get("articleSection") or fallback_category))
        title = normalize_text(str(article.get("headline") or fallback_title))
        content = normalize_text(str(article.get("articleBody") or ""))

        if title and content:
            return {
                "category": category or fallback_category,
                "title": title,
                "content": content,
            }

    soup = BeautifulSoup(html, "html.parser")
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


def get_news_with_cache(category_key: str, limit: int) -> list[dict[str, str]]:
    cache_key = (category_key, limit)
    now = time.time()

    with _cache_lock:
        cached = _cache.get(cache_key)
        if cached and now - cached[0] <= CACHE_TTL_SECONDS:
            return list(cached[1])

    news = crawl_news(category_key, limit)

    with _cache_lock:
        _cache[cache_key] = (now, news)

    return list(news)


@app.route("/")
def index() -> str:
    return render_template("index.html")


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
        items = get_news_with_cache(category, limit)
    except Exception as exc:  # noqa: BLE001
        return jsonify({"error": f"Failed to crawl CNA news: {exc}"}), 500

    return jsonify(
        {
            "category": category,
            "count": len(items),
            "items": items,
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5050, debug=True)
