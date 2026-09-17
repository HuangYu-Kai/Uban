# -*- coding: utf-8 -*-
"""自己算正交走線的轉折點，並避開方塊（draw.io 的自動路由不會避障）。

踩過的坑：
  1. 只驗垂直線段不夠，水平線段一樣會穿過方塊。
  2. 把並行的線錯開時，通道會被推進下一排的範圍裡 —— 必須夾在排與排的空隙內。
真正的驗收以 check_render.py（量 draw.io 實際渲染的 SVG）為準。
"""
from dio_layout import ROW_GAP

CLEAR = 12          # 線與方塊要保持的距離
STUB  = 22          # 離開來源後先直走這麼長，決策分岔才不會變成一條平的橫桿

def _cx(n): return n['x'] + n['w'] / 2
def _cy(n): return n['y'] + n['h'] / 2

def _others(model, exclude):
    return [n for n in model['nodes'].values() if n['id'] not in exclude]

def _v_blocked(model, x, ya, yb, exclude):
    ya, yb = min(ya, yb), max(ya, yb)
    for n in _others(model, exclude):
        if n['y'] - CLEAR < yb and n['y'] + n['h'] + CLEAR > ya and \
           n['x'] - CLEAR < x < n['x'] + n['w'] + CLEAR:
            return True
    return False

def _h_blocked(model, y, xa, xb, exclude):
    xa, xb = min(xa, xb), max(xa, xb)
    for n in _others(model, exclude):
        if n['x'] - CLEAR < xb and n['x'] + n['w'] + CLEAR > xa and \
           n['y'] - CLEAR < y < n['y'] + n['h'] + CLEAR:
            return True
    return False

def _search(want, lo, hi, ok):
    if lo <= want <= hi and ok(want):
        return want, True
    for step in range(10, 1200, 10):
        for cand in (want - step, want + step):
            if lo <= cand <= hi and ok(cand):
                return cand, True
    return want, False

def _gap(g, r):
    """第 r 排（含子排）下方那條空隙的上下界。"""
    ranks = g['ranks']
    i = ranks.index(r)
    top, rh = g['row_y'][r]
    bottom = top + rh
    nxt = g['row_y'][ranks[i + 1]][0] if i + 1 < len(ranks) else bottom + ROW_GAP
    return bottom + 6, max(bottom + 8, nxt - 6)

def route(model, e, slot=0):
    """回傳中間轉折點（不含端點）。draw.io 與 SVG 共用。"""
    g = model['geom']; nodes = model['nodes']
    n1, n2 = nodes[e['src']], nodes[e['dst']]
    ex = (n1['id'], n2['id'])
    r1 = (n1['rank'], n1['sub']); r2 = (n2['rank'], n2['sub'])
    x1, x2 = _cx(n1), _cx(n2)
    # 允許走到泳道框外側：那裡保證沒有方塊，是「一定找得到」的退路。
    # 只留在框內的話，泳道一擠就找不到淨空通道，只能回傳會穿框的預設值。
    lo, hi = -70, g['total_w'] + 70

    if g['ranks'].index(r2) > g['ranks'].index(r1):
        y1 = n1['y'] + n1['h']; y2 = n2['y']
        glo, ghi = _gap(g, r1)
        chan = min(ghi, glo + slot * 15)                      # 錯開，但必須留在空隙裡
        if abs(x1 - x2) < 3 and not _v_blocked(model, x1, y1, y2, ex):
            return []                                         # 直直落下
        chan, _ = _search(chan, glo, ghi,
                          lambda y: not _h_blocked(model, y, x1, x2, ex))
        vx, ok = _search(x2, lo, hi,
                         lambda x: not _v_blocked(model, x, chan, y2, (n2['id'],))
                         and not _h_blocked(model, chan, x1, x, (n1['id'],)))
        pts = [(x1, chan), (vx, chan)]
        if abs(vx - x2) > 2:
            glo2, ghi2 = _gap(g, g['ranks'][g['ranks'].index(r2) - 1]) if g['ranks'].index(r2) > 0 else (chan, chan)
            lo2 = max(glo2, chan + 8)          # 通道只能往下走，不可以折回上面
            chan2, _ = _search(max(lo2, min(ghi2, g['row_y'][r2][0] - 20)), lo2, max(lo2, ghi2),
                               lambda y: not _h_blocked(model, y, vx, x2, ex))
            pts += [(vx, chan2), (x2, chan2)]
        return pts

    # 回程：從來源底部離開 → 在「排與排的空隙」裡橫越 → 垂直上行 → 從目標上緣偏左進入。
    # 空隙與泳道框外側都保證沒有方塊，所以一定找得到安全路徑。
    # 走過的冤枉路：從來源中心高度橫向離開，必定撞到同一排左邊的鄰居（A12 的 A7→A1）。
    i1 = g['ranks'].index(r1); i2 = g['ranks'].index(r2)
    gb_lo, gb_hi = _gap(g, r1)
    gb = min(gb_hi, gb_lo + slot * 14)
    if i2 > 0:
        ga_lo, ga_hi = _gap(g, g['ranks'][i2 - 1])
    else:
        ga_lo, ga_hi = g['row_y'][r2][0] - ROW_GAP + 6, g['row_y'][r2][0] - 8
    ga = max(ga_lo, min(ga_hi, ga_hi - slot * 14))

    xe = n2['x'] + n2['w'] * 0.25
    xa, _ = _search(min(n1['x'], n2['x']) - 26 - slot * 18, lo, hi,
                    lambda x: not _v_blocked(model, x, gb, ga, ())
                    and not _h_blocked(model, gb, x, x1, (n1['id'],))
                    and not _h_blocked(model, ga, x, xe, (n2['id'],)))
    e['_side'] = 'TOP'
    return [(x1, gb), (xa, gb), (xa, ga), (xe, ga)]

def check_crossings(model):
    """快篩：用自己算的折線檢查有沒有穿框。
    ⚠ 這只是預檢，真正的驗收看 check_render.py（量 draw.io 渲染後的 SVG）。"""
    bad = []
    for e in model['edges']:
        if e['src'] not in model['nodes'] or e['dst'] not in model['nodes']:
            continue
        n1, n2 = model['nodes'][e['src']], model['nodes'][e['dst']]
        ex = (n1['id'], n2['id'])
        pts = [(_cx(n1), n1['y'] + n1['h'])] + route(model, e) + [(_cx(n2), n2['y'])]
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            for n in _others(model, ex):
                if abs(bx - ax) < 2:
                    if n['x'] < ax < n['x'] + n['w'] and min(ay, by) < n['y'] + n['h'] and max(ay, by) > n['y']:
                        bad.append((e['src'], e['dst'], n['id'], 'V'))
                elif abs(by - ay) < 2:
                    if n['y'] < ay < n['y'] + n['h'] and min(ax, bx) < n['x'] + n['w'] and max(ax, bx) > n['x']:
                        bad.append((e['src'], e['dst'], n['id'], 'H'))
    return bad
