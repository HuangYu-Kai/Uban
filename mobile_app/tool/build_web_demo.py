#!/usr/bin/env python3
"""Build + slim the Flutter Web survey demo.

用法（在 mobile_app/ 下執行）：
    python tool/build_web_demo.py [--server https://host | http://127.0.0.1:8010]
                                  [--skip-flutter --from DIR] [--out DIR] [--install]

產出（預設 mobile_app/build/web_demo_out）可整個複製到 Uban-api/static/demo：
    <out>/index.html, shell.css, shell.js, vendor/...   <- 來自 mobile_app/web_demo/（排除 app_index.html、mock/）
    <out>/config.js                                     <- 示意監視機（monitor.js）的 STUN/TURN 設定，建置時產生
    <out>/app/...                                       <- Flutter build（base-href /demo/app/），已瘦身
    <out>/build_id.txt

瘦身內容：
  * 移除 flutter_service_worker.js 與 bootstrap 的 serviceWorkerSettings（Flutter 3.41 已無
    --pwa-strategy 旗標，所以改成建置後處理）
  * 移除本機 canvaskit/（bootstrap 在有 engineRevision 且未設 useLocalCanvasKit 時走 gstatic CDN）
  * 刪除 lib/**/*.dart 完全沒引用的素材，並同步改寫 AssetManifest.bin / .bin.json
  * NotoSansTC 子集化（只留 Regular / Bold 兩份真資料，其餘字重路徑放同內容副本，
    因 google_fonts 會依檔名從 AssetManifest 找），FontManifest 只列 2 個 NotoSansTC 讓開機只下載兩份
  * StarPanda / Inter 子集化
  * 圖片就地壓成 WebP（檔名與副檔名不變，Flutter 依內容判斷格式）
  * 預壓縮 .br(q11) 與 .gz
"""
from __future__ import annotations

import argparse
import ast
import base64
import gzip
import hashlib
import io
import json
import multiprocessing as mp
import os
import re
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
MOBILE = HERE.parent                      # mobile_app
REPO = MOBILE.parent                      # Uban repo
API_STATIC_DEMO = (MOBILE / ".." / ".." / "Uban-api" / "static" / "demo").resolve()
API_DIR = (MOBILE / ".." / ".." / "Uban-api").resolve()
DEFAULT_OUT = MOBILE / "build" / "web_demo_out"
WORK = MOBILE / "build" / "web_demo_work"
DEFAULT_SERVER = "localhost-0.tail5abf5e.ts.net"
BASE_HREF = "/demo/app/"

FONT_ALIASES = {"Medium": "Regular", "SemiBold": "Bold", "ExtraBold": "Bold", "Black": "Bold"}
FETCH_SHIM = (
    "(function(){var m={" + ",".join(f'"{k}":"{v}"' for k, v in FONT_ALIASES.items()) + "};"
    r"var r=/(assets\/assets\/fonts\/NotoSansTC-)(" + "|".join(FONT_ALIASES) + r")(\.ttf)/;"
    "var f=window.fetch;window.fetch=function(u,o){try{var s=typeof u==='string'?u:(u&&u.url);"
    "if(s&&r.test(s)){var n=s.replace(r,function(_,a,b,c){return a+m[b]+c});"
    "u=typeof u==='string'?n:new Request(n,u)}}catch(e){}return f.call(this,u,o)}})();\n"
)
IMG_EXT = {".png", ".jpg", ".jpeg"}
COMPRESS_EXT = {".js", ".mjs", ".json", ".html", ".css", ".ttf", ".otf", ".wasm", ".svg", ".glb",
                ".frag", ".bin", ".wav", ".txt", ".xml", ".md"}


# --------------------------------------------------------------------------- helpers
def log(*a):
    print("[web_demo]", *a, flush=True)


def human(n: float) -> str:
    for u in ("B", "KB", "MB", "GB"):
        if abs(n) < 1024 or u == "GB":
            return f"{n:.0f} {u}" if u == "B" else f"{n:.2f} {u}"
        n /= 1024
    return str(n)


def dir_size(p: Path, skip_ext=()) -> int:
    return sum(f.stat().st_size for f in p.rglob("*") if f.is_file() and f.suffix not in skip_ext)


def shell_config() -> str:
    """外殼的示意監視機要用的 ICE 設定（與 Flutter 端同一組 TURN，來源相同的環境變數）。"""
    ice = [{"urls": "stun:stun.l.google.com:19302"}]
    server = os.environ.get("TURN_SERVER")
    if server:
        ice.append({"urls": [f"turn:{server}", f"turn:{server}?transport=tcp"],
                    "username": os.environ.get("TURN_USER", ""), "credential": os.environ.get("TURN_PASS", "")})
    return "window.UBAN_DEMO_ICE = " + json.dumps(ice) + ";\n"


def rmtree(p: Path):
    def onerr(fn, path, exc):
        os.chmod(path, 0o700)
        fn(path)
    if p.exists():
        shutil.rmtree(p, onerror=onerr)


# --------------------------------------------------------------------------- StandardMessageCodec (AssetManifest.bin)
def _rv(b, i):
    n = b[i]
    i += 1
    if n < 254:
        return n, i
    if n == 254:
        return struct.unpack_from("<H", b, i)[0], i + 2
    return struct.unpack_from("<I", b, i)[0], i + 4


def _wv(n):
    if n < 254:
        return bytes([n])
    if n <= 0xFFFF:
        return b"\xfe" + struct.pack("<H", n)
    return b"\xff" + struct.pack("<I", n)


def smc_decode(b, i=0):
    t = b[i]
    i += 1
    if t == 0:
        return None, i
    if t == 1:
        return True, i
    if t == 2:
        return False, i
    if t == 3:
        return struct.unpack_from("<i", b, i)[0], i + 4
    if t == 4:
        return struct.unpack_from("<q", b, i)[0], i + 8
    if t == 6:
        i += (-i) % 8
        return struct.unpack_from("<d", b, i)[0], i + 8
    if t == 7:
        n, i = _rv(b, i)
        return b[i:i + n].decode("utf8"), i + n
    if t == 12:
        n, i = _rv(b, i)
        out = []
        for _ in range(n):
            v, i = smc_decode(b, i)
            out.append(v)
        return out, i
    if t == 13:
        n, i = _rv(b, i)
        out = {}
        for _ in range(n):
            k, i = smc_decode(b, i)
            v, i = smc_decode(b, i)
            out[k] = v
        return out, i
    raise ValueError(f"unsupported SMC type {t}")


def smc_encode(v, out: bytearray):
    if v is None:
        out.append(0)
    elif v is True:
        out.append(1)
    elif v is False:
        out.append(2)
    elif isinstance(v, int):
        if -2**31 <= v < 2**31:
            out.append(3)
            out += struct.pack("<i", v)
        else:
            out.append(4)
            out += struct.pack("<q", v)
    elif isinstance(v, float):
        out.append(6)
        out += b"\0" * ((-len(out)) % 8)
        out += struct.pack("<d", v)
    elif isinstance(v, str):
        d = v.encode("utf8")
        out.append(7)
        out += _wv(len(d)) + d
    elif isinstance(v, list):
        out.append(12)
        out += _wv(len(v))
        for x in v:
            smc_encode(x, out)
    elif isinstance(v, dict):
        out.append(13)
        out += _wv(len(v))
        for k, x in v.items():
            smc_encode(k, out)
            smc_encode(x, out)
    else:
        raise TypeError(type(v))


class AssetManifest:
    """app/assets/AssetManifest.bin(.json)。"""

    def __init__(self, assets_dir: Path):
        self.dir = assets_dir
        self.data, _ = smc_decode((assets_dir / "AssetManifest.bin").read_bytes())

    def variants(self, key):
        return [v["asset"] for v in self.data[key]]

    def save(self):
        out = bytearray()
        smc_encode(self.data, out)
        (self.dir / "AssetManifest.bin").write_bytes(bytes(out))
        (self.dir / "AssetManifest.bin.json").write_text(
            json.dumps(base64.b64encode(bytes(out)).decode("ascii")), encoding="utf8")

    def remove(self, key) -> int:
        """從 manifest 與磁碟移除 key（含 variant 檔）；回傳釋放 bytes。"""
        freed = 0
        for a in self.variants(key):
            f = self.dir / a
            if f.is_file():
                freed += f.stat().st_size
                f.unlink()
        del self.data[key]
        return freed


# --------------------------------------------------------------------------- dart source analysis
def pkg_name() -> str:
    m = re.search(r"^name:\s*(\S+)", (MOBILE / "pubspec.yaml").read_text(encoding="utf8"), re.M)
    return m.group(1) if m else "flutter_application_1"


def read_dart(p: Path) -> str:
    return p.read_text(encoding="utf8", errors="ignore")


def reachable_dart(entry: Path) -> dict[Path, str]:
    pk = pkg_name()
    lib = MOBILE / "lib"
    seen: dict[Path, str] = {}
    stack = [entry.resolve()]
    pat = re.compile(r"""(?:\bimport|\bexport|\bpart|\bif\s*\([^)]*\))\s+(?:of\s+)?['"]([^'"]+)['"]""")
    while stack:
        f = stack.pop()
        if f in seen or not f.is_file():
            continue
        txt = read_dart(f)
        seen[f] = txt
        for m in pat.finditer(txt):
            u = m.group(1)
            if u.startswith("dart:") or (u.startswith("package:") and not u.startswith(f"package:{pk}/")):
                continue
            if u.startswith(f"package:{pk}/"):
                stack.append((lib / u[len(f"package:{pk}/"):]).resolve())
            else:
                stack.append((f.parent / u).resolve())
    return seen


class AssetRefs:
    def __init__(self, texts: list[str]):
        self.text = "\n".join(texts)
        self.regexes = []
        for lit in re.findall(r"""['"]([^'"\n]*\$[^'"\n]*)['"]""", self.text):
            if not re.search(r"\.(png|jpe?g|webp|json|mp3|wav|glb|ogg|svg|gif|txt|tflite)\b|assets/", lit):
                continue
            parts = re.split(r"\$\{[^}]*\}|\$[A-Za-z_]\w*", lit)
            rx = ".*".join(re.escape(p) for p in parts)
            try:
                self.regexes.append(re.compile(rx))
            except re.error:
                pass

    def referenced(self, key: str) -> bool:
        t = self.text
        base = key.rsplit("/", 1)[-1]
        stem = base.rsplit(".", 1)[0]
        if key in t or base in t or (len(stem) >= 4 and stem in t):
            return True
        d = key.rsplit("/", 1)[0]
        # 目錄被當前綴（例如 'assets/images/pet_seq_idle'）→ 整個目錄保留
        if d not in ("assets/images", "assets/sounds", "assets/models", "assets/fonts"):
            segs = d.split("/")
            # 取目錄路徑（含後綴子目錄如 2.0x）
            for n in range(len(segs), 1, -1):
                pre = "/".join(segs[:n])
                if pre in ("assets/images", "assets/sounds", "assets/models", "assets/fonts"):
                    break
                if pre in t:
                    return True
        return any(rx.search(key) for rx in self.regexes)


# --------------------------------------------------------------------------- charset
def collect_chars() -> str:
    chars: set[str] = set()

    def add(s):
        chars.update(c for c in s if ord(c) > 0x7F)

    for f in (MOBILE / "lib").rglob("*.dart"):
        add(read_dart(f))
    wd = MOBILE / "web_demo"
    if wd.is_dir():
        for f in wd.rglob("*"):
            if f.suffix in {".html", ".js", ".css", ".json", ".txt", ".md"} and "vendor" not in f.parts:
                add(f.read_text(encoding="utf8", errors="ignore"))
    if API_DIR.is_dir():
        for f in API_DIR.rglob("*.py"):
            if any(p in f.parts for p in ("venv", ".venv", "site-packages", "__pycache__", "node_modules", "tests")):
                continue
            try:
                tree = ast.parse(f.read_text(encoding="utf8", errors="ignore"))
            except Exception:
                continue
            for n in ast.walk(tree):
                if isinstance(n, ast.Constant) and isinstance(n.value, str):
                    add(n.value)
    # Big5 level 1 (A440-C67E)
    for hi in range(0xA4, 0xC7):
        for lo in list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF)):
            if hi == 0xC6 and lo > 0x7E:
                break
            try:
                chars.add(bytes([hi, lo]).decode("big5"))
            except UnicodeDecodeError:
                pass
    ranges = [(0x20, 0x7E), (0xA0, 0x24F), (0x2010, 0x2060), (0x2190, 0x21FF), (0x2460, 0x24FF),
              (0x25A0, 0x26FF), (0x2E80, 0x2EFF), (0x3000, 0x303F), (0x3100, 0x312F), (0x31A0, 0x31BF),
              (0xFE30, 0xFE4F), (0xFF00, 0xFFEF)]
    for a, b in ranges:
        chars.update(chr(c) for c in range(a, b + 1))
    return "".join(sorted(chars))


LATIN = "".join(chr(c) for c in list(range(0x20, 0x7F)) + list(range(0xA0, 0x180)) + list(range(0x2010, 0x2060))
                + list(range(0x2190, 0x2200)))


def subset_font_job(args):
    src, dst, text, keep_layout = args
    from fontTools import subset
    from fontTools.ttLib import TTFont
    o = subset.Options()
    o.hinting = False
    o.layout_features = ["kern", "locl", "ccmp", "vert", "vrt2", "liga", "mark", "mkmk", "calt", "ss01", "case"] \
        if keep_layout else ["kern", "liga", "locl", "ccmp", "mark", "mkmk"]
    o.name_IDs = [1, 2, 3, 4, 6]
    o.notdef_outline = True
    o.glyph_names = False
    o.legacy_kern = False
    o.drop_tables += ["DSIG", "FFTM"]
    f = TTFont(src)
    s = subset.Subsetter(o)
    s.populate(text=text)
    s.subset(f)
    f.save(dst)
    return dst, Path(dst).stat().st_size


# --------------------------------------------------------------------------- images
def image_job(args):
    path, max_side = args
    from PIL import Image
    p = Path(path)
    before = p.stat().st_size
    if before < 20 * 1024:
        return path, before, before, "skip-small"
    try:
        im = Image.open(p)
        im.load()
    except Exception as e:
        return path, before, before, f"skip-{e}"
    if im.format == "WEBP":
        return path, before, before, "skip-webp"
    w, h = im.size
    long_, short = max(w, h), min(w, h)
    cap = max_side
    if long_ / max(short, 1) > 1.8:      # 很寬/很高的長圖，放寬長邊上限以免短邊過小
        cap = int(max_side * 2.2)
    if long_ > cap:
        r = cap / long_
        im = im.resize((max(1, round(w * r)), max(1, round(h * r))), Image.LANCZOS)
    has_alpha = im.mode in ("RGBA", "LA", "P") and (im.mode != "P" or "transparency" in im.info)
    if has_alpha:
        im = im.convert("RGBA")
    else:
        im = im.convert("RGB")
    buf = io.BytesIO()
    im.save(buf, "WEBP", quality=80, method=5, exact=has_alpha)
    data = buf.getvalue()
    if len(data) >= before * 0.95:
        return path, before, before, "skip-larger"
    p.write_bytes(data)
    return path, before, len(data), "ok"


# --------------------------------------------------------------------------- compression
def compress_job(path):
    import brotli
    p = Path(path)
    raw = p.read_bytes()
    n_br = n_gz = 0
    b = brotli.compress(raw, quality=11, lgwin=22)
    if len(b) < len(raw) * 0.97:
        Path(str(p) + ".br").write_bytes(b)
        n_br = len(b)
    g = io.BytesIO()
    with gzip.GzipFile(fileobj=g, mode="wb", compresslevel=9, mtime=0) as z:
        z.write(raw)
    if len(g.getvalue()) < len(raw) * 0.97:
        Path(str(p) + ".gz").write_bytes(g.getvalue())
        n_gz = len(g.getvalue())
    return path, len(raw), n_br, n_gz


# --------------------------------------------------------------------------- flutter
def run_flutter(args, work_app: Path):
    target = Path(args.target)
    if not target.is_absolute():
        target = MOBILE / target
    if not target.is_file():
        sys.exit(f"找不到進入點 {target}（lib/main_demo.dart 還沒好？可用 --target lib/main.dart 試跑）")
    server = args.server or os.environ.get("DEMO_SERVER") or DEFAULT_SERVER
    cmd = ["flutter", "build", "web", "--release", "-t", str(target.relative_to(MOBILE)) if target.is_relative_to(MOBILE) else str(target),
           "--base-href", BASE_HREF, "--no-wasm-dry-run", "--no-source-maps",
           "--output", str(work_app), f"--dart-define=SERVER_IP={server}"]
    for k in ("TURN_SERVER", "TURN_USER", "TURN_PASS", "MAP_TILE_URL"):
        if os.environ.get(k):
            cmd.append(f"--dart-define={k}={os.environ[k]}")
    log("flutter:", " ".join(c if "PASS" not in c else "--dart-define=TURN_PASS=***" for c in cmd))
    rmtree(work_app)
    r = subprocess.run(cmd, cwd=MOBILE, shell=(os.name == "nt"))
    if r.returncode:
        sys.exit("flutter build 失敗")


# --------------------------------------------------------------------------- main pipeline
def finalize_index(app: Path, args):
    """index.html、bootstrap 後處理，移除 service worker。"""
    boot_p = app / "flutter_bootstrap.js"
    boot = boot_p.read_text(encoding="utf8")
    boot = re.sub(r"_flutter\.loader\.load\(\{.*?\}\);?\s*$", "_flutter.loader.load();", boot, flags=re.S)
    boot = FETCH_SHIM + boot
    boot_p.write_text(boot, encoding="utf8")
    (app / "flutter_service_worker.js").unlink(missing_ok=True)

    src = MOBILE / "web_demo" / "app_index.html"
    if src.is_file():
        html = src.read_text(encoding="utf8")
        html = html.replace("$FLUTTER_BASE_HREF", BASE_HREF)
        html = html.replace("{{flutter_service_worker_version}}", "null")
        html = html.replace("{{flutter_js}}", "")
        html = html.replace("{{flutter_bootstrap_js}}", f"<script>{boot}</script>".replace("<script>", "").replace("</script>", "")
                            if False else boot)
        if "{{" in html and "flutter_bootstrap_js" in html:
            sys.exit("app_index.html 仍有未解析 token")
        # 若原本是 <script>{{flutter_bootstrap_js}}</script> 則已內嵌；否則維持外部 flutter_bootstrap.js
        (app / "index.html").write_text(html, encoding="utf8")
        log("index.html <- web_demo/app_index.html")
    else:
        log("警告：web_demo/app_index.html 不存在，沿用 Flutter 產生的 index.html")


def prune_and_slim(app: Path, args, entry: Path):
    assets = app / "assets"
    report: dict = {"removed": [], "fonts": [], "images": []}
    man = AssetManifest(assets)

    # ---- 引用分析
    all_texts = [read_dart(f) for f in (MOBILE / "lib").rglob("*.dart")]
    refs_all = AssetRefs(all_texts)
    reach = reachable_dart(entry)
    refs_reach = AssetRefs(list(reach.values()))
    log(f"lib dart {len(all_texts)} 檔，自 {entry.name} 可達 {len(reach)} 檔")

    keep_models = args.keep_models
    freed = 0
    fixed_dirs = ("assets/fonts/",)  # 字型另外處理
    for key in sorted(man.data):
        if key.startswith(fixed_dirs) or key == ".env":
            continue
        why = None
        if key.startswith("assets/"):
            if key.startswith(("assets/models/", "assets/sounds/")) and not keep_models:
                if not refs_reach.referenced(key):
                    why = "unreachable-from-entry"
            elif not refs_all.referenced(key):
                why = "unreferenced"
            if key.startswith("assets/images/NotoSansTC-"):
                why = None  # 下面字型步驟處理
        elif key.startswith("packages/flutter_inappwebview/assets/t_rex_runner"):
            why = "package-unneeded"
        elif key.startswith("packages/model_viewer_plus/") and not keep_models and not any(
                "model_viewer_plus" in t for t in reach.values()):
            why = "package-unneeded"
        if why:
            sz = man.remove(key)
            freed += sz
            report["removed"].append((key, sz, why))
    # NOTICES
    notices = assets / "NOTICES"
    if notices.is_file() and not args.keep_notices:
        report["removed"].append(("NOTICES", notices.stat().st_size, "license-text"))
        freed += notices.stat().st_size
        notices.unlink()
    # 空目錄
    for d in sorted((p for p in assets.rglob("*") if p.is_dir()), key=lambda p: -len(p.parts)):
        if not any(d.iterdir()):
            d.rmdir()
    log(f"素材修剪釋出 {human(freed)}（{len(report['removed'])} 項）")

    # ---- 字型
    text = collect_chars()
    log(f"子集字元數（非 ASCII 部分含 Big5 一級）：{len(text)}")
    fdir = assets / "assets" / "fonts"
    jobs = []
    work_fonts = app.parent / "_fonts_tmp"
    rmtree(work_fonts)
    work_fonts.mkdir(parents=True)
    src_reg, src_bold = fdir / "NotoSansTC-Regular.ttf", fdir / "NotoSansTC-Bold.ttf"
    have_noto = src_reg.is_file() and src_bold.is_file()
    if have_noto:
        jobs.append((str(src_reg), str(work_fonts / "R.ttf"), text, True))
        jobs.append((str(src_bold), str(work_fonts / "B.ttf"), text, True))
    for f in sorted(fdir.glob("Inter-*.ttf")):
        jobs.append((str(f), str(work_fonts / f.name), LATIN, True))
    star = fdir / "StarPandaKids.otf"
    if star.is_file():
        np = MOBILE / "lib" / "screens" / "news_listen_player"
        star_text = "".join(sorted(set(LATIN) | {c for f in np.rglob("*.dart") for c in read_dart(f) if ord(c) > 0x7F}))
        jobs.append((str(star), str(work_fonts / "StarPanda.otf"), star_text, True))
    before_fonts = dir_size(fdir) + sum(
        (assets / k).stat().st_size for k in ("assets/images/NotoSansTC-Thin.ttf",) if (assets / k).is_file())
    with mp.Pool(min(len(jobs), os.cpu_count() or 2)) as pool:
        res = pool.map(subset_font_job, jobs) if jobs else []
    sizes = {Path(d).name: s for d, s in res}
    for d, s in res:
        report["fonts"].append((Path(d).name, s))

    if have_noto:
        # 只出貨 Regular / Bold 兩份真資料。google_fonts 會依 AssetManifest 的檔名找 Medium/SemiBold/
        # ExtraBold/Black，所以 manifest 的 key 保留，但磁碟上不放檔案；flutter_bootstrap.js 開頭注入
        # fetch 轉址（見 FETCH_SHIM），把這四個路徑導向 Regular / Bold，瀏覽器只會下載 2 份。
        shutil.copyfile(work_fonts / "R.ttf", fdir / "NotoSansTC-Regular.ttf")
        shutil.copyfile(work_fonts / "B.ttf", fdir / "NotoSansTC-Bold.ttf")
        for name in FONT_ALIASES:
            (fdir / f"NotoSansTC-{name}.ttf").unlink(missing_ok=True)
        # assets/images/ 下 google_fonts 用的 5MB 副本全部移除（程式沒有用 w100/w300，沒有 Thin/Light 需求）
        for key in list(man.data):
            if key.startswith("assets/images/NotoSansTC-"):
                sz = man.remove(key)
                report["removed"].append((key, sz, "google_fonts-duplicate"))
    for f in work_fonts.glob("Inter-*.ttf"):
        shutil.copyfile(f, fdir / f.name)
    if (work_fonts / "StarPanda.otf").is_file():
        shutil.copyfile(work_fonts / "StarPanda.otf", star)
    rmtree(work_fonts)

    # assets/fonts 下沒被 FontManifest 或 google_fonts 使用的檔案（CupertinoIcons 副本、MaterialIcons 完整版）
    fm_p = assets / "FontManifest.json"
    fm = json.loads(fm_p.read_text(encoding="utf8"))
    used = {f["asset"] for fam in fm for f in fam["fonts"]}
    for key in sorted(man.data):
        if key.startswith("assets/fonts/") and key not in used and not re.search(
                r"/(NotoSansTC|Inter)-[A-Za-z]+\.ttf$", key):
            sz = man.remove(key)
            report["removed"].append((key, sz, "font-unused"))

    # FontManifest：NotoSansTC 只列 Regular+Bold
    for fam in fm:
        if fam["family"] == "NotoSansTC":
            fam["fonts"] = [{"weight": 400, "asset": "assets/fonts/NotoSansTC-Regular.ttf"},
                            {"weight": 700, "asset": "assets/fonts/NotoSansTC-Bold.ttf"}]
    fm_p.write_text(json.dumps(fm, separators=(",", ":")), encoding="utf8")
    man.save()
    return report, before_fonts, fm


def recompress_images(app: Path, report, workers: int):
    assets = app / "assets"
    jobs = []
    for f in assets.rglob("*"):
        if f.is_file() and f.suffix.lower() in IMG_EXT and "packages" not in f.relative_to(assets).parts[:1]:
            rel = f.relative_to(assets).as_posix()
            ms = 512 if "/pet_seq_" in rel else 1080
            jobs.append((str(f), ms))
    with mp.Pool(workers) as pool:
        res = pool.map(image_job, jobs, chunksize=2)
    report["images"] = res
    b = sum(r[1] for r in res)
    a = sum(r[2] for r in res)
    log(f"圖片 {len(res)} 張：{human(b)} -> {human(a)}")


def precompress(root: Path, workers: int):
    files = [str(f) for f in root.rglob("*")
             if f.is_file() and f.suffix in COMPRESS_EXT and f.stat().st_size > 1024]
    # 大檔先做
    files.sort(key=lambda p: -os.path.getsize(p))
    with mp.Pool(workers) as pool:
        res = pool.map(compress_job, files, chunksize=1)
    return {Path(p).resolve(): (raw, br, gz) for p, raw, br, gz in res}


def first_load_estimate(out: Path, comp, fm):
    """index + shell + bootstrap + main.dart.js.br + FontManifest 字型.br + manifest。"""
    app = out / "app"
    items = []

    def best(p: Path):
        p = p.resolve()
        if p in comp and comp[p][1]:
            return comp[p][1]
        return p.stat().st_size if p.is_file() else 0

    for rel in ("index.html", "shell.css", "shell.js"):
        if (out / rel).is_file():
            items.append((rel, best(out / rel)))
    for rel in ("index.html", "flutter_bootstrap.js", "flutter.js", "main.dart.js", "version.json",
                "manifest.json", "favicon.png", "assets/AssetManifest.bin.json", "assets/FontManifest.json",
                "assets/.env", "assets/shaders/ink_sparkle.frag", "assets/shaders/stretch_effect.frag"):
        if (app / rel).is_file():
            items.append(("app/" + rel, best(app / rel)))
    for fam in fm:
        for f in fam["fonts"]:
            p = app / "assets" / f["asset"]
            if not p.is_file():
                p = app / "assets" / "assets" / f["asset"] if False else p
            # FontManifest 的 asset 相對於 assets/；pubspec 內宣告的檔案在 assets/assets/...
            p2 = app / "assets" / f["asset"]
            if p2.is_file():
                items.append(("font " + f["asset"], best(p2)))
    return items


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--server", help="後端：host 或完整 URL（https://host、http://127.0.0.1:8010）→ SERVER_IP")
    ap.add_argument("--skip-flutter", action="store_true", help="跳過 flutter build，搭配 --from")
    ap.add_argument("--from", dest="from_dir", help="既有 flutter build web 輸出目錄（不會被修改）")
    ap.add_argument("--out", help=f"輸出目錄（預設 {DEFAULT_OUT}）")
    ap.add_argument("--install", action="store_true", help=f"另外鏡像到 {API_STATIC_DEMO}")
    ap.add_argument("--target", default="lib/main_demo.dart", help="Flutter 進入點（預設 lib/main_demo.dart）")
    ap.add_argument("--keep-canvaskit", action="store_true", help="保留本機 canvaskit/（預設刪除，走 gstatic CDN）")
    ap.add_argument("--keep-models", "--keep-heavy", dest="keep_models", action="store_true",
                    help="保留 3D 模型(.glb)、音檔與 model_viewer（預設只留進入點可達程式碼引用的）")
    ap.add_argument("--keep-notices", action="store_true")
    ap.add_argument("--no-images", action="store_true", help="略過圖片重壓縮")
    ap.add_argument("--no-compress", action="store_true", help="略過 .br/.gz 預壓縮")
    ap.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    args = ap.parse_args()

    t0 = time.time()
    out = Path(args.out).resolve() if args.out else DEFAULT_OUT
    work_app = WORK / "app"
    WORK.mkdir(parents=True, exist_ok=True)

    if args.skip_flutter:
        if not args.from_dir:
            sys.exit("--skip-flutter 需要 --from DIR")
        src = Path(args.from_dir).resolve()
        if not (src / "flutter_bootstrap.js").is_file():
            sys.exit(f"{src} 不像 flutter build web 輸出")
        rmtree(work_app)
        log("複製", src, "->", work_app)
        shutil.copytree(src, work_app)
    else:
        run_flutter(args, work_app)

    raw_total = dir_size(work_app)
    log("原始 build 大小", human(raw_total))
    entry = MOBILE / args.target
    if not entry.is_file():
        entry = MOBILE / "lib" / "main.dart"

    # 1. 後處理 index / sw / canvaskit
    finalize_index(work_app, args)
    cv = work_app / "canvaskit"
    cv_size = dir_size(cv) if cv.is_dir() else 0
    boot = (work_app / "flutter_bootstrap.js").read_text(encoding="utf8")
    cdn_ok = '"engineRevision"' in boot and "useLocalCanvasKit" not in re.sub(r"function.*", "", boot.split("_flutter.buildConfig")[-1])
    if not args.keep_canvaskit and cv.is_dir():
        if cdn_ok:
            rmtree(cv)
            log(f"移除本機 canvaskit/（{human(cv_size)}），改走 gstatic CDN")
        else:
            log("buildConfig 無 engineRevision，保留 canvaskit/")
    for junk in ("flutter.js.map", "main.dart.js.map", "main.dart.js.deps"):
        (work_app / junk).unlink(missing_ok=True)

    # 2-3. 素材與字型
    report, before_fonts, fm = prune_and_slim(work_app, args, entry)

    # 4. 圖片
    if not args.no_images:
        recompress_images(work_app, report, args.workers)

    # build id
    bid = time.strftime("%Y%m%d-%H%M%S")
    h = hashlib.sha1((work_app / "main.dart.js").read_bytes()).hexdigest()[:10]
    build_id = f"{bid}-{h}"
    (work_app / "build_id.txt").write_text(build_id + "\n", encoding="utf8")

    # 組合輸出
    marker = out / "build_id.txt"
    if out.exists() and any(out.iterdir()) and not marker.is_file():
        sys.exit(f"輸出目錄 {out} 非空且不是先前的 build 輸出，請換一個 --out")
    rmtree(out)
    out.mkdir(parents=True)
    wd = MOBILE / "web_demo"
    if wd.is_dir():
        for p in wd.iterdir():
            if p.name in ("app_index.html", "mock"):
                continue
            if p.is_dir():
                shutil.copytree(p, out / p.name)
            else:
                shutil.copyfile(p, out / p.name)
    else:
        log("警告：mobile_app/web_demo 不存在，只輸出 app/")
    (out / "config.js").write_text(shell_config(), encoding="utf8")
    shutil.copytree(work_app, out / "app")
    marker.write_text(build_id + "\n", encoding="utf8")

    # 6. 預壓縮
    comp = {}
    if not args.no_compress:
        comp = precompress(out, args.workers)
    # 統計
    shipped_orig = sum(f.stat().st_size for f in out.rglob("*") if f.is_file() and f.suffix not in (".br", ".gz"))
    shipped_all = dir_size(out)
    est = first_load_estimate(out, comp, fm)

    # ---- 報告
    print("\n================ 摘要 ================")
    print(f"build id              : {build_id}")
    print(f"原始 Flutter build    : {human(raw_total)}")
    print(f"素材修剪 / 字型 / 圖片 : -{human(sum(r[1] for r in report['removed']))} / "
          f"字型 {human(before_fonts)} -> {human(sum(s for _, s in report['fonts']))} / "
          f"圖片 {human(sum(r[1] for r in report['images']))} -> {human(sum(r[2] for r in report['images']))}")
    print(f"輸出（原檔，不含 .br/.gz）: {human(shipped_orig)}")
    print(f"輸出（含 .br/.gz 全部） : {human(shipped_all)}   <- 實際部署大小")
    print("---- 首次載入估算（我方主機傳輸，br）----")
    tot = 0
    for name, sz in est:
        tot += sz
        print(f"  {human(sz):>10}  {name}")
    print(f"  {human(tot):>10}  合計（另加 gstatic CanvasKit ≈ 6-7 MB br、依需求的 Noto 後備字型/表情字）")
    print("---- 移除的素材 ----")
    by = {}
    for k, s, why in report["removed"]:
        by.setdefault(why, []).append((k, s))
    for why, lst in by.items():
        print(f"  [{why}] {len(lst)} 項 {human(sum(s for _, s in lst))}")
        for k, s in sorted(lst, key=lambda x: -x[1])[:12]:
            print(f"      {human(s):>10}  {k}")
    print("---- 字型子集 ----")
    for n, s in report["fonts"]:
        print(f"  {human(s):>10}  {n}")
    print(f"耗時 {time.time() - t0:.0f}s；輸出 {out}")

    # 7. install
    if args.install:
        dst = API_STATIC_DEMO
        if not (API_DIR.is_dir()):
            sys.exit(f"找不到 {API_DIR}")
        dst.mkdir(parents=True, exist_ok=True)
        want = {p.relative_to(out) for p in out.rglob("*") if p.is_file()}
        for p in list(dst.rglob("*")):
            if p.is_file() and p.relative_to(dst) not in want:
                p.unlink()
        for rel in want:
            d = dst / rel
            d.parent.mkdir(parents=True, exist_ok=True)
            s = out / rel
            if not d.exists() or d.stat().st_size != s.stat().st_size or d.read_bytes() != s.read_bytes():
                shutil.copyfile(s, d)
        for d in sorted((p for p in dst.rglob("*") if p.is_dir()), key=lambda p: -len(p.parts)):
            if not any(d.iterdir()):
                d.rmdir()
        log("已鏡像到", dst)


if __name__ == "__main__":
    mp.freeze_support()
    main()
