(function () {
  'use strict';
  var root = document.documentElement;
  var screen = document.getElementById('screen');
  var showcaseEmbed = window.parent !== window && new URLSearchParams(window.location.search).get('showcase') === '1';
  if (showcaseEmbed) root.classList.add('showcase-embed');
  var canvas = document.getElementById('canvas');
  var SCALE = 1;
  var reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  function $(s, c) { return (c || document).querySelector(s); }
  function $$(s, c) { return Array.prototype.slice.call((c || document).querySelectorAll(s)); }
  function store(k, v) { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) { return null; } }
  function icon(id, size) { return '<svg class="ic24"' + (size ? ' style="width:' + size + 'px;height:' + size + 'px"' : '') + '><use href="#' + id + '"/></svg>'; }
  function easeOutQuart(x) { return 1 - Math.pow(1 - x, 4); }

  /* ---------- 等比縮放（同長輩稿） ---------- */
  function fitScreen() {
    var pw = screen.clientWidth, ph = screen.clientHeight;
    if (pw <= 0 || ph <= 0) return;
    SCALE = pw / 390;
    canvas.style.setProperty('--s', SCALE);
    canvas.style.setProperty('--screen-h', (ph / SCALE) + 'px');
  }
  fitScreen();

  /* ---------- 外觀 ---------- */
  var themeBtns = $$('[data-theme-set]');
  function isDark() { var t = root.getAttribute('data-theme'); return t ? t === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches; }
  function setTheme(t) {
    if (t === 'system') root.removeAttribute('data-theme'); else root.setAttribute('data-theme', t);
    themeBtns.forEach(function (b) { b.classList.toggle('on', b.dataset.themeSet === t); });
    $('#darkSwitch').classList.toggle('on', isDark());
    store('uban-theme', t);
  }
  themeBtns.forEach(function (b) { b.addEventListener('click', function () { setTheme(b.dataset.themeSet); }); });
  setTheme(store('uban-theme') || 'system');
  $('#darkSwitch').addEventListener('click', function (e) { e.stopPropagation(); setTheme(isDark() ? 'light' : 'dark'); });

  /* ---------- 家屬端主色候選 ---------- */
  var accentBtns = $$('[data-accent-set]');
  function setAccent(a) {
    if (a === 'green') delete screen.dataset.accent; else screen.dataset.accent = a;
    accentBtns.forEach(function (b) { b.classList.toggle('on', b.dataset.accentSet === a); });
    store('uban-fam-accent-v3', a);
  }
  accentBtns.forEach(function (b) { b.addEventListener('click', function () { setAccent(b.dataset.accentSet); }); });
  setAccent(store('uban-fam-accent-v3') || 'ocean');

  /* ---------- 液態暈開 ---------- */
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
    var t0 = performance.now();
    (function f(now) {
      var k = Math.min(1, (now - t0) / 620), p = easeOutQuart(k);
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
  var views = ['fmain', 'map', 'places', 'trends', 'health', 'alerts', 'copilot', 'memoirs', 'sub', 'fwelcome', 'fpair', 'fselect', 'fcall'];
  var pushed = { map: 1, places: 1, trends: 1, health: 1, alerts: 1, copilot: 1, memoirs: 1, sub: 1, fpair: 1, fcall: 1 };
  var statusbar = $('#statusbar'), panelChips = $$('.panel [data-go]');
  var currentView = '', history = [];
  function show(id) {
    views.forEach(function (v) {
      var el = document.getElementById(v), on = v === id;
      el.hidden = !on;
      if (on && v !== currentView) { el.classList.remove('enter', 'push-enter'); void el.offsetWidth; el.classList.add(pushed[v] ? 'push-enter' : 'enter'); el.scrollTop = 0; }
    });
    currentView = id;
    statusbar.classList.toggle('light', id === 'fcall');
  }
  function go(target, fromBack) {
    closeAll();
    var parts = target.split(':'), v = parts[0], sub = parts[1];
    if (!fromBack && currentView && currentView !== v) history.push(currentView === 'fmain' ? 'fmain:' + currentTab : currentView === 'fcall' ? 'fmain:' + currentTab : currentView);
    show(v);
    if (v === 'fmain') selectTab(sub || currentTab, true);
    if (v === 'fcall') setCall(sub || 'video'); else stopTimer();
    if (v === 'map') renderMap();
    if (v === 'trends') renderTrends();
    if (v === 'health') renderHealth();
    requestAnimationFrame(layoutSegs);
    panelChips.forEach(function (c) { c.classList.toggle('on', c.dataset.go === target || (!sub && c.dataset.go === v)); });
  }

  window.addEventListener('message', function (event) {
    if (!showcaseEmbed || event.source !== window.parent) return;
    var data = event.data || {};
    if (data.app !== 'uban-showcase' || data.command !== 'show') return;
    if (typeof data.target !== 'string' || !/^[a-z]+(?::[a-z]+)?$/.test(data.target)) return;
    go(data.target);
    window.parent.postMessage({ app: 'uban-prototype', type: 'shown', target: data.target, role: 'family' }, '*');
  });
  function back() { go(history.pop() || 'fmain:' + currentTab, true); }

  /* ---------- 導覽列 ---------- */
  var nav = $('#nav'), ind = $('#ind'), navBtns = $$('button', nav), IND_W = 58;
  var navSpring = new Spring(.8, 380, function (x, v) { var s = Math.min(30, Math.abs(v) * .045); ind.style.width = (IND_W + s) + 'px'; ind.style.transform = 'translateX(' + (x - s / 2) + 'px)'; });
  var tabs = { home: 'tabHome', interact: 'tabInteract', data: 'tabData' }, currentTab = 'home';
  function targetX(btn) { return btn.offsetLeft + btn.offsetWidth / 2 - IND_W / 2; }
  function selectTab(name, instant) {
    var btn = $('[data-tab="' + name + '"]', nav);
    navBtns.forEach(function (b) { b.classList.toggle('on', b === btn); });
    if (!instant) { btn.classList.remove('pop'); void btn.offsetWidth; btn.classList.add('pop'); try { navigator.vibrate && navigator.vibrate(8); } catch (e) { } }
    Object.keys(tabs).forEach(function (k) { var el = document.getElementById(tabs[k]), on = k === name; el.hidden = !on; if (on && k !== currentTab) { el.classList.remove('enter'); void el.offsetWidth; el.classList.add('enter'); el.scrollTop = 0; } });
    currentTab = name;
    if (name === 'data') renderSparks();
    requestAnimationFrame(function () { navSpring.to(targetX(btn), instant); });
    panelChips.forEach(function (c) { c.classList.toggle('on', c.dataset.go === 'fmain:' + name); });
  }
  navBtns.forEach(function (b) { b.addEventListener('click', function () { if (b.dataset.tab !== currentTab) selectTab(b.dataset.tab); }); });
  window.addEventListener('resize', function () { fitScreen(); var b = $('.on', nav); if (b) navSpring.to(targetX(b), true); layoutSegs(); });

  /* ---------- 分段切換 ---------- */
  function layoutSegs() { $$('[data-seg]').forEach(function (s) { var on = $('button.on', s), th = $('.thumb', s); if (on && on.offsetWidth) { th.style.left = on.offsetLeft + 'px'; th.style.width = on.offsetWidth + 'px'; } }); }
  $$('[data-seg]').forEach(function (s) {
    $$('button', s).forEach(function (b) {
      b.addEventListener('click', function () {
        $$('button', s).forEach(function (x) { x.classList.toggle('on', x === b); }); layoutSegs();
        if (b.dataset.pane) $$('[data-pane-body]', s.parentElement).forEach(function (p) { p.hidden = p.dataset.paneBody !== b.dataset.pane; });
        if (b.dataset.range) { range = +b.dataset.range; renderTrends(); }
        if (b.dataset.hk) { healthKey = b.dataset.hk; renderHealth(); }
      });
    });
  });

  /* ---------- 浮層 ---------- */
  var scrim = $('#scrim');
  function closeAll() { scrim.classList.remove('show'); $$('.sheet.show,.alarm.show').forEach(function (e) { e.classList.remove('show'); }); }
  function openSheet(name) {
    if (name === 'timeline') renderTimeline();
    if (currentView !== 'fmain' && (name === 'elder')) go('fmain:' + currentTab);
    if (name === 'timeline' && currentView !== 'map') go('map');
    closeAll(); scrim.classList.add('show'); $('#sh-' + name).classList.add('show');
  }

  /* ---------- 全域點擊 ---------- */
  screen.addEventListener('click', function (e) {
    var t = e.target;
    var sw = t.closest('.switch'); if (sw && sw.id !== 'darkSwitch') { sw.classList.toggle('on'); return; }
    var pick = t.closest('[data-pick]'); if (pick) { $$('[data-pick]', pick.parentElement).forEach(function (x) { x.classList.toggle('on', x === pick); }); }
    var pc = t.closest('[data-pickcard]'); if (pc) { $$('[data-pickcard]', pc.parentElement).forEach(function (x) { x.classList.toggle('on', x === pc); }); return; }
    var pl = t.closest('[data-plan]'); if (pl) { $$('[data-plan]').forEach(function (x) { x.classList.toggle('on', x === pl); }); return; }
    var fc = t.closest('.fchip'); if (fc) { $$('.fchip', fc.parentElement).forEach(function (x) { x.classList.toggle('on', x === fc); }); return; }
    var bk = t.closest('[data-back]'); if (bk) { back(); return; }
    var g = t.closest('[data-go]'); if (g) { go(g.dataset.go); return; }
    var o = t.closest('[data-overlay]'); if (o) { openSheet(o.dataset.overlay); return; }
    var ts = t.closest('[data-toast]'); if (ts) toast(ts.dataset.toast);
    if (t.closest('[data-close]')) closeAll();
  });
  $$('.panel [data-go]').forEach(function (b) { b.addEventListener('click', function () { history = []; go(b.dataset.go); }); });
  $$('.panel [data-overlay]').forEach(function (b) { b.addEventListener('click', function () { openSheet(b.dataset.overlay); }); });
  $$('.panel [data-alarm]').forEach(function (b) { b.addEventListener('click', function () { showAlarm(b.dataset.alarm); }); });

  /* ---------- 地圖（示意底圖；Flutter 用 flutter_map 圖磚） ---------- */
  var H = [240, 480], T = [112, 452], M = [322, 548];
  var leg1 = [H, [240, 500], [190, 500], [190, 420], [120, 420], T];
  var leg2 = [T, [120, 500], [190, 500], [300, 500], [300, 560], M];
  var gapLeg = [M, [240, 500]];
  var leg3 = [[240, 500], H];
  var places = [
    { p: H, r: 26, home: true, name: '家' },
    { p: T, r: 34, name: '龍山寺' },
    { p: M, r: 30, name: '南機場市場' },
    { p: [86, 640], r: 46, name: '青年公園' }
  ];
  function pts(a) { return a.map(function (q) { return q[0] + ',' + q[1]; }).join(' '); }
  var mapState = 'ok';
  function mapSvg(vb, mini) {
    var s = '<svg viewBox="' + vb + '" preserveAspectRatio="xMidYMid slice" aria-label="秀枝阿嬤今天的移動軌跡（示意）">';
    s += '<defs><linearGradient id="trailG' + (mini ? 'm' : '') + '" gradientUnits="userSpaceOnUse" x1="240" y1="480" x2="322" y2="548"><stop offset="0" stop-color="var(--trail-a)"/><stop offset="1" stop-color="var(--trail-b)"/></linearGradient></defs>';
    s += '<rect x="-400" y="-400" width="1200" height="1700" fill="var(--map-land)"/>';
    // 街廓
    for (var y = 120; y < 860; y += 80) for (var x = 70; x < 390; x += 60) s += '<rect x="' + (x + 6) + '" y="' + (y + 6) + '" width="48" height="68" rx="4" fill="var(--map-block)"/>';
    // 公園與河
    s += '<rect x="44" y="590" width="96" height="104" rx="10" fill="var(--map-park)"/>';
    s += '<path d="M-20 140 C 30 300, 10 420, 40 560 S 30 760, 60 900 L -60 900 L -60 140 Z" fill="var(--map-water)"/>';
    // 道路
    var roads = [[60, 300, 400, 300], [60, 420, 400, 420], [60, 500, 400, 500], [60, 580, 400, 580], [60, 700, 400, 700], [120, 100, 120, 860], [190, 100, 190, 860], [240, 100, 240, 860], [300, 100, 300, 860], [360, 100, 360, 860]];
    roads.forEach(function (r) { s += '<line x1="' + r[0] + '" y1="' + r[1] + '" x2="' + r[2] + '" y2="' + r[3] + '" stroke="var(--map-road-edge)" stroke-width="12" stroke-linecap="round"/>'; });
    roads.forEach(function (r) { s += '<line x1="' + r[0] + '" y1="' + r[1] + '" x2="' + r[2] + '" y2="' + r[3] + '" stroke="var(--map-road)" stroke-width="9" stroke-linecap="round"/>'; });
    if (!mini) {
      s += '<text x="26" y="380" fill="var(--map-label)" font-size="11" font-weight="700" transform="rotate(80 26 380)" style="letter-spacing:.3em">淡水河</text>';
      s += '<text x="250" y="414" fill="var(--map-label)" font-size="10">廣州街</text><text x="250" y="574" fill="var(--map-label)" font-size="10">西藏路</text>';
    }
    // 常去地點範圍
    places.forEach(function (pl) {
      var c = pl.home ? 'var(--place-home)' : 'var(--place-other)';
      s += '<circle cx="' + pl.p[0] + '" cy="' + pl.p[1] + '" r="' + pl.r + '" fill="' + c + '" fill-opacity=".12" stroke="' + c + '" stroke-opacity=".5" stroke-width="1.5"/>';
    });
    // 軌跡：白邊＋漸層；斷訊用虛線
    var g = 'url(#trailG' + (mini ? 'm' : '') + ')';
    [leg1, leg2, leg3].forEach(function (l) { s += '<polyline points="' + pts(l) + '" fill="none" stroke="var(--surface)" stroke-width="9" stroke-linejoin="round" stroke-linecap="round"/>'; });
    [leg1, leg2, leg3].forEach(function (l) { s += '<polyline points="' + pts(l) + '" fill="none" stroke="' + g + '" stroke-width="5" stroke-linejoin="round" stroke-linecap="round"/>'; });
    s += '<polyline points="' + pts(gapLeg) + '" fill="none" stroke="var(--text-3)" stroke-width="3" stroke-dasharray="5 6" stroke-linecap="round"/>';
    if (!mini) {
      // 地點名稱
      places.forEach(function (pl) { if (!pl.home) s += '<text x="' + pl.p[0] + '" y="' + (pl.p[1] + pl.r + 14) + '" text-anchor="middle" fill="var(--text-2)" font-size="11.5" font-weight="700" stroke="var(--map-land)" stroke-width="3" paint-order="stroke">' + pl.name + '</text>'; });
      // 停留膠囊
      [[T, '停留 42 分'], [M, '停留 25 分']].forEach(function (st) {
        var x = st[0][0], y = st[0][1] - 26;
        s += '<g><rect x="' + (x - 36) + '" y="' + (y - 12) + '" width="72" height="24" rx="12" fill="var(--stay)"/><text x="' + x + '" y="' + (y + 4) + '" text-anchor="middle" fill="var(--bg)" font-size="11.5" font-weight="700">' + st[1] + '</text><path d="M' + (x - 5) + ' ' + (y + 12) + ' L' + x + ' ' + (y + 18) + ' L' + (x + 5) + ' ' + (y + 12) + 'Z" fill="var(--stay)"/></g>';
      });
    } else {
      [T, M].forEach(function (p) { s += '<circle cx="' + p[0] + '" cy="' + p[1] + '" r="6" fill="var(--stay)" stroke="var(--surface)" stroke-width="2.5"/>'; });
    }
    // 起點
    s += '<circle cx="' + (H[0] + 9) + '" cy="' + (H[1] + 4) + '" r="5" fill="var(--place-home)" stroke="var(--surface)" stroke-width="2"/>';
    // 目前位置（過舊時變灰）
    var pc = mapState === 'stale' || mapState === 'device' ? 'var(--text-3)' : 'var(--pin)';
    if (mapState === 'ok' && !reduce) s += '<circle cx="' + H[0] + '" cy="' + H[1] + '" r="10" fill="' + pc + '" opacity=".25"><animate attributeName="r" values="10;22;10" dur="2.4s" repeatCount="indefinite"/><animate attributeName="opacity" values=".3;0;.3" dur="2.4s" repeatCount="indefinite"/></circle>';
    s += '<circle cx="' + H[0] + '" cy="' + H[1] + '" r="9" fill="' + pc + '" stroke="var(--surface)" stroke-width="3.5"/>';
    if (!mini) s += '<g transform="translate(' + (H[0] + 14) + ' ' + (H[1] - 30) + ')"><rect width="44" height="22" rx="11" fill="var(--place-home)"/><text x="22" y="15" text-anchor="middle" fill="var(--bg)" font-size="11.5" font-weight="900">家</text></g>';
    return s + '</svg>';
  }
  $('#miniMap').innerHTML = mapSvg('8 404 384 160', true);
  var dayOffset = 0;
  function renderMap() {
    $('#bigMap').innerHTML = mapSvg('0 0 390 ' + Math.round(screen.clientHeight / SCALE), false);
    var stale = mapState === 'stale' || mapState === 'device';
    $('#mapWarn').hidden = mapState !== 'device';
    var ms = $('#mapStatus'); ms.classList.toggle('stale', stale);
    $('#msTitle').textContent = stale ? '最後位置在家附近' : dayOffset ? '這天外出 1 次' : '在家，已停留 2 小時 53 分';
    $('#msSub').textContent = stale ? '最後更新 09:58・已經 3 小時沒有新位置' : dayOffset ? '移動 1.2 公里・在外 48 分鐘' : '最後更新 12:55・今天外出 2 次';
    var empty = $('#mapEmpty');
    empty.hidden = !(mapState === 'off' || mapState === 'empty');
    if (mapState === 'off') { $('#meIcon').innerHTML = '<use href="#i-lock"/>'; $('#meTitle').textContent = '阿嬤關閉了位置分享'; $('#meText').textContent = '這是阿嬤自己的設定。她在「我的」頁打開「分享我的位置」後，這裡就會出現她的位置與路線。'; $('#meBtn').hidden = false; }
    if (mapState === 'empty') { $('#meIcon').innerHTML = '<use href="#i-map"/>'; $('#meTitle').textContent = dayOffset ? '這天沒有位置紀錄' : '今天還沒有位置紀錄'; $('#meText').textContent = '阿嬤的手機回報位置後就會出現在這裡。一直沒有的話，可能是手機沒開定位或沒有網路。'; $('#meBtn').hidden = true; }
    $('#dLabel').textContent = dayOffset ? fmtDate(dayOffset) : '今天';
    $('#dNext').disabled = dayOffset === 0;
    $('#dPrev').disabled = dayOffset <= -29;
  }
  function fmtDate(off) { var d = new Date(2026, 9, 4 + off); return (d.getMonth() + 1) + '/' + d.getDate(); }
  $('#dPrev').addEventListener('click', function (e) { e.stopPropagation(); dayOffset--; renderMap(); });
  $('#dNext').addEventListener('click', function (e) { e.stopPropagation(); if (dayOffset < 0) dayOffset++; renderMap(); });
  $$('[data-mapstate]').forEach(function (b) {
    b.addEventListener('click', function () {
      mapState = b.dataset.mapstate;
      $$('[data-mapstate]').forEach(function (x) { x.classList.toggle('on', x === b); });
      if (currentView !== 'map') { history = []; go('map'); } else renderMap();
    });
  });

  /* ---------- 時間軸 ---------- */
  var events = [
    { k: 'depart', t: '08:12', b: '出門', s: '離開家' },
    { k: 'move', t: '08:12', b: '移動 1.1 公里', s: '步行約 19 分鐘' },
    { k: 'stay', t: '08:31', b: '停留在龍山寺', s: '42 分鐘' },
    { k: 'move', t: '09:13', b: '移動 0.9 公里', s: '步行約 7 分鐘' },
    { k: 'stay', t: '09:20', b: '停留在南機場市場', s: '25 分鐘' },
    { k: 'gap', t: '09:45', b: '訊號中斷 17 分鐘', s: '這段路線用虛線表示' },
    { k: 'depart', t: '10:02', b: '回到家', s: '到現在 2 小時 53 分' }
  ];
  function renderTimeline() {
    $('#tline').innerHTML = events.map(function (e) { return '<button class="ev ' + e.k + ' press" data-toast="地圖移到 ' + e.t + '" data-close><time>' + e.t + '</time><span class="rail"><i></i></span><span class="c"><b>' + e.b + '</b><small>' + e.s + '</small></span></button>'; }).join('');
  }

  /* ---------- 外出趨勢 ---------- */
  var range = 7, healthKey = 'steps';
  function seq(n, seed, lo, hi, dec) { var a = [], x = seed; for (var i = 0; i < n; i++) { x = (x * 9301 + 49297) % 233280; a.push(+(lo + (x / 233280) * (hi - lo)).toFixed(dec)); } return a; }
  var d7 = { dist: [2.1, 3.4, 1.2, 2.8, 0.6, 3.1, 2.4], count: [2, 3, 1, 2, 1, 2, 2], time: [2.5, 3.2, 1.1, 2.7, 0.5, 3.0, 1.8] };
  function data(key) {
    if (range === 7) return d7[key];
    var base = { dist: seq(23, 7, 0.4, 3.8, 1), count: seq(23, 11, 0, 3.4, 0).map(Math.round), time: seq(23, 5, 0.3, 3.4, 1) }[key];
    return base.concat(d7[key]);
  }
  function dayLabel(i, n) { var off = i - (n - 1); return off === 0 ? '今天' : fmtDate(off); }
  function avg(a) { var x = a.slice(0, -1); return x.reduce(function (s, v) { return s + v; }, 0) / x.length; }
  function niceMax(v) { var steps = [1, 2, 3, 4, 5, 6, 8, 10]; for (var i = 0; i < steps.length; i++) if (steps[i] >= v) return steps[i]; return Math.ceil(v / 5) * 5; }
  function barChart(el, title, color, unit, vals, fmt) {
    var W = 330, Hh = 150, L = 30, B = 22, Tp = 18, n = vals.length, max = niceMax(Math.max.apply(null, vals));
    var cw = (W - L) / n, bw = Math.max(4, Math.min(26, cw * .56));
    var s = '<div class="chart-h"><h4><i style="background:' + color + '"></i>' + title + '</h4><small>平均 ' + fmt(avg(vals)) + ' ' + unit + '</small></div><svg viewBox="0 0 ' + W + ' ' + (Hh + B) + '">';
    [0, .5, 1].forEach(function (f) { var y = Tp + (Hh - Tp) * (1 - f); s += '<line class="grid" x1="' + L + '" x2="' + W + '" y1="' + y + '" y2="' + y + '"/><text class="lab" x="' + (L - 6) + '" y="' + (y + 4) + '" text-anchor="end">' + fmt(max * f) + '</text>'; });
    vals.forEach(function (v, i) {
      var h = (Hh - Tp) * v / max, x = L + cw * i + (cw - bw) / 2, y = Hh - h, today = i === n - 1;
      s += '<rect x="' + x.toFixed(1) + '" y="' + y.toFixed(1) + '" width="' + bw.toFixed(1) + '" height="' + Math.max(h, 1.5).toFixed(1) + '" rx="' + Math.min(6, bw / 2).toFixed(1) + '" fill="' + color + '"' + (today ? ' fill-opacity=".38"' : '') + ' style="cursor:pointer" data-day="' + i + '"><title>' + dayLabel(i, n) + ' ' + fmt(v) + ' ' + unit + '</title></rect>';
      if (n <= 7) s += '<text class="val" x="' + (x + bw / 2) + '" y="' + (y - 5) + '" text-anchor="middle">' + fmt(v) + '</text>';
      if (n <= 7 || i % 5 === 4 || today) s += '<text class="' + (today ? 'labz' : 'lab') + '" x="' + (L + cw * i + cw / 2) + '" y="' + (Hh + 16) + '" text-anchor="middle">' + (today ? (n <= 7 ? '今天' : '今') : dayLabel(i, n)) + '</text>';
    });
    s += '</svg><div class="legend"><span><i style="background:' + color + '"></i>已結算</span><span><i style="background:' + color + ';opacity:.38"></i>今天（統計中）</span></div>';
    el.innerHTML = s;
  }
  function f1(v) { return (Math.round(v * 10) / 10).toString(); }
  function f0(v) { return String(Math.round(v)); }
  function renderTrends() {
    var dist = data('dist'), count = data('count'), time = data('time');
    $('#sumGrid').innerHTML = '<div class="stat"><small>平均距離</small><b>' + f1(avg(dist)) + '<i>公里</i></b></div><div class="stat"><small>平均外出</small><b>' + f1(avg(count)) + '<i>次</i></b></div><div class="stat"><small>平均在外</small><b>' + f1(avg(time)) + '<i>小時</i></b></div>';
    barChart($('#chDist'), '移動距離', 'var(--fam-chart-2)', '公里', dist, f1);
    barChart($('#chCount'), '外出次數', 'var(--fam-chart-1)', '次', count, f0);
    barChart($('#chTime'), '在外時間', 'var(--fam-chart-3)', '小時', time, f1);
  }
  $('#trends').addEventListener('click', function (e) { var r = e.target.closest('[data-day]'); if (!r) return; var n = range, off = +r.dataset.day - (n - 1); dayOffset = off; toast('開啟 ' + (off ? fmtDate(off) : '今天') + ' 的地圖'); go('map'); });

  /* ---------- 健康趨勢（折線） ---------- */
  var hdata = { steps: { v: [3200, 4100, 2650, 5620, 3980, 4300, 3482], u: '步', goal: 4000, f: function (v) { return Math.round(v).toLocaleString('en-US'); } }, weight: { v: [52.6, 52.4, 52.5, 52.3, 52.2, 52.4, 52.1], u: '公斤', f: f1 }, height: { v: [153, 153, 153, 153, 153, 153, 153], u: '公分', f: f0 } };
  function lineChart(el, d) {
    var W = 330, Hh = 170, L = 44, B = 22, Tp = 16, n = d.v.length;
    var lo = Math.min.apply(null, d.v.concat(d.goal || d.v[0])), hi = Math.max.apply(null, d.v.concat(d.goal || d.v[0]));
    var pad = (hi - lo) * .15 || hi * .02; lo -= pad; hi += pad;
    function X(i) { return L + (W - L - 10) * i / (n - 1); }
    function Y(v) { return Tp + (Hh - Tp) * (1 - (v - lo) / (hi - lo)); }
    var s = '<div class="chart-h"><h4><i style="background:var(--fam-chart-1)"></i>' + ({ steps: '每日步數', weight: '體重', height: '身高' })[healthKey] + '</h4><small>最近 7 天</small></div><svg viewBox="0 0 ' + W + ' ' + (Hh + B) + '">';
    [0, .5, 1].forEach(function (f) { var v = lo + (hi - lo) * f, y = Y(v); s += '<line class="grid" x1="' + L + '" x2="' + W + '" y1="' + y + '" y2="' + y + '"/><text class="lab" x="' + (L - 6) + '" y="' + (y + 4) + '" text-anchor="end">' + d.f(v) + '</text>'; });
    if (d.goal) s += '<line x1="' + L + '" x2="' + W + '" y1="' + Y(d.goal) + '" y2="' + Y(d.goal) + '" stroke="var(--warm)" stroke-dasharray="4 5" stroke-width="1.5"/><text x="' + (W - 2) + '" y="' + (Y(d.goal) - 6) + '" text-anchor="end" class="labz" style="fill:var(--warm)">目標</text>';
    var line = d.v.map(function (v, i) { return X(i).toFixed(1) + ',' + Y(v).toFixed(1); }).join(' ');
    s += '<polygon points="' + X(0) + ',' + Hh + ' ' + line + ' ' + X(n - 1) + ',' + Hh + '" fill="var(--fam-chart-1)" fill-opacity=".1"/>';
    s += '<polyline points="' + line + '" fill="none" stroke="var(--fam-chart-1)" stroke-width="2.5" stroke-linejoin="round"/>';
    d.v.forEach(function (v, i) { var last = i === n - 1; s += '<circle cx="' + X(i) + '" cy="' + Y(v) + '" r="' + (last ? 5 : 3) + '" fill="' + (last ? 'var(--fam-chart-1)' : 'var(--surface)') + '" stroke="var(--fam-chart-1)" stroke-width="2"/>'; s += '<text class="' + (last ? 'labz' : 'lab') + '" x="' + X(i) + '" y="' + (Hh + 16) + '" text-anchor="middle">' + dayLabel(i, n) + '</text>'; });
    var lv = d.v[n - 1]; s += '<text class="val" x="' + (X(n - 1) - 8) + '" y="' + (Y(lv) - 10) + '" text-anchor="end">' + d.f(lv) + ' ' + d.u + '</text>';
    el.innerHTML = s + '</svg>';
  }
  function renderHealth() { lineChart($('#chHealth'), hdata[healthKey]); }

  /* ---------- 迷你走勢 ---------- */
  function spark(el, vals, color) {
    var W = 120, Hh = 30, lo = Math.min.apply(null, vals), hi = Math.max.apply(null, vals), n = vals.length;
    function X(i) { return W * i / (n - 1); } function Y(v) { return 3 + (Hh - 6) * (1 - (v - lo) / ((hi - lo) || 1)); }
    var line = vals.map(function (v, i) { return X(i).toFixed(1) + ',' + Y(v).toFixed(1); }).join(' ');
    el.innerHTML = '<svg viewBox="0 0 ' + W + ' ' + Hh + '" preserveAspectRatio="none"><polygon points="0,' + Hh + ' ' + line + ' ' + W + ',' + Hh + '" fill="' + color + '" fill-opacity=".12"/><polyline points="' + line + '" fill="none" stroke="' + color + '" stroke-width="2" vector-effect="non-scaling-stroke" stroke-linejoin="round"/><circle cx="' + X(n - 1) + '" cy="' + Y(vals[n - 1]) + '" r="3" fill="' + color + '"/></svg>';
  }
  function renderSparks() { spark($('#sparkHealth'), hdata.steps.v, 'var(--fam-chart-1)'); spark($('#sparkOut'), d7.dist, 'var(--fam-chart-2)'); spark($('#sparkMood'), [70, 74, 52, 68, 72, 75, 72], 'var(--fam-chart-3)'); }

  /* ---------- 警報彈窗 ---------- */
  var alarms = {
    fall: { ic: 'i-fall', t: '客廳偵測到跌倒', d: '監視機看到阿嬤倒在地上超過 10 秒。', loc: false, acts: [['btn danger', 'i-video', '看即時畫面', 'go:fcall:monitor'], ['btn tonal', 'i-phone', '打電話給阿嬤', 'go:fcall:voice'], ['btn ghost', '', '確認沒事，標記已處理', 'close']] },
    sos: { ic: 'i-alert', t: '阿嬤按下緊急求救', d: '阿嬤在手機上按了求救按鈕。', loc: true, acts: [['btn danger', 'i-video', '緊急強制通話', 'go:fcall:video'], ['btn tonal', 'i-pin', '查看位置', 'go:map'], ['btn ghost', '', '標記已處理', 'close']] },
    sos_voice: { ic: 'i-mic', t: '阿嬤用語音求救', d: '她對小嘎說「我跌倒了，起不來」。這是語音求救，不是監視機偵測到的。', loc: true, acts: [['btn danger', 'i-phone', '馬上打給阿嬤', 'go:fcall:voice'], ['btn tonal', 'i-pin', '查看位置', 'go:map'], ['btn ghost', '', '標記已處理', 'close']] },
    sos_voice_noloc: { ic: 'i-mic', t: '阿嬤用語音求救', d: '她對小嘎說「我跌倒了，起不來」。這是語音求救，不是監視機偵測到的。', loc: false, acts: [['btn danger', 'i-phone', '馬上打給阿嬤', 'go:fcall:voice'], ['btn ghost', '', '標記已處理', 'close']] }
  };
  function showAlarm(k) {
    var a = alarms[k];
    if (currentView !== 'fmain') { history = []; go('fmain:' + currentTab); }
    closeAll();
    $('#alIcon').innerHTML = '<use href="#' + a.ic + '"/>';
    $('#alTitle').textContent = a.t; $('#alDesc').textContent = a.d; $('#alWhere').hidden = !a.loc;
    $('#alActs').innerHTML = a.acts.map(function (x) { return '<button class="' + x[0] + ' press" data-blob data-al="' + x[3] + '">' + (x[1] ? icon(x[1]) : '') + x[2] + '</button>'; }).join('');
    $('#alarm').classList.add('show');
  }
  $('#alarm').addEventListener('click', function (e) {
    var b = e.target.closest('[data-al]'); if (!b) return; e.stopPropagation();
    var a = b.dataset.al; $('#alarm').classList.remove('show');
    if (a === 'close') toast('已標記處理'); else go(a.slice(3));
  });

  /* ---------- 通話房 ---------- */
  var timerT = 0, timerS = 0;
  function startTimer() { stopTimer(); timerS = 0; tick(); timerT = setInterval(function () { timerS++; tick(); }, 1000); }
  function stopTimer() { clearInterval(timerT); timerT = 0; }
  function tick() { var m = Math.floor(timerS / 60), s = timerS % 60; $$('[data-timer]').forEach(function (e) { e.textContent = (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s; }); }
  var fcall = $('#fcall'), pip = $('#fpip');
  function setCall(state) {
    fcall.dataset.state = state;
    $$('[data-show]', fcall).forEach(function (n) { n.hidden = n.dataset.show.split(' ').indexOf(state) < 0; });
    $$('.ctl', fcall).forEach(function (c) { c.classList.remove('off'); c.disabled = false; });
    pip.classList.remove('camoff');
    var spk = $('[data-ctl="speaker"]', fcall), loud = state !== 'voice';
    spk.dataset.loud = loud ? '1' : '0'; spk.innerHTML = icon(loud ? 'i-vol' : 'i-ear');
    $('[data-ftype]', fcall).textContent = state === 'voice' ? '語音通話' : '視訊通話';
    if (state === 'voice' || state === 'video') startTimer(); else stopTimer();
    if (!pip.hidden) requestAnimationFrame(function () { snapPip(pip.dataset.corner || 'br', true); });
  }
  fcall.addEventListener('click', function (e) {
    var c = e.target.closest('[data-ctl]'); if (!c) return;
    var k = c.dataset.ctl;
    if (k === 'speaker') { var loud = c.dataset.loud !== '1'; c.dataset.loud = loud ? '1' : '0'; c.innerHTML = icon(loud ? 'i-vol' : 'i-ear'); toast(loud ? '擴音' : '聽筒'); return; }
    if (k === 'flip') { toast('已切換前後鏡頭'); return; }
    var off = c.classList.toggle('off');
    if (k === 'mic') toast(off ? '麥克風已關閉' : '麥克風已開啟');
    if (k === 'cam') { pip.classList.toggle('camoff', off); var fl = $('[data-ctl="flip"]', fcall); if (fl) fl.disabled = off; }
  });
  function SH() { return screen.clientHeight / SCALE; }
  function snapPip(corner, instant) {
    var m = 14, top = 104, bottom = 120;
    var x = corner[1] === 'l' ? m : 390 - pip.offsetWidth - m, y = corner[0] === 't' ? top : SH() - pip.offsetHeight - bottom;
    if (instant) pip.style.transition = 'none';
    pip.style.left = x + 'px'; pip.style.top = y + 'px'; pip.dataset.corner = corner;
    if (instant) { void pip.offsetWidth; pip.style.transition = ''; }
  }
  (function () {
    var d = null;
    pip.addEventListener('pointerdown', function (e) { d = { x: e.clientX, y: e.clientY, l: pip.offsetLeft, t: pip.offsetTop }; pip.classList.add('dragging'); pip.setPointerCapture(e.pointerId); });
    pip.addEventListener('pointermove', function (e) { if (!d) return; pip.style.left = (d.l + (e.clientX - d.x) / SCALE) + 'px'; pip.style.top = (d.t + (e.clientY - d.y) / SCALE) + 'px'; });
    pip.addEventListener('pointerup', function () { if (!d) return; d = null; pip.classList.remove('dragging'); var cx = pip.offsetLeft + pip.offsetWidth / 2, cy = pip.offsetTop + pip.offsetHeight / 2; snapPip((cy < SH() / 2 ? 't' : 'b') + (cx < 195 ? 'l' : 'r')); });
  })();
  pip.dataset.corner = 'br';

  /* ---------- 開場 ---------- */
  go('fmain:home');
  if (showcaseEmbed) window.parent.postMessage({ app: 'uban-prototype', type: 'ready', role: 'family' }, '*');
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { var b = $('.on', nav); if (b) navSpring.to(targetX(b), true); layoutSegs(); });
})();
