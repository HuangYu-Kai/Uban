// 展示影片（長版）共用元件：章節轉場、字幕、後端事件字卡、品牌標誌
import React from "react";
import { AbsoluteFill, interpolate, spring, Easing } from "remotion";

export const FPS = 30;
export const sec = (s: number) => Math.round(s * FPS);

export const COLORS = {
  brand: "#59B294",
  brandDeep: "#3E957A",
  brandGlow: "#7FD3B0",
  light: "#F3F7F5",
  ink: "#1C2925",
  muted: "#5D6B66",
  charcoal: "#2A2824",
  cream: "#FFF6E8",
  creamDim: "rgba(255,246,232,0.72)",
  warm: "#F2B880",
};
export const FONT = '"Microsoft JhengHei UI","Microsoft JhengHei","Noto Sans TC","PingFang TC",sans-serif';
export const MONO = '"Cascadia Mono","Consolas",monospace';
export const ease = Easing.bezier(0.22, 1, 0.36, 1);
export const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

// 品牌愛心路徑（中心在 0,0，寬約 68）
export const HEART = "M0 27 C-26 9 -34 -5 -24 -17 C-14 -27 -2 -21 0 -11 C2 -21 14 -27 24 -17 C34 -5 26 9 0 27 Z";

// Uban 圖示：綠色圓角方塊＋愛心人形
export const HeartMark: React.FC<{ size: number; shadow?: boolean }> = ({ size, shadow = true }) => (
  <div style={{ width: size, height: size, borderRadius: size * 0.3, background: "linear-gradient(180deg,#5CBB9B,#4DAD88)", display: "grid", placeItems: "center", boxShadow: shadow ? "0 18px 40px rgba(77,173,136,0.35)" : undefined }}>
    <svg viewBox="0 0 64 64" style={{ width: size * 0.64, height: size * 0.64 }}>
      <circle cx="32" cy="15" r="9" fill="#D1EEE7" />
      <path d="M32 54C20 46 12 38 12 30a10 10 0 0 1 20-3 10 10 0 0 1 20 3c0 8-8 16-20 24z" fill="none" stroke="#D1EEE7" strokeWidth="5" strokeLinejoin="round" />
      <path d="M17 37l15-10" stroke="#D1EEE7" strokeWidth="5" strokeLinecap="round" />
    </svg>
  </div>
);

// 逐字彈入
export const Kinetic: React.FC<{ text: string; local: number; size: number; color: string; weight?: number; stagger?: number; center?: boolean }> = ({ text, local, size, color, weight = 800, stagger = 2.5, center }) => (
  <div style={{ display: "flex", flexWrap: "wrap", justifyContent: center ? "center" : "flex-start" }}>
    {[...text].map((ch, i) => {
      const t = spring({ frame: local - i * stagger, fps: FPS, config: { damping: 15, mass: 0.7 } });
      return (
        <span key={i} style={{ display: "inline-block", fontSize: size, fontWeight: weight, color, opacity: t, transform: `translateY(${(1 - t) * 0.45 * size}px)`, whiteSpace: "pre" }}>
          {ch}
        </span>
      );
    })}
  </div>
);

// 章節轉場：愛心從中央擴大成品牌綠，帶出章節編號與標題，最後以圓形揭開下一個畫面
// 全長 CHAPTER_CARD 影格；放在 <Sequence> 裡、蓋在章節第一個鏡頭上方
export const CHAPTER_CARD = 50;
export const ChapterCard: React.FC<{ frame: number; num: string; title: string; dark?: boolean }> = ({ frame, num, title }) => {
  if (frame < 0 || frame > CHAPTER_CARD) return null;
  const grow = interpolate(frame, [0, 14], [0, 150], { ...clamp, easing: Easing.in(Easing.cubic) });
  const reveal = interpolate(frame, [36, CHAPTER_CARD], [0, 1], { ...clamp, easing: Easing.in(Easing.cubic) });
  const textO = interpolate(frame, [10, 16, 34, 40], [0, 1, 1, 0], clamp);
  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
        <defs>
          <mask id={`chap-mask-${num}`}>
            <rect width={1920} height={1080} fill="white" />
            <circle cx={960} cy={540} r={reveal * 1150} fill="black" />
          </mask>
        </defs>
        <g mask={`url(#chap-mask-${num})`}>
          <path d={HEART} fill={COLORS.brand} transform={`translate(960 540) scale(${grow})`} />
        </g>
      </svg>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", fontFamily: FONT, opacity: textO, transform: `scale(${1 + reveal * 0.15})` }}>
        <div style={{ fontFamily: MONO, fontSize: 40, letterSpacing: 10, color: "rgba(255,255,255,0.8)", fontWeight: 700 }}>{num}</div>
        <Kinetic text={title} local={frame - 12} size={110} color="#FFFFFF" center stagger={1.5} />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

// 字幕：畫面下方、白字黑框（沿用校方規定的字幕樣式）
export type Sub = { from: number; to: number; text: string };
export const Subtitles: React.FC<{ frame: number; subs: Sub[] }> = ({ frame, subs }) => {
  const s = subs.find((x) => frame >= x.from && frame < x.to);
  if (!s) return null;
  const o = Math.min(interpolate(frame, [s.from, s.from + 5], [0, 1], clamp), interpolate(frame, [s.to - 5, s.to], [1, 0], clamp));
  return (
    <div style={{ position: "absolute", left: 0, right: 0, bottom: 46, textAlign: "center", fontFamily: FONT, fontSize: 44, fontWeight: 700, color: "#FFFFFF", opacity: o, WebkitTextStroke: "8px #111", paintOrder: "stroke fill", letterSpacing: 1 }}>
      {s.text}
    </div>
  );
};

// 後端事件字卡：畫面右下角，顯示這一刻後端在做什麼
export type Chip = { from: number; to: number; text: string };
export const BackendChips: React.FC<{ frame: number; chips: Chip[]; dark?: boolean }> = ({ frame, chips, dark }) => {
  const active = chips.filter((c) => frame >= c.from && frame < c.to);
  return (
    <div style={{ position: "absolute", right: 48, bottom: 140, display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 10 }}>
      {active.map((c, i) => {
        const t = spring({ frame: frame - c.from, fps: FPS, config: { damping: 18 } });
        const out = interpolate(frame, [c.to - 8, c.to], [0, 1], clamp);
        return (
          <div key={i} style={{ fontFamily: MONO, fontSize: 24, padding: "8px 16px", borderRadius: 10, background: dark ? "rgba(15,21,19,0.78)" : "rgba(255,255,255,0.9)", color: dark ? COLORS.brandGlow : COLORS.brandDeep, border: `1.5px solid ${dark ? "rgba(127,211,176,0.5)" : "rgba(62,149,122,0.35)"}`, opacity: t * (1 - out), transform: `translateX(${(1 - t) * 30}px)`, whiteSpace: "nowrap", display: "flex", gap: 10, alignItems: "center" }}>
            <span style={{ width: 9, height: 9, borderRadius: "50%", background: dark ? COLORS.brandGlow : COLORS.brand }} />
            {c.text}
          </div>
        );
      })}
    </div>
  );
};
