// 第五章：和小嘎聊天：一個真的會做事的 AI（分鏡 07:30–11:30，本版 200 秒）
// 主要手法：元件拉出放大＋爆炸圖（記憶）＋放大鏡（藥袋）；材質：3D 手機＋實機錄影
// 錄影：04_小嘎聊天_國語天氣、04_小嘎聊天_台語提醒、05_新聞朗讀、06_用藥提醒打卡（打卡完成畫面）
// 待補錄：長期記憶、拍藥袋、語音打卡、播放音樂；「Hey 嘎蛙」依決定不展示
import React from "react";
import { AbsoluteFill, Audio, Sequence, interpolate, spring, staticFile, useCurrentFrame } from "remotion";
import { BackendChips, ChapterCard, Chip, COLORS as C, FONT, FPS, MONO, Sub, Subtitles, clamp, ease, sec } from "./common";
import { Backdrop, ClipSound, DemoClip, Headline, Placeholder, Tag, pop, vis } from "./scene";
import { Phone3D, PhoneAt, Pose, PullOut, Stage, Tap } from "../kit";
import { kf, Waveform } from "../ChatFeature";

const SHOW_SUBS = true;
const T = { a: 0, b: sec(32), c: sec(54), d: sec(92), e: sec(124), f: sec(158), g: sec(174), end: sec(200) };
export const CH05_FRAMES = T.end;

const HOME: Pose = { x: 250, y: 6, ry: -14, rx: 4, rz: 1, s: 0.94 };

const SUBS: Sub[] = [
  // A 天氣（小嘎朗讀時旁白讓位）
  { from: sec(1.7), to: sec(6.6), text: "阿嬤不用打字，按住說話就好。" },
  { from: sec(7), to: sec(13.6), text: "阿嬤問：今天天氣如何？出門要帶雨傘嗎？" },
  { from: sec(23.5), to: sec(31.6), text: "天氣這類事實，系統會直接查真實的氣象資料，不讓 AI 自己編。" },
  // B 速度
  { from: sec(32.6), to: sec(36), text: "長輩等不了。" },
  { from: sec(36.4), to: sec(44), text: "我們把小嘎的回應時間，從中位數七秒多，壓到一秒左右。" },
  { from: sec(44.4), to: sec(53.5), text: "關掉模型的「思考」、讓系統提示吃到快取，再讓模型隨時保持暖機。" },
  // C 台語＋覆述
  { from: sec(54.6), to: sec(57.8), text: "小嘎會說台語。" },
  { from: sec(66), to: sec(72.5), text: "阿嬤說：明天上午七點，要提醒我吃藥。" },
  { from: sec(72.9), to: sec(80.5), text: "小嘎不會馬上記下，而是先覆述一次，問清楚是只有明天，還是每天都要。" },
  { from: sec(80.9), to: sec(86.5), text: "阿嬤說對了，才真的建立提醒，避免聽錯。" },
  { from: sec(86.9), to: sec(91.6), text: "家人的提醒管理頁，也同步看得到。" },
  // D 記憶
  { from: sec(92.6), to: sec(97), text: "小嘎記得阿嬤說過的話。" },
  { from: sec(97.4), to: sec(104), text: "每一次聊天，都會在背景轉成記憶向量；" },
  { from: sec(104.4), to: sec(111), text: "下次聊到相關的事，它就接得上。" },
  { from: sec(111.4), to: sec(123.5), text: "記憶查不到也不會卡住——超過一秒半，就先往下聊。" },
  // E 藥袋
  { from: sec(124.6), to: sec(130.5), text: "拍一張藥袋，小嘎就能幫阿嬤排好吃藥時間。" },
  { from: sec(130.9), to: sec(135), text: "我們刻意不讓 AI 讀藥名——" },
  { from: sec(135.4), to: sec(141.5), text: "小字容易看錯，錯的藥名比沒有更危險。" },
  { from: sec(141.9), to: sec(149.5), text: "所以只讀：一天幾次、什麼時候吃、一次幾顆。" },
  { from: sec(149.9), to: sec(157.5), text: "小嘎覆述一次，阿嬤說好，三個提醒一次建好。" },
  // F 語音打卡
  { from: sec(158.6), to: sec(165.5), text: "說一句「我中午的藥吃過了」，也算打卡，" },
  { from: sec(165.9), to: sec(173.5), text: "和按按鈕寫進同一份紀錄，家人那邊同步看到。" },
  // G 新聞
  { from: sec(174.6), to: sec(177.8), text: "想聽新聞，點一下就好。" },
  { from: sec(184.5), to: sec(191), text: "小嘎會把今天的頭條，一則一則唸給阿嬤聽；" },
  { from: sec(191.4), to: sec(199.5), text: "新聞每天清晨自動整理，語音也預先合成好，按下去馬上能聽。" },
];

const CHIPS: Chip[] = [
  { from: sec(3), to: sec(10), text: "手機語音辨識 → 文字" },
  { from: sec(9), to: sec(22), text: "POST /api/ai/chat_stream（SSE 串流）" },
  { from: sec(12), to: sec(31), text: "_forced_tool_call → get_weather_info" },
  { from: sec(45), to: sec(53.5), text: "think=False · 前綴快取" },
  { from: sec(47), to: sec(53.5), text: "keep_alive · ollama_keep_warm_job 每 4 分鐘" },
  { from: sec(56), to: sec(66), text: "台語朗讀 · 雅婷 TTS" },
  { from: sec(70), to: sec(82), text: "propose_reminder → 先覆述" },
  { from: sec(81), to: sec(91.5), text: "classify_confirmation → confirm_reminder" },
  { from: sec(97), to: sec(111), text: "背景執行緒 → Pinecone 768 維" },
  { from: sec(104), to: sec(123.5), text: "build_memory_context" },
  { from: sec(111), to: sec(123.5), text: "語意召回逾時 1.5s · fail-open" },
  { from: sec(126), to: sec(140), text: "POST /api/ai/upload_image" },
  { from: sec(131), to: sec(150), text: "medicine_bag_service · 自架 Gemma 4" },
  { from: sec(142), to: sec(157.5), text: "標題一律「吃藥（每次 N 顆）」" },
  { from: sec(160), to: sec(173.5), text: "record_medication_taken → reminder_completion" },
  { from: sec(178), to: sec(190), text: "search_news" },
  { from: sec(184), to: sec(199.5), text: "06:00 爬中央社 · 03:00 預先合成語音" },
];

// ============ A 問天氣（chat_weather） ============
// 片內：0–2 聊天頁、2–6 按住說話、6–9 文字帶入、9 送出、10–15.5 小嘎想想、15.5 回覆、18.6 起朗讀
const WEATHER_SEGS = (a: number) => [
  { at: a, to: a + 60, from: 0 },
  { at: a + 60, to: a + 270, from: 2 },
  { at: a + 270, to: a + 330, from: 9, rate: 3.25 }, // 等待回覆的 6.5 秒快轉
  { at: a + 330, to: a + 960, from: 15.5 },
];
const WeatherScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.a, b = T.b;
  if (frame < a || frame > b) return null;
  // 推近：從遠處滑進來
  const push = interpolate(frame, [a, a + 50], [0, 1], { ...clamp, easing: ease });
  const pose: Pose = { ...HOME, z: -600 * (1 - push), ry: HOME.ry - 25 * (1 - push), rz: HOME.rz + 4 * (1 - push) };
  const screen = <DemoClip src="chat_weather" segs={WEATHER_SEGS(a)} />;
  const pb = { dx: -360, dy: -160, z: 240, s: 1.35, face: 1 };
  const pr = { dx: -380, dy: -60, z: 250, s: 1.42, face: 1 };
  const ff = frame >= a + 270 && frame < a + 330;
  const talk = frame >= a + 60 && frame < a + 180;
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12) }}>
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={screen}>
            {/* 「按住 說話」按鈕拉出 */}
            <PullOut frame={frame} rect={{ x: 0.2, y: 0.765, w: 0.78, h: 0.08 }} pose={pose} radius={20} keys={[{ f: a + 40 }, { f: a + 58, ...pb }, { f: a + 190, ...pb }, { f: a + 206 }]}>
              {screen}
            </PullOut>
            <Tap frame={frame} at={a + 62} nx={0.58} ny={0.8} />
            {/* 小嘎回覆泡泡拉出 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.48, w: 0.7, h: 0.34 }} pose={pose} keys={[{ f: a + 420 }, { f: a + 440, ...pr }, { f: a + 680, ...pr }, { f: a + 698 }]}>
              {screen}
            </PullOut>
          </Phone3D>
        </PhoneAt>
      </Stage>
      {talk && (
        <div style={{ position: "absolute", left: 300, top: 640, width: 300 }}>
          <Waveform frame={frame} />
        </div>
      )}
      {ff && <div style={{ position: "absolute", left: 960 + HOME.x - 70, top: 90, padding: "8px 20px", borderRadius: 999, background: C.ink, color: C.cream, fontFamily: FONT, fontSize: 26, fontWeight: 800 }}>快轉 ▶▶</div>}
      <Headline frame={frame} start={a + 210} end={a + 415} x={150} y={300} eyebrow="和小嘎聊天" lines={["按住說話，", "就問得到"]} />
      <Headline frame={frame} start={a + 700} x={150} y={300} eyebrow="查真實資料" lines={["天氣不用猜，", "直接查"]} note="氣象資料由工具查回，模型只負責說給阿嬤聽" />
    </AbsoluteFill>
  );
};

// ============ B 回應速度 ============
const SpeedScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.b, b = T.c;
  if (frame < a || frame > b) return null;
  const go = a + 100;
  const v = (stop: number) => Math.min(stop, Math.max(0, (frame - go) / 30) * 1.6);
  const oldV = v(7.6), newV = v(1.1);
  const newDone = newV >= 1.1, oldDone = oldV >= 7.6;
  const hit = (done: boolean, at: number) => (done ? spring({ frame: frame - at, fps: FPS, config: { damping: 9 } }) : 0);
  const newAt = go + Math.ceil((1.1 / 1.6) * 30), oldAt = go + Math.ceil((7.6 / 1.6) * 30);
  const row = (label: string, val: number, stop: number, done: boolean, at: number, color: string, y: number) => {
    const t = pop(frame, a + 30 + (y > 500 ? 8 : 0));
    const h = hit(done, at);
    return (
      <div style={{ position: "absolute", left: 260, top: y, width: 1400, opacity: t, transform: `translateY(${(1 - t) * 30}px)` }}>
        <div style={{ fontSize: 34, fontWeight: 800, color: C.muted, marginBottom: 14 }}>{label}</div>
        <div style={{ display: "flex", alignItems: "center", gap: 36 }}>
          <div style={{ width: 1000, height: 46, borderRadius: 23, background: "#E2EBE7", overflow: "hidden" }}>
            <div style={{ width: `${(val / 8) * 100}%`, height: "100%", borderRadius: 23, background: color }} />
          </div>
          <div style={{ fontFamily: MONO, fontSize: 92, fontWeight: 800, color: done ? color : C.ink, transform: `scale(${1 + h * 0.12 - (done ? 0.12 : 0) * (h > 0 ? 1 : 0)})`, minWidth: 300 }}>
            {val.toFixed(1)}<span style={{ fontSize: 44 }}> 秒</span>
          </div>
        </div>
      </div>
    );
  };
  const tips = ["關閉 Gemma「思考」", "系統提示吃前綴快取", "模型常駐預熱"];
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12), fontFamily: FONT }}>
      <Headline frame={frame} start={a + 8} x={960} y={110} center width={1400} eyebrow="回應速度（中位數）" lines={["長輩等不了"]} size={70} />
      {row("改善前", oldV, 7.6, oldDone, oldAt, "#B9A79A", 360)}
      {row("現在", newV, 1.1, newDone, newAt, C.brand, 560)}
      <div style={{ position: "absolute", left: 0, right: 0, top: 790, display: "flex", justifyContent: "center", gap: 24 }}>
        {tips.map((s, i) => {
          const t = pop(frame, a + 330 + i * 12);
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

// ============ C 台語＋覆述提醒（chat_tw） ============
// 片內：台語分頁、「明天上午7點要提醒我吃藥」、小嘎覆述並問是每天還是只有明天；2.2–21 台語朗讀
const TwScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.c, b = T.d;
  if (frame < a || frame > b) return null;
  const enter = spring({ frame: frame - a, fps: FPS, config: { damping: 20 } });
  const drift = interpolate(frame, [a, b], [0, 1]);
  const pose: Pose = { ...HOME, x: HOME.x + (1 - enter) * 600, ry: HOME.ry - (1 - enter) * 30 + drift * 6, rz: HOME.rz - drift, s: (HOME.s ?? 1) + drift * 0.04 };
  const screen = <DemoClip src="chat_tw" segs={[{ at: a, to: a + 90, from: 0, rate: 0.5 }, { at: a + 90, to: a + 693, from: 1.5 }, { at: a + 693, to: b, from: 21.4, rate: 0.005 }]} />;
  const pt = { dx: -300, dy: 200, z: 250, s: 1.7, face: 1 };
  const pr = { dx: -380, dy: 20, z: 250, s: 1.32, face: 1 };
  const ttsOn = frame >= a + 111 && frame < a + 351;
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12) }}>
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={screen}>
            {/* 國語／台語切換 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.125, w: 0.36, h: 0.05 }} pose={pose} radius={14} keys={[{ f: a + 20 }, { f: a + 38, ...pt }, { f: a + 100, ...pt }, { f: a + 116 }]}>
              {screen}
            </PullOut>
            {/* 長輩的話＋小嘎的覆述 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.38, w: 0.96, h: 0.35 }} pose={pose} keys={[{ f: a + 380 }, { f: a + 400, ...pr }, { f: a + 760, ...pr }, { f: a + 778 }]}>
              {screen}
            </PullOut>
          </Phone3D>
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 110} end={a + 375} x={150} y={300} eyebrow="台語朗讀" lines={["小嘎", "會說台語"]} />
      {ttsOn && (
        <div style={{ position: "absolute", left: 150, top: 600, width: 280 }}>
          <Waveform frame={frame} />
        </div>
      )}
      <Headline frame={frame} start={a + 790} x={150} y={300} eyebrow="語音排行程" lines={["先覆述，", "說對了才建立"]} note="提醒建立後，家人的提醒管理頁同步看得到" />
    </AbsoluteFill>
  );
};

// ============ D 長期記憶（爆炸圖示意） ============
const MEMS = ["上週四去南門市場，買了肉粽", "孫子下個月要考試", "最近膝蓋有點痠", "喜歡聽老歌", "女兒住在台中"];
const MemoryScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.d, b = T.e;
  if (frame < a || frame > b) return null;
  const ex = interpolate(frame, [a + 60, a + 140], [0, 1], { ...clamp, easing: ease }); // 爆炸展開
  const orbit = interpolate(frame, [a, b], [0, 1]);
  const pose: Pose = { x: 380, y: 10, ry: -30 - ex * 10 + orbit * 8, rx: 4, rz: 1, s: 0.86 };
  const pick = 0;
  const fly = interpolate(frame, [a + 300, a + 360], [0, 1], { ...clamp, easing: ease });
  const screen = <DemoClip src="chat_weather" segs={[{ at: a, to: b, from: 30, rate: 0.01 }]} />;
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12), fontFamily: FONT }}>
      <Stage>
        {/* 手機後方一層層的記憶卡片 */}
        {MEMS.map((m, i) => {
          // 從手機後方往左展開成一疊，每張往後一層
          const lit = i === pick && frame >= a + 260;
          const isFly = i === pick;
          const x = pose.x + (-560 - i * 36) * ex + (isFly ? fly * 40 : 0);
          const y = pose.y + (-250 + i * 128) * ex;
          const z = -i * 70 * ex - 60 * (1 - ex) + (isFly ? fly * 220 : 0);
          const o = interpolate(frame, [a + 60 + i * 6, a + 90 + i * 6], [0, 1], clamp) * (lit ? 1 : 0.88 - i * 0.1);
          return (
            <div key={i} style={{ position: "absolute", left: -260, top: -60, width: 520, height: 116, borderRadius: 26, background: lit ? "#FFFFFF" : "rgba(255,255,255,0.8)", border: `3px solid ${lit ? C.brand : "rgba(89,178,148,0.35)"}`, boxShadow: lit ? `0 0 50px rgba(89,178,148,0.6)` : "0 10px 30px rgba(28,41,37,0.08)", transform: `translate3d(${x}px,${y}px,${z}px) rotateY(${-12 * (1 - (isFly ? fly : 0))}deg) scale(${1 + (isFly ? fly * 0.12 : 0)})`, opacity: o, padding: "16px 26px", boxSizing: "border-box" }}>
              <div style={{ fontSize: 20, fontWeight: 800, color: C.brandDeep, letterSpacing: 2 }}>記憶 · {["3 天前", "1 週前", "2 週前", "1 個月前", "2 個月前"][i]}</div>
              <div style={{ marginTop: 6, fontSize: 32, fontWeight: 800, color: C.ink, whiteSpace: "nowrap" }}>「{m}」</div>
            </div>
          );
        })}
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={screen} dim={ex * 0.25} />
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 10} x={150} y={80} width={1100} eyebrow="長期記憶" lines={["小嘎記得阿嬤說過的話"]} size={56} />
      <div style={{ position: "absolute", left: 60, top: 40, fontSize: 22, color: C.muted, opacity: 0.8 }}>示意動畫（實機對話待補錄）</div>
    </AbsoluteFill>
  );
};

// ============ E 拍藥袋（示意＋待補錄） ============
const MedBagScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.e, b = T.f;
  if (frame < a || frame > b) return null;
  const bag = pop(frame, a + 10);
  // 放大鏡依序停在三個欄位
  const stops = [
    { at: a + 300, x: 520, y: 600 },
    { at: a + 400, x: 520, y: 700 },
    { at: a + 500, x: 520, y: 800 },
  ];
  const lx = kf(frame, [[a + 200, 900], [stops[0].at - 20, stops[0].x], [stops[1].at - 20, stops[1].x], [stops[2].at - 20, stops[2].x], [a + 560, 980]]);
  const ly = kf(frame, [[a + 200, 380], [stops[0].at - 20, stops[0].y], [stops[0].at + 40, stops[0].y], [stops[1].at - 20, stops[1].y], [stops[1].at + 40, stops[1].y], [stops[2].at - 20, stops[2].y], [stops[2].at + 40, stops[2].y], [a + 560, 380]]);
  const lensO = interpolate(frame, [a + 190, a + 210, a + 560, a + 580], [0, 1, 1, 0], clamp);
  const maskT = pop(frame, a + 120);
  const result = pop(frame, a + 780);
  const pose: Pose = { ...HOME, x: 520, ry: -22 };
  const fields = [
    { k: "用法", v: "一天三次" },
    { k: "時間", v: "三餐飯後" },
    { k: "每次", v: "1 顆" },
  ];
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12), fontFamily: FONT }}>
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={<Placeholder frame={frame} title="拍藥袋傳給小嘎" lines={["小嘎覆述吃藥時間", "阿嬤說「好」→ 建立提醒"]} />} />
        </PhoneAt>
      </Stage>
      {/* 藥袋（示意圖） */}
      <div style={{ position: "absolute", left: 200, top: 300, width: 640, height: 600, borderRadius: 26, background: "#FFFDF8", boxShadow: "0 20px 50px rgba(28,41,37,0.14)", opacity: bag * (1 - result), transform: `rotate(-3deg) translateY(${(1 - bag) * 40}px)`, padding: "34px 40px", boxSizing: "border-box" }}>
        <div style={{ fontSize: 34, fontWeight: 900, color: "#C8553D", letterSpacing: 6, borderBottom: "3px solid #E9DCCB", paddingBottom: 14 }}>藥 袋</div>
        <div style={{ marginTop: 28, height: 72, display: "flex", alignItems: "center", gap: 18, position: "relative" }}>
          <span style={{ fontSize: 28, color: C.muted, width: 90 }}>藥名</span>
          <div style={{ display: "flex", gap: 10, filter: "blur(5px)" }}>
            {[150, 90, 120].map((w, i) => <div key={i} style={{ width: w, height: 30, borderRadius: 8, background: "#9AA6A1" }} />)}
          </div>
          <div style={{ position: "absolute", left: 100, right: -10, top: -6, bottom: -6, borderRadius: 14, background: "rgba(28,41,37,0.72)", display: "grid", placeItems: "center", color: "#fff", fontSize: 30, fontWeight: 900, letterSpacing: 4, opacity: maskT, transform: `scale(${0.9 + maskT * 0.1})` }}>不讀藥名</div>
        </div>
        {fields.map((fd, i) => {
          const on = frame >= stops[i].at;
          return (
            <div key={i} style={{ marginTop: 28, height: 72, display: "flex", alignItems: "center", gap: 18, borderRadius: 14, boxShadow: on ? `0 0 0 4px ${C.brand}` : "none", padding: "0 10px", marginLeft: -10 }}>
              <span style={{ fontSize: 28, color: C.muted, width: 90 }}>{fd.k}</span>
              <span style={{ fontSize: 38, fontWeight: 800, color: C.ink }}>{fd.v}</span>
              {on && <span style={{ marginLeft: "auto", fontSize: 34, color: C.brand, fontWeight: 900 }}>✓</span>}
            </div>
          );
        })}
      </div>
      {/* 放大鏡 */}
      <div style={{ position: "absolute", left: lx - 90, top: ly - 90, width: 180, height: 180, borderRadius: "50%", border: `10px solid ${C.ink}`, background: "rgba(221,241,232,0.25)", boxShadow: "0 12px 30px rgba(28,41,37,0.25)", opacity: lensO }}>
        <div style={{ position: "absolute", right: -64, bottom: -40, width: 80, height: 22, borderRadius: 11, background: C.ink, transform: "rotate(45deg)" }} />
      </div>
      {/* 建立的提醒 */}
      <div style={{ position: "absolute", left: 200, top: 300, width: 640, display: "flex", flexDirection: "column", gap: 16, opacity: result, pointerEvents: "none" }}>
        {["08:30", "12:30", "18:30"].map((tm, i) => {
          const t = pop(frame, a + 790 + i * 10);
          return (
            <div key={i} style={{ height: 120, borderRadius: 26, background: C.ink, color: C.cream, display: "flex", alignItems: "center", gap: 26, padding: "0 34px", boxShadow: "0 16px 40px rgba(28,41,37,0.25)", transform: `translateX(${(1 - t) * -80}px)`, opacity: t }}>
              <span style={{ fontFamily: MONO, fontSize: 52, fontWeight: 800, color: C.brandGlow }}>{tm}</span>
              <span style={{ fontSize: 36, fontWeight: 800 }}>吃藥（每次 1 顆）</span>
            </div>
          );
        })}
      </div>
      <Headline frame={frame} start={a + 10} end={a + 770} x={200} y={120} width={900} eyebrow="拍藥袋排提醒" lines={["只讀吃藥時間"]} size={60} />
      <div style={{ position: "absolute", left: 60, top: 40, fontSize: 22, color: C.muted, opacity: 0.8 }}>示意動畫（實機畫面待補錄）</div>
    </AbsoluteFill>
  );
};

// ============ F 語音打卡（借用 06_用藥提醒打卡 的完成畫面） ============
const TakenScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.f, b = T.g;
  if (frame < a || frame > b) return null;
  const enter = spring({ frame: frame - a, fps: FPS, config: { damping: 20 } });
  const pose: Pose = { ...HOME, y: HOME.y + (1 - enter) * 300, rx: HOME.rx + (1 - enter) * 30 };
  const screen = <DemoClip src="med" segs={[{ at: a, to: a + 40, from: 28.8, rate: 0.5 }, { at: a + 40, to: b, from: 33.6, rate: 0.02 }]} />;
  const bubble = pop(frame, a + 20);
  const check = spring({ frame: frame - (a + 60), fps: FPS, config: { damping: 8 } });
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12), fontFamily: FONT }}>
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={screen} />
        </PhoneAt>
      </Stage>
      <div style={{ position: "absolute", left: 150, top: 330, padding: "26px 36px", borderRadius: "34px 34px 34px 8px", background: C.brand, color: "#fff", fontSize: 44, fontWeight: 800, opacity: bubble, transform: `translateY(${(1 - bubble) * 30}px)`, boxShadow: "0 16px 40px rgba(62,149,122,0.3)", whiteSpace: "nowrap" }}>
        「我中午的藥吃過了。」
      </div>
      {frame >= a + 60 && (
        <div style={{ position: "absolute", left: 960 + HOME.x - 200, top: 220, width: 130, height: 130, borderRadius: "50%", background: C.brand, display: "grid", placeItems: "center", color: "#fff", fontSize: 80, fontWeight: 900, transform: `scale(${check})`, boxShadow: "0 16px 40px rgba(62,149,122,0.4)" }}>✓</div>
      )}
      <Headline frame={frame} start={a + 70} x={150} y={520} lines={["說一句，", "也算打卡"]} size={64} />
      <div style={{ position: "absolute", left: 60, top: 40, fontSize: 22, color: C.muted, opacity: 0.8 }}>畫面為按鈕打卡後的結果；語音打卡實機畫面待補錄</div>
    </AbsoluteFill>
  );
};

// ============ G 新聞（news） ============
// 片內：0 首頁、0.8 點今日頭條、1–3.9 準備播放、3.9 起朗讀、9 列表
const NewsScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.g, b = T.end;
  if (frame < a || frame > b) return null;
  const push = interpolate(frame, [a + 26, a + 50], [0, 1], { ...clamp, easing: ease });
  const back = interpolate(frame, [a + 60, a + 100], [0, 1], { ...clamp, easing: ease });
  const k = push * (1 - back);
  // 推近穿越：點下頭條時鏡頭衝進螢幕，再退回
  const pose: Pose = { ...HOME, z: k * 700, ry: HOME.ry * (1 - k), rx: HOME.rx * (1 - k) };
  const screen = <DemoClip src="news" segs={[{ at: a, to: a + 30, from: 0 }, { at: a + 30, to: a + 300, from: 1 }, { at: a + 300, to: b, from: 10, rate: 0.01 }]} />;
  const pp = { dx: -380, dy: 0, z: 240, s: 1.35, face: 1 };
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12) }}>
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={screen}>
            <Tap frame={frame} at={a + 22} nx={0.3} ny={0.66} />
            {/* 朗讀中的新聞卡 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.22, w: 0.96, h: 0.19 }} pose={pose} radius={18} keys={[{ f: a + 130 }, { f: a + 148, ...pp }, { f: a + 290, ...pp }, { f: a + 306 }]}>
              {screen}
            </PullOut>
          </Phone3D>
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 320} x={150} y={300} eyebrow="代誌報給你知" lines={["今天的新聞，", "唸給阿嬤聽"]} />
    </AbsoluteFill>
  );
};

export const Ch05: React.FC = () => {
  const frame = useCurrentFrame();
  // 小嘎原聲出現時配樂壓低
  const duck: [number, number][] = [
    [T.a + 410, T.a + 680],
    [T.c + 100, T.c + 360],
    [T.g + 110, T.g + 300],
  ];
  const music = (f: number) => {
    let v = interpolate(f, [0, 30, T.end - 40, T.end], [0, 0.2, 0.2, 0], clamp);
    for (const [s, e] of duck) v = Math.min(v, interpolate(f, [s - 10, s, e, e + 15], [0.2, 0.05, 0.05, 0.2], clamp));
    return v;
  };
  return (
    <AbsoluteFill style={{ background: C.light, overflow: "hidden" }}>
      <Backdrop />
      <WeatherScene frame={frame} />
      <SpeedScene frame={frame} />
      <TwScene frame={frame} />
      <MemoryScene frame={frame} />
      <MedBagScene frame={frame} />
      <TakenScene frame={frame} />
      <NewsScene frame={frame} />
      <BackendChips frame={frame} chips={CHIPS} />
      {SHOW_SUBS && <Subtitles frame={frame} subs={SUBS} />}
      <ChapterCard frame={frame} num="05" title="和小嘎聊天" />
      <Audio src={staticFile("ad/audio/music.wav")} volume={music} />
      <Sequence from={0} durationInFrames={sec(1.5)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.5} /></Sequence>
      {/* 小嘎原聲 */}
      <ClipSound src="chat_weather" at={T.a + 423} from={18.6} dur={252} volume={1} />
      <ClipSound src="chat_tw" at={T.c + 111} from={2.2} dur={240} volume={1} />
      <ClipSound src="chat_tw" at={T.c + 351} from={10.2} dur={330} volume={0.22} />
      <ClipSound src="news" at={T.g + 117} from={3.9} dur={180} volume={0.95} />
      {/* 音效 */}
      {[T.a + 40, T.a + 420, T.c + 20, T.c + 380, T.g + 130].map((at, i) => (
        <Sequence key={`w${i}`} from={at} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.28} /></Sequence>
      ))}
      <Sequence from={T.a + 62} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/pop.wav")} volume={0.4} /></Sequence>
      {Array.from({ length: 16 }).map((_, i) => (
        <Sequence key={`k${i}`} from={T.b + 100 + i * 9} durationInFrames={sec(0.4)}><Audio src={staticFile("ad/audio/tick.wav")} volume={0.25} /></Sequence>
      ))}
      <Sequence from={T.b + 100 + 21} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/thud.wav")} volume={0.5} /></Sequence>
      <Sequence from={T.b + 100 + 143} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/thud.wav")} volume={0.25} /></Sequence>
      <Sequence from={T.d + 260} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/ding.wav")} volume={0.3} /></Sequence>
      <Sequence from={T.d + 300} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.3} /></Sequence>
      <Sequence from={T.e + 120} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/thud.wav")} volume={0.35} /></Sequence>
      {[300, 400, 500].map((d, i) => (
        <Sequence key={`m${i}`} from={T.e + d} durationInFrames={sec(0.6)}><Audio src={staticFile("ad/audio/tick.wav")} volume={0.5} /></Sequence>
      ))}
      {[0, 10, 20].map((d, i) => (
        <Sequence key={`r${i}`} from={T.e + 790 + d} durationInFrames={sec(0.6)}><Audio src={staticFile("ad/audio/pop.wav")} volume={0.3} /></Sequence>
      ))}
      <Sequence from={T.f + 60} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/ding.wav")} volume={0.35} /></Sequence>
      <Sequence from={T.g + 22} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/pop.wav")} volume={0.4} /></Sequence>
    </AbsoluteFill>
  );
};
