# -*- coding: utf-8 -*-
"""把工作台主文（不含附錄）裡引用的檔案路徑與行號抽出來，逐一到真實程式碼查證。"""
import io, os, re, sys

WB = r"C:\Users\kevin\Desktop\115207\Uban\Uban System Documents\第5-2至8章重寫工作台.html"
ROOTS = {
    'uban-api': r"C:\Users\kevin\Desktop\115207\uban-api",
    'mobile': r"C:\Users\kevin\Desktop\115207\Uban\mobile_app",
    'uban': r"C:\Users\kevin\Desktop\115207\Uban",
}

html = io.open(WB, encoding='utf-8').read()
cut = html.index('<section class="appendix">')
main = html[:cut]

# 1) 抽出所有 <code>…</code>（主文）
codes = re.findall(r'<code>(.*?)</code>', main, re.S)
codes = [re.sub(r'<[^>]+>', '', c).strip() for c in codes]

# 2) 也抽出 mermaid 原始碼裡出現的檔名（那些不在 <code> 裡）
mm = '\n'.join(re.findall(r'<script type="text/plain" class="mmsrc">(.*?)</script>', main, re.S))

FILE_RE = re.compile(r'^([A-Za-z0-9_./\-]+\.(?:py|dart|tsx|ts|sql|md|json|yml|yaml))(?::([0-9,\-]+))?$')

def resolve(path):
    """回傳 (實際絕對路徑, 用哪個 root) 或 (None, None)。"""
    cands = []
    if path.startswith('uban-admin/') or path.startswith('routers/') or path.startswith('services/') \
       or path.startswith('scripts/') or path.startswith('tests/') or path in (
           'main.py', 'database.py', 'auth.py', 'auth_developer.py', 'ai_server.py',
           'yolo_detector_service.py', 'stt_controller.py', 'requirements.txt', 'Dockerfile'):
        cands.append((os.path.join(ROOTS['uban-api'], path.replace('/', os.sep)), 'uban-api'))
    # Flutter：可能寫成 lib/xxx 或直接 screens/xxx 或只有檔名
    cands.append((os.path.join(ROOTS['mobile'], 'lib', path.replace('/', os.sep)), 'mobile/lib'))
    cands.append((os.path.join(ROOTS['mobile'], 'lib', 'screens', path.replace('/', os.sep)), 'mobile/lib/screens'))
    cands.append((os.path.join(ROOTS['mobile'], 'lib', 'services', path.replace('/', os.sep)), 'mobile/lib/services'))
    cands.append((os.path.join(ROOTS['mobile'], 'lib', 'screens', 'elder_tabs', path.replace('/', os.sep)), 'mobile/lib/screens/elder_tabs'))
    cands.append((os.path.join(os.path.dirname(ROOTS['uban']), path.replace('/', os.sep)), '115207'))
    cands.append((os.path.join(ROOTS['mobile'], path.replace('/', os.sep)), 'mobile'))
    cands.append((os.path.join(ROOTS['uban-api'], path.replace('/', os.sep)), 'uban-api'))
    cands.append((os.path.join(ROOTS['uban'], path.replace('/', os.sep)), 'uban'))
    for p, tag in cands:
        if os.path.isfile(p):
            return p, tag
    return None, None

def find_by_basename(name):
    """只給檔名時，在兩個專案裡找同名檔。"""
    hits = []
    for tag, root in (('mobile', os.path.join(ROOTS['mobile'], 'lib')), ('uban-api', ROOTS['uban-api'])):
        for dp, dns, fns in os.walk(root):
            dns[:] = [d for d in dns if d not in ('.git', 'node_modules', '.venv', 'venv', '__pycache__', 'build')]
            if name in fns:
                hits.append(os.path.join(dp, name))
    return hits

seen = {}
for c in codes:
    m = FILE_RE.match(c)
    if not m:
        continue
    path, lines = m.group(1), m.group(2)
    seen.setdefault(path, set())
    if lines:
        seen[path].add(lines)

ok, missing, linebad = [], [], []
for path, linesets in sorted(seen.items()):
    real, tag = resolve(path)
    if real is None and '/' not in path:
        hits = find_by_basename(path)
        if len(hits) == 1:
            real, tag = hits[0], 'basename'
        elif len(hits) > 1:
            real, tag = hits[0], 'basename(多個:%d)' % len(hits)
    if real is None:
        missing.append(path)
        continue
    total = sum(1 for _ in io.open(real, encoding='utf-8', errors='ignore'))
    bad = []
    for ls in linesets:
        for part in ls.split(','):
            nums = [int(x) for x in part.split('-') if x.isdigit()]
            for n in nums:
                if n > total:
                    bad.append('%s>檔案共%d行' % (part, total))
    if bad:
        linebad.append((path, sorted(set(bad))))
    ok.append((path, tag, total))

print('=' * 60)
print('主文引用的檔案：%d 個' % len(seen))
print('  可解析 : %d' % len(ok))
print('  找不到 : %d' % len(missing))
print('  行號超出檔案長度 : %d' % len(linebad))
print('=' * 60)
if missing:
    print('\n--- 找不到的檔案 ---')
    for p in missing:
        print('  ✗', p)
if linebad:
    print('\n--- 行號有問題 ---')
    for p, b in linebad:
        print('  ✗', p, b)
print('\n--- 已驗證存在（前 60）---')
for p, tag, total in ok[:60]:
    print('  ✓ %-58s [%s, %d 行]' % (p, tag, total))
