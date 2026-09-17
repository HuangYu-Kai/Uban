# -*- coding: utf-8 -*-
"""5-2 使用個案圖：.mmd → .drawio（火柴人在系統邊界外、橢圓使用案例、依角色上色）。

mermaid 畫不出火柴人，只能用圓形代替；draw.io 有 umlActor，這裡改回組長原圖的畫法。
"""
import re, os, sys, glob

ACTOR = re.compile(r'^\s*(\w+)\(\("(.*?)"\)\)(?::::(\w+))?\s*$')
UC    = re.compile(r'^\s*(\w+)\(\["(.*?)"\]\)(?::::(\w+))?\s*$')
EV    = re.compile(r'^\s*(\w+)\["(.*?)"\](?::::(\w+))?\s*$')
SUB   = re.compile(r'^\s*subgraph\s+(\w+)\["(.*?)"\]\s*$')
LINK  = re.compile(r'^\s*(\w+)\s*---\s*(\w+)\s*$')
CDEF  = re.compile(r'^\s*classDef\s+(\w+)\s+(.*)$')

FONT, LINE_H = 20, 26
ACT_W, ACT_H = 74, 112
GAP_Y, GAP_X = 26, 90
PAD, HEAD = 26, 42
MAXCH = 12


def _w(ch):
    return FONT if ord(ch) > 0x2E80 else FONT * 0.55


def wrap(t):
    out = []
    for seg in re.split(r'<br\s*/?>', t):
        seg = seg.strip()
        if not seg:
            continue
        cur = ''
        for ch in seg:
            if sum(_w(c) for c in cur + ch) > MAXCH * FONT:
                out.append(cur)
                cur = ch
            else:
                cur += ch
        if cur:
            out.append(cur)
    return out or ['']


def parse(path):
    actors, boxes, order = [], [], []
    nodes, links, styles = {}, [], {}
    cur = None
    for line in open(path, encoding='utf-8').read().split('\n'):
        if line.lstrip().startswith(('%%', 'flowchart', 'direction', 'class ')) or '~~~' in line:
            continue
        m = CDEF.match(line)
        if m:
            d = dict(re.findall(r'(fill|stroke|color)\s*:\s*(#[0-9A-Fa-f]{6})', m.group(2)))
            styles[m.group(1)] = d
            continue
        m = SUB.match(line)
        if m:
            cur = m.group(1)
            boxes.append(dict(id=cur, title=m.group(2), items=[]))
            continue
        if line.strip() == 'end':
            cur = None
            continue
        m = ACTOR.match(line)
        if m:
            nodes[m.group(1)] = dict(id=m.group(1), kind='actor', label=m.group(2), cls=m.group(3) or '')
            actors.append(m.group(1))
            continue
        m = UC.match(line)
        if m:
            nodes[m.group(1)] = dict(id=m.group(1), kind='uc', label=m.group(2), cls=m.group(3) or '', box=cur)
            if cur:
                boxes[-1]['items'].append(m.group(1))
            order.append(m.group(1))
            continue
        m = EV.match(line)
        if m:
            nodes[m.group(1)] = dict(id=m.group(1), kind='ev', label=m.group(2), cls=m.group(3) or '', box=cur)
            if cur:
                boxes[-1]['items'].append(m.group(1))
            order.append(m.group(1))
            continue
        m = LINK.match(line)
        if m:
            links.append((m.group(1), m.group(2)))
    return dict(actors=actors, boxes=boxes, nodes=nodes, links=links, styles=styles, order=order)


def size(n):
    if n['kind'] == 'actor':
        return ACT_W, ACT_H
    ls = wrap(n['label'])
    w = max(max(sum(_w(c) for c in l) for l in ls) + 40, 180)
    return round(w), max(len(ls) * LINE_H + 24, 46)


def layout_overview(m):
    """總覽圖沒有事件，改成多個系統邊界並排，各自的火柴人放在自己邊界左邊。
    否則 29 個使用案例會排成一直行，變成 482x2298 的細長條。"""
    N = m['nodes']
    for n in N.values():
        n['w'], n['h'] = size(n)
    owner = {}
    for a, b in m['links']:
        if a in N and N[a]['kind'] == 'actor' and b in N and N[b]['kind'] == 'uc':
            owner.setdefault(N[b].get('box'), a)
    x = 10
    bottom = HEAD + 20
    for box in m['boxes']:
        ucs = [i for i in box['items'] if N[i]['kind'] == 'uc']
        w = max([N[i]['w'] for i in ucs] or [160])
        ax = x
        x += ACT_W + GAP_X - 30
        box['x0'] = x
        box['x1'] = x + w + PAD * 2
        y = HEAD + 24
        box['y0'] = y
        for u in ucs:
            N[u]['x'] = box['x0'] + PAD + (w - N[u]['w']) / 2
            N[u]['y'] = y
            y += N[u]['h'] + GAP_Y
        box['y1'] = y
        box['ucs'], box['evs'] = ucs, {u: [] for u in ucs}
        a = owner.get(box['id'])
        if a:
            N[a]['x'] = ax
            N[a]['y'] = round((box['y0'] + box['y1']) / 2 - ACT_H / 2)
        bottom = max(bottom, y)
        x = box['x1'] + GAP_X
    for b in m['boxes']:
        b['y1'] = bottom
    # 沒被任何邊界認領的節點（例如沒連到使用案例的火柴人）也要有座標
    leftover = [n for n in N.values() if 'x' not in n]
    ly = HEAD + 24
    for n in leftover:
        n['x'] = 10
        n['y'] = ly
        ly += n['h'] + GAP_Y
        bottom = max(bottom, ly)
    m['W'] = x + 10
    m['H'] = bottom + 60
    return m


def layout(m):
    if not any(n['kind'] == 'ev' for n in m['nodes'].values()):
        return layout_overview(m)
    N = m['nodes']
    for n in N.values():
        n['w'], n['h'] = size(n)
    kids = {}
    for a, b in m['links']:
        kids.setdefault(a, []).append(b)
    y = HEAD + 20
    for box in m['boxes']:
        ucs = [i for i in box['items'] if N[i]['kind'] == 'uc']
        evs = {u: [k for k in kids.get(u, []) if N.get(k, {}).get('kind') == 'ev'] for u in ucs}
        box['y0'] = y
        for u in ucs:
            block = max(N[u]['h'], sum(N[e]['h'] for e in evs[u]) + GAP_Y * max(0, len(evs[u]) - 1))
            N[u]['y'] = round(y + (block - N[u]['h']) / 2)
            ey = y
            for e in evs[u]:
                N[e]['y'] = round(ey)
                ey += N[e]['h'] + GAP_Y
            y += block + GAP_Y
        box['y1'] = y
        y += 46
        box['ucs'], box['evs'] = ucs, evs
    ucw = max([N[i]['w'] for b in m['boxes'] for i in b['ucs']] or [160])
    evw = max([N[e]['w'] for b in m['boxes'] for u in b['ucs'] for e in b['evs'][u]] or [0])
    x_box = ACT_W + GAP_X + 20
    x_uc = x_box + PAD
    x_ev = x_uc + ucw + GAP_X
    for b in m['boxes']:
        for u in b['ucs']:
            N[u]['x'] = x_uc + (ucw - N[u]['w']) / 2
            for e in b['evs'][u]:
                N[e]['x'] = x_ev
        b['x0'], b['x1'] = x_box, x_ev + (evw or 0) + PAD
    # 火柴人：對齊它連到的使用案例的垂直中心
    for a in m['actors']:
        ys = [N[u]['y'] + N[u]['h'] / 2 for x, u in m['links'] if x == a and u in N and N[u]['kind'] == 'uc']
        N[a]['x'] = 10
        N[a]['y'] = round((sum(ys) / len(ys) - ACT_H / 2) if ys else HEAD + 20)
    m['W'] = max(b['x1'] for b in m['boxes']) + 20
    m['H'] = y + 10
    return m


def style_of(m, n):
    d = m['styles'].get(n['cls'], {})
    fill = d.get('fill', '#FFFFFF')
    stroke = d.get('stroke', '#000000')
    col = d.get('color', '#000000')
    base = 'html=1;fontSize=%d;fillColor=%s;strokeColor=%s;fontColor=%s;whiteSpace=wrap;' % (FONT, fill, stroke, col)
    if n['kind'] == 'actor':
        return 'shape=umlActor;verticalLabelPosition=bottom;verticalAlign=top;' + base + 'fillColor=none;'
    if n['kind'] == 'uc':
        return 'ellipse;' + base
    return 'rounded=1;arcSize=20;' + base


def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')


def lab(s):
    return '&lt;br&gt;'.join(esc(x) for x in wrap(s))


def to_xml(m, title):
    o = ['<mxfile host="uban-doc"><diagram name="%s">' % esc(title),
         '<mxGraphModel dx="1400" dy="900" grid="0" gridSize="10" guides="1" tooltips="1" connect="1" '
         'arrows="1" fold="1" page="1" pageScale="1" pageWidth="%d" pageHeight="%d" math="0" shadow="0">'
         % (m['W'] + 60, m['H'] + 60),
         '<root><mxCell id="0"/><mxCell id="1" parent="0"/>']
    for b in m['boxes']:
        o.append('<mxCell id="box_%s" value="%s" style="rounded=0;html=1;fillColor=none;strokeColor=#000000;'
                 'verticalAlign=top;fontSize=23;fontColor=#000000;" vertex="1" parent="1">'
                 % (b['id'], esc(b['title'])))
        o.append('<mxGeometry x="%g" y="%g" width="%g" height="%g" as="geometry"/></mxCell>'
                 % (b['x0'], b['y0'] - 34, b['x1'] - b['x0'], b['y1'] - b['y0'] + 42))
    for nid, n in m['nodes'].items():
        o.append('<mxCell id="n_%s" value="%s" style="%s" vertex="1" parent="1">'
                 % (nid, lab(n['label']), style_of(m, n)))
        o.append('<mxGeometry x="%g" y="%g" width="%g" height="%g" as="geometry"/></mxCell>'
                 % (n['x'], n['y'], n['w'], n['h']))
    for i, (a, b) in enumerate(m['links']):
        if a not in m['nodes'] or b not in m['nodes']:
            continue
        o.append('<mxCell id="l%d" style="edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;endArrow=none;'
                 'strokeColor=#000000;exitX=1;exitY=0.5;entryX=0;entryY=0.5;exitPerimeter=0;entryPerimeter=0;" '
                 'edge="1" parent="1" source="n_%s" target="n_%s"><mxGeometry relative="1" as="geometry"/></mxCell>'
                 % (i, a, b))
    o.append('</root></mxGraphModel></diagram></mxfile>')
    return '\n'.join(o)


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    HERE = os.path.dirname(os.path.abspath(__file__))
    SRC = os.path.join(os.path.dirname(HERE), 'mermaid原始碼')
    OUT = os.path.join(os.path.dirname(HERE), 'drawio圖')
    for f in sorted(glob.glob(os.path.join(SRC, 'D52*.mmd'))):
        stem = os.path.basename(f)[:-4]
        m = layout(parse(f))
        open(os.path.join(OUT, stem + '.drawio'), 'w', encoding='utf-8', newline='').write(to_xml(m, stem))
        print('%-24s %4d x %4d  火柴人%d 使用案例%d 事件%d'
              % (stem[:22], m['W'], m['H'], len(m['actors']),
                 sum(1 for n in m['nodes'].values() if n['kind'] == 'uc'),
                 sum(1 for n in m['nodes'].values() if n['kind'] == 'ev')))
