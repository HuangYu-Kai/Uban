// 共用元件：從 ChatFeature.tsx 的 3D 厚度手機與「元件飛出放大」抽出來的通用版，
// 螢幕內容改成可以放任何東西（實機錄影、截圖）。
import React from "react";
import { OffthreadVideo, Sequence, staticFile } from "remotion";
import { kf } from "./ChatFeature";

// 手機尺寸（場景座標）。螢幕比例 = 實機錄影 480:1068
export const SW = 392;
export const SH = 872;
export const BEZ = 13;
export const PW = SW + BEZ * 2;
export const PH = SH + BEZ * 2;
export const DEPTH = 44;
export const RADIUS = 66;
export const Z0 = DEPTH / 2 + 2;

// 一段實機錄影：at/to 是廣告時間軸的影格，from 是片內秒數，rate 是播放倍速
export type Seg = { at: number; to: number; src: string; from: number; rate?: number };

export const ClipView: React.FC<{ segs: Seg[] }> = ({ segs }) => (
  <>
    {segs.map((s, i) => (
      <Sequence key={i} from={s.at} durationInFrames={s.to - s.at} layout="none">
        <OffthreadVideo
          src={staticFile(`ad/clips/${s.src}.mp4`)}
          startFrom={Math.round(s.from * 30)}
          playbackRate={s.rate ?? 1}
          muted
          style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" }}
        />
      </Sequence>
    ))}
  </>
);

// 3D 舞台：原點在畫面上的 (cx, cy)
export const Stage: React.FC<{ perspective?: number; cx?: string; cy?: string; children: React.ReactNode }> = ({ perspective = 2300, cx = "50%", cy = "50%", children }) => (
  <div style={{ position: "absolute", inset: 0, perspective, perspectiveOrigin: `${cx} ${cy}` }}>
    <div style={{ position: "absolute", left: cx, top: cy, width: 0, height: 0, transformStyle: "preserve-3d" }}>{children}</div>
  </div>
);

export type Pose = { x: number; y: number; z?: number; ry: number; rx: number; rz: number; s?: number };

export const PhoneAt: React.FC<{ pose: Pose; children: React.ReactNode }> = ({ pose, children }) => (
  <div
    style={{
      position: "absolute",
      left: -PW / 2,
      top: -PH / 2,
      width: PW,
      height: PH,
      transformStyle: "preserve-3d",
      transform: `translate3d(${pose.x}px,${pose.y}px,${pose.z ?? 0}px) rotateY(${pose.ry}deg) rotateX(${pose.rx}deg) rotateZ(${pose.rz}deg) scale3d(${pose.s ?? 1},${pose.s ?? 1},${pose.s ?? 1})`,
    }}
  >
    {children}
  </div>
);

export const Phone3D: React.FC<{ frame: number; screen: React.ReactNode; dim?: number; children?: React.ReactNode }> = ({ frame, screen, dim = 0, children }) => {
  const slices = 22;
  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: PW, height: PH, transformStyle: "preserve-3d" }}>
      {/* 機身厚度：一層層堆疊的圓角板 */}
      {Array.from({ length: slices }).map((_, i) => {
        const z = -DEPTH / 2 + (i * DEPTH) / (slices - 1);
        const edge = Math.abs(i / (slices - 1) - 0.5) * 2;
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              inset: 0,
              borderRadius: RADIUS,
              transform: `translateZ(${z}px)`,
              background: `linear-gradient(120deg, ${edge > 0.8 ? "#9AA6A1" : "#C3CDC9"} 0%, #E9EFEC 38%, #A8B3AE 62%, #D5DDD9 100%)`,
            }}
          />
        );
      })}
      {/* 側邊按鍵 */}
      {[{ y: 190, h: 54 }, { y: 268, h: 90 }].map((b, i) => (
        <div key={i} style={{ position: "absolute", left: -DEPTH * 0.22, top: b.y, width: DEPTH * 0.44, height: b.h, borderRadius: 6, background: "linear-gradient(90deg,#8E9A95,#D8E0DC,#8E9A95)", transform: "translateX(-3px) rotateY(90deg)" }} />
      ))}
      <div style={{ position: "absolute", right: -DEPTH * 0.22, top: 300, width: DEPTH * 0.44, height: 120, borderRadius: 6, background: "linear-gradient(90deg,#8E9A95,#D8E0DC,#8E9A95)", transform: "translateX(3px) rotateY(90deg)" }} />
      {/* 背面 */}
      <div style={{ position: "absolute", inset: 0, borderRadius: RADIUS, transform: `translateZ(${-DEPTH / 2 - 1}px) rotateY(180deg)`, background: "linear-gradient(160deg,#DCE8E2,#B9CBC3)" }} />
      {/* 正面：黑邊框＋螢幕 */}
      <div style={{ position: "absolute", inset: 0, borderRadius: RADIUS, transform: `translateZ(${DEPTH / 2 + 0.5}px)`, background: "#0F1513", padding: BEZ, boxSizing: "border-box" }}>
        <div style={{ position: "relative", width: "100%", height: "100%", borderRadius: RADIUS - BEZ, overflow: "hidden", background: "#0B0F0E" }}>
          {screen}
          <div style={{ position: "absolute", inset: 0, background: "#0B0F0E", opacity: dim }} />
          {/* 玻璃反光 */}
          <div style={{ position: "absolute", inset: 0, background: `linear-gradient(115deg, rgba(255,255,255,0.14) 0%, rgba(255,255,255,0) ${30 + Math.sin(frame / 40) * 6}%)` }} />
        </div>
      </div>
      {children}
    </div>
  );
};

// 元件拉出放大：把螢幕上的一塊（rect，0..1 的比例座標）從手機裡拉到鏡頭前
export type PullKey = { f: number; dx?: number; dy?: number; z?: number; s?: number; face?: number; o?: number };
export const PullOut: React.FC<{
  frame: number;
  rect: { x: number; y: number; w: number; h: number };
  keys: PullKey[];
  pose: { ry: number; rx: number; rz: number };
  radius?: number;
  children: React.ReactNode;
}> = ({ frame, rect, keys, pose, radius = 22, children }) => {
  if (frame < keys[0].f || frame > keys[keys.length - 1].f) return null;
  const pick = (n: keyof Omit<PullKey, "f">, def: number) => kf(frame, keys.map((k) => [k.f, k[n] ?? def] as [number, number]));
  const w = rect.w * SW, h = rect.h * SH;
  const x = (rect.x + rect.w / 2 - 0.5) * SW + pick("dx", 0);
  const y = (rect.y + rect.h / 2 - 0.5) * SH + pick("dy", 0);
  const z = pick("z", Z0), s = pick("s", 1), face = pick("face", 0), o = pick("o", 1);
  const lift = Math.max(0, Math.min(1, (z - Z0) / 120));
  return (
    <div
      style={{
        position: "absolute",
        left: PW / 2 - w / 2,
        top: PH / 2 - h / 2,
        width: w,
        height: h,
        opacity: o,
        transform: `translate3d(${x}px,${y}px,${z}px) rotateZ(${-pose.rz * face}deg) rotateX(${-pose.rx * face}deg) rotateY(${-pose.ry * face}deg) scale(${s})`,
        borderRadius: radius,
        overflow: "hidden",
        boxShadow: `0 ${10 + lift * 30}px ${24 + lift * 50}px rgba(10,20,16,${0.2 + lift * 0.3}), 0 0 0 ${lift * 3}px rgba(127,211,176,${lift * 0.9})`,
      }}
    >
      <div style={{ position: "absolute", left: -rect.x * SW, top: -rect.y * SH, width: SW, height: SH }}>{children}</div>
    </div>
  );
};

// 手勢示意：在螢幕的 (nx, ny) 比例位置點一下
export const Tap: React.FC<{ frame: number; at: number; nx: number; ny: number }> = ({ frame, at, nx, ny }) => {
  const t = frame - at;
  if (t < -12 || t > 16) return null;
  const dot = t < 0 ? 1 + (-t / 12) * 0.5 : t < 3 ? 0.8 : 1;
  const ring = Math.max(0, t) / 16;
  return (
    <div style={{ position: "absolute", left: BEZ + nx * SW, top: BEZ + ny * SH, width: 0, height: 0, transform: `translateZ(${Z0 + 3}px)`, transformStyle: "preserve-3d" }}>
      <div style={{ position: "absolute", left: -60, top: -60, width: 120, height: 120, borderRadius: "50%", border: "5px solid rgba(255,255,255,0.9)", transform: `scale(${0.3 + ring * 1.1})`, opacity: t >= 0 ? 1 - ring : 0 }} />
      <div style={{ position: "absolute", left: -27, top: -27, width: 54, height: 54, borderRadius: "50%", background: "rgba(255,255,255,0.55)", border: "3px solid rgba(255,255,255,0.95)", transform: `scale(${dot})`, opacity: Math.min(1, (t + 12) / 5) * (t > 8 ? Math.max(0, 1 - (t - 8) / 8) : 1) }} />
    </div>
  );
};
