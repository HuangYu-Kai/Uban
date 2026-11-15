// 第十章：視訊通話：按一下就看到家人（分鏡 20:00–21:45，本版 72 秒）
// 主要手法：雙機同步（同一通電話的兩端錄影）＋數字跳動；材質：3D 手機＋實機錄影
// 錄影：09_視訊_1（家屬端撥出）、09_視訊_2（長輩端接聽），兩支是同一通電話，時間軸大致對齊
// 待補錄：對小嘎說「打給○○」、撥出後馬上掛斷
import React from "react";
import { AbsoluteFill, Audio, Sequence, interpolate, spring, staticFile, useCurrentFrame } from "remotion";
import { BackendChips, ChapterCard, Chip, COLORS as C, FONT, FPS, MONO, Sub, Subtitles, clamp, ease, sec } from "./common";
import { Backdrop, DemoClip, CSeg, Headline, Tag, pop, vis } from "./scene";
import { Phone3D, PhoneAt, Pose, PullOut, Stage, Tap } from "../kit";

const SHOW_SUBS = true;
const T = { a: 0, b: sec(14), c: sec(52), end: sec(72) };
export const CH10_FRAMES = T.end;

const HOME: Pose = { x: 250, y: 6, ry: -14, rx: 4, rz: 1, s: 0.94 };
const LEFT: Pose = { x: -330, y: 40, ry: 12, rx: 3, rz: -1, s: 0.8 };
const RIGHT: Pose = { x: 330, y: 40, ry: -12, rx: 3, rz: 1, s: 0.8 };

const SUBS: Sub[] = [
  { from: sec(1.7), to: sec(7.5), text: "想打給家人，打開「電話」分頁，按一下就好；" },
  { from: sec(7.9), to: sec(13.6), text: "也可以直接跟小嘎說：打給誰。" },
  { from: sec(14.6), to: sec(19.5), text: "反過來，家人按一下視訊通話。" },
  { from: sec(19.9), to: sec(27.5), text: "就算阿嬤的 App 是關著的，手機也會像一般來電一樣響起來。" },
  { from: sec(27.9), to: sec(33), text: "阿嬤按下接聽，畫面就接通了。" },
  { from: sec(33.4), to: sec(41.5), text: "信令只在雙方之間點對點轉送；影音則走另一條 UDP 中繼。" },
  { from: sec(41.9), to: sec(51.5), text: "一方掛斷，兩邊同時結束，不會留下一通讓人緊張的未接來電。" },
  { from: sec(52.6), to: sec(58.5), text: "為了讓來電一定接得到，" },
  { from: sec(58.9), to: sec(65), text: "我們前後修了五十多輪：" },
  { from: sec(65.4), to: sec(71.6), text: "從冷啟動、鎖定畫面到重複來電，一層一層補起來。" },
];

const CHIPS: Chip[] = [
  { from: sec(4), to: sec(13.5), text: "「打給 X」→ _dial_call → initiate_video_call" },
  { from: sec(16), to: sec(27), text: "Socket call-request · callId · 有效 60 秒" },
  { from: sec(20), to: sec(30), text: "App 關著 → FCM 高優先級 → CallKit 響鈴" },
  { from: sec(31), to: sec(42), text: "offer / answer / ice-candidate → 指定對象，不廣播" },
  { from: sec(35), to: sec(42), text: "影音 → Oracle Cloud TURN（UDP）" },
  { from: sec(43), to: sec(51.5), text: "掛斷同步兩端" },
];

// ============ A 長輩端「打電話」分頁（call2 片內 0–5） ============
const DialScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.a, b = T.b;
  if (frame < a || frame > b) return null;
  const drift = interpolate(frame, [a, b], [0, 1]);
  const pose: Pose = { ...HOME, ry: HOME.ry + drift * 8, s: (HOME.s ?? 1) * (1 + drift * 0.05) };
  const screen = <DemoClip src="call2" segs={[{ at: a, to: b, from: 0, rate: 0.3 }]} />;
  const pc = { dx: -380, dy: 220, z: 260, s: 1.45, face: 1 };
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12) }}>
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={screen}>
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.2, w: 0.96, h: 0.21 }} pose={pose} radius={18} keys={[{ f: a + 70 }, { f: a + 90, ...pc }, { f: a + 380, ...pc }, { f: a + 396 }]}>
              {screen}
            </PullOut>
          </Phone3D>
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 52} x={150} y={240} eyebrow="打電話" lines={["按一下，", "就看到家人"]} />
    </AbsoluteFill>
  );
};

// ============ B 同一通電話的兩端 ============
// 兩支錄影共用同一條時間對應，畫面才會同步
// call1（家屬）：1.8 點視訊通話、4.3 選一般視訊通話、5–9 連線中、約 9.5 接通、13.8 掛斷
// call2（長輩）：5 響鈴「來電」、6.5 接聽、7–9 通話建立中、約 9.5 接通、14 通話結束
const CALL_SEGS = (a: number): CSeg[] => [
  { at: a, to: a + 230, from: 0.6, rate: 0.6 }, //   0.6–5.2
  { at: a + 230, to: a + 470, from: 5.2, rate: 0.6 }, // 5.2–10
  { at: a + 470, to: a + 770, from: 10, rate: 0.5 }, // 10–15
  { at: a + 770, to: T.c, from: 15, rate: 0.01 },
];
const at = (a: number, clipT: number) => {
  // 片內秒數 → 場景影格（與 CALL_SEGS 對應）
  if (clipT < 5.2) return a + Math.round(((clipT - 0.6) / 0.6) * 30);
  if (clipT < 10) return a + 230 + Math.round(((clipT - 5.2) / 0.6) * 30);
  return a + 470 + Math.round(((clipT - 10) / 0.5) * 30);
};
const CallScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.b, b = T.c;
  if (frame < a || frame > b) return null;
  const enter = spring({ frame: frame - a, fps: FPS, config: { damping: 20 } });
  const ring = at(a, 5.0), answer = at(a, 6.5), live = at(a, 9.6), hang = at(a, 13.9);
  const shake = frame >= ring && frame < answer ? Math.sin(frame * 1.6) * 1.6 : 0;
  const left: Pose = { ...LEFT, x: LEFT.x - (1 - enter) * 500 };
  const right: Pose = { ...RIGHT, x: RIGHT.x + (1 - enter) * 500, rz: RIGHT.rz + shake };
  const fam = <DemoClip src="call1" segs={CALL_SEGS(a)} />;
  const eld = <DemoClip src="call2" segs={CALL_SEGS(a)} />;
  const LX = 960 + LEFT.x, RX = 960 + RIGHT.x;
  // 接通時兩支手機之間拉出一條線（信令＝綠、影音＝橘）
  const link = interpolate(frame, [live, live + 30], [0, 1], { ...clamp, easing: ease });
  const cut = interpolate(frame, [hang, hang + 12], [1, 0], clamp);
  const pr = { dx: -60, dy: 40, z: 230, s: 1.25, face: 1 };
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12), fontFamily: FONT }}>
      {link > 0 && (
        <svg width={1920} height={1080} style={{ position: "absolute", inset: 0, opacity: cut }}>
          <line x1={LX + 150} y1={420} x2={LX + 150 + (RX - LX - 300) * link} y2={420} stroke={C.brand} strokeWidth="6" strokeDasharray="4 14" strokeLinecap="round" strokeDashoffset={-frame * 2} />
          <line x1={LX + 150} y1={470} x2={LX + 150 + (RX - LX - 300) * link} y2={470} stroke="#E58A4E" strokeWidth="10" strokeLinecap="round" strokeDasharray="26 10" strokeDashoffset={-frame * 5} />
        </svg>
      )}
      {link > 0.6 && (
        <>
          <div style={{ position: "absolute", left: 960 - 80, top: 370, width: 160, textAlign: "center", fontSize: 22, fontWeight: 800, color: C.brandDeep, opacity: cut }}>信令</div>
          <div style={{ position: "absolute", left: 960 - 80, top: 488, width: 160, textAlign: "center", fontSize: 22, fontWeight: 800, color: "#C26A30", opacity: cut }}>影音 UDP</div>
        </>
      )}
      <Stage>
        <PhoneAt pose={left}>
          <Phone3D frame={frame} screen={fam}>
            <Tap frame={frame} at={at(a, 1.8)} nx={0.25} ny={0.19} />
            <Tap frame={frame} at={at(a, 4.3)} nx={0.5} ny={0.82} />
            <Tap frame={frame} at={hang} nx={0.5} ny={0.91} />
          </Phone3D>
        </PhoneAt>
        <PhoneAt pose={right}>
          <Phone3D frame={frame} screen={eld}>
            <Tap frame={frame} at={answer} nx={0.75} ny={0.85} />
            {/* 來電畫面拉出 */}
            <PullOut frame={frame} rect={{ x: 0.04, y: 0.2, w: 0.92, h: 0.42 }} pose={right} keys={[{ f: ring + 6 }, { f: ring + 22, ...pr }, { f: answer - 12, ...pr }, { f: answer }]}>
              {eld}
            </PullOut>
          </Phone3D>
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 14} end={live - 2} x={960} y={40} center width={1400} lines={["App 關著，也會響"]} size={56} />
      <Headline frame={frame} start={live} end={hang} x={960} y={40} center width={1400} lines={["接通了"]} size={56} />
      <Headline frame={frame} start={hang} x={960} y={40} center width={1400} lines={["一方掛斷，兩邊同時結束"]} size={56} />
      <Tag frame={frame} at={a + 30} x={LX - 70} y={960} text="家人" />
      <Tag frame={frame} at={a + 34} x={RX - 70} y={960} text="長輩" />
    </AbsoluteFill>
  );
};

// ============ C 五十多輪 ============
const RoundsScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.c, b = T.end;
  if (frame < a || frame > b) return null;
  const n = Math.round(interpolate(frame, [a + 40, a + 150], [0, 53], { ...clamp, easing: Easing2 }));
  const land = spring({ frame: frame - (a + 150), fps: FPS, config: { damping: 9 } });
  const tags = ["App 被殺掉也能響", "鎖定畫面直接接聽", "來電 60 秒有效", "callId 去重", "冷啟動五層兜底"];
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12), fontFamily: FONT, alignItems: "center" }}>
      <div style={{ position: "absolute", top: 160, fontSize: 40, fontWeight: 800, color: C.muted, opacity: pop(frame, a + 10) }}>通話與來電子系統，前後修正</div>
      <div style={{ position: "absolute", top: 260, display: "flex", alignItems: "baseline", gap: 18, transform: `scale(${1 + land * 0.08 - (frame >= a + 150 ? 0.08 : 0)})` }}>
        <span style={{ fontFamily: MONO, fontSize: 260, fontWeight: 800, color: C.brandDeep, lineHeight: 1 }}>{n}</span>
        <span style={{ fontSize: 80, fontWeight: 800, color: C.ink }}>輪修正</span>
      </div>
      <div style={{ position: "absolute", top: 640, left: 160, right: 160, display: "flex", flexWrap: "wrap", justifyContent: "center", gap: 20 }}>
        {tags.map((s, i) => {
          const t = pop(frame, a + 190 + i * 10);
          return (
            <div key={i} style={{ padding: "14px 30px", borderRadius: 999, background: "#fff", fontSize: 32, fontWeight: 700, color: C.ink, boxShadow: "0 10px 26px rgba(28,41,37,0.08)", opacity: t, transform: `translateY(${(1 - t) * 24}px)`, whiteSpace: "nowrap" }}>
              {s}
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};
const Easing2 = (t: number) => 1 - Math.pow(1 - t, 3);

export const Ch10: React.FC = () => {
  const frame = useCurrentFrame();
  const a = T.b;
  const ring = at(a, 5.0), answer = at(a, 6.5), hang = at(a, 13.9);
  return (
    <AbsoluteFill style={{ background: C.light, overflow: "hidden" }}>
      <Backdrop glowX={960} />
      <DialScene frame={frame} />
      <CallScene frame={frame} />
      <RoundsScene frame={frame} />
      <BackendChips frame={frame} chips={CHIPS} />
      {SHOW_SUBS && <Subtitles frame={frame} subs={SUBS} />}
      <ChapterCard frame={frame} num="10" title="視訊通話" />
      <Audio
        src={staticFile("ad/audio/music.wav")}
        volume={(f) => Math.min(interpolate(f, [0, 30, T.end - 40, T.end], [0, 0.2, 0.2, 0], clamp), interpolate(f, [ring - 10, ring, answer, answer + 20], [0.2, 0.07, 0.07, 0.2], clamp))}
      />
      <Sequence from={0} durationInFrames={sec(1.5)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.5} /></Sequence>
      <Sequence from={T.a + 70} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.28} /></Sequence>
      <Sequence from={a} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/swipe.wav")} volume={0.4} /></Sequence>
      {[at(a, 1.8), at(a, 4.3), answer].map((f, i) => (
        <Sequence key={`p${i}`} from={f} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/pop.wav")} volume={0.4} /></Sequence>
      ))}
      {/* 響鈴（用提示音模擬，接聽那一格切斷） */}
      {Array.from({ length: Math.ceil((answer - ring) / 24) }).map((_, i) => (
        <Sequence key={`r${i}`} from={ring + i * 24} durationInFrames={Math.min(20, answer - (ring + i * 24))}><Audio src={staticFile("ad/audio/ding.wav")} volume={0.3} /></Sequence>
      ))}
      <Sequence from={hang} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/thud.wav")} volume={0.35} /></Sequence>
      {Array.from({ length: 12 }).map((_, i) => (
        <Sequence key={`k${i}`} from={T.c + 40 + i * 9} durationInFrames={sec(0.4)}><Audio src={staticFile("ad/audio/tick.wav")} volume={0.25} /></Sequence>
      ))}
      <Sequence from={T.c + 150} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/thud.wav")} volume={0.5} /></Sequence>
    </AbsoluteFill>
  );
};
