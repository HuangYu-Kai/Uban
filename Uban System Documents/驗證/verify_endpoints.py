# -*- coding: utf-8 -*-
"""抽出工作台主文（含 mermaid 原始碼）提到的 API 端點，比對後端真實路由表。"""
import io, os, re
Q = chr(34); A = chr(39)

WB = r"C:\Users\kevin\Desktop\115207\Uban\Uban System Documents\第5-2至8章重寫工作台.html"
API = r"C:\Users\kevin\Desktop\115207\uban-api"

# ── 1. 建立真實路由表：main.py 的 include_router(prefix) + 各 router 的裝飾器 ──
main_py = io.open(os.path.join(API, 'main.py'), encoding='utf-8').read()
mods = re.findall(r'include_router\(\s*([A-Za-z_][A-Za-z0-9_]*)\.router', main_py)

real = set()
for mod in sorted(set(mods)):
    f = os.path.join(API, 'routers', mod + '.py')
    if not os.path.isfile(f):
        print('!! 找不到 router 檔:', mod)
        continue
    src = io.open(f, encoding='utf-8').read()
    pm = re.search('APIRouter' + chr(92) + '(' + chr(92) + 's*prefix' + chr(92) + 's*=' + chr(92) + 's*[' + Q + A + '](['+chr(94)+Q+A+']*)[' + Q + A + ']', src)
    prefix = pm.group(1) if pm else ''
    for m in re.finditer('@router' + chr(92) + '.(get|post|put|patch|delete|websocket)' + chr(92) + '(' + chr(92) + 's*[' + Q + A + '](['+chr(94)+Q+A+']*)[' + Q + A + ']', src):
        verb, path = m.group(1).upper(), m.group(2)
        real.add((verb, (prefix + path) or '/'))

# main.py 自帶的 app-level 端點
for m in re.finditer(r'@app\.(get|post|put|patch|delete)\(\s*["\']([^"\']*)["\']', main_py):
    real.add((m.group(1).upper(), m.group(2)))

def norm(p):
    """把 {xxx} 參數統一成 {} 以便比對。"""
    p = re.sub(r'\{[^}]*\}', '{}', p)
    return p.rstrip('/') or '/'

real_norm = {(v, norm(p)) for v, p in real}
real_paths = {norm(p) for v, p in real}

# ── 2. 抽出工作台提到的端點 ──
html = io.open(WB, encoding='utf-8').read()
main_txt = html[:html.index('<section class="appendix">')]
plain = re.sub(r'<br\s*/?>', ' ', main_txt)
plain = re.sub(r'<[^>]+>', ' ', plain)

cited = set()
for m in re.finditer(r'\b(GET|POST|PUT|PATCH|DELETE|WEBSOCKET)\s+(/[A-Za-z0-9_/{}\-\.]*)', plain):
    cited.add((m.group(1), norm(m.group(2))))

# ── 3. 比對 ──
ok, bad = [], []
for verb, path in sorted(cited):
    if (verb, path) in real_norm:
        ok.append((verb, path, 'exact'))
    elif path in real_paths:
        bad.append((verb, path, '路徑存在但 HTTP 方法對不上'))
    else:
        # 容許工作台寫的是相對簡寫（例如 /accounts/me/password 省略 /api/developer）
        suffix_hit = [p for p in real_paths if p.endswith(path)]
        if suffix_hit:
            ok.append((verb, path, '簡寫→' + suffix_hit[0]))
        else:
            bad.append((verb, path, '查無此路由'))

print('後端真實路由：%d 支' % len(real_norm))
print('工作台引用端點：%d 個  →  對得上 %d，對不上 %d' % (len(cited), len(ok), len(bad)))
if bad:
    print('\n--- 對不上的 ---')
    for v, p, why in bad:
        print('  X %-7s %-46s %s' % (v, p, why))
print('\n--- 非 exact（簡寫）的，人工確認 ---')
for v, p, why in ok:
    if why != 'exact':
        print('  ~ %-7s %-46s %s' % (v, p, why))
