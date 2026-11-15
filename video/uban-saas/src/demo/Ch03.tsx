// 第三章：註冊、配對與首次設定（分鏡 03:30–05:00，共 90 秒）
// 主要手法：手勢示意＋元件拉出；材質：實機錄影（02_身分選擇、03_QR綁定）
// 缺的兩段（Email 註冊、填長輩資料）先用示意動畫／待補錄佔位
import React from "react";
import { AbsoluteFill, Audio, Sequence, interpolate, spring, staticFile, useCurrentFrame } from "remotion";
import { BackendChips, ChapterCard, Chip, COLORS as C, FONT, FPS, MONO, Sub, Subtitles, clamp, ease, sec } from "./common";
import { Backdrop, DemoClip, Headline, Placeholder, Tag, pop, vis } from "./scene";
import { Phone3D, PhoneAt, Pose, PullOut, Stage, Tap } from "../kit";
import { kf } from "../ChatFeature";

const SHOW_SUBS = true;
const T = { a: 0, b: sec(20), c: sec(40), d: sec(65), end: sec(90) };
export const CH03_FRAMES = T.end;

// 手機放在右半邊
const HOME: Pose = { x: 250, y: 6, ry: -14, rx: 4, rz: 1, s: 0.94 };

const SUBS: Sub[] = [
  { from: sec(1.7), to: sec(6.6), text: "第一次打開 Uban，會先問：誰在使用這支手機？" },
  { from: sec(7), to: sec(13), text: "長輩、家屬，還是放在客廳的監控設備，三種身分看到的畫面都不一樣。" },
  { from: sec(13.4), to: sec(19.6), text: "不確定選哪個，新手導覽會一步一步說明，之後也能隨時再看。" },
  { from: sec(20.5), to: sec(27.5), text: "家人用 Email 註冊，收一組六位數驗證碼就好。" },
  { from: sec(28), to: sec(34), text: "密碼以 bcrypt 加密保存；" },
  { from: sec(34.3), to: sec(39.6), text: "忘記密碼，也能用同一套驗證碼重設。" },
  { from: sec(40.5), to: sec(46.5), text: "接著幫阿嬤綁定。阿嬤的手機會出現一組四位數配對碼。" },
  { from: sec(47), to: sec(53.5), text: "家人掃一下 QR Code，或直接輸入四個數字，就完成配對。" },
  { from: sec(54), to: sec(59), text: "阿嬤不用記帳號、不用打密碼——" },
  { from: sec(59.3), to: sec(64.6), text: "對長輩來說，這一步最重要。" },
  { from: sec(65.5), to: sec(72), text: "家人再把阿嬤的稱呼、年齡、住哪裡、平常吃什麼藥填好。" },
  { from: sec(72.4), to: sec(78.5), text: "居住地按一下「一鍵定位」，就會自動帶入行政區。" },
  { from: sec(79), to: sec(84.5), text: "這些資料，就是小嘎認識阿嬤的第一步；" },
  { from: sec(84.8), to: sec(89.6), text: "隱私授權也會在這裡清楚告知。" },
];

const CHIPS: Chip[] = [
  { from: sec(22), to: sec(30), text: "POST /api/auth/email-code" },
  { from: sec(24), to: sec(30), text: "有效 10 分鐘 · 冷卻 60 秒 · 每小時 ≤ 5 封" },
  { from: sec(30), to: sec(39.5), text: "POST /api/auth/register · bcrypt" },
  { from: sec(33), to: sec(39.5), text: "POST /api/auth/login → JWT" },
  { from: sec(42), to: sec(51), text: "長輩端 POST /api/pairing/request_code" },
  { from: sec(50), to: sec(60), text: "POST /api/pairing/confirm" },
  { from: sec(52), to: sec(60), text: "建立 family_elder_relationship" },
  { from: sec(68), to: sec(80), text: "PUT /api/user/profile/{id}" },
  { from: sec(80), to: sec(89.5), text: "elder_profile → get_elder_context" },
];

// ============ A 身分選擇 ============
const ROLE_SEGS = (a: number) => [
  { at: a, to: a + 200, from: 0, rate: 0.25 }, // 前 1.5 秒畫面是靜止的，放慢當停格，讓拉出的卡片停住
  { at: a + 200, to: a + 600, from: 1.5 },
];

const RoleScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.a, b = T.b;
  if (frame < a || frame > b) return null;
  const rise = 40;
  const pose: Pose = { ...HOME, y: kf(frame, [[a + 20, HOME.y + 260], [a + 20 + rise, HOME.y]]), rx: kf(frame, [[a + 20, 58], [a + 20 + rise, HOME.rx]]), s: (HOME.s ?? 1) * kf(frame, [[a + 20, 0.8], [a + 20 + rise, 1]]) };
  const screen = <DemoClip src="role" segs={ROLE_SEGS(a)} />;
  const pull = { dx: -330, dy: 30, z: 260, s: 1.25, face: 1 };
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12) }}>
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={screen}>
            {/* 兩張身分卡拉出放大 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.355, w: 0.96, h: 0.285 }} pose={pose} keys={[{ f: a + 80 }, { f: a + 100, ...pull }, { f: a + 180, ...pull }, { f: a + 198 }]}>
              {screen}
            </PullOut>
            <Tap frame={frame} at={a + 246} nx={0.88} ny={0.26} />
          </Phone3D>
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 52} end={a + 300} x={150} y={300} eyebrow="身分選擇" lines={["誰在使用", "這支手機？"]} note="長輩、家屬、監控設備，三種身分各有不同的畫面" />
      <Headline frame={frame} start={a + 300} x={150} y={300} eyebrow="新手導覽" lines={["一步一步", "說給你聽"]} note="五個步驟框出每個選項；右上角「怎麼選？」隨時可以再看一次" />
    </AbsoluteFill>
  );
};

// ============ B Email 驗證碼（示意動畫） ============
const CODE = "482916";
const HASH = "$2b$12$Qe7Lx0vN3kTzR8yWm1pFhO";
const EmailScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.b, b = T.c;
  if (frame < a || frame > b) return null;
  const f = frame - a;
  const env = pop(frame, a + 14);
  const step2 = pop(frame, a + 80);
  const step3 = pop(frame, a + 300);
  const jwt = pop(frame, a + 420);
  const scr = (i: number) => {
    // 雜湊字串：先亂跳再定住
    const lock = a + 330 + i * 1.2;
    if (frame >= lock) return HASH[i];
    const pool = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz0123456789./";
    return pool[(i * 7 + Math.floor(frame / 2) * 13) % pool.length];
  };
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12), fontFamily: FONT }}>
      <Headline frame={frame} start={a + 6} x={960} y={110} center width={1200} eyebrow="家屬註冊" lines={["Email 驗證碼，一次完成"]} size={64} />
      {/* 第一步：信封 */}
      <div style={{ position: "absolute", left: 230, top: 400, width: 340, height: 330, borderRadius: 36, background: "#fff", boxShadow: "0 18px 44px rgba(28,41,37,0.10)", opacity: env, transform: `translateY(${(1 - env) * 40}px)`, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 22 }}>
        <svg width="150" height="110" viewBox="0 0 150 110">
          <rect x="5" y="5" width="140" height="100" rx="14" fill="#DDF1E8" stroke={C.brand} strokeWidth="5" />
          <path d={`M10 14 L75 ${62 - Math.min(1, Math.max(0, (f - 40) / 14)) * 40} L140 14`} fill="none" stroke={C.brandDeep} strokeWidth="5" strokeLinejoin="round" />
        </svg>
        <div style={{ fontSize: 30, fontWeight: 800, color: C.ink }}>收到驗證信</div>
        <div style={{ fontSize: 24, color: C.muted }}>10 分鐘內有效</div>
      </div>
      {/* 第二步：六位數落定 */}
      <div style={{ position: "absolute", left: 640, top: 400, width: 640, height: 330, borderRadius: 36, background: "#fff", boxShadow: "0 18px 44px rgba(28,41,37,0.10)", opacity: step2, transform: `translateY(${(1 - step2) * 40}px)`, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 30 }}>
        <div style={{ display: "flex", gap: 16 }}>
          {[...CODE].map((d, i) => {
            const land = a + 110 + i * 14;
            const done = frame >= land;
            const t = spring({ frame: frame - land, fps: FPS, config: { damping: 12 } });
            const roll = String((Math.floor(frame / 2) + i * 3) % 10);
            return (
              <div key={i} style={{ width: 82, height: 112, borderRadius: 18, border: `4px solid ${done ? C.brand : "#D5E2DC"}`, background: done ? "#F1FAF6" : "#F7FAF9", display: "grid", placeItems: "center", fontFamily: MONO, fontSize: 64, fontWeight: 800, color: done ? C.brandDeep : "#B5C4BE", transform: `scale(${done ? 0.9 + t * 0.1 : 1})` }}>
                {frame < a + 96 ? "" : done ? d : roll}
              </div>
            );
          })}
        </div>
        <div style={{ fontSize: 28, fontWeight: 700, color: C.ink }}>輸入六位數驗證碼</div>
      </div>
      {/* 第三步：bcrypt → JWT */}
      <div style={{ position: "absolute", left: 1350, top: 400, width: 340, height: 330, borderRadius: 36, background: C.ink, boxShadow: "0 18px 44px rgba(28,41,37,0.18)", opacity: step3, transform: `translateY(${(1 - step3) * 40}px)`, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 18, padding: 24, boxSizing: "border-box" }}>
        <svg width="70" height="84" viewBox="0 0 70 84">
          <rect x="5" y="36" width="60" height="44" rx="10" fill={C.brand} />
          <path d="M18 36 V24 a17 17 0 0 1 34 0 V36" fill="none" stroke={C.brandGlow} strokeWidth="7" />
        </svg>
        <div style={{ fontFamily: MONO, fontSize: 20, color: C.brandGlow, wordBreak: "break-all", textAlign: "center", lineHeight: 1.4 }}>{[...HASH].map((_, i) => scr(i)).join("")}…</div>
        <div style={{ fontSize: 26, fontWeight: 800, color: C.cream }}>bcrypt 加密保存</div>
      </div>
      {/* 箭頭 */}
      {[[585, a + 70], [1295, a + 290]].map(([x, at], i) => (
        <div key={i} style={{ position: "absolute", left: x - 6, top: 548, fontSize: 48, color: C.brand, fontWeight: 900, opacity: interpolate(frame, [at, at + 10], [0, 1], clamp) }}>›</div>
      ))}
      {/* 登入完成 */}
      <div style={{ position: "absolute", left: 960, top: 800, transform: `translateX(-50%) scale(${0.85 + jwt * 0.15})`, opacity: jwt, padding: "16px 34px", borderRadius: 999, background: C.brand, color: "#fff", fontSize: 32, fontWeight: 800, whiteSpace: "nowrap", boxShadow: "0 14px 34px rgba(62,149,122,0.35)" }}>
        ✓ 註冊完成，自動登入
      </div>
      <div style={{ position: "absolute", left: 60, top: 40, fontSize: 22, color: C.muted, opacity: 0.8 }}>示意動畫</div>
    </AbsoluteFill>
  );
};

// ============ C QR 配對（03_QR綁定：家屬機掃長輩機） ============
// 片內：0–1 表單、1–4 掃描、4–8 帶入 0635、8–9.5 開始配對、9.5–11 配對成功、11–15.5 家屬首頁
const QR_SEGS = (a: number) => [
  { at: a, to: a + 300, from: 0, rate: 0.95 },
  { at: a + 300, to: a + 390, from: 9.5, rate: 0.5 }, // 「配對成功」放慢停留
  { at: a + 390, to: a + 525, from: 11 },
  { at: a + 525, to: a + 750, from: 15.4, rate: 0.01 }, // 最後停在家屬首頁
];
const QrScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.c, b = T.d;
  if (frame < a || frame > b) return null;
  const enter = spring({ frame: frame - a, fps: FPS, config: { damping: 20 } });
  const drift = interpolate(frame, [a, b], [0, 1]);
  const pose: Pose = { ...HOME, x: HOME.x + (1 - enter) * 700, ry: HOME.ry - (1 - enter) * 30 + drift * 6, rz: HOME.rz - drift };
  const screen = <DemoClip src="qr" segs={QR_SEGS(a)} />;
  const ok = a + 300;
  const ring = interpolate(frame, [ok, ok + 40], [0, 1], clamp);
  const pull = { dx: -380, dy: 400, z: 240, s: 1.4, face: 1 };
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12) }}>
      {/* 配對成功的擴散光圈 */}
      {frame >= ok && <div style={{ position: "absolute", left: 960 + HOME.x - 300, top: 540 - 300, width: 600, height: 600, borderRadius: "50%", border: `6px solid ${C.brand}`, opacity: 1 - ring, transform: `scale(${0.6 + ring * 1.2})` }} />}
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={screen}>
            <Tap frame={frame} at={a + 36} nx={0.5} ny={0.38} />
            {/* 四位數配對碼欄位拉出放大（鍵盤彈出後欄位在上方） */}
            <PullOut frame={frame} rect={{ x: 0.04, y: 0.128, w: 0.92, h: 0.075 }} pose={pose} radius={14} keys={[{ f: a + 170 }, { f: a + 188, ...pull }, { f: a + 250, ...pull }, { f: a + 266 }]}>
              {screen}
            </PullOut>
            {/* 「配對成功」提示拉出 */}
            <PullOut frame={frame} rect={{ x: 0.02, y: 0.925, w: 0.96, h: 0.055 }} pose={pose} radius={14} keys={[{ f: ok + 10 }, { f: ok + 26, dx: -40, dy: -400, z: 300, s: 1.3, face: 1 }, { f: ok + 80, dx: -40, dy: -400, z: 300, s: 1.3, face: 1 }, { f: ok + 96 }]}>
              {screen}
            </PullOut>
          </Phone3D>
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 14} end={a + 380} x={150} y={300} eyebrow="QR 配對" lines={["掃一下，", "就綁定好了"]} note="阿嬤手機出現四位數配對碼，家人掃 QR Code 或直接輸入" />
      <Headline frame={frame} start={a + 380} x={150} y={300} eyebrow="配對完成" lines={["長輩不用", "記帳號密碼"]} note="家屬首頁立刻出現阿嬤的打卡、近況與定位" />
      <Tag frame={frame} at={a + 190} end={a + 270} x={150} y={720} text="配對碼 4 位數" />
    </AbsoluteFill>
  );
};

// ============ D 填長輩資料（待補錄） ============
const FIELDS = [
  { k: "稱呼", v: "阿嬤" },
  { k: "年齡", v: "78 歲" },
  { k: "居住地", v: "一鍵定位 → 行政區", pin: true },
  { k: "慢性病與用藥", v: "高血壓 · 早晚各一次" },
];
const ProfileScene: React.FC<{ frame: number }> = ({ frame }) => {
  const a = T.d, b = T.end;
  if (frame < a || frame > b) return null;
  const enter = spring({ frame: frame - a, fps: FPS, config: { damping: 20 } });
  const pose: Pose = { ...HOME, x: HOME.x + 120, y: HOME.y + (1 - enter) * 300, ry: -20, rx: 4 + (1 - enter) * 30 };
  const lit = (i: number) => a + 50 + i * 75;
  const merge = a + 420;
  const m = interpolate(frame, [merge, merge + 40], [0, 1], { ...clamp, easing: ease });
  const brain = pop(frame, merge + 30);
  return (
    <AbsoluteFill style={{ opacity: vis(frame, a, b, 12), fontFamily: FONT }}>
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={<Placeholder frame={frame} title="家屬填寫長輩資料" lines={["稱呼、年齡、居住地「一鍵定位」", "慢性病與用藥", "長輩機：醫療免責與隱私授權"]} />} />
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 10} x={150} y={130} eyebrow="長輩資料" lines={["小嘎認識阿嬤", "的第一步"]} size={64} />
      {FIELDS.map((fd, i) => {
        const t = pop(frame, lit(i));
        const pinT = fd.pin ? spring({ frame: frame - lit(i) - 18, fps: FPS, config: { damping: 9 } }) : 0;
        const x = 150 + m * (380 - 150);
        const y = 420 + i * 108 + m * (640 - (420 + i * 108)) ;
        return (
          <div key={i} style={{ position: "absolute", left: x, top: y, width: 620, height: 88, borderRadius: 22, background: "#fff", boxShadow: `0 10px 26px rgba(28,41,37,0.10), 0 0 0 ${t * 3}px rgba(89,178,148,${0.6 * (1 - m)})`, opacity: t * (1 - m * 0.95), transform: `translateX(${(1 - t) * -40}px) scale(${1 - m * 0.6})`, display: "flex", alignItems: "center", padding: "0 26px", boxSizing: "border-box", gap: 18 }}>
            <span style={{ fontSize: 26, color: C.muted, width: 190 }}>{fd.k}</span>
            <span style={{ fontSize: 32, fontWeight: 800, color: C.ink, whiteSpace: "nowrap" }}>{fd.v}</span>
            {fd.pin && (
              <svg width="40" height="52" viewBox="0 0 40 52" style={{ marginLeft: "auto", transform: `translateY(${(1 - pinT) * -90}px)`, opacity: Math.min(1, pinT * 3) }}>
                <path d="M20 50 C20 50 4 30 4 19 a16 16 0 0 1 32 0 C36 30 20 50 20 50 Z" fill={C.warm} />
                <circle cx="20" cy="19" r="6" fill="#fff" />
              </svg>
            )}
          </div>
        );
      })}
      {/* 資料匯進小嘎 */}
      <div style={{ position: "absolute", left: 230, top: 560, width: 520, padding: "28px 32px", borderRadius: 30, background: C.ink, color: C.cream, opacity: brain, transform: `scale(${0.85 + brain * 0.15})`, boxShadow: "0 18px 44px rgba(28,41,37,0.25)" }}>
        <div style={{ fontSize: 24, color: C.brandGlow, fontWeight: 800, letterSpacing: 2 }}>小嘎的背景知識</div>
        <div style={{ marginTop: 12, fontSize: 30, lineHeight: 1.5, fontWeight: 700 }}>「阿嬤 78 歲，有高血壓，<br />早晚各吃一次藥。」</div>
      </div>
    </AbsoluteFill>
  );
};

export const Ch03: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: C.light, overflow: "hidden" }}>
      <Backdrop />
      <RoleScene frame={frame} />
      <EmailScene frame={frame} />
      <QrScene frame={frame} />
      <ProfileScene frame={frame} />
      <BackendChips frame={frame} chips={CHIPS} />
      {SHOW_SUBS && <Subtitles frame={frame} subs={SUBS} />}
      <ChapterCard frame={frame} num="03" title="註冊與配對" />
      {/* 聲音 */}
      <Audio src={staticFile("ad/audio/music.wav")} volume={(f) => interpolate(f, [0, 30, T.end - 40, T.end], [0, 0.2, 0.2, 0], clamp)} />
      <Sequence from={0} durationInFrames={sec(1.5)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.5} /></Sequence>
      {[T.a + 80, T.c + 170, T.c + 310].map((at, i) => (
        <Sequence key={`w${i}`} from={at} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/whoosh.wav")} volume={0.3} /></Sequence>
      ))}
      {[T.a + 246, T.c + 36].map((at, i) => (
        <Sequence key={`t${i}`} from={at} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/pop.wav")} volume={0.4} /></Sequence>
      ))}
      {[...CODE].map((_, i) => (
        <Sequence key={`c${i}`} from={T.b + 110 + i * 14} durationInFrames={sec(0.6)}><Audio src={staticFile("ad/audio/tick.wav")} volume={0.45} /></Sequence>
      ))}
      <Sequence from={T.b + 420} durationInFrames={sec(2)}><Audio src={staticFile("ad/audio/ding.wav")} volume={0.35} /></Sequence>
      <Sequence from={T.c + 300} durationInFrames={sec(3)}><Audio src={staticFile("pain/chord.wav")} volume={0.35} /></Sequence>
      {FIELDS.map((_, i) => (
        <Sequence key={`f${i}`} from={T.d + 50 + i * 75} durationInFrames={sec(0.6)}><Audio src={staticFile("ad/audio/tick.wav")} volume={0.4} /></Sequence>
      ))}
      <Sequence from={T.d + 50 + 2 * 75 + 22} durationInFrames={sec(1)}><Audio src={staticFile("ad/audio/thud.wav")} volume={0.35} /></Sequence>
      <Sequence from={T.d + 450} durationInFrames={sec(2)}><Audio src={staticFile("ad/audio/ding.wav")} volume={0.3} /></Sequence>
    </AbsoluteFill>
  );
};
