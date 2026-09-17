# -*- coding: utf-8 -*-
"""輸出 draw.io（mxGraphModel）檔：垂直泳道 pool＋節點＋正交連線。"""
from dio_layout import wrap
import dio_route

STYLE = {
 'rect':     'rounded=0;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#000000;fontSize=20;fontColor=#000000;',
 'round':    'rounded=1;arcSize=40;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#000000;fontSize=20;fontColor=#000000;',
 'decision': 'rhombus;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#000000;fontSize=20;fontColor=#000000;',
 'db':       'shape=cylinder3;boundedLbl=1;backgroundOutline=1;size=9;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#000000;fontSize=20;fontColor=#000000;',
 'start':    'ellipse;html=1;fillColor=#000000;strokeColor=#000000;',
 'end':      'ellipse;html=1;shape=endState;fillColor=#000000;strokeColor=#000000;',
}
LANE = ('swimlane;html=1;horizontal=1;startSize=40;fillColor=none;'
        'strokeColor=#000000;fontSize=24;fontColor=#000000;fontStyle=0;'
        'swimlaneFillColor=none;collapsible=0;')
EDGE = ('edgeStyle=none;rounded=0;html=1;'
        'strokeColor=#000000;fontSize=17;fontColor=#000000;labelBackgroundColor=#FFFFFF;'
        'endArrow=%s;endFill=1;exitPerimeter=0;entryPerimeter=0;')

def esc(s):
    return (s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
             .replace('"', '&quot;'))

def label_html(label):
    return '&lt;br&gt;'.join(esc(l) for l in wrap(label)) if label else ''

def to_xml(model, title='圖'):
    g = model['geom']; nodes = model['nodes']
    rank = {k: v['rank'] for k, v in nodes.items()}
    o = ['<mxfile host="uban-doc"><diagram name="%s">' % esc(title),
         '<mxGraphModel dx="1400" dy="900" grid="0" gridSize="10" guides="1" tooltips="1" '
         'connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="%g" pageHeight="%g" math="0" shadow="0">'
         % (g['total_w'] + 80, g['total_h'] + 80),
         '<root><mxCell id="0"/><mxCell id="1" parent="0"/>']
    for lid, ttl in model['lanes']:
        o.append('<mxCell id="lane_%s" value="%s" style="%s" vertex="1" parent="1">' % (lid, esc(ttl), LANE))
        o.append('<mxGeometry x="%g" y="0" width="%g" height="%g" as="geometry"/></mxCell>'
                 % (g['lane_x'][lid], g['lane_w'][lid], g['total_h']))
    for nid in model['order']:
        n = nodes[nid]
        st = STYLE[n['shape']]
        if n['cls'] == 'gap':
            st += 'dashed=1;'
        o.append('<mxCell id="n_%s" value="%s" style="%s" vertex="1" parent="lane_%s">'
                 % (nid, label_html(n['label']), st, n['lane']))
        o.append('<mxGeometry x="%g" y="%g" width="%g" height="%g" as="geometry"/></mxCell>'
                 % (n['x'] - g['lane_x'][n['lane']], n['y'], n['w'], n['h']))
    slot = {}
    for i, e in enumerate(model['edges']):
        if e['src'] not in nodes or e['dst'] not in nodes:
            continue
        st = EDGE % ('classic' if e['arrow'] else 'none')
        if e['dashed']:
            st += 'dashed=1;'
        if rank[e['dst']] <= rank[e['src']]:
            pass          # 進出點等走線算完才知道走左邊還右邊，見下方
        else:
            st += 'exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;'
        n1 = nodes[e['src']]
        # 同一個來源扇出的線共用一條通道（分岔才會是平的）；不同來源才錯開
        ch_key = (n1['rank'], n1['sub'], rank[e['dst']] <= rank[e['src']])
        srcs = slot.setdefault(ch_key, [])
        if e['src'] not in srcs:
            srcs.append(e['src'])
        pts = dio_route.route(model, e, srcs.index(e['src']))
        back = rank[e['dst']] <= rank[e['src']]
        n2 = nodes[e['dst']]
        if back:
            st += 'exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.25;entryY=0;entryDx=0;entryDy=0;'
            nx, ny = n1['x'] + n1['w'] / 2, n1['y'] + n1['h']
            tx, ty = n2['x'] + n2['w'] * 0.25, n2['y']
        else:
            nx, ny = n1['x'] + n1['w'] / 2, n1['y'] + n1['h']
            tx, ty = n2['x'] + n2['w'] / 2, n2['y']
        o.append('<mxCell id="e%d" value="%s" style="%s" edge="1" parent="1" source="n_%s" target="n_%s">'
                 % (i, esc(e['label']), st, e['src'], e['dst']))
        if pts:
            chain = [(nx, ny)] + pts + [(tx, ty)]
            for (ax, ay), (bx, by) in zip(chain, chain[1:]):
                assert abs(ax - bx) < 2 or abs(ay - by) < 2,                     '非正交線段 %s→%s' % (e['src'], e['dst'])
            o.append('<mxGeometry relative="1" as="geometry"><Array as="points">')
            for (px, py) in pts:
                o.append('<mxPoint x="%g" y="%g"/>' % (px, py))
            o.append('</Array></mxGeometry></mxCell>')
        else:
            o.append('<mxGeometry relative="1" as="geometry"/></mxCell>')
    o.append('</root></mxGraphModel></diagram></mxfile>')
    return '\n'.join(o)
