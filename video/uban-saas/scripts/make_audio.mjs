// 合成廣告用的配樂與音效（純程式產生，沒有任何取樣或版權素材）。
// 執行：node scripts/make_audio.mjs   → 輸出到 public/ad/audio/
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// ================= 可直接修改的內容 =================
const BPM = 120; // 1 拍 = 15 影格，要和 src/Ad.tsx 的切點一致
// 每一支配樂：bars＝正常段落的小節數（每小節 2 秒）；endingAt＝配樂開始後第幾秒落下收尾和弦
// （= (結尾鏡頭起點 − 配樂起點) / 30）；length＝總長（秒）；full＝一開始就有鼓與旋律（短版用）
const MUSICS = [
  { name: "music.wav", bars: 20, endingAt: 41, length: 49.5, full: false }, // 60 秒版：(1560 − 330) / 30
  { name: "music_15.wav", bars: 3, endingAt: 7.5, length: 11.5, full: true }, // 15 秒版：(360 − 135) / 30
];
const DRONE_LENGTH = 11.5; // 開場低頻鋪底長度（秒）
// ===================================================

const SR = 44100;
const OUT = join(dirname(fileURLToPath(import.meta.url)), "..", "public", "ad", "audio");
mkdirSync(OUT, { recursive: true });

const buf = (sec) => ({ l: new Float32Array(Math.ceil(sec * SR)), r: new Float32Array(Math.ceil(sec * SR)) });
const midi = (n) => 440 * Math.pow(2, (n - 69) / 12);
let seed = 7;
const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647) * 2 - 1;

// 有泛音、指數衰減的音（像輕柔的鋼琴／拇指琴）
function tone(b, t0, freq, dur, amp, { harm = [1, 0.35, 0.12], decay = 0.5, attack = 0.004, pan = 0, vib = 0 } = {}) {
  const s0 = Math.floor(t0 * SR), n = Math.floor(dur * SR);
  const gl = amp * Math.cos(((pan + 1) * Math.PI) / 4), gr = amp * Math.sin(((pan + 1) * Math.PI) / 4);
  for (let i = 0; i < n; i++) {
    const idx = s0 + i;
    if (idx < 0 || idx >= b.l.length) continue;
    const t = i / SR;
    const env = Math.min(1, t / attack) * Math.exp(-t / decay) * Math.min(1, (dur - t) / 0.02);
    let v = 0;
    for (let h = 0; h < harm.length; h++) v += harm[h] * Math.sin(2 * Math.PI * freq * (h + 1) * t + (vib ? vib * Math.sin(2 * Math.PI * 5 * t) : 0));
    b.l[idx] += v * env * gl;
    b.r[idx] += v * env * gr;
  }
}
// 柔和的鋪底：慢起慢收
function pad(b, t0, freq, dur, amp) {
  const s0 = Math.floor(t0 * SR), n = Math.floor(dur * SR);
  for (let i = 0; i < n; i++) {
    const idx = s0 + i;
    if (idx < 0 || idx >= b.l.length) continue;
    const t = i / SR;
    const env = Math.min(1, t / 0.5) * Math.min(1, (dur - t) / 0.6);
    b.l[idx] += amp * env * (Math.sin(2 * Math.PI * freq * 0.997 * t) + 0.3 * Math.sin(2 * Math.PI * freq * 2 * t));
    b.r[idx] += amp * env * (Math.sin(2 * Math.PI * freq * 1.003 * t) + 0.3 * Math.sin(2 * Math.PI * freq * 2.004 * t));
  }
}
// 頻率滑動的正弦（大鼓、悶響、啵）
function sweep(b, t0, f0, f1, dur, amp, decay) {
  const s0 = Math.floor(t0 * SR), n = Math.floor(dur * SR);
  let ph = 0;
  for (let i = 0; i < n; i++) {
    const idx = s0 + i;
    if (idx < 0 || idx >= b.l.length) continue;
    const t = i / SR;
    const f = f1 + (f0 - f1) * Math.exp(-t / (dur * 0.25));
    ph += (2 * Math.PI * f) / SR;
    const v = Math.sin(ph) * Math.exp(-t / decay) * Math.min(1, t / 0.002) * amp;
    b.l[idx] += v;
    b.r[idx] += v;
  }
}
// 濾過的雜訊（沙鈴、咻聲）；hp/lp 為 0..1 的單極點濾波係數
function noise(b, t0, dur, amp, { hp = 0, lp = 1, shape = (x) => Math.exp(-x * 6), pan = 0 } = {}) {
  const s0 = Math.floor(t0 * SR), n = Math.floor(dur * SR);
  let lo = 0, hi = 0;
  for (let i = 0; i < n; i++) {
    const idx = s0 + i;
    if (idx < 0 || idx >= b.l.length) continue;
    const x = i / n;
    const k = typeof lp === "function" ? lp(x) : lp;
    lo += k * (rnd() - lo);
    hi += hp * (lo - hi);
    const v = (hp ? lo - hi : lo) * shape(x) * amp;
    b.l[idx] += v * (1 - pan * 0.5);
    b.r[idx] += v * (1 + pan * 0.5);
  }
}
function finish(b, peak = 0.8) {
  let m = 0;
  for (let i = 0; i < b.l.length; i++) m = Math.max(m, Math.abs(b.l[i]), Math.abs(b.r[i]));
  const g = m > 0 ? peak / m : 1;
  for (let i = 0; i < b.l.length; i++) { b.l[i] *= g; b.r[i] *= g; }
  return b;
}
function fade(b, inSec, outSec) {
  const n = b.l.length, a = Math.floor(inSec * SR), z = Math.floor(outSec * SR);
  for (let i = 0; i < a; i++) { b.l[i] *= i / a; b.r[i] *= i / a; }
  for (let i = 0; i < z; i++) { const k = i / z; b.l[n - 1 - i] *= k; b.r[n - 1 - i] *= k; }
  return b;
}
function save(name, b) {
  const n = b.l.length, data = Buffer.alloc(44 + n * 4);
  data.write("RIFF", 0); data.writeUInt32LE(36 + n * 4, 4); data.write("WAVEfmt ", 8);
  data.writeUInt32LE(16, 16); data.writeUInt16LE(1, 20); data.writeUInt16LE(2, 22);
  data.writeUInt32LE(SR, 24); data.writeUInt32LE(SR * 4, 28); data.writeUInt16LE(4, 32); data.writeUInt16LE(16, 34);
  data.write("data", 36); data.writeUInt32LE(n * 4, 40);
  for (let i = 0; i < n; i++) {
    data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, b.l[i])) * 32767), 44 + i * 4);
    data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, b.r[i])) * 32767), 46 + i * 4);
  }
  writeFileSync(join(OUT, name), data);
  console.log(name, (n / SR).toFixed(2) + "s");
}

// ---------- 配樂：C – G – Am – F，溫暖輕快 ----------
for (const { name, bars: MUSIC_BARS, endingAt: ENDING_AT, length: MUSIC_LENGTH, full } of MUSICS) {
  const beat = 60 / BPM, bar = beat * 4;
  const b = buf(MUSIC_LENGTH);
  const CH = [
    { bass: 36, notes: [60, 64, 67, 74] }, // C add9
    { bass: 43, notes: [59, 62, 67, 74] }, // G
    { bass: 45, notes: [57, 60, 64, 72] }, // Am
    { bass: 41, notes: [57, 60, 65, 72] }, // F
  ];
  const ARP = [0, 1, 2, 3, 2, 1, 2, 3];
  // 旋律（每 4 小節一句，單位：拍）
  const MELODY = [[0, 76, 1], [1, 79, 1], [3, 81, 1], [4, 79, 2], [6, 74, 2], [8, 76, 2], [10, 72, 1], [11, 74, 1], [12, 72, 3]];
  for (let i = 0; i < MUSIC_BARS; i++) {
    const t = i * bar, c = CH[i % 4];
    pad(b, t, midi(c.notes[0] - 12), bar + 0.3, 0.035);
    pad(b, t, midi(c.notes[2] - 12), bar + 0.3, 0.028);
    for (let k = 0; k < 8; k++) tone(b, t + k * beat * 0.5, midi(c.notes[ARP[k]]), 0.9, k % 2 ? 0.1 : 0.14, { pan: k % 2 ? 0.35 : -0.35, decay: 0.42 });
    if (full || i >= 1) {
      tone(b, t, midi(c.bass + 12), 0.9, 0.2, { harm: [1, 0.5, 0.1], decay: 0.4 });
      tone(b, t + beat * 2.5, midi(c.bass + 12), 0.6, 0.14, { harm: [1, 0.5, 0.1], decay: 0.3 });
      sweep(b, t, 130, 46, 0.22, 0.34, 0.09);
      sweep(b, t + beat * 2, 130, 46, 0.22, 0.28, 0.09);
      for (let k = 0; k < 4; k++) noise(b, t + beat * (k + 0.5), 0.05, 0.05, { hp: 0.5, lp: 0.9, pan: 0.4 });
    }
    if (full || i >= 4) for (const k of [1, 3]) noise(b, t + beat * k, 0.09, 0.1, { hp: 0.35, lp: 0.6, shape: (x) => Math.exp(-x * 9) });
  }
  for (let p = full ? 0 : 2; p * 4 < MUSIC_BARS; p++) {
    for (const [at, n, len] of MELODY) if (p * 4 * bar + at * beat < MUSIC_BARS * bar) tone(b, p * 4 * bar + at * beat, midi(n), len * beat + 0.5, 0.13, { harm: [1, 0.2, 0.05], decay: 0.7, pan: 0.1 });
  }
  // 收尾前半小節的屬和弦，再落在主和弦
  const g = MUSIC_BARS * bar;
  for (let k = 0; g + k * beat * 0.5 < ENDING_AT - 0.01; k++) tone(b, g + k * beat * 0.5, midi([62, 67, 71, 74][k % 4]), 0.8, 0.13 + (k % 4) * 0.01, { decay: 0.4 });
  tone(b, g, midi(55), ENDING_AT - g, 0.2, { harm: [1, 0.5, 0.1], decay: 0.5 });
  [48, 55, 60, 64, 67, 72, 74, 79].forEach((n, k) => tone(b, ENDING_AT + k * 0.045, midi(n), 6, k < 2 ? 0.2 : 0.15, { decay: 2.2, pan: (k % 3) * 0.3 - 0.3 }));
  pad(b, ENDING_AT, midi(48), 6, 0.05);
  pad(b, ENDING_AT, midi(55), 6, 0.04);
  sweep(b, ENDING_AT, 130, 46, 0.3, 0.3, 0.12);
  save(name, fade(finish(b, 0.85), 0.02, 2.5));
}

// ---------- 開場低頻鋪底＋心跳 ----------
{
  const b = buf(DRONE_LENGTH);
  pad(b, 0, 55, DRONE_LENGTH, 0.3);
  pad(b, 0, 82.4, DRONE_LENGTH, 0.14);
  noise(b, 0, DRONE_LENGTH, 0.08, { lp: 0.02, shape: () => 1 });
  for (let t = 1.2; t < DRONE_LENGTH - 1; t += 1.0) { sweep(b, t, 70, 40, 0.25, 0.5, 0.08); sweep(b, t + 0.22, 62, 38, 0.25, 0.32, 0.08); }
  save("drone.wav", fade(finish(b, 0.7), 0.4, 1.2));
}

// ---------- 音效 ----------
{ const b = buf(0.9); sweep(b, 0, 110, 34, 0.8, 1, 0.22); noise(b, 0, 0.12, 0.5, { lp: 0.2 }); save("thud.wav", fade(finish(b, 0.9), 0, 0.1)); }
{ const b = buf(0.45); noise(b, 0, 0.45, 1, { hp: 0.08, lp: (x) => 0.04 + 0.5 * Math.sin(Math.PI * x) ** 2, shape: (x) => Math.sin(Math.PI * x) ** 2 }); save("whoosh.wav", finish(b, 0.6)); }
{ const b = buf(0.9); tone(b, 0, 1318.5, 0.9, 1, { harm: [1, 0.3, 0.1], decay: 0.22 }); tone(b, 0.07, 1975.5, 0.8, 0.6, { harm: [1, 0.2], decay: 0.2 }); save("ding.wav", finish(b, 0.6)); }
{ const b = buf(0.2); sweep(b, 0, 520, 980, 0.12, 1, 0.05); save("pop.wav", finish(b, 0.55)); }
{ const b = buf(0.12); tone(b, 0, 2093, 0.1, 1, { harm: [1], decay: 0.03 }); save("tick.wav", finish(b, 0.4)); }
{ const b = buf(0.3); noise(b, 0, 0.3, 1, { hp: 0.3, lp: (x) => 0.7 - 0.5 * x, shape: (x) => (1 - x) ** 2 }); save("swipe.wav", finish(b, 0.5)); }
