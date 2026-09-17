# -*- coding: utf-8 -*-
"""把活動圖 .mmd 解析成 {泳道, 節點, 邊} 的中性模型，供 draw.io / SVG 產生器使用。"""
import re, os

SUB   = re.compile(r'^\s*subgraph\s+(\w+)\["(.*?)"\]\s*$')
END   = re.compile(r'^\s*end\s*$')
NODE  = re.compile(r'^\s*([A-Za-z_]\w*)'
                   r'(\[\(|\(\(|\(\[|\{|\[|\()'
                   r'(.*?)'
                   r'(\)\]|\)\)|\]\)|\}|\]|\))'
                   r'(?::::(\w+))?\s*$')
EDGE  = re.compile(r'^\s*([A-Za-z_]\w*)\s*'
                   r'(-->|---|-\.->|-\.-)'
                   r'(?:\|"?(.*?)"?\|)?\s*'
                   r'([A-Za-z_]\w*)\s*$')

OPEN2SHAPE = {'[(': 'db', '((': 'circle', '([': 'round', '{': 'decision', '[': 'rect', '(': 'round'}

def parse(path):
    lanes, order = [], []
    nodes, edges = {}, []
    cur = None
    for raw in open(path, encoding='utf-8').read().split('\n'):
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith('%%'):
            continue
        if line.lstrip().startswith(('classDef', 'flowchart', 'class ')):
            continue
        if '~~~' in line:
            continue
        m = SUB.match(line)
        if m:
            cur = m.group(1); lanes.append((m.group(1), m.group(2))); continue
        if END.match(line):
            cur = None; continue
        m = NODE.match(line)
        if m:
            nid, op, lab, _cl, cls = m.groups()
            if nid.startswith('PAD_'):
                continue
            label = lab.strip().strip('"')
            shape = OPEN2SHAPE[op]
            if cls == 'term':    shape = 'start'
            if cls == 'endterm': shape = 'end'
            if label in ('&nbsp;', '●'): label = ''
            nodes[nid] = dict(id=nid, lane=cur, shape=shape, label=label, cls=cls or 'act')
            order.append(nid)
            continue
        m = EDGE.match(line)
        if m:
            s, arrow, lab, t = m.groups()
            if s.startswith('PAD_') or t.startswith('PAD_'):
                continue
            edges.append(dict(src=s, dst=t,
                              label=(lab or '').strip().strip('"'),
                              dashed=arrow.startswith('-.'),
                              arrow=arrow in ('-->', '-.->')))
            continue
    return dict(lanes=lanes, nodes=nodes, edges=edges, order=order,
                name=os.path.basename(path))

if __name__ == '__main__':
    import sys
    sys.stdout.reconfigure(encoding='utf-8')
    m = parse(sys.argv[1])
    print('泳道:', m['lanes'])
    print('節點:', len(m['nodes']), '邊:', len(m['edges']))
    miss = [e for e in m['edges'] if e['src'] not in m['nodes'] or e['dst'] not in m['nodes']]
    print('指向不存在節點的邊:', miss)
    for nid in m['order'][:6]:
        print('  ', m['nodes'][nid])
