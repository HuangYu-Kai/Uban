import React from "react";
import {
  AbsoluteFill,
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
  Easing,
} from "remotion";

// ================= 可直接修改的內容 =================
export const FPS = 30;
const SEG = 90; // 每段 3 秒

const COLORS = {
  bg: "#F5F8F6",
  glow: "#DDF1E8",
  ink: "#1C2925",
  muted: "#5D6B66",
  brand: "#59B294",
  brandDeep: "#3E957A",
  phone: "#1C2925",
};

const FONT = '"Microsoft JhengHei UI","Microsoft JhengHei","Noto Sans TC","PingFang TC",sans-serif';

// 每段：手機螢幕、手機在左或右、上方小標、主標題（\n 換行）
const FEATURES = [
  { screen: "elder_home.png", side: "right", eyebrow: "長輩端", title: "大字、大按鈕\n一眼看完今天" },
  { screen: "elder_checkin.png", side: "right", eyebrow: "提醒與打卡", title: "按一下打卡\n家人即時知道" },
  { screen: "family_notify.png", side: "left", eyebrow: "家屬端", title: "打卡、跌倒、迷路\n第一時間通知" },
  { screen: "elder_chat.png", side: "right", eyebrow: "AI 夥伴小嘎", title: "會聊天、會提醒\n也會幫忙找家人" },
] as const;

const OUTRO = {
  screen: "elder_home.png",
  wordmark: "Uban",
  tagline: "讓每一天的平安，都有人知道",
  button: "下載 App",
};
// ===================================================

export const TOTAL_FRAMES = SEG * (FEATURES.length + 1) + 30;
const OUTRO_START = SEG * FEATURES.length;

// 手機在左／右時的位置與傾角
const POSE = {
  right: { x: 1270, rotY: -20, rotX: 6, rotZ: 2 },
  left: { x: 650, rotY: 20, rotX: 6, rotZ: -2 },
  outro: { x: 640, rotY: 18, rotX: 5, rotZ: -3 },
};

const ease = Easing.bezier(0.22, 1, 0.36, 1);

function poseAt(frame: number) {
  const keys: { f: number; p: { x: number; rotY: number; rotX: number; rotZ: number } }[] = [];
  FEATURES.forEach((s, i) => keys.push({ f: i * SEG, p: POSE[s.side] }));
  keys.push({ f: OUTRO_START, p: POSE.outro });
  let p = keys[0].p;
  for (let i = 1; i < keys.length; i++) {
    const a = keys[i - 1].p;
    const b = keys[i].p;
    const t = interpolate(frame, [keys[i].f - 14, keys[i].f + 10], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
      easing: ease,
    });
    if (t > 0) p = { x: a.x + (b.x - a.x) * t, rotY: a.rotY + (b.rotY - a.rotY) * t, rotX: a.rotX + (b.rotX - a.rotX) * t, rotZ: a.rotZ + (b.rotZ - a.rotZ) * t };
  }
  return p;
}

const PHONE_W = 380;
const PHONE_H = Math.round(PHONE_W * (2472 / 1110)) + 28;

const Phone: React.FC<{ frame: number; fps: number }> = ({ frame, fps }) => {
  const enter = spring({ frame, fps, config: { damping: 18, mass: 0.9 } });
  const p = poseAt(frame);
  const floatY = Math.sin(frame / 28) * 8;
  const screens = [...FEATURES.map((f) => f.screen), OUTRO.screen];
  return (
    <div
      style={{
        position: "absolute",
        left: p.x - PHONE_W / 2,
        top: 540 - PHONE_H / 2 + floatY + (1 - enter) * 500,
        width: PHONE_W,
        height: PHONE_H,
        opacity: enter,
        transform: `perspective(2200px) rotateY(${p.rotY + (1 - enter) * -30}deg) rotateX(${p.rotX}deg) rotateZ(${p.rotZ}deg)`,
        transformStyle: "preserve-3d",
      }}
    >
      {/* 陰影 */}
      <div style={{ position: "absolute", inset: 0, borderRadius: 64, boxShadow: "0 60px 120px rgba(28,41,37,0.28), 0 18px 40px rgba(28,41,37,0.18)" }} />
      {/* 機身 */}
      <div style={{ position: "absolute", inset: 0, borderRadius: 64, background: COLORS.phone, padding: 14 }}>
        <div style={{ position: "relative", width: "100%", height: "100%", borderRadius: 52, overflow: "hidden", background: "#fff" }}>
          {screens.map((src, i) => {
            const start = i * SEG;
            const inT = i === 0 ? 1 : interpolate(frame, [start - 8, start + 10], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease });
            const outT = i === screens.length - 1 ? 0 : interpolate(frame, [start + SEG - 8, start + SEG + 10], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease });
            if (inT <= 0 || outT >= 1) return null;
            return (
              <Img
                key={i}
                src={staticFile(src)}
                style={{
                  position: "absolute",
                  inset: 0,
                  width: "100%",
                  height: "100%",
                  objectFit: "cover",
                  transform: `translateY(${(1 - inT) * 60 - outT * 60}px) scale(${1 - outT * 0.04})`,
                  opacity: Math.min(inT, 1 - outT),
                }}
              />
            );
          })}
        </div>
      </div>
      {/* 光澤 */}
      <div style={{ position: "absolute", inset: 0, borderRadius: 64, background: "linear-gradient(115deg, rgba(255,255,255,0.18) 0%, rgba(255,255,255,0) 35%)", pointerEvents: "none" }} />
    </div>
  );
};

// 文字逐行由下往上滑入，段落結束往上淡出
const FeatureText: React.FC<{ frame: number; fps: number; idx: number }> = ({ frame, fps, idx }) => {
  const s = FEATURES[idx];
  const local = frame - idx * SEG;
  if (local < -10 || local > SEG + 10) return null;
  const out = interpolate(local, [SEG - 12, SEG + 4], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease });
  const textX = s.side === "right" ? 220 : 1110;
  const lines = s.title.split("\n");
  const eyebrowIn = spring({ frame: local - 4, fps, config: { damping: 20 } });
  return (
    <div style={{ position: "absolute", left: textX, top: 360, width: 640, fontFamily: FONT, opacity: 1 - out, transform: `translateY(${-out * 30}px)` }}>
      <div
        style={{
          display: "inline-block",
          padding: "8px 18px",
          borderRadius: 999,
          background: COLORS.glow,
          color: COLORS.brandDeep,
          fontSize: 26,
          fontWeight: 700,
          letterSpacing: 2,
          opacity: eyebrowIn,
          transform: `translateY(${(1 - eyebrowIn) * 20}px)`,
        }}
      >
        {s.eyebrow}
      </div>
      <div style={{ marginTop: 26 }}>
        {lines.map((line, li) => {
          const t = spring({ frame: local - 8 - li * 6, fps, config: { damping: 18 } });
          return (
            <div key={li} style={{ overflow: "hidden", lineHeight: 1.22 }}>
              <div style={{ fontSize: 76, fontWeight: 800, color: COLORS.ink, transform: `translateY(${(1 - t) * 100}%)` }}>{line}</div>
            </div>
          );
        })}
      </div>
      {/* 進度點 */}
      <div style={{ display: "flex", gap: 10, marginTop: 40 }}>
        {FEATURES.map((_, i) => (
          <div key={i} style={{ width: i === idx ? 44 : 12, height: 12, borderRadius: 6, background: i === idx ? COLORS.brand : "#CBD8D2" }} />
        ))}
      </div>
    </div>
  );
};

const HeartMark: React.FC<{ size: number }> = ({ size }) => (
  <div style={{ width: size, height: size, borderRadius: size * 0.3, background: "linear-gradient(180deg,#5CBB9B,#4DAD88)", display: "grid", placeItems: "center", boxShadow: "0 18px 40px rgba(77,173,136,0.35)" }}>
    <svg viewBox="0 0 64 64" style={{ width: size * 0.64, height: size * 0.64 }}>
      <circle cx="32" cy="15" r="9" fill="#D1EEE7" />
      <path d="M32 54C20 46 12 38 12 30a10 10 0 0 1 20-3 10 10 0 0 1 20 3c0 8-8 16-20 24z" fill="none" stroke="#D1EEE7" strokeWidth="5" strokeLinejoin="round" />
      <path d="M17 37l15-10" stroke="#D1EEE7" strokeWidth="5" strokeLinecap="round" />
    </svg>
  </div>
);

const Outro: React.FC<{ frame: number; fps: number }> = ({ frame, fps }) => {
  const local = frame - OUTRO_START;
  if (local < 0) return null;
  const mark = spring({ frame: local - 6, fps, config: { damping: 12, mass: 0.8 } });
  const word = spring({ frame: local - 14, fps, config: { damping: 18 } });
  const tag = spring({ frame: local - 24, fps, config: { damping: 20 } });
  const btn = spring({ frame: local - 34, fps, config: { damping: 16 } });
  // 游標：從右下進來，在 local=82 點擊按鈕
  const CLICK = 82;
  const cur = interpolate(local, [50, CLICK - 4], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease });
  const press = interpolate(local, [CLICK - 2, CLICK + 2, CLICK + 8], [1, 0.94, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const ripple = interpolate(local, [CLICK, CLICK + 18], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const BTN = { x: 1110, y: 690, w: 300, h: 84 };
  const cx = interpolate(cur, [0, 1], [1700, BTN.x + BTN.w * 0.62]);
  const cy = interpolate(cur, [0, 1], [1040, BTN.y + BTN.h * 0.55]);
  return (
    <>
      <div style={{ position: "absolute", left: 1110, top: 330, fontFamily: FONT }}>
        <div style={{ display: "flex", alignItems: "center", gap: 34 }}>
          <div style={{ transform: `scale(${mark}) rotate(${(1 - mark) * -20}deg)` }}>
            <HeartMark size={150} />
          </div>
          <div style={{ fontSize: 150, fontWeight: 800, letterSpacing: -4, color: COLORS.ink, fontFamily: '"Segoe UI",' + FONT, opacity: word, transform: `translateX(${(1 - word) * -40}px)` }}>
            {OUTRO.wordmark}
          </div>
        </div>
        <div style={{ marginTop: 30, fontSize: 44, fontWeight: 600, color: COLORS.muted, opacity: tag, transform: `translateY(${(1 - tag) * 20}px)` }}>
          {OUTRO.tagline}
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: BTN.x,
          top: BTN.y,
          width: BTN.w,
          height: BTN.h,
          borderRadius: 999,
          background: COLORS.brand,
          color: "#fff",
          fontFamily: FONT,
          fontSize: 34,
          fontWeight: 700,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          gap: 14,
          overflow: "hidden",
          opacity: btn,
          transform: `translateY(${(1 - btn) * 30}px) scale(${press})`,
          boxShadow: "0 16px 36px rgba(89,178,148,0.35)",
        }}
      >
        {OUTRO.button}
        <span style={{ fontSize: 36 }}>→</span>
        <div style={{ position: "absolute", left: BTN.w * 0.62, top: BTN.h * 0.55, width: 10, height: 10, borderRadius: "50%", background: "rgba(255,255,255,0.45)", transform: `translate(-50%,-50%) scale(${ripple * 60})`, opacity: 1 - ripple }} />
      </div>
      {/* 游標 */}
      <svg viewBox="0 0 24 24" style={{ position: "absolute", left: cx, top: cy, width: 52, height: 52, opacity: cur > 0 ? 1 : 0, filter: "drop-shadow(0 4px 6px rgba(0,0,0,0.25))" }}>
        <path d="M3 2l7.5 19 2.6-7.4L20.5 11z" fill="#1C2925" stroke="#fff" strokeWidth="1.4" strokeLinejoin="round" />
      </svg>
    </>
  );
};

export const UbanPromo: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const fadeOut = interpolate(frame, [TOTAL_FRAMES - 10, TOTAL_FRAMES], [1, 0], { extrapolateLeft: "clamp" });
  const glowX = poseAt(frame).x;
  return (
    <AbsoluteFill style={{ background: COLORS.bg, opacity: fadeOut }}>
      <div style={{ position: "absolute", left: glowX - 600, top: -60, width: 1200, height: 1200, borderRadius: "50%", background: `radial-gradient(circle, ${COLORS.glow} 0%, rgba(221,241,232,0) 65%)` }} />
      {FEATURES.map((_, i) => (
        <FeatureText key={i} frame={frame} fps={fps} idx={i} />
      ))}
      <Phone frame={frame} fps={fps} />
      <Outro frame={frame} fps={fps} />
    </AbsoluteFill>
  );
};
