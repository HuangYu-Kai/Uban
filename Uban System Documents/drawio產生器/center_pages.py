# -*- coding: utf-8 -*-
"""把 .drawio 的內容整張平移到頁面正中間（不動內部排版）。

用法：python center_pages.py <資料夾或檔案> [...]
  - A4 分頁版（1654×1169）：保留頁面大小，內容置中。
  - 其他：內容從 (PAD, PAD) 開始，頁面＝內容＋四邊各 PAD。
只平移最上層的方塊與連線轉折點；容器（泳道、分組）內的子元素是相對座標，跟著容器走。
"""
import sys, os, glob, zlib, base64, urllib.parse
import xml.etree.ElementTree as ET

PAD = 40
A4 = (1654.0, 1169.0)

def _models(root):
    for d in root.iter('diagram'):
        m = d.find('mxGraphModel')
        if m is None and (d.text or '').strip():
            raw = zlib.decompress(base64.b64decode(d.text.strip()), -15).decode()
            m = ET.fromstring(urllib.parse.unquote(raw))
            d.text = None
            d.append(m)
        if m is not None:
            yield m

def _abs(cells, c):
    x = y = 0.0
    while c is not None:
        g = c.find('mxGeometry')
        if g is not None and g.get('relative') != '1' and c.get('vertex') == '1':
            x += float(g.get('x', 0)); y += float(g.get('y', 0))
        c = cells.get(c.get('parent'))
    return x, y

def center_model(m):
    cells = {c.get('id'): c for c in m.iter('mxCell')}
    layers = {cid for cid, c in cells.items() if c.get('parent') in (None, '0') or cid == '0'}
    xs, ys = [], []
    for c in cells.values():
        g = c.find('mxGeometry')
        if g is None:
            continue
        if c.get('vertex') == '1':
            # 掛在連線上的標籤（多重度 1、0..* 等）是相對於連線的座標，不算進外框
            if g.get('relative') == '1' or cells.get(c.get('parent'), c).get('edge') == '1':
                continue
            x, y = _abs(cells, c)
            xs += [x, x + float(g.get('width', 0))]; ys += [y, y + float(g.get('height', 0))]
        elif c.get('edge') == '1' and c.get('parent') in layers:
            for p in g.iter('mxPoint'):
                if p.get('as') != 'offset':
                    xs.append(float(p.get('x', 0))); ys.append(float(p.get('y', 0)))
    if not xs:
        return False
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    pw, ph = float(m.get('pageWidth', 0)), float(m.get('pageHeight', 0))
    if (pw, ph) == A4 and x1 - x0 <= pw and y1 - y0 <= ph:
        dx, dy = (pw - (x1 - x0)) / 2 - x0, (ph - (y1 - y0)) / 2 - y0
    else:
        dx, dy = PAD - x0, PAD - y0
        m.set('pageWidth', '%g' % round(x1 - x0 + PAD * 2))
        m.set('pageHeight', '%g' % round(y1 - y0 + PAD * 2))
    dx, dy = round(dx), round(dy)
    if dx == 0 and dy == 0:
        return False
    for c in cells.values():
        if c.get('parent') not in layers or c.get('id') in layers:
            continue
        g = c.find('mxGeometry')
        if g is None:
            continue
        if c.get('vertex') == '1':
            g.set('x', '%g' % (float(g.get('x', 0)) + dx)); g.set('y', '%g' % (float(g.get('y', 0)) + dy))
        elif c.get('edge') == '1':
            for p in g.iter('mxPoint'):
                if p.get('as') != 'offset':
                    p.set('x', '%g' % (float(p.get('x', 0)) + dx)); p.set('y', '%g' % (float(p.get('y', 0)) + dy))
    return True

def center_file(path):
    tree = ET.parse(path)
    changed = [center_model(m) for m in _models(tree.getroot())]
    if any(changed):
        tree.write(path, encoding='utf-8', xml_declaration=False)
    return any(changed)

if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    for arg in sys.argv[1:]:
        files = sorted(glob.glob(os.path.join(arg, '*.drawio'))) if os.path.isdir(arg) else [arg]
        for f in files:
            print(('置中 ' if center_file(f) else '已置中 ') + os.path.basename(f))
