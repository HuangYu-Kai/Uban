# -*- coding: utf-8 -*-
r"""
Generate Chapter 5 Document (Word .docx and Markdown .md)
Strictly adheres to:
1. Heading 1: 16 pt, Heading 2: 14 pt, Body: 12 pt.
2. Fonts: Chinese DFKai-SB (標楷體), English Times New Roman.
3. Typography: All 12pt body text and table cells strictly EXACTLY 18pt line spacing, space before 0pt, space after 0pt.
4. Tables: All cells 12 pt, vertical center, cantSplit on rows, tblHeader on header row.
   - Captions: bold=False, keep_with_next=True.
5. Section breaks: Each subsection (5-1, 5-2, 5-3, 5-4) separated by Section Break (Next Page).
6. Preserves 100% of 5-2, 5-3, 5-4 original UML diagrams (all 16 images natively preserved).
7. Terminology: 0 occurrences of 機構, 長照, 護理, 床位, 高熵, 禪風水池. Official name: Uban.
"""

import os
import shutil
import docx
from docx.shared import Pt, RGBColor, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml import OxmlElement, parse_xml
from docx.oxml.ns import nsdecls, qn
from docx.text.paragraph import Paragraph

from chapter5_data import FUNCTIONAL_REQUIREMENTS_TABLE, NON_FUNCTIONAL_REQUIREMENTS

def set_cell_background(cell, color_hex):
    shading_xml = f'<w:shd {nsdecls("w")} w:fill="{color_hex}"/>'
    cell._tc.get_or_add_tcPr().append(parse_xml(shading_xml))

def set_cell_margins(cell, top=60, bottom=60, left=100, right=100):
    tcPr = cell._tc.get_or_add_tcPr()
    tcMar = parse_xml(
        f'<w:tcMar {nsdecls("w")}>'
        f'<w:top w:w="{top}" w:type="dxa"/>'
        f'<w:bottom w:w="{bottom}" w:type="dxa"/>'
        f'<w:left w:w="{left}" w:type="dxa"/>'
        f'<w:right w:w="{right}" w:type="dxa"/>'
        f'</w:tcMar>'
    )
    tcPr.append(tcMar)

def set_table_borders(table, color="B0C4DE", sz="4", val="single"):
    tblPr = table._tbl.tblPr
    borders_xml = f"""
    <w:tblBorders {nsdecls("w")}>
        <w:top w:val="{val}" w:sz="{sz}" w:space="0" w:color="{color}"/>
        <w:left w:val="{val}" w:sz="{sz}" w:space="0" w:color="{color}"/>
        <w:bottom w:val="{val}" w:sz="{sz}" w:space="0" w:color="{color}"/>
        <w:right w:val="{val}" w:sz="{sz}" w:space="0" w:color="{color}"/>
        <w:insideH w:val="{val}" w:sz="{sz}" w:space="0" w:color="{color}"/>
        <w:insideV w:val="{val}" w:sz="{sz}" w:space="0" w:color="{color}"/>
    </w:tblBorders>
    """
    tblPr.append(parse_xml(borders_xml))

def format_run(run, text, font_east="標楷體", font_ascii="Times New Roman", size_pt=12, bold=False, color_rgb=(0, 0, 0)):
    run.text = text
    run.font.name = font_ascii
    run.font.size = Pt(size_pt)
    run.bold = bold
    run.font.color.rgb = RGBColor(*color_rgb)
    rPr = run._r.get_or_add_rPr()
    rFonts = rPr.find(qn('w:rFonts'))
    if rFonts is None:
        rFonts = OxmlElement('w:rFonts')
        rPr.append(rFonts)
    rFonts.set(qn('w:eastAsia'), font_east)
    rFonts.set(qn('w:ascii'), font_ascii)
    rFonts.set(qn('w:hAnsi'), font_ascii)

def add_heading_1(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(16)
    p.paragraph_format.space_after = Pt(8)
    p.paragraph_format.keep_with_next = True
    r = p.add_run()
    format_run(r, text, font_east="標楷體", font_ascii="Times New Roman", size_pt=16, bold=True, color_rgb=(0, 51, 102))
    return p

def add_heading_2(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(14)
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.keep_with_next = True
    r = p.add_run()
    format_run(r, text, font_east="標楷體", font_ascii="Times New Roman", size_pt=14, bold=True, color_rgb=(20, 60, 110))
    return p

def add_heading_3(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(12)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.keep_with_next = True
    r = p.add_run()
    format_run(r, text, font_east="標楷體", font_ascii="Times New Roman", size_pt=14, bold=True, color_rgb=(30, 70, 120))
    return p

def add_paragraph(doc, text, bold_prefix="", indent=True):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
    p.paragraph_format.line_spacing = Pt(18)
    if indent:
        p.paragraph_format.first_line_indent = Pt(24)
    if bold_prefix:
        r_pre = p.add_run()
        format_run(r_pre, bold_prefix, font_east="標楷體", font_ascii="Times New Roman", size_pt=12, bold=True, color_rgb=(0, 0, 0))
    r_body = p.add_run()
    format_run(r_body, text, font_east="標楷體", font_ascii="Times New Roman", size_pt=12, bold=False, color_rgb=(30, 30, 30))
    return p

def create_section_break_paragraph():
    p_xml = f'<w:p {nsdecls("w")}><w:pPr><w:sectPr><w:type w:val="nextPage"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:pPr></w:p>'
    return parse_xml(p_xml)

def create_functional_req_table(doc):
    """產製表 5-1-1 使用者功能性需求表"""
    p_caption = doc.add_paragraph()
    p_caption.paragraph_format.space_before = Pt(6)
    p_caption.paragraph_format.space_after = Pt(2)
    p_caption.paragraph_format.keep_with_next = True
    p_caption.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run_cap = p_caption.add_run()
    # 遵照需求 6：圖、表標題不使用粗體，並與表格置於同一頁
    format_run(run_cap, "表 5-1-1 Uban 使用者功能性需求表", font_east="標楷體", font_ascii="Times New Roman", size_pt=12, bold=False, color_rgb=(20, 40, 80))

    headers = ["角色", "使用案例", "事件項目", "系統規格與功能詳細說明"]
    table = doc.add_table(rows=len(FUNCTIONAL_REQUIREMENTS_TABLE) + 1, cols=len(headers))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    set_table_borders(table, color="B0C4DE", sz="4", val="single")

    col_widths = [Inches(1.0), Inches(1.4), Inches(1.6), Inches(2.6)]
    for row in table.rows:
        for idx, width in enumerate(col_widths):
            row.cells[idx].width = width

    # 表頭設定
    header_tr = table.rows[0]._tr.get_or_add_trPr()
    header_tr.append(parse_xml(f'<w:tblHeader {nsdecls("w")}/>'))
    header_tr.append(parse_xml(f'<w:cantSplit {nsdecls("w")}/>'))

    for idx, h_text in enumerate(headers):
        cell = table.rows[0].cells[idx]
        set_cell_background(cell, "D9E1F2")
        set_cell_margins(cell, top=60, bottom=60, left=90, right=90)
        cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_before = Pt(0)
        p.paragraph_format.space_after = Pt(0)
        p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
        p.paragraph_format.line_spacing = Pt(18)
        r = p.add_run()
        format_run(r, h_text, font_east="標楷體", font_ascii="Times New Roman", size_pt=12, bold=True, color_rgb=(20, 40, 80))

    # 資料列設定
    for row_idx, r_data in enumerate(FUNCTIONAL_REQUIREMENTS_TABLE):
        row = table.rows[row_idx + 1]
        trPr = row._tr.get_or_add_trPr()
        trPr.append(parse_xml(f'<w:cantSplit {nsdecls("w")}/>'))

        bg_color = "FAFAFA" if row_idx % 2 == 1 else "FFFFFF"
        for col_idx, val in enumerate(r_data):
            cell = row.cells[col_idx]
            set_cell_background(cell, bg_color)
            set_cell_margins(cell, top=50, bottom=50, left=90, right=90)
            cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
            p = cell.paragraphs[0]
            p.paragraph_format.space_before = Pt(0)
            p.paragraph_format.space_after = Pt(0)
            p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
            p.paragraph_format.line_spacing = Pt(18)

            # 前三欄水平置中，最後一欄靠左
            if col_idx < 3:
                p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                r = p.add_run()
                format_run(r, str(val), font_east="標楷體", font_ascii="Times New Roman", size_pt=12, bold=(col_idx == 0), color_rgb=(40, 40, 40))
            else:
                p.alignment = WD_ALIGN_PARAGRAPH.LEFT
                r = p.add_run()
                format_run(r, str(val), font_east="標楷體", font_ascii="Times New Roman", size_pt=12, color_rgb=(30, 30, 30))

    p_spacer = doc.add_paragraph()
    p_spacer.paragraph_format.space_before = Pt(0)
    p_spacer.paragraph_format.space_after = Pt(0)
    p_spacer.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
    p_spacer.paragraph_format.line_spacing = Pt(18)
    return p_caption, table, p_spacer

def format_existing_heading_element(p_elem, text, doc):
    """將既有段落之內容完全替換為符合規範之標題樣式"""
    for child in list(p_elem):
        if child.tag.endswith('}r'):
            p_elem.remove(child)
    p_obj = Paragraph(p_elem, doc)
    p_obj.paragraph_format.space_before = Pt(14)
    p_obj.paragraph_format.space_after = Pt(6)
    p_obj.paragraph_format.keep_with_next = True
    r = p_obj.add_run()
    format_run(r, text, font_east="標楷體", font_ascii="Times New Roman", size_pt=14, bold=True, color_rgb=(20, 60, 110))
    return p_obj

def generate_chapter5_docx(source_docx_path, target_docx_path):
    print(f"Reading base docx from: {source_docx_path}")
    doc = docx.Document(source_docx_path)
    body = doc._body._element

    # 取得 5-2 的起始段落節點 (原 body[14])
    p52_elem = None
    p52_idx = None
    for idx, child in enumerate(body):
        txt = ''.join(child.itertext()).strip()
        if '5-2' in txt and ('Use case' in txt or '使用' in txt):
            p52_elem = child
            p52_idx = idx
            break

    if p52_elem is None:
        raise ValueError("Could not find 5-2 paragraph in source docx!")

    print(f"Found 5-2 at body index {p52_idx}")

    # 1. 建立全新章節與 5-1 各項內容元素
    elements_to_insert = []

    # 第五章 需求模型 (大標題 16 點)
    p_ch5 = add_heading_1(doc, "第五章 需求模型")
    elements_to_insert.append(p_ch5._p)

    # 5-1 使用者需求 (中標題 14 點)
    p_sec51 = add_heading_2(doc, "5-1 使用者需求")
    elements_to_insert.append(p_sec51._p)

    p_intro = add_paragraph(
        doc,
        "本系統「Uban」專為現代家庭照護情境量身研發，"
        "著重化解出門在外工作的成年子女與獨居長輩之間的照護痛點與心理焦慮。"
        "透過高度整合邊緣運算視覺辨識、Google Gemini 智慧語音對話、WebRTC 全雙工即時影音通訊"
        "與戶外 GPS 軌跡防走失追蹤，為家庭成員建構全天候主動守護環境。"
        "本節依循軟體工程規範，將系統需求細分為「功能性需求」與「非功能性需求」兩大範疇進行系統化規格定義。"
    )
    elements_to_insert.append(p_intro._p)

    # 功能性需求 (小標題 14 點)
    p_h_func = add_heading_3(doc, "功能性需求")
    elements_to_insert.append(p_h_func._p)

    p_func_intro = add_paragraph(
        doc,
        "本系統之功能性需求依據實際使用者之操作情境，精確劃分為「長輩端」、「家屬端」"
        "與「開發者主控台」三大角色面向。全系統共定義 52 項現役核心功能需求，"
        "完整涵蓋長者無密碼快速登入、日常語音陪伴閒聊、一鍵視訊通話、一鍵 SOS 緊急求助、"
        "早安圖社群生活圈、手繪小豬步數能量養成、全域安心助理導覽、家屬端極光狀態中樞、"
        "室內房間幾何定位、戶外 GPS 軌跡回溯、居家監控串流、跌倒自動警報派發、"
        "定時用藥排程、數位人生回憶錄畫廊，以及開發者主控台運作監控等完整功能矩陣。"
        "各角色使用案例、觸發事件與系統規格說明如表 5-1-1 所示："
    )
    elements_to_insert.append(p_func_intro._p)

    # 表 5-1-1
    p_cap, tbl_func, p_spc = create_functional_req_table(doc)
    elements_to_insert.append(p_cap._p)
    elements_to_insert.append(tbl_func._tbl)
    elements_to_insert.append(p_spc._p)

    # 非功能性需求 (小標題 14 點)
    p_h_nonfunc = add_heading_3(doc, "非功能性需求")
    elements_to_insert.append(p_h_nonfunc._p)

    p_nonfunc_intro = add_paragraph(
        doc,
        "非功能性需求定義系統在運作效能、人機互動、系統可靠度、資訊安全、架構擴展性、"
        "後續維護、跨裝置相容以及法律規範等各層面之品質屬性標準。為確保 Uban 系統在真實家庭環境中"
        "能提供穩定且值得信賴之長期守護，系統訂定八大維度之品質規範："
    )
    elements_to_insert.append(p_nonfunc_intro._p)

    for req in NON_FUNCTIONAL_REQUIREMENTS:
        p_nfr = add_paragraph(doc, req["description"], bold_prefix=f"{req['dimension']}：", indent=True)
        elements_to_insert.append(p_nfr._p)

    # 2. 將所有新建元素依序移動至 p52_elem 前方
    for elem in elements_to_insert:
        p52_elem.addprevious(elem)

    # 3. 刪除原有的前 p52_idx 個過期節點 (原 0 到 13)
    for _ in range(p52_idx):
        body.remove(body[0])

    print("Successfully replaced Section 5-1 elements!")

    # 4. 遵照需求 5：小節之間以「下一頁 (分節符號)」隔開，並格式化 5-2、5-3、5-4 標題
    for child in list(body):
        txt = ''.join(child.itertext()).strip()
        if '5-2' in txt and ('Use case' in txt or '使用' in txt):
            # 插入分節符號 (下一頁)
            child.addprevious(create_section_break_paragraph())
            format_existing_heading_element(child, "5-2 使用案例圖 (Use case diagram)", doc)
            print("Formatted 5-2 heading with next-page section break")
        elif '5-3' in txt and ('Activity' in txt or '活動' in txt):
            # 插入分節符號 (下一頁)
            child.addprevious(create_section_break_paragraph())
            format_existing_heading_element(child, "5-3 使用案例描述：使用活動圖 (Activity diagram) 描述之", doc)
            print("Formatted 5-3 heading with next-page section break")
        elif '5-4' in txt and ('Analysis class' in txt or '分析' in txt):
            # 插入分節符號 (下一頁)
            child.addprevious(create_section_break_paragraph())

            # 插入 5-4 獨立標題段落
            p54_h = doc.add_paragraph()
            p54_h.paragraph_format.space_before = Pt(14)
            p54_h.paragraph_format.space_after = Pt(6)
            p54_h.paragraph_format.keep_with_next = True
            r = p54_h.add_run()
            format_run(r, "5-4 分析類別圖 (Analysis class diagram)", font_east="標楷體", font_ascii="Times New Roman", size_pt=14, bold=True, color_rgb=(20, 60, 110))
            child.addprevious(p54_h._p)

            # 移除 child 中不含 drawing 的文字 run
            for r_node in list(child):
                if r_node.tag.endswith('}r') and not r_node.xpath('.//w:drawing'):
                    child.remove(r_node)
            print("Formatted 5-4 heading with next-page section break and cleaned text runs")

    # 清理 5-3 圖片段落中殘留的非圖片 run
    for child in body:
        if child.xpath('.//w:drawing'):
            for r_node in list(child):
                if r_node.tag.endswith('}r') and not r_node.xpath('.//w:drawing'):
                    child.remove(r_node)

    # 設定全文件各節之標準邊界為 1 英吋
    for s in doc.sections:
        s.top_margin = Inches(1.0)
        s.bottom_margin = Inches(1.0)
        s.left_margin = Inches(1.0)
        s.right_margin = Inches(1.0)

    # 驗證圖片數量與關聯完整性
    all_blips = doc._element.xpath('.//a:blip')
    print(f"Total blips in generated doc: {len(all_blips)}")
    for i, b in enumerate(all_blips):
        rId = b.get('{http://schemas.openxmlformats.org/officeDocument/2006/relationships}embed')
        rel = doc.part.rels.get(rId)
        if rel is None:
            raise ValueError(f"Blip {i} has broken relation: {rId}")
    print(f"All {len(all_blips)} image relationships are intact and valid!")

    os.makedirs(os.path.dirname(target_docx_path), exist_ok=True)
    doc.save(target_docx_path)
    print(f"[SUCCESS] Successfully saved Chapter 5 DOCX: {target_docx_path}")

def generate_chapter5_markdown(target_md_path):
    print(f"Generating Chapter 5 Markdown at {target_md_path}...")
    lines = []
    lines.append("# 第五章 需求模型\n")

    # 5-1
    lines.append("## 5-1 使用者需求\n")
    lines.append(
        "本系統「Uban」專為現代家庭照護情境量身研發，"
        "著重化解出門在外工作的成年子女與獨居長輩之間的照護痛點與心理焦慮。"
        "透過高度整合邊緣運算視覺辨識、Google Gemini 智慧語音對話、WebRTC 全雙工即時影音通訊"
        "與戶外 GPS 軌跡防走失追蹤，為家庭成員建構全天候主動守護環境。"
        "本節依循軟體工程規範，將系統需求細分為「功能性需求」與「非功能性需求」兩大範疇進行系統化規格定義。\n"
    )

    lines.append("### 功能性需求\n")
    lines.append(
        "本系統之功能性需求依據實際使用者之操作情境，精確劃分為「長輩端」、「家屬端」"
        "與「開發者主控台」三大角色面向。全系統共定義 52 項現役核心功能需求，"
        "完整涵蓋長者無密碼快速登入、日常語音陪伴閒聊、一鍵視訊通話、一鍵 SOS 緊急求助、"
        "早安圖社群生活圈、手繪小豬步數能量養成、全域安心助理導覽、家屬端極光狀態中樞、"
        "室內房間幾何定位、戶外 GPS 軌跡回溯、居家監控串流、跌倒自動警報派發、"
        "定時用藥排程、數位人生回憶錄畫廊，以及開發者主控台運作監控等完整功能矩陣。"
        "各角色使用案例、觸發事件與系統規格說明如表 5-1-1 所示：\n"
    )

    lines.append("#### 表 5-1-1 Uban 使用者功能性需求表\n")
    lines.append("| 角色 | 使用案例 | 事件項目 | 系統規格與功能詳細說明 |")
    lines.append("| :---: | :---: | :---: | :--- |")
    for r in FUNCTIONAL_REQUIREMENTS_TABLE:
        lines.append(f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} |")
    lines.append("\n")

    lines.append("### 非功能性需求\n")
    lines.append(
        "非功能性需求定義系統在運作效能、人機互動、系統可靠度、資訊安全、架構擴展性、"
        "後續維護、跨裝置相容以及法律規範等各層面之品質屬性標準。為確保 Uban 系統在真實家庭環境中"
        "能提供穩定且值得信賴之長期守護，系統訂定八大維度之品質規範：\n"
    )

    for req in NON_FUNCTIONAL_REQUIREMENTS:
        lines.append(f"#### {req['dimension']}\n")
        lines.append(f"{req['description']}\n")

    lines.append("## 5-2 使用案例圖 (Use case diagram)\n")
    lines.append("本系統依據長者生活端、家屬守護端與系統管理端之實際互動行為，繪製完整之 UML 使用案例圖。\n")

    lines.append("## 5-3 使用案例描述：使用活動圖 (Activity diagram) 描述之\n")
    lines.append("本節針對系統核心業務流程（含語音對話、緊急求救、視訊通話、用藥排程與警報派發等流程）運用 UML 活動圖進行行為建模。\n")

    lines.append("## 5-4 分析類別圖 (Analysis class diagram)\n")
    lines.append("本節展示 Uban 系統領域實體、邊界控制器與資料存取物件之結構化分析類別圖。\n")

    os.makedirs(os.path.dirname(target_md_path), exist_ok=True)
    with open(target_md_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"[SUCCESS] Successfully generated Chapter 5 Markdown: {target_md_path}")

def main():
    source_docx = r"E:\114Project\Uban\Uban System Documents\Chapter 5(update5-1).docx"
    base_dir = r"E:\114Project\Uban\Uban System Documents\章節性文件"
    sub_dir = os.path.join(base_dir, "Chapter 5")
    os.makedirs(sub_dir, exist_ok=True)

    target_docx = os.path.join(sub_dir, "Chapter 5.docx")
    target_md = os.path.join(sub_dir, "Chapter 5.md")

    generate_chapter5_docx(source_docx, target_docx)
    generate_chapter5_markdown(target_md)

    # 拷貝至根層備份
    root_docx = os.path.join(base_dir, "Chapter 5.docx")
    root_md = os.path.join(base_dir, "Chapter 5.md")
    try:
        shutil.copy2(target_docx, root_docx)
        print(f"[SUCCESS] Successfully copied to root docx: {root_docx}")
    except Exception as e:
        print(f"[WARNING] Could not copy to root docx: {e}")

    try:
        shutil.copy2(target_md, root_md)
        print(f"[SUCCESS] Successfully copied to root md: {root_md}")
    except Exception as e:
        print(f"[WARNING] Could not copy to root md: {e}")

if __name__ == "__main__":
    main()
