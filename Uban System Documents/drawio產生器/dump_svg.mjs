// 把 .drawio 交給官方 viewer 渲染，再把產生的 SVG 存出來供幾何檢查
import puppeteer from 'puppeteer-core';
import fs from 'node:fs';
import path from 'node:path';
const [,, dir, outDir] = process.argv;
fs.mkdirSync(outDir, {recursive:true});
const files = fs.readdirSync(dir).filter(f => f.endsWith('.drawio')).sort();
const b = await puppeteer.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe', args:['--no-sandbox']});
const p = await b.newPage();
await p.setViewport({width:1600, height:1000});
for (const f of files) {
  const xml = fs.readFileSync(path.join(dir, f), 'utf8');
  const html = '<!doctype html><meta charset="utf-8"><div class="mxgraph" id="g"></div>'
    + '<script>window.GX=' + JSON.stringify(xml) + ';</scr' + 'ipt>'
    + '<script src="https://viewer.diagrams.net/js/viewer-static.min.js"></scr' + 'ipt>'
    + '<script>document.getElementById("g").setAttribute("data-mxgraph",JSON.stringify({xml:window.GX,toolbar:"",nav:false,zoom:1}));GraphViewer.processElements();</scr' + 'ipt>';
  const tmp = path.join(outDir, '_tmp.html');  // 暫存檔放輸出資料夾，不要污染 drawio圖/
  fs.writeFileSync(tmp, html, 'utf8');
  await p.goto('file:///' + tmp.split(String.fromCharCode(92)).join('/'), {waitUntil:'networkidle0', timeout:60000});
  await new Promise(r => setTimeout(r, 700));
  const svg = await p.evaluate(() => { const s = document.querySelector('svg'); return s ? s.outerHTML : ''; });
  fs.writeFileSync(path.join(outDir, f.replace('.drawio', '.svg')), svg, 'utf8');
  console.log(f, svg.length);
}
fs.unlinkSync(path.join(outDir, '_tmp.html'));
await b.close();
