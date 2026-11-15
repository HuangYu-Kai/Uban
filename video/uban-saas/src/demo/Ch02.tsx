// 第二章：系統架構總覽（分鏡 01:30–03:30，共 120 秒）
// 主要手法：路徑描繪＋資料流動；材質：動畫圖解
import React from "react";
import { AbsoluteFill, Audio, Sequence, interpolate, spring, staticFile, useCurrentFrame } from "remotion";
import { BackendChips, ChapterCard, Chip, COLORS as C, FONT, FPS, MONO, Sub, Subtitles, clamp, ease, sec } from "./common";

// ================= 可直接修改的內容 =================
const SHOW_SUBS = true;
const T = { a: 0, b: sec(30), c: sec(70), d: sec(100), end: sec(120) };
export const CH02_FRAMES = T.end;

const SIGNAL = "#3E957A"; // 信令（綠）
const MEDIA = "#E58A4E"; //  影音（橘）
const AI = "#5B6FB0"; //     AI（藍紫）
const DATA = "#5D6B66"; //   資料

const SUBS: Sub[] = [
  // A 架構
  { from: sec(1.6), to: sec(7.5), text: "兩個 App 都用 Flutter 開發，連到同一個 FastAPI 後端。" },
  { from: sec(8), to: sec(13), text: "後端同時提供 REST API 和 Socket.IO 即時通道，" },
  { from: sec(13.5), to: sec(17.5), text: "資料存在 MySQL，" },
  { from: sec(18), to: sec(29), text: "長輩說過的話則轉成向量放進 Pinecone，成為小嘎的長期記憶。" },
  // B 雙軌制
  { from: sec(31), to: sec(35), text: "視訊通話，我們用「雙軌制」。" },
  { from: sec(35.5), to: sec(45), text: "開鏡頭需要 HTTPS，所以信令走 Tailscale 的 HTTPS 通道；" },
  { from: sec(45.5), to: sec(58), text: "但即時影像需要 UDP，所以媒體改由 Oracle Cloud 上的 TURN 伺服器轉送。" },
  { from: sec(58.5), to: sec(69.5), text: "兩條路分開，4G 和 Wi-Fi 之間也能穩定接通。" },
  // C AI 引擎
  { from: sec(71), to: sec(78.5), text: "小嘎的大腦，是我們自己架設的 Gemma 4 模型；" },
  { from: sec(79), to: sec(85.5), text: "萬一主機忙不過來，會自動切到 Gemini 備援。" },
  { from: sec(86), to: sec(94.5), text: "小嘎背後有 18 項工具，查天氣、查停班停課、找家人、排行程，" },
  { from: sec(95), to: sec(99.5), text: "都是真的去查、真的去做。" },
  // D 通知管道
  { from: sec(101), to: sec(106), text: "訊息要送到對方手上，我們同時準備兩條路：" },
  { from: sec(106.5), to: sec(111.5), text: "App 開著走即時通道，App 關著走推播。" },
  { from: sec(112), to: sec(119.5), text: "而且依事情輕重分級——跌倒是高優先，一般關心不會半夜吵醒人。" },
];

const CHIPS: Chip[] = [
  { from: sec(4), to: sec(13), text: "FastAPI（Python 3.12）＋ Socket.IO" },
  { from: sec(13.5), to: sec(20), text: "MySQL：參數化 SQL，不用 ORM" },
  { from: sec(18), to: sec(29), text: "Pinecone：768 維記憶向量" },
  { from: sec(36), to: sec(46), text: "信令：只交換 SDP／ICE 文字（TCP / WSS）" },
  { from: sec(46), to: sec(60), text: "TURN／STUN 中繼：影音（UDP）" },
  { from: sec(72), to: sec(80), text: "主引擎：gemma4:e4b（Ollama 自架）" },
  { from: sec(80), to: sec(86), text: "連不上 → 自動改用 Gemini" },
  { from: sec(87), to: sec(99), text: "TOOL_MAP：兩個引擎共用同一份工具表" },
  { from: sec(104), to: sec(112), text: "線上走 Socket、離線走 FCM，以 callId 去重" },
  { from: sec(112), to: sec(119.5), text: "跌倒：高優先級　｜　一般關心：一般優先級" },
];

// 18 項工具（依 uban-api readme「四、AI Tool Calling」）
const TOOLS = ["查時間", "查天氣", "停班停課", "颱風", "地震", "我在哪裡", "問家人", "提出提醒", "確認提醒", "長輩背景", "家人留言", "通知家人", "建議活動", "記錄活動", "記錄吃藥", "打視訊", "查新聞", "找影片"];
// ===================================================

type P = { x: number; y: number };
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const lerpP = (a: P, b: P, t: number): P => ({ x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t) });
// 二次貝茲曲線上的點
const qAt = (a: P, c: P, b: P, t: number): P => ({ x: (1 - t) ** 2 * a.x + 2 * (1 - t) * t * c.x + t * t * b.x, y: (1 - t) ** 2 * a.y + 2 * (1 - t) * t * c.y + t * t * b.y });
const ctrl = (a: P, b: P, bend = 0): P => ({ x: (a.x + b.x) / 2 - (b.y - a.y) * bend, y: (a.y + b.y) / 2 + (b.x - a.x) * bend });

// ---------- 圖示 ----------
const Glyph: React.FC<{ kind: string; color: string }> = ({ kind, color }) => {
  const s = { fill: "none", stroke: color, strokeWidth: 3.5, strokeLinecap: "round" as const, strokeLinejoin: "round" as const };
  switch (kind) {
    case "phone": return <g {...s}><rect x={-14} y={-24} width={28} height={48} rx={6} /><line x1={-5} y1={-17} x2={5} y2={-17} /></g>;
    case "server": return <g {...s}><rect x={-22} y={-22} width={44} height={18} rx={4} /><rect x={-22} y={4} width={44} height={18} rx={4} /><circle cx={-12} cy={-13} r={2} fill={color} /><circle cx={-12} cy={13} r={2} fill={color} /></g>;
    case "db": return <g {...s}><ellipse cx={0} cy={-16} rx={20} ry={7} /><path d="M-20 -16 V16 A20 7 0 0 0 20 16 V-16" /><path d="M-20 0 A20 7 0 0 0 20 0" /></g>;
    case "vector": return <g {...s}>{[[-14, -12], [10, -16], [16, 8], [-8, 14], [0, 0]].map(([x, y], i) => <circle key={i} cx={x} cy={y} r={4} fill={color} />)}<path d="M-14 -12 L0 0 L10 -16 M0 0 L16 8 M0 0 L-8 14" /></g>;
    case "chip": return <g {...s}><rect x={-16} y={-16} width={32} height={32} rx={6} /><text x={0} y={6} textAnchor="middle" fontSize={15} fontWeight={800} fill={color} stroke="none" fontFamily={MONO}>AI</text>{[-8, 0, 8].map((v) => <g key={v}><line x1={v} y1={-16} x2={v} y2={-23} /><line x1={v} y1={16} x2={v} y2={23} /><line x1={-16} y1={v} x2={-23} y2={v} /><line x1={16} y1={v} x2={23} y2={v} /></g>)}</g>;
    case "cloud": return <g {...s}><path d="M-20 12 H18 A12 12 0 0 0 16 -12 A16 16 0 0 0 -14 -10 A11 11 0 0 0 -20 12 Z" /></g>;
    case "relay": return <g {...s}><circle r={7} fill={color} /><path d="M-22 -14 Q0 -30 22 -14 M-22 14 Q0 30 22 14" /></g>;
    case "lock": return <g {...s}><rect x={-14} y={-4} width={28} height={22} rx={4} /><path d="M-8 -4 V-12 A8 8 0 0 1 8 -12 V-4" /></g>;
    default: return null;
  }
};

const Node: React.FC<{ p: P; w: number; h: number; title: string; sub?: string; kind: string; color: string; t: number; dim?: number; cross?: number }> = ({ p, w, h, title, sub, kind, color, t, dim = 0, cross = 0 }) => {
  if (t <= 0.01) return null;
  return (
    <g transform={`translate(${p.x} ${p.y}) scale(${0.85 + t * 0.15})`} opacity={t * (1 - dim * 0.6)}>
      <rect x={-w / 2} y={-h / 2} width={w} height={h} rx={22} fill="#FFFFFF" stroke={color} strokeWidth={3} filter="url(#shadow)" />
      <g transform={`translate(${-w / 2 + 52} 0)`}>
        <circle r={32} fill={color} opacity={0.12} />
        <Glyph kind={kind} color={color} />
      </g>
      <text x={-w / 2 + 100} y={sub ? -6 : 10} fontSize={30} fontWeight={800} fill={C.ink} fontFamily={FONT}>{title}</text>
      {sub && <text x={-w / 2 + 100} y={28} fontSize={21} fontWeight={600} fill={C.muted} fontFamily={FONT}>{sub}</text>}
      {cross > 0 && (
        <g opacity={cross} stroke="#D2554A" strokeWidth={8} strokeLinecap="round">
          <line x1={w / 2 - 70} y1={-30} x2={w / 2 - 20} y2={20} /><line x1={w / 2 - 20} y1={-30} x2={w / 2 - 70} y2={20} />
        </g>
      )}
    </g>
  );
};

// 線條描繪＋沿線流動的光點
const Link: React.FC<{ a: P; b: P; bend?: number; draw: number; color: string; flow?: number; dots?: number; dash?: boolean; width?: number; speed?: number; o?: number }> = ({ a, b, bend = 0, draw, color, flow = 0, dots = 3, dash, width = 4, speed = 0.012, o = 1 }) => {
  if (draw <= 0 || o <= 0) return null;
  const c = ctrl(a, b, bend);
  const d = `M${a.x} ${a.y} Q${c.x} ${c.y} ${b.x} ${b.y}`;
  const len = Math.hypot(b.x - a.x, b.y - a.y) * 1.15;
  return (
    <g opacity={o}>
      <path d={d} fill="none" stroke={color} strokeWidth={width} strokeLinecap="round" opacity={0.35} strokeDasharray={dash ? "2 14" : `${len}`} strokeDashoffset={dash ? 0 : len * (1 - draw)} />
      {flow > 0 &&
        Array.from({ length: dots }).map((_, i) => {
          const t = ((flow * speed + i / dots) % 1 + 1) % 1;
          const q = qAt(a, c, b, t);
          return <circle key={i} cx={q.x} cy={q.y} r={width + 4} fill={color} opacity={Math.sin(t * Math.PI)} />;
        })}
    </g>
  );
};

// ---------- 鏡頭 A＋B：架構 → 雙軌制（節點位置連續移動） ----------
const ArchAndDualTrack: React.FC<{ f: number }> = ({ f }) => {
  const ap = (at: number) => spring({ frame: f - at, fps: FPS, config: { damping: 16 } });
  const dr = (a: number, b: number) => interpolate(f, [a, b], [0, 1], { ...clamp, easing: ease });
  const m = dr(T.b, T.b + 40); // A → B 版面轉換
  const tilt = dr(T.b + 10, T.b + 60);
  // 位置
  const elder = lerpP({ x: 300, y: 380 }, { x: 330, y: 560 }, m);
  const family = lerpP({ x: 300, y: 740 }, { x: 1590, y: 560 }, m);
  const api = lerpP({ x: 960, y: 560 }, { x: 960, y: 250 }, m);
  const mysql = { x: 1600, y: 300 }, pine = { x: 1600, y: 560 }, ollama = { x: 1600, y: 820 };
  const turn = { x: 960, y: 870 };
  const rightOut = 1 - m;
  const turnIn = ap(T.b + sec(15));
  const sigFlow = f > T.b + sec(6) ? f - (T.b + sec(6)) : 0;
  const medFlow = f > T.b + sec(17) ? f - (T.b + sec(17)) : 0;
  const out = dr(T.c - 20, T.c);
  if (f >= T.c) return null;
  return (
    <AbsoluteFill style={{ opacity: 1 - out }}>
      <div style={{ position: "absolute", inset: 0, perspective: 2200 }}>
        <div style={{ position: "absolute", inset: 0, transform: `rotateX(${tilt * 22}deg) scale(${1 - tilt * 0.06})`, transformOrigin: "50% 60%" }}>
          <svg width={1920} height={1080}>
            <defs>
              <filter id="shadow" x="-20%" y="-30%" width="140%" height="160%"><feDropShadow dx={0} dy={10} stdDeviation={12} floodColor="#1C2925" floodOpacity={0.12} /></filter>
            </defs>
            {/* A：App → 後端 → 三個服務 */}
            <Link a={elder} b={api} bend={-0.08} draw={dr(sec(3), sec(4.5)) } color={SIGNAL} flow={f > sec(5) && f < T.b ? f : 0} o={rightOut} />
            <Link a={family} b={api} bend={0.08} draw={dr(sec(3.4), sec(5))} color={SIGNAL} flow={f > sec(5) && f < T.b ? f + 40 : 0} o={rightOut} />
            <Link a={api} b={mysql} bend={0.06} draw={dr(sec(13.5), sec(15))} color={DATA} flow={f > sec(15) ? f : 0} o={rightOut} />
            <Link a={api} b={pine} draw={dr(sec(18), sec(19.5))} color={AI} flow={f > sec(19.5) ? f : 0} o={rightOut} />
            <Link a={api} b={ollama} bend={-0.06} draw={dr(sec(22), sec(23.5))} color={AI} flow={f > sec(23.5) ? f : 0} o={rightOut} />
            {/* B：信令（綠，短促）與影音（橘，連續） */}
            <Link a={elder} b={api} bend={-0.1} draw={dr(T.b + sec(5), T.b + sec(6))} color={SIGNAL} flow={sigFlow} dots={2} speed={0.02} />
            <Link a={family} b={api} bend={0.1} draw={dr(T.b + sec(5), T.b + sec(6))} color={SIGNAL} flow={sigFlow + 25} dots={2} speed={0.02} />
            <Link a={elder} b={turn} bend={0.1} draw={dr(T.b + sec(16), T.b + sec(17))} color={MEDIA} flow={medFlow} dots={9} speed={0.008} width={7} />
            <Link a={turn} b={family} bend={0.1} draw={dr(T.b + sec(16.5), T.b + sec(17.5))} color={MEDIA} flow={medFlow} dots={9} speed={0.008} width={7} />
            <Node p={elder} w={330} h={110} title="長輩端 App" sub="Flutter" kind="phone" color={SIGNAL} t={ap(sec(1))} />
            <Node p={family} w={330} h={110} title="家屬端 App" sub="Flutter" kind="phone" color={SIGNAL} t={ap(sec(1.4))} />
            <Node p={api} w={420} h={120} title={m < 0.5 ? "FastAPI 後端" : "信令伺服器"} sub={m < 0.5 ? "REST API ＋ Socket.IO" : "Tailscale Funnel・TCP / WSS"} kind={m < 0.5 ? "server" : "lock"} color={SIGNAL} t={ap(sec(2.4))} />
            <Node p={mysql} w={360} h={110} title="MySQL" sub="打卡、提醒、警報" kind="db" color={DATA} t={ap(sec(13.5)) * rightOut} />
            <Node p={pine} w={360} h={110} title="Pinecone" sub="長期記憶向量" kind="vector" color={AI} t={ap(sec(18)) * rightOut} />
            <Node p={ollama} w={360} h={110} title="Ollama" sub="自架 Gemma 4" kind="chip" color={AI} t={ap(sec(22)) * rightOut} />
            <Node p={turn} w={440} h={120} title="TURN／STUN 中繼" sub="Oracle Cloud・UDP 影音" kind="relay" color={MEDIA} t={turnIn} />
          </svg>
        </div>
      </div>
      {/* 圖例（B 段） */}
      <div style={{ position: "absolute", left: 80, top: 70, display: "flex", gap: 36, fontFamily: FONT, fontSize: 28, fontWeight: 700, opacity: dr(T.b + sec(5), T.b + sec(6)) }}>
        <span style={{ color: SIGNAL }}>● 第一軌：信令（文字）</span>
        <span style={{ color: MEDIA, opacity: turnIn }}>● 第二軌：影音（UDP）</span>
      </div>
    </AbsoluteFill>
  );
};

// ---------- 鏡頭 C：AI 引擎＋備援＋18 項工具 ----------
const AiEngine: React.FC<{ f: number }> = ({ f }) => {
  const L = f - T.c;
  if (L < 0 || f >= T.d) return null;
  const ap = (at: number) => spring({ frame: L - at, fps: FPS, config: { damping: 16 } });
  const dr = (a: number, b: number) => interpolate(L, [a, b], [0, 1], { ...clamp, easing: ease });
  const core = { x: 840, y: 520 }, gemini = { x: 1560, y: 520 }, xiaoga = { x: 170, y: 520 };
  const fail = dr(sec(9.5), sec(10.2)); // 主機忙不過來
  const back = dr(sec(15.5), sec(16.5)); // 恢復
  const toolsIn = (i: number) => spring({ frame: L - sec(16) - i * 3, fps: FPS, config: { damping: 13 } });
  const shrinkBackup = dr(sec(15.5), sec(16.5));
  const out = dr(sec(29.4), sec(30));
  return (
    <AbsoluteFill style={{ opacity: (1 - out) * dr(0, 15) }}>
      <svg width={1920} height={1080}>
        <defs><filter id="shadow2" x="-20%" y="-30%" width="140%" height="160%"><feDropShadow dx={0} dy={10} stdDeviation={12} floodColor="#1C2925" floodOpacity={0.12} /></filter></defs>
        {/* 小嘎 → 主引擎；故障時改走 Gemini */}
        <Link a={xiaoga} b={core} draw={dr(sec(1), sec(2))} color={AI} flow={L > sec(2) && (fail < 0.5 || back > 0.5) ? L : 0} o={1 - fail * (1 - back) * 0.7} />
        <Link a={xiaoga} b={gemini} bend={-0.22} draw={dr(sec(10), sec(11))} color={SIGNAL} flow={fail > 0.5 && back < 0.5 ? L : 0} o={1 - shrinkBackup * 0.75} dots={4} />
        <g transform={`translate(${xiaoga.x} ${xiaoga.y}) scale(${ap(sec(0.3))})`}>
          <circle r={70} fill="#FFFFFF" stroke={AI} strokeWidth={3} filter="url(#shadow2)" />
          <text y={12} textAnchor="middle" fontSize={36} fontWeight={800} fill={C.ink} fontFamily={FONT}>小嘎</text>
        </g>
        {/* 主引擎 */}
        <g transform={`translate(${core.x} ${core.y}) scale(${ap(sec(1.2)) * (1 - shrinkBackup * 0)})`}>
          <circle r={150} fill="#FFFFFF" stroke={AI} strokeWidth={4} filter="url(#shadow2)" />
          <circle r={150} fill={AI} opacity={0.06 + Math.sin(L / 10) * 0.03} />
          <g transform="translate(0 -60) scale(1.6)"><Glyph kind="chip" color={AI} /></g>
          <text y={18} textAnchor="middle" fontSize={40} fontWeight={800} fill={C.ink} fontFamily={FONT}>Gemma 4</text>
          <text y={56} textAnchor="middle" fontSize={22} fontWeight={600} fill={C.muted} fontFamily={FONT}>自架・資料不出門</text>
          <g opacity={fail * (1 - back)} stroke="#D2554A" strokeWidth={10} strokeLinecap="round"><line x1={88} y1={-108} x2={128} y2={-68} /><line x1={128} y1={-108} x2={88} y2={-68} /></g>
        </g>
        {/* Gemini 備援 */}
        <g transform={`translate(${gemini.x} ${gemini.y}) scale(${ap(sec(9.8)) * (1 - shrinkBackup * 0.35)})`} opacity={1 - shrinkBackup * 0.5}>
          <rect x={-170} y={-60} width={340} height={120} rx={22} fill="#FFFFFF" stroke={SIGNAL} strokeWidth={3} filter="url(#shadow2)" />
          <g transform="translate(-110 0)"><Glyph kind="cloud" color={SIGNAL} /></g>
          <text x={-60} y={-4} fontSize={32} fontWeight={800} fill={C.ink} fontFamily={FONT}>Gemini</text>
          <text x={-60} y={30} fontSize={22} fontWeight={600} fill={C.muted} fontFamily={FONT}>備援引擎</text>
        </g>
        {/* 18 項工具：兩圈從主引擎爆開 */}
        {TOOLS.map((name, i) => {
          const inner = i < 8;
          const n = inner ? 8 : 10;
          const k = inner ? i : i - 8;
          const ang = (k / n) * Math.PI * 2 - Math.PI / 2 + (inner ? 0 : Math.PI / 10);
          const r = inner ? 300 : 460;
          const t = toolsIn(i);
          const x = core.x + Math.cos(ang) * r * t, y = core.y + Math.sin(ang) * r * (inner ? 0.78 : 0.74) * t;
          const w = 28 * name.length + 34;
          return (
            <g key={name} transform={`translate(${x} ${y}) scale(${t})`} opacity={t}>
              <rect x={-w / 2} y={-26} width={w} height={52} rx={26} fill={inner ? "#EEF0FA" : "#FFFFFF"} stroke={AI} strokeWidth={2} />
              <text y={9} textAnchor="middle" fontSize={24} fontWeight={700} fill={AI} fontFamily={FONT}>{name}</text>
            </g>
          );
        })}
      </svg>
      <div style={{ position: "absolute", right: 120, top: 120, fontFamily: FONT, textAlign: "right", opacity: dr(sec(17), sec(18)) }}>
        <div style={{ fontSize: 120, fontWeight: 800, color: AI, lineHeight: 1 }}>{Math.round(interpolate(L, [sec(16), sec(18.5)], [0, 18], clamp))}</div>
        <div style={{ fontSize: 32, fontWeight: 700, color: C.muted }}>項工具，真的去查、真的去做</div>
      </div>
    </AbsoluteFill>
  );
};

// ---------- 鏡頭 D：兩條通知管道＋輕重分級 ----------
const Notify: React.FC<{ f: number }> = ({ f }) => {
  const L = f - T.d;
  if (L < 0) return null;
  const ap = (at: number) => spring({ frame: L - at, fps: FPS, config: { damping: 16 } });
  const dr = (a: number, b: number) => interpolate(L, [a, b], [0, 1], { ...clamp, easing: ease });
  const server = { x: 900, y: 520 }, open = { x: 1520, y: 290 }, closed = { x: 1520, y: 720 }, fcm = { x: 1220, y: 760 }, sender = { x: 330, y: 520 };
  // 兩種波紋：一般（小、綠）與高優先（大、橘）
  const ripple = (start: number, big: boolean) => {
    const t = ((L - start) % 40) / 40;
    if (L < start) return null;
    return <circle r={(big ? 90 : 55) + t * (big ? 120 : 60)} fill="none" stroke={big ? "#E0703F" : SIGNAL} strokeWidth={big ? 6 : 4} opacity={(1 - t) * 0.8} />;
  };
  const phone = (p: P, lit: boolean, label: string, sub: string, t: number, rip?: React.ReactNode) => (
    <g transform={`translate(${p.x} ${p.y}) scale(${t})`}>
      {rip}
      <rect x={-55} y={-95} width={110} height={190} rx={20} fill={lit ? "#FFFFFF" : "#2A2F2D"} stroke={C.ink} strokeWidth={5} />
      {lit && <rect x={-40} y={-70} width={80} height={36} rx={8} fill={SIGNAL} opacity={0.85} />}
      <text x={90} y={-8} fontSize={32} fontWeight={800} fill={C.ink} fontFamily={FONT}>{label}</text>
      <text x={90} y={30} fontSize={23} fontWeight={600} fill={C.muted} fontFamily={FONT}>{sub}</text>
    </g>
  );
  return (
    <AbsoluteFill style={{ opacity: dr(0, 15) }}>
      <svg width={1920} height={1080}>
        <defs><filter id="shadow3" x="-20%" y="-30%" width="140%" height="160%"><feDropShadow dx={0} dy={10} stdDeviation={12} floodColor="#1C2925" floodOpacity={0.12} /></filter></defs>
        <Link a={sender} b={server} draw={dr(sec(1), sec(2))} color={SIGNAL} flow={L > sec(2) ? L : 0} />
        <Link a={server} b={open} bend={-0.08} draw={dr(sec(5), sec(6))} color={SIGNAL} flow={L > sec(6) ? L : 0} />
        <Link a={server} b={fcm} bend={0.1} draw={dr(sec(8), sec(9))} color={MEDIA} flow={L > sec(9) ? L : 0} dots={2} />
        <Link a={fcm} b={closed} bend={0.1} draw={dr(sec(8.5), sec(9.5))} color={MEDIA} flow={L > sec(9.5) ? L + 20 : 0} dots={2} />
        {phone(sender, true, "", "", ap(sec(0.3)))}
        <g transform={`translate(${server.x} ${server.y}) scale(${ap(sec(0.8))})`}>
          <rect x={-170} y={-60} width={340} height={120} rx={22} fill="#FFFFFF" stroke={SIGNAL} strokeWidth={3} filter="url(#shadow3)" />
          <g transform="translate(-110 0)"><Glyph kind="server" color={SIGNAL} /></g>
          <text x={-60} y={-4} fontSize={32} fontWeight={800} fill={C.ink} fontFamily={FONT}>Uban 後端</text>
          <text x={-60} y={30} fontSize={22} fontWeight={600} fill={C.muted} fontFamily={FONT}>依輕重分級派送</text>
        </g>
        <g transform={`translate(${fcm.x} ${fcm.y}) scale(${ap(sec(8))})`}>
          <circle r={48} fill="#FFFFFF" stroke={MEDIA} strokeWidth={3} filter="url(#shadow3)" />
          <Glyph kind="cloud" color={MEDIA} />
          <text y={-66} textAnchor="middle" fontSize={24} fontWeight={700} fill={MEDIA} fontFamily={FONT}>FCM 推播</text>
        </g>
        {phone(open, true, "App 開著", "Socket.IO 即時通道", ap(sec(5)), L > sec(13) ? ripple(sec(13), false) : null)}
        {phone(closed, false, "App 關著", "推播喚醒", ap(sec(8.5)), L > sec(15.5) ? ripple(sec(15.5), true) : null)}
      </svg>
      <div style={{ position: "absolute", left: 120, top: 740, fontFamily: FONT, display: "flex", flexDirection: "column", gap: 18, opacity: dr(sec(12.5), sec(13.5)) }}>
        <div style={{ display: "flex", alignItems: "center", gap: 16 }}><span style={{ width: 24, height: 24, borderRadius: 12, border: `4px solid ${SIGNAL}` }} /><span style={{ fontSize: 32, fontWeight: 800, color: C.ink }}>一般關心</span><span style={{ fontSize: 26, color: C.muted, fontWeight: 600 }}>不蓋屏、不吵醒</span></div>
        <div style={{ display: "flex", alignItems: "center", gap: 16, opacity: dr(sec(15.5), sec(16.3)) }}><span style={{ width: 24, height: 24, borderRadius: 12, border: "6px solid #E0703F" }} /><span style={{ fontSize: 32, fontWeight: 800, color: C.ink }}>跌倒警報</span><span style={{ fontSize: 26, color: C.muted, fontWeight: 600 }}>高優先級，繞過勿擾</span></div>
      </div>
    </AbsoluteFill>
  );
};

export const Ch02: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: C.light, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 360, top: -200, width: 1200, height: 1200, borderRadius: "50%", background: "radial-gradient(circle, #E3F3EB 0%, rgba(227,243,235,0) 62%)" }} />
      <ArchAndDualTrack f={frame} />
      <AiEngine f={frame} />
      <Notify f={frame} />
      <BackendChips frame={frame} chips={CHIPS} />
      {SHOW_SUBS && <Subtitles frame={frame} subs={SUBS} />}
      <ChapterCard frame={frame} num="02" title="系統架構" />

      {/* 聲音：配樂低音量鋪底；線條畫完一聲「滴」；切換備援「咔」；工具爆開一串「啵」 */}
      <Audio src={staticFile("ad/audio/music.wav")} volume={(f) => interpolate(f, [0, 30, T.end - 40, T.end], [0, 0.22, 0.22, 0], clamp)} />
      <Sequence from={0} durationInFrames={sec(1.5)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.5} /></Sequence>
      {[sec(4.5), sec(5), sec(15), sec(19.5), sec(23.5), T.b + sec(6), T.b + sec(17)].map((at, i) => (
        <Sequence key={`d${i}`} from={at} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/tick.wav")} volume={0.5} /></Sequence>
      ))}
      <Sequence from={T.b + sec(17)} durationInFrames={sec(12)}><Audio src={staticFile("ad/audio/drone.wav")} volume={0.12} /></Sequence>
      <Sequence from={T.c + sec(9.5)} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/thud.wav")} volume={0.5} /></Sequence>
      {TOOLS.map((_, i) => (i % 3 === 0 ? <Sequence key={`p${i}`} from={T.c + sec(16) + i * 3} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/pop.wav")} volume={0.3} /></Sequence> : null))}
      <Sequence from={T.d + sec(13)} durationInFrames={sec(2)}><Audio src={staticFile("ad/audio/ding.wav")} volume={0.35} /></Sequence>
      <Sequence from={T.d + sec(15.5)} durationInFrames={sec(2)}><Audio src={staticFile("ad/audio/alert_real.wav")} volume={0.25} /></Sequence>
    </AbsoluteFill>
  );
};
