// 有實機錄影的章節共用：亮底背景、標題、實機錄影播放、待補錄佔位、飛行光點
import React from "react";
import { AbsoluteFill, Audio, OffthreadVideo, Sequence, interpolate, spring, staticFile } from "remotion";
import { COLORS as C, FONT, FPS, Kinetic, clamp, ease } from "./common";

// ---- 背景 ----
export const Glow: React.FC<{ x: number; y: number; o?: number; color?: string; r?: number }> = ({ x, y, o = 1, color = "#DDF1E8", r = 620 }) => (
  <div style={{ position: "absolute", left: x - r, top: y - r, width: r * 2, height: r * 2, borderRadius: "50%", background: `radial-gradient(circle, ${color} 0%, rgba(221,241,232,0) 64%)`, opacity: o }} />
);

export const Backdrop: React.FC<{ glowX?: number; glowY?: number }> = ({ glowX = 1190, glowY = 540 }) => (
  <AbsoluteFill style={{ background: C.light }}>
    <Glow x={glowX} y={glowY} r={700} />
  </AbsoluteFill>
);

// 場景可見度：進出各淡 fade 格
export const vis = (frame: number, a: number, b: number, fade = 10) =>
  Math.min(interpolate(frame, [a, a + fade], [0, 1], clamp), interpolate(frame, [b - fade, b], [1, 0], clamp));

// ---- 標題 ----
export const Eyebrow: React.FC<{ text: string; o?: number; dark?: boolean }> = ({ text, o = 1, dark }) => (
  <div style={{ display: "inline-block", padding: "8px 20px", borderRadius: 999, background: dark ? "rgba(127,211,176,0.16)" : "#DDF1E8", color: dark ? C.brandGlow : C.brandDeep, fontSize: 28, fontWeight: 800, letterSpacing: 2, opacity: o, whiteSpace: "nowrap" }}>
    {text}
  </div>
);

export const Headline: React.FC<{
  frame: number;
  start: number;
  end?: number;
  x: number;
  y: number;
  lines: string[];
  eyebrow?: string;
  size?: number;
  width?: number;
  center?: boolean;
  dark?: boolean;
  note?: string;
}> = ({ frame, start, end, x, y, lines, eyebrow, size = 72, width = 700, center, dark, note }) => {
  if (frame < start - 2 || (end !== undefined && frame > end)) return null;
  const out = end !== undefined ? interpolate(frame, [end - 8, end], [0, 1], { ...clamp, easing: ease }) : 0;
  const noteO = interpolate(frame, [start + 14 + lines.length * 9, start + 24 + lines.length * 9], [0, 1], clamp);
  return (
    <div style={{ position: "absolute", left: center ? x - width / 2 : x, top: y, width, fontFamily: FONT, opacity: 1 - out, transform: `translateY(${-out * 24}px)`, textAlign: center ? "center" : "left" }}>
      {eyebrow && <Eyebrow text={eyebrow} dark={dark} o={interpolate(frame, [start, start + 10], [0, 1], clamp)} />}
      <div style={{ marginTop: eyebrow ? 22 : 0 }}>
        {lines.map((line, i) => (
          <div key={i} style={{ lineHeight: 1.26 }}>
            <Kinetic text={line} local={frame - start - 4 - i * 9} size={size} color={dark ? C.cream : C.ink} center={center} stagger={1.8} />
          </div>
        ))}
      </div>
      {note && <div style={{ marginTop: 22, fontSize: 32, lineHeight: 1.5, color: dark ? C.creamDim : C.muted, fontWeight: 600, opacity: noteO, transform: `translateY(${(1 - noteO) * 12}px)` }}>{note}</div>}
    </div>
  );
};

// ---- 實機錄影 ----
// at/to：場景時間軸影格；from：片內秒數；rate：倍速（< 1 可當作停格用）
export type CSeg = { at: number; to: number; from: number; rate?: number };

export const DemoClip: React.FC<{ src: string; segs: CSeg[] }> = ({ src, segs }) => (
  <>
    {segs.map((s, i) => (
      <Sequence key={i} from={s.at} durationInFrames={s.to - s.at} layout="none">
        <OffthreadVideo
          src={staticFile(`demo/clips/${src}.mp4`)}
          startFrom={Math.round(s.from * FPS)}
          playbackRate={s.rate ?? 1}
          muted
          style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" }}
        />
      </Sequence>
    ))}
  </>
);

// 錄影裡的原聲（小嘎 TTS、提醒音）：只在指定區段播放
export const ClipSound: React.FC<{ src: string; at: number; from: number; dur: number; volume?: number }> = ({ src, at, from, dur, volume = 1 }) => (
  <Sequence from={at} durationInFrames={dur}>
    <Audio src={staticFile(`demo/clips/${src}.mp4`)} startFrom={Math.round(from * FPS)} volume={(f) => interpolate(f, [0, 4, dur - 6, dur], [0, volume, volume, 0], clamp)} />
  </Sequence>
);

// ---- 待補錄佔位：放在手機螢幕裡 ----
export const Placeholder: React.FC<{ frame: number; title: string; lines?: string[] }> = ({ frame, title, lines = [] }) => (
  <AbsoluteFill style={{ background: "#141B19", fontFamily: FONT, alignItems: "center", justifyContent: "center", padding: 34, boxSizing: "border-box" }}>
    <div style={{ position: "absolute", inset: 22, borderRadius: 34, border: "3px dashed rgba(127,211,176,0.45)", backgroundImage: "repeating-linear-gradient(135deg, rgba(127,211,176,0.05) 0 18px, rgba(0,0,0,0) 18px 36px)", backgroundPosition: `${frame * 0.6}px 0` }} />
    <div style={{ position: "relative", textAlign: "center" }}>
      <div style={{ display: "inline-block", padding: "6px 18px", borderRadius: 999, background: "rgba(242,184,128,0.18)", color: C.warm, fontSize: 24, fontWeight: 800, letterSpacing: 2 }}>待補錄</div>
      <div style={{ marginTop: 22, fontSize: 34, fontWeight: 800, color: C.cream, lineHeight: 1.35 }}>{title}</div>
      {lines.map((l, i) => (
        <div key={i} style={{ marginTop: i === 0 ? 18 : 8, fontSize: 24, color: C.creamDim, lineHeight: 1.45 }}>{l}</div>
      ))}
    </div>
  </AbsoluteFill>
);

// ---- 飛行光點：沿弧線從 (x0,y0) 飛到 (x1,y1)，lift 是弧高 ----
export type Arc = { x0: number; y0: number; x1: number; y1: number; lift: number };
export const FlyDot: React.FC<{ frame: number; at: number; dur: number; arc: Arc; color?: string; size?: number }> = ({ frame, at, dur, arc, color = C.brand, size = 34 }) => {
  if (frame < at || frame > at + dur + 8) return null;
  const pt = (t: number) => {
    const e = ease(Math.max(0, Math.min(1, t)));
    return { x: arc.x0 + (arc.x1 - arc.x0) * e, y: arc.y0 + (arc.y1 - arc.y0) * e - Math.sin(Math.PI * e) * arc.lift };
  };
  return (
    <>
      {[0, 1, 2, 3, 4].map((i) => {
        const t = (frame - at - i * 1.6) / dur;
        if (t < 0) return null;
        const { x, y } = pt(t);
        const s = 1 - i * 0.17;
        const o = (i === 0 ? 1 : 0.45 * s) * interpolate(frame, [at + dur, at + dur + 8], [1, 0], clamp);
        return <div key={i} style={{ position: "absolute", left: x - size / 2, top: y - size / 2, width: size, height: size, borderRadius: "50%", background: color, opacity: o, transform: `scale(${s})`, boxShadow: i === 0 ? `0 0 30px 10px ${color}88` : undefined }} />;
      })}
    </>
  );
};

// 一般進場彈性
export const pop = (frame: number, at: number, damping = 16) => spring({ frame: frame - at, fps: FPS, config: { damping } });

// 小字卡（畫面上的浮動標籤）
export const Tag: React.FC<{ frame: number; at: number; x: number; y: number; text: string; dot?: string; end?: number }> = ({ frame, at, x, y, text, dot = C.brand, end }) => {
  const t = pop(frame, at, 18);
  const out = end !== undefined ? interpolate(frame, [end - 8, end], [0, 1], clamp) : 0;
  if (frame < at) return null;
  return (
    <div style={{ position: "absolute", left: x, top: y, padding: "12px 24px", borderRadius: 999, background: "#FFFFFF", color: C.ink, fontFamily: FONT, fontSize: 30, fontWeight: 700, boxShadow: "0 10px 26px rgba(28,41,37,0.10)", opacity: t * (1 - out), transform: `translateY(${(1 - t) * 20}px)`, display: "flex", alignItems: "center", gap: 12, whiteSpace: "nowrap" }}>
      <span style={{ width: 14, height: 14, borderRadius: "50%", background: dot }} />
      {text}
    </div>
  );
};
