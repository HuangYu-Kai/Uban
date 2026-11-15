import React from "react";
import { AbsoluteFill, Audio, Easing, Img, Sequence, interpolate, spring, staticFile, useCurrentFrame } from "remotion";
import { kf, Kinetic, Waveform } from "./ChatFeature";
import { ClipView, Phone3D, PhoneAt, PullOut, Stage, Tap, type Pose, type Seg } from "./kit";

// ============================================================
// 可直接修改的內容：時間點、文案、顏色、素材、聲音、版面都在這一區
// 影格換算：30 影格 = 1 秒；配樂 120 BPM，1 拍 = 15 影格
// 三支成品共用同一套鏡頭：
//   Ad60  ＝ TL60 時間軸 ＋ GEO.wide 版面（橫式 60 秒）
//   Ad15  ＝ TL15 時間軸 ＋ GEO.wide 版面（橫式 15 秒）
//   Ad60V ＝ TL60 時間軸 ＋ GEO.tall 版面（直式 60 秒）
// ============================================================
export const AD_FPS = 30;
const NONE = -9999; // 這個時間軸不用的動作

// ---- 顏色 ----
const C = {
  dark: "#0F1416", // 開場暗底
  light: "#F5F8F6", // 中段亮底
  outro: "#EAF5F0", // 結尾底色
  glow: "#DDF1E8",
  ink: "#1C2925",
  muted: "#5D6B66",
  brand: "#59B294", // 品牌綠
  brandDeep: "#3E957A",
  brandOnDark: "#7FD3B0",
  cream: "#FFF6E8",
  creamDim: "rgba(255,246,232,0.72)",
  warm: "#F2B880",
};
const FONT = '"Microsoft JhengHei UI","Microsoft JhengHei","Noto Sans TC","PingFang TC",sans-serif';

// ---- 文案（60 秒版；15 秒版只覆寫有差異的幾句，見 TL15.COPY）----
const COPY = {
  badge: "App 畫面皆為實機錄影",
  hook: { lines: ["媽媽倒在地上", "你，多久才知道？"], note: "閒置手機當監控機・實機監視畫面" },
  alert: {
    eyebrow: "家屬端",
    title1: ["警報第一時間", "送到家人手機"],
    title2: ["點開，就看到", "即時畫面"],
    summaryTitle: "同時附上情境摘要",
    summary: ["今天 08:02 完成吃藥打卡", "最後位置：家", "10:15 和小嘎說過話"],
    summaryNote: "＊摘要為示意內容",
  },
  turn: { line1: "平常的每一天", line2: "Uban 也都在" },
  elder: { eyebrow: "長輩端", title1: ["大字、大按鈕", "一眼看完今天"], title2: ["時間到會提醒", "按一下就打卡"] },
  chat: { eyebrow: "AI 夥伴小嘎", title: ["會聊天、會提醒", "還會說台語"], elderSays: "長輩說", elderQuote: "「明天上午 7 點要提醒我吃藥」", voiceTitle: "小嘎用台語回答", voiceNote: "實機錄音，不是後製配音" },
  cheer: {
    elderChip: "長輩的手機",
    familyChip: "家人的手機",
    title1: ["按一下打卡", "家人就知道"],
    title2: ["家人錄一句鼓勵", "馬上送過去"],
    title3: ["聽到的是", "家人真正的聲音"],
  },
  question: {
    old: "有吃飯嗎？",
    fresh: "今天，聊點別的",
    eyebrow: "每日一問",
    title: ["一天一個回憶", "兩代多了話題"],
    elderSays: "長輩說",
    elderQuote: "「我小時候最喜歡阿嬤做的蕃薯粥」",
    familySays: "家人回",
    familyQuote: "「明天煮給你吃」",
  },
  pig: { eyebrow: "福氣小豬", title: ["打卡賺胡蘿蔔", "全家一起養小豬"], stages: "五個成長階段" },
  outro: {
    wordmark: "Uban",
    tagline: "讓每一天的平安，都有人知道",
    sub: "AI 跨世代感知照護系統",
    points: ["長輩用得來", "出事第一時間知道", "兩代多了話題"],
  },
};

type Span = [number, number];
type Sound = { at: number; src: string; vol: number; dur?: number };
type Timeline = {
  total: number;
  // 每個鏡頭的起訖影格（[NONE, NONE] ＝這個版本沒有這個鏡頭）
  T: Record<"hook" | "alert" | "turn" | "elder" | "chat" | "cheer" | "question" | "pig" | "outro", Span>;
  COPY: typeof COPY;
  // 實機錄影片段（at/to：廣告影格；from：片內秒數；rate：倍速）
  CLIPS: Record<"hook" | "alert" | "elder" | "chat" | "cheerElder" | "cheerFamily" | "questionElder" | "questionFamily" | "pig", Seg[]>;
  // 動作發生的影格（和畫面裡的操作對齊）
  CUE: {
    hookLine1: number;
    hookLine2: number;
    hookNote: number;
    alertTitleSwap: number;
    alertTap: number;
    alertPush: Span | null;
    summaryCard: number;
    summaryLines: number[];
    heartIn: Span;
    elderPull: number[] | null;
    elderTitleSwap: number;
    elderTap: number;
    chatQuote: number;
    chatPull: number[] | null;
    ttsStart: number;
    ttsEnd: number;
    cheerTap: number;
    cheerTitles: { at: number; key: "title1" | "title2" | "title3" }[];
    cheerDotGo: Span | null;
    cheerDotBack: Span | null;
    voiceStart: number;
    voiceEnd: number;
    questionStrike: number;
    questionFresh: number;
    questionCards: number;
    questionDot: Span | null;
    questionQuote1: number;
    questionQuote2: number;
    pigStages: number[];
    heartOut: Span;
    outroLogo: number;
    outroTagline: number;
    outroPoints: number;
  };
  MUSIC: { at: number; src: string; vol: number; duckVol: number; duck: Span[] };
  SOUNDS: Sound[];
};

// ================= 60 秒版時間軸 =================
const TL60: Timeline = {
  total: 1800,
  T: {
    hook: [0, 120], // 開場：監控機畫面＋提問
    alert: [120, 330], // 家屬收到警報、點開即時畫面
    turn: [330, 390], // 愛心遮罩，暗轉亮
    elder: [390, 570], // 長輩首頁大字＋提醒打卡
    chat: [570, 810], // 小嘎說台語
    cheer: [810, 1140], // 打卡 → 家人鼓勵 → 長輩聽到
    question: [1140, 1365], // 每日一問
    pig: [1365, 1560], // 福氣小豬
    outro: [1560, 1800], // Logo 與標語
  },
  COPY,
  CLIPS: {
    hook: [{ at: 0, to: 122, src: "monitor", from: 2.0 }],
    alert: [
      { at: 118, to: 270, src: "alert", from: 1.55 }, // 警報彈出 → 點「查看監視畫面」
      { at: 270, to: 350, src: "alert", from: 9.4 }, // 即時畫面
    ],
    elder: [
      { at: 388, to: 486, src: "checkin", from: 1.25 }, // 首頁 → 提醒彈出
      { at: 486, to: 572, src: "checkin", from: 10.3 }, // 按「我做好了！打卡」
    ],
    chat: [{ at: 568, to: 812, src: "chat_tw", from: 1.15 }],
    cheerElder: [
      { at: 808, to: 900, src: "checkin", from: 10.85 }, // 打卡
      { at: 900, to: 1020, src: "checkin", from: 13.9, rate: 0.12 },
      { at: 1020, to: 1142, src: "cheer_recv", from: 5.0 }, // 收到家人語音
    ],
    cheerFamily: [
      { at: 808, to: 900, src: "cheer_send", from: 0.2, rate: 0.4 },
      { at: 900, to: 960, src: "cheer_send", from: 2.6, rate: 1.2 }, // 開始錄音
      { at: 960, to: 1020, src: "cheer_send", from: 7.4, rate: 1.4 }, // 送出鼓勵
      { at: 1020, to: 1142, src: "cheer_send", from: 10.3, rate: 0.12 },
    ],
    questionElder: [
      { at: 1213, to: 1290, src: "question_elder", from: 4.0, rate: 1.5 }, // 口述回答 → 送出給家人
      { at: 1290, to: 1367, src: "question_elder", from: 7.9, rate: 0.12 },
    ],
    questionFamily: [
      { at: 1213, to: 1290, src: "question_family", from: 3.0, rate: 0.12 },
      { at: 1290, to: 1367, src: "question_family", from: 4.3, rate: 1.3 }, // 家人回覆
    ],
    pig: [{ at: 1363, to: 1562, src: "pig", from: 0.2, rate: 0.85 }],
  },
  CUE: {
    hookLine1: 16,
    hookLine2: 46,
    hookNote: 70,
    alertTitleSwap: 266, // 換成「點開，就看到即時畫面」
    alertTap: 252, // 點「查看監視畫面」
    alertPush: [258, 296], // 手機推近
    summaryCard: 168, // 情境摘要字卡進場
    summaryLines: [182, 206, 230], // 三行各自開始打字
    heartIn: [318, 346], // 愛心遮罩（暗轉亮）
    elderPull: [426, 444, 462, 476], // 「今天」日期卡：離開螢幕／到位／開始收回／回到螢幕
    elderTitleSwap: 484,
    elderTap: 522, // 點「我做好了！打卡」
    chatQuote: 584, // 長輩說的那句話出現
    chatPull: [596, 616, 770, 790], // 國語／台語切換鈕拉出放大
    ttsStart: 600, // 小嘎台語開始
    ttsEnd: 756,
    cheerTap: 828, // 雙機鏡頭裡長輩點打卡
    cheerTitles: [{ at: 818, key: "title1" }, { at: 902, key: "title2" }, { at: 1022, key: "title3" }],
    cheerDotGo: [858, 885], // 光點：長輩 → 家人
    cheerDotBack: [1003, 1028], // 光點：家人 → 長輩
    voiceStart: 1053, // 家人鼓勵語音開始
    voiceEnd: 1118,
    questionStrike: 1152, // 「有吃飯嗎？」被劃掉
    questionFresh: 1162,
    questionCards: 1215, // 字卡結束、雙機進場
    questionDot: [1266, 1290], // 光點：長輩 → 家人
    questionQuote1: 1240,
    questionQuote2: 1304,
    pigStages: [1425, 1440, 1455, 1470, 1485], // 五階段小豬各對一拍
    heartOut: [1548, 1576], // 愛心遮罩（進結尾）
    outroLogo: 1568,
    outroTagline: 1592,
    outroPoints: 1640,
  },
  MUSIC: { at: 330, src: "music.wav", vol: 0.66, duckVol: 0.14, duck: [[590, 762], [1045, 1122]] },
  SOUNDS: [
    { at: 0, src: "drone.wav", vol: 0.45 }, // 開場低頻鋪底
    { at: 6, src: "thud.wav", vol: 0.8 }, // 悶響
    { at: 112, src: "whoosh.wav", vol: 0.5 }, // 急甩
    { at: 150, src: "alert_real.wav", vol: 0.5 }, // 實機警報聲
    { at: 252, src: "tick.wav", vol: 0.6 },
    { at: 318, src: "whoosh.wav", vol: 0.45 }, // 愛心遮罩
    { at: 522, src: "ding.wav", vol: 0.5 },
    { at: 600, src: "tts_taiwanese.wav", vol: 1 }, // 小嘎台語原聲
    { at: 828, src: "ding.wav", vol: 0.45 },
    { at: 858, src: "whoosh.wav", vol: 0.35 },
    { at: 885, src: "pop.wav", vol: 0.6 },
    { at: 1003, src: "whoosh.wav", vol: 0.35 },
    { at: 1028, src: "pop.wav", vol: 0.6 },
    { at: 1053, src: "cheer_voice.wav", vol: 1 }, // 家人鼓勵原聲
    { at: 1152, src: "swipe.wav", vol: 0.5 },
    { at: 1266, src: "whoosh.wav", vol: 0.35 },
    { at: 1290, src: "pop.wav", vol: 0.6 },
    ...[1425, 1440, 1455, 1470, 1485].map((at) => ({ at, src: "tick.wav", vol: 0.5 })),
    { at: 1548, src: "whoosh.wav", vol: 0.4 },
    { at: 1592, src: "ding.wav", vol: 0.3 },
  ],
};

// ================= 15 秒版時間軸 =================
// 保留：開場 2.5 秒 → 警報 2 秒 → 打卡 2 秒 → 小嘎台語 2 秒 → 鼓勵 2 秒 → 小豬 1.5 秒 → 結尾 3 秒
const TL15: Timeline = {
  total: 450,
  T: {
    hook: [0, 75],
    alert: [75, 135],
    turn: [NONE, NONE],
    elder: [135, 195],
    chat: [195, 255],
    cheer: [255, 315],
    question: [NONE, NONE],
    pig: [315, 360],
    outro: [360, 450],
  },
  COPY: {
    ...COPY,
    elder: { ...COPY.elder, title1: ["大字、大按鈕", "按一下就打卡"] },
    chat: { ...COPY.chat, title: ["小嘎會聊天", "還會說台語"] },
    cheer: { ...COPY.cheer, title3: ["家人的鼓勵", "是真的聲音"] },
    pig: { ...COPY.pig, title: ["全家一起", "養小豬"] },
  },
  CLIPS: {
    hook: [{ at: 0, to: 77, src: "monitor", from: 2.0 }],
    alert: [{ at: 73, to: 150, src: "alert", from: 2.9 }], // 警報已彈出
    elder: [{ at: 133, to: 197, src: "checkin", from: 10.4 }], // 提醒 → 按打卡
    chat: [{ at: 193, to: 257, src: "chat_tw", from: 1.9 }],
    cheerElder: [{ at: 253, to: 317, src: "cheer_recv", from: 4.6 }], // 收到家人語音
    cheerFamily: [{ at: 253, to: 317, src: "cheer_send", from: 8.7 }], // 送出鼓勵
    questionElder: [],
    questionFamily: [],
    pig: [{ at: 313, to: 375, src: "pig", from: 1.2 }],
  },
  CUE: {
    hookLine1: 8,
    hookLine2: 28,
    hookNote: 46,
    alertTitleSwap: 99999,
    alertTap: NONE,
    alertPush: null,
    summaryCard: 84,
    summaryLines: [90, 100, 110],
    heartIn: [122, 144],
    elderPull: null,
    elderTitleSwap: 99999,
    elderTap: 166,
    chatQuote: 99999,
    chatPull: null,
    ttsStart: 201,
    ttsEnd: 253,
    cheerTap: NONE,
    cheerTitles: [{ at: 259, key: "title3" }],
    cheerDotGo: null,
    cheerDotBack: [277, 297],
    voiceStart: 297,
    voiceEnd: 315,
    questionStrike: NONE,
    questionFresh: NONE,
    questionCards: NONE,
    questionDot: null,
    questionQuote1: NONE,
    questionQuote2: NONE,
    pigStages: [322, 328, 334, 340, 346],
    heartOut: [348, 370],
    outroLogo: 365,
    outroTagline: 380,
    outroPoints: 404,
  },
  MUSIC: { at: 135, src: "music_15.wav", vol: 0.66, duckVol: 0.16, duck: [[199, 255], [295, 353]] },
  SOUNDS: [
    { at: 0, src: "drone.wav", vol: 0.45, dur: 140 },
    { at: 4, src: "thud.wav", vol: 0.8 },
    { at: 68, src: "whoosh.wav", vol: 0.5 },
    { at: 78, src: "alert_real.wav", vol: 0.5, dur: 56 },
    { at: 122, src: "whoosh.wav", vol: 0.45 },
    { at: 166, src: "ding.wav", vol: 0.5 },
    { at: 201, src: "tts_taiwanese.wav", vol: 1, dur: 54 }, // 小嘎台語原聲（只取開頭）
    { at: 277, src: "whoosh.wav", vol: 0.35 },
    { at: 297, src: "pop.wav", vol: 0.6 },
    { at: 297, src: "cheer_voice.wav", vol: 1, dur: 62 }, // 家人鼓勵原聲
    ...[322, 328, 334, 340, 346].map((at) => ({ at, src: "tick.wav", vol: 0.4 })),
    { at: 348, src: "whoosh.wav", vol: 0.4 },
    { at: 380, src: "ding.wav", vol: 0.3 },
  ],
};

// ================= 版面（位置、大小）=================
// 手機位置 x/y 是相對畫面中心的位移；其他 x/y 是畫面上的絕對座標（左上角為 0,0）
type P2 = [number, number];
type Arc = { a: P2; b: P2; c: P2 }; // 光點：起點、終點、弧線控制點
type Geo = {
  W: number;
  H: number;
  badgeY: number;
  titleSize: number;
  titleW: number;
  hook: { cx: string; cy: string; ring: P2; ry: number; s: Span; textX: number; line1Y: number; line2Y: number; noteY: number; size: number };
  alert: { phone: Pose; push: { dx: number; ry: number; ds: number }; glow: P2; title: P2; card: { x: number; y: number; w: number; font: number; row: number } };
  turn: { y1: number; y2: number; size1: number; size2: number };
  elder: { phone: Pose; title: P2; pull: { dx: number; dy: number; z: number; s: number } };
  chat: { phone: Pose; driftX: number; title: P2; quote: P2; voice: P2; pull: { dx: number; dy: number; z: number; s: number } };
  cheer: { elder: Pose; family: Pose; enterDX: number; chipY: number; chipElderX: number; chipFamilyX: number; titleY: number; titleSize: number; titleW: number; waveY: number; go: Arc; back: Arc };
  question: { oldY: number; freshY: number; oldSize: number; freshSize: number; elder: Pose; family: Pose; chipY: number; chipElderX: number; chipFamilyX: number; title: P2; q1: P2; q2: P2; dot: Arc };
  pig: { phone: Pose; title: P2; row: { x: number; y: number; w: number; h: number }; heights: number[]; lineY: number; labelY: number };
  outro: { logoY: number; icon: number; word: number; taglineY: number; taglineSize: number; subY: number; pointsY: number; column: boolean };
};

const GEO: Record<"wide" | "tall", Geo> = {
  // ---- 橫式 1920×1080：手機一側、文字另一側 ----
  wide: {
    W: 1920,
    H: 1080,
    badgeY: 30,
    titleSize: 84,
    titleW: 760,
    hook: { cx: "73%", cy: "50%", ring: [1400, 540], ry: -26, s: [0.84, 0.98], textX: 130, line1Y: 330, line2Y: 474, noteY: 660, size: 108 },
    alert: { phone: { x: 440, y: 0, ry: -18, rx: 6, rz: 2, s: 1 }, push: { dx: -40, ry: 8, ds: 0.08 }, glow: [1400, 540], title: [130, 176], card: { x: 130, y: 520, w: 660, font: 38, row: 50 } },
    turn: { y1: 388, y2: 540, size1: 104, size2: 72 },
    elder: { phone: { x: -430, y: 0, ry: 20, rx: 6, rz: -2, s: 1 }, title: [1150, 330], pull: { dx: 210, dy: -30, z: 240, s: 1.28 } },
    chat: { phone: { x: 440, y: 0, ry: -20, rx: 6, rz: 2, s: 1 }, driftX: -24, title: [130, 220], quote: [130, 556], voice: [130, 650], pull: { dx: -250, dy: -40, z: 220, s: 1.55 } },
    cheer: {
      elder: { x: -600, y: 30, ry: 16, rx: 5, rz: -1.5, s: 0.88 },
      family: { x: 600, y: 30, ry: -16, rx: 5, rz: 1.5, s: 0.88 },
      enterDX: 300,
      chipY: 96,
      chipElderX: 360,
      chipFamilyX: 1560,
      titleY: 390,
      titleSize: 78,
      titleW: 660,
      waveY: 590,
      go: { a: [430, 872], b: [1456, 540], c: [940, -300] },
      back: { a: [1560, 880], b: [360, 560], c: [960, -300] },
    },
    question: {
      oldY: 360,
      freshY: 560,
      oldSize: 120,
      freshSize: 76,
      elder: { x: 222, y: 14, ry: -14, rx: 5, rz: 1.5, s: 0.84 },
      family: { x: 618, y: 14, ry: -14, rx: 5, rz: 1.5, s: 0.84 },
      chipY: 44,
      chipElderX: 1172,
      chipFamilyX: 1588,
      title: [130, 250],
      q1: [130, 610],
      q2: [130, 700],
      dot: { a: [1182, 900], b: [1590, 430], c: [1350, 300] },
    },
    pig: { phone: { x: -430, y: 0, ry: 18, rx: 6, rz: -2, s: 1 }, title: [1010, 200], row: { x: 1010, y: 580, w: 790, h: 260 }, heights: [115, 142, 174, 208, 246], lineY: 852, labelY: 872 },
    outro: { logoY: 250, icon: 170, word: 160, taglineY: 500, taglineSize: 68, subY: 620, pointsY: 770, column: false },
  },
  // ---- 直式 1080×1920：文字在上、手機在下；雙機左右並排 ----
  tall: {
    W: 1080,
    H: 1920,
    badgeY: 150,
    titleSize: 84,
    titleW: 900,
    hook: { cx: "50%", cy: "66%", ring: [540, 1267], ry: -18, s: [0.98, 1.14], textX: 90, line1Y: 250, line2Y: 384, noteY: 540, size: 100 },
    alert: { phone: { x: 0, y: 405, ry: -12, rx: 6, rz: 1.5, s: 1.05 }, push: { dx: 0, ry: 6, ds: 0.04 }, glow: [540, 1365], title: [90, 220], card: { x: 90, y: 530, w: 900, font: 34, row: 46 } },
    turn: { y1: 800, y2: 950, size1: 96, size2: 68 },
    elder: { phone: { x: 0, y: 330, ry: 14, rx: 6, rz: -2, s: 1.18 }, title: [90, 240], pull: { dx: 60, dy: -50, z: 240, s: 1.2 } },
    chat: { phone: { x: 0, y: 400, ry: -14, rx: 6, rz: 2, s: 1 }, driftX: 0, title: [90, 220], quote: [90, 540], voice: [90, 632], pull: { dx: -70, dy: -75, z: 240, s: 1.6 } },
    cheer: {
      elder: { x: -262, y: 250, ry: 10, rx: 5, rz: -1, s: 1.08 },
      family: { x: 262, y: 250, ry: -10, rx: 5, rz: 1, s: 1.08 },
      enterDX: 300,
      chipY: 640,
      chipElderX: 278,
      chipFamilyX: 802,
      titleY: 230,
      titleSize: 78,
      titleW: 900,
      waveY: 1740,
      go: { a: [348, 1615], b: [667, 1176], c: [500, 620] },
      back: { a: [802, 1615], b: [278, 1230], c: [540, 640] },
    },
    question: {
      oldY: 760,
      freshY: 950,
      oldSize: 110,
      freshSize: 72,
      elder: { x: -240, y: 345, ry: -8, rx: 5, rz: 1, s: 0.9 },
      family: { x: 240, y: 345, ry: -8, rx: 5, rz: 1, s: 0.9 },
      chipY: 704,
      chipElderX: 300,
      chipFamilyX: 780,
      title: [90, 220],
      q1: [90, 536],
      q2: [90, 612],
      dot: { a: [300, 1672], b: [780, 1100], c: [540, 900] },
    },
    pig: { phone: { x: 0, y: 395, ry: 12, rx: 6, rz: -2, s: 1.04 }, title: [90, 220], row: { x: 90, y: 540, w: 900, h: 220 }, heights: [96, 119, 146, 175, 206], lineY: 772, labelY: 790 },
    outro: { logoY: 610, icon: 170, word: 160, taglineY: 880, taglineSize: 64, subY: 1000, pointsY: 1170, column: true },
  },
};
// ============================================================

export const AD60_FRAMES = TL60.total;
export const AD15_FRAMES = TL15.total;

const ease = Easing.bezier(0.22, 1, 0.36, 1);
const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const vis = (f: number, [a, b]: Span, fi = 7, fo = 7) => Math.min(interpolate(f, [a, a + fi], [0, 1], clamp), interpolate(f, [b - fo, b], [1, 0], clamp));
const typed = (text: string, f: number, start: number, perFrame = 1.1) => text.slice(0, Math.max(0, Math.floor((f - start) * perFrame)));

type ShotProps = { frame: number; tl: Timeline; g: Geo };
const FastCtx = React.createContext(false); // 15 秒版：標題進場加快

// ---------- 小元件 ----------
const Eyebrow: React.FC<{ text: string; dark?: boolean; o?: number }> = ({ text, dark, o = 1 }) => (
  <div
    style={{
      display: "inline-block",
      padding: "8px 20px",
      borderRadius: 999,
      background: dark ? "rgba(127,211,176,0.16)" : C.glow,
      color: dark ? C.brandOnDark : C.brandDeep,
      fontSize: 28,
      fontWeight: 800,
      letterSpacing: 2,
      opacity: o,
      whiteSpace: "nowrap",
    }}
  >
    {text}
  </div>
);

// 標題：逐字彈入；end 之前 8 格往上淡出
const Headline: React.FC<{
  frame: number;
  start: number;
  end?: number;
  x: number;
  y: number;
  lines: readonly string[];
  eyebrow?: string;
  size?: number;
  dark?: boolean;
  colors?: string[];
  center?: boolean;
  width?: number;
}> = ({ frame, start, end, x, y, lines, eyebrow, size = 84, dark, colors, center, width = 760 }) => {
  const fast = React.useContext(FastCtx);
  if (frame < start - 2 || (end !== undefined && frame > end)) return null;
  const out = end !== undefined ? interpolate(frame, [end - 8, end], [0, 1], { ...clamp, easing: ease }) : 0;
  return (
    <div
      style={{
        position: "absolute",
        left: center ? x - width / 2 : x,
        top: y,
        width,
        fontFamily: FONT,
        opacity: 1 - out,
        transform: `translateY(${-out * 24}px)`,
        textAlign: center ? "center" : "left",
      }}
    >
      {eyebrow && <Eyebrow text={eyebrow} dark={dark} o={interpolate(frame, [start, start + 10], [0, 1], clamp)} />}
      <div style={{ marginTop: eyebrow ? 22 : 0 }}>
        {lines.map((line, i) => (
          <div key={i} style={{ display: "flex", justifyContent: center ? "center" : "flex-start", lineHeight: 1.24 }}>
            <Kinetic text={line} frame={frame} start={fast ? start - 4 + i * 5 : start + 4 + i * 9} size={size} color={colors?.[i] ?? (dark ? C.cream : C.ink)} />
          </div>
        ))}
      </div>
    </div>
  );
};

const Chip: React.FC<{ frame: number; start: number; x: number; y: number; text: string }> = ({ frame, start, x, y, text }) => {
  const t = spring({ frame: frame - start, fps: AD_FPS, config: { damping: 18 } });
  return (
    <div style={{ position: "absolute", left: x - 150, top: y, width: 300, textAlign: "center", fontFamily: FONT, opacity: t, transform: `translateY(${(1 - t) * 14}px)` }}>
      <span style={{ display: "inline-block", padding: "7px 20px", borderRadius: 999, background: "#FFFFFF", color: C.brandDeep, fontSize: 26, fontWeight: 800, boxShadow: "0 6px 18px rgba(28,41,37,0.10)", whiteSpace: "nowrap" }}>{text}</span>
    </div>
  );
};

const Glow: React.FC<{ x: number; y: number; o?: number }> = ({ x, y, o = 1 }) => (
  <div style={{ position: "absolute", left: x - 620, top: y - 620, width: 1240, height: 1240, borderRadius: "50%", background: `radial-gradient(circle, ${C.glow} 0%, rgba(221,241,232,0) 64%)`, opacity: o }} />
);

// 綠色光點沿弧線飛行（a → b，c 為弧線控制點），落地後一圈波紋
const FlyDot: React.FC<{ frame: number; span: Span | null; arc: Arc }> = ({ frame, span, arc }) => {
  if (!span) return null;
  const [f0, f1] = span;
  if (frame < f0 || frame > f1 + 16) return null;
  const { a, b, c } = arc;
  const at = (t: number): P2 => {
    const u = 1 - t;
    return [u * u * a[0] + 2 * u * t * c[0] + t * t * b[0], u * u * a[1] + 2 * u * t * c[1] + t * t * b[1]];
  };
  const p = interpolate(frame, [f0, f1], [0, 1], { ...clamp, easing: Easing.inOut(Easing.cubic) });
  const land = interpolate(frame, [f1, f1 + 16], [0, 1], clamp);
  return (
    <>
      {frame <= f1 &&
        Array.from({ length: 9 }).map((_, i) => {
          const [x, y] = at(Math.max(0, p - i * 0.035));
          const s = 1 - i / 10;
          return <div key={i} style={{ position: "absolute", left: x - 17, top: y - 17, width: 34, height: 34, borderRadius: "50%", background: C.brand, opacity: i === 0 ? 1 : 0.5 * s, transform: `scale(${s})`, boxShadow: i === 0 ? `0 0 30px 10px rgba(89,178,148,0.55)` : undefined }} />;
        })}
      {frame > f1 && <div style={{ position: "absolute", left: b[0] - 60, top: b[1] - 60, width: 120, height: 120, borderRadius: "50%", border: `6px solid ${C.brand}`, transform: `scale(${0.3 + land * 1.2})`, opacity: 1 - land }} />}
    </>
  );
};

// 愛心遮罩：品牌愛心從畫面中央擴大蓋滿畫面
const HeartWipe: React.FC<{ frame: number; span: Span; color: string }> = ({ frame, span, color }) => {
  if (frame < span[0]) return null;
  const s = interpolate(frame, [span[0], span[1]], [0, 150], { ...clamp, easing: Easing.in(Easing.cubic) });
  return (
    <svg width={1} height={1} style={{ position: "absolute", left: "50%", top: "50%", overflow: "visible" }}>
      <path d="M0 27 C-26 9 -34 -5 -24 -17 C-14 -27 -2 -21 0 -11 C2 -21 14 -27 24 -17 C34 -5 26 9 0 27 Z" fill={color} transform={`scale(${s})`} />
    </svg>
  );
};

const SpeakerIcon: React.FC<{ color: string }> = ({ color }) => (
  <svg viewBox="0 0 48 48" width={56} height={56}>
    <path d="M8 19 h8 l10 -9 v28 l-10 -9 h-8 z" fill={color} />
    <path d="M32 17 q6 7 0 14 M37 12 q11 12 0 24" fill="none" stroke={color} strokeWidth={3.5} strokeLinecap="round" />
  </svg>
);

const VoiceCard: React.FC<{ frame: number; start: number; x: number; y: number; active: boolean; title: string; note: string }> = ({ frame, start, x, y, active, title, note }) => {
  const t = spring({ frame: frame - start, fps: AD_FPS, config: { damping: 18 } });
  return (
    <div style={{ position: "absolute", left: x, top: y, width: 620, height: 132, boxSizing: "border-box", borderRadius: 30, background: "#FFFFFF", boxShadow: "0 18px 44px rgba(28,41,37,0.12)", display: "flex", alignItems: "center", gap: 18, padding: "0 26px", fontFamily: FONT, opacity: t, transform: `translateY(${(1 - t) * 26}px)` }}>
      <SpeakerIcon color={C.brandDeep} />
      <div style={{ width: 150, height: 80, overflow: "hidden", flexShrink: 0 }}>
        <div style={{ transform: "scale(0.66)", transformOrigin: "0 50%", width: 228, opacity: active ? 1 : 0.35 }}>
          <Waveform frame={active ? frame : 3} />
        </div>
      </div>
      <div style={{ minWidth: 0 }}>
        <div style={{ fontSize: 34, fontWeight: 800, color: C.ink, whiteSpace: "nowrap" }}>{title}</div>
        <div style={{ fontSize: 24, fontWeight: 600, color: C.muted, marginTop: 4, whiteSpace: "nowrap" }}>{note}</div>
      </div>
    </div>
  );
};

const Quote: React.FC<{ frame: number; start: number; x: number; y: number; label: string; text: string }> = ({ frame, start, x, y, label, text }) => {
  const t = spring({ frame: frame - start, fps: AD_FPS, config: { damping: 18 } });
  if (frame < start) return null;
  return (
    <div style={{ position: "absolute", left: x, top: y, fontFamily: FONT, opacity: t, transform: `translateY(${(1 - t) * 22}px)`, display: "flex", alignItems: "center", gap: 18 }}>
      <span style={{ padding: "6px 16px", borderRadius: 12, background: C.brand, color: "#fff", fontSize: 26, fontWeight: 800, whiteSpace: "nowrap" }}>{label}</span>
      <span style={{ fontSize: 40, fontWeight: 700, color: C.ink, whiteSpace: "nowrap" }}>{text}</span>
    </div>
  );
};

// ---------- 鏡頭 ----------
// S0 開場：暗底、監控機實機畫面、滑動變焦
const Hook: React.FC<ShotProps> = ({ frame, tl, g }) => {
  const [, b] = tl.T.hook;
  const { CUE, COPY: copy } = tl;
  const h = g.hook;
  if (frame > b) return null;
  const out = interpolate(frame, [b - 9, b], [0, 1], { ...clamp, easing: Easing.in(Easing.cubic) });
  const fadeIn = interpolate(frame, [0, 10], [0, 1], clamp);
  const P = kf(frame, [[4, 640], [b - 12, 2300]]); // 透視由強到弱＝滑動變焦
  const pose: Pose = { x: 0, y: 0, ry: h.ry, rx: 9, rz: 3, s: kf(frame, [[0, h.s[0]], [b - 8, h.s[1]]]) };
  const ring = interpolate(frame, [0, b], [0.7, 1.5]);
  return (
    <AbsoluteFill style={{ opacity: fadeIn * (1 - out), transform: `translateX(${-out * 460}px)`, filter: out > 0 ? `blur(${out * 12}px)` : undefined }}>
      {[520, 820, 1160].map((d, i) => (
        <div key={i} style={{ position: "absolute", left: h.ring[0] - d / 2, top: h.ring[1] - d / 2, width: d, height: d, borderRadius: "50%", border: "2px solid rgba(255,246,232,0.07)", transform: `scale(${ring})` }} />
      ))}
      <Stage perspective={P} cx={h.cx} cy={h.cy}>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={<ClipView segs={tl.CLIPS.hook} />} />
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={CUE.hookLine1} x={h.textX} y={h.line1Y} lines={[copy.hook.lines[0]]} size={h.size} dark width={g.titleW} />
      <Headline frame={frame} start={CUE.hookLine2} x={h.textX} y={h.line2Y} lines={[copy.hook.lines[1]]} size={h.size} dark colors={[C.warm]} width={900} />
      <div style={{ position: "absolute", left: h.textX + 6, top: h.noteY, fontFamily: FONT, fontSize: 30, fontWeight: 600, color: C.creamDim, opacity: interpolate(frame, [CUE.hookNote, CUE.hookNote + 14], [0, 1], clamp), borderLeft: `6px solid ${C.warm}`, paddingLeft: 16, whiteSpace: "nowrap" }}>{copy.hook.note}</div>
    </AbsoluteFill>
  );
};

// S1 警報：家屬機實機畫面＋情境摘要字卡
const Alert: React.FC<ShotProps> = ({ frame, tl, g }) => {
  const [a] = tl.T.alert;
  const { CUE, COPY: copy } = tl;
  const q = g.alert;
  if (frame < a - 2 || frame > CUE.heartIn[1] + 2) return null;
  const inn = interpolate(frame, [a - 2, a + 12], [0, 1], { ...clamp, easing: ease });
  const push = CUE.alertPush ? kf(frame, [[CUE.alertPush[0], 0], [CUE.alertPush[1], 1]]) : 0;
  const pose: Pose = { ...q.phone, x: q.phone.x + push * q.push.dx, ry: q.phone.ry + push * q.push.ry, rz: q.phone.rz * (1 - push * 0.5), s: (q.phone.s ?? 1) + push * q.push.ds };
  const card = spring({ frame: frame - CUE.summaryCard, fps: AD_FPS, config: { damping: 18 } });
  return (
    <AbsoluteFill style={{ opacity: inn, transform: `translateX(${(1 - inn) * 460}px)`, filter: inn < 1 ? `blur(${(1 - inn) * 12}px)` : undefined }}>
      <div style={{ position: "absolute", left: q.glow[0] - 560, top: q.glow[1] - 560, width: 1120, height: 1120, borderRadius: "50%", background: "radial-gradient(circle, rgba(255,107,107,0.16) 0%, rgba(255,107,107,0) 62%)", opacity: 0.6 + 0.4 * Math.sin(frame / 6) }} />
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={<ClipView segs={tl.CLIPS.alert} />}>
            <Tap frame={frame} at={CUE.alertTap} nx={0.5} ny={0.858} />
          </Phone3D>
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 8} end={CUE.alertTitleSwap} x={q.title[0]} y={q.title[1]} eyebrow={copy.alert.eyebrow} lines={copy.alert.title1} size={g.titleSize} width={g.titleW} dark />
      <Headline frame={frame} start={CUE.alertTitleSwap} x={q.title[0]} y={q.title[1]} eyebrow={copy.alert.eyebrow} lines={copy.alert.title2} size={g.titleSize} width={g.titleW} dark />
      {/* 情境摘要字卡（不是 App 畫面，所以放在手機外面） */}
      <div style={{ position: "absolute", left: q.card.x, top: q.card.y, width: q.card.w, boxSizing: "border-box", padding: "26px 34px", borderRadius: 30, background: "rgba(255,246,232,0.07)", border: "2px solid rgba(255,246,232,0.16)", fontFamily: FONT, opacity: card, transform: `translateY(${(1 - card) * 30}px)` }}>
        <div style={{ fontSize: 30, fontWeight: 800, color: C.brandOnDark, letterSpacing: 1 }}>{copy.alert.summaryTitle}</div>
        {copy.alert.summary.map((line, i) => (
          <div key={i} style={{ marginTop: 14, fontSize: q.card.font, fontWeight: 700, color: C.cream, height: q.card.row, whiteSpace: "nowrap", display: "flex", alignItems: "center", gap: 14 }}>
            <span style={{ width: 12, height: 12, borderRadius: "50%", background: C.warm, opacity: frame >= CUE.summaryLines[i] ? 1 : 0.2 }} />
            {typed(line, frame, CUE.summaryLines[i], tl.total < 900 ? 2.2 : 1.1)}
          </div>
        ))}
        <div style={{ marginTop: 16, fontSize: 22, fontWeight: 600, color: "rgba(255,246,232,0.5)" }}>{copy.alert.summaryNote}</div>
      </div>
    </AbsoluteFill>
  );
};

// S2 轉折：愛心遮罩之後的一句話
const Turn: React.FC<ShotProps> = ({ frame, tl, g }) => {
  const [a, b] = tl.T.turn;
  if (frame < a || frame > b) return null;
  const out = interpolate(frame, [b - 8, b], [0, 1], clamp);
  return (
    <AbsoluteFill style={{ opacity: 1 - out, fontFamily: FONT }}>
      <div style={{ position: "absolute", left: 0, right: 0, top: g.turn.y1, display: "flex", justifyContent: "center" }}>
        <Kinetic text={tl.COPY.turn.line1} frame={frame} start={a + 10} size={g.turn.size1} color={C.ink} />
      </div>
      <div style={{ position: "absolute", left: 0, right: 0, top: g.turn.y2, display: "flex", justifyContent: "center" }}>
        <Kinetic text={tl.COPY.turn.line2} frame={frame} start={a + 24} size={g.turn.size2} color={C.brandDeep} />
      </div>
    </AbsoluteFill>
  );
};

// S3 長輩端：首頁大字 → 提醒 → 打卡
const Elder: React.FC<ShotProps> = ({ frame, tl, g }) => {
  const [a, b] = tl.T.elder;
  const { CUE, COPY: copy } = tl;
  const q = g.elder;
  if (frame < a || frame > b) return null;
  const rise = Math.min(34, b - a - 8); // 俯衝抬起的長度
  const pose: Pose = { ...q.phone, y: q.phone.y + kf(frame, [[a, 240], [a + rise, 0]]), rx: kf(frame, [[a, 58], [a + rise, q.phone.rx]]), s: (q.phone.s ?? 1) * kf(frame, [[a, 0.78], [a + rise, 1]]) };
  const pk = CUE.elderPull;
  return (
    <AbsoluteFill style={{ opacity: vis(frame, tl.T.elder) }}>
      <Glow x={g.W / 2 + q.phone.x} y={g.H / 2 + q.phone.y} />
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={<ClipView segs={tl.CLIPS.elder} />}>
            {/* 把「今天」日期卡從螢幕拉出來放大 */}
            {pk && (
              <PullOut frame={frame} rect={{ x: 0.03, y: 0.162, w: 0.94, h: 0.218 }} pose={pose} keys={[{ f: pk[0] }, { f: pk[1], ...q.pull, face: 1 }, { f: pk[2], ...q.pull, face: 1 }, { f: pk[3] }]}>
                <ClipView segs={tl.CLIPS.elder} />
              </PullOut>
            )}
            <Tap frame={frame} at={CUE.elderTap} nx={0.667} ny={0.6} />
          </Phone3D>
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 8} end={CUE.elderTitleSwap} x={q.title[0]} y={q.title[1]} eyebrow={copy.elder.eyebrow} lines={copy.elder.title1} size={g.titleSize} width={g.titleW} />
      <Headline frame={frame} start={CUE.elderTitleSwap} x={q.title[0]} y={q.title[1]} eyebrow={copy.elder.eyebrow} lines={copy.elder.title2} size={g.titleSize} width={g.titleW} />
    </AbsoluteFill>
  );
};

// S4 小嘎：台語原聲
const Chat: React.FC<ShotProps> = ({ frame, tl, g }) => {
  const [a, b] = tl.T.chat;
  const { CUE, COPY: copy } = tl;
  const q = g.chat;
  if (frame < a || frame > b) return null;
  const enter = spring({ frame: frame - a, fps: AD_FPS, config: { damping: 18 } });
  const drift = interpolate(frame, [a, b], [0, 1]); // 整段慢慢推近
  const pose: Pose = { ...q.phone, x: q.phone.x + drift * q.driftX, y: q.phone.y + (1 - enter) * 260, ry: q.phone.ry + (1 - enter) * -24 + drift * 8, rz: q.phone.rz - drift, s: (q.phone.s ?? 1) + drift * 0.05 };
  const pk = CUE.chatPull;
  return (
    <AbsoluteFill style={{ opacity: vis(frame, tl.T.chat) }}>
      <Glow x={g.W / 2 + q.phone.x} y={g.H / 2 + q.phone.y} />
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={<ClipView segs={tl.CLIPS.chat} />}>
            {/* 國語／台語切換鈕拉出放大 */}
            {pk && (
              <PullOut frame={frame} rect={{ x: 0.03, y: 0.118, w: 0.36, h: 0.062 }} pose={pose} radius={16} keys={[{ f: pk[0] }, { f: pk[1], ...q.pull, face: 1 }, { f: pk[2], ...q.pull, face: 1 }, { f: pk[3] }]}>
                <ClipView segs={tl.CLIPS.chat} />
              </PullOut>
            )}
          </Phone3D>
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 8} x={q.title[0]} y={q.title[1]} eyebrow={copy.chat.eyebrow} lines={copy.chat.title} size={g.titleSize} width={g.titleW} />
      <Quote frame={frame} start={CUE.chatQuote} x={q.quote[0]} y={q.quote[1]} label={copy.chat.elderSays} text={copy.chat.elderQuote} />
      <VoiceCard frame={frame} start={CUE.ttsStart - 8} x={q.voice[0]} y={q.voice[1]} active={frame >= CUE.ttsStart && frame <= CUE.ttsEnd} title={copy.chat.voiceTitle} note={copy.chat.voiceNote} />
    </AbsoluteFill>
  );
};

// S5 打卡與鼓勵：雙機對話＋光點來回
const Cheer: React.FC<ShotProps> = ({ frame, tl, g }) => {
  const [a, b] = tl.T.cheer;
  const { CUE, COPY: copy } = tl;
  const q = g.cheer;
  if (frame < a || frame > b) return null;
  const enter = spring({ frame: frame - a, fps: AD_FPS, config: { damping: 20 } });
  const elder: Pose = { ...q.elder, x: q.elder.x - (1 - enter) * q.enterDX };
  const pulse = CUE.cheerDotGo ? interpolate(frame, [CUE.cheerDotGo[1], CUE.cheerDotGo[1] + 14], [1, 0], clamp) : 0;
  const family: Pose = { ...q.family, x: q.family.x + (1 - enter) * q.enterDX, s: (q.family.s ?? 1) * (1 + (frame >= (CUE.cheerDotGo?.[1] ?? 1e9) ? pulse * 0.03 : 0)) };
  const titles = CUE.cheerTitles;
  const voiceOn = frame >= CUE.voiceStart && frame <= CUE.voiceEnd;
  return (
    <AbsoluteFill style={{ opacity: vis(frame, tl.T.cheer) }}>
      <Glow x={g.W / 2} y={g.H / 2 + q.elder.y} />
      <Stage>
        <PhoneAt pose={elder}>
          <Phone3D frame={frame} screen={<ClipView segs={tl.CLIPS.cheerElder} />}>
            <Tap frame={frame} at={CUE.cheerTap} nx={0.667} ny={0.6} />
          </Phone3D>
        </PhoneAt>
        <PhoneAt pose={family}>
          <Phone3D frame={frame} screen={<ClipView segs={tl.CLIPS.cheerFamily} />} />
        </PhoneAt>
      </Stage>
      <Chip frame={frame} start={a + 10} x={q.chipElderX} y={q.chipY} text={copy.cheer.elderChip} />
      <Chip frame={frame} start={a + 14} x={q.chipFamilyX} y={q.chipY} text={copy.cheer.familyChip} />
      {titles.map((t, i) => (
        <Headline key={i} frame={frame} start={t.at} end={titles[i + 1] ? titles[i + 1].at - 2 : undefined} x={g.W / 2} y={q.titleY} lines={copy.cheer[t.key]} size={q.titleSize} center width={q.titleW} />
      ))}
      {frame >= titles[titles.length - 1].at + 16 && (
        <div style={{ position: "absolute", left: g.W / 2 - 114, top: q.waveY, width: 228, opacity: voiceOn ? 1 : 0.3 }}>
          <Waveform frame={voiceOn ? frame : 3} />
        </div>
      )}
      <FlyDot frame={frame} span={CUE.cheerDotGo} arc={q.go} />
      <FlyDot frame={frame} span={CUE.cheerDotBack} arc={q.back} />
    </AbsoluteFill>
  );
};

// S6 每日一問：「有吃飯嗎？」→ 雙機
const Question: React.FC<ShotProps> = ({ frame, tl, g }) => {
  const [a, b] = tl.T.question;
  const { CUE, COPY: copy } = tl;
  const q = g.question;
  if (frame < a || frame > b) return null;
  const strike = interpolate(frame, [CUE.questionStrike, CUE.questionStrike + 10], [0, 1], { ...clamp, easing: ease });
  const cardOut = interpolate(frame, [CUE.questionCards - 9, CUE.questionCards], [0, 1], clamp);
  const enter = spring({ frame: frame - CUE.questionCards, fps: AD_FPS, config: { damping: 20 } });
  const swap = CUE.questionDot ? CUE.questionDot[1] : b;
  const focus = kf(frame, [[swap - 10, 1], [swap + 8, 0]]); // 1＝長輩機在前
  const elder: Pose = { ...q.elder, y: q.elder.y + (1 - enter) * 320, z: focus * 60, s: (q.elder.s ?? 1) + focus * 0.1 };
  const family: Pose = { ...q.family, y: q.family.y + (1 - enter) * 420, z: (1 - focus) * 60, s: (q.family.s ?? 1) + (1 - focus) * 0.1 };
  return (
    <AbsoluteFill style={{ opacity: vis(frame, tl.T.question) }}>
      <Glow x={g.W / 2 + (q.elder.x + q.family.x) / 2} y={g.H / 2 + q.elder.y} o={interpolate(frame, [CUE.questionCards, CUE.questionCards + 14], [0, 1], clamp)} />
      {frame < CUE.questionCards && (
        <AbsoluteFill style={{ fontFamily: FONT, opacity: 1 - cardOut, transform: `translateY(${-cardOut * 30}px)` }}>
          <div style={{ position: "absolute", left: 0, right: 0, top: q.oldY, display: "flex", justifyContent: "center" }}>
            <div style={{ position: "relative" }}>
              <Kinetic text={copy.question.old} frame={frame} start={a + 2} size={q.oldSize} color={C.muted} />
              <div style={{ position: "absolute", left: -20, right: -20, top: "52%", height: 10, borderRadius: 5, background: C.brand, transformOrigin: "0 50%", transform: `scaleX(${strike})` }} />
            </div>
          </div>
          <div style={{ position: "absolute", left: 0, right: 0, top: q.freshY, display: "flex", justifyContent: "center" }}>
            <Kinetic text={copy.question.fresh} frame={frame} start={CUE.questionFresh} size={q.freshSize} color={C.brandDeep} />
          </div>
        </AbsoluteFill>
      )}
      {frame >= CUE.questionCards - 2 && (
        <>
          <Stage>
            <PhoneAt pose={elder}>
              <Phone3D frame={frame} dim={(1 - focus) * 0.45} screen={<ClipView segs={tl.CLIPS.questionElder} />} />
            </PhoneAt>
            <PhoneAt pose={family}>
              <Phone3D frame={frame} dim={focus * 0.45} screen={<ClipView segs={tl.CLIPS.questionFamily} />} />
            </PhoneAt>
          </Stage>
          <Chip frame={frame} start={CUE.questionCards + 12} x={q.chipElderX} y={q.chipY} text={copy.cheer.elderChip} />
          <Chip frame={frame} start={CUE.questionCards + 16} x={q.chipFamilyX} y={q.chipY} text={copy.cheer.familyChip} />
          <Headline frame={frame} start={CUE.questionCards + 4} x={q.title[0]} y={q.title[1]} eyebrow={copy.question.eyebrow} lines={copy.question.title} size={g.titleSize} width={g.titleW} />
          <Quote frame={frame} start={CUE.questionQuote1} x={q.q1[0]} y={q.q1[1]} label={copy.question.elderSays} text={copy.question.elderQuote} />
          <Quote frame={frame} start={CUE.questionQuote2} x={q.q2[0]} y={q.q2[1]} label={copy.question.familySays} text={copy.question.familyQuote} />
          <FlyDot frame={frame} span={CUE.questionDot} arc={q.dot} />
        </>
      )}
    </AbsoluteFill>
  );
};

// S7 福氣小豬：實機餵食＋手繪五階段
const Pig: React.FC<ShotProps> = ({ frame, tl, g }) => {
  const [a] = tl.T.pig;
  const { CUE, COPY: copy } = tl;
  const q = g.pig;
  if (frame < a || frame > CUE.heartOut[1] + 2) return null;
  const enter = spring({ frame: frame - a, fps: AD_FPS, config: { damping: 18 } });
  const pose: Pose = { ...q.phone, y: q.phone.y + (1 - enter) * 260, ry: q.phone.ry + (1 - enter) * 24 };
  const last = CUE.pigStages[CUE.pigStages.length - 1];
  return (
    <AbsoluteFill style={{ opacity: interpolate(frame, [a, a + 7], [0, 1], clamp) }}>
      <Glow x={g.W / 2 + q.phone.x} y={g.H / 2 + q.phone.y} />
      <Stage>
        <PhoneAt pose={pose}>
          <Phone3D frame={frame} screen={<ClipView segs={tl.CLIPS.pig} />} />
        </PhoneAt>
      </Stage>
      <Headline frame={frame} start={a + 6} x={q.title[0]} y={q.title[1]} eyebrow={copy.pig.eyebrow} lines={copy.pig.title} size={g.titleSize} width={g.titleW} />
      <div style={{ position: "absolute", left: q.row.x, top: q.row.y, width: q.row.w, height: q.row.h, display: "flex", alignItems: "flex-end", gap: 18 }}>
        {q.heights.map((h, i) => {
          const t = spring({ frame: frame - CUE.pigStages[i], fps: AD_FPS, config: { damping: 9, mass: 0.7 } });
          return <Img key={i} src={staticFile(`ad/pig/pig_stage_${i + 1}.png`)} style={{ height: h, width: "auto", transformOrigin: "50% 100%", transform: `scale(${t})`, opacity: Math.min(1, t * 2) }} />;
        })}
      </div>
      <div style={{ position: "absolute", left: q.row.x, top: q.lineY, width: q.row.w - 10, height: 5, borderRadius: 3, background: "#CBD8D2", transformOrigin: "0 50%", transform: `scaleX(${interpolate(frame, [CUE.pigStages[0] - 6, last + 6], [0, 1], clamp)})` }} />
      <div style={{ position: "absolute", left: q.row.x, top: q.labelY, fontFamily: FONT, fontSize: 28, fontWeight: 700, color: C.muted, opacity: interpolate(frame, [last, last + 12], [0, 1], clamp) }}>{copy.pig.stages}</div>
    </AbsoluteFill>
  );
};

// S8 結尾：Logo、標語、三個重點
const Outro: React.FC<ShotProps> = ({ frame, tl, g }) => {
  const [a, b] = tl.T.outro;
  const { CUE, COPY: copy } = tl;
  const q = g.outro;
  if (frame < a) return null;
  const mark = spring({ frame: frame - CUE.outroLogo, fps: AD_FPS, config: { damping: 12, mass: 0.8 } });
  const word = spring({ frame: frame - CUE.outroLogo - 8, fps: AD_FPS, config: { damping: 18 } });
  const sub = interpolate(frame, [CUE.outroTagline + 26, CUE.outroTagline + 40], [0, 1], clamp);
  const fade = interpolate(frame, [b - 12, b], [1, 0], clamp);
  return (
    <AbsoluteFill style={{ fontFamily: FONT, opacity: fade }}>
      <div style={{ position: "absolute", left: g.W / 2 - 700, top: g.H / 2 - 700, width: 1400, height: 1400, borderRadius: "50%", background: "radial-gradient(circle, rgba(255,255,255,0.9) 0%, rgba(255,255,255,0) 60%)" }} />
      <div style={{ position: "absolute", left: 0, right: 0, top: q.logoY, display: "flex", justifyContent: "center", alignItems: "center", gap: 36 }}>
        <Img src={staticFile("ad/app_icon.png")} style={{ width: q.icon, height: q.icon, borderRadius: q.icon * 0.235, transform: `scale(${mark}) rotate(${(1 - mark) * -20}deg)`, boxShadow: "0 18px 40px rgba(77,173,136,0.35)" }} />
        <div style={{ fontSize: q.word, fontWeight: 800, letterSpacing: -4, color: C.ink, fontFamily: '"Segoe UI",' + FONT, opacity: word, transform: `translateX(${(1 - word) * -40}px)`, lineHeight: 1 }}>{copy.outro.wordmark}</div>
      </div>
      <div style={{ position: "absolute", left: 0, right: 0, top: q.taglineY, display: "flex", justifyContent: "center" }}>
        <Kinetic text={copy.outro.tagline} frame={frame} start={CUE.outroTagline} size={q.taglineSize} color={C.ink} />
      </div>
      <div style={{ position: "absolute", left: 0, right: 0, top: q.subY, textAlign: "center", fontSize: 32, fontWeight: 700, letterSpacing: 6, color: C.brandDeep, opacity: sub }}>{copy.outro.sub}</div>
      <div style={{ position: "absolute", left: 0, right: 0, top: q.pointsY, display: "flex", flexDirection: q.column ? "column" : "row", alignItems: "center", justifyContent: "center", gap: 26 }}>
        {copy.outro.points.map((p, i) => {
          const t = spring({ frame: frame - CUE.outroPoints - i * 10, fps: AD_FPS, config: { damping: 16 } });
          return (
            <div key={i} style={{ padding: "14px 30px", borderRadius: 999, background: "#FFFFFF", color: C.ink, fontSize: 32, fontWeight: 700, boxShadow: "0 10px 26px rgba(28,41,37,0.08)", opacity: t, transform: `translateY(${(1 - t) * 24}px)`, display: "flex", alignItems: "center", gap: 12, whiteSpace: "nowrap" }}>
              <span style={{ width: 14, height: 14, borderRadius: "50%", background: C.brand }} />
              {p}
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

// ---------- 主 composition ----------
export const Ad: React.FC<{ layout?: "wide" | "tall"; cut?: "full" | "short" }> = ({ layout = "wide", cut = "full" }) => {
  const frame = useCurrentFrame();
  const tl = cut === "short" ? TL15 : TL60;
  const g = GEO[layout];
  const { CUE, T, MUSIC } = tl;
  const isDark = frame < CUE.heartIn[1];
  const inTurn = frame >= T.turn[0] - 12 && frame < T.turn[1];
  const badge = Math.min(interpolate(frame, [T.alert[0] + 6, T.alert[0] + 20], [0, 1], clamp), interpolate(frame, [CUE.heartOut[0] - 8, CUE.heartOut[0]], [1, 0], clamp)) * (inTurn ? 0 : 1);
  const p: ShotProps = { frame, tl, g };
  return (
    <FastCtx.Provider value={cut === "short"}>
    <AbsoluteFill style={{ background: C.dark, overflow: "hidden" }}>
      {/* 暗場：開場與警報 */}
      {frame <= CUE.heartIn[1] + 2 && (
        <>
          <AbsoluteFill style={{ background: `radial-gradient(ellipse at ${g.hook.cx} ${g.hook.cy}, #1D2629 0%, #0F1416 60%, #080B0C 100%)` }} />
          <Hook {...p} />
          <Alert {...p} />
        </>
      )}
      {/* 愛心遮罩：暗轉亮 */}
      <HeartWipe frame={frame} span={CUE.heartIn} color={C.light} />
      {/* 亮場 */}
      {frame >= CUE.heartIn[0] && frame <= CUE.heartOut[1] + 2 && (
        <>
          <Turn {...p} />
          <Elder {...p} />
          <Chat {...p} />
          <Cheer {...p} />
          <Question {...p} />
          <Pig {...p} />
        </>
      )}
      {/* 愛心遮罩：進結尾 */}
      <HeartWipe frame={frame} span={CUE.heartOut} color={C.outro} />
      <Outro {...p} />

      {/* 實機錄影標示 */}
      <div style={{ position: "absolute", left: 0, right: 0, top: g.badgeY, textAlign: "center", fontFamily: FONT, fontSize: 22, fontWeight: 700, letterSpacing: 2, color: isDark ? "rgba(255,246,232,0.5)" : "rgba(28,41,37,0.42)", opacity: badge }}>{tl.COPY.badge}</div>

      {/* 聲音 */}
      <Sequence from={MUSIC.at} layout="none">
        <Audio
          src={staticFile(`ad/audio/${MUSIC.src}`)}
          volume={(f) => {
            const t = f + MUSIC.at;
            let v = MUSIC.vol;
            for (const [d0, d1] of MUSIC.duck) {
              const k = Math.min(interpolate(t, [d0 - 10, d0], [0, 1], clamp), interpolate(t, [d1, d1 + 14], [1, 0], clamp));
              v = Math.min(v, MUSIC.vol + (MUSIC.duckVol - MUSIC.vol) * k);
            }
            return v * interpolate(t, [tl.total - 24, tl.total], [1, 0], clamp);
          }}
        />
      </Sequence>
      {tl.SOUNDS.map((s, i) => (
        <Sequence key={i} from={s.at} durationInFrames={s.dur} layout="none">
          <Audio src={staticFile(`ad/audio/${s.src}`)} volume={s.dur ? (f) => s.vol * interpolate(f, [s.dur! - 10, s.dur!], [1, 0], clamp) : s.vol} />
        </Sequence>
      ))}
    </AbsoluteFill>
    </FastCtx.Provider>
  );
};
