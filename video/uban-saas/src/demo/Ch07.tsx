// 第七章：福氣小豬與全家互動（分鏡 14:00–16:30，本版 100 秒）
// 主要手法：環繞＋數字跳動；材質：3D 手機＋實機錄影＋小豬插畫
// 錄影：08_小豬（餵胡蘿蔔、體重增加、全家一起走、好友排行榜）
// 待補錄：家屬送點心 → 長輩餵食 → 送禮者收到通知；每日吉祥祝賀圖
import React from "react";
import { AbsoluteFill, Audio, Img, Sequence, interpolate, spring, staticFile, useCurrentFrame } from "remotion";
import { BackendChips, ChapterCard, Chip, COLORS as C, FONT, FPS, MONO, Sub, Subtitles, clamp, ease, sec } from "./common";
import { Backdrop, DemoClip, FlyDot, Headline, Placeholder, Tag, pop, vis } from "./scene";
import { Phone3D, PhoneAt, Pose, PullOut, Stage, Tap } from "../kit";
import { kf } from "../ChatFeature";

const SHOW_SUBS = true;
const T = { a: 0, b: sec(30), c: sec(47), d: sec(68), e: sec(87), end: sec(100) };
export const CH07_FRAMES = T.end;

const HOME: Pose = { x: 250, y: 6, ry: -14, rx: 4, rz: 1, s: 0.94 };
const LEFT: Pose = { x: -330, y: 60, ry: 12, rx: 3, rz: -1, s: 0.78 };
const RIGHT: Pose = { x: 330, y: 60, ry: -12, rx: 3, rz: 1, s: 0.78 };

const SUBS: Sub[] = [
  { from: sec(1.7), to: sec(6.6), text: "這是阿嬤的福氣小豬。" },
  { from: sec(7), to: sec(13.5), text: "胡蘿蔔不是買來的，是阿嬤好好吃藥、出門走路賺來的。" },
  { from: sec(13.9), to: sec(19.5), text: "把胡蘿蔔餵給小豬，體重就往上加。" },
  { from: sec(19.9), to: sec(24.6), text: "每打一次卡、或每走五百步，就多一根；" },
  { from: sec(25), to: sec(29.6), text: "一天最多五根。好好照顧自己，小豬就會長大。" },
  { from: sec(30.6), to: sec(36.5), text: "小豬有五個成長階段，" },
  { from: sec(36.9), to: sec(46.5), text: "每一季，大家還會分到不同品種的小豬。" },
  { from: sec(47.6), to: sec(53), text: "家人也能參與：送一顆蘋果過去，" },
  { from: sec(53.4), to: sec(59.5), text: "但要阿嬤親手餵，小豬才會長大。" },
  { from: sec(59.9), to: sec(67.5), text: "餵完之後，送禮的人會收到通知——這是一份來回的心意。" },
  { from: sec(68.6), to: sec(74), text: "全家人的步數加在一起，挑戰每週目標。" },
  { from: sec(74.4), to: sec(80), text: "子女在外地走的每一步，也在陪爸媽一起努力；" },
  { from: sec(80.4), to: sec(86.6), text: "達標了，小豬會得到一份全家一起贏來的番薯。" },
  { from: sec(87.6), to: sec(93.5), text: "阿嬤還能和朋友比一比，誰的小豬養得好——" },
  { from: sec(93.9), to: sec(99.6), text: "多一個每天出門走走的理由。" },
];

const CHIPS: Chip[] = [
  { from: sec(14), to: sec(24), text: "POST /api/pet/feed · client_event_id 冪等" },
  { from: sec(16), to: sec(24), text: "伺服器原子累加，體重以後端為準" },
  { from: sec(20), to: sec(29.5), text: "打卡或 500 步 +1 根 · 每日上限 5 根" },
  { from: sec(32), to: sec(46.5), text: "GET /api/pet/state · /thresholds" },
  { from: sec(37), to: sec(46.5), text: "賽季豬種池 → pet_skin.breed_key" },
  { from: sec(50), to: sec(59), text: "POST /api/pet_gift · 每位家屬每天 1 份" },
  { from: sec(58), to: sec(67.5), text: "pet-gift-fed → 只通知送禮者" },
  { from: sec(70), to: sec(86.5), text: "POST /api/step_challenge/family_steps" },
  { from: sec(78), to: sec(86.5), text: "過半推播 · 達標發番薯（一週一次）" },
  { from: sec(89), to: sec(99.5), text: "GET /api/pet/leaderboard/{elder_id}" },
];

// 08_小豬 片內：0–1 胡蘿蔔徽章、1 餵食、約 2 體重 1.61→1.65、4–6 愛心＋「小豬吃得好開心！」
const PIG_SEGS = (a: number, b: number) => [
  { at: a, to: a + 120, from: 0, rate: 0.25 },
  { at: a + 120, to: a + 270, from: 1, rate: 0.5 },
  { at: a + 270, to: b, from: 3.5, rate: 0.12 },
];

// ============ A 小豬分頁 ============
const PigScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.a, b = T.b;
  if (frame < a || frame > b) return null;
  // 環繞：從側面轉進來，看得到機身厚度
  const orbit = interpolate(frame, [a, a + 110], [0, 1], { ...clamp, easing: ease });
  const pose: Pose = { ...HOME, ry: HOME.ry - 62 * (1 - orbit), x: HOME.x + 60 * (1 - orbit), rz: HOME.rz + 3 * (1 - orbit) };
  const screen = <DemoClip src="pig" segs={PIG_SEGS(a, b)} />;
  const pl = { dx: -360, dy: 120, z: 250, s: 1.5, face: 1 };
  const pt = { dx: -40, dy: -390, z: 300, s: 1.3, face: 1 };
  const pb = { dx: -360, dy: 160, z: 250, s: 1.45, face: 1 };
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12) }}>
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={screen}>
            <Tap frame={frame} at={a + 112} nx={0.87} ny={0.3} />
            {/* 體重卡：1.61 → 1.65 公斤 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.57, w: 0.96, h: 0.11 }} pose={pose} radius={16} keys={[{ f: a + 140 }, { f: a + 158, ...pl }, { f: a + 330, ...pl }, { f: a + 346 }]}>
              {screen}
            </PullOut>
            {/* 「小豬吃得好開心！」 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.875, w: 0.96, h: 0.075 }} pose={pose} radius={16} keys={[{ f: a + 520 }, { f: a + 538, ...pt }, { f: a + 660, ...pt }, { f: a + 676 }]}>
              {screen}
            </PullOut>
            {/* 「再走 487 步，或打一次卡，就多 1 根」 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.355, w: 0.96, h: 0.06 }} pose={pose} radius={14} keys={[{ f: a + 690 }, { f: a + 708, ...pb }, { f: a + 870, ...pb }, { f: a + 886 }]}>
              {screen}
            </PullOut>
          </Phone3D>
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 50} end={a + 515} x={150} y={300} eyebrow="福氣小豬" lines={["胡蘿蔔，", "是自己賺來的"]} />
      <Headline frame={frame} start={a + 515} x={150} y={300} eyebrow="照顧自己" lines={["好好照顧自己，", "小豬就長大"]} />
    </AbsoluteFill>
  );
};

// ============ B 五個成長階段 ============
const StageScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.b, b = T.c;
  if (frame < a || frame > b) return null;
  const sizes = [150, 190, 230, 270, 320];
  const line = interpolate(frame, [a + 30, a + 30 + 4 * 16 + 20], [0, 1], { ...clamp, easing: ease });
  const shine = interpolate(frame, [a + 30 + 4 * 16, a + 30 + 4 * 16 + 30], [0, 1], clamp);
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12), fontFamily: FONT }}>
      <Headline frame={frame} start={a + 8} x={960} y={110} center width={1400} eyebrow="成長階段" lines={["五個階段，一季一個品種"]} size={64} />
      <div style={{ position: "absolute", left: 260, top: 812, width: 1400, height: 6, borderRadius: 3, background: "#CBD8D2", transformOrigin: "0 50%", transform: `scaleX(${line})` }} />
      <div style={{ position: "absolute", left: 220, right: 220, top: 300, height: 520, display: "flex", alignItems: "flex-end", justifyContent: "space-between" }}>
        {sizes.map((s, i) => {
          const at = a + 30 + i * 16;
          const t = spring({ frame: frame - at, fps: FPS, config: { damping: 11 } });
          return (
            <div key={i} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 10, opacity: Math.min(1, t * 2) }}>
              <div style={{ position: "relative" }}>
                {i === 4 && <div style={{ position: "absolute", inset: -40, borderRadius: "50%", background: "radial-gradient(circle, rgba(242,184,128,0.55) 0%, rgba(242,184,128,0) 65%)", opacity: shine }} />}
                <Img src={staticFile(`ad/pig/pig_stage_${i + 1}.png`)} style={{ position: "relative", width: s, height: s, objectFit: "contain", transform: `translateY(${(1 - t) * 60}px) scale(${0.6 + t * 0.4})` }} />
              </div>
              <div style={{ fontFamily: MONO, fontSize: 30, fontWeight: 800, color: C.brandDeep, marginTop: 16 }}>第 {i + 1} 階</div>
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

// ============ C 家屬送點心（待補錄） ============
const Apple: React.FC<{ size?: number }> = ({ size = 70 }) => (
  <svg width={size} height={size} viewBox="0 0 70 70">
    <path d="M35 20 C25 10 6 14 8 34 C10 54 24 64 35 58 C46 64 60 54 62 34 C64 14 45 10 35 20 Z" fill="#E4574B" />
    <path d="M35 20 C35 12 38 6 44 4" stroke="#6B4A2B" strokeWidth="4" fill="none" strokeLinecap="round" />
    <path d="M38 12 C46 4 56 8 56 8 C52 16 44 16 38 12 Z" fill="#59B294" />
  </svg>
);
const GiftScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.c, b = T.d;
  if (frame < a || frame > b) return null;
  const enter = spring({ frame: frame - a, fps: FPS, config: { damping: 20 } });
  const left: Pose = { ...LEFT, x: LEFT.x - (1 - enter) * 500 };
  const right: Pose = { ...RIGHT, x: RIGHT.x + (1 - enter) * 500 };
  const LX = 960 + LEFT.x, RX = 960 + RIGHT.x, MY = 540 + LEFT.y;
  const go = a + 90, dur = 50;
  const t = Math.max(0, Math.min(1, (frame - go) / dur));
  const e = ease(t);
  const ax = LX + (RX - LX) * e, ay = MY - 80 - Math.sin(Math.PI * e) * 220;
  const fed = a + 300;
  const munch = interpolate(frame, [fed, fed + 20], [1, 0], clamp);
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12), fontFamily: FONT }}>
      <Stage>
        <PhoneAt pose={left}>
          <Phone3D frame={frame} screen={<Placeholder frame={frame} title="家屬：送點心給小豬" lines={["互動 → 選蘋果 → 送出", "之後收到「餵給小豬了」"]} />} />
        </PhoneAt>
        <PhoneAt pose={right}>
          <Phone3D frame={frame} screen={<Placeholder frame={frame} title="長輩：收到一顆蘋果" lines={["親手餵給小豬"]} />} />
        </PhoneAt>
      </Stage>
      {frame >= go && frame < fed + 20 && (
        <div style={{ position: "absolute", left: ax - 40, top: ay - 40, transform: `rotate(${e * 360}deg) scale(${frame >= fed ? munch : 1})` }}>
          <Apple size={80} />
        </div>
      )}
      <FlyDot frame={frame} at={fed + 40} dur={46} arc={{ x0: RX, y0: MY - 80, x1: LX, y1: MY - 80, lift: 220 }} color="#E4574B" />
      {frame >= fed + 86 && (
        <div style={{ position: "absolute", left: LX - 50, top: MY - 140, fontSize: 90, color: "#E4574B", transform: `scale(${spring({ frame: frame - fed - 86, fps: FPS, config: { damping: 8 } })})` }}>♥</div>
      )}
      <Headline frame={frame} start={a + 14} x={960} y={50} center width={1400} lines={["一份來回的心意"]} size={56} />
      <Tag frame={frame} at={a + 30} x={LX - 70} y={950} text="家人" />
      <Tag frame={frame} at={a + 34} x={RX - 70} y={950} text="長輩" />
    </AbsoluteFill>
  );
};

// ============ D 全家一起走 ============
const StepsScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.d, b = T.e;
  if (frame < a || frame > b) return null;
  const enter = spring({ frame: frame - a, fps: FPS, config: { damping: 20 } });
  const pose: Pose = { ...HOME, x: HOME.x + 120, ry: -20 - (1 - enter) * 25, y: HOME.y + (1 - enter) * 200 };
  const screen = <DemoClip src="pig" segs={[{ at: a, to: b, from: 5.6, rate: 0.01 }]} />;
  const ps = { dx: -420, dy: -60, z: 260, s: 1.45, face: 1 };
  // 示意：家人與長輩的步數一起累加
  const elder = Math.round(interpolate(frame, [a + 120, a + 260], [0, 110], { ...clamp, easing: ease }));
  const fam = Math.round(interpolate(frame, [a + 140, a + 300], [0, 5900], { ...clamp, easing: ease }));
  const sum = pop(frame, a + 310);
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12), fontFamily: FONT }}>
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={screen}>
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.445, w: 0.96, h: 0.12 }} pose={pose} radius={16} keys={[{ f: a + 60 }, { f: a + 80, ...ps }, { f: b - 30, ...ps }, { f: b - 14 }]}>
              {screen}
            </PullOut>
          </Phone3D>
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 10} x={150} y={130} eyebrow="全家一起走" lines={["步數加在一起"]} size={64} />
      <div style={{ position: "absolute", left: 150, top: 640, display: "flex", gap: 22, alignItems: "center" }}>
        {[["長輩", elder], ["家人", fam]].map(([k, v], i) => (
          <div key={i} style={{ padding: "16px 26px", borderRadius: 24, background: "#fff", boxShadow: "0 10px 26px rgba(28,41,37,0.10)", opacity: pop(frame, a + 110 + i * 10) }}>
            <div style={{ fontSize: 24, color: C.muted, fontWeight: 700 }}>{k}</div>
            <div style={{ fontFamily: MONO, fontSize: 48, fontWeight: 800, color: C.ink }}>{(v as number).toLocaleString()}</div>
          </div>
        ))}
        <div style={{ fontSize: 50, color: C.brand, fontWeight: 900, opacity: sum }}>＝</div>
        <div style={{ padding: "16px 26px", borderRadius: 24, background: C.brand, color: "#fff", opacity: sum, transform: `scale(${0.8 + sum * 0.2})` }}>
          <div style={{ fontSize: 24, fontWeight: 700, opacity: 0.85 }}>本週全家</div>
          <div style={{ fontFamily: MONO, fontSize: 48, fontWeight: 800 }}>6,010</div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

// ============ E 好友排行榜 ============
const BoardScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.e, b = T.end;
  if (frame < a || frame > b) return null;
  const drift = interpolate(frame, [a, b], [0, 1]);
  const pose: Pose = { ...HOME, x: HOME.x + 120, ry: -20 + drift * 8 };
  const screen = <DemoClip src="pig" segs={[{ at: a, to: b, from: 2.4, rate: 0.01 }]} />;
  const pb = { dx: -420, dy: -140, z: 260, s: 1.4, face: 1 };
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12) }}>
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={screen}>
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.705, w: 0.96, h: 0.18 }} pose={pose} radius={18} keys={[{ f: a + 30 }, { f: a + 50, ...pb }, { f: b - 20, ...pb }, { f: b - 4 }]}>
              {screen}
            </PullOut>
          </Phone3D>
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 10} x={150} y={130} eyebrow="好友排行榜" lines={["和朋友比一比"]} size={64} />
    </AbsoluteFill>
  );
};

export const Ch07: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: C.light, overflow: "hidden" }}>
      <Backdrop />
      <PigScene frame={frame} />
      <StageScene frame={frame} />
      <GiftScene frame={frame} />
      <StepsScene frame={frame} />
      <BoardScene frame={frame} />
      <BackendChips frame={frame} chips={CHIPS} />
      {SHOW_SUBS && <Subtitles frame={frame} subs={SUBS} />}
      <ChapterCard frame={frame} num="07" title="福氣小豬" />
      <Audio src={staticFile("ad/audio/music.wav")} volume={(f) => interpolate(f, [0, 30, T.end - 40, T.end], [0, 0.22, 0.22, 0], clamp)} />
      <Sequence from={0} durationInFrames={sec(1.5)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.5} /></Sequence>
      <Sequence from={T.a + 112} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/pop.wav")} volume={0.45} /></Sequence>
      {[T.a + 140, T.a + 520, T.a + 690].map((at, i) => (
        <Sequence key={`w${i}`} from={at} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.28} /></Sequence>
      ))}
      <Sequence from={T.a + 525} durationInFrames={sec(1.5)}><Audio src={staticFile("ad/audio/ding.wav")} volume={0.35} /></Sequence>
      {[0, 1, 2, 3, 4].map((i) => (
        <Sequence key={`s${i}`} from={T.b + 30 + i * 16} durationInFrames={sec(0.6)}><Audio src={staticFile("ad/audio/pop.wav")} volume={0.35} /></Sequence>
      ))}
      <Sequence from={T.b + 30 + 64} durationInFrames={sec(2)}><Audio src={staticFile("pain/chord.wav")} volume={0.3} /></Sequence>
      <Sequence from={T.c + 90} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.35} /></Sequence>
      <Sequence from={T.c + 340} durationInFrames={sec(1.5)}><Audio src={staticFile("ad/audio/ding.wav")} volume={0.3} /></Sequence>
      {Array.from({ length: 10 }).map((_, i) => (
        <Sequence key={`k${i}`} from={T.d + 140 + i * 16} durationInFrames={sec(0.4)}><Audio src={staticFile("ad/audio/tick.wav")} volume={0.22} /></Sequence>
      ))}
      <Sequence from={T.d + 310} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/pop.wav")} volume={0.4} /></Sequence>
      <Sequence from={T.e + 30} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.3} /></Sequence>
    </AbsoluteFill>
  );
};
