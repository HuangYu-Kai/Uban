# -*- coding: utf-8 -*-
"""Comprehensive Geometric Auditor for All Chapter 5-14 Diagram Assets."""
import os, sys, glob, math
import xml.etree.ElementTree as ET
from PIL import Image

sys.stdout.reconfigure(encoding='utf-8')

HERE = os.path.dirname(os.path.abspath(__file__))
DRAWIO_DIR = os.path.join(os.path.dirname(HERE), 'drawio圖')
NANO_DIR = os.path.join(os.path.dirname(HERE), 'Nano Banana')
MERMAID_DIR = os.path.join(os.path.dirname(HERE), 'mermaid原始碼')

def ccw(A, B, C):
    return (C[1]-A[1]) * (B[0]-A[0]) > (B[1]-A[1]) * (C[0]-A[0])

def segments_intersect(A, B, C, D):
    if max(A[0], B[0]) < min(C[0], D[0]) or min(A[0], B[0]) > max(C[0], D[0]):
        return False
    if max(A[1], B[1]) < min(C[1], D[1]) or min(A[1], B[1]) > max(C[1], D[1]):
        return False
    def same(p1, p2, eps=1.0):
        return abs(p1[0]-p2[0]) < eps and abs(p1[1]-p2[1]) < eps
    if same(A, C) or same(A, D) or same(B, C) or same(B, D):
        return False
    def cp(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
    cp1 = cp(A, B, C); cp2 = cp(A, B, D)
    cp3 = cp(C, D, A); cp4 = cp(C, D, B)
    if abs(cp1) < 1e-4 and abs(cp2) < 1e-4:
        return False
    if ((cp1 > 1e-4 and cp2 < -1e-4) or (cp1 < -1e-4 and cp2 > 1e-4)) and \
       ((cp3 > 1e-4 and cp4 < -1e-4) or (cp3 < -1e-4 and cp4 > 1e-4)):
        return True
    return False

def seg_overlaps(A, B, C, D, eps=2.0):
    if abs(A[1] - B[1]) < eps and abs(C[1] - D[1]) < eps and abs(A[1] - C[1]) < eps:
        x_min1, x_max1 = min(A[0], B[0]), max(A[0], B[0])
        x_min2, x_max2 = min(C[0], D[0]), max(C[0], D[0])
        overlap = min(x_max1, x_max2) - max(x_min1, x_min2)
        if overlap > eps:
            return True, overlap
    if abs(A[0] - B[0]) < eps and abs(C[0] - D[0]) < eps and abs(A[0] - C[0]) < eps:
        y_min1, y_max1 = min(A[1], B[1]), max(A[1], B[1])
        y_min2, y_max2 = min(C[1], D[1]), max(C[1], D[1])
        overlap = min(y_max1, y_max2) - max(y_min1, y_min2)
        if overlap > eps:
            return True, overlap
    return False, 0

def seg_rect_penetration(A, B, rect, margin=4.0):
    rx, ry, rw, rh = rect
    x1, y1 = rx + margin, ry + margin
    x2, y2 = rx + rw - margin, ry + rh - margin
    if x2 <= x1 or y2 <= y1:
        return False
    dx = B[0] - A[0]; dy = B[1] - A[1]
    p = [-dx, dx, -dy, dy]
    q = [A[0] - x1, x2 - A[0], A[1] - y1, y2 - A[1]]
    u1, u2 = 0.0, 1.0
    for pi, qi in zip(p, q):
        if abs(pi) < 1e-6:
            if qi < 0: return False
        else:
            t = qi / pi
            if pi < 0:
                if t > u2: return False
                if t > u1: u1 = t
            else:
                if t < u1: return False
                if t < u2: u2 = t
    return u1 < u2 and (u2 - u1) > 1e-4

def audit_drawio(filepath):
    tree = ET.parse(filepath)
    root = tree.getroot()
    model = root.find('.//mxGraphModel')
    page_w = float(model.get('pageWidth', '2000')) if model is not None else 2000.0
    page_h = float(model.get('pageHeight', '2000')) if model is not None else 2000.0
    
    cells = {c.get('id'): c for c in root.iter('mxCell') if c.get('id')}
    geom_map = {}
    
    def get_abs_pos(cid):
        if cid in geom_map:
            return geom_map[cid]
        c = cells.get(cid)
        if c is None: return None
        geo = c.find('mxGeometry')
        if geo is None: return None
        x = float(geo.get('x', '0'))
        y = float(geo.get('y', '0'))
        w = float(geo.get('width', '0'))
        h = float(geo.get('height', '0'))
        parent_id = c.get('parent')
        style = c.get('style', '')
        is_container = 'swimlane' in style or cid.startswith('box_') or 'container=1' in style
        val = c.get('value', '')
        if parent_id and parent_id not in ('0', '1'):
            p_geom = get_abs_pos(parent_id)
            if p_geom:
                px, py, pw, ph, _, _, _ = p_geom
                x += px; y += py
        geom_map[cid] = (x, y, w, h, is_container, val, style)
        return geom_map[cid]

    vertices = {}
    containers = {}
    for cid, c in cells.items():
        if c.get('vertex') == '1':
            res = get_abs_pos(cid)
            if res:
                if res[4]:
                    containers[cid] = res
                else:
                    vertices[cid] = res

    edges = []
    for cid, c in cells.items():
        if c.get('edge') == '1':
            src_id = c.get('source')
            dst_id = c.get('target')
            style = c.get('style', '')
            val = c.get('value', '')
            p_start = None
            if src_id and src_id in vertices:
                vx, vy, vw, vh, _, _, _ = vertices[src_id]
                ex = 0.5; ey = 1.0
                for s in style.split(';'):
                    if s.startswith('exitX='): ex = float(s.split('=')[1])
                    elif s.startswith('exitY='): ey = float(s.split('=')[1])
                p_start = (vx + vw * ex, vy + vh * ey)
            p_end = None
            if dst_id and dst_id in vertices:
                vx, vy, vw, vh, _, _, _ = vertices[dst_id]
                enx = 0.5; eny = 0.0
                for s in style.split(';'):
                    if s.startswith('entryX='): enx = float(s.split('=')[1])
                    elif s.startswith('entryY='): eny = float(s.split('=')[1])
                p_end = (vx + vw * enx, vy + vh * eny)
            pts = []
            geo = c.find('mxGeometry')
            if geo is not None:
                arr = geo.find('Array')
                if arr is not None:
                    for pt in arr.findall('mxPoint'):
                        pts.append((float(pt.get('x', '0')), float(pt.get('y', '0'))))
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
                cleaned = [full_pts[0]]
                for p in full_pts[1:]:
                    if abs(p[0] - cleaned[-1][0]) > 0.5 or abs(p[1] - cleaned[-1][1]) > 0.5:
                        cleaned.append(p)
                edges.append({'id': cid, 'src': src_id, 'dst': dst_id, 'pts': cleaned, 'val': val})

    crossings = []
    penetrations = []
    out_of_bounds = []
    overlaps = []

    # 1. Crossings
    for i in range(len(edges)):
        pts1 = edges[i]['pts']
        for j in range(i + 1, len(edges)):
            pts2 = edges[j]['pts']
            for s1_idx in range(len(pts1) - 1):
                seg1 = (pts1[s1_idx], pts1[s1_idx + 1])
                for s2_idx in range(len(pts2) - 1):
                    seg2 = (pts2[s2_idx], pts2[s2_idx + 1])
                    if segments_intersect(seg1[0], seg1[1], seg2[0], seg2[1]):
                        crossings.append((edges[i]['id'], edges[j]['id'], seg1, seg2))

    # 2. Penetrations (excluding dividers/decorations inside state machines/tables)
    for e in edges:
        pts = e['pts']
        for s_idx in range(len(pts) - 1):
            A = pts[s_idx]; B = pts[s_idx + 1]
            for vid, v in vertices.items():
                if vid == e['src'] or vid == e['dst']:
                    continue
                rx, ry, rw, rh, is_lane, val, style = v
                if 'text' in style and not val.strip():
                    continue
                # If edge is an internal divider of a composite node (e.g. state machine header divider)
                if e['id'].endswith('_div') and vid.startswith(e['id'].replace('_div', '')):
                    continue
                if seg_rect_penetration(A, B, (rx, ry, rw, rh), margin=4.0):
                    penetrations.append((e['id'], vid, val[:20], (A, B)))

    # 3. Out of bounds
    for vid, v in vertices.items():
        rx, ry, rw, rh, is_lane, val, style = v
        # Ignored non-visual or zero-size connector ports (e.g. port constraints with w=0, h=0)
        if rw == 0 and rh == 0:
            continue
        if rx < -5 or ry < -5 or (rx + rw) > page_w + 15 or (ry + rh) > page_h + 15:
            out_of_bounds.append(('node', vid, (rx, ry, rw, rh)))
    for e in edges:
        for p in e['pts']:
            if p[0] < -5 or p[1] < -5 or p[0] > page_w + 15 or p[1] > page_h + 15:
                out_of_bounds.append(('edge_point', e['id'], p))

    # 4. Overlaps
    for i in range(len(edges)):
        pts1 = edges[i]['pts']
        for j in range(i + 1, len(edges)):
            pts2 = edges[j]['pts']
            for s1_idx in range(len(pts1) - 1):
                seg1 = (pts1[s1_idx], pts1[s1_idx + 1])
                for s2_idx in range(len(pts2) - 1):
                    seg2 = (pts2[s2_idx], pts2[s2_idx + 1])
                    ov, length = seg_overlaps(seg1[0], seg1[1], seg2[0], seg2[1], eps=2.0)
                    if ov and length > 5.0:
                        overlaps.append((edges[i]['id'], edges[j]['id'], length))

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

def run_all_audits():
    categories = [
        ('Chapter 5 Activity Diagrams (O01~O12, F01~F10, D01~D07)', sorted(glob.glob(os.path.join(DRAWIO_DIR, 'A*.drawio')))),
        ('Chapter 5 Use Case Diagrams (UC01~UC05)', sorted(glob.glob(os.path.join(DRAWIO_DIR, 'D52*.drawio')))),
        ('Chapter 5 Analysis Class Diagrams (CDA01)', sorted(glob.glob(os.path.join(DRAWIO_DIR, 'D54*.drawio')))),
        ('Chapter 7 State Machine Diagrams (SM01~SM06)', sorted(glob.glob(os.path.join(DRAWIO_DIR, 'SM*.drawio')))),
        ('Chapter 8 Database ERD Diagrams (D801~D806)', sorted(glob.glob(os.path.join(DRAWIO_DIR, 'D8*.drawio')))),
    ]
    
    grand_pass = 0
    grand_fail = 0
    
    for cat_name, flist in categories:
        print(f"\n{'='*75}\n### {cat_name} (Total: {len(flist)})\n{'='*75}")
        c_tot = 0; p_tot = 0; oob_tot = 0; ov_tot = 0
        cat_pass = 0; cat_fail = 0
        for f in flist:
            res = audit_drawio(f)
            c_tot += res['crossings']
            p_tot += res['penetrations']
            oob_tot += res['out_of_bounds']
            ov_tot += res['overlaps']
            if res['verdict'] == 'PASS':
                cat_pass += 1
                grand_pass += 1
                tag = '[PASS]'
            else:
                cat_fail += 1
                grand_fail += 1
                tag = '[FAIL]'
            print(f"{tag:<7} {res['file'][:32]:<34} | Crossings:{res['crossings']:2d} | Penetrations:{res['penetrations']:2d} | Out-of-bounds:{res['out_of_bounds']:2d} | Overlaps:{res['overlaps']:2d}")
            if res['crossings'] > 0:
                print(f"       -> Crossings detail (sample): {res['details']['crossings'][:2]}")
            if res['penetrations'] > 0:
                print(f"       -> Penetrations detail (sample): {res['details']['penetrations'][:2]}")
            if res['out_of_bounds'] > 0:
                print(f"       -> OOB detail (sample): {res['details']['out_of_bounds'][:2]}")
            if res['overlaps'] > 0:
                print(f"       -> Overlaps detail (sample): {res['details']['overlaps'][:2]}")
        print(f"--- Subtotal for {cat_name}: PASS={cat_pass}, FAIL={cat_fail} (Total Crossings={c_tot}, Penetrations={p_tot}, OOB={oob_tot}, Overlaps={ov_tot})")

    print(f"\n{'='*75}")
    print(f"GRAND TOTAL (DrawIO Vector Audits): PASS={grand_pass}, FAIL={grand_fail}")
    print(f"{'='*75}\n")

if __name__ == '__main__':
    run_all_audits()
