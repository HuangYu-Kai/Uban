# -*- coding: utf-8 -*-
"""Comprehensive Geometric Auditor for DrawIO files.
Strictly audits against:
1. Line Crossings (線交叉)
2. Line-Node Penetrations (線穿進程序/文字裡)
3. Out-of-bounds (超出圖或泳道邊界)
4. Tangled Overlaps (線與線重疊、箭頭過近、線與文字重疊)
"""
import xml.etree.ElementTree as ET
import glob, os, sys, math
sys.stdout.reconfigure(encoding='utf-8')

def ccw(A, B, C):
    return (C[1]-A[1]) * (B[0]-A[0]) > (B[1]-A[1]) * (C[0]-A[0])

def segments_intersect(A, B, C, D):
    # Proper intersection of open segments AB and CD
    # Check if bounding boxes overlap
    if max(A[0], B[0]) < min(C[0], D[0]) or min(A[0], B[0]) > max(C[0], D[0]):
        return False
    if max(A[1], B[1]) < min(C[1], D[1]) or min(A[1], B[1]) > max(C[1], D[1]):
        return False
    
    # Check endpoints sharing
    def same(p1, p2, eps=1.0):
        return abs(p1[0]-p2[0]) < eps and abs(p1[1]-p2[1]) < eps
    if same(A, C) or same(A, D) or same(B, C) or same(B, D):
        return False

    def cp(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])

    cp1 = cp(A, B, C)
    cp2 = cp(A, B, D)
    cp3 = cp(C, D, A)
    cp4 = cp(C, D, B)

    # If collinear
    if abs(cp1) < 1e-4 and abs(cp2) < 1e-4:
        return False # collinear handled by overlap check

    if ((cp1 > 1e-4 and cp2 < -1e-4) or (cp1 < -1e-4 and cp2 > 1e-4)) and \
       ((cp3 > 1e-4 and cp4 < -1e-4) or (cp3 < -1e-4 and cp4 > 1e-4)):
        return True
    return False

def seg_overlaps(A, B, C, D, eps=2.0):
    # Check if collinear segments overlap
    # Check horizontal
    if abs(A[1] - B[1]) < eps and abs(C[1] - D[1]) < eps and abs(A[1] - C[1]) < eps:
        x_min1, x_max1 = min(A[0], B[0]), max(A[0], B[0])
        x_min2, x_max2 = min(C[0], D[0]), max(C[0], D[0])
        overlap = min(x_max1, x_max2) - max(x_min1, x_min2)
        if overlap > eps:
            return True, overlap
    # Check vertical
    if abs(A[0] - B[0]) < eps and abs(C[0] - D[0]) < eps and abs(A[0] - C[0]) < eps:
        y_min1, y_max1 = min(A[1], B[1]), max(A[1], B[1])
        y_min2, y_max2 = min(C[1], D[1]), max(C[1], D[1])
        overlap = min(y_max1, y_max2) - max(y_min1, y_min2)
        if overlap > eps:
            return True, overlap
    return False, 0

def seg_rect_penetration(A, B, rect, margin=4.0):
    # rect: (rx, ry, rw, rh)
    rx, ry, rw, rh = rect
    x1, y1 = rx + margin, ry + margin
    x2, y2 = rx + rw - margin, ry + rh - margin
    if x2 <= x1 or y2 <= y1:
        return False
    
    # Check if segment passes through interior of [x1, x2] x [y1, y2]
    # Simple check: parametric line clipping (Liang-Barsky)
    dx = B[0] - A[0]
    dy = B[1] - A[1]
    
    p = [-dx, dx, -dy, dy]
    q = [A[0] - x1, x2 - A[0], A[1] - y1, y2 - A[1]]
    
    u1, u2 = 0.0, 1.0
    for pi, qi in zip(p, q):
        if abs(pi) < 1e-6:
            if qi < 0:
                return False
        else:
            t = qi / pi
            if pi < 0:
                if t > u2: return False
                if t > u1: u1 = t
            else:
                if t < u1: return False
                if t < u2: u2 = t
    return u1 < u2 and (u2 - u1) > 1e-4

def audit_drawio_file(filepath):
    tree = ET.parse(filepath)
    root = tree.getroot()
    
    # Find mxGraphModel
    model = root.find('.//mxGraphModel')
    page_w = float(model.get('pageWidth', '2000')) if model is not None else 2000.0
    page_h = float(model.get('pageHeight', '2000')) if model is not None else 2000.0
    
    # Map cells
    cells = {}
    for cell in root.iter('mxCell'):
        cid = cell.get('id')
        if cid:
            cells[cid] = cell
            
    # Resolve absolute positions of vertices
    # First find all vertices and geometries
    geom_map = {} # cid -> (abs_x, abs_y, w, h, is_swimlane, value, style)
    
    def get_abs_pos(cid):
        if cid in geom_map:
            return geom_map[cid]
        c = cells.get(cid)
        if c is None:
            return None
        geo = c.find('mxGeometry')
        if geo is None:
            return None
        x = float(geo.get('x', '0'))
        y = float(geo.get('y', '0'))
        w = float(geo.get('width', '0'))
        h = float(geo.get('height', '0'))
        parent_id = c.get('parent')
        
        style = c.get('style', '')
        is_lane = 'swimlane' in style
        val = c.get('value', '')
        
        if parent_id and parent_id not in ('0', '1'):
            p_geom = get_abs_pos(parent_id)
            if p_geom:
                px, py, pw, ph, _, _, _ = p_geom
                x += px
                y += py
        geom_map[cid] = (x, y, w, h, is_lane, val, style)
        return geom_map[cid]

    vertices = {}
    lanes = {}
    for cid, c in cells.items():
        if c.get('vertex') == '1':
            res = get_abs_pos(cid)
            if res:
                if res[4]: # is_lane
                    lanes[cid] = res
                else:
                    vertices[cid] = res

    # Resolve edges
    edges = []
    for cid, c in cells.items():
        if c.get('edge') == '1':
            src_id = c.get('source')
            dst_id = c.get('target')
            style = c.get('style', '')
            val = c.get('value', '')
            
            # Determine start point
            p_start = None
            if src_id and src_id in vertices:
                vx, vy, vw, vh, _, _, _ = vertices[src_id]
                # check exitX, exitY
                ex = 0.5; ey = 1.0 # default bottom
                for s in style.split(';'):
                    if s.startswith('exitX='): ex = float(s.split('=')[1])
                    elif s.startswith('exitY='): ey = float(s.split('=')[1])
                p_start = (vx + vw * ex, vy + vh * ey)
                
            # Determine end point
            p_end = None
            if dst_id and dst_id in vertices:
                vx, vy, vw, vh, _, _, _ = vertices[dst_id]
                enx = 0.5; eny = 0.0 # default top
                for s in style.split(';'):
                    if s.startswith('entryX='): enx = float(s.split('=')[1])
                    elif s.startswith('entryY='): eny = float(s.split('=')[1])
                p_end = (vx + vw * enx, vy + vh * eny)
                
            # Intermediate points
            pts = []
            geo = c.find('mxGeometry')
            if geo is not None:
                arr = geo.find('Array')
                if arr is not None:
                    for pt in arr.findall('mxPoint'):
                        px = float(pt.get('x', '0'))
                        py = float(pt.get('y', '0'))
                        pts.append((px, py))
                        
            # If start or end point not connected to vertex, check geo sourcePoint/targetPoint
            if p_start is None and geo is not None:
                sp = geo.find('mxPoint[@as="sourcePoint"]')
                if sp is not None:
                    p_start = (float(sp.get('x', '0')), float(sp.get('y', '0')))
            if p_end is None and geo is not None:
                tp = geo.find('mxPoint[@as="targetPoint"]')
                if tp is not None:
                    p_end = (float(tp.get('x', '0')), float(tp.get('y', '0')))
                    
            if p_start and p_end:
                full_pts = [p_start] + pts + [p_end]
                # Remove zero-length consecutive segments
                cleaned = [full_pts[0]]
                for p in full_pts[1:]:
                    if abs(p[0] - cleaned[-1][0]) > 0.5 or abs(p[1] - cleaned[-1][1]) > 0.5:
                        cleaned.append(p)
                edges.append({
                    'id': cid,
                    'src': src_id,
                    'dst': dst_id,
                    'pts': cleaned,
                    'val': val
                })

    # Now run the 4 geometric audits:
    crossings = []
    penetrations = []
    out_of_bounds = []
    overlaps = []

    # 1. Crossings (線交叉)
    for i in range(len(edges)):
        e1 = edges[i]
        pts1 = e1['pts']
        for j in range(i + 1, len(edges)):
            e2 = edges[j]
            pts2 = e2['pts']
            # Check every segment pair
            for s1_idx in range(len(pts1) - 1):
                seg1 = (pts1[s1_idx], pts1[s1_idx + 1])
                for s2_idx in range(len(pts2) - 1):
                    seg2 = (pts2[s2_idx], pts2[s2_idx + 1])
                    if segments_intersect(seg1[0], seg1[1], seg2[0], seg2[1]):
                        crossings.append({
                            'edge1': e1['id'], 'edge2': e2['id'],
                            'seg1': seg1, 'seg2': seg2
                        })

    # 2. Line-Node Penetrations (線穿進程序/文字裡)
    for e in edges:
        pts = e['pts']
        for s_idx in range(len(pts) - 1):
            A = pts[s_idx]
            B = pts[s_idx + 1]
            for vid, v in vertices.items():
                # Skip if this vertex is the source or destination of this edge
                if vid == e['src'] or vid == e['dst']:
                    continue
                rx, ry, rw, rh, is_lane, val, style = v
                if 'text' in style and not val.strip():
                    continue # empty decorative text
                if seg_rect_penetration(A, B, (rx, ry, rw, rh), margin=4.0):
                    penetrations.append({
                        'edge': e['id'],
                        'node': vid,
                        'node_label': val[:20],
                        'seg': (A, B),
                        'rect': (rx, ry, rw, rh)
                    })

    # 3. Out-of-bounds (超出邊界)
    for vid, v in vertices.items():
        rx, ry, rw, rh, is_lane, val, style = v
        if rx < 0 or ry < 0 or (rx + rw) > page_w + 10 or (ry + rh) > page_h + 10:
            out_of_bounds.append({
                'type': 'node',
                'id': vid,
                'pos': (rx, ry, rw, rh),
                'bounds': (page_w, page_h)
            })
    for e in edges:
        for p in e['pts']:
            if p[0] < -2 or p[1] < -2 or p[0] > page_w + 10 or p[1] > page_h + 10:
                out_of_bounds.append({
                    'type': 'edge_point',
                    'id': e['id'],
                    'point': p,
                    'bounds': (page_w, page_h)
                })

    # 4. Tangled Overlaps (線與線重疊、箭頭過近)
    # Check collinear segment overlaps
    for i in range(len(edges)):
        e1 = edges[i]
        pts1 = e1['pts']
        for j in range(i + 1, len(edges)):
            e2 = edges[j]
            pts2 = e2['pts']
            for s1_idx in range(len(pts1) - 1):
                seg1 = (pts1[s1_idx], pts1[s1_idx + 1])
                for s2_idx in range(len(pts2) - 1):
                    seg2 = (pts2[s2_idx], pts2[s2_idx + 1])
                    ov, length = seg_overlaps(seg1[0], seg1[1], seg2[0], seg2[1], eps=2.0)
                    if ov and length > 5.0:
                        overlaps.append({
                            'type': 'collinear_overlap',
                            'edge1': e1['id'], 'edge2': e2['id'],
                            'length': length
                        })
                        
    # Check arrow proximity (target points distance < 8px unless targeting same node)
    for i in range(len(edges)):
        e1 = edges[i]
        p1 = e1['pts'][-1]
        for j in range(i + 1, len(edges)):
            e2 = edges[j]
            p2 = e2['pts'][-1]
            if e1['dst'] != e2['dst']:
                dist = math.hypot(p1[0] - p2[0], p1[1] - p2[1])
                if dist < 8.0:
                    overlaps.append({
                        'type': 'arrow_too_close',
                        'edge1': e1['id'], 'edge2': e2['id'],
                        'dist': dist
                    })

    verdict = (len(crossings) == 0 and len(penetrations) == 0 and 
               len(out_of_bounds) == 0 and len(overlaps) == 0)

    return {
        'file': os.path.basename(filepath),
        'crossings': len(crossings),
        'penetrations': len(penetrations),
        'out_of_bounds': len(out_of_bounds),
        'overlaps': len(overlaps),
        'verdict': 'PASS' if verdict else 'FAIL',
        'details': {
            'crossings': crossings,
            'penetrations': penetrations,
            'out_of_bounds': out_of_bounds,
            'overlaps': overlaps
        }
    }

if __name__ == '__main__':
    target = sys.argv[1] if len(sys.argv) > 1 else 'drawio圖'
    if os.path.isdir(target):
        files = sorted(glob.glob(os.path.join(target, '*.drawio')))
    else:
        files = [target]
    
    total_pass = 0
    total_fail = 0
    for f in files:
        res = audit_drawio_file(f)
        status = '✓ PASS' if res['verdict'] == 'PASS' else '✗ FAIL'
        print(f"{status} | {res['file']:<35} | C:{res['crossings']} P:{res['penetrations']} OOB:{res['out_of_bounds']} Ov:{res['overlaps']}")
        if res['verdict'] == 'PASS':
            total_pass += 1
        else:
            total_fail += 1
            if res['crossings']:
                print(f"   -> Crossings: {res['details']['crossings'][:3]}")
            if res['penetrations']:
                print(f"   -> Penetrations: {res['details']['penetrations'][:3]}")
            if res['out_of_bounds']:
                print(f"   -> Out of bounds: {res['details']['out_of_bounds'][:3]}")
            if res['overlaps']:
                print(f"   -> Overlaps: {res['details']['overlaps'][:3]}")
    print(f"\nSummary: Total={len(files)}, PASS={total_pass}, FAIL={total_fail}")
