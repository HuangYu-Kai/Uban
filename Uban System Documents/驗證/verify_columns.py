# -*- coding: utf-8 -*-
"""驗證 5-4 分析類別圖的每個屬性，名稱與型別都對得上 database.py 的真實欄位。

2026-09-15 更新兩件事：
  1. 類別圖由 1 張拆成 3 張（5-4-1／5-4-2／5-4-3），不再斷言只有一張。
  2. 屬性改成組長的寫法 `+int user_id`，所以除了欄位名，**型別也要一起驗**——
     這才是「型別沒有自己編」的真正檢查。
後兩張的核心兩類是灰色「引用」框，沒有屬性，不列入比對。
"""
import io, os, re, sys

WB = r"C:\Users\kevin\Desktop\115207\Uban\Uban System Documents\第5-2至8章重寫工作台.html"
DB = r"C:\Users\kevin\Desktop\115207\uban-api\database.py"

# 類別 → 實際資料表（生命故事刻意無表：只存在裝置的 SharedPreferences）
MAP = {
    '使用者帳戶': 'user_account_data', '長輩檔案': 'elder_profile',
    '家屬長輩關係': 'family_elder_relationship', '配對碼': 'pairing_code',
    '訂閱狀態': 'subscription_status', '遠端提醒': 'remote_reminders',
    '活動日誌': 'activity_log', '對話主題': 'elder_talk_topics',
    '生命故事': None,
    '通話紀錄': 'call_record', '推播權杖': 'user_fcm_token',
    '監視裝置綁定': 'monitor_device_binding', '影像串流狀態': 'cctv_feed_status',
    '緊急警報': 'emergency_alerts', '室內區域事件': 'elder_zone_event',
    '家庭貼文': 'community_posts', '長輩好友關係': 'elder_friendship',
    '家屬好友關係': 'family_friendship', '每日新聞': 'daily_news_items',
    '寵物狀態': 'elder_pet_state', '成長階段門檻': 'pet_stage_threshold',
    '賽季': 'pet_season', '賽季結算': 'pet_season_settlement', '寵物造型': 'pet_skin',
    '開發者帳號': 'developer_account', '問題回報': 'bug_report',
    '帳號停權': 'account_ban', '管理操作稽核': 'admin_action_log',
}

TYPES = ('int', 'String', 'Text', 'DateTime', 'Date', 'Time',
         'float', 'boolean', 'Json', 'Blob')


def sqltype(t):
    """SQL 型別 → 組長舊圖的寫法。與 build_class.py 必須一致。"""
    t = t.upper()
    if t.startswith('TINYINT(1)') or t.startswith('BOOL'):
        return 'boolean'
    if re.match(r'(INT|INTEGER|BIGINT|SMALLINT|TINYINT|MEDIUMINT)', t):
        return 'int'
    if re.match(r'(VARCHAR|CHAR)', t):
        return 'String'
    if re.match(r'(TEXT|LONGTEXT|MEDIUMTEXT|TINYTEXT)', t):
        return 'Text'
    if t.startswith('DATETIME') or t.startswith('TIMESTAMP'):
        return 'DateTime'
    if t.startswith('DATE'):
        return 'Date'
    if t.startswith('TIME'):
        return 'Time'
    if re.match(r'(FLOAT|DOUBLE|DECIMAL|NUMERIC|REAL)', t):
        return 'float'
    if t.startswith('JSON'):
        return 'Json'
    if t.startswith('BLOB'):
        return 'Blob'
    return 'String'


def scan_columns():
    """回傳 {表名: {欄位: 型別}}。SQLite 與 MySQL 兩個分支都掃，取欄位多的那份。"""
    src = io.open(DB, encoding='utf-8', errors='replace').read()
    cols = {}
    for m in re.finditer(r'CREATE TABLE(?: IF NOT EXISTS)?\s+`?(\w+)`?\s*\(', src, re.I):
        name, i, depth, body = m.group(1), m.end() - 1, 0, ''
        for j in range(i, len(src)):
            if src[j] == '(':
                depth += 1
            elif src[j] == ')':
                depth -= 1
                if depth == 0:
                    body = src[i + 1:j]
                    break
        found = {}
        for part in body.split(','):
            part = part.strip().replace('\n', ' ')
            w = re.match(r'`?(\w+)`?\s+([A-Za-z]+(?:\(\d+(?:,\d+)?\))?)', part)
            if w and w.group(1).upper() not in (
                    'PRIMARY', 'FOREIGN', 'UNIQUE', 'KEY', 'INDEX', 'CONSTRAINT', 'CHECK'):
                found[w.group(1)] = w.group(2)
        if name not in cols or len(found) > len(cols[name]):
            cols[name] = found

    # 補上 migrations 新增的欄位
    mig = os.path.join(os.path.dirname(DB), 'scripts', 'migrations')
    if os.path.isdir(mig):
        for fn in sorted(os.listdir(mig)):
            if not fn.endswith('.sql'):
                continue
            s = io.open(os.path.join(mig, fn), encoding='utf-8', errors='ignore').read()
            for m in re.finditer(
                    r'ALTER TABLE\s+`?(\w+)`?\s+ADD\s+(?:COLUMN\s+)?`?(\w+)`?\s+'
                    r'([A-Za-z]+(?:\(\d+(?:,\d+)?\))?)', s, re.I):
                cols.setdefault(m.group(1), {}).setdefault(m.group(2), m.group(3))
    return cols


def scan_classes():
    """抓出所有 classDiagram 的類別與屬性，回傳 {類別: [(型別, 欄位)]}。

    2026-09-17：工作台的圖改成 draw.io 之後，HTML 裡已經沒有 mermaid 原始碼，
    改讀 mermaid原始碼/D54*.mmd —— 那本來就是內容的真相來源，draw.io 檔是由它產生的。"""
    import glob
    SRC = os.path.join(os.path.dirname(WB), 'mermaid原始碼')
    blocks = [io.open(f, encoding='utf-8').read()
              for f in sorted(glob.glob(os.path.join(SRC, 'D54*.mmd')))]
    blocks = [b for b in blocks if 'classDiagram' in b]
    if not blocks:
        sys.exit('找不到 classDiagram 原始碼')
    attrs, cur = {}, None
    for cd in blocks:
        for line in cd.splitlines():
            ls = line.strip()
            m = re.match(r'class\s+(\S+?)\s*\{', ls)
            if m:
                cur = m.group(1)
                attrs.setdefault(cur, [])
                continue
            if ls == '}':
                cur = None
                continue
            if cur and ls.startswith('+'):
                toks = ls[1:].strip().split()
                if len(toks) >= 2 and toks[0] in TYPES:
                    attrs[cur].append((toks[0], toks[1]))
                else:
                    attrs[cur].append((None, toks[0]))
    return len(blocks), attrs


def main():
    cols = scan_columns()
    nblocks, attrs = scan_classes()

    bad, okn, skipped, untyped = [], 0, 0, 0
    for cls, items in attrs.items():
        tbl = MAP.get(cls, '__UNMAPPED__')
        if tbl is None:
            skipped += len(items)
            continue
        if tbl == '__UNMAPPED__':
            bad.append((cls, '(類別未對應到表)', ''))
            continue
        have = cols.get(tbl)
        if not have:
            bad.append((cls, tbl, '找不到這張表的 DDL'))
            continue
        for typ, name in items:
            if name not in have:
                bad.append((cls, tbl, '欄位不存在: ' + name))
                continue
            want = sqltype(have[name])
            if typ is None:
                untyped += 1
            elif typ != want:
                bad.append((cls, tbl, '型別不符: %s 標成 %s，DDL 是 %s → 應為 %s'
                            % (name, typ, have[name], want)))
            else:
                okn += 1

    print('classDiagram %d 張，類別 %d 個（含引用框）' % (nblocks, len(attrs)))
    print('屬性比對：名稱與型別皆通過 %d，未標型別 %d，跳過（無資料表）%d，問題 %d'
          % (okn, untyped, skipped, len(bad)))
    if bad:
        print('\n--- 需確認 ---')
        for c, t, why in bad:
            print('  X %-14s %-26s %s' % (c, t, why))
        sys.exit(1)


if __name__ == '__main__':
    main()
