import React from "react";
import { AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig, Easing } from "remotion";
import meta from "../public/chat/meta.json";

// ================= 可直接修改的內容 =================
export const CHAT_FPS = 30;
export const CHAT_FRAMES = 450; // 15 秒

const C = {
  bg: "#F3F7F5",
  glow: "#D7EFE4",
  ink: "#1C2925",
  muted: "#5D6B66",
  brand: "#59B294",
  brandDeep: "#3E957A",
  meBubble: "#3F9C7C",
};
const FONT = '"Microsoft JhengHei UI","Microsoft JhengHei","Noto Sans TC",sans-serif';

const TITLE = { eyebrow: "AI 夥伴", title: "和小嘎聊天" };
const CAPTIONS = [
  { from: 150, to: 268, text: "想到什麼，就跟小嘎說" },
  { from: 272, to: 362, text: "按住說話，小嘎用國語或台語回您" },
  { from: 366, to: 450, text: "聊一聊，順手幫您記下提醒" },
];
const BUBBLES = {
  ai0: "阿嬤，昨晚睡得好嗎？",
  me0: "睡得不錯，就是半夜起來一次",
  ai1: "那很正常喔，年紀大了比較淺眠。白天記得多走動、曬點太陽，晚上會更好睡。",
  ai2: "太好了！要不要我幫您記下來，等到下午提醒您出門散步？",
  me2: "好啊，謝謝你",
};
const REMINDER = { time: "下午 3:00", text: "提醒出門散步" };
// ===================================================

type Rect = { x: number; y: number; w: number; h: number };
const M = meta as Record<string, Rect>;

// 手機尺寸（場景座標）
const SW = 392;
const K = SW / 370; // 原型螢幕 CSS px → 場景 px
const SH = Math.round(824 * K);
const BEZ = 13;
const PW = SW + BEZ * 2;
const PH = SH + BEZ * 2;
const DEPTH = 44;
const RADIUS = 66;

const ease = Easing.bezier(0.22, 1, 0.36, 1);

// 關鍵影格：[影格, 值]，中間緩動
export function kf(frame: number, keys: [number, number][]) {
  if (frame <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    if (frame <= keys[i][0]) {
      const [f0, v0] = keys[i - 1];
      const [f1, v1] = keys[i];
      const t = ease((frame - f0) / Math.max(1, f1 - f0));
      return v0 + (v1 - v0) * t;
    }
  }
  return keys[keys.length - 1][1];
}

type Pose = { f: number; x: number; y: number; ry: number; rx: number; rz: number };
const PHONE_POSES: Pose[] = [
  { f: 0, x: 280, y: 520, ry: -78, rx: 20, rz: 10 },
  { f: 48, x: 270, y: 0, ry: -30, rx: 10, rz: 4 },
  { f: 82, x: 250, y: -6, ry: -26, rx: 9, rz: 4 },
  { f: 136, x: 320, y: 0, ry: 24, rx: 8, rz: -3 },
  { f: 205, x: 350, y: 10, ry: 15, rx: 6, rz: -2 },
  { f: 268, x: 350, y: 10, ry: 13, rx: 6, rz: -2 },
  { f: 300, x: 400, y: 16, ry: -15, rx: 8, rz: 2 },
  { f: 360, x: 400, y: 16, ry: -17, rx: 8, rz: 2 },
  { f: 400, x: 330, y: 0, ry: 20, rx: 8, rz: -3 },
  { f: 450, x: 300, y: -6, ry: 26, rx: 10, rz: -4 },
];
function phonePose(frame: number) {
  const get = (k: keyof Omit<Pose, "f">) => kf(frame, PHONE_POSES.map((p) => [p.f, p[k]] as [number, number]));
  return { x: get("x"), y: get("y"), ry: get("ry"), rx: get("rx"), rz: get("rz") };
}

// 攝影機：z 越大越靠近
const CAM_Z: [number, number][] = [[0, -900], [60, -160], [140, -90], [205, 150], [268, 170], [300, 130], [360, 150], [400, 20], [450, -240]];
const CAM_RY: [number, number][] = [[0, -8], [450, 7]];
const CAM_X: [number, number][] = [[0, 0], [140, -40], [270, -60], [360, -70], [450, -20]];

// 卡片：從螢幕上的位置飛出來
type CardKey = { f: number; x?: number; y?: number; z?: number; s?: number; face?: number; o?: number };
const Z0 = DEPTH / 2 + 2;

function cardState(frame: number, rect: Rect, keys: CardKey[]) {
  const home = { x: (rect.x + rect.w / 2 - 185) * K, y: (rect.y + rect.h / 2 - 412) * K, z: Z0, s: 1, face: 0, o: 1 };
  const full = keys.map((k) => ({ ...home, ...k }));
  const pick = (n: "x" | "y" | "z" | "s" | "face" | "o") => kf(frame, full.map((k) => [k.f, k[n]] as [number, number]));
  return { x: pick("x"), y: pick("y"), z: pick("z"), s: pick("s"), face: pick("face"), o: pick("o"), w: rect.w * K, h: rect.h * K };
}

const Card: React.FC<{
  frame: number;
  rect: Rect;
  keys: CardKey[];
  pose: { ry: number; rx: number; rz: number };
  radius?: string;
  children: React.ReactNode;
  visibleFrom: number;
  auto?: boolean;
}> = ({ frame, rect, keys, pose, radius = "24px", children, visibleFrom, auto }) => {
  if (frame < visibleFrom) return null;
  const st = cardState(frame, rect, keys);
  if (st.o <= 0.01) return null;
  const lift = Math.max(0, Math.min(1, (st.z - Z0) / 120));
  return (
    <div
      style={{
        position: "absolute",
        left: auto ? PW / 2 : PW / 2 - st.w / 2,
        top: auto ? PH / 2 : PH / 2 - st.h / 2,
        width: auto ? "max-content" : st.w,
        maxWidth: auto ? st.w * 1.08 : undefined,
        height: auto ? "auto" : st.h,
        opacity: st.o,
        transform: `${auto ? "translate(-50%,-50%) " : ""}translate3d(${st.x}px,${st.y}px,${st.z}px) rotateZ(${-pose.rz * st.face}deg) rotateX(${-pose.rx * st.face}deg) rotateY(${-pose.ry * st.face}deg) scale(${st.s})`,
        borderRadius: radius,
        boxShadow: `0 ${10 + lift * 30}px ${24 + lift * 50}px rgba(28,41,37,${0.08 + lift * 0.16})`,
        overflow: "hidden",
      }}
    >
      {children}
    </div>
  );
};

const Bubble: React.FC<{ who: "ai" | "me"; text: string; listen?: boolean }> = ({ who, text, listen }) => (
  <div
    style={{
      boxSizing: "border-box",
      padding: `${13 * K}px ${17 * K}px`,
      background: who === "ai" ? "#FFFFFF" : C.meBubble,
      color: who === "ai" ? C.ink : "#fff",
      fontFamily: FONT,
      fontSize: 18 * K,
      lineHeight: 1.5,
      fontWeight: 500,
    }}
  >
    {text}
    {listen && (
      <div style={{ marginTop: 4 * K, color: C.brandDeep, fontSize: 15 * K, fontWeight: 700 }}>🔊 再聽一次</div>
    )}
  </div>
);

const Phone: React.FC<{ frame: number; children: React.ReactNode; screenSwap: number; dim: number }> = ({ frame, children, screenSwap, dim }) => {
  const slices = 22;
  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: PW, height: PH, transformStyle: "preserve-3d" }}>
      {/* 機身厚度：一層層堆疊的圓角板 */}
      {Array.from({ length: slices }).map((_, i) => {
        const z = -DEPTH / 2 + (i * DEPTH) / (slices - 1);
        const edge = Math.abs(i / (slices - 1) - 0.5) * 2; // 0 中間 → 1 邊緣
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
      {[{ y: 190, h: 54 }, { y: 268, h: 90 }, { y: 372, h: 90 }].map((b, i) => (
        <div key={i} style={{ position: "absolute", left: -DEPTH * 0.22, top: b.y, width: DEPTH * 0.44, height: b.h, borderRadius: 6, background: "linear-gradient(90deg,#8E9A95,#D8E0DC,#8E9A95)", transform: "translateX(-3px) rotateY(90deg)" }} />
      ))}
      <div style={{ position: "absolute", right: -DEPTH * 0.22, top: 300, width: DEPTH * 0.44, height: 120, borderRadius: 6, background: "linear-gradient(90deg,#8E9A95,#D8E0DC,#8E9A95)", transform: "translateX(3px) rotateY(90deg)" }} />
      {/* 背面 */}
      <div style={{ position: "absolute", inset: 0, borderRadius: RADIUS, transform: `translateZ(${-DEPTH / 2 - 1}px) rotateY(180deg)`, background: "linear-gradient(160deg,#DCE8E2,#B9CBC3)" }} />
      {/* 正面：黑邊框＋螢幕 */}
      <div style={{ position: "absolute", inset: 0, borderRadius: RADIUS, transform: `translateZ(${DEPTH / 2 + 0.5}px)`, background: "#0F1513", padding: BEZ, boxSizing: "border-box" }}>
        <div style={{ position: "relative", width: "100%", height: "100%", borderRadius: RADIUS - BEZ, overflow: "hidden", background: "#fff" }}>
          <Img src={staticFile("chat/pig_screen.png")} style={{ position: "absolute", inset: 0, width: "100%", height: "100%" }} />
          <Img src={staticFile("chat/chat_screen.png")} style={{ position: "absolute", inset: 0, width: "100%", height: "100%", opacity: screenSwap, transform: `translateX(${(1 - screenSwap) * 40}px)` }} />
          <div style={{ position: "absolute", inset: 0, background: "#F3F7F5", opacity: dim }} />
          {/* 玻璃反光 */}
          <div style={{ position: "absolute", inset: 0, background: `linear-gradient(115deg, rgba(255,255,255,0.22) 0%, rgba(255,255,255,0) ${30 + Math.sin(frame / 40) * 6}%)` }} />
        </div>
      </div>
      {children}
    </div>
  );
};

export const Waveform: React.FC<{ frame: number }> = ({ frame }) => (
  <div style={{ display: "flex", gap: 9, alignItems: "center", height: 80, justifyContent: "center" }}>
    {Array.from({ length: 13 }).map((_, i) => {
      const h = 14 + Math.abs(Math.sin(frame / 4 + i * 0.9)) * 52 * (1 - Math.abs(i - 6) / 9);
      return <div key={i} style={{ width: 9, height: h, borderRadius: 5, background: C.brand }} />;
    })}
  </div>
);

export const Kinetic: React.FC<{ text: string; frame: number; start: number; size: number; color: string; weight?: number }> = ({ text, frame, start, size, color, weight = 800 }) => {
  const { fps } = useVideoConfig();
  return (
    <div style={{ display: "flex", flexWrap: "wrap" }}>
      {[...text].map((ch, i) => {
        const t = spring({ frame: frame - start - i * 1.6, fps, config: { damping: 16, mass: 0.6 } });
        return (
          <span key={i} style={{ display: "inline-block", fontSize: size, fontWeight: weight, color, opacity: t, transform: `translateY(${(1 - t) * 40}px) scale(${0.8 + t * 0.2})`, whiteSpace: "pre" }}>
            {ch}
          </span>
        );
      })}
    </div>
  );
};

export const ChatFeature: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pose = phonePose(frame);
  const camZ = kf(frame, CAM_Z);
  const camRY = kf(frame, CAM_RY);
  const camX = kf(frame, CAM_X);
  const screenSwap = kf(frame, [[98, 0], [116, 1]]);
  const dim = kf(frame, [[150, 0], [175, 0.35], [262, 0.35], [282, 0.2], [362, 0.2], [380, 0.35]]);
  const navSwap = frame >= 96 ? 1 : 0;
  const ripple = kf(frame, [[90, 0], [108, 1]]);

  const talkPress = frame >= 308 && frame <= 318 ? 0.93 : 1;
  const langSwap = kf(frame, [[326, 0], [336, 1]]);

  const caption = CAPTIONS.find((c) => frame >= c.from && frame < c.to);
  const capOut = caption ? kf(frame, [[caption.to - 10, 0], [caption.to, 1]]) : 1;

  const titleIn = frame - 104;
  const brand = spring({ frame: frame - 412, fps, config: { damping: 18 } });

  return (
    <AbsoluteFill style={{ background: C.bg, overflow: "hidden" }}>
      {/* 背景光暈 */}
      <div style={{ position: "absolute", left: 960 + pose.x - 650 + camX, top: -120, width: 1300, height: 1300, borderRadius: "50%", background: `radial-gradient(circle, ${C.glow} 0%, rgba(215,239,228,0) 62%)` }} />
      <div style={{ position: "absolute", left: -300, top: 600, width: 900, height: 900, borderRadius: "50%", background: "radial-gradient(circle, rgba(89,178,148,0.10) 0%, rgba(89,178,148,0) 60%)" }} />

      {/* 3D 舞台 */}
      <div style={{ position: "absolute", inset: 0, perspective: 2300, perspectiveOrigin: "50% 50%" }}>
        <div style={{ position: "absolute", left: "50%", top: "50%", width: 0, height: 0, transformStyle: "preserve-3d", transform: `translate3d(${camX}px,0,${camZ}px) rotateY(${camRY}deg)` }}>
          <div
            style={{
              position: "absolute",
              left: -PW / 2,
              top: -PH / 2,
              width: PW,
              height: PH,
              transformStyle: "preserve-3d",
              transform: `translate3d(${pose.x}px,${pose.y + Math.sin(frame / 30) * 6}px,0) rotateY(${pose.ry}deg) rotateX(${pose.rx}deg) rotateZ(${pose.rz}deg)`,
            }}
          >
            <Phone frame={frame} screenSwap={screenSwap} dim={dim}>
              {/* 底部導覽列：浮出 → 點「聊天」 → 收回 */}
              <Card frame={frame} rect={M.nav_pig} pose={pose} radius="999px" visibleFrom={20}
                keys={[{ f: 28 }, { f: 62, y: (M.nav_pig.y + M.nav_pig.h / 2 - 412) * K + 70, z: 110, s: 1.08 }, { f: 122, y: (M.nav_pig.y + M.nav_pig.h / 2 - 412) * K + 70, z: 110, s: 1.08 }, { f: 142 }]}>
                <div style={{ position: "relative", width: "100%", height: "100%" }}>
                  <Img src={staticFile(navSwap ? "chat/nav_chat.png" : "chat/nav_pig.png")} style={{ width: "100%", height: "100%", display: "block" }} />
                  {ripple > 0 && ripple < 1 && (
                    <div style={{ position: "absolute", left: "69%", top: "45%", width: 12, height: 12, borderRadius: "50%", background: "rgba(89,178,148,0.35)", transform: `translate(-50%,-50%) scale(${ripple * 14})`, opacity: 1 - ripple }} />
                  )}
                </div>
              </Card>

              {/* 對話泡泡 */}
              <Card frame={frame} rect={M.ai0} pose={pose} radius="24px 24px 24px 8px" visibleFrom={148} auto
                keys={[{ f: 150 }, { f: 176, x: -560, y: -150, z: 230, s: 1.5, face: 1 }, { f: 246, x: -560, y: -150, z: 230, s: 1.5, face: 1 }, { f: 268, x: -620, y: -200, z: 80, s: 1.3, face: 1, o: 0 }]}>
                <Bubble who="ai" text={BUBBLES.ai0} listen />
              </Card>
              <Card frame={frame} rect={M.me0} pose={pose} radius="24px 24px 8px 24px" visibleFrom={166} auto
                keys={[{ f: 168 }, { f: 194, x: -430, y: 10, z: 270, s: 1.5, face: 1 }, { f: 250, x: -430, y: 10, z: 270, s: 1.5, face: 1 }, { f: 270, x: -480, y: -30, z: 100, s: 1.3, face: 1, o: 0 }]}>
                <Bubble who="me" text={BUBBLES.me0} />
              </Card>
              <Card frame={frame} rect={M.ai1} pose={pose} radius="24px 24px 24px 8px" visibleFrom={184} auto
                keys={[{ f: 186 }, { f: 212, x: -530, y: 190, z: 240, s: 1.45, face: 1 }, { f: 254, x: -530, y: 190, z: 240, s: 1.45, face: 1 }, { f: 272, x: -570, y: 220, z: 100, s: 1.3, face: 1, o: 0 }]}>
                <Bubble who="ai" text={BUBBLES.ai1} />
              </Card>

              {/* 按住說話＋聲波＋國語／台語 */}
              <Card frame={frame} rect={M.talk} pose={pose} radius="999px" visibleFrom={272}
                keys={[{ f: 274 }, { f: 298, x: -470, y: 30, z: 290, s: 1.9 * talkPress, face: 1 }, { f: 346, x: -470, y: 30, z: 290, s: 1.9, face: 1 }, { f: 364, x: -500, y: 60, z: 100, s: 1.6, face: 1, o: 0 }]}>
                <Img src={staticFile("chat/talk.png")} style={{ width: "100%", height: "100%", display: "block" }} />
              </Card>
              <Card frame={frame} rect={{ x: 85, y: 560, w: 270, h: 70 }} pose={pose} radius="20px" visibleFrom={290}
                keys={[{ f: 290, o: 0, z: Z0 + 40 }, { f: 304, x: -470, y: -130, z: 300, s: 1.5, face: 1, o: 1 }, { f: 346, x: -470, y: -130, z: 300, s: 1.5, face: 1 }, { f: 362, x: -480, y: -150, z: 120, s: 1.3, face: 1, o: 0 }]}>
                <div style={{ width: "100%", height: "100%", background: "rgba(255,255,255,0.92)", display: "flex", alignItems: "center", justifyContent: "center", flexDirection: "column" }}>
                  <div style={{ transform: "scale(0.62)" }}><Waveform frame={frame} /></div>
                </div>
              </Card>
              <Card frame={frame} rect={M.langseg} pose={pose} radius="999px" visibleFrom={282}
                keys={[{ f: 284 }, { f: 306, x: -470, y: 205, z: 260, s: 1.7, face: 1 }, { f: 348, x: -470, y: 205, z: 260, s: 1.7, face: 1 }, { f: 364, x: -480, y: 240, z: 100, s: 1.4, face: 1, o: 0 }]}>
                <div style={{ position: "relative", width: "100%", height: "100%" }}>
                  <Img src={staticFile("chat/langseg.png")} style={{ position: "absolute", inset: 0, width: "100%", height: "100%" }} />
                  <Img src={staticFile("chat/langseg_tw.png")} style={{ position: "absolute", inset: 0, width: "100%", height: "100%", opacity: langSwap }} />
                </div>
              </Card>

              {/* 提醒流程 */}
              <Card frame={frame} rect={M.ai2} pose={pose} radius="24px 24px 24px 8px" visibleFrom={364} auto
                keys={[{ f: 366 }, { f: 390, x: -560, y: -110, z: 230, s: 1.42, face: 1 }, { f: 450, x: -540, y: -120, z: 250, s: 1.42, face: 1 }]}>
                <Bubble who="ai" text={BUBBLES.ai2} />
              </Card>
              <Card frame={frame} rect={M.me2} pose={pose} radius="24px 24px 8px 24px" visibleFrom={380} auto
                keys={[{ f: 382 }, { f: 404, x: -400, y: 50, z: 270, s: 1.45, face: 1 }, { f: 450, x: -390, y: 45, z: 290, s: 1.45, face: 1 }]}>
                <Bubble who="me" text={BUBBLES.me2} />
              </Card>
              <Card frame={frame} rect={{ x: 50, y: 600, w: 290, h: 74 }} pose={pose} radius="22px" visibleFrom={396}
                keys={[{ f: 396, o: 0 }, { f: 418, x: -500, y: 190, z: 300, s: 1.45, face: 1, o: 1 }, { f: 450, x: -495, y: 185, z: 320, s: 1.45, face: 1 }]}>
                <div style={{ width: "100%", height: "100%", background: "#FFFFFF", border: `3px solid ${C.brand}`, boxSizing: "border-box", borderRadius: 22, display: "flex", alignItems: "center", gap: 12, padding: "0 16px", fontFamily: FONT }}>
                  <div style={{ width: 44, height: 44, borderRadius: 14, background: C.glow, display: "grid", placeItems: "center", fontSize: 24 }}>⏰</div>
                  <div>
                    <div style={{ fontSize: 15, color: C.brandDeep, fontWeight: 700 }}>已建立提醒</div>
                    <div style={{ fontSize: 19, color: C.ink, fontWeight: 800, whiteSpace: "nowrap" }}>{REMINDER.time}・{REMINDER.text}</div>
                  </div>
                </div>
              </Card>
            </Phone>
          </div>
        </div>
      </div>

      {/* 標題 */}
      {titleIn > -2 && (
        <div style={{ position: "absolute", left: 130, top: 96, fontFamily: FONT }}>
          <div style={{ display: "inline-block", padding: "8px 20px", borderRadius: 999, background: C.glow, color: C.brandDeep, fontSize: 28, fontWeight: 800, letterSpacing: 2, opacity: kf(frame, [[104, 0], [116, 1]]) }}>{TITLE.eyebrow}</div>
          <div style={{ marginTop: 14 }}>
            <Kinetic text={TITLE.title} frame={frame} start={108} size={96} color={C.ink} />
          </div>
        </div>
      )}

      {/* 段落字幕 */}
      {caption && (
        <div style={{ position: "absolute", left: 130, bottom: 110, fontFamily: FONT, opacity: 1 - capOut, transform: `translateY(${-capOut * 20}px)` }}>
          <div style={{ width: 70, height: 6, borderRadius: 3, background: C.brand, marginBottom: 20 }} />
          <Kinetic text={caption.text} frame={frame} start={caption.from} size={58} color={C.ink} weight={700} />
        </div>
      )}

      {/* 品牌 */}
      <div style={{ position: "absolute", right: 110, bottom: 96, display: "flex", alignItems: "center", gap: 16, opacity: brand, transform: `translateY(${(1 - brand) * 20}px)`, fontFamily: FONT }}>
        <div style={{ width: 64, height: 64, borderRadius: 20, background: "linear-gradient(180deg,#5CBB9B,#4DAD88)", display: "grid", placeItems: "center" }}>
          <svg viewBox="0 0 64 64" style={{ width: 42, height: 42 }}>
            <circle cx="32" cy="15" r="9" fill="#D1EEE7" />
            <path d="M32 54C20 46 12 38 12 30a10 10 0 0 1 20-3 10 10 0 0 1 20 3c0 8-8 16-20 24z" fill="none" stroke="#D1EEE7" strokeWidth="5" strokeLinejoin="round" />
            <path d="M17 37l15-10" stroke="#D1EEE7" strokeWidth="5" strokeLinecap="round" />
          </svg>
        </div>
        <div style={{ fontSize: 58, fontWeight: 800, color: C.ink, fontFamily: '"Segoe UI",' + FONT, letterSpacing: -1 }}>Uban</div>
      </div>
    </AbsoluteFill>
  );
};
