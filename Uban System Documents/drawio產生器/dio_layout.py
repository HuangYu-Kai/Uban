# -*- coding: utf-8 -*-
"""分層排版：垂直泳道分欄、縱軸＝流程時間、由上往下讀。"""
import re
from collections import defaultdict, deque

FONT   = 20
LINE_H = 26
PAD_X  = 30
PAD_Y  = 22
MIN_W  = 170
MAX_CH = 15          # 一行最多幾個中文字寬，超過就折行
COL_GAP   = 44       # 同一排、同一道裡兩個節點的水平間距
ROW_GAP   = 54       # 排與排之間的垂直留白（走線通道）
LANE_PAD  = 26       # 泳道左右內縮
HEAD_H    = 60       # 泳道標題列高度

def _w(ch):
    return FONT if ord(ch) > 0x2E80 else FONT * 0.55

def text_w(s):
    return sum(_w(c) for c in s)

def wrap(label):
    """依 <br/> 斷行，過長的再折。中文標點不落在行首、行尾不留單字。"""
    CLOSE = '）)」』】》,.;:、。？！%'
    OPEN  = '（(「『【《'
    out = []
    for seg in re.split(r'<br\s*/?>', label):
        seg = seg.strip()
        if not seg:
            continue
        limit = MAX_CH * FONT
        if text_w(seg) <= limit:
            out.append(seg); continue
        cur, lines = '', []
        for token in re.findall(r'[A-Za-z0-9_./{}\-]+|\s+|[^\sA-Za-z0-9_./{}\-]', seg):
            if text_w(cur + token) > limit and cur.strip() and token not in CLOSE:
                lines.append(cur.strip()); cur = token.lstrip()
            else:
                cur += token
        if cur.strip():
            lines.append(cur.strip())
        # 行首的收尾標點往前一行挪；行尾的開頭標點往後一行挪
        fixed = []
        for ln in lines:
            while ln and ln[0] in CLOSE and fixed:
                fixed[-1] += ln[0]; ln = ln[1:]
            if fixed and len(fixed[-1]) > 1 and fixed[-1][-1] in OPEN:
                ln = fixed[-1][-1] + ln; fixed[-1] = fixed[-1][:-1]
            if ln:
                fixed.append(ln)
        # 只剩一兩個字的尾行，從上一行借字回來湊
        if len(fixed) > 1 and len(fixed[-1]) <= 2 and text_w(fixed[-2] + fixed[-1]) <= limit * 1.18:
            fixed[-2] += fixed[-1]; fixed.pop()
        out += fixed
    return out or ['']

def size(node):
    if node['shape'] in ('start', 'end'):
        return (46, 46)
    lines = wrap(node['label'])
    w = max(MIN_W, max(text_w(l) for l in lines) + PAD_X)
    h = len(lines) * LINE_H + PAD_Y
    if node['shape'] == 'decision':
        w = max(w * 1.25, 110); h = max(h * 1.7, 72)
    if node['shape'] == 'db':
        h += 12
    return (round(w), round(h))

def rank_nodes(model):
    """破環後用最長路徑分層；回程邊（back edge）不影響層級。"""
    nodes, edges = model['nodes'], model['edges']
    succ = defaultdict(list); pred = defaultdict(list)
    for e in edges:
        succ[e['src']].append(e['dst']); pred[e['dst']].append(e['src'])
    order = model['order']
    idx = {n: i for i, n in enumerate(order)}
    # DFS 找回程邊
    color = {}; back = set()
    def dfs(u):
        color[u] = 1
        for v in succ[u]:
            if color.get(v, 0) == 1:
                back.add((u, v))
            elif color.get(v, 0) == 0:
                dfs(v)
        color[u] = 2
    for n in order:
        if color.get(n, 0) == 0:
            dfs(n)
    fwd = [(e['src'], e['dst']) for e in edges if (e['src'], e['dst']) not in back]
    indeg = defaultdict(int); fsucc = defaultdict(list)
    for s, t in fwd:
        indeg[t] += 1; fsucc[s].append(t)
    rank = {n: 0 for n in nodes}
    q = deque(sorted([n for n in nodes if indeg[n] == 0], key=lambda n: idx[n]))
    seen = set(q)
    while q:
        u = q.popleft()
        for v in fsucc[u]:
            rank[v] = max(rank[v], rank[u] + 1)
            indeg[v] -= 1
            if indeg[v] == 0:
                q.append(v); seen.add(v)
    for n in nodes:                      # 環裡的節點沒被拓樸走到，補一個合理層級
        if n not in seen:
            ps = [rank[p] for p in pred[n] if p in seen]
            rank[n] = (max(ps) + 1) if ps else 0
    return rank, back

def layout(model):
    nodes = model['nodes']
    lane_ids = [l[0] for l in model['lanes']]
    rank, back = rank_nodes(model)
    for n in nodes.values():
        n['w'], n['h'] = size(n)
        n['rank'] = rank[n['id']]

    # 每排、每道有哪些節點（照宣告順序）
    cell = defaultdict(list)
    for nid in model['order']:
        n = nodes[nid]
        cell[(n['rank'], n['lane'])].append(nid)

    # 同一道同一排擠超過 3 個就折到下一個子排，免得整張圖被撐得又扁又寬
    MAXPERROW = 3
    for key, ns in list(cell.items()):
        for i, nid in enumerate(ns):
            nodes[nid]['sub'] = i // MAXPERROW
    for n in nodes.values():
        n.setdefault('sub', 0)
    cell = defaultdict(list)
    for nid in model['order']:
        n = nodes[nid]
        cell[(n['rank'], n['sub'], n['lane'])].append(nid)
    ranks = sorted({(n['rank'], n['sub']) for n in nodes.values()})
    # 泳道寬度＝該道在所有排裡最寬的那一排
    lane_w = {}
    for lid in lane_ids:
        need = 0
        for r in ranks:
            ns = cell[(r[0], r[1], lid)]
            if ns:
                need = max(need, sum(nodes[x]['w'] for x in ns) + COL_GAP * (len(ns) - 1))
        lane_w[lid] = max(need + LANE_PAD * 2, 200)
    widest = max(lane_w.values())           # 各道用自然寬度，但設下限，免得窄道細成一條
    lane_w = {lid: max(w, widest * 0.45, 240) for lid, w in lane_w.items()}
    lane_x = {}; x = 0
    for lid in lane_ids:
        lane_x[lid] = x; x += lane_w[lid]
    total_w = x

    # 每排高度
    row_y = {}; y = HEAD_H + ROW_GAP // 2
    for r in ranks:
        hs = [nodes[x]['h'] for x in nodes if (nodes[x]['rank'], nodes[x]['sub']) == r]
        rh = max(hs) if hs else 40
        row_y[r] = (y, rh)
        y += rh + ROW_GAP
    total_h = y

    for (r, sub, lid), ns in cell.items():
        if not ns:
            continue
        span = sum(nodes[x]['w'] for x in ns) + COL_GAP * (len(ns) - 1)
        cx = lane_x[lid] + lane_w[lid] / 2 - span / 2
        top, rh = row_y[(r, sub)]
        for nid in ns:
            n = nodes[nid]
            n['x'] = round(cx); n['y'] = round(top + (rh - n['h']) / 2)
            cx += n['w'] + COL_GAP

    model['geom'] = dict(lane_x=lane_x, lane_w=lane_w, row_y=row_y,
                         total_w=total_w, total_h=total_h,
                         head_h=HEAD_H, back=back, ranks=ranks)
    return model
