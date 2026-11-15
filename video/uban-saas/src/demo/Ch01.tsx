// 第一章：開場 — 問題與願景（分鏡 00:00–01:30）
import React from "react";
import { AbsoluteFill, Audio, Img, Sequence, interpolate, spring, staticFile, useCurrentFrame } from "remotion";
import { PainPoints, PAIN_FRAMES } from "../PainPoints";
import { Stage, PhoneAt, Phone3D } from "../kit";
import { COLORS as C, FONT, FPS, HEART, HeartMark, Kinetic, Subtitles, Sub, clamp, ease, sec } from "./common";

// ================= 可直接修改的內容 =================
const SHOW_SUBS = true;
// 鏡頭起點（影格）
const T = {
  open: 0, //            00:00 開場數據與引言（20 秒）
  pain: sec(20), //      00:20 三個痛點（PainPoints，25 秒）
  logo: sec(45), //      00:45 Logo 與兩位主角（25 秒）
  array: sec(70), //     01:10 八支手機陣列（20 秒）
  end: sec(90),
};
export const CH01_FRAMES = T.end;

const OPEN_SUBS: Sub[] = [
  { from: sec(1.5), to: sec(5.5), text: "台灣每五個人，就有一位長輩。" },
  { from: sec(6), to: sec(13), text: "很多長輩一個人在家，子女在外地工作，最常說的一句話是：「有事再打給我。」" },
  { from: sec(13.5), to: sec(19.5), text: "但真的有事的時候，往往來不及打。" },
];
const LOGO_SUBS: Sub[] = [
  { from: sec(1.5), to: sec(7), text: "這是 Uban——AI 跨世代感知照護系統。" },
  { from: sec(7.5), to: sec(15.5), text: "長輩身邊有一位會聊天、會提醒、會求救的 AI 夥伴「小嘎」，" },
  { from: sec(16), to: sec(24), text: "還有一隻要靠每天好好生活，才能長大的福氣小豬。" },
];
const ARRAY_SUBS: Sub[] = [
  { from: sec(1), to: sec(10), text: "接下來，我們用阿嬤和家人的一天，帶大家看 Uban 怎麼運作——" },
  { from: sec(10.5), to: sec(19.5), text: "從畫面上看得到的，到畫面背後後端在做的每一件事。" },
];
// 八支手機（實機錄影截圖）
const PHONES = [
  { img: "e_home", label: "首頁", side: "長輩端" },
  { img: "e_chat", label: "和小嘎聊天", side: "長輩端" },
  { img: "e_pig", label: "福氣小豬", side: "長輩端" },
  { img: "e_news", label: "新聞朗讀", side: "長輩端" },
  { img: "e_question", label: "每日一問", side: "長輩端" },
  { img: "f_home", label: "家屬首頁", side: "家屬端" },
  { img: "f_interact", label: "互動", side: "家屬端" },
  { img: "f_ai", label: "AI 照護秘書", side: "家屬端" },
];
// ===================================================

// ---------- 00:00 開場：每五個人一位長輩 → 「有事再打給我。」 ----------
const Person: React.FC<{ hl: number; elder?: boolean }> = ({ hl, elder }) => {
  const stroke = hl > 0.5 ? C.warm : C.creamDim;
  return (
    <svg viewBox="0 0 120 200" width={120} height={200} style={{ transform: `scale(${1 + hl * 0.12})` }}>
      <circle cx={60} cy={58} r={32} fill="none" stroke={stroke} strokeWidth={7} />
      {elder && <circle cx={60} cy={18} r={13} fill="none" stroke={stroke} strokeWidth={7} opacity={hl} />}
      <path d="M14 190 Q14 104 60 100 Q106 104 106 190" fill="none" stroke={stroke} strokeWidth={7} strokeLinecap="round" />
    </svg>
  );
};

const Opening: React.FC<{ f: number }> = ({ f }) => {
  // 第一段：五個人一排，第三個亮起成長輩
  const rowIn = (i: number) => spring({ frame: f - sec(0.8) - i * 5, fps: FPS, config: { damping: 16 } });
  const hl = interpolate(f, [sec(2.6), sec(3.2)], [0, 1], { ...clamp, easing: ease });
  const part1Out = interpolate(f, [sec(5.3), sec(6)], [0, 1], { ...clamp, easing: ease });
  // 第二段：引言打字
  const quote = "有事再打給我。";
  const typed = Math.floor(interpolate(f, [sec(9), sec(11)], [0, quote.length], clamp));
  const phoneIn = spring({ frame: f - sec(6.2), fps: FPS, config: { damping: 18 } });
  // 第三段：時鐘飛快轉動、手機一直沒亮
  const spin = Math.max(0, f - sec(13.5)) * 9;
  const part3 = interpolate(f, [sec(13.5), sec(14.3)], [0, 1], clamp);
  const fadeOut = interpolate(f, [sec(19.3), sec(20)], [1, 0], clamp);
  return (
    <AbsoluteFill style={{ background: C.charcoal, fontFamily: FONT, opacity: fadeOut }}>
      {f < sec(6.2) && (
        <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", opacity: 1 - part1Out, transform: `translateY(${-part1Out * 60}px)` }}>
          <div style={{ display: "flex", gap: 40, alignItems: "flex-end" }}>
            {[0, 1, 2, 3, 4].map((i) => (
              <div key={i} style={{ opacity: rowIn(i), transform: `translateY(${(1 - rowIn(i)) * 40}px)` }}>
                <Person hl={i === 2 ? hl : 0} elder={i === 2} />
              </div>
            ))}
          </div>
          <div style={{ marginTop: 50, display: "flex", alignItems: "baseline", gap: 18, opacity: interpolate(f, [sec(2.8), sec(3.4)], [0, 1], clamp) }}>
            <span style={{ fontSize: 64, color: C.cream, fontWeight: 700 }}>每 5 個人，就有</span>
            <span style={{ fontSize: 120, color: C.warm, fontWeight: 800 }}>1</span>
            <span style={{ fontSize: 64, color: C.cream, fontWeight: 700 }}>位長輩</span>
          </div>
        </AbsoluteFill>
      )}
      {f >= sec(6.2) && (
        <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 90, opacity: phoneIn, transform: `translateY(${(1 - phoneIn) * 40}px)` }}>
            {/* 桌上暗著的手機 */}
            <svg viewBox="0 0 220 380" width={220} height={380}>
              <rect x={20} y={10} width={180} height={360} rx={30} fill="#1A1916" stroke={C.creamDim} strokeWidth={6} />
              <rect x={86} y={30} width={48} height={8} rx={4} fill={C.creamDim} opacity={0.5} />
              {/* 第三段：螢幕依然是暗的，旁邊的時鐘一直轉 */}
              <g transform="translate(110 190)" opacity={part3}>
                <circle r={54} fill="none" stroke={C.creamDim} strokeWidth={6} />
                <line x1={0} y1={0} x2={0} y2={-36} stroke={C.cream} strokeWidth={6} strokeLinecap="round" transform={`rotate(${spin})`} />
                <line x1={0} y1={0} x2={24} y2={0} stroke={C.cream} strokeWidth={6} strokeLinecap="round" transform={`rotate(${spin / 12})`} />
              </g>
            </svg>
            <div style={{ width: 1060 }}>
              <div style={{ fontSize: 34, color: C.creamDim, fontWeight: 600, marginBottom: 18, opacity: interpolate(f, [sec(7), sec(8)], [0, 1], clamp) }}>子女最常說的一句話</div>
              <div style={{ fontSize: 96, color: C.cream, fontWeight: 800, minHeight: 130, whiteSpace: "nowrap" }}>
                「{quote.slice(0, typed)}
                <span style={{ opacity: typed < quote.length ? (Math.floor(f / 8) % 2) : 1 }}>{typed < quote.length ? "｜" : "」"}</span>
              </div>
              <div style={{ marginTop: 40, fontSize: 52, color: C.warm, fontWeight: 700, whiteSpace: "nowrap", opacity: part3, transform: `translateY(${(1 - part3) * 20}px)` }}>
                但真的有事的時候，往往來不及打。
              </div>
            </div>
          </div>
        </AbsoluteFill>
      )}
    </AbsoluteFill>
  );
};

// ---------- 00:45 Logo 與兩位主角 ----------
const LogoScene: React.FC<{ f: number }> = ({ f }) => {
  // 痛點最後的愛心擴大成品牌綠，再以淺色圓形揭開
  const grow = interpolate(f, [0, 16], [0.8, 150], { ...clamp, easing: (t) => t * t * t });
  const reveal = interpolate(f, [14, 34], [0, 1], { ...clamp, easing: ease });
  const mark = spring({ frame: f - 24, fps: FPS, config: { damping: 12, mass: 0.8 } });
  const word = spring({ frame: f - 34, fps: FPS, config: { damping: 18 } });
  const tag = spring({ frame: f - 46, fps: FPS, config: { damping: 20 } });
  // 7 秒後 Logo 往上移，下面出現兩位主角
  const lift = interpolate(f, [sec(6.5), sec(7.5)], [0, 1], { ...clamp, easing: ease });
  const gaIn = spring({ frame: f - sec(7.6), fps: FPS, config: { damping: 16 } });
  const pigIn = spring({ frame: f - sec(15.8), fps: FPS, config: { damping: 16 } });
  const out = interpolate(f, [sec(24.4), sec(25)], [0, 1], clamp);
  return (
    <AbsoluteFill style={{ background: C.charcoal, fontFamily: FONT }}>
      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
        <path d={HEART} fill={C.brand} transform={`translate(960 400) scale(${grow})`} />
        <circle cx={960} cy={540} r={reveal * 1150} fill={C.light} />
      </svg>
      <AbsoluteFill style={{ opacity: 1 - out }}>
        {/* Logo */}
        <div style={{ position: "absolute", left: 0, right: 0, top: interpolate(lift, [0, 1], [330, 110]), display: "flex", flexDirection: "column", alignItems: "center", transform: `scale(${1 - lift * 0.35})` }}>
          <div style={{ display: "flex", alignItems: "center", gap: 40 }}>
            <div style={{ transform: `scale(${mark}) rotate(${(1 - mark) * -20}deg)` }}><HeartMark size={190} /></div>
            <div style={{ fontSize: 200, fontWeight: 800, letterSpacing: -6, color: C.ink, fontFamily: '"Segoe UI",' + FONT, opacity: word, transform: `translateX(${(1 - word) * -40}px)` }}>Uban</div>
          </div>
          <div style={{ marginTop: 18, fontSize: 52, fontWeight: 700, color: C.muted, letterSpacing: 6, opacity: tag, transform: `translateY(${(1 - tag) * 20}px)` }}>AI 跨世代感知照護系統</div>
        </div>
        {/* 主角一：小嘎（實機聊天畫面） */}
        <div style={{ position: "absolute", left: 300, top: 420, width: 560, display: "flex", gap: 34, alignItems: "center", opacity: gaIn, transform: `translateY(${(1 - gaIn) * 50}px)` }}>
          <div style={{ width: 200, height: 445, borderRadius: 34, overflow: "hidden", border: "8px solid #0F1513", boxShadow: "0 24px 50px rgba(28,41,37,0.25)", flexShrink: 0 }}>
            <Img src={staticFile("demo/ch01/e_chat.png")} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
          </div>
          <div>
            <div style={{ display: "inline-block", padding: "6px 18px", borderRadius: 999, background: "#DDF1E8", color: C.brandDeep, fontSize: 28, fontWeight: 800 }}>AI 夥伴</div>
            <div style={{ fontSize: 76, fontWeight: 800, color: C.ink, marginTop: 10 }}>小嘎</div>
            <div style={{ fontSize: 34, fontWeight: 600, color: C.muted, marginTop: 8, lineHeight: 1.5 }}>會聊天<br />會提醒<br />會求救</div>
          </div>
        </div>
        {/* 主角二：福氣小豬（手繪五階段依序長大） */}
        <div style={{ position: "absolute", left: 1010, top: 470, width: 700, opacity: pigIn, transform: `translateY(${(1 - pigIn) * 50}px)` }}>
          <div style={{ display: "inline-block", padding: "6px 18px", borderRadius: 999, background: "#FBE7DF", color: "#B5645A", fontSize: 28, fontWeight: 800 }}>福氣小豬</div>
          <div style={{ display: "flex", alignItems: "flex-end", gap: 8, marginTop: 20, height: 260 }}>
            {[1, 2, 3, 4, 5].map((s, i) => {
              const t = spring({ frame: f - sec(16.4) - i * 9, fps: FPS, config: { damping: 11 } });
              const h = 120 + i * 32;
              return <Img key={s} src={staticFile(`ad/pig/pig_stage_${s}.png`)} style={{ height: h, opacity: t, transform: `scale(${t})`, transformOrigin: "50% 100%" }} />;
            })}
          </div>
          <div style={{ fontSize: 34, fontWeight: 600, color: C.muted, marginTop: 14 }}>好好吃藥、出門走路，小豬就會長大</div>
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{ background: C.light, opacity: out }} />
    </AbsoluteFill>
  );
};

// ---------- 01:10 八支手機陣列 ----------
const ArrayScene: React.FC<{ f: number }> = ({ f }) => {
  const camX = interpolate(f, [0, sec(20)], [130, -130], { ...clamp, easing: ease });
  return (
    <AbsoluteFill style={{ background: C.light, fontFamily: FONT, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 960 + camX - 700, top: -200, width: 1400, height: 1400, borderRadius: "50%", background: "radial-gradient(circle, #DDF1E8 0%, rgba(221,241,232,0) 62%)" }} />
      <Stage perspective={2600}>
        <div style={{ position: "absolute", transformStyle: "preserve-3d", transform: `translate3d(${camX}px, -60px, -180px)` }}>
          {PHONES.map((p, i) => {
            const n = PHONES.length;
            const a = (i - (n - 1) / 2) / ((n - 1) / 2); // -1..1
            const enter = spring({ frame: f - 6 - i * 7, fps: FPS, config: { damping: 15 } });
            // 依序亮起：每支一拍（15 影格）
            const lit = interpolate(f, [sec(1.4) + i * 15, sec(1.4) + i * 15 + 8], [0.65, 0], clamp);
            const pose = { x: a * 880 + (p.side === "家屬端" ? 60 : 0), y: Math.abs(a) * 50 + (1 - enter) * 600, z: -Math.abs(a) * 300, ry: -a * 26, rx: 4, rz: a * 2.5, s: 0.7 };
            return (
              <PhoneAt key={p.img} pose={pose}>
                <Phone3D frame={f} dim={lit} screen={<Img src={staticFile(`demo/ch01/${p.img}.png`)} style={{ width: "100%", height: "100%", objectFit: "cover" }} />} />
                {/* 標籤放在手機下方，跟著手機一起動 */}
                <div style={{ position: "absolute", left: -60, width: 540, top: 925, textAlign: "center", fontFamily: FONT, transform: "translateZ(30px)", opacity: interpolate(f, [sec(1.4) + i * 15, sec(1.4) + i * 15 + 10], [0, 1], clamp) }}>
                  <div style={{ fontSize: 34, fontWeight: 700, color: p.side === "家屬端" ? "#5B7FA3" : C.brandDeep, letterSpacing: 4 }}>{p.side}</div>
                  <div style={{ fontSize: 50, fontWeight: 800, color: C.ink, whiteSpace: "nowrap" }}>{p.label}</div>
                </div>
              </PhoneAt>
            );
          })}
        </div>
      </Stage>
    </AbsoluteFill>
  );
};

export const Ch01: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: C.charcoal }}>
      <Sequence from={T.open} durationInFrames={T.pain - T.open}><Opening f={frame - T.open} /></Sequence>
      <Sequence from={T.pain} durationInFrames={PAIN_FRAMES}><PainPoints /></Sequence>
      <Sequence from={T.logo} durationInFrames={T.array - T.logo}><LogoScene f={frame - T.logo} /></Sequence>
      <Sequence from={T.array} durationInFrames={T.end - T.array}><ArrayScene f={frame - T.array} /></Sequence>

      {SHOW_SUBS && frame < T.pain && <Subtitles frame={frame - T.open} subs={OPEN_SUBS} />}
      {SHOW_SUBS && frame >= T.logo && frame < T.array && <Subtitles frame={frame - T.logo} subs={LOGO_SUBS} />}
      {SHOW_SUBS && frame >= T.array && <Subtitles frame={frame - T.array} subs={ARRAY_SUBS} />}

      {/* 聲音：開場只有時鐘滴答；Logo 定格「叮」；配樂從 Logo 開始 */}
      <Sequence from={sec(13.5)} durationInFrames={sec(6)}>
        <Audio src={staticFile("ad/audio/tick.wav")} loop volume={0.35} />
      </Sequence>
      <Sequence from={T.logo + 24} durationInFrames={sec(3)}><Audio src={staticFile("ad/audio/ding.wav")} volume={0.7} /></Sequence>
      <Sequence from={T.logo} durationInFrames={T.end - T.logo}>
        <Audio src={staticFile("ad/audio/music.wav")} volume={(f) => interpolate(f, [0, 20, T.end - T.logo - 30, T.end - T.logo], [0, 0.32, 0.32, 0], clamp)} />
      </Sequence>
      {PHONES.map((_, i) => (
        <Sequence key={i} from={T.array + sec(1.4) + i * 15} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/pop.wav")} volume={0.35} /></Sequence>
      ))}
    </AbsoluteFill>
  );
};
