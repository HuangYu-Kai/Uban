# -*- coding: utf-8 -*-
r"""
Generate Chapter 11 Document (Word .docx and Markdown .md) - 第十一章 操作手冊
排版規範與第 12 章完全一致：
1. Heading 1: 16 pt, Heading 2: 14 pt, Body: 12 pt.
2. Fonts: Chinese DFKai-SB (標楷體), English Times New Roman.
3. All 12pt body text and table cells: EXACTLY 18pt line spacing, space before/after 0pt.
4. Tables: 12 pt, vertical alignment center.
   - Attribute column: centered, background #EBF1F5. Content column: left-aligned.
   - cantSplit on every row, tblHeader on header rows.
   - Captions and figure captions: bold=False, keep_with_next=True.
5. Images: centered；手機截圖 3.2 吋、電腦視窗截圖 5.5 吋（fig 的 w 欄位）。 檔案不存在時改插入灰字佔位「〔截圖待補：檔名〕」，圖說照常輸出。
6. Section breaks: each section (11-1 ... 11-5) separated by Section Break (Next Page).
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

from chapter11_data import (
    IMAGES_DIR,
    CHAPTER_TITLE,
    CHAPTER_INTRO,
    S11_1_TITLE,
    S11_1_INTRO,
    S11_1_AFTER,
    S11_1_TABLE,
    SECTIONS,
)

TARGET_DIR = r"C:\Users\kevin\Desktop\115207\Uban\Uban System Documents\章節性文件\Chapter 11"
ROOT_DIR = r"C:\Users\kevin\Desktop\115207\Uban\Uban System Documents\章節性文件"


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
    format_run(r, text, size_pt=16, bold=True, color_rgb=(0, 51, 102))
    return p


def add_heading_2(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(14)
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.keep_with_next = True
    r = p.add_run()
    format_run(r, text, size_pt=14, bold=True, color_rgb=(20, 60, 110))
    return p


def add_paragraph(doc, text, indent=True):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
    p.paragraph_format.line_spacing = Pt(18)
    if indent:
        p.paragraph_format.first_line_indent = Pt(24)
    r = p.add_run()
    format_run(r, text, size_pt=12, bold=False, color_rgb=(30, 30, 30))
    return p


def add_section_break(doc):
    new_sect = doc.add_section(WD_SECTION_START.NEW_PAGE)
    new_sect.top_margin = Inches(1.0)
    new_sect.bottom_margin = Inches(1.0)
    new_sect.left_margin = Inches(1.0)
    new_sect.right_margin = Inches(1.0)
    return new_sect


def add_caption(doc, text, is_table=True):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    if is_table:
        p.paragraph_format.space_before = Pt(6)
        p.paragraph_format.space_after = Pt(2)
    else:
        p.paragraph_format.space_before = Pt(2)
        p.paragraph_format.space_after = Pt(8)
    p.paragraph_format.keep_with_next = True
    r = p.add_run()
    format_run(r, text, size_pt=12, bold=False, color_rgb=(20, 40, 80))


def _fmt_cell_par(p, align):
    p.alignment = align
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
    p.paragraph_format.line_spacing = Pt(18)


def add_table(doc, table_id, title, header, rows, col_widths=None):
    add_caption(doc, f"{table_id} {title}", is_table=True)
    ncol = len(header)
    if col_widths is None:
        col_widths = (Inches(1.5), Inches(5.0)) if ncol == 2 else tuple(Inches(6.5 / ncol) for _ in range(ncol))
    rows_def = [tuple(header)] + [tuple(r) for r in rows]
    table = doc.add_table(rows=len(rows_def), cols=ncol)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    set_table_borders(table)

    table.rows[0]._tr.get_or_add_trPr().append(parse_xml(f'<w:tblHeader {nsdecls("w")}/>'))

    for row_idx, vals in enumerate(rows_def):
        row = table.rows[row_idx]
        row._tr.get_or_add_trPr().append(parse_xml(f'<w:cantSplit {nsdecls("w")}/>'))
        is_header = (row_idx == 0)
        for ci, content in enumerate(vals):
            c = row.cells[ci]
            c.width = col_widths[ci]
            c.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
            set_cell_margins(c, top=50, bottom=50, left=80, right=80)
            if ci == 0:
                set_cell_background(c, "D9E1F2" if is_header else "EBF1F5")
            else:
                set_cell_background(c, "D9E1F2" if is_header else "FFFFFF")
            for i, line in enumerate(content.split(chr(10))):
                p1 = c.paragraphs[0] if i == 0 else c.add_paragraph()
                if is_header or ci == 0:
                    _fmt_cell_par(p1, WD_ALIGN_PARAGRAPH.CENTER)
                    format_run(p1.add_run(), line, size_pt=12, bold=True, color_rgb=(20, 40, 80))
                else:
                    _fmt_cell_par(p1, WD_ALIGN_PARAGRAPH.LEFT)
                    format_run(p1.add_run(), line, size_pt=12, bold=False, color_rgb=(20, 20, 20))


def add_figure(doc, f):
    img_path = os.path.join(IMAGES_DIR, f["file"])
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(6)
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.keep_with_next = True
    r = p.add_run()
    if os.path.exists(img_path):
        r.add_picture(img_path, width=Inches(f.get("w", 5.5)))
    else:
        format_run(r, f"〔截圖待補：{f['file']}〕", size_pt=12, bold=False, color_rgb=(128, 128, 128))
    add_caption(doc, f"{f['fig_id']} {f['title']}", is_table=False)


def add_block(doc, block):
    widths = tuple(Inches(x) for x in block["widths"]) if block.get("widths") else None
    add_table(doc, block["table_id"], block["title"], block["header"], block["rows"], widths)
    if block.get("after"):
        add_paragraph(doc, block["after"])
    for f in block["figs"]:
        add_figure(doc, f)


def generate_docx(output_path):
    print(f"Generating DOCX -> {output_path}")
    doc = docx.Document()
    for sec in doc.sections:
        sec.top_margin = sec.bottom_margin = sec.left_margin = sec.right_margin = Inches(1.0)

    add_heading_1(doc, CHAPTER_TITLE)
    add_paragraph(doc, CHAPTER_INTRO)

    add_heading_2(doc, S11_1_TITLE)
    add_paragraph(doc, S11_1_INTRO)
    t = S11_1_TABLE
    add_table(doc, t["table_id"], t["title"], t["header"], t["rows"])
    add_paragraph(doc, S11_1_AFTER)

    for title, intro, blocks in SECTIONS:
        add_section_break(doc)
        add_heading_2(doc, title)
        add_paragraph(doc, intro)
        for b in blocks:
            add_block(doc, b)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    doc.save(output_path)
    print("DOCX done")


def _md_table(block):
    h = block["header"]
    out = [f"### {block['table_id']} {block['title']}"+chr(10), "| " + " | ".join(h) + " |",
           "| " + " | ".join([":---:"] + [":---"] * (len(h) - 1)) + " |"]
    for r in block["rows"]:
        cells = [f"**{r[0]}**"] + [c.replace(chr(10), "<br>") for c in r[1:]]
        out.append("| " + " | ".join(cells) + " |")
    out.append("")
    if block.get("after"):
        out.append(block["after"] + chr(10))
    return out


def generate_markdown(output_path):
    print(f"Generating Markdown -> {output_path}")
    md = [f"# {CHAPTER_TITLE}\n", CHAPTER_INTRO + "\n"]
    md.append(f"## {S11_1_TITLE}\n")
    md.append(S11_1_INTRO + "\n")
    md.extend(_md_table({**S11_1_TABLE}))
    md.append(S11_1_AFTER + "\n")
    for title, intro, blocks in SECTIONS:
        md.append(f"## {title}\n")
        md.append(intro + "\n")
        for b in blocks:
            md.extend(_md_table(b))
            for f in b["figs"]:
                if os.path.exists(os.path.join(IMAGES_DIR, f["file"])):
                    md.append(f"![{f['title']}](images/{f['file']})\n")
                else:
                    md.append(f"<p align=\"center\">〔截圖待補：{f['file']}〕</p>\n")
                md.append(f"<p align=\"center\">{f['fig_id']} {f['title']}</p>\n")
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(md))
    print("Markdown done")


def generate_shot_list(path):
    lines = ["第十一章 截圖清單（已有圖者標「已完成」；只剩圖 11-3-3 待補，須用實體手機拍攝後以檔名放入本資料夾，產生器偵測到檔案會自動插入）",
             "格式：檔名 | 圖說 | 要拍的畫面", ""]
    for _, _, blocks in SECTIONS:
        for b in blocks:
            for f in b["figs"]:
                lines.append(f"{f['file']} | {f['fig_id']} {f['title']} | {f['shoot']}")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"Shot list: {path}")


def main():
    os.makedirs(IMAGES_DIR, exist_ok=True)
    docx_path = os.path.join(TARGET_DIR, "Chapter 11.docx")
    md_path = os.path.join(TARGET_DIR, "Chapter 11.md")
    generate_docx(docx_path)
    generate_markdown(md_path)
    generate_shot_list(os.path.join(IMAGES_DIR, "截圖清單.txt"))
    shutil.copyfile(docx_path, os.path.join(ROOT_DIR, "Chapter 11.docx"))
    shutil.copyfile(md_path, os.path.join(ROOT_DIR, "Chapter 11.md"))
    print("Copied to root.")


if __name__ == "__main__":
    main()
