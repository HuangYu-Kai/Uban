// 第八章：家人的話，由小嘎轉達（分鏡 16:30–18:00，共 90 秒）
// 主要手法：逐步打字＋原聲呼吸點；材質：3D 手機＋實機錄影
// 錄影：07_每日一問_長輩回答、07_每日一問_家屬回覆
// 待補錄：家屬在時光牆發照片 → 小嘎開場轉達
import React from "react";
import { AbsoluteFill, Audio, Sequence, interpolate, spring, staticFile, useCurrentFrame } from "remotion";
import { BackendChips, ChapterCard, Chip, COLORS as C, FONT, FPS, Sub, Subtitles, clamp, ease, sec } from "./common";
import { Backdrop, ClipSound, DemoClip, Headline, Placeholder, Tag, pop, vis } from "./scene";
import { Phone3D, PhoneAt, Pose, PullOut, Stage, Tap } from "../kit";
import { Waveform } from "../ChatFeature";

const SHOW_SUBS = true;
const T = { a: 0, b: sec(24), c: sec(57), end: sec(90) };
export const CH08_FRAMES = T.end;

const HOME: Pose = { x: 250, y: 6, ry: -14, rx: 4, rz: 1, s: 0.94 };
const LEFT: Pose = { x: -330, y: 60, ry: 12, rx: 3, rz: -1, s: 0.78 };
const RIGHT: Pose = { x: 330, y: 60, ry: -12, rx: 3, rz: 1, s: 0.78 };

// 長輩回答的原聲（片內 4.3 秒起）出現時，旁白與配樂讓位
const VOICE_AT = T.b + 60 + Math.round((4.3 - 1) * 30);

const SUBS: Sub[] = [
  { from: sec(1.7), to: sec(7.5), text: "家人在家庭時光牆分享了一張生活照，" },
  { from: sec(7.9), to: sec(14.5), text: "阿嬤下次打開聊天，小嘎會先開口：" },
  { from: sec(14.9), to: sec(23.5), text: "家人分享的好消息，不需要阿嬤自己去滑，小嘎會像聊天一樣說給她聽。" },
  { from: sec(24.6), to: sec(29.2), text: "每天，小嘎會問阿嬤一個回憶小問題。" },
  { from: sec(43), to: sec(50), text: "阿嬤說的故事，連同原聲一起保存，" },
  { from: sec(50.4), to: sec(56.5), text: "送到家人的手機。" },
  { from: sec(57.6), to: sec(63), text: "家人這邊，回答都收進「回憶錄」。" },
  { from: sec(63.4), to: sec(69), text: "點開就能聽到媽媽的原聲，" },
  { from: sec(69.4), to: sec(75.5), text: "還能留一句悄悄話回去。" },
  { from: sec(75.9), to: sec(82.5), text: "日積月累，這些回答就成了一本阿嬤的回憶錄——" },
  { from: sec(82.9), to: sec(89.6), text: "這是家人之間，最珍貴的資產。" },
];

const CHIPS: Chip[] = [
  { from: sec(3), to: sec(12), text: "POST /api/community/posts" },
  { from: sec(9), to: sec(23.5), text: "GET /api/ai/family_updates/{id}/opening" },
  { from: sec(16), to: sec(23.5), text: "POST …/relayed 標記已轉達" },
  { from: sec(25), to: sec(42), text: "GET /api/daily_question/today · 題庫或家屬出題" },
  { from: sec(43), to: sec(56.5), text: "POST /api/daily_question/{id}/answer · 語音 ≤ 5MB" },
  { from: sec(48), to: sec(56.5), text: "daily-answer → 通知家屬" },
  { from: sec(60), to: sec(89.5), text: "GET /api/daily_question/history" },
];

// ============ A 時光牆照片 → 小嘎開場（待補錄） ============
const OPEN = "家人剛剛分享了一張照片，看起來大家都好開心喔！";
const WallScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.a, b = T.b;
  if (frame < a || frame > b) return null;
  const enter = spring({ frame: frame - a, fps: FPS, config: { damping: 20 } });
  const left: Pose = { ...LEFT, x: LEFT.x - (1 - enter) * 500 };
  const right: Pose = { ...RIGHT, x: RIGHT.x + (1 - enter) * 500 };
  const LX = 960 + LEFT.x, RX = 960 + RIGHT.x, MY = 540 + LEFT.y;
  // 照片從家屬機飛出，在空中翻轉，落到長輩機前
  const go = a + 70, dur = 70;
  const t = ease(Math.max(0, Math.min(1, (frame - go) / dur)));
  const px = LX + (RX - LX) * t, py = MY - 60 - Math.sin(Math.PI * t) * 240;
  const flip = t * 360;
  const n = Math.floor(interpolate(frame, [a + 240, a + 420], [0, OPEN.length], clamp));
  const bubble = pop(frame, a + 230);
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12), fontFamily: FONT }}>
      <Stage>
        <PhoneAt pose={left}>
          <Phone3D frame={frame} screen={<Placeholder frame={frame} title="家屬：時光牆發照片" lines={["家庭生活時光牆"]} />} />
        </PhoneAt>
        <PhoneAt pose={right}>
          <Phone3D frame={frame} screen={<Placeholder frame={frame} title="長輩：打開聊天" lines={["小嘎開場轉達", "並附上照片"]} />} />
        </PhoneAt>
      </Stage>
      {frame >= go && (
        <div style={{ position: "absolute", left: px - 110, top: py - 80, width: 220, height: 160, borderRadius: 14, background: "#fff", padding: 10, boxSizing: "border-box", boxShadow: "0 18px 40px rgba(28,41,37,0.25)", transform: `rotateY(${flip}deg) rotate(${(1 - t) * -12}deg)` }}>
          <div style={{ width: "100%", height: "100%", borderRadius: 8, background: "linear-gradient(180deg,#BFE3F2 0%,#BFE3F2 55%,#9CCB8E 55%,#7FB874 100%)", position: "relative", overflow: "hidden" }}>
            <div style={{ position: "absolute", left: 30, top: 20, width: 34, height: 34, borderRadius: "50%", background: "#FFE08A" }} />
            {[60, 100, 140].map((x, i) => (
              <div key={i} style={{ position: "absolute", left: x, bottom: 18, width: 26, height: 44 + (i % 2) * 10, borderRadius: "13px 13px 4px 4px", background: ["#E58A4E", "#5B6FB0", "#E4574B"][i] }} />
            ))}
          </div>
        </div>
      )}
      <div style={{ position: "absolute", left: 960 - 470, top: 50, width: 940, padding: "24px 32px", borderRadius: 30, background: C.ink, color: C.cream, opacity: bubble, transform: `translateY(${(1 - bubble) * 20}px)`, boxShadow: "0 18px 44px rgba(28,41,37,0.25)", display: "flex", gap: 18, alignItems: "center" }}>
        <div style={{ width: 56, height: 56, flexShrink: 0, borderRadius: "50%", background: C.brand, display: "grid", placeItems: "center", color: "#fff", fontSize: 28, fontWeight: 800 }}>嘎</div>
        <div style={{ fontSize: 36, fontWeight: 700, lineHeight: 1.4, minHeight: 50 }}>{OPEN.slice(0, n)}</div>
      </div>
      <Tag frame={frame} at={a + 30} x={LX - 70} y={950} text="家人" />
      <Tag frame={frame} at={a + 34} x={RX - 70} y={950} text="長輩" />
      <div style={{ position: "absolute", left: 60, top: 40, fontSize: 22, color: C.muted, opacity: 0.8 }}>示意動畫（實機畫面待補錄）</div>
    </AbsoluteFill>
  );
};

// ============ B 每日一問：長輩回答（q_elder） ============
// 片內：0–1 聊天頁「今日一問」卡、1.5 我來回答、3.5 按住說出答案、4.3–11 長輩說話、約 13 送出給家人、14 小嘎道謝
const ElderScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.b, b = T.c;
  if (frame < a || frame > b) return null;
  const enter = spring({ frame: frame - a, fps: FPS, config: { damping: 20 } });
  const drift = interpolate(frame, [a, b], [0, 1]);
  // 回答時慢慢推近（留白、不加特效）
  const pose: Pose = { ...HOME, x: HOME.x - (1 - enter) * 500, ry: HOME.ry + (1 - enter) * 30, s: (HOME.s ?? 1) * (1 + drift * 0.06) };
  const screen = <DemoClip src="q_elder" segs={[{ at: a, to: a + 60, from: 0, rate: 0.5 }, { at: a + 60, to: a + 540, from: 1 }, { at: a + 540, to: b, from: 16.9, rate: 0.01 }]} />;
  const pq = { dx: -380, dy: 140, z: 250, s: 1.32, face: 1 };
  const voiceOn = frame >= VOICE_AT && frame < VOICE_AT + 200;
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12) }}>
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={screen}>
            <Tap frame={frame} at={a + 75} nx={0.43} ny={0.63} />
            <Tap frame={frame} at={a + 135} nx={0.5} ny={0.26} />
            {/* 題目拉出 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.105, w: 0.96, h: 0.1 }} pose={pose} radius={14} keys={[{ f: a + 100 }, { f: a + 118, ...pq }, { f: a + 230, ...pq }, { f: a + 246 }]}>
              {screen}
            </PullOut>
            <Tap frame={frame} at={a + 420} nx={0.5} ny={0.94} />
          </Phone3D>
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 20} end={a + 95} x={150} y={300} eyebrow="每日一問" lines={["每天一個", "回憶小問題"]} />
      {voiceOn && (
        <div style={{ position: "absolute", left: 220, top: 470, width: 340 }}>
          <Waveform frame={frame} />
          <div style={{ marginTop: 12, textAlign: "center", fontFamily: FONT, fontSize: 28, fontWeight: 700, color: C.muted }}>阿嬤的原聲</div>
        </div>
      )}
      <Headline frame={frame} start={a + 470} x={150} y={300} eyebrow="原聲保存" lines={["阿嬤的故事，", "送到家人手上"]} />
    </AbsoluteFill>
  );
};

// ============ C 回憶錄：家屬回覆（q_family） ============
// 片內：0–1 回憶錄列表、2 點開、可播放原聲、3–6 打字「明天煮給你吃」、7 送出、悄悄話 (1)
const FamilyScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.c, b = T.end;
  if (frame < a || frame > b) return null;
  const enter = spring({ frame: frame - a, fps: FPS, config: { damping: 20 } });
  const drift = interpolate(frame, [a, b], [0, 1]);
  const pose: Pose = { ...HOME, x: HOME.x + (1 - enter) * 600, ry: HOME.ry - (1 - enter) * 30 + drift * 6, rz: HOME.rz - drift };
  const screen = <DemoClip src="q_family" segs={[{ at: a, to: a + 90, from: 0, rate: 0.4 }, { at: a + 90, to: a + 420, from: 1.2, rate: 0.7 }, { at: a + 420, to: b, from: 9.0, rate: 0.01 }]} />;
  const pa = { dx: -380, dy: 40, z: 250, s: 1.32, face: 1 };
  const pr = { dx: -380, dy: -60, z: 250, s: 1.4, face: 1 };
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12) }}>
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={screen}>
            <Tap frame={frame} at={a + 80} nx={0.26} ny={0.32} />
            {/* 原聲播放器＋文字回答 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.32, w: 0.96, h: 0.28 }} pose={pose} keys={[{ f: a + 150 }, { f: a + 168, ...pa }, { f: a + 300, ...pa }, { f: a + 316 }]}>
              {screen}
            </PullOut>
            {/* 悄悄話 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.63, w: 0.96, h: 0.1 }} pose={pose} radius={14} keys={[{ f: a + 450 }, { f: a + 468, ...pr }, { f: a + 640, ...pr }, { f: a + 656 }]}>
              {screen}
            </PullOut>
          </Phone3D>
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 20} end={a + 145} x={150} y={300} eyebrow="回憶錄" lines={["聽得到", "媽媽的原聲"]} />
      <Headline frame={frame} start={a + 322} end={a + 446} x={150} y={300} eyebrow="悄悄話" lines={["還能留一句", "話回去"]} />
      <Headline frame={frame} start={a + 680} x={150} y={300} eyebrow="回憶錄" lines={["一本阿嬤的", "回憶錄"]} />
    </AbsoluteFill>
  );
};

export const Ch08: React.FC = () => {
  const frame = useCurrentFrame();
  const music = (f: number) =>
    Math.min(
      interpolate(f, [0, 30, T.end - 40, T.end], [0, 0.2, 0.2, 0], clamp),
      interpolate(f, [VOICE_AT - 20, VOICE_AT, VOICE_AT + 200, VOICE_AT + 240], [0.2, 0, 0, 0.2], clamp),
    );
  return (
    <AbsoluteFill style={{ background: C.light, overflow: "hidden" }}>
      <Backdrop />
      <WallScene frame={frame} />
      <ElderScene frame={frame} />
      <FamilyScene frame={frame} />
      <BackendChips frame={frame} chips={CHIPS} />
      {SHOW_SUBS && <Subtitles frame={frame} subs={SUBS} />}
      <ChapterCard frame={frame} num="08" title="家人的話" />
      <Audio src={staticFile("ad/audio/music.wav")} volume={music} />
      <Sequence from={0} durationInFrames={sec(1.5)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.5} /></Sequence>
      <Sequence from={T.a + 70} durationInFrames={sec(1.5)}><Audio src={staticFile("ad/audio/swipe.wav")} volume={0.4} /></Sequence>
      <Sequence from={T.a + 140} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/pop.wav")} volume={0.35} /></Sequence>
      {/* 呼吸點：長輩原聲（含之後小嘎道謝） */}
      <ClipSound src="q_elder" at={VOICE_AT} from={4.3} dur={381} volume={1} />
      <Sequence from={T.b + 420} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.3} /></Sequence>
      {[T.c + 80, T.b + 75, T.b + 135].map((at, i) => (
        <Sequence key={`p${i}`} from={at} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/pop.wav")} volume={0.35} /></Sequence>
      ))}
      <Sequence from={T.c + 450} durationInFrames={sec(1.5)}><Audio src={staticFile("ad/audio/ding.wav")} volume={0.3} /></Sequence>
    </AbsoluteFill>
  );
};
