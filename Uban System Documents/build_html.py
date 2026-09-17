# -*- coding: utf-8 -*-
"""把 drawio圖/ 的 .drawio 注回工作台 HTML 的 <script class="diosrc"> 區塊。

為什麼要有這一步，而不是讓 HTML 直接去讀 .drawio：
組員是從 repo 下載後<b>雙擊</b>打開 HTML 的，網址會是 file://，
Chrome 在 file:// 下禁止 fetch() 讀取旁邊的檔案（CORS），
真的改成動態讀取的話，組員那邊會 37 張圖全部空白。
所以資料夾是「原始碼真相」，HTML 是「產出」，兩者靠這支腳本同步。

改圖的流程：改 mermaid原始碼/XXX.mmd → 跑 drawio產生器/build_all.py（活動圖）、
dio_uc.py（使用個案圖）、dio_class.py（類別圖） → 跑 `python build_html.py` 注回 → git diff 會很好讀。
組員也可以直接改 drawio圖/XXX.drawio，再跑 `python build_html.py` 注回。

用法：
    python build_html.py           注回並回報改了幾張
    python build_html.py --check   只檢查是否同步，不寫檔（給 CI 或提交前自查用）
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WB = os.path.join(HERE, '第5-2至8章重寫工作台.html')
SRC = os.path.join(HERE, 'drawio圖')

# <figure ... data-id="A01" ...> 一路到它自己的 mmsrc 區塊
FIGURE = re.compile(
    r'(<figure class="dia" data-id="(?P<id>[^"]+)"[\s\S]*?'
    r'<script type="text/plain" class="diosrc">)(?P<body>[\s\S]*?)(</script>)')


def load_sources():
    """檔名格式是 <data-id>-<短名>.drawio，第一個連字號前面就是鍵。"""
    out = {}
    for fn in sorted(os.listdir(SRC)):
        if not fn.endswith('.drawio'):
            continue
        did = fn.split('-', 1)[0]
        if did in out:
            raise SystemExit('data-id 重複：%s' % did)
        out[did] = io.open(os.path.join(SRC, fn), encoding='utf-8').read().strip()
    return out


def main():
    check = '--check' in sys.argv
    html = io.open(WB, encoding='utf-8').read()
    srcs = load_sources()

    ids = [m.group('id') for m in FIGURE.finditer(html)]
    missing = [i for i in ids if i not in srcs]
    extra = [k for k in srcs if k not in ids]
    if missing or extra:
        for i in missing:
            print('HTML 有圖框但資料夾沒有對應的 .drawio：', i)
        for k in extra:
            print('資料夾有 .drawio 但 HTML 沒有對應的圖框：', k)
        raise SystemExit(1)

    changed = []

    def sub(m):
        body = '\n' + srcs[m.group('id')] + '\n'
        if body != m.group('body'):
            changed.append(m.group('id'))
        return m.group(1) + body + m.group(4)

    new = FIGURE.sub(sub, html)

    if check:
        if changed:
            print('不同步，下列 %d 張的 HTML 內容與資料夾不一致：' % len(changed))
            print('  ' + '、'.join(changed))
            raise SystemExit(1)
        print('已同步：%d 張' % len(ids))
        return

    if changed:
        io.open(WB, 'w', encoding='utf-8').write(new)
    print('注回 %d 張，其中 %d 張有變動' % (len(ids), len(changed)))
    if changed:
        print('  ' + '、'.join(changed))


if __name__ == '__main__':
    main()
