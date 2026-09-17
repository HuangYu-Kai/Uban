# -*- coding: utf-8 -*-
"""把 29 張活動圖的 .mmd 全部轉成 .drawio，並逐張自檢。"""
import os, sys, glob
sys.stdout.reconfigure(encoding='utf-8')
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import dio_parse, dio_layout, dio_xml, dio_route
SRC = os.path.join(os.path.dirname(HERE), 'mermaid原始碼')
OUT = os.path.join(os.path.dirname(HERE), 'drawio圖'); os.makedirs(OUT, exist_ok=True)
rows = []
for f in sorted(glob.glob(os.path.join(SRC, 'A*.mmd'))):
    stem = os.path.basename(f)[:-4]
    try:
        m = dio_layout.layout(dio_parse.parse(f))
        bad = dio_route.check_crossings(m)
        g = m['geom']
        xml = dio_xml.to_xml(m, stem)
        open(os.path.join(OUT, stem + '.drawio'), 'w', encoding='utf-8', newline='').write(xml)
        rows.append((stem[:3], g['total_w'], g['total_h'], g['total_w']/g['total_h'],
                     len(m['nodes']), len(m['edges']), len(bad), len(g['ranks'])))
    except Exception as e:
        print('✗', stem, str(e)[:160])
print('%-5s %6s %6s %6s %5s %5s %5s %5s' % ('圖','寬','高','比例','節點','邊','穿框','排數'))
tot_bad = 0
for r in rows:
    tot_bad += r[6]
    flag = '  ⚠' if r[6] else ''
    print('%-5s %6d %6d %6.2f %5d %5d %5d %5d%s' % (r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], flag))
import statistics
print('---')
print('共 %d 張｜線穿過方塊合計 %d 條｜比例中位數 %.2f｜最細長 %.2f'
      % (len(rows), tot_bad, statistics.median(r[3] for r in rows), min(r[3] for r in rows)))
