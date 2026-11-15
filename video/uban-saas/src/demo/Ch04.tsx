// 第四章：長輩的一天：提醒、打卡與鼓勵（分鏡 05:00–07:30，共 150 秒）
// 主要手法：雙機對話＋飛行光點（打卡變通知、鼓勵飛回）；材質：3D 手機＋實機錄影
// 錄影：06_用藥提醒打卡（長輩機，20:00 服用高血壓藥）、13_打卡鼓勵_1（家屬機）、13_打卡鼓勵_2（長輩機）
// 待補錄：主動關懷卡片（HeartbeatOverlay）、漏打卡通知
import React from "react";
import { AbsoluteFill, Audio, Sequence, interpolate, spring, staticFile, useCurrentFrame } from "remotion";
import { BackendChips, ChapterCard, Chip, COLORS as C, FONT, FPS, MONO, Sub, Subtitles, clamp, ease, sec } from "./common";
import { Backdrop, ClipSound, DemoClip, FlyDot, Headline, Placeholder, Tag, pop, vis } from "./scene";
import { Phone3D, PhoneAt, Pose, PullOut, Stage, Tap } from "../kit";
import { kf, Waveform } from "../ChatFeature";

const SHOW_SUBS = true;
const T = { a: 0, b: sec(25), c: sec(48), d: sec(80), e: sec(112), f: sec(134), end: sec(150) };
export const CH04_FRAMES = T.end;

const HOME: Pose = { x: 250, y: 6, ry: -14, rx: 4, rz: 1, s: 0.94 };
const LEFT: Pose = { x: -330, y: 60, ry: 12, rx: 3, rz: -1, s: 0.78 };
const RIGHT: Pose = { x: 330, y: 60, ry: -12, rx: 3, rz: 1, s: 0.78 };
// 雙機時兩支手機螢幕中心在畫面上的位置（飛行光點用）
const LX = 960 + LEFT.x, RX = 960 + RIGHT.x, MY = 540 + LEFT.y;

const SUBS: Sub[] = [
  { from: sec(1.7), to: sec(7.5), text: "這是阿嬤手機的首頁。字很大，重要的事情一眼看完。" },
  { from: sec(8), to: sec(15.5), text: "今天幾號、星期幾、農曆幾號、天氣和降雨，都在最上面這張卡。" },
  { from: sec(16), to: sec(24.5), text: "下面是今天要做的事，做完一件，就勾掉一件。" },
  { from: sec(25.5), to: sec(32), text: "不用阿嬤開口，小嘎也會主動問候。" },
  { from: sec(32.4), to: sec(40), text: "這則關懷除了唸出來，也會留在首頁和聊天紀錄裡——" },
  { from: sec(40.3), to: sec(47.5), text: "就算阿嬤剛好沒聽到，回來還看得到。" },
  { from: sec(48.5), to: sec(54.5), text: "晚上八點，吃藥時間到了。" },
  { from: sec(55), to: sec(63), text: "手機會響、會把提醒唸出來，" },
  { from: sec(63.4), to: sec(71), text: "阿嬤只要按一個大按鈕，就完成打卡。" },
  { from: sec(71.5), to: sec(79.5), text: "沒空的話按「稍後提醒」，過一會兒會再提醒一次。" },
  { from: sec(80.5), to: sec(87), text: "同一時間，家人的手機也知道了。" },
  { from: sec(87.4), to: sec(93.2), text: "這是一般關心等級的通知，不會像警報一樣大聲響。" },
  { from: sec(93.5), to: sec(98.4), text: "點開今日打卡，哪一項幾點完成，看得清清楚楚。" },
  { from: sec(98.8), to: sec(105.5), text: "家人順手按住麥克風，錄一句鼓勵，" },
  { from: sec(105.8), to: sec(111.5), text: "按下送出，就飛回阿嬤的手機。" },
  { from: sec(112.5), to: sec(119), text: "阿嬤的手機馬上跳出：家人傳了一段語音給您。" },
  { from: sec(119.4), to: sec(126), text: "語音也留在聊天紀錄，想聽幾次都可以。" },
  { from: sec(126.4), to: sec(133.5), text: "阿嬤聽到的不是機器人，是家人真正的聲音。" },
  { from: sec(136.5), to: sec(142.5), text: "如果過了半小時還沒打卡，系統會溫和地告訴家人，" },
  { from: sec(142.8), to: sec(149.6), text: "而且同一件事只提醒一次，不會一直轟炸。" },
];

const CHIPS: Chip[] = [
  { from: sec(9), to: sec(17), text: "天氣：手機座標 → 行政區（CWA / Open-Meteo）" },
  { from: sec(27), to: sec(37), text: "heartbeat_job · 每分鐘巡檢" },
  { from: sec(29), to: sec(37), text: "Socket heartbeat-message" },
  { from: sec(37), to: sec(47), text: "care_message_store · 留存最近 30 則" },
  { from: sec(50), to: sec(60), text: "check_remote_reminders_job · 每分鐘" },
  { from: sec(66), to: sec(78), text: "POST /api/reminder/{id}/complete" },
  { from: sec(68), to: sec(78), text: "reminder_completion（冪等）→ reminder-sync" },
  { from: sec(82), to: sec(94), text: "checkin_dispatcher → Socket elder-checkin" },
  { from: sec(85), to: sec(94), text: "App 關著 → FCM normal · ttl 6h" },
  { from: sec(104), to: sec(116), text: "POST /api/checkin_cheer · 語音 ≤ 3MB" },
  { from: sec(108), to: sec(118), text: "Socket checkin-cheer → 長輩房間" },
  { from: sec(137), to: sec(149.5), text: "checkin_missed_job · 每 5 分鐘" },
  { from: sec(140), to: sec(149.5), text: "checkin_missed_alert UNIQUE 去重" },
];

// ============ A 首頁 ============
// med 片內 0–21 秒是靜止的首頁（19:59），放慢當停格
const HomeScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.a, b = T.b;
  if (frame < a || frame > b) return null;
  const rise = 60;
  // 俯衝：從正上方看平躺的手機，慢慢抬起
  const pose: Pose = { ...HOME, y: kf(frame, [[a, HOME.y + 200], [a + rise, HOME.y]]), rx: kf(frame, [[a, 70], [a + rise, HOME.rx]]), s: (HOME.s ?? 1) * kf(frame, [[a, 0.75], [a + rise, 1]]) };
  const screen = <DemoClip src="med" segs={[{ at: a, to: b, from: 1, rate: 0.6 }]} />;
  const pa = { dx: -340, dy: 120, z: 250, s: 1.35, face: 1 };
  const pb = { dx: -340, dy: 40, z: 250, s: 1.35, face: 1 };
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12) }}>
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={screen}>
            {/* 「今天」卡 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.16, w: 0.96, h: 0.215 }} pose={pose} keys={[{ f: a + 230 }, { f: a + 250, ...pa }, { f: a + 440, ...pa }, { f: a + 458 }]}>
              {screen}
            </PullOut>
            {/* 「今天要做的事」卡 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.38, w: 0.96, h: 0.16 }} pose={pose} keys={[{ f: a + 470 }, { f: a + 490, ...pb }, { f: a + 700, ...pb }, { f: a + 718 }]}>
              {screen}
            </PullOut>
          </Phone3D>
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 52} end={a + 225} x={150} y={300} eyebrow="長輩首頁" lines={["字很大，", "一眼看完"]} note="首頁只放長輩每天真正需要的東西" />
    </AbsoluteFill>
  );
};

// ============ B 主動關懷（待補錄） ============
const CARE = "阿嬤，今天天氣不錯，要不要出去走走？記得多喝水喔！";
const CareScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.b, b = T.c;
  if (frame < a || frame > b) return null;
  const enter = spring({ frame: frame - a, fps: FPS, config: { damping: 20 } });
  const pose: Pose = { ...HOME, x: HOME.x + 120, ry: -20 - (1 - enter) * 20, y: HOME.y + (1 - enter) * 200 };
  const card = pop(frame, a + 60);
  const n = Math.floor(interpolate(frame, [a + 80, a + 260], [0, CARE.length], clamp));
  const breathe = 0.5 + 0.5 * Math.sin((frame - a) / 12);
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12), fontFamily: FONT }}>
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={<Placeholder frame={frame} title="首頁浮出主動關懷卡片" lines={["HeartbeatOverlay＋小嘎朗讀", "聊天分頁接成小嘎的一則訊息"]} />} />
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 10} x={150} y={150} eyebrow="主動關懷" lines={["不用開口，", "小嘎先問候"]} size={64} />
      {/* 關懷泡泡（示意） */}
      <div style={{ position: "absolute", left: 150, top: 520, width: 700, padding: "30px 36px", borderRadius: 34, background: "#fff", opacity: card, transform: `translateY(${(1 - card) * 30}px)`, boxShadow: `0 18px 44px rgba(28,41,37,0.10), 0 0 0 ${4 + breathe * 10}px rgba(89,178,148,${0.18 + breathe * 0.12})` }}>
        <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
          <div style={{ width: 52, height: 52, borderRadius: "50%", background: C.brand, display: "grid", placeItems: "center", color: "#fff", fontSize: 28, fontWeight: 800 }}>嘎</div>
          <div style={{ fontSize: 26, fontWeight: 800, color: C.brandDeep }}>小嘎 · 主動關懷</div>
          <div style={{ marginLeft: "auto", width: 150 }}><Waveform frame={frame < a + 270 ? frame : 3} /></div>
        </div>
        <div style={{ marginTop: 18, fontSize: 38, lineHeight: 1.5, fontWeight: 700, color: C.ink, minHeight: 114 }}>{CARE.slice(0, n)}</div>
      </div>
      <Tag frame={frame} at={a + 300} x={150} y={790} text="唸出來" />
      <Tag frame={frame} at={a + 330} x={330} y={790} text="留在首頁" />
      <Tag frame={frame} at={a + 360} x={540} y={790} text="接進聊天" />
    </AbsoluteFill>
  );
};

// ============ C 吃藥提醒與打卡 ============
// med 片內：21.5 跳出用藥提醒、23–28.8 提醒音與朗讀、30.7 按「我做好了！打卡」、32 完成提示、33.5 清單 1/1
const REM_SEGS = (a: number) => [
  { at: a, to: a + 60, from: 19.5 },
  { at: a + 60, to: a + 460, from: 21.5, rate: 0.75 },
  { at: a + 460, to: a + 960, from: 31.5, rate: 0.15 },
];
const RemindScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.c, b = T.d;
  if (frame < a || frame > b) return null;
  const enter = spring({ frame: frame - a, fps: FPS, config: { damping: 20 } });
  const drift = interpolate(frame, [a, b], [0, 1]);
  const pose: Pose = { ...HOME, x: HOME.x - (1 - enter) * 500, ry: HOME.ry + (1 - enter) * 30 + drift * 5, s: (HOME.s ?? 1) + drift * 0.04 };
  const screen = <DemoClip src="med" segs={REM_SEGS(a)} />;
  // 片內 30.7 秒按下 → 時間軸 a+60+(30.7-21.5)/0.75*30 ≈ a+428
  const tapAt = a + 428;
  const pp = { dx: -330, dy: 290, z: 260, s: 1.25, face: 1 };
  const shrink = interpolate(frame, [tapAt, tapAt + 4, tapAt + 10], [1, 0.9, 1], clamp);
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12) }}>
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={screen}>
            {/* 用藥提醒卡拉出放大，按下時縮一下 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.38, w: 0.96, h: 0.265 }} pose={pose} keys={[{ f: a + 120 }, { f: a + 140, ...pp }, { f: tapAt - 4, ...pp }, { f: tapAt + 6, ...pp, s: pp.s * shrink }, { f: tapAt + 14, ...pp }, { f: tapAt + 30 }]}>
              {screen}
            </PullOut>
            <Tap frame={frame} at={tapAt} nx={0.66} ny={0.6} />
            {/* 完成提示 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.925, w: 0.96, h: 0.06 }} pose={pose} radius={14} keys={[{ f: a + 565 }, { f: a + 583, dx: -40, dy: -380, z: 300, s: 1.3, face: 1 }, { f: a + 690, dx: -40, dy: -380, z: 300, s: 1.3, face: 1 }, { f: a + 706 }]}>
              {screen}
            </PullOut>
          </Phone3D>
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 14} end={tapAt + 50} x={150} y={300} eyebrow="用藥提醒" lines={["會響、會說話，", "按一下就打卡"]} />
      <Headline frame={frame} start={tapAt + 50} x={150} y={300} eyebrow="打卡完成" lines={["今天的事", "都做完了"]} note="清單同步更新成 1 / 1 完成" />
    </AbsoluteFill>
  );
};

// ============ D 家屬收到打卡、錄鼓勵（雙機） ============
// cheer2 片內 0–5：長輩首頁 4/4 完成；cheer1 片內 0–1 家屬首頁、1.5 點開今日打卡、3–11 錄鼓勵、11.5 送出
const FamilyScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.d, b = T.e;
  if (frame < a || frame > b) return null;
  const enter = spring({ frame: frame - a, fps: FPS, config: { damping: 20 } });
  const left: Pose = { ...LEFT, x: LEFT.x - (1 - enter) * 500 };
  const right: Pose = { ...RIGHT, x: RIGHT.x + (1 - enter) * 500 };
  const elder = <DemoClip src="cheer2" segs={[{ at: a, to: b, from: 0.5, rate: 0.12 }]} />;
  // 片內 1.0 點進度環、1.5–3 今日打卡清單、3.7 按麥克風、10.5 送出鼓勵
  const fam = <DemoClip src="cheer1" segs={[{ at: a, to: a + 420, from: 0, rate: 0.085 }, { at: a + 420, to: a + 528, from: 1.2, rate: 0.5 }, { at: a + 528, to: a + 774, from: 3 }, { at: a + 774, to: b, from: 11.2, rate: 0.2 }]} />;
  const dot = a + 60;
  const land = dot + 36;
  const pulse = interpolate(frame, [land, land + 16], [1, 0], clamp);
  const famPose: Pose = { ...right, s: (right.s ?? 1) * (frame >= land ? 1 + pulse * 0.04 : 1) };
  const pr = { dx: -60, dy: -40, z: 230, s: 1.45, face: 1 };
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12) }}>
      <Stage>
        <PhoneAt pose={left}>
          <Phone3D frame={frame} screen={elder} />
        </PhoneAt>
        <PhoneAt pose={famPose}>
          <Phone3D frame={frame} screen={fam}>
            {/* 今日打卡進度環 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.34, w: 0.96, h: 0.23 }} pose={famPose} keys={[{ f: land + 20 }, { f: land + 40, ...pr }, { f: a + 300, ...pr }, { f: a + 318 }]}>
              {fam}
            </PullOut>
            <Tap frame={frame} at={a + 412} nx={0.18} ny={0.46} />
            <Tap frame={frame} at={a + 549} nx={0.5} ny={0.79} />
            <Tap frame={frame} at={a + 753} nx={0.5} ny={0.94} />
          </Phone3D>
        </PhoneAt>
      </Stage>
      <FlyDot frame={frame} at={dot} dur={36} arc={{ x0: LX + 40, y0: MY - 120, x1: RX - 40, y1: MY - 160, lift: 160 }} />
      <Headline frame={frame} start={a + 14} end={a + 530} x={960} y={50} center width={1400} lines={["打卡的那一刻，家人也知道了"]} size={56} />
      <Headline frame={frame} start={a + 530} x={960} y={50} center width={1400} lines={["順手錄一句鼓勵"]} size={56} />
      <Tag frame={frame} at={a + 30} x={LX - 70} y={950} text="長輩" />
      <Tag frame={frame} at={a + 34} x={RX - 70} y={950} text="家人" />
    </AbsoluteFill>
  );
};

// ============ E 鼓勵送回長輩機 ============
// cheer2 片內 5–6.2 跳出家人留言、6.2–8.2 朗讀、9 進聊天、12.96 起播放家人的聲音
const CheerBackScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.e, b = T.f;
  if (frame < a || frame > b) return null;
  const elder = <DemoClip src="cheer2" segs={[{ at: a, to: a + 40, from: 4.2 }, { at: a + 40, to: a + 330, from: 5.5, rate: 0.6 }, { at: a + 330, to: b, from: 11.3, rate: 0.85 }]} />;
  const fam = <DemoClip src="cheer1" segs={[{ at: a, to: b, from: 12.4, rate: 0.03 }]} />;
  const dot = a + 4;
  const land = dot + 34;
  const pulse = interpolate(frame, [land, land + 16], [1, 0], clamp);
  const zoom = interpolate(frame, [a + 40, a + 120], [0, 1], { ...clamp, easing: ease });
  // 鏡頭推向長輩機
  const left: Pose = { ...LEFT, x: LEFT.x + zoom * 200, ry: LEFT.ry - zoom * 4, s: (LEFT.s ?? 1) * (1 + zoom * 0.18 + (frame >= land ? pulse * 0.04 : 0)) };
  const right: Pose = { ...RIGHT, x: RIGHT.x + zoom * 950, z: -zoom * 300 };
  const voiceOn = frame >= a + 388 && frame <= a + 455;
  const pl = { dx: 360, dy: -80, z: 240, s: 1.3, face: 1 };
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12) }}>
      <Stage>
        <PhoneAt pose={right}>
          <Phone3D frame={frame} screen={fam} dim={zoom * 0.5} />
        </PhoneAt>
        <PhoneAt pose={left}>
          <Phone3D frame={frame} screen={elder}>
            {/* 家人留言卡拉出 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.31, w: 0.96, h: 0.37 }} pose={left} keys={[{ f: a + 70 }, { f: a + 90, ...pl }, { f: a + 300, ...pl }, { f: a + 318 }]}>
              {elder}
            </PullOut>
          </Phone3D>
        </PhoneAt>
      </Stage>
      <FlyDot frame={frame} at={dot} dur={34} arc={{ x0: RX - 40, y0: MY - 160, x1: LX + 40, y1: MY - 120, lift: 160 }} color={C.warm} />
      <Headline frame={frame} start={a + 330} x={1080} y={330} width={700} eyebrow="家人的聲音" lines={["不是機器人，", "是家人親口說的"]} size={64} />
      {frame >= a + 360 && (
        <div style={{ position: "absolute", left: 1080, top: 640, width: 260, opacity: voiceOn ? 1 : 0.3 }}>
          <Waveform frame={voiceOn ? frame : 3} />
        </div>
      )}
    </AbsoluteFill>
  );
};

// ============ F 漏打卡（待補錄）＋呼吸點 ============
const MissScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.f, b = T.end;
  if (frame < a || frame > b) return null;
  // 前 2 秒安靜停住，再讓時鐘快轉 30 分鐘
  const spin = interpolate(frame, [a + 70, a + 190], [0, 1], { ...clamp, easing: ease });
  const minute = 30 * spin;
  const hourAng = 240 + (12 + minute) * 0.5; // 20:12 → 20:42
  const minAng = (12 + minute) * 6;
  const card = pop(frame, a + 200);
  const pose: Pose = { ...HOME, x: HOME.x + 140, ry: -18 };
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12), fontFamily: FONT }}>
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={<Placeholder frame={frame} title="家屬收到漏打卡通知" lines={["「阿嬤還沒完成：飯後吃藥」", "提醒時間過 30 分鐘才通知"]} />} />
        </PhoneAt>
      </Stage>
      <svg width={360} height={360} viewBox="-180 -180 360 360" style={{ position: "absolute", left: 250, top: 230 }}>
        <circle r="160" fill="#fff" stroke="#D5E2DC" strokeWidth="8" />
        <path d={`M0 0 L0 -160 A160 160 0 ${spin > 0.5 ? 1 : 0} 1 ${160 * Math.sin(Math.PI * spin)} ${-160 * Math.cos(Math.PI * spin)} Z`} fill="rgba(242,184,128,0.35)" />
        {Array.from({ length: 12 }).map((_, i) => (
          <line key={i} x1="0" y1="-140" x2="0" y2="-124" stroke={C.muted} strokeWidth="6" strokeLinecap="round" transform={`rotate(${i * 30})`} />
        ))}
        <line x1="0" y1="0" x2="0" y2="-78" stroke={C.ink} strokeWidth="12" strokeLinecap="round" transform={`rotate(${hourAng})`} />
        <line x1="0" y1="0" x2="0" y2="-118" stroke={C.brandDeep} strokeWidth="8" strokeLinecap="round" transform={`rotate(${minAng})`} />
        <circle r="12" fill={C.ink} />
      </svg>
      <div style={{ position: "absolute", left: 150, top: 640, width: 560, textAlign: "center", fontFamily: MONO, fontSize: 44, fontWeight: 800, color: C.ink }}>+{Math.round(minute)} 分鐘</div>
      <div style={{ position: "absolute", left: 150, top: 730, width: 560, padding: "18px 26px", boxSizing: "border-box", borderRadius: 24, background: "#fff", boxShadow: "0 12px 30px rgba(28,41,37,0.10)", opacity: card, transform: `translateY(${(1 - card) * 20}px)`, fontSize: 30, fontWeight: 700, color: C.ink, textAlign: "center" }}>
        溫和提醒家人 · <span style={{ color: C.brandDeep }}>同一則只通知一次</span>
      </div>
    </AbsoluteFill>
  );
};

export const Ch04: React.FC = () => {
  const frame = useCurrentFrame();
  const tapAt = T.c + 428;
  return (
    <AbsoluteFill style={{ background: C.light, overflow: "hidden" }}>
      <Backdrop />
      <HomeScene frame={frame} />
      <CareScene frame={frame} />
      <RemindScene frame={frame} />
      <FamilyScene frame={frame} />
      <CheerBackScene frame={frame} />
      <MissScene frame={frame} />
      <BackendChips frame={frame} chips={CHIPS} />
      {SHOW_SUBS && <Subtitles frame={frame} subs={SUBS} />}
      <ChapterCard frame={frame} num="04" title="提醒與打卡" />
      {/* 配樂：提醒原聲、家人聲音、呼吸點時退開 */}
      <Audio
        src={staticFile("ad/audio/music.wav")}
        volume={(f) =>
          interpolate(f, [0, 30, T.c + 80, T.c + 100, T.c + 260, T.c + 280, T.e + 360, T.e + 380, T.f - 10, T.f + 10, T.f + 190, T.f + 230, T.end - 20, T.end], [0, 0.2, 0.2, 0.06, 0.06, 0.2, 0.2, 0.05, 0.05, 0, 0, 0.14, 0.14, 0], clamp)
        }
      />
      <Sequence from={0} durationInFrames={sec(1.5)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.5} /></Sequence>
      {[T.a + 230, T.a + 470, T.c + 120, T.e + 70].map((at, i) => (
        <Sequence key={`w${i}`} from={at} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.28} /></Sequence>
      ))}
      {/* 長輩機原聲：用藥提醒音與朗讀（片內 23–28.8 秒，放慢段落外用原速播放） */}
      <ClipSound src="med" at={T.c + 120} from={23} dur={sec(5.9)} volume={0.9} />
      <Sequence from={tapAt} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/ding.wav")} volume={0.35} /></Sequence>
      <Sequence from={T.d + 60} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.35} /></Sequence>
      <Sequence from={T.d + 96} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/pop.wav")} volume={0.35} /></Sequence>
      <Sequence from={T.e + 4} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.35} /></Sequence>
      {/* 長輩機原聲：朗讀家人留言、播放家人的語音 */}
      <ClipSound src="cheer2" at={T.e + 75} from={6.1} dur={sec(2.2)} volume={0.9} />
      <ClipSound src="cheer2" at={T.e + 388} from={12.9} dur={sec(2.1)} volume={1} />
      {/* 呼吸點後的時鐘快轉 */}
      {Array.from({ length: 12 }).map((_, i) => (
        <Sequence key={`k${i}`} from={T.f + 70 + i * 10} durationInFrames={sec(0.5)}><Audio src={staticFile("ad/audio/tick.wav")} volume={0.3} /></Sequence>
      ))}
      <Sequence from={T.f + 200} durationInFrames={sec(2)}><Audio src={staticFile("ad/audio/ding.wav")} volume={0.25} /></Sequence>
    </AbsoluteFill>
  );
};
