(function () {
  'use strict';
  var root = document.documentElement;
  var screen = document.getElementById('screen');
  var showcaseEmbed = window.parent !== window && new URLSearchParams(window.location.search).get('showcase') === '1';
  if (showcaseEmbed) root.classList.add('showcase-embed');
  var canvas = document.getElementById('canvas');
  var SCALE = 1;                 // 縮放層倍率（由 fitScreen 更新）
  function SW() { return 390; }  // 邏輯寬（canvas 參考寬）
  function SH() { return screen.clientHeight / SCALE; } // 邏輯高
  var reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  function $(s, c) { return (c || document).querySelector(s); }
  function $$(s, c) { return Array.prototype.slice.call((c || document).querySelectorAll(s)); }
  function store(k, v) { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) { return null; } }
  function icon(id, size) { return '<svg class="ic24"' + (size ? ' style="width:' + size + 'px;height:' + size + 'px"' : '') + '><use href="#' + id + '"/></svg>'; }
  function easeOutQuart(x) { return 1 - Math.pow(1 - x, 4); }
  function relRect(el) { var a = el.getBoundingClientRect(), b = screen.getBoundingClientRect(); return { x: (a.left - b.left) / SCALE, y: (a.top - b.top) / SCALE, w: a.width / SCALE, h: a.height / SCALE }; }

  /* ---------- 外觀 ---------- */
  var themeBtns = $$('[data-theme-set]');
  function setTheme(t) {
    if (t === 'system') root.removeAttribute('data-theme'); else root.setAttribute('data-theme', t);
    themeBtns.forEach(function (b) { b.classList.toggle('on', b.dataset.themeSet === t); });
    store('uban-theme', t);
  }
  themeBtns.forEach(function (b) { b.addEventListener('click', function () { setTheme(b.dataset.themeSet); }); });
  if (store('uban-theme')) setTheme(store('uban-theme'));

  /* ---------- 液態暈開（splash 同款波紋公式） ---------- */
  function blobPoly(cx, cy, maxR, p, w, h, n) {
    var A = maxR * 0.08 * p, R = maxR * p * 1.2, pts = [];
    for (var i = 0; i < n; i++) {
      var t = i / n * Math.PI * 2;
      var r = R + Math.sin(3 * t) * A * .7 + Math.cos(5 * t - p * 6) * A * .5 + Math.sin(7 * t + p * 4) * A * .3;
      pts.push(((cx + Math.cos(t) * r) / w * 100).toFixed(2) + '% ' + ((cy + Math.sin(t) * r) / h * 100).toFixed(2) + '%');
    }
    return 'polygon(' + pts.join(',') + ')';
  }
  screen.addEventListener('pointerdown', function (e) {
    var el = e.target.closest('[data-blob]'); if (!el || reduce || el.disabled) return;
    var r = el.getBoundingClientRect(), x = e.clientX - r.left, y = e.clientY - r.top;
    var maxR = Math.hypot(Math.max(x, r.width - x), Math.max(y, r.height - y));
    var s = document.createElement('span'); s.className = 'blob'; el.appendChild(s);
    var t0 = performance.now(), dur = 620;
    (function f(now) {
      var k = Math.min(1, (now - t0) / dur), p = easeOutQuart(k);
      s.style.clipPath = blobPoly(x, y, maxR, p, r.width, r.height, 90);
      s.style.opacity = k < .55 ? 1 : 1 - (k - .55) / .45;
      if (k < 1) requestAnimationFrame(f); else s.remove();
    })(t0);
  });

  /* ---------- 提示 ---------- */
  var toastEl = $('#toast'), toastT;
  function toast(m) { toastEl.textContent = m; toastEl.classList.add('show'); clearTimeout(toastT); toastT = setTimeout(function () { toastEl.classList.remove('show'); }, 1900); }

  /* ---------- 彈簧 ---------- */
  function Spring(zeta, k, onStep) { this.x = 0; this.v = 0; this.t = 0; this.c = 2 * zeta * Math.sqrt(k); this.k = k; this.onStep = onStep; this.raf = 0; }
  Spring.prototype.to = function (t, instant) {
    this.t = t;
    if (instant || reduce) { this.x = t; this.v = 0; this.onStep(this.x, 0); return; }
    if (this.raf) return;
    var self = this, last = performance.now();
    function f(now) {
      var dt = Math.min(.032, (now - last) / 1000); last = now;
      for (var i = 0; i < 4; i++) { var a = -self.k * (self.x - self.t) - self.c * self.v; self.v += a * dt / 4; self.x += self.v * dt / 4; }
      self.onStep(self.x, self.v);
      if (Math.abs(self.v) < .5 && Math.abs(self.x - self.t) < .3) { self.x = self.t; self.v = 0; self.onStep(self.x, 0); self.raf = 0; return; }
      self.raf = requestAnimationFrame(f);
    }
    this.raf = requestAnimationFrame(f);
  };

  /* ---------- 畫面切換 ---------- */
  var views = ['splash', 'privacy', 'identify', 'login', 'register', 'pairing', 'onboard', 'monitor', 'elder', 'news', 'article', 'moments', 'addfriend', 'almanac', 'permguide', 'states', 'call', 'fcall'];
  var pushed = { news: 1, article: 1, moments: 1, addfriend: 1, almanac: 1, permguide: 1, states: 1, call: 1, fcall: 1 };
  var statusbar = $('#statusbar'), panelChips = $$('.panel [data-go]');
  var currentView = '', splashGreen = false;
  function show(id) {
    views.forEach(function (v) {
      var el = document.getElementById(v), on = v === id;
      el.hidden = !on;
      if (on && v !== currentView) { el.classList.remove('enter', 'push-enter'); void el.offsetWidth; el.classList.add(pushed[v] ? 'push-enter' : 'enter'); if (!el.classList.contains('call')) el.scrollTop = 0; }
    });
    currentView = id;
    updateStatusbar();
  }
  function updateStatusbar() {
    var light = currentView === 'call' || currentView === 'fcall' || currentView === 'news' || currentView === 'article' || (currentView === 'splash' && splashGreen);
    statusbar.classList.toggle('light', light);
  }
  function go(target) {
    closeAll(); stopTutorial(true);
    var parts = target.split(':'), v = parts[0], sub = parts[1];
    show(v);
    if (v === 'splash') playSplash();
    if (v === 'elder') selectTab(sub || currentTab, true);
    if (v === 'call' || v === 'fcall') setCall(v, sub || 'video');
    if (v === 'news') { renderNews(); }
    if (v !== 'call' && v !== 'fcall') stopTimer();
    requestAnimationFrame(layoutSegs);
    panelChips.forEach(function (c) { c.classList.toggle('on', c.dataset.go === target || (!sub && c.dataset.go === v)); });
  }

  window.addEventListener('message', function (event) {
    if (!showcaseEmbed || event.source !== window.parent) return;
    var data = event.data || {};
    if (data.app !== 'uban-showcase' || data.command !== 'show') return;
    if (typeof data.target !== 'string' || !/^[a-z]+(?::[a-z]+)?$/.test(data.target)) return;
    go(data.target);
    window.parent.postMessage({ app: 'uban-prototype', type: 'shown', target: data.target, role: 'elder' }, '*');
  });

  /* ---------- 開場（照搬 splash_screen.dart 時間軸） ---------- */
  var cv = $('#splashCanvas'), ctx = cv.getContext('2d'), splashRun = 0;
  function playSplash() {
    var run = ++splashRun, dpr = window.devicePixelRatio || 1;
    var w = cv.clientWidth, h = cv.clientHeight; cv.width = w * dpr; cv.height = h * dpr; ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    var maxR = Math.hypot(w, h), t0 = 0, font = '600 64px Poppins, "Noto Sans TC", sans-serif';
    function word(c) { ctx.fillStyle = c; ctx.font = font; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText('Uban', w / 2, h / 2); }
    function frame(now) {
      if (run !== splashRun) return;
      if (!t0) t0 = now;
      var el = now - t0, t = Math.min(1, el / 3200), p = easeOutQuart(Math.max(0, Math.min(1, (t - .25) / .75)));
      var fade = el > 3200 ? Math.max(0, 1 - (el - 3200) / 1000) : 1;
      ctx.globalAlpha = 1; ctx.fillStyle = '#F5F5F5'; ctx.fillRect(0, 0, w, h);
      ctx.globalAlpha = fade; ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, w, h); word('#59B294');
      if (p > 0) {
        ctx.save(); ctx.beginPath();
        var A = maxR * .08 * p, R = maxR * p * 1.2;
        for (var i = 0; i <= 180; i++) { var a = i / 180 * Math.PI * 2, r = R + Math.sin(3 * a) * A * .7 + Math.cos(5 * a - p * 6) * A * .5 + Math.sin(7 * a + p * 4) * A * .3; var X = w / 2 + Math.cos(a) * r, Y = h / 2 + Math.sin(a) * r; if (i) ctx.lineTo(X, Y); else ctx.moveTo(X, Y); }
        ctx.clip(); ctx.fillStyle = '#59B294'; ctx.fillRect(0, 0, w, h); word('#fff'); ctx.restore();
      }
      splashGreen = p > .5 && fade > .5; updateStatusbar();
      if (el < 4200) requestAnimationFrame(frame); else if (currentView === 'splash') go('privacy');
    }
    var start = function () { requestAnimationFrame(frame); };
    if (document.fonts && document.fonts.load) document.fonts.load(font).then(start, start); else start();
  }

  /* ---------- 懸浮玻璃導覽列 ---------- */
  var nav = $('#nav'), ind = $('#ind'), navBtns = $$('button', nav), IND_W = 58;
  var navSpring = new Spring(.8, 380, function (x, v) { var s = Math.min(30, Math.abs(v) * .045); ind.style.width = (IND_W + s) + 'px'; ind.style.transform = 'translateX(' + (x - s / 2) + 'px)'; });
  var tabs = { home: 'tabHome', phone: 'tabPhone', pet: 'tabPet', chat: 'tabChat', profile: 'tabProfile' }, currentTab = 'home';
  function targetX(btn) { return btn.offsetLeft + btn.offsetWidth / 2 - IND_W / 2; }
  function selectTab(name, instant) {
    var btn = $('[data-tab="' + name + '"]', nav);
    navBtns.forEach(function (b) { b.classList.toggle('on', b === btn); });
    if (!instant) { btn.classList.remove('pop'); void btn.offsetWidth; btn.classList.add('pop'); try { navigator.vibrate && navigator.vibrate(8); } catch (e) { } }
    Object.keys(tabs).forEach(function (k) { var el = document.getElementById(tabs[k]), on = k === name; el.hidden = !on; if (on && k !== currentTab) { el.classList.remove('enter'); void el.offsetWidth; el.classList.add('enter'); el.scrollTop = 0; } });
    $('#chatbar').hidden = name !== 'chat';
    $('.helppill').hidden = name === 'chat';
    $('.mic').hidden = name === 'chat';   // 聊天頁已有「按住說話」＋鍵盤鈕，隱藏浮動語音助理避免擋住鍵盤
    currentTab = name;
    if (name === 'pet') renderFoods();
    if (name === 'home') requestAnimationFrame(playHomeIntro);
    resetFloatHide();
    requestAnimationFrame(function () { navSpring.to(targetX(btn), instant); layoutSegs(); });
    panelChips.forEach(function (c) { c.classList.toggle('on', c.dataset.go === 'elder:' + name); });
  }
  navBtns.forEach(function (b) { b.addEventListener('click', function () { if (b.dataset.tab !== currentTab) selectTab(b.dataset.tab); }); });
  window.addEventListener('resize', function () { fitScreen(); var b = $('.on', nav); if (b) navSpring.to(targetX(b), true); layoutSegs(); });

  /* ---------- 分段切換 ---------- */
  function layoutSegs() { $$('[data-seg]').forEach(function (s) { var on = $('button.on', s), th = $('.thumb', s); if (on && on.offsetWidth) { th.style.left = on.offsetLeft + 'px'; th.style.width = on.offsetWidth + 'px'; } }); }
  $$('[data-seg]').forEach(function (s) {
    $$('button', s).forEach(function (b) {
      b.addEventListener('click', function () {
        $$('button', s).forEach(function (x) { x.classList.toggle('on', x === b); }); layoutSegs();
        if (b.dataset.pane) $$('[data-pane-body]', s.parentElement).forEach(function (p) { p.hidden = p.dataset.paneBody !== b.dataset.pane; if (!p.hidden) { p.classList.remove('enter'); void p.offsetWidth; p.classList.add('enter'); } });
      });
    });
  });
  $$('.langseg').forEach(function (s) { $$('button', s).forEach(function (b) { b.addEventListener('click', function () { $$('button', s).forEach(function (x) { x.classList.toggle('on', x === b); }); }); }); });
  var blessings = { sunrise: '旭日東昇　平安喜樂', lotus: '蓮開並蒂　清淨自在', koi: '鯉躍龍門　年年有餘' };
  $$('.thumbs button').forEach(function (b) { b.addEventListener('click', function () {
    $$('button', b.parentElement).forEach(function (x) { x.classList.toggle('on', x === b); });
    var t = b.dataset.tpl || 'sunrise', g = $('#gcard');
    g.dataset.tpl = t; g.style.background = '';
    var bl = $('[data-bless]', g); if (bl) bl.textContent = blessings[t];
  }); });

  /* ---------- 今日任務：進度環＋下一件 ---------- */
  var NOW = 12 * 60 + 5;
  var tasks = [
    { id: 1, time: '07:30', title: '早上降血壓藥 1 顆', cat: 'med', done: true },
    { id: 2, time: '08:00', title: '喝一杯溫開水', cat: 'water', done: true },
    { id: 3, time: '09:30', title: '散步 20 分鐘', cat: 'walk', done: true },
    { id: 4, time: '12:30', title: '降血壓藥 1 顆', cat: 'med', done: false },
    { id: 5, time: '12:40', title: '喝一杯溫開水', cat: 'water', done: false },
    { id: 6, time: '15:00', title: '量血壓', cat: 'other', done: false },
    { id: 7, time: '18:30', title: '晚餐後降血糖藥', cat: 'med', done: false },
    { id: 8, time: '21:30', title: '睡前鈣片', cat: 'med', done: false }
  ];
  var catStyle = { med: ['i-pill', 'warm'], water: ['i-drop', 'info'], walk: ['i-walk', ''], other: ['i-clock', ''] };
  var openGroups = { now: true, later: false, done: false };
  function mins(t) { var p = t.split(':'); return +p[0] * 60 + +p[1]; }
  function nextTask() { return tasks.filter(function (t) { return !t.done; })[0]; }
  function catChip(cat) { if (cat === 'med') return ['var(--warm-container)', 'var(--warm)']; if (cat === 'water') return ['var(--info-container)', 'var(--info)']; return ['var(--brand-soft)', 'var(--brand-strong)']; }
  function taskRow(t) {
    var cs = catStyle[t.cat], c = catChip(t.cat);
    return '<div class="trow' + (t.done ? ' done' : '') + '"><span class="ci" style="background:' + c[0] + ';color:' + c[1] + '">' + icon(cs[0]) + '</span><div class="grow"><div class="tt">' + t.time + '</div><div class="ti ellipsis">' + t.title + '</div></div><button class="tick press" data-done="' + t.id + '" aria-label="打卡 ' + t.title + '"><svg viewBox="0 0 24 24"><use href="#i-check"/></svg></button></div>';
  }
  function renderTaskList(card, done, total) {
    card.innerHTML = '<div class="sec-head" style="margin-bottom:4px"><span class="h2">今天要做的事</span><span class="tag">' + done + '／' + total + ' 完成</span></div>' + tasks.map(taskRow).join('');
  }
  function renderTaskCards() {
    var done = tasks.filter(function (t) { return t.done; }).length, total = tasks.length, n = nextTask();
    var C = 2 * Math.PI * 38, off = C * (1 - done / total);
    $$('[data-taskcard]').forEach(function (card) {
      if (card.dataset.taskcard === 'list') { renderTaskList(card, done, total); return; }
      var prev = card.querySelector('.fg'), prevOff = prev ? prev.style.strokeDashoffset : C;
      var right = n
        ? '<div class="grow"><div class="label">下一件</div><div class="next-t">' + n.time + '</div><div class="ellipsis" style="font-size:19px;font-weight:700">' + n.title + '</div></div><button class="checkin press" data-blob data-done="' + n.id + '">打卡</button>'
        : '<div class="grow"><div class="alldone">' + icon('i-check', 22) + '今天的事都做完了</div><div style="font-size:15px;color:var(--text-2);margin-top:4px">小豬也替您開心</div></div>';
      card.innerHTML = '<div class="taskcard" role="button" tabindex="0" data-overlay="tasks" aria-label="今天要做的事，已完成 ' + done + ' 件，共 ' + total + ' 件">' +
        '<div class="ring"><svg viewBox="0 0 88 88"><circle class="bgc" cx="44" cy="44" r="38"/><circle class="fg" cx="44" cy="44" r="38" stroke-dasharray="' + C + '" style="stroke-dashoffset:' + prevOff + '"/></svg><div class="num"><div class="frac"><b>' + done + '</b><span>/' + total + '</span></div></div></div>' +
        right + '</div>';
      var fg = card.querySelector('.fg'); requestAnimationFrame(function () { requestAnimationFrame(function () { fg.style.strokeDashoffset = off; }); });
    });
    $$('[data-taskcount]').forEach(function (e) { e.textContent = done + '／' + total; });
    renderTaskSheet();
  }
  function renderTaskSheet() {
    var g = { now: [], later: [], done: [] };
    tasks.forEach(function (t) { if (t.done) g.done.push(t); else if (mins(t.time) <= NOW + 60) g.now.push(t); else g.later.push(t); });
    var names = { now: '現在要做', later: '稍後', done: '已完成' };
    $('#taskgroups').innerHTML = ['now', 'later', 'done'].filter(function (k) { return g[k].length; }).map(function (k) {
      var rows = g[k].map(function (t) {
        var cs = catStyle[t.cat];
        return '<div class="trow' + (t.done ? ' done' : '') + '"><span class="ci ' + (cs[1] ? 'ib ' + cs[1] : '') + '" style="' + (cs[1] ? '' : 'background:var(--brand-soft);color:var(--brand-strong)') + '">' + icon(cs[0]) + '</span><div class="grow"><div class="tt">' + t.time + '</div><div class="ti ellipsis">' + t.title + '</div></div><button class="tick press" data-done="' + t.id + '" aria-label="打卡 ' + t.title + '"><svg viewBox="0 0 24 24"><use href="#i-check"/></svg></button></div>';
      }).join('');
      return '<button class="grp-h" data-grp="' + k + '" aria-expanded="' + openGroups[k] + '"><span>' + names[k] + '（' + g[k].length + '）</span><svg class="ic24 chev"><use href="#i-chev"/></svg></button><div class="grp-b' + (openGroups[k] ? ' open' : '') + '"><div>' + rows + '</div></div>';
    }).join('');
    $$('.trow .ci.ib').forEach(function (e) { e.classList.remove('ib'); var c = e.classList.contains('warm') ? ['var(--warm-container)', 'var(--warm)'] : ['var(--info-container)', 'var(--info)']; e.style.background = c[0]; e.style.color = c[1]; });
  }
  function toggleTask(id) {
    var t = tasks.filter(function (x) { return x.id === +id; })[0]; if (!t) return;
    t.done = !t.done;
    var all = tasks.every(function (x) { return x.done; });
    if (t.done && !all) toast('打卡成功「' + t.title + '」');
    renderTaskCards(); renderFoods(); renderWeek(all && streak.celebrated);
    if (all && !streak.celebrated) { streak.celebrated = true; setTimeout(celebrate, 500); }
  }
  renderTaskCards();

  /* ---------- 小豬舞台 ---------- */
  var todPref = 'auto', wxPref = 'auto';
  function tod() { if (todPref !== 'auto') return todPref; var h = new Date().getHours(); return h < 5 ? 'night' : h < 8 ? 'dawn' : h < 17 ? 'day' : h < 19 ? 'dusk' : 'night'; }
  // 天氣沿用 WeatherService 的三段分級：多雲到晴／局部陣雨／陰雨綿綿（示意資料：降雨機率 35% → 局部陣雨）
  function weather() { return wxPref !== 'auto' ? wxPref : 'shower'; }
  var todName = { dawn: '清晨', day: '白天', dusk: '黃昏', night: '夜晚' }, wxName = { sunny: '多雲到晴', shower: '局部陣雨', rain: '陰雨綿綿' };
  function applyScene() {
    var t = tod(), w = weather();
    $$('[data-buddy]').forEach(function (b) { b.dataset.time = t; b.dataset.weather = w; });
    $$('[data-todlabel]').forEach(function (l) { l.textContent = todName[t] + '・' + wxName[w]; });
    updateStatusbar(); startRain();
  }
  $$('[data-tod]').forEach(function (b) { b.addEventListener('click', function () { todPref = b.dataset.tod; $$('[data-tod]').forEach(function (x) { x.classList.toggle('on', x === b); }); applyScene(); }); });
  $$('[data-wx]').forEach(function (b) { b.addEventListener('click', function () { wxPref = b.dataset.wx; $$('[data-wx]').forEach(function (x) { x.classList.toggle('on', x === b); }); applyScene(); }); });

  // 雨：canvas 粒子，陣雨稀疏、陰雨密集；夜晚雨絲調暗
  var rainCv = $('#rain'), rainCx = rainCv.getContext('2d'), rainRaf = 0, drops = [];
  function startRain() {
    cancelAnimationFrame(rainRaf);
    var w = weather(), n = w === 'rain' ? 110 : w === 'shower' ? 40 : 0;
    var W = rainCv.width = rainCv.clientWidth, H = rainCv.height = rainCv.clientHeight;
    rainCx.clearRect(0, 0, W, H);
    if (!n || reduce) return;
    drops = []; for (var i = 0; i < n; i++) drops.push({ x: Math.random() * W, y: Math.random() * H, l: 10 + Math.random() * 12, v: 9 + Math.random() * 6 });
    var alpha = tod() === 'night' ? .35 : .6;
    (function f() {
      if (currentView !== 'elder' || currentTab !== 'pet') { rainRaf = requestAnimationFrame(f); return; }
      rainCx.clearRect(0, 0, W, H); rainCx.strokeStyle = 'rgba(225,235,245,' + alpha + ')'; rainCx.lineWidth = 1.4; rainCx.beginPath();
      drops.forEach(function (d) { d.y += d.v; d.x -= d.v * .18; if (d.y > H) { d.y = -d.l; d.x = Math.random() * (W + 40); } rainCx.moveTo(d.x, d.y); rainCx.lineTo(d.x + d.l * .18, d.y - d.l); });
      rainCx.stroke(); rainRaf = requestAnimationFrame(f);
    })();
  }

  var pet = { w: 39.82, v: 62, stage: 2, consumedCarrot: 0, breed: store('uban-breed') || 'pink', view: 'front' };
  var FRONT_H = [0, 120, 138, 150, 160, 170], SIDE_H = [0, 82, 96, 108, 118, 128];
  // 耳標錨點：耳朵上的穿孔位置（相對圖片寬高）。耳標永遠戴在豬的「左耳」：
  // 正面圖是畫面右側那隻；側面圖（鼻子朝左）是看得到的那隻。朝右走時左耳在遠側，由 CSS 把耳標藏到頭後面。
  var EAR = {
    pink_front: [[.82, .17], [.84, .20], [.85, .19], [.87, .19], [.85, .18]],
    pink_side: [[.27, .22], [.23, .24], [.22, .24], [.20, .22], [.21, .20]],
    black_front: [[.82, .40], [.83, .42], [.80, .40], [.80, .41], [.77, .42]],
    black_side: [[.19, .38], [.17, .34], [.17, .36], [.17, .46], [.15, .47]]
  };
  var pigEl = $('#petPig'), body = $('#pigBody'), pigImg = $('[data-pigimg]'), tag = $('#earTag'), walker = $('#walker'), petFx = $('#petFx'), stage = $('#petStage');
  function pigSrc(breed, view, s) { return 'img/pet/' + breed + '_' + view + '_' + s + '.png'; }
  function drawPig() {
    var key = pet.breed + '_' + pet.view, a = EAR[key][pet.stage - 1], h = (pet.view === 'front' ? FRONT_H : SIDE_H)[pet.stage];
    pigImg.src = pigSrc(pet.breed, pet.view, pet.stage); pigImg.style.height = h + 'px';
    tag.src = 'img/pet/ear_tag_' + pet.stage + '.png';
    tag.style.left = (a[0] * 100) + '%'; tag.style.top = (a[1] * 100) + '%';
    tag.style.width = Math.round(h * (pet.view === 'front' ? .15 : .2)) + 'px';
    $$('[data-pigimg-front]').forEach(function (i) { i.src = pigSrc(pet.breed, 'front', pet.stage); });
    $$('[data-stagelabel]').forEach(function (e) { e.textContent = '第 ' + pet.stage + ' 階'; });
  }
  function setBreed(b) { pet.breed = b; store('uban-breed', b); $$('[data-breed]').forEach(function (x) { x.classList.toggle('on', x.dataset.breed === b); }); drawPig(); renderBoard(); }
  $$('[data-breed]').forEach(function (x) { x.addEventListener('click', function () { setBreed(x.dataset.breed); hop(pigEl); }); });

  /* 耳標鐘擺：阻尼小、週期約 0.9 秒，比豬的步伐慢，所以會甩起來、晚一拍才停 */
  var tagA = 0, tagV = 0, tagLean = 0, tagRaf = 0, TAG_K = 49, TAG_C = 2 * .12 * Math.sqrt(49);
  function kick(v) { tagV += v; if (!tagRaf) tagLoop(); }
  function tagLoop() {
    var last = performance.now();
    tagRaf = requestAnimationFrame(function f(now) {
      var dt = Math.min(.032, (now - last) / 1000); last = now;
      for (var i = 0; i < 4; i++) { var acc = -TAG_K * (tagA - tagLean) - TAG_C * tagV; tagV += acc * dt / 4; tagA += tagV * dt / 4; }
      tag.style.transform = 'translate(-50%,-12%) rotate(' + tagA.toFixed(2) + 'deg)';
      if (Math.abs(tagV) < .05 && Math.abs(tagA - tagLean) < .05) { tagRaf = 0; return; }
      tagRaf = requestAnimationFrame(f);
    });
  }

  function hop(p) { p.classList.remove('hop', 'ready', 'chew'); void p.offsetWidth; p.classList.add('hop'); kick(-140); setTimeout(function () { kick(90); }, 260); }
  function spawnHeart(fx, x, y, delay) {
    var h = document.createElement('div'); h.className = 'heart'; h.innerHTML = '<svg viewBox="0 0 24 24" width="26" height="26"><path d="M12 20s-7-4.2-7-9.2A3.9 3.9 0 0 1 12 8.4a3.9 3.9 0 0 1 7 2.4c0 5-7 9.2-7 9.2z" fill="currentColor"/></svg>';
    h.style.left = x + 'px'; h.style.top = y + 'px'; h.style.animationDelay = (delay || 0) + 'ms'; h.style.opacity = 0; fx.appendChild(h); setTimeout(function () { h.remove(); }, 1500 + (delay || 0));
  }
  function pigCenter() { var s = relRect(stage), p = relRect(pigImg); return { x: p.x - s.x + p.w / 2, top: p.y - s.y, h: p.h }; }
  pigEl.addEventListener('click', function () { if (busy()) return; hop(pigEl); var c = pigCenter(); spawnHeart(petFx, c.x - 13, c.top - 6); });

  // 寶可夢 GO 式走動：換側面圖 → 走一段 → 轉身走回 → 換回正面
  var walking = false, feeding = false, walkT = 0, stepT = 0;
  function busy() { return walking || feeding; }
  function walk() {
    if (busy() || reduce || currentView !== 'elder' || currentTab !== 'pet') return;
    walking = true;
    var dir = Math.random() < .5 ? -1 : 1, dist = dir > 0 ? 40 + Math.random() * 15 : 70 + Math.random() * 30; // 右下角有胡蘿蔔鈕，往右走短一點
    pet.view = 'side'; drawPig();
    function leg(d, done, delay) {
      // 側面圖鼻子朝左；往右走時整個身體（含耳標）水平翻轉
      setTimeout(function () {
        body.classList.toggle('flip', d > 0); body.classList.add('walking');
        tagLean = d * 7; // 走路時耳標往後甩
        var step = 0; clearInterval(stepT); stepT = setInterval(function () { kick((step++ % 2 ? 1 : -1) * 55 - d * 25); }, 320);
        var from = d === dir ? 0 : dir * dist, to = d === dir ? dir * dist : 0;
        walker.animate([{ transform: 'translateX(' + from + 'px)' }, { transform: 'translateX(' + to + 'px)' }], { duration: 2200, easing: 'ease-in-out', fill: 'forwards' }).onfinish = function () { clearInterval(stepT); body.classList.remove('walking'); tagLean = 0; kick(d * 60); done(); };
      }, delay);
    }
    leg(dir, function () { leg(-dir, function () { body.classList.remove('flip'); walker.getAnimations().forEach(function (a) { a.cancel(); }); pet.view = 'front'; drawPig(); walking = false; hop(pigEl); }, 500); }, 0);
  }
  function scheduleWalk() { clearTimeout(walkT); walkT = setTimeout(function () { walk(); scheduleWalk(); }, 9000); }

  /* ---------- 餵食：只有胡蘿蔔，按鈕在舞台右下角 ---------- */
  // 胡蘿蔔照現有後端規則：打卡 1 次賺 1 根，一天最多 5 根
  function checkins() { return tasks.filter(function (t) { return t.done; }).length; }
  function carrotsEarned() { return Math.min(5, checkins()); }
  function carrotsLeft() { return Math.max(0, carrotsEarned() - pet.consumedCarrot); }
  var carrotBtn = $('#carrotBtn');
  function renderFoods() {
    var n = carrotsLeft();
    $('.cnt', carrotBtn).textContent = n;
    carrotBtn.classList.toggle('empty', n <= 0);
    carrotBtn.setAttribute('aria-label', n > 0 ? '餵胡蘿蔔，還有 ' + n + ' 根' : '胡蘿蔔吃完了，打卡就能賺');
    updatePetStats();
  }
  function selectFood() { carrotBtn.classList.remove('nudge'); void carrotBtn.offsetWidth; carrotBtn.classList.add('nudge'); }
  function updatePetStats() {
    var lo = (pet.stage - 1) * 20;
    $('[data-stagebar]').style.width = Math.max(2, Math.min(100, (pet.w - lo) / 20 * 100)) + '%';
    $('[data-stagehint]').textContent = '再胖 ' + Math.max(0, lo + 20 - pet.w).toFixed(2) + ' 公斤就到第 ' + (pet.stage + 1) + ' 階';
    $('[data-weight]').textContent = pet.w.toFixed(2);
  }

  // 點一下餵，或從按鈕拖到小豬身上
  var drag = null, dragMoved = false;
  function overPig(cx, cy) { var p = relRect(pigImg); return cx > p.x - 30 && cx < p.x + p.w + 30 && cy > p.y - 40 && cy < p.y + p.h + 10; }
  carrotBtn.addEventListener('pointerdown', function (e) { if (busy() || carrotsLeft() <= 0) return; drag = { sx: e.clientX, sy: e.clientY, ghost: null }; dragMoved = false; });
  window.addEventListener('pointermove', function (e) {
    if (!drag) return;
    if (!drag.ghost && Math.hypot(e.clientX - drag.sx, e.clientY - drag.sy) > 12) {
      dragMoved = true;
      var g = document.createElement('img'); g.src = 'img/carrot.svg'; g.className = 'flyfood'; g.style.width = g.style.height = '72px'; canvas.appendChild(g); drag.ghost = g;
    }
    if (drag.ghost) {
      var b = screen.getBoundingClientRect(), x = (e.clientX - b.left) / SCALE, y = (e.clientY - b.top) / SCALE;
      drag.ghost.style.left = (x - 36) + 'px'; drag.ghost.style.top = (y - 36) + 'px';
      stage.classList.toggle('dropok', overPig(x, y));
    }
  });
  window.addEventListener('pointerup', function () {
    if (!drag) return;
    var d = drag; drag = null; stage.classList.remove('dropok');
    if (!d.ghost) return;
    var gr = relRect(d.ghost); d.ghost.remove();
    if (overPig(gr.x + gr.w / 2, gr.y + gr.h / 2)) feed(gr); else toast('拖到小豬身上就能餵');
    setTimeout(function () { dragMoved = false; }, 50);
  });
  carrotBtn.addEventListener('click', function () { if (!dragMoved) feed(relRect(carrotBtn)); });

  function feed(from) {
    if (busy()) return;
    if (carrotsLeft() <= 0) { toast('打卡就能賺胡蘿蔔'); return; }
    feeding = true; pet.consumedCarrot++; renderFoods();
    var pr = relRect(pigImg), to = { x: pr.x + pr.w / 2 - 32, y: pr.y + pr.h * .42 - 32 };
    var start = { x: from.x + from.w / 2 - 32, y: from.y + from.h / 2 - 32 }, ctrl = { x: (start.x + to.x) / 2, y: Math.min(start.y, to.y) - 90 };
    var img = document.createElement('img'); img.src = 'img/carrot.svg'; img.className = 'flyfood'; canvas.appendChild(img);
    pigEl.classList.remove('hop', 'chew'); pigEl.classList.add('ready');
    var t0 = performance.now(), dur = reduce ? 1 : 520;
    (function fly(now) {
      var k = Math.min(1, (now - t0) / dur), e = k < .5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
      img.style.left = ((1 - e) * (1 - e) * start.x + 2 * (1 - e) * e * ctrl.x + e * e * to.x) + 'px';
      img.style.top = ((1 - e) * (1 - e) * start.y + 2 * (1 - e) * e * ctrl.y + e * e * to.y) + 'px';
      img.style.transform = 'scale(' + (1 - e * .55) + ') rotate(' + (-e * 220) + 'deg)';
      if (k < 1) requestAnimationFrame(fly); else { img.remove(); chew(); }
    })(t0);
  }
  function chew() {
    pigEl.classList.remove('ready'); void pigEl.offsetWidth; pigEl.classList.add('chew');
    var c = pigCenter(), n = 0;
    var crumbs = setInterval(function () {
      kick(n % 2 ? 40 : -40);
      for (var i = 0; i < 3; i++) {
        var el = document.createElement('span'); el.className = 'crumb'; el.style.background = '#F28C28';
        el.style.left = (c.x + (Math.random() - .5) * 40) + 'px'; el.style.top = (c.top + c.h * .45) + 'px'; petFx.appendChild(el);
        el.animate([{ transform: 'translate(0,0)', opacity: 1 }, { transform: 'translate(' + ((Math.random() - .5) * 90) + 'px,' + (30 + Math.random() * 50) + 'px)', opacity: 0 }], { duration: 650, easing: 'cubic-bezier(.2,.6,.4,1)' }).onfinish = function () { this.effect.target.remove(); };
      }
      if (++n >= 8) clearInterval(crumbs);
    }, 150);
    setTimeout(function () {
      // 數值照樣累積（體重決定階段與排行榜），但畫面上不講加了多少
      pet.v = Math.min(100, pet.v + 10); pet.w = +(pet.w + .04).toFixed(2);
      for (var i = 0; i < 3; i++) spawnHeart(petFx, c.x - 13 + (i - 1) * 34, c.top - 4, i * 140);
      updatePetStats(); renderBoard(); hop(pigEl);
      var evolve = pet.stage < 5 && pet.w >= pet.stage * 20;
      setTimeout(function () { feeding = false; if (evolve) showEvo(pet.stage + 1); else toast('小豬吃得好開心！'); }, 600);
    }, 1250);
  }
  var evoTo = 0;
  function showEvo(to) {
    evoTo = to || Math.min(5, pet.stage + 1);
    var evo = $('#evo'), box = $('.box', evo), copy = box.cloneNode(true);
    $('.old', copy).src = pigSrc(pet.breed, 'front', evoTo - 1); $('.new', copy).src = pigSrc(pet.breed, 'front', evoTo);
    $('h2', copy).textContent = '長大到第 ' + evoTo + ' 階了！';
    box.parentNode.replaceChild(copy, box); evo.classList.add('show');
  }
  // 只有體重真的到門檻才升階；面板上的「進化動畫」只是預覽
  function closeEvo() {
    $('#evo').classList.remove('show');
    if (pet.w >= (evoTo - 1) * 20 && evoTo > pet.stage) { pet.stage = evoTo; drawPig(); updatePetStats(); renderBoard(); hop(pigEl); }
  }

  /* ---------- 好友排行榜（第 3 季） ---------- */
  var board = [
    { name: '美玉', breed: 'black', stage: 3, w: 52.4 },
    { name: '金花', breed: 'pink', stage: 3, w: 41.1 },
    { name: '我（秀枝）', me: true },
    { name: '阿德', breed: 'black', stage: 2, w: 33.5 },
    { name: '春嬌', breed: 'pink', stage: 2, w: 21.0 }
  ];
  function renderBoard() {
    var rows = board.map(function (r) { return r.me ? { name: r.name, me: true, breed: pet.breed, stage: pet.stage, w: pet.w } : r; }).sort(function (a, b) { return b.w - a.w; });
    $('#board').innerHTML = rows.map(function (r, i) {
      return '<div class="brow' + (r.me ? ' me' : '') + '"><span class="rank r' + (i + 1) + '">' + (i + 1) + '</span><span class="bpig"><img src="' + pigSrc(r.breed, 'front', r.stage) + '" alt=""></span><span class="grow ellipsis bname">' + r.name + '</span><span class="bw">' + r.w.toFixed(1) + '<small> 公斤</small></span></div>';
    }).join('');
  }

  /* ---------- 連勝（全部打卡完成） ---------- */
  var streak = { days: 6, celebrated: false }, WEEK = ['一', '二', '三', '四', '五', '六', '日'], TODAY = 2; // 10/1 是星期三
  function renderWeek(todayDone) {
    $$('[data-week]').forEach(function (w) {
      w.innerHTML = WEEK.map(function (d, i) { var on = i < TODAY || (i === TODAY && todayDone); return '<div><span>' + d + '</span><i class="' + (on ? 'on' : '') + (i === TODAY && !todayDone ? ' today' : '') + '"></i></div>'; }).join('');
    });
    var n = streak.days + (todayDone ? 1 : 0);
    $$('[data-streaknum]').forEach(function (e) { e.textContent = n; });
    $$('[data-streakchip]').forEach(function (e) { e.innerHTML = '<svg viewBox="0 0 24 24"><use href="#i-flame"/></svg>連續 ' + n + ' 天'; });
  }
  function celebrate() {
    var fx = $('#streakfx'), n = streak.days;
    $('[data-sfrom]').textContent = n; $('[data-sto]').textContent = n + 1; $('[data-sto2]').textContent = n + 1;
    $('[data-earned]').textContent = Math.max(1, carrotsEarned());
    closeAll(); renderWeek(false);
    fx.classList.remove('rolled'); fx.classList.add('show');
    setTimeout(function () { fx.classList.add('rolled'); renderWeek(true); var d = $$('.week i', fx)[TODAY]; if (d) d.classList.add('pop'); confetti(); }, 450);
  }
  function confetti() {
    var cv = $('#confetti'), cx = cv.getContext('2d'), W = cv.width = cv.clientWidth, H = cv.height = cv.clientHeight;
    if (reduce) return;
    var cols = ['#59B294', '#FFB547', '#F26B3A', '#F09AA6', '#8DBBEA', '#FFE08A'], ps = [];
    for (var i = 0; i < 120; i++) ps.push({ x: W / 2 + (Math.random() - .5) * 60, y: H * .32, vx: (Math.random() - .5) * 11, vy: -Math.random() * 12 - 4, r: Math.random() * 6 + 4, c: cols[i % cols.length], a: Math.random() * 6, va: (Math.random() - .5) * .3 });
    var t0 = performance.now();
    (function f(now) {
      cx.clearRect(0, 0, W, H);
      ps.forEach(function (p) { p.vy += .32; p.vx *= .99; p.x += p.vx; p.y += p.vy; p.a += p.va; cx.save(); cx.translate(p.x, p.y); cx.rotate(p.a); cx.fillStyle = p.c; cx.fillRect(-p.r / 2, -p.r / 4, p.r, p.r / 2); cx.restore(); });
      if (now - t0 < 3200 && $('#streakfx').classList.contains('show')) requestAnimationFrame(f); else cx.clearRect(0, 0, W, H);
    })(t0);
  }
  // 慶祝畫面關掉後，連勝數字維持今天已完成的狀態
  function closeStreak() { $('#streakfx').classList.remove('show'); renderWeek(tasks.every(function (x) { return x.done; }) || streak.celebrated); }

  setBreed(pet.breed); applyScene(); scheduleWalk(); renderFoods(); renderWeek(false);
  // 待機時耳標偶爾自己晃一下
  setInterval(function () { if (!busy() && currentTab === 'pet') kick((Math.random() - .5) * 60); }, 3800);

  /* ---------- 新聞 ---------- */
  var news = [
    { cat: '健康', title: '寒露將至早晚溫差大，醫師提醒長輩外出加件薄外套', src: '中央社', bg: 'linear-gradient(135deg,#7FC8AE,#2B6C59)', subs: ['中央氣象署表示，下週三進入寒露', '各地早晚氣溫明顯下降', '醫師提醒出門多帶一件薄外套'] },
    { cat: '生活', title: '敬老卡點數新制上路 搭公車更划算', src: '中央社', bg: 'linear-gradient(135deg,#F6C98B,#C27A2C)', subs: ['敬老卡點數新制本月上路', '搭公車每趟扣點變少', '還可以用來搭計程車'] },
    { cat: '生活', title: '社區據點秋季健走 本週六早上開跑', src: '中央社', bg: 'linear-gradient(135deg,#A8D5A2,#4F8B48)', subs: ['社區關懷據點週六舉辦健走', '早上七點在公園集合', '完成就送一份健康早餐'] },
    { cat: '國際', title: '日本秋季賞楓提前 北海道已轉紅', src: '中央社', bg: 'linear-gradient(135deg,#F2A07B,#B4472E)', subs: ['日本今年楓葉轉紅較早', '北海道山區已經轉紅', '預計十月中最漂亮'] },
    { cat: '財經', title: '台股收紅 電子股帶頭上漲', src: '中央社', bg: 'linear-gradient(135deg,#9DB8E0,#3B5F99)', subs: ['台股今天收盤上漲', '電子股是主要推手', '成交量比昨天增加'] }
  ];
  var cur = 0, playing = false, playT0 = 0, playRaf = 0, catSel = '全部';
  function renderNews() {
    var n = news[cur];
    $('#nowTitle').textContent = n.title;
    $('#nowMeta').textContent = '第 ' + (cur + 1) + '／12 則・' + n.cat + '・2026-10-01';
    $('#pigSay').textContent = n.title.slice(0, 14) + '…';
    $('#subs').innerHTML = n.subs.map(function (s, i) { return '<p' + (i === 0 ? ' class="cur"' : '') + '>' + s + '</p>'; }).join('');
    $('#nlist').innerHTML = news.map(function (x, i) {
      if (catSel !== '全部' && x.cat !== catSel) return '';
      return '<button class="ncard press" data-article="' + i + '"' + (i === cur ? ' style="border:2px solid var(--brand)"' : '') + '><div class="img" style="background:' + x.bg + '"><span class="tag">' + x.cat + '</span>' + (i === cur ? '<span class="playing">' + icon('i-vol', 16) + '播放中</span>' : '') + '</div><div class="txt"><h4>' + x.title + '</h4><div class="src">' + x.src + '・2026-10-01</div></div></button>';
    }).join('') || '<div class="empty"><b style="font-size:20px">目前沒有這一類的新聞</b></div>';
    setPlay(playing);
  }
  function setPlay(p) {
    playing = p;
    $('#playBtn').innerHTML = icon(p ? 'i-pause' : 'i-play', 34);
    $('#playBtn').setAttribute('aria-label', p ? '暫停' : '播放');
    $('#eq').classList.toggle('on', p);
    cancelAnimationFrame(playRaf);
    if (p) { playT0 = performance.now(); karaoke(); }
  }
  function karaoke() {
    var lines = $$('#subs p'), per = 3200;
    playRaf = requestAnimationFrame(function step(now) {
      if (!playing || currentView !== 'news') return;
      var el = now - playT0, idx = Math.floor(el / per);
      if (idx >= lines.length) { setPlay(false); return; }
      lines.forEach(function (l, i) { l.classList.toggle('cur', i === idx); if (i === idx) l.style.setProperty('--k', ((el % per) / per * 100).toFixed(1) + '%'); });
      playRaf = requestAnimationFrame(step);
    });
  }
  $('#playBtn').addEventListener('click', function () { setPlay(!playing); });
  $$('#catrow button').forEach(function (b) { b.addEventListener('click', function () { catSel = b.textContent; $$('#catrow button').forEach(function (x) { x.classList.toggle('on', x === b); }); renderNews(); }); });
  // 面板拖曳
  var np = $('#npanel'), npDrag = null;
  function npOpen(o) { np.style.transform = ''; np.classList.toggle('open', o); }
  $('.grab', np).addEventListener('pointerdown', function (e) { npDrag = { y: e.clientY, h: np.offsetHeight, moved: false }; np.style.transition = 'none'; e.target.setPointerCapture(e.pointerId); });
  $('.grab', np).addEventListener('pointermove', function (e) { if (!npDrag) return; var dy = Math.max(0, e.clientY - npDrag.y); if (dy > 4) npDrag.moved = true; np.style.transform = 'translateY(' + dy + 'px)'; });
  // 點一下收起；拖曳超過面板 35% 才收起，否則彈回
  $('.grab', np).addEventListener('pointerup', function (e) { if (!npDrag) return; var dy = e.clientY - npDrag.y, moved = npDrag.moved; np.style.transition = ''; npDrag = null; npOpen(moved ? dy < np.offsetHeight * .35 : false); });

  /* ---------- 通話房 ---------- */
  var timerT = 0, timerS = 0;
  function startTimer() { stopTimer(); timerS = 0; tick(); timerT = setInterval(function () { timerS++; tick(); }, 1000); }
  function stopTimer() { clearInterval(timerT); timerT = 0; }
  function tick() { var m = Math.floor(timerS / 60), s = timerS % 60; $$('[data-timer]').forEach(function (e) { e.textContent = (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s; }); }
  var dialT = 0;
  function setCall(v, state) {
    var el = document.getElementById(v); el.dataset.state = state;
    $$('[data-show]', el).forEach(function (n) { n.hidden = n.dataset.show.split(' ').indexOf(state) < 0; });
    $$('.ctl', el).forEach(function (c) { c.classList.remove('off'); c.disabled = false; });
    $$('.pip', el).forEach(function (p) { p.classList.remove('camoff'); });
    var mb = $('[data-mutebadge]', el); if (mb) mb.classList.remove('show');
    var spk = $('[data-ctl="speaker"]', el), loud = !(state === 'voice' || state === 'dialing');
    spk.dataset.loud = loud ? '1' : '0'; spk.innerHTML = icon(loud ? 'i-vol' : 'i-ear');
    clearTimeout(dialT);
    if (state === 'voice' || state === 'video' || state === 'emergency') startTimer(); else stopTimer();
    if (state === 'dialing') dialT = setTimeout(function () { if (currentView === 'call' && el.dataset.state === 'dialing') { setCall('call', 'voice'); panelChips.forEach(function (c) { c.classList.toggle('on', c.dataset.go === 'call:voice'); }); } }, 3200);
    if (v === 'fcall') { var ft = $('[data-ftype]', el); if (ft) ft.textContent = state === 'voice' ? '語音通話' : '視訊通話'; }
    var pip = $('.pip', el); if (pip && !pip.hidden) requestAnimationFrame(function () { snapPip(pip, pip.dataset.corner || 'tr', true); });
  }
  $$('.call').forEach(function (room) {
    room.addEventListener('click', function (e) {
      var c = e.target.closest('[data-ctl]'); if (!c) return;
      var k = c.dataset.ctl;
      if (k === 'speaker') { var loud = c.dataset.loud !== '1'; c.dataset.loud = loud ? '1' : '0'; c.innerHTML = icon(loud ? 'i-vol' : 'i-ear'); toast(loud ? '擴音' : '聽筒'); return; }
      if (k === 'flip') { toast('已切換前後鏡頭'); return; }
      var off = c.classList.toggle('off');
      if (k === 'mic') { var mb = $('[data-mutebadge]', room); if (mb) mb.classList.toggle('show', off); toast(off ? '麥克風已關閉' : '麥克風已開啟'); }
      if (k === 'cam') { $$('.pip', room).forEach(function (p) { p.classList.toggle('camoff', off); }); var fl = $('[data-ctl="flip"]', room); if (fl) fl.disabled = off; }
    });
  });
  function snapPip(pip, corner, instant) {
    var W = SW(), H = SH(), m = 14, top = 104, bottom = 120;
    var x = corner[1] === 'l' ? m : W - pip.offsetWidth - m, y = corner[0] === 't' ? top : H - pip.offsetHeight - bottom;
    if (instant) pip.style.transition = 'none';
    pip.style.left = x + 'px'; pip.style.top = y + 'px'; pip.dataset.corner = corner;
    if (instant) { void pip.offsetWidth; pip.style.transition = ''; }
  }
  $$('.pip').forEach(function (pip) {
    var d = null;
    pip.addEventListener('pointerdown', function (e) { d = { x: e.clientX, y: e.clientY, l: pip.offsetLeft, t: pip.offsetTop }; pip.classList.add('dragging'); pip.setPointerCapture(e.pointerId); });
    pip.addEventListener('pointermove', function (e) { if (!d) return; pip.style.left = (d.l + (e.clientX - d.x) / SCALE) + 'px'; pip.style.top = (d.t + (e.clientY - d.y) / SCALE) + 'px'; });
    pip.addEventListener('pointerup', function () { if (!d) return; d = null; pip.classList.remove('dragging'); var cx = pip.offsetLeft + pip.offsetWidth / 2, cy = pip.offsetTop + pip.offsetHeight / 2; snapPip(pip, (cy < SH() / 2 ? 't' : 'b') + (cx < SW() / 2 ? 'l' : 'r')); });
  });
  $('#fpip').dataset.corner = 'br';

  /* ---------- 浮層 ---------- */
  var scrim = $('#scrim'), elderOverlays = { help: 1, tasks: 1, reminder: 1, heartbeat: 1, assistant: 1, call: 1 };
  function closeAll() { scrim.classList.remove('show'); $$('.sheet.show,.dialog.show,.callmodal.show').forEach(function (e) { e.classList.remove('show'); }); }
  function overlay(kind) {
    if (elderOverlays[kind] && currentView !== 'elder' && kind !== 'assistant') go('elder:' + currentTab);
    closeAll();
    if (kind === 'call') { $('#incoming').classList.add('show'); return; }
    var el = document.getElementById('sh-' + kind) || document.getElementById('dl-' + kind);
    if (!el) return;
    scrim.classList.add('show'); el.classList.add('show');
    if (kind === 'tasks') renderTaskSheet();
  }

  /* ---------- 引導式教學 ---------- */
  var tutorials = {
    main: [
      { t: '歡迎使用', b: '接下來帶您看一下最下面的五個按鈕，跟著「下一步」看下去就可以了。' },
      { sel: '[data-tab="home"]', t: '首頁', b: '打開 App 就會先看到這裡，可以看到今天的日期，還有每天更新的新聞。' },
      { sel: '[data-tab="phone"]', t: '電話', b: '想打電話給家人的時候，按這裡就對了。' },
      { sel: '[data-tab="pet"]', t: '小豬', b: '這是陪您一起變健康的小豬，可以餵牠吃東西，還能讓牠幫您做祝福圖傳到 LINE。' },
      { sel: '[data-tab="chat"]', t: '聊天', b: '有什麼想問的、想聊的，都可以按這裡跟 AI 好朋友小嘎說話。' },
      { sel: '[data-tab="profile"]', t: '我的', b: '這裡有每天的小任務、連續完成的天數，還有跟家人配對、設定的地方。' }
    ],
    home: [
      { sel: '#tabHome [data-tut="date"]', t: '今日日期', b: '這裡會顯示今天的日期、農民曆和節氣，按下去還能看更多內容。' },
      { sel: '#tabHome [data-taskcard]', t: '今天要做的事', b: '圈圈是今天完成了幾件事，右邊是下一件。做好了按「打卡」。' },
      { sel: '#tabHome [data-tut="news"]', t: '今日頭條', b: '每天都會更新新聞，按下去可以用聽的，不用自己看小字。' },
      { sel: '#tabHome [data-tut="more"]', t: '看更多新聞', b: '想看其他新聞的話，按這裡就可以看到更多則。' }
    ]
  };
  var tut = $('#tut'), hole = $('#tutHole'), ring = $('#tutRing'), card = $('#tutCard'), tutSteps = null, tutI = 0;
  var H = { x: 0, y: 0, w: 0, h: 0 };
  function drawHole() { ['x', 'y', 'w', 'h'].forEach(function (k) { }); hole.setAttribute('x', H.x); hole.setAttribute('y', H.y); hole.setAttribute('width', Math.max(0, H.w)); hole.setAttribute('height', Math.max(0, H.h)); ring.style.left = H.x + 'px'; ring.style.top = H.y + 'px'; ring.style.width = Math.max(0, H.w) + 'px'; ring.style.height = Math.max(0, H.h) + 'px'; ring.style.opacity = H.w > 8 ? 1 : 0; }
  var hs = ['x', 'y', 'w', 'h'].map(function (k) { return new Spring(.75, 300, function (v) { H[k] = v; drawHole(); }); });
  function startTutorial(name) {
    if (currentView !== 'elder') go('elder:home');
    else if (name === 'home' && currentTab !== 'home') selectTab('home', true);
    if (name === 'main' && currentTab !== 'home') selectTab('home', true);
    closeAll();
    tutSteps = tutorials[name]; tutI = 0;
    var cx = SW() / 2, cy = SH() / 2;
    hs[0].to(cx, true); hs[1].to(cy, true); hs[2].to(0, true); hs[3].to(0, true);
    $('#tutDots').innerHTML = tutSteps.map(function () { return '<i></i>'; }).join('');
    tut.classList.add('show'); setTimeout(showStep, 60);
  }
  function showStep() {
    var s = tutSteps[tutI], W = SW(), Hh = SH(), r;
    if (s.sel) {
      var el = $(s.sel), sc = el.closest('.tabview');
      if (sc) { var er = relRect(el); if (er.y < 70 || er.y + er.h > Hh - 140) sc.scrollTop += er.y - Hh * .3; }
      r = relRect(el); r = { x: r.x - 8, y: r.y - 8, w: r.w + 16, h: r.h + 16 };
    } else r = { x: W / 2, y: Hh / 2, w: 0, h: 0 };
    hs[0].to(r.x); hs[1].to(r.y); hs[2].to(r.w); hs[3].to(r.h);
    $$('#tutDots i').forEach(function (d, i) { d.classList.toggle('on', i === tutI); });
    $('#tutStep').textContent = '第 ' + (tutI + 1) + '／共 ' + tutSteps.length + ' 步';
    $('#tutT').textContent = s.t; $('#tutB').textContent = s.b;
    $('#tutNext').textContent = tutI === tutSteps.length - 1 ? '完成' : '下一步';
    card.style.transform = '';
    if (!s.sel) { card.style.top = '50%'; card.style.bottom = 'auto'; card.style.transform = 'translateY(-50%)'; }
    else if (r.y + r.h / 2 < Hh / 2) { card.style.top = 'auto'; card.style.bottom = '28px'; }
    else { card.style.bottom = 'auto'; card.style.top = '58px'; }
    card.animate([{ opacity: .4, transform: card.style.transform + ' scale(.97)' }, { opacity: 1, transform: card.style.transform || 'none' }], { duration: 260, easing: 'cubic-bezier(.2,.8,.2,1)' });
  }
  function stopTutorial(silent) { if (!tut.classList.contains('show')) return; tut.classList.remove('show'); tutSteps = null; if (!silent) toast('之後可以在「我的」頁重新觀看'); }
  $('#tutNext').addEventListener('click', function () { if (!tutSteps) return; if (++tutI >= tutSteps.length) { tut.classList.remove('show'); tutSteps = null; toast('教學完成！'); } else showStep(); });
  $('#tutSkip').addEventListener('click', function () { stopTutorial(false); });

  /* ---------- 點擊總管 ---------- */
  document.addEventListener('click', function (e) {
    var el = e.target.closest('[data-go],[data-overlay],[data-toast],[data-close],[data-tutorial],[data-evo],[data-evo-close],[data-streak],[data-streak-close],[data-feedcarrot],[data-walk],[data-sheet],[data-summary],[data-meaning],[data-npanel],[data-track],[data-like],[data-req],[data-step],[data-done],[data-grp],[data-article],[data-checkin-next]');
    if (!el) return;
    if (el.dataset.done) { e.stopPropagation(); toggleTask(el.dataset.done); return; }
    if (el.dataset.grp) { var k = el.dataset.grp; openGroups[k] = !openGroups[k]; el.setAttribute('aria-expanded', openGroups[k]); el.nextElementSibling.classList.toggle('open', openGroups[k]); return; }
    if (el.matches('[data-close]')) closeAll();
    if (el.matches('[data-checkin-next]')) { var n = nextTask(); if (n) toggleTask(n.id); }
    if (el.dataset.toast) toast(el.dataset.toast);
    if (el.dataset.step) { var v = $('.val', el.closest('[data-stepper]')); v.textContent = Math.max(1, Math.min(120, +v.textContent + (+el.dataset.step))); }
    if (el.dataset.overlay) overlay(el.dataset.overlay);
    if (el.dataset.sheet) { scrim.classList.add('show'); $('#sh-' + el.dataset.sheet).classList.add('show'); }
    if (el.matches('[data-summary]')) { setPlay(false); scrim.classList.add('show'); $('#dl-summary').classList.add('show'); }
    if (el.dataset.meaning) { var p = el.dataset.meaning.split('：'); $('[data-meaning-t]').textContent = '「' + p[0] + '」是什麼意思？'; $('[data-meaning-b]').textContent = p[1]; scrim.classList.add('show'); $('#dl-meaning').classList.add('show'); }
    if (el.dataset.npanel) npOpen(el.dataset.npanel === 'open');
    if (el.dataset.track) { cur = (cur + (+el.dataset.track) + news.length) % news.length; renderNews(); setPlay(true); }
    if (el.dataset.article) { var a = news[+el.dataset.article]; $('#article h1').textContent = a.title; $('#article .ahero').style.background = a.bg; $('#article .abody .tag').textContent = a.cat; cur = +el.dataset.article; go('article'); return; }
    if (el.matches('[data-like]')) { if (el.classList.contains('liked')) { toast('已經按過讚囉'); } else { el.classList.add('liked'); var s = $('span', el); s.textContent = +s.textContent + 1; } }
    if (el.dataset.req) { var rc = $('#reqCard'); rc.animate([{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'scale(.95)' }], { duration: 260 }).onfinish = function () { rc.hidden = true; }; toast(el.dataset.req === 'yes' ? '已成為好友！' : '已拒絕邀請'); }
    if (el.matches('[data-evo]')) { if (currentView !== 'elder' || currentTab !== 'pet') go('elder:pet'); showEvo(); }
    if (el.matches('[data-evo-close]')) closeEvo();
    if (el.matches('[data-streak]')) { if (currentView !== 'elder') go('elder:profile'); celebrate(); }
    if (el.matches('[data-streak-close]')) closeStreak();
    if (el.matches('[data-feedcarrot]')) { closeStreak(); go('elder:pet'); selectFood('carrot'); setTimeout(function () { $('#petStage').scrollIntoView({ block: 'center', behavior: 'smooth' }); }, 300); }
    if (el.matches('[data-walk]')) { if (currentView !== 'elder' || currentTab !== 'pet') go('elder:pet'); setTimeout(walk, 400); }
    if (el.dataset.tutorial) { startTutorial(el.dataset.tutorial); return; }
    if (el.dataset.go) {
      go(el.dataset.go);
      if (el.matches('[data-after-tutorial]')) setTimeout(function () { startTutorial('main'); }, 700);
    }
  });
  $('#searchBtn').addEventListener('click', function () { var r = $('#fresult'); r.hidden = false; r.classList.remove('enter'); void r.offsetWidth; r.classList.add('enter'); });
  $('#sendReq').addEventListener('click', function () { this.outerHTML = '<div class="row" style="margin-top:14px;color:var(--brand-strong);font-weight:700;font-size:18px">' + icon('i-check') + '已送出邀請，等待對方同意</div>'; });
  $('#loginForm').addEventListener('submit', function (e) { e.preventDefault(); toast('登入中…'); setTimeout(function () { toast('登入成功（家屬端下一階段改版）'); }, 700); });
  $('#regForm').addEventListener('submit', function (e) { e.preventDefault(); toast('註冊成功，請登入'); setTimeout(function () { go('login'); }, 900); });
  $('#terms').addEventListener('click', function () { this.classList.toggle('done'); });
  var ls = $('#locSwitch'); ls.addEventListener('click', function () { var on = ls.classList.toggle('on'); $('#locText').textContent = on ? '子女可以看到您的位置與移動路線' : '目前未分享，子女無法看到您的位置'; });
  var tts = $('#ttsBtn'); tts.addEventListener('click', function () { var on = tts.classList.toggle('danger'); tts.classList.toggle('tonal', !on); $('span', tts).textContent = on ? '停止' : '唸給我聽'; });
  var talk = $('#talk');
  talk.addEventListener('pointerdown', function () { talk.classList.add('hold'); $('span', talk).textContent = '放開　送出給小嘎'; });
  ['pointerup', 'pointerleave', 'pointercancel'].forEach(function (ev) { talk.addEventListener(ev, function () { if (!talk.classList.contains('hold')) return; talk.classList.remove('hold'); $('span', talk).textContent = '按住　說話'; }); });

  /* ---------- 示意條碼 ---------- */
  $$('.qrc').forEach(function (cnv) {
    var q = cnv.getContext('2d'), n = 29, seed = +cnv.dataset.seed || 1;
    function rnd() { seed = (seed * 16807) % 2147483647; return seed / 2147483647; }
    q.fillStyle = '#fff'; q.fillRect(0, 0, n, n); q.fillStyle = '#16201C';
    for (var y = 0; y < n; y++) for (var x = 0; x < n; x++) if (rnd() > .52) q.fillRect(x, y, 1, 1);
    [[0, 0], [n - 7, 0], [0, n - 7]].forEach(function (p) { q.fillStyle = '#fff'; q.fillRect(Math.max(0, p[0] - 1), Math.max(0, p[1] - 1), 8, 8); q.fillStyle = '#16201C'; q.fillRect(p[0], p[1], 7, 7); q.fillStyle = '#fff'; q.fillRect(p[0] + 1, p[1] + 1, 5, 5); q.fillStyle = '#1F7A5C'; q.fillRect(p[0] + 2, p[1] + 2, 3, 3); });
  });

  /* ---------- 等比縮放：內容鎖 390px 參考寬，整體縮放到實際螢幕 ---------- */
  function fitScreen() {
    if (!canvas || !screen) return;
    var pw = screen.clientWidth, ph = screen.clientHeight;
    if (pw <= 0 || ph <= 0) return;
    SCALE = pw / 390;
    canvas.style.setProperty('--s', SCALE);
    canvas.style.setProperty('--screen-h', (ph / SCALE) + 'px');
  }
  fitScreen();
  window.addEventListener('orientationchange', function () { setTimeout(fitScreen, 120); });

  /* ---------- 捲動：浮層自動隱藏（麥克風＋怎麼用？），導覽列常駐 ---------- */
  var micBtn = $('.mic'), helpPill = $('.helppill');
  function setFloatHide(h) { if (micBtn) micBtn.classList.toggle('scrollaway', h); if (helpPill) helpPill.classList.toggle('scrollaway', h); }
  function resetFloatHide() { setFloatHide(false); }
  function onTabScroll(e) {
    var el = e.currentTarget, y = el.scrollTop, d = y - (el._ly || 0);
    // 累積方向位移，避免小抖動一直翻來翻去
    el._acc = (el._acc || 0) + d; if (d * el._acc < 0) el._acc = d;
    el._ly = y;
    if (!reduce) {
      if (el._acc > 28 && y > 60) { setFloatHide(true); el._acc = 0; }
      else if (el._acc < -24) { setFloatHide(false); el._acc = 0; }
    }
    clearTimeout(el._idle); el._idle = setTimeout(resetFloatHide, 1100);
  }
  $$('.tabview').forEach(function (v) { v.addEventListener('scroll', onTabScroll, { passive: true }); });

  /* ---------- 聊天橡皮筋：拖到邊界把泡泡「拉開」，放手彈回（iMessage 式） ---------- */
  var chatView = $('#tabChat .chat-scroll');
  if (chatView && !reduce) {
    var MAX_PULL = 26, RESIST = 90;
    var cDragging = false, cHijack = false, cLastY = 0, cOver = 0, cEdge = 0, cSpringRaf = 0;
    var cBubs = function () { return $$('.bub', chatView); };
    function applyPull(p) {
      var bs = cBubs(), n = Math.max(1, bs.length - 1);
      bs.forEach(function (b, i) {
        // 離被拉的邊越遠，位移越多 → 相鄰泡泡被拉開
        var dist = cEdge < 0 ? i / n : 1 - i / n;
        b.style.transform = 'translate3d(0,' + (p * (0.3 + dist * 0.95)).toFixed(2) + 'px,0)';
      });
    }
    function clearPull() { cBubs().forEach(function (b) { b.style.transform = ''; }); }
    chatView.addEventListener('pointerdown', function (e) {
      if (e.pointerType === 'mouse' && e.button !== 0) return;
      cDragging = true; cHijack = false; cLastY = e.clientY; cOver = 0;
      if (cSpringRaf) { cancelAnimationFrame(cSpringRaf); cSpringRaf = 0; }
    });
    chatView.addEventListener('pointermove', function (e) {
      if (!cDragging) return;
      var dy = e.clientY - cLastY; cLastY = e.clientY;
      var atTop = chatView.scrollTop <= 0;
      var atBottom = chatView.scrollTop + chatView.clientHeight >= chatView.scrollHeight - 1;
      if (!cHijack) {
        if (atTop && dy > 0) { cHijack = true; cEdge = -1; }
        else if (atBottom && dy < 0) { cHijack = true; cEdge = 1; }
        if (cHijack) { try { chatView.setPointerCapture(e.pointerId); } catch (x) { } }
      }
      if (cHijack) {
        cOver += dy;
        if ((cEdge < 0 && cOver <= 0) || (cEdge > 0 && cOver >= 0)) { cHijack = false; cOver = 0; clearPull(); return; }
        e.preventDefault();
        var pull = Math.sign(cOver) * MAX_PULL * (1 - 1 / (1 + Math.abs(cOver) / RESIST));
        applyPull(pull);
      }
    }, { passive: false });
    function cRelease() {
      cDragging = false;
      if (!cHijack) return; cHijack = false;
      var pull = Math.sign(cOver) * MAX_PULL * (1 - 1 / (1 + Math.abs(cOver) / RESIST)), v = 0;
      (function spring() {
        v += (0 - pull) * 0.2; v *= 0.78; pull += v;
        applyPull(pull);
        if (Math.abs(v) > 0.05 || Math.abs(pull) > 0.05) cSpringRaf = requestAnimationFrame(spring);
        else { clearPull(); cSpringRaf = 0; }
      })();
    }
    chatView.addEventListener('pointerup', cRelease);
    chatView.addEventListener('pointercancel', cRelease);
  }

  /* ---------- 首頁大卡「寶石鑲入」入場（輕微，交錯） ---------- */
  function playHomeIntro() {
    if (reduce) return;
    $$('#tabHome .stack > .card').forEach(function (c, i) {
      c.classList.remove('gem-in'); void c.offsetWidth;
      c.style.animationDelay = (i * 95) + 'ms';
      c.classList.add('gem-in');
    });
  }

  go(location.hash === '#elder' ? 'elder:home' : 'splash');
  if (showcaseEmbed) window.parent.postMessage({ app: 'uban-prototype', type: 'ready', role: 'elder' }, '*');
})();
