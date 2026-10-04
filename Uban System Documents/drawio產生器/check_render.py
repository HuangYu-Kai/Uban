# -*- coding: utf-8 -*-
"""以 draw.io 實際渲染出來的 SVG 為準，檢查連線有沒有穿過方塊。

為什麼要有這一支：產生器自己算的轉折點是「我們打算怎麼走」，
但 draw.io 會在節點出口與第一個轉折點之間自行補線段，那段只有渲染後才看得到。
用法：先跑 render/dump_svg.mjs 產出 SVG，再 `python check_render.py <svg資料夾>`
"""
import re, os, sys, glob
sys.stdout.reconfigure(encoding='utf-8')
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import dio_parse, dio_layout

NUM = r'-?\d+(?:\.\d+)?'
MARGIN = 4          # 邊緣容差：貼著框走不算穿過

def lane_lines(g):
    """泳道的外框與標題分隔線也是 fill:none 的 path，要排除，否則整排假警報。"""
    xs = set(); ys = {0.0, float(g['head_h']), float(g['total_h'])}
    for lid, x in g['lane_x'].items():
        xs.add(float(x)); xs.add(float(x + g['lane_w'][lid]))
    return xs, ys


def edge_paths(svg):
    """取出所有『沒有填色』的折線 path —— 那就是連線。"""
    out = []
    for m in re.finditer(r'<path\b([^>]*)/?>', svg):
        attrs = m.group(1)
        if 'fill="none"' not in attrs and 'fill:none' not in attrs:
            continue
        d = re.search(r'\bd="([^"]+)"', attrs)
        if not d:
            continue
        cmds = d.group(1)
        if 'C' in cmds or 'A' in cmds or 'Q' in cmds:
            continue                        # 圓角／圓柱的弧線，不是連線
        pts = [(float(a), float(b)) for a, b in re.findall(r'(' + NUM + r')[ ,](' + NUM + r')', cmds)]
        if len(pts) >= 2:
            out.append(pts)
    return out

def node_rects(mmd_path):
    m = dio_layout.layout(dio_parse.parse(mmd_path))
    g = m['geom']
    return [(n['x'], n['y'], n['w'], n['h'], n['id']) for n in m['nodes'].values()], g

def check(svg_dir, mmd_dir):
    total = 0
    for svg_file in sorted(glob.glob(os.path.join(svg_dir, 'A*.svg'))):
        stem = os.path.basename(svg_file)[:-4]
        mmd = os.path.join(mmd_dir, stem + '.mmd')
        if not os.path.exists(mmd):
            continue
        rects, g = node_rects(mmd)
        svg = open(svg_file, encoding='utf-8').read()
        vb = re.search(r'viewBox="(' + NUM + r') (' + NUM + r') (' + NUM + r') (' + NUM + r')"', svg)
        ox, oy = (float(vb.group(1)), float(vb.group(2))) if vb else (0.0, 0.0)
        lx, ly = lane_lines(g)
        bad = []
        for pts in edge_paths(svg):
            if all(any(abs(p[0] + 0 - v) < 2 for v in lx) or any(abs(p[1] + 0 - v) < 2 for v in ly)
                   for p in pts):
                continue                      # 整條都貼在泳道框線上 → 是外框不是連線
            for (ax, ay), (bx, by) in zip(pts, pts[1:]):
                ax, ay, bx, by = ax + ox, ay + oy, bx + ox, by + oy
                x1, x2 = min(ax, bx), max(ax, bx)
                y1, y2 = min(ay, by), max(ay, by)
                for (rx, ry, rw, rh, nid) in rects:
                    if x2 > rx + MARGIN and x1 < rx + rw - MARGIN and y2 > ry + MARGIN and y1 < ry + rh - MARGIN:
                        # 線段的端點就貼在這個方塊的邊界上 → 這是它自己的起點或終點
                        ends = ((ax, ay), (bx, by))
                        if any(abs(px - rx) < 14 or abs(px - (rx + rw)) < 14
                               or abs(py - ry) < 14 or abs(py - (ry + rh)) < 14 for px, py in ends):
                            continue
                        # 整段都在框內 → 是這個節點自己的外框裝飾，不算
                        if x1 >= rx - 1 and x2 <= rx + rw + 1 and y1 >= ry - 1 and y2 <= ry + rh + 1:
                            continue
                        bad.append(nid)
        bad = sorted(set(bad))
        total += len(bad)
        print(('X ' if bad else 'v ') + stem[:24].ljust(26) + ('穿過：' + '、'.join(bad[:6]) if bad else '乾淨'))
    print('---- 被穿過的方塊合計 %d 個 ----' % total)
    return total

if __name__ == '__main__':
    svg_dir = sys.argv[1]
    mmd_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(HERE), 'mermaid原始碼')
    sys.exit(1 if check(svg_dir, mmd_dir) else 0)
