import React from "react";
import { AbsoluteFill, Audio, Sequence, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig, Easing } from "remotion";

// ================= 可直接修改的內容 =================
export const PAIN_FPS = 30;
export const PAIN_FRAMES = 750; // 25 秒（分鏡 00:20–00:45）
const SHOW_SUBS = true; // 顯示旁白字幕（對時用；正式版可關掉改用配音）
const BG = "#2A2824"; // 背景純色（暖炭灰）

const C = { cream: "#FFF6E8", creamDim: "rgba(255,246,232,0.72)", brand: "#7FD3B0", warm: "#F2B880", shade: "rgba(32,30,26,0.55)" };
const FONT = '"Microsoft JhengHei UI","Microsoft JhengHei","Noto Sans TC",sans-serif';

// 三張痛點字卡：開始影格、結束影格、主標、副標、鋼琴音
const CARDS = [
  { from: 45, to: 195, no: "01", title: "不會用手機", sub: "密密麻麻的按鈕，看不懂也不敢亂按", icon: "phone", note: "pain/g4.wav" },
  { from: 195, to: 345, no: "02", title: "出事沒人知道", sub: "跌倒、迷路，家人往往最後才知道", icon: "house", note: "pain/a4.wav" },
  { from: 345, to: 495, no: "03", title: "想關心，卻不知道聊什麼", sub: "電話接通了，只剩一句「有吃飯嗎？」", icon: "chat", note: "pain/e4.wav" },
] as const;
const RECAP = { from: 495, to: 585 };
const BRIDGE = { from: 585, title: "連結兩代的橋", sub: "不是另一個監視工具" };

// 旁白字幕（依分鏡表旁白切段）
const SUBS = [
  { from: 50, to: 190, text: "長輩不會用手機、" },
  { from: 200, to: 340, text: "跌倒沒人知道、" },
  { from: 350, to: 490, text: "子女想關心卻不知道從哪裡開始。" },
  { from: 505, to: 600, text: "我們想做的，不是另一個監視工具，" },
  { from: 610, to: 745, text: "而是一座連結兩代的橋。" },
];
// ===================================================

const ease = Easing.bezier(0.22, 1, 0.36, 1);
const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

// 線條描繪：progress 0→1
const Draw: React.FC<{ d: string; p: number; w?: number; color?: string; len?: number }> = ({ d, p, w = 5, color = C.cream, len = 1000 }) => (
  <path d={d} fill="none" stroke={color} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round" strokeDasharray={len} strokeDashoffset={len * (1 - p)} />
);

const Icon: React.FC<{ kind: string; local: number }> = ({ kind, local }) => {
  const p = (a: number, b: number) => interpolate(local, [a, b], [0, 1], { ...clamp, easing: ease });
  if (kind === "phone") {
    // 手機＋一堆小方塊＋浮出的問號
    const q = spring({ frame: local - 40, fps: 30, config: { damping: 9 } });
    return (
      <svg viewBox="0 0 240 240" width={240} height={240}>
        <Draw d="M78 30 h84 a16 16 0 0 1 16 16 v148 a16 16 0 0 1 -16 16 h-84 a16 16 0 0 1 -16 -16 v-148 a16 16 0 0 1 16 -16 z" p={p(0, 30)} />
        {Array.from({ length: 12 }).map((_, i) => {
          const x = 84 + (i % 3) * 26, y = 58 + Math.floor(i / 3) * 30;
          const s = spring({ frame: local - 14 - i * 1.5, fps: 30, config: { damping: 14 } });
          return <rect key={i} x={x} y={y} width={18} height={18} rx={5} fill={C.creamDim} opacity={s} transform={`translate(${9 * (1 - s)} ${9 * (1 - s)}) scale(1)`} />;
        })}
        <g transform={`translate(176 52) scale(${q})`}>
          <circle r={30} fill={C.warm} />
          <text x={0} y={13} textAnchor="middle" fontSize={40} fontWeight={800} fill="#3A2A20" fontFamily={FONT}>?</text>
        </g>
      </svg>
    );
  }
  if (kind === "house") {
    // 房子、亮著的窗、飛快轉動的時鐘
    const spin = Math.max(0, local - 30) * 14;
    const glow = 0.55 + Math.sin(local / 8) * 0.25;
    return (
      <svg viewBox="0 0 240 240" width={240} height={240}>
        <Draw d="M40 118 L120 50 L200 118" p={p(0, 22)} />
        <Draw d="M62 104 V200 H178 V104" p={p(8, 34)} />
        <rect x={98} y={128} width={44} height={40} rx={6} fill={C.warm} opacity={p(20, 34) * glow} />
        <g transform="translate(186 186)" opacity={p(26, 40)}>
          <circle r={34} fill="rgba(32,30,26,0.6)" stroke={C.cream} strokeWidth={5} />
          <line x1={0} y1={0} x2={0} y2={-22} stroke={C.cream} strokeWidth={5} strokeLinecap="round" transform={`rotate(${spin})`} />
          <line x1={0} y1={0} x2={14} y2={0} stroke={C.cream} strokeWidth={5} strokeLinecap="round" transform={`rotate(${spin / 12})`} />
        </g>
      </svg>
    );
  }
  // chat：兩個泡泡，一個只有「…」
  const dots = Math.floor(local / 8) % 4;
  return (
    <svg viewBox="0 0 240 240" width={240} height={240}>
      <Draw d="M30 50 h110 a18 18 0 0 1 18 18 v40 a18 18 0 0 1 -18 18 h-74 l-22 18 v-18 h-14 a18 18 0 0 1 -18 -18 v-40 a18 18 0 0 1 18 -18 z" p={p(0, 28)} />
      <text x={85} y={98} textAnchor="middle" fontSize={26} fontWeight={700} fill={C.cream} fontFamily={FONT} opacity={p(20, 30)}>有吃飯嗎？</text>
      <Draw d="M100 140 h110 a18 18 0 0 1 18 18 v36 a18 18 0 0 1 -18 18 h-14 v16 l-20 -16 h-76 a18 18 0 0 1 -18 -18 v-36 a18 18 0 0 1 18 -18 z" p={p(18, 46)} color={C.creamDim} />
      {[0, 1, 2].map((i) => (
        <circle key={i} cx={135 + i * 22} cy={176} r={6} fill={C.cream} opacity={local > 46 && i < dots ? 0.9 : 0.2} />
      ))}
    </svg>
  );
};

const Kinetic: React.FC<{ text: string; local: number; size: number; color: string; weight?: number; stagger?: number }> = ({ text, local, size, color, weight = 800, stagger = 3 }) => (
  <div style={{ display: "flex", flexWrap: "wrap", justifyContent: "center" }}>
    {[...text].map((ch, i) => {
      const t = spring({ frame: local - i * stagger, fps: 30, config: { damping: 15, mass: 0.7 } });
      return (
        <span key={i} style={{ display: "inline-block", fontSize: size, fontWeight: weight, color, opacity: t, transform: `translateY(${(1 - t) * 50}px)`, filter: `blur(${(1 - t) * 6}px)`, whiteSpace: "pre" }}>
          {ch}
        </span>
      );
    })}
  </div>
);

const Card: React.FC<{ idx: number; frame: number }> = ({ idx, frame }) => {
  const c = CARDS[idx];
  const local = frame - c.from;
  const dur = c.to - c.from;
  if (local < 0 || local > dur) return null;
  const out = interpolate(local, [dur - 20, dur], [0, 1], { ...clamp, easing: ease });
  const iconIn = spring({ frame: local, fps: 30, config: { damping: 18 } });
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", fontFamily: FONT, opacity: 1 - out, transform: `translateY(${-out * 80}px)` }}>
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 26 }}>
        <div style={{ opacity: iconIn, transform: `scale(${0.85 + iconIn * 0.15})` }}>
          <Icon kind={c.icon} local={local} />
        </div>
        <div style={{ fontSize: 30, letterSpacing: 8, color: C.brand, fontWeight: 700, opacity: interpolate(local, [6, 18], [0, 1], clamp) }}>痛點 {c.no}</div>
        <Kinetic text={c.title} local={local - 10} size={120} color={C.cream} />
        <div style={{ fontSize: 40, color: C.creamDim, fontWeight: 500, opacity: interpolate(local, [40, 58], [0, 1], clamp), transform: `translateY(${interpolate(local, [40, 58], [16, 0], { ...clamp, easing: ease })}px)` }}>{c.sub}</div>
      </div>
    </AbsoluteFill>
  );
};

// 三張卡縮小排成一列回顧
const Recap: React.FC<{ frame: number }> = ({ frame }) => {
  const local = frame - RECAP.from;
  if (local < 0 || frame > BRIDGE.from + 20) return null;
  const out = interpolate(frame, [BRIDGE.from - 6, BRIDGE.from + 16], [0, 1], { ...clamp, easing: ease });
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", fontFamily: FONT }}>
      <div style={{ display: "flex", gap: 60 }}>
        {CARDS.map((c, i) => {
          const t = spring({ frame: local - i * 7, fps: 30, config: { damping: 16 } });
          // 往中間收攏後淡出
          const gather = out * (1 - i) * 320;
          return (
            <div key={i} style={{ width: 420, display: "flex", flexDirection: "column", alignItems: "center", gap: 14, opacity: t * (1 - out), transform: `translate(${gather}px, ${(1 - t) * 40}px) scale(${1 - out * 0.4})` }}>
              <div style={{ transform: "scale(0.62)", height: 150, display: "flex", alignItems: "center" }}><Icon kind={c.icon} local={120} /></div>
              <div style={{ fontSize: 42, fontWeight: 800, color: C.cream, textAlign: "center", whiteSpace: "nowrap" }}>{c.title}</div>
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

// 兩個人物之間畫出一座橋
const Bridge: React.FC<{ frame: number }> = ({ frame }) => {
  const local = frame - BRIDGE.from;
  if (local < 0) return null;
  const pin = spring({ frame: local, fps: 30, config: { damping: 16 } });
  const arc = interpolate(local, [14, 60], [0, 1], { ...clamp, easing: ease });
  const heart = spring({ frame: local - 58, fps: 30, config: { damping: 8 } });
  const glow = interpolate(local, [58, 90], [0, 1], clamp);
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", fontFamily: FONT }}>
      <svg viewBox="0 0 1200 420" width={1200} height={420} style={{ overflow: "visible" }}>
        <defs>
          <filter id="glow"><feGaussianBlur stdDeviation="8" /></filter>
        </defs>
        {/* 長輩（髮髻） */}
        <g transform={`translate(170 300) scale(${pin})`} opacity={pin}>
          <circle cx={0} cy={-120} r={46} fill="none" stroke={C.cream} strokeWidth={8} />
          <circle cx={0} cy={-178} r={18} fill="none" stroke={C.cream} strokeWidth={8} />
          <path d="M-70 40 Q-70 -50 0 -54 Q70 -50 70 40" fill="none" stroke={C.cream} strokeWidth={8} strokeLinecap="round" />
        </g>
        {/* 家人 */}
        <g transform={`translate(1030 300) scale(${pin})`} opacity={pin}>
          <circle cx={0} cy={-128} r={46} fill="none" stroke={C.cream} strokeWidth={8} />
          <path d="M-44 -150 Q0 -196 44 -150" fill="none" stroke={C.cream} strokeWidth={8} strokeLinecap="round" />
          <path d="M-70 40 Q-70 -56 0 -60 Q70 -56 70 40" fill="none" stroke={C.cream} strokeWidth={8} strokeLinecap="round" />
        </g>
        {/* 橋 */}
        <path d="M260 250 Q600 -20 940 250" fill="none" stroke={C.brand} strokeWidth={22} strokeLinecap="round" opacity={0.5 * glow} filter="url(#glow)" />
        <Draw d="M260 250 Q600 -20 940 250" p={arc} w={10} color={C.brand} len={900} />
        <g transform={`translate(600 115) scale(${heart})`}>
          <path d="M0 22 C-26 4 -34 -10 -24 -22 C-14 -32 -2 -26 0 -16 C2 -26 14 -32 24 -22 C34 -10 26 4 0 22 Z" fill={C.warm} />
        </g>
      </svg>
      <div style={{ marginTop: 10, fontSize: 36, color: C.creamDim, fontWeight: 500, opacity: interpolate(local, [24, 40], [0, 1], clamp), textDecoration: "line-through", textDecorationColor: "rgba(255,246,232,0.6)" }}>{BRIDGE.sub}</div>
      <div style={{ marginTop: 6 }}>
        <Kinetic text={BRIDGE.title} local={local - 60} size={96} color={C.cream} stagger={4} />
      </div>
    </AbsoluteFill>
  );
};

export const PainPoints: React.FC = () => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const sub = SUBS.find((s) => frame >= s.from && frame < s.to);
  const subO = sub ? Math.min(interpolate(frame, [sub.from, sub.from + 8], [0, 1], clamp), interpolate(frame, [sub.to - 8, sub.to], [1, 0], clamp)) : 0;
  return (
    <AbsoluteFill style={{ background: BG, overflow: "hidden" }}>

      {CARDS.map((_, i) => <Card key={i} idx={i} frame={frame} />)}
      <Recap frame={frame} />
      <Bridge frame={frame} />

      {SHOW_SUBS && sub && (
        <div style={{ position: "absolute", left: 0, right: 0, bottom: 64, textAlign: "center", fontFamily: FONT, fontSize: 36, color: "#fff", opacity: subO, textShadow: "0 2px 10px rgba(0,0,0,0.6)" }}>{sub.text}</div>
      )}

      {/* 鋼琴音：每張字卡一個音，橋出現時一個和弦 */}
      {CARDS.map((c) => (
        <Sequence key={c.no} from={c.from + 10} durationInFrames={105}>
          <Audio src={staticFile(c.note)} volume={0.9} />
        </Sequence>
      ))}
      <Sequence from={BRIDGE.from + 58} durationInFrames={170}>
        <Audio src={staticFile("pain/chord.wav")} volume={0.8} />
      </Sequence>
    </AbsoluteFill>
  );
};
