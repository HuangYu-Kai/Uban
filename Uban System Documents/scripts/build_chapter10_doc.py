# -*- coding: utf-8 -*-
r"""
Generate Chapter 10 Document (Word .docx and Markdown .md)
Strictly adheres to:
1. Heading 1: 16 pt, Heading 2: 14 pt, Body: 12 pt.
2. Fonts: Chinese DFKai-SB (標楷體), English Times New Roman.
3. Typography: All 12pt body text and table cells strictly EXACTLY 18pt line spacing, space before 0pt, space after 0pt.
4. Tables: All text exactly 12 pt, vertical alignment center.
   - Non-detailed overview table (10-1-1): horizontally centered.
   - Detailed test case tables (10-2-1 ~ 10-2-36): left column centered label, right column left-aligned content.
   - Captions: bold=False, keep_with_next=True.
   - cantSplit on every row, tblHeader on header rows.
5. Section breaks: 10-1 and 10-2 separated by Section Break (Next Page).
6. Official System Name: "Uban". 0 occurrences of "Uban 居家高齡長者智慧守護系統", "Uban 智慧長者守護系統", "高熵", "收件匣".
"""

import os
import shutil
import docx
from docx.shared import Pt, RGBColor, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.enum.section import WD_SECTION_START
from docx.oxml import OxmlElement, parse_xml
from docx.oxml.ns import nsdecls, qn

from chapter10_data import TEST_PLAN_SUMMARY, TEST_CASES

def set_cell_background(cell, color_hex):
    shading_xml = f'<w:shd {nsdecls("w")} w:fill="{color_hex}"/>'
    cell._tc.get_or_add_tcPr().append(parse_xml(shading_xml))

def set_cell_margins(cell, top=60, bottom=60, left=90, right=90):
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

def add_section_break(doc):
    new_sect = doc.add_section(WD_SECTION_START.NEW_PAGE)
    new_sect.top_margin = Inches(1.0)
    new_sect.bottom_margin = Inches(1.0)
    new_sect.left_margin = Inches(1.0)
    new_sect.right_margin = Inches(1.0)
    return new_sect

def create_overview_table(doc, table_id, title_text, headers, rows_data, col_widths=None):
    """表 10-1-1 測試計畫總表：內容垂直置中、水平靠中對齊，字體 12 點"""
    p_caption = doc.add_paragraph()
    p_caption.paragraph_format.space_before = Pt(6)
    p_caption.paragraph_format.space_after = Pt(2)
    p_caption.paragraph_format.keep_with_next = True
    p_caption.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run_cap = p_caption.add_run()
    format_run(run_cap, f"表 {table_id} {title_text}", font_east="標楷體", font_ascii="Times New Roman", size_pt=12, bold=False, color_rgb=(20, 40, 80))

    table = doc.add_table(rows=len(rows_data) + 1, cols=len(headers))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    set_table_borders(table, color="B0C4DE", sz="4", val="single")

    if col_widths and len(col_widths) == len(headers):
        for row in table.rows:
            for idx, width in enumerate(col_widths):
                row.cells[idx].width = width

    # 表頭設定
    header_tr = table.rows[0]._tr.get_or_add_trPr()
    header_tr.append(parse_xml(f'<w:tblHeader {nsdecls("w")}/>'))
    header_tr.append(parse_xml(f'<w:cantSplit {nsdecls("w")}/>'))

    for idx, h_text in enumerate(headers):
        cell = table.rows[0].cells[idx]
        set_cell_background(cell, "EBF1F5")
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

    # 資料列
    for row_idx, r_data in enumerate(rows_data):
        row = table.rows[row_idx + 1]
        trPr = row._tr.get_or_add_trPr()
        trPr.append(parse_xml(f'<w:cantSplit {nsdecls("w")}/>'))
        bg_color = "FAFAFA" if row_idx % 2 == 1 else "FFFFFF"
        for col_idx, val in enumerate(r_data):
            cell = row.cells[col_idx]
            set_cell_background(cell, bg_color)
            set_cell_margins(cell, top=60, bottom=60, left=80, right=80)
            cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
            p = cell.paragraphs[0]
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.space_before = Pt(0)
            p.paragraph_format.space_after = Pt(0)
            p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
            p.paragraph_format.line_spacing = Pt(18)
            r = p.add_run()
            format_run(r, str(val), font_east="標楷體", font_ascii="Times New Roman", size_pt=12, bold=False, color_rgb=(40, 40, 40))

def create_test_case_table(doc, item):
    """表 10-2-x 測試個案詳細說明表格：垂直置中、內容靠左對齊，字體 12 點"""
    p_caption = doc.add_paragraph()
    p_caption.paragraph_format.space_before = Pt(6)
    p_caption.paragraph_format.space_after = Pt(2)
    p_caption.paragraph_format.keep_with_next = True
    p_caption.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run_cap = p_caption.add_run()
    format_run(run_cap, f"表 {item['table_id']} {item['func_name']}", font_east="標楷體", font_ascii="Times New Roman", size_pt=12, bold=False, color_rgb=(20, 40, 80))

    table = doc.add_table(rows=6, cols=2)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    set_table_borders(table, color="B0C4DE", sz="6", val="single")

    col_widths = [Inches(1.5), Inches(5.0)]
    for row in table.rows:
        trPr = row._tr.get_or_add_trPr()
        trPr.append(parse_xml(f'<w:cantSplit {nsdecls("w")}/>'))
        for idx, width in enumerate(col_widths):
            row.cells[idx].width = width

    fields = [
        ("測試編號", item["case_id"], False),
        ("功能名稱", item["func_name"], False),
        ("測試目的", item["purpose"], False),
        ("測試流程", item["steps"], False),
        ("預期結果", item["expected"], False),
        ("測試結果", item["result"], True),
    ]

    for row_idx, (label, val, is_highlight) in enumerate(fields):
        cell_lbl = table.rows[row_idx].cells[0]
        cell_val = table.rows[row_idx].cells[1]

        set_cell_background(cell_lbl, "EBF1F5")
        set_cell_background(cell_val, "FFFFFF")
        set_cell_margins(cell_lbl, 50, 50, 80, 80)
        set_cell_margins(cell_val, 50, 50, 80, 80)

        cell_lbl.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
        cell_val.vertical_alignment = WD_ALIGN_VERTICAL.CENTER

        # 左欄標籤置中
        p_lbl = cell_lbl.paragraphs[0]
        p_lbl.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p_lbl.paragraph_format.space_before = Pt(0)
        p_lbl.paragraph_format.space_after = Pt(0)
        p_lbl.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
        p_lbl.paragraph_format.line_spacing = Pt(18)
        r_lbl = p_lbl.add_run()
        format_run(r_lbl, label, font_east="標楷體", font_ascii="Times New Roman", size_pt=12, bold=True, color_rgb=(20, 40, 80))

        # 右欄內容靠左對齊
        p_val = cell_val.paragraphs[0]
        p_val.alignment = WD_ALIGN_PARAGRAPH.LEFT
        p_val.paragraph_format.space_before = Pt(0)
        p_val.paragraph_format.space_after = Pt(0)
        p_val.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
        p_val.paragraph_format.line_spacing = Pt(18)

        # 針對換行的多步驟分別加入段落或文字
        lines = val.split("\n")
        for l_idx, line in enumerate(lines):
            if l_idx > 0:
                p_val = cell_val.add_paragraph()
                p_val.alignment = WD_ALIGN_PARAGRAPH.LEFT
                p_val.paragraph_format.space_before = Pt(0)
                p_val.paragraph_format.space_after = Pt(0)
                p_val.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
                p_val.paragraph_format.line_spacing = Pt(18)
            r_val = p_val.add_run()
            if is_highlight:
                format_run(r_val, line, font_east="標楷體", font_ascii="Times New Roman", size_pt=12, bold=True, color_rgb=(0, 128, 64))
            else:
                format_run(r_val, line, font_east="標楷體", font_ascii="Times New Roman", size_pt=12, bold=False, color_rgb=(30, 30, 30))

def build_docx(target_docx_path):
    print(f"Building docx at {target_docx_path}...")
    doc = docx.Document()

    # 頁面邊界 1 英吋
    for s in doc.sections:
        s.top_margin = Inches(1.0)
        s.bottom_margin = Inches(1.0)
        s.left_margin = Inches(1.0)
        s.right_margin = Inches(1.0)

    # 第十章 操作模型（大標題 16 點）
    add_heading_1(doc, "第十章 操作模型")

    # 10-1 測試計畫（小標題 14 點）
    add_heading_2(doc, "10-1 測試計畫")
    add_paragraph(
        doc,
        "本測試計畫旨在確保「Uban」在長者端、家屬端、雲端與邊緣智慧運算服務以及開發者主控台等各項功能之運作效能、通訊穩定性、影像辨識精確度與資訊安全防護皆能達到預期目標。透過結構化與系統性的功能驗證流程，及早發現並排除潛在問題，確保系統在真實長者居家環境與各類網路情境下能提供高度可靠的守護服務。",
        indent=True
    )
    add_paragraph(
        doc,
        "本專案測試範圍涵蓋行動應用介面互動、WebRTC 雙向視訊通話、YOLOv8 骨架跌倒偵測、長時間未活動滯留判定、室內房間幾何定位、雲端與本機雙軌語言模型對話、親情語音複製合成，以及後台即時監控儀表等四大核心模組。各功能模組之測試項目分類、案例編號範圍與檢驗重心如表 10-1-1 所示：",
        indent=True
    )

    # 表 10-1-1
    create_overview_table(
        doc, "10-1-1", "Uban 測試計畫總表",
        ["模組分類", "測試編號範圍", "受測子系統名稱", "測試重點與驗證範疇說明"],
        TEST_PLAN_SUMMARY,
        [Inches(1.2), Inches(1.2), Inches(1.6), Inches(2.5)]
    )

    # 10-2 測試個案與測試結果（小標題 14 點，使用下一頁分節符號）
    add_section_break(doc)
    add_heading_2(doc, "10-2 測試個案與測試結果")
    add_paragraph(
        doc,
        "本節依照長者端日常生活陪伴、家屬端守護中心遠端照護、邊緣與雲端智慧運算服務，以及開發者主控台運作監控等四大子系統面向，規劃 36 項具體之功能測試個案。各測試個案皆詳列測試編號、功能名稱、測試目的、操作測試流程、預期結果與實際驗證結果：",
        indent=True
    )

    for item in TEST_CASES:
        create_test_case_table(doc, item)

    os.makedirs(os.path.dirname(target_docx_path), exist_ok=True)
    doc.save(target_docx_path)
    print(f"[SUCCESS] Successfully generated docx: {target_docx_path}")

def build_markdown(target_md_path):
    print(f"Building markdown at {target_md_path}...")
    lines = []
    lines.append("# 第十章 操作模型\n")
    
    # 10-1
    lines.append("## 10-1 測試計畫\n")
    lines.append("本測試計畫旨在確保「Uban」在長者端、家屬端、雲端與邊緣智慧運算服務以及開發者主控台等各項功能之運作效能、通訊穩定性、影像辨識精確度與資訊安全防護皆能達到預期目標。透過結構化與系統性的功能驗證流程，及早發現並排除潛在問題，確保系統在真實長者居家環境與各類網路情境下能提供高度可靠的守護服務。\n")
    lines.append("本專案測試範圍涵蓋行動應用介面互動、WebRTC 雙向視訊通話、YOLOv8 骨架跌倒偵測、長時間未活動滯留判定、室內房間幾何定位、雲端與本機雙軌語言模型對話、親情語音複製合成，以及後台即時監控儀表等四大核心模組。各功能模組之測試項目分類、案例編號範圍與檢驗重心如表 10-1-1 所示：\n")

    lines.append("### 表 10-1-1 Uban 測試計畫總表\n")
    lines.append("| 模組分類 | 測試編號範圍 | 受測子系統名稱 | 測試重點與驗證範疇說明 |")
    lines.append("| :---: | :---: | :---: | :---: |")
    for r in TEST_PLAN_SUMMARY:
        lines.append(f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} |")
    lines.append("\n")

    # 10-2
    lines.append("## 10-2 測試個案與測試結果\n")
    lines.append("本節依照長者端日常生活陪伴、家屬端守護中心遠端照護、邊緣與雲端智慧運算服務，以及開發者主控台運作監控等四大子系統面向，規劃 36 項具體之功能測試個案。各測試個案皆詳列測試編號、功能名稱、測試目的、操作測試流程、預期結果與實際驗證結果：\n")

    for item in TEST_CASES:
        lines.append(f"### 表 {item['table_id']} {item['func_name']}\n")
        lines.append(f"| 項目 | 內容說明 |")
        lines.append(f"| :---: | :--- |")
        lines.append(f"| **測試編號** | `{item['case_id']}` |")
        lines.append(f"| **功能名稱** | {item['func_name']} |")
        lines.append(f"| **測試目的** | {item['purpose']} |")
        steps_md = item['steps'].replace('\n', '<br>')
        lines.append(f"| **測試流程** | {steps_md} |")
        lines.append(f"| **預期結果** | {item['expected']} |")
        lines.append(f"| **測試結果** | **{item['result']}** |")
        lines.append("\n")

    os.makedirs(os.path.dirname(target_md_path), exist_ok=True)
    with open(target_md_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"[SUCCESS] Successfully generated markdown: {target_md_path}")

def main():
    base_dir = r"E:\114Project\Uban\Uban System Documents\章節性文件"
    sub_dir = os.path.join(base_dir, "Chapter 10")
    os.makedirs(sub_dir, exist_ok=True)

    target_docx = os.path.join(sub_dir, "Chapter 10.docx")
    target_md = os.path.join(sub_dir, "Chapter 10.md")

    build_docx(target_docx)
    build_markdown(target_md)

    root_docx = os.path.join(base_dir, "Chapter 10.docx")
    root_md = os.path.join(base_dir, "Chapter 10.md")
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
