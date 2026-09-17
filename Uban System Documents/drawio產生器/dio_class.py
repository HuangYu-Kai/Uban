# -*- coding: utf-8 -*-
"""5-4 分析類別圖：.mmd（classDiagram）→ .drawio（真正的三欄式 UML 類別框）。

mermaid 的類別框只能平塗；draw.io 用 swimlane + stackLayout 可以做出組長原圖那種
「類別名一欄、屬性一欄」的標準 UML 類別框，而且組員可以直接拖拉修改。
"""
import re, os, sys, glob
from collections import defaultdict, deque
import dio_route

CLS_OPEN = re.compile(r'^\s*class\s+(\S+)\s*\{\s*$')
CLS_TAG  = re.compile(r'^\s*class\s+(\S+?):::(\w+)\s*$')
CDEF     = re.compile(r'^\s*classDef\s+(\w+)\s+(.*)$')
REL      = re.compile(r'^\s*(\S+?)\s*(?:"([^"]*)")?\s*(<\|--|--\|>|\*--|o--|-->|<--|\.\.>|\.\.|--)\s*(?:"([^"]*)")?\s*(\S+?)\s*(?::\s*(.*))?$')

FONT = 20
ROW_H = 28
TITLE_H = 42
PAD_X = 34
COL_GAP = 80
ROW_GAP = 110
MARGIN = 30


def _w(ch):
    return FONT if ord(ch) > 0x2E80 else FONT * 0.56


def text_w(s):
    return sum(_w(c) for c in s)


def parse(path):
    classes, order, rels, styles, tags = {}, [], [], {}, {}
    cur = None
    for line in open(path, encoding='utf-8').read().split('\n'):
        t = line.rstrip()
        if not t.strip() or t.lstrip().startswith(('%%', 'classDiagram', 'direction')):
            continue
        m = CDEF.match(t)
        if m:
            styles[m.group(1)] = dict(re.findall(r'(fill|stroke|color)\s*:\s*(#[0-9A-Fa-f]{6})', m.group(2)))
            continue
        m = CLS_TAG.match(t)
        if m:
            tags[m.group(1)] = m.group(2)
            continue
        m = CLS_OPEN.match(t)
        if m:
            cur = m.group(1)
            classes[cur] = []
            order.append(cur)
            continue
        if cur is not None:
            if t.strip() == '}':
                cur = None
            else:
                classes[cur].append(t.strip())
            continue
        m = REL.match(t)
        if m and m.group(1) in classes and m.group(5) in classes:
            rels.append(dict(a=m.group(1), am=m.group(2) or '', kind=m.group(3),
                             bm=m.group(4) or '', b=m.group(5), label=(m.group(6) or '').strip()))
    return dict(classes=classes, order=order, rels=rels, styles=styles, tags=tags)


def layout(m):
    C = m['classes']
    size = {}
    for name, attrs in C.items():
        w = max([text_w(name)] + [text_w(a) for a in attrs]) + PAD_X * 2
        size[name] = (round(max(w, 220)), TITLE_H + ROW_H * len(attrs) + 10)
    # 以關聯建圖，用 BFS 分層（從連結最多的類別出發）
    adj = defaultdict(set)
    for r in m['rels']:
        adj[r['a']].add(r['b'])
        adj[r['b']].add(r['a'])
    rank = {}
    remaining = list(m['order'])
    base = 0
    while remaining:
        root = max(remaining, key=lambda n: len(adj[n]))
        q = deque([(root, base)])
        seen = {root}
        while q:
            u, d = q.popleft()
            rank[u] = d
            for v in adj[u]:
                if v not in seen:
                    seen.add(v)
                    q.append((v, d + 1))
        remaining = [n for n in remaining if n not in rank]
        base = max(rank.values()) + 1 if rank else 0
    rows = defaultdict(list)
    for n in m['order']:
        rows[rank.get(n, 0)].append(n)
    pos, y = {}, MARGIN
    width = 0
    for d in sorted(rows):
        names = rows[d]
        span = sum(size[n][0] for n in names) + COL_GAP * (len(names) - 1)
        width = max(width, span)
        h = max(size[n][1] for n in names)
        x = MARGIN
        for n in names:
            pos[n] = (x, y + (h - size[n][1]) / 2)
            x += size[n][0] + COL_GAP
        y += h + ROW_GAP
    # 每一列置中
    for d in sorted(rows):
        names = rows[d]
        span = sum(size[n][0] for n in names) + COL_GAP * (len(names) - 1)
        off = (width - span) / 2
        for n in names:
            pos[n] = (pos[n][0] + off, pos[n][1])
    m['size'], m['pos'] = size, pos
    m['W'], m['H'] = width + MARGIN * 2, y - ROW_GAP + MARGIN
    # 組成 dio_route 認得的模型，沿用活動圖那套避障走線（draw.io 自動路由會穿過方塊）
    nodes = {}
    for n in m['order']:
        x, yy = pos[n]
        w, h = size[n]
        nodes[n] = dict(id=n, x=x, y=yy, w=w, h=h, lane='ALL',
                        rank=rank.get(n, 0), sub=0)
    ranks = sorted({(nodes[n]['rank'], 0) for n in nodes})
    row_y = {}
    for r in ranks:
        ns = [nodes[n] for n in nodes if (nodes[n]['rank'], 0) == r]
        row_y[r] = (min(q['y'] for q in ns), max(q['h'] for q in ns))
    m['rt'] = dict(nodes=nodes,
                   edges=[dict(src=r['a'], dst=r['b'], label='', dashed=False, arrow=True) for r in m['rels']],
                   lanes=[('ALL', '')], order=list(m['order']),
                   geom=dict(lane_x={'ALL': 0}, lane_w={'ALL': m['W']}, row_y=row_y,
                             total_w=m['W'], total_h=m['H'], head_h=0, ranks=ranks))
    return m


def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')


ARROW = {
    '<|--': ('block', 1, 'none'),
    '--|>': ('none', 0, 'block'),
    '*--':  ('diamondThin', 1, 'none'),
    'o--':  ('diamondThin', 0, 'none'),
    '-->':  ('none', 0, 'open'),
    '<--':  ('open', 0, 'none'),
    '..':   ('none', 0, 'none'),
    '..>':  ('none', 0, 'open'),
    '--':   ('none', 0, 'none'),
}


def to_xml(m, title):
    o = ['<mxfile host="uban-doc"><diagram name="%s">' % esc(title),
         '<mxGraphModel dx="1400" dy="900" grid="0" gridSize="10" guides="1" tooltips="1" connect="1" '
         'arrows="1" fold="1" page="1" pageScale="1" pageWidth="%d" pageHeight="%d" math="0" shadow="0">'
         % (m['W'] + 60, m['H'] + 60),
         '<root><mxCell id="0"/><mxCell id="1" parent="0"/>']
    ids = {}
    for i, name in enumerate(m['order']):
        cid = 'c%d' % i
        ids[name] = cid
        st = m['styles'].get(m['tags'].get(name, ''), {})
        fill = st.get('fill', '#FFFFFF')
        stroke = st.get('stroke', '#000000')
        col = st.get('color', '#000000')
        x, y = m['pos'][name]
        w, h = m['size'][name]
        o.append('<mxCell id="%s" value="%s" style="swimlane;fontStyle=1;childLayout=stackLayout;horizontal=1;'
                 'startSize=%d;horizontalStack=0;resizeParent=1;resizeParentMax=0;resizeLast=0;collapsible=0;'
                 'marginBottom=0;html=1;fontSize=%d;fillColor=%s;strokeColor=%s;fontColor=%s;" vertex="1" parent="1">'
                 % (cid, esc(name), TITLE_H, FONT + 1, fill, stroke, col))
        o.append('<mxGeometry x="%g" y="%g" width="%g" height="%g" as="geometry"/></mxCell>' % (x, y, w, h))
        for j, a in enumerate(m['classes'][name]):
            o.append('<mxCell id="%s_a%d" value="%s" style="text;strokeColor=none;fillColor=none;align=left;'
                     'verticalAlign=middle;spacingLeft=12;spacingRight=4;overflow=hidden;rotatable=0;points=[[0,0.5],[1,0.5]];'
                     'portConstraint=eastwest;html=1;fontSize=%d;fontColor=%s;" vertex="1" parent="%s">'
                     % (cid, j, esc(a), FONT, col, cid))
            o.append('<mxGeometry y="%d" width="%g" height="%d" as="geometry"/></mxCell>'
                     % (TITLE_H + ROW_H * j, w, ROW_H))
    for i, r in enumerate(m['rels']):
        start, fill, end = ARROW.get(r['kind'], ('none', 0, 'none'))
        dashed = ';dashed=1' if r['kind'].startswith('..') else ''
        rt = m['rt']
        slot = m.setdefault('_slot', {})
        n1 = rt['nodes'][r['a']]
        ck = (n1['rank'], 0, rt['nodes'][r['b']]['rank'] <= n1['rank'])
        srcs = slot.setdefault(ck, [])
        if r['a'] not in srcs:
            srcs.append(r['a'])
        pts = dio_route.route(rt, rt['edges'][i], srcs.index(r['a']))
        o.append('<mxCell id="r%d" value="%s" style="edgeStyle=none;rounded=0;html=1;'
                 'endArrow=%s;endFill=%d;startArrow=%s;startFill=%d;strokeColor=#000000;fontSize=%d;'
                 'fontColor=#000000;labelBackgroundColor=#FFFFFF%s;" edge="1" parent="1" source="%s" target="%s">'
                 % (i, esc(r['label']), end, 1 if end != 'none' else 0, start, fill, FONT - 3, dashed,
                    ids[r['a']], ids[r['b']]))
        back = rt['edges'][i].get('_side') == 'TOP'
        if back:
            st_extra = 'exitX=0.5;exitY=1;entryX=0.25;entryY=0;'
        else:
            st_extra = 'exitX=0.5;exitY=1;entryX=0.5;entryY=0;'
        o[-1] = o[-1].replace('labelBackgroundColor=#FFFFFF',
                              'labelBackgroundColor=#FFFFFF;exitPerimeter=0;entryPerimeter=0;' + st_extra)
        if pts:
            o.append('<mxGeometry relative="1" as="geometry"><Array as="points">')
            for px, py in pts:
                o.append('<mxPoint x="%g" y="%g"/>' % (px, py))
            o.append('</Array></mxGeometry></mxCell>')
        else:
            o.append('<mxGeometry relative="1" as="geometry"/></mxCell>')
        for tag, frac in (('am', -0.75), ('bm', 0.75)):
            if r[tag]:
                o.append('<mxCell id="r%d_%s" value="%s" style="edgeLabel;html=1;align=center;verticalAlign=middle;'
                         'resizable=0;points=[];fontSize=%d;fontColor=#000000;labelBackgroundColor=#FFFFFF;" '
                         'vertex="1" connectable="0" parent="r%d">' % (i, tag, esc(r[tag]), FONT - 3, i))
                o.append('<mxGeometry x="%g" relative="1" as="geometry"><mxPoint as="offset"/></mxGeometry></mxCell>'
                         % frac)
    o.append('</root></mxGraphModel></diagram></mxfile>')
    return '\n'.join(o)


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    HERE = os.path.dirname(os.path.abspath(__file__))
    SRC = os.path.join(os.path.dirname(HERE), 'mermaid原始碼')
    OUT = os.path.join(os.path.dirname(HERE), 'drawio圖')
    for f in sorted(glob.glob(os.path.join(SRC, 'D54*.mmd'))):
        stem = os.path.basename(f)[:-4]
        m = layout(parse(f))
        open(os.path.join(OUT, stem + '.drawio'), 'w', encoding='utf-8', newline='').write(to_xml(m, stem))
        print('%-26s %4d x %4d  類別%d 關聯%d 屬性%d'
              % (stem[:24], m['W'], m['H'], len(m['classes']), len(m['rels']),
                 sum(len(v) for v in m['classes'].values())))
