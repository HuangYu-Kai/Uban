/* Uban 體驗版外殼：兩個同源 iframe 各跑一份真正的 App（長輩端／家屬端）。 */
(function () {
  'use strict';

  var LS_MAIN = 'uban_demo.v1';
  var LS_SESS = 'uban_demo.session';
  var ROLES = ['elder', 'family'];
  var ROLE_NAME = { elder: '長輩端', family: '家屬端' };
  var BASE = location.origin + location.pathname.replace(/index\.html$/, '');

  /* ---------- 小工具 ---------- */
  function lget(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function lset(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* ignore */ } }
  function ldel(k) { try { localStorage.removeItem(k); } catch (e) { /* ignore */ } }
  function $(id) { return document.getElementById(id); }
  function h(tag, attrs) {
    var el = document.createElement(tag);
    if (attrs) {
      Object.keys(attrs).forEach(function (k) {
        var v = attrs[k];
        if (v == null || v === false) return;
        if (k === 'class') el.className = v;
        else if (k === 'text') el.textContent = v;
        else if (k.slice(0, 2) === 'on') el.addEventListener(k.slice(2), v);
        else el.setAttribute(k, v === true ? '' : v);
      });
    }
    for (var i = 2; i < arguments.length; i++) {
      var c = arguments[i];
      if (c == null || c === false) continue;
      if (Array.isArray(c)) { c.forEach(function (x) { if (x) el.appendChild(x); }); continue; }
      el.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    }
    return el;
  }
  function svg(html, size) {
    var s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    s.setAttribute('viewBox', '0 0 24 24'); s.setAttribute('width', size || 20); s.setAttribute('height', size || 20);
    s.setAttribute('aria-hidden', 'true'); s.innerHTML = html; // 僅限本檔內的常數字串
    return s;
  }
  var CHECK = '<path d="M5 12.5l4.5 4.5L19 7.5" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>';
  var CHEV = '<path d="M9 5l7 7-7 7" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>';

  /* ---------- 狀態 ---------- */
  var S = { introDone: false, seen: {}, tasks: {}, surveyPrompted: false };
  try { var raw = lget(LS_MAIN); if (raw) S = Object.assign(S, JSON.parse(raw)); } catch (e) { /* ignore */ }
  var firstVisit = lget(LS_MAIN) == null;
  function save() { lset(LS_MAIN, JSON.stringify(S)); }

  var session = null;          // 後端 session
  var sessionPromise = null;
  var sessionError = null;
  var notice = '';
  var bootHash = location.hash;    // 開啟時的網址片段（之後會從網址列清掉）
  var joinMode = false;        // 由另一支手機的連結開啟
  var onlyRole = null;         // join 模式下預設只顯示的端
  var switchVisible = true;
  var active = 'elder';
  var started = false;
  var elderRemote = !!S.elderRemote;
  var badges = { elder: false, family: false };
  var callState = { elder: { active: false, emergency: false }, family: { active: false, emergency: false } };
  var pipOn = false, lastCaller = null, callOrigin = null, muteTimer = null;
  var frames = { elder: null, family: null };
  var lowMem = typeof navigator.deviceMemory === 'number' && navigator.deviceMemory <= 2;

  /* ---------- 後端 ---------- */
  function httpError(status, j) {
    var m = j && (typeof j.error === 'string' ? j.error : (typeof j.detail === 'string' ? j.detail : ''));
    if (m) return m;
    if (status === 429) return '目前嘗試的人太多了，請稍後再試。';
    if (status === 503) return '體驗服務暫時忙碌中，請稍後再試。';
    return '無法連線到體驗服務（' + status + '），請稍後再試。';
  }
  function api(method, path) {
    return fetch(path, { method: method, headers: { 'Accept': 'application/json' }, cache: 'no-store' }).then(function (r) {
      return r.json().catch(function () { return null; }).then(function (j) {
        if (!r.ok || !j || j.status === 'error') {
          var e = new Error(httpError(r.status, j)); e.status = r.status; throw e;
        }
        var d = j.data;
        if (!d || !d.token) { var e2 = new Error('體驗服務回傳的資料不完整，請重試。'); e2.status = 0; throw e2; }
        return d;
      });
    }, function () {
      var e = new Error('網路不穩，連不上體驗服務。請確認網路後重試。'); e.status = 0; throw e;
    });
  }
  function createSession() { return api('POST', '../api/demo/session'); }
  function getSession(t) { return api('GET', '../api/demo/session/' + encodeURIComponent(t)); }

  function adopt(d) {
    session = d; sessionError = null;
    lset(LS_SESS, JSON.stringify(d));
    ROLES.forEach(function (r) {
      lset('demo_' + r + '.demo_session', JSON.stringify(JSON.stringify(d)));
    });
    return d;
  }
  function clearSessionKeys() {
    try {
      var del = [];
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (k && (k.indexOf('uban_demo.') === 0 || k.indexOf('demo_elder.') === 0 || k.indexOf('demo_family.') === 0)) del.push(k);
      }
      del.forEach(ldel);
    } catch (e) { /* ignore */ }
  }
  function ensureSession(fresh) {
    sessionError = null;
    sessionPromise = (function () {
      var saved = null;
      try { saved = JSON.parse(lget(LS_SESS) || 'null'); } catch (e) { /* ignore */ }
      if (!fresh && saved && saved.token) {
        return getSession(saved.token).then(adopt, function (e) {
          if (e.status === 404) {
            ldel(LS_SESS);
            S.tasks = {}; S.surveyPrompted = false; S.only = ''; setElderRemote(false); renderTaskCount();
            notice = '先前的體驗已過期，已為您換上全新的體驗。';
            return createSession().then(adopt);
          }
          if (e.status === 0) return adopt(saved); // 暫時連不上：先沿用本機的
          throw e;
        });
      }
      return createSession().then(adopt);
    })();
    sessionPromise.catch(function (e) { sessionError = e.message || '發生未知錯誤'; renderIntro(); });
    return sessionPromise;
  }

  /* ---------- Bottom sheet ---------- */
  var sheetOpen = false, sheetReturn = null, sheetOnClose = null;
  function openSheet(title, bodyNodes, onClose) {
    sheetReturn = document.activeElement; sheetOnClose = onClose || null;
    $('sheet-title').textContent = title;
    var b = $('sheet-body'); b.textContent = '';
    [].concat(bodyNodes).forEach(function (n) { if (n) b.appendChild(n); });
    $('sheet-wrap').hidden = false; sheetOpen = true;
    $('app').querySelectorAll('.topbar, .stage').forEach(function (e) { e.inert = true; });
    setTimeout(function () { $('sheet').focus(); b.scrollTop = 0; }, 30);
  }
  function closeSheet() {
    if (!sheetOpen) return;
    sheetOpen = false; $('sheet-wrap').hidden = true;
    $('app').querySelectorAll('.topbar, .stage').forEach(function (e) { e.inert = false; });
    applyLayout();
    var cb = sheetOnClose; sheetOnClose = null;
    if (sheetReturn && sheetReturn.focus) { try { sheetReturn.focus(); } catch (e) { /* ignore */ } }
    if (cb) cb();
  }
  $('sheet-close').addEventListener('click', closeSheet);
  $('sheet-backdrop').addEventListener('click', closeSheet);
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && sheetOpen) closeSheet(); });

  /* ---------- Toast 與說明字幕 ---------- */
  var toastTimer = null;
  function toast(text, actionLabel, action) {
    var t = $('toast'); t.textContent = '';
    t.appendChild(h('span', { text: text }));
    if (actionLabel) t.appendChild(h('button', { type: 'button', text: actionLabel, onclick: function () { hideToast(); action(); } }));
    t.appendChild(h('button', { type: 'button', class: 'x', 'aria-label': '關閉提示', text: '×', onclick: hideToast }));
    t.hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(hideToast, 4000);
  }
  function hideToast() { $('toast').hidden = true; clearTimeout(toastTimer); }
  var captionTimer = null;
  function caption(main, small, calm) {
    var c = $('caption'); c.textContent = ''; c.className = 'caption' + (calm ? ' calm' : '');
    c.appendChild(h('p', null, main, small ? h('small', { text: small }) : null));
    c.appendChild(h('button', { type: 'button', 'aria-label': '關閉說明', text: '×', onclick: function () { c.hidden = true; } }));
    c.hidden = false;
    clearTimeout(captionTimer); captionTimer = setTimeout(function () { c.hidden = true; }, 12000);
  }

  /* ---------- iframe 與載入面板 ---------- */
  var panels = {};
  function setElderRemote(v) { elderRemote = v; S.elderRemote = v; save(); }
  function frameState(role) { return frames[role] ? frames[role].state : 'idle'; }
  function loadFrame(role) {
    var f = frames[role];
    if (!f) {
      var el = h('iframe', {
        class: 'frame', title: ROLE_NAME[role] + '（' + (role === 'elder' ? '長輩手機畫面' : '家屬手機畫面') + '）',
        allow: 'microphone; camera; geolocation; autoplay; clipboard-write; fullscreen; display-capture; screen-wake-lock'
      });
      $('stage').appendChild(el);
      f = frames[role] = { el: el, state: 'idle', t0: 0, timer: null };
    }
    if (role === 'elder' && elderRemote) return;
    clearTimeout(f.timer);
    f.state = 'loading'; f.t0 = Date.now();
    f.el.src = 'app/index.html?role=' + role;
    f.timer = setTimeout(function () { if (f.state !== 'home') { f.state = 'timeout'; renderPanels(); } }, 45000);
    applyLayout();
  }
  function reloadFrame(role) {
    var f = frames[role]; if (!f) return;
    f.el.src = 'about:blank';
    setTimeout(function () { loadFrame(role); }, 50);
  }
  function renderPanels() {
    ROLES.forEach(function (role) {
      var p = panels[role];
      if (!p) { p = panels[role] = h('div', { class: 'panel ' + role, role: 'status' }); $('stage').appendChild(p); }
      var f = frames[role], show = role === active && !(pipOn);
      var st = f ? f.state : 'idle';
      if (role === 'elder' && elderRemote) {
        p.textContent = '';
        p.appendChild(h('h3', { text: '長輩端正在另一支手機上' }));
        p.appendChild(h('p', { text: '王奶奶的畫面現在顯示在另一支手機。在這支手機上操作家屬端，兩邊會即時互通。' }));
        p.appendChild(h('button', { type: 'button', class: 'btn primary', text: '收回到這支手機', onclick: function () { setElderRemote(false); loadFrame('elder'); renderPanels(); } }));
        p.dataset.kind = 'remote'; p.hidden = !show; return;
      }
      if (st === 'home' || !show) { p.hidden = true; p.dataset.kind = ''; return; }
      var secs = f && f.t0 ? Math.round((Date.now() - f.t0) / 1000) : 0;
      var kind = st === 'timeout' ? 'timeout' : 'loading';
      if (p.dataset.kind !== kind) {
        p.textContent = '';
        if (kind === 'timeout') {
          p.appendChild(h('h3', { text: '好像比較久了' }));
          p.appendChild(h('p', { text: '可能是網路較慢。您可以重新載入，或再等一下。' }));
          p.appendChild(h('button', { type: 'button', class: 'btn ' + (role === 'elder' ? 'primary' : 'family'), text: '重新載入', onclick: function () { p.dataset.kind = ''; reloadFrame(role); } }));
        } else {
          p.appendChild(h('div', { class: 'spinner', 'aria-hidden': 'true' }));
          p.appendChild(h('h3', { text: '正在準備' + (role === 'elder' ? '王奶奶' : '王小明') + '的手機' }));
          p.appendChild(h('p', { text: '第一次載入約需 10～15 秒' }));
          p.appendChild(h('p', { class: 'secs' }));
        }
        p.dataset.kind = kind;
      }
      var s = p.querySelector('.secs'); if (s) s.textContent = '已等待 ' + secs + ' 秒';
      p.hidden = false;
    });
  }
  setInterval(function () { if (started) renderPanels(); }, 1000);

  /* ---------- 版面（顯示哪一端／子母畫面） ---------- */
  var pipHit = null, pipTag = null;
  function applyLayout() {
    ROLES.forEach(function (role) {
      var f = frames[role]; if (!f) return;
      var isMain = role === active, isPip = pipOn && !isMain;
      f.el.classList.toggle('on', isMain);
      f.el.classList.toggle('pip', isPip);
      var hidden = !isMain;
      f.el.inert = hidden || sheetOpen; f.el.setAttribute('aria-hidden', hidden ? 'true' : 'false');
    });
    if (pipOn) {
      if (!pipHit) {
        pipHit = h('button', { type: 'button', class: 'pip-hit', onclick: function () { setActive(active === 'elder' ? 'family' : 'elder', { silent: true }); } });
        pipTag = h('span', { class: 'pip-tag' });
        $('stage').appendChild(pipHit); $('stage').appendChild(pipTag);
      }
      var other = active === 'elder' ? 'family' : 'elder';
      pipHit.setAttribute('aria-label', '切換到' + ROLE_NAME[other] + '（目前縮小顯示）');
      pipTag.textContent = ROLE_NAME[other]; pipHit.hidden = pipTag.hidden = false;
    } else if (pipHit) { pipHit.hidden = pipTag.hidden = true; }
    ROLES.forEach(function (role) {
      var b = $('tab-' + role);
      b.setAttribute('aria-selected', role === active ? 'true' : 'false');
      b.tabIndex = role === active ? 0 : -1;
      b.querySelector('.dot').hidden = !(badges[role] && role !== active);
      b.setAttribute('aria-label', ROLE_NAME[role] + (badges[role] && role !== active ? '，有新動態' : ''));
    });
    $('seg').hidden = !switchVisible;
  }

  function setActive(role, opts) {
    opts = opts || {};
    if (!switchVisible && !opts.force && role !== active) return;
    active = role; badges[role] = false;
    if (!frames[role] || frames[role].state === 'idle') loadFrame(role);
    applyLayout(); renderPanels();
    if (!opts.silent && started && !S.seen[role]) openRoleSheet(role);
  }
  ROLES.forEach(function (role) {
    $('tab-' + role).addEventListener('click', function () { setActive(role); });
  });
  $('seg').addEventListener('keydown', function (e) {
    if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
      var n = active === 'elder' ? 'family' : 'elder'; setActive(n); $('tab-' + n).focus();
    }
  });

  /* ---------- 來自 App 的訊息 ---------- */
  var BADGE_TOAST = {
    family: {
      'elder-question': '奶奶的提問', 'elder-checkin': '奶奶完成了打卡', 'daily-answer': '奶奶的每日一問回答',
      'pet-gift-fed': '奶奶餵了小豬點心', 'agent-task-done': '小嘎的交辦結果'
    },
    elder: {
      'elder-question-answered': '家人的回覆', 'checkin-cheer': '家人的鼓勵', 'pet-gift': '家人送的點心',
      'heartbeat-message': '小嘎的關心', 'daily-question-new': '家人的每日一問', 'family-share-new': '家人的分享'
    }
  };
  var TASKS = [
    { id: 1, role: 'elder', text: '請小嘎傳話給家人', how: '到「聊天」分頁，對小嘎說或打字：「幫我問兒子週六要不要回來」。', ev: ['family', 'elder-question'] },
    { id: 2, role: 'family', text: '回覆長輩的問題', how: '在「首頁」最上面的「爸媽問你的問題」按「回覆」，輸入答案後按「送出」。', ev: ['elder', 'elder-question-answered'] },
    { id: 3, role: 'elder', text: '完成一項提醒打卡', how: '到「我的」分頁的「今日任務」，在任一項按「打卡」。', ev: ['family', 'elder-checkin'] },
    { id: 4, role: 'family', text: '送出鼓勵或點心', how: '在「首頁」的「今日打卡」按「鼓勵」，或到「互動」分頁按「送點心給小豬」。', ev: ['elder', 'checkin-cheer', 'pet-gift'] },
    { id: 5, role: 'family', text: '查看今天的位置與行程', how: '在「首頁」往下捲，點開顯示「今天外出…」或「今天移動…」的位置卡片，看地圖與行程。看過後請自行勾選。', manual: true },
    { id: 6, role: 'family', text: '撥打緊急通話', how: '到「互動」分頁按「視訊通話」，選「緊急強制通話」。', ev: ['elder', 'emergency-call'] }
  ];
  function doneCount() { return TASKS.filter(function (t) { return S.tasks[t.id]; }).length; }
  function renderTaskCount() {
    var n = doneCount(); $('task-count').textContent = n + '/6';
    $('btn-tasks').classList.toggle('done', n === 6);
  }
  function markTask(id, val) {
    if (!!S.tasks[id] === val) return;
    S.tasks[id] = val; save(); renderTaskCount();
    if (val && doneCount() >= 4 && !S.surveyPrompted && session && session.survey_url) {
      S.surveyPrompted = true; save();
      setTimeout(function () { toast('做得很好！有空的話歡迎填問卷。', '填問卷', openSurvey); }, 1200);
    }
    if (val) {
      var t = TASKS.filter(function (x) { return x.id === id; })[0];
      if (t && !sheetOpen) toast('完成任務：' + t.text);
    }
  }

  function onEvent(role, name) {
    TASKS.forEach(function (t) { if (t.ev && t.ev[0] === role && t.ev.indexOf(name, 1) > 0) markTask(t.id, true); });
    var label = BADGE_TOAST[role] && BADGE_TOAST[role][name];
    if (label && role !== active) {
      badges[role] = true; applyLayout();
      toast(ROLE_NAME[role] + '收到：' + label, '去看看', function () { setActive(role, { silent: true }); });
    }
    if (name === 'call-request') {
      lastCaller = role === 'elder' ? 'family' : 'elder';
      if (role !== active) {
        badges[role] = true; applyLayout();
        toast(ROLE_NAME[role] + '有來電', '去接聽', function () { setActive(role, { silent: true }); });
      }
    }
    if (name === 'emergency-call' && role === 'elder') {
      lastCaller = 'family'; callState.elder.emergency = true;
      setTimeout(function () {
        if (active !== 'elder') setActive('elder', { silent: true, force: true });
        caption('緊急通話：長輩的手機已自動接通，不需要按接聽。', '真實手機上會自動亮起螢幕、打開 App 並把音量調到最大。');
      }, 1000);
    }
  }
  function onCall(role, d) {
    callState[role] = { active: !!d.active, emergency: !!d.emergency };
    var both = callState.elder.active && callState.family.active;
    if (both && !pipOn) {
      pipOn = true; callOrigin = lastCaller || active;
      applyLayout(); renderPanels();
      if ($('caption').hidden) caption('兩端都在通話中，另一端縮小在左下角，點它可切換。', '同一支手機示範時聲音會關閉，以免回音。', true);
      else { var sm = $('caption').querySelector('small'); if (sm) sm.textContent += ' 同一支手機示範時聲音會關閉，以免回音。'; }
      clearInterval(muteTimer); muteTimer = setInterval(muteAll, 500); muteAll();
    } else if (!both && pipOn) {
      pipOn = false; clearInterval(muteTimer);
      $('caption').hidden = true;
      var o = callOrigin; callOrigin = null;
      applyLayout(); renderPanels();
      if (o && o !== active) setActive(o, { silent: true, force: true });
    }
    if (!callState.elder.active && !callState.family.active) { lastCaller = null; if (!pipOn) callState.elder.emergency = false; }
  }
  function muteAll() {
    ROLES.forEach(function (r) {
      try {
        var f = frames[r]; if (!f || !f.el.contentDocument) return;
        f.el.contentDocument.querySelectorAll('audio,video').forEach(function (m) { m.muted = true; m.volume = 0; });
      } catch (e) { /* ignore */ }
    });
  }
  function onHome(role) {
    var f = frames[role]; if (!f) return;
    clearTimeout(f.timer); f.state = 'home'; renderPanels();
    if (role === active && !lowMem && switchVisible) {
      var other = role === 'elder' ? 'family' : 'elder';
      setTimeout(function () { if (!frames[other] && !(other === 'elder' && elderRemote)) loadFrame(other); }, 1500);
    }
  }
  window.addEventListener('message', function (e) {
    if (e.origin !== location.origin) return;
    var d = e.data; if (!d || d.src !== 'uban-demo' || ROLES.indexOf(d.role) < 0) return;
    var f = frames[d.role]; if (!f || e.source !== f.el.contentWindow) return;
    try {
      if (d.type === 'ready') { if (f.state === 'loading') f.state = 'ready'; }
      else if (d.type === 'home') onHome(d.role);
      else if (d.type === 'event' && typeof d.name === 'string') onEvent(d.role, d.name);
      else if (d.type === 'call') onCall(d.role, d);
    } catch (err) { /* ignore */ }
  });

  /* ---------- 各種面板 ---------- */
  function openSurvey() { if (session && session.survey_url) window.open(session.survey_url, '_blank', 'noopener'); }

  function openRoleSheet(role) {
    S.seen[role] = true; save();
    var el = role === 'elder';
    var tabs = el ? ['首頁', '電話', '小豬', '聊天', '我的'] : ['首頁', '互動', '資料'];
    var nodes = [
      h('p', { class: 'lead', text: el
        ? '這是王奶奶（78 歲，一個人住）的手機。她用它看新聞、跟 AI 夥伴「小嘎」聊天、照時間吃藥，也能打電話給家人。'
        : '這是兒子王小明的手機。他用它看奶奶今天的狀況、回覆奶奶的問題、送上鼓勵，緊急時直接撥打緊急通話。' }),
      h('h3', { text: '最下面的 ' + tabs.length + ' 個分頁' }),
      h('div', { class: 'chips' }, tabs.map(function (t) { return h('span', { class: 'chip', text: t }); })),
      h('h3', { text: '可以這樣試試看' })
    ];
    var says = el
      ? ['「幫我問兒子週六要不要回來」', '「今天天氣怎麼樣」', '到「我的」完成一項「今日任務」打卡']
      : ['在「首頁」回覆「爸媽問你的問題」', '在「今日打卡」按「鼓勵」', '到「互動」試試「緊急強制通話」'];
    says.forEach(function (s) { nodes.push(h('div', { class: 'say' + (el ? '' : ' family'), text: s })); });
    nodes.push(h('p', { text: el ? '說話時請按畫面上的麥克風鈕，或直接打字。' : '兩端是同時在跑的，奶奶做的事這裡馬上看得到。' }));
    nodes.push(h('button', { type: 'button', class: 'btn block ' + (el ? 'primary' : 'family'), text: '開始體驗' + ROLE_NAME[role], onclick: closeSheet }));
    openSheet(el ? '長輩端：王奶奶的手機' : '家屬端：王小明的手機', nodes);
  }

  function openTasks() {
    var n = doneCount();
    var list = h('ul', { class: 'list' });
    TASKS.forEach(function (t) {
      var done = !!S.tasks[t.id];
      var act = h('div', { class: 'task-act' });
      act.appendChild(h('button', { type: 'button', class: 'btn ghost', text: '帶我去', onclick: function () {
        closeSheet();
        if (t.role === 'elder' && elderRemote) toast('長輩端在另一支手機上，請到那支手機操作。');
        else if (!switchVisible && t.role !== onlyRole) toast('請先在選單開啟「顯示兩端切換」。');
        else setActive(t.role, { force: true });
      } }));
      act.appendChild(h('button', { type: 'button', class: 'btn ghost', 'aria-pressed': done ? 'true' : 'false', text: done ? '取消完成' : '我完成了', onclick: function () { markTask(t.id, !done); openTasks(); } }));
      list.appendChild(h('li', null, h('div', { class: 'task' + (done ? ' done' : '') },
        h('span', { class: 'task-mark', 'aria-hidden': 'true' }, done ? svg(CHECK, 16) : null),
        h('div', { class: 'task-text' }, h('span', { class: 'task-role ' + t.role, text: ROLE_NAME[t.role] }), t.text, done ? h('span', { class: 'sr', text: '（已完成）' }) : null),
        h('div', { class: 'task-how', text: t.how }), act)));
    });
    var nodes = [
      h('p', { class: 'lead', text: '做完 6 件事，就把兩端的主要功能都玩過一遍。完成會自動打勾，也可以自己勾選。' }),
      h('div', { class: 'progress', role: 'progressbar', 'aria-valuemin': 0, 'aria-valuemax': 6, 'aria-valuenow': n, 'aria-label': '任務進度' }, h('i', { style: 'width:' + (n / 6 * 100) + '%' })),
      list
    ];
    if (n >= 4 && session && session.survey_url) {
      nodes.push(h('div', { class: 'note' }, '已經完成 ' + n + ' 項，非常感謝！方便的話請花一分鐘填寫問卷。'));
      nodes.push(h('button', { type: 'button', class: 'btn primary block', text: '填問卷', onclick: openSurvey }));
    }
    openSheet('體驗任務（' + n + '/6）', nodes);
  }

  function openMenu() {
    var items = [
      ['正常使用流程與綁定流程說明', '重新看一次開頭的說明', function () { closeSheet(); showIntro(true); }],
      ['這一端怎麼用', '目前：' + ROLE_NAME[active], function () { closeSheet(); setTimeout(function () { openRoleSheet(active); }, 50); }],
      ['兩支手機一起體驗', '用另一支手機當王奶奶的手機', function () { closeSheet(); setTimeout(openTwoPhone, 50); }]
    ];
    if (!switchVisible) items.push(['顯示兩端切換', '這支手機也能操作另一端', function () { switchVisible = true; onlyRole = null; S.only = ''; save(); closeSheet(); applyLayout(); onHome(active); }]);
    if (session && session.survey_url) items.push(['填寫問卷', '會在新分頁開啟', function () { closeSheet(); openSurvey(); }]);
    items.push(['重新載入', '畫面卡住時使用', function () { closeSheet(); ROLES.forEach(function (r) { if (frames[r] && frames[r].state !== 'idle') reloadFrame(r); }); }]);
    items.push(['重新開始體驗', '清除這支手機上的體驗資料', function () { openRestart(); }]);
    openSheet('選單', h('ul', { class: 'list' }, items.map(function (it) {
      return h('li', null, h('button', { type: 'button', class: 'menu-item', onclick: it[2] },
        h('span', null, it[0], h('small', { text: it[1] })), svg(CHEV, 18)));
    })));
  }

  function openRestart() {
    openSheet('重新開始體驗？', [
      h('p', { class: 'lead', text: '會清除這支手機上的體驗資料（任務進度、兩端的帳號與對話），並重新配一組新的王奶奶與王小明。' }),
      h('div', { class: 'row' },
        h('button', { type: 'button', class: 'btn ghost', text: '取消', onclick: closeSheet }),
        h('button', { type: 'button', class: 'btn danger', text: '清除並重新開始', onclick: function () { clearSessionKeys(); location.replace(BASE); } }))
    ]);
  }

  function qrSvg(text) {
    var q = qrcode(0, 'M'); q.addData(text); q.make();
    var n = q.getModuleCount(), m = 2, d = '';
    for (var r = 0; r < n; r++) for (var c = 0; c < n; c++) if (q.isDark(r, c)) d += 'M' + (c + m) + ' ' + (r + m) + 'h1v1h-1z';
    var s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    s.setAttribute('viewBox', '0 0 ' + (n + m * 2) + ' ' + (n + m * 2)); s.setAttribute('role', 'img'); s.setAttribute('aria-label', '連結的 QR Code');
    s.setAttribute('shape-rendering', 'crispEdges');
    s.innerHTML = '<rect width="100%" height="100%" fill="#fff"/><path fill="#16201C" d="' + d + '"/>';
    return s;
  }
  function openTwoPhone() {
    if (!session) { toast('體驗還在準備中，請稍後再試。'); return; }
    var url = BASE + '#join=' + encodeURIComponent(session.token) + '&role=elder';
    var nodes = [
      h('p', { class: 'lead', text: '用另一支手機掃描，它就是王奶奶的手機。' }),
      h('div', { class: 'qr' }, qrSvg(url)),
      h('div', { class: 'link-box', text: url }),
      h('div', { class: 'row' },
        h('button', { type: 'button', class: 'btn ghost', text: '複製連結', onclick: function (ev) {
          var b = ev.currentTarget;
          var ok = function () { b.textContent = '已複製'; };
          if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(url).then(ok, function () { toast('無法複製，請長按上方連結手動複製。'); });
          else toast('請長按上方連結手動複製。');
        } }),
        navigator.share ? h('button', { type: 'button', class: 'btn ghost', text: '分享連結', onclick: function () { navigator.share({ title: 'Uban 體驗版', text: '用這個連結開啟，就是王奶奶的手機', url: url }).catch(function () {}); } }) : null),
      h('p', { text: '另一支手機打開後，這支手機的長輩端會收起來，只留下家屬端。連結只有這次體驗有效，請勿轉貼到公開的地方。' }),
      h('button', { type: 'button', class: 'btn primary block', text: '已經用另一支手機開啟', onclick: function () {
        closeSheet(); setElderRemote(true);
        if (frames.elder) { frames.elder.state = 'idle'; frames.elder.el.src = 'about:blank'; }
        callState.elder = { active: false, emergency: false };
        setActive('family', { silent: true, force: true }); renderPanels();
        toast('長輩端已移到另一支手機。');
      } })
    ];
    openSheet('兩支手機一起體驗', nodes);
  }

  $('btn-tasks').addEventListener('click', openTasks);
  $('btn-menu').addEventListener('click', openMenu);

  /* ---------- 開頭說明 ---------- */
  var introSteps = [], introIdx = 0, introReplay = false;
  function inAppBrowser() {
    var ua = navigator.userAgent || '';
    if (/\bLine\//i.test(ua)) return 'line';
    if (/FBAN|FBAV|FB_IAB|Instagram|MicroMessenger/i.test(ua)) return 'other';
    return '';
  }
  function ttlText() {
    var days = 3;
    if (session && session.expires_at) {
      var ms = Date.parse(session.expires_at) - Date.now();
      if (ms > 0) days = Math.max(1, Math.round(ms / 86400000));
    }
    return days + ' 天';
  }
  function phoneIllus() {
    var qrMini = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    qrMini.setAttribute('viewBox', '0 0 9 9'); qrMini.setAttribute('class', 'qrmini'); qrMini.setAttribute('aria-hidden', 'true');
    qrMini.innerHTML = '<path fill="#16201C" d="M0 0h3v3H0zM6 0h3v3H6zM0 6h3v3H0zM4 1h1v1H4zM4 4h2v1H4zM7 4h1v2H7zM4 7h1v2H4zM6 7h3v1H6z"/><path fill="#fff" d="M1 1h1v1H1zM7 1h1v1H7zM1 7h1v1H1z"/>';
    var arrow = svg('<path d="M4 12h14M13 6l6 6-6 6" fill="none" stroke="#546660" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>', 28);
    return h('div', { class: 'phones', role: 'img', 'aria-label': '示意圖：長輩手機顯示配對碼與 QR Code，家屬手機掃描或輸入後填長輩稱呼' },
      h('div', { class: 'ph' }, h('span', { class: 'cap', text: '長輩的手機' }), h('span', { class: 'codebox', text: '4 位數' }), qrMini, h('span', { class: 'cap', text: '10 分鐘內有效' })),
      arrow,
      h('div', { class: 'ph fam' }, h('span', { class: 'cap', text: '家屬的手機' }), h('span', { class: 'codebox', text: '掃描或輸入' }), h('span', { text: '填長輩稱呼' }), h('span', { class: 'cap', text: '綁定成功' })));
  }
  var STEP = {
    what: function () {
      return {
        title: '這是什麼', body: [
          h('div', { class: 'brand' }, h('img', { src: './icon.png', alt: '', width: 56, height: 56 }), h('div', null, h('div', { style: 'font-weight:800;font-size:20px', text: 'Uban' }), h('div', { class: 'sub', text: '問卷體驗版' }))),
          h('h1', { text: '讓長輩有人陪、家人放心' }),
          h('p', { text: '這是問卷用的體驗版，約需 5 分鐘。' }),
          h('p', { class: 'sub', text: joinMode
            ? '這支手機是' + (onlyRole === 'family' ? '兒子王小明的「家屬端」' : '王奶奶的「長輩端」') + '，會和另一支手機即時互通。'
            : '畫面上方可以切換「長輩端」和「家屬端」，兩邊是同時運作的真實 App。' })
        ]
      };
    },
    scene: function () {
      return {
        title: '使用情境', body: [
          h('h1', { text: '王奶奶與王小明' }),
          h('p', { text: '78 歲的王奶奶一個人住在臺北，兒子王小明在外地工作。' }),
          h('div', { class: 'card' }, h('h3', { text: '平常' }), h('p', { text: '奶奶跟 AI 夥伴「小嘎」聊天、聽新聞、照時間吃藥；小明用手機看奶奶今天的狀況、回覆奶奶的問題、送上鼓勵。' })),
          h('div', { class: 'card' }, h('h3', { text: '緊急時' }), h('p', { text: '奶奶跌倒或聯絡不上，小明按「緊急通話」，奶奶的手機會自動接通。' }))
        ]
      };
    },
    flow: function () {
      var li = function (a, b) { return h('li', null, a, b ? h('small', { text: b }) : null); };
      return {
        title: '正常的使用流程', body: [
          h('h1', { text: '真實使用時的 6 個步驟' }),
          h('ol', { class: 'timeline' },
            li('長輩與家屬各自在自己的手機安裝 Uban'),
            li('打開後選擇身分', '「我是長者」或「我是家屬／照護者」'),
            li('家屬註冊並登入帳號'),
            li('兩支手機完成綁定', '下一頁會說明怎麼綁'),
            li('填寫基本資料', '並允許通知、麥克風、相機、定位'),
            li('開始使用'))
        ]
      };
    },
    pair: function () {
      return {
        title: '正常的綁定流程', body: [
          h('h1', { text: '兩支手機怎麼綁在一起' }),
          phoneIllus(),
          h('ol', { class: 'timeline' },
            h('li', null, '長輩手機顯示 4 位數配對碼與 QR Code', h('small', { text: '10 分鐘內有效，過期會自動換新的' })),
            h('li', null, '家屬手機掃描 QR Code，或手動輸入 4 位數'),
            h('li', null, '填上長輩的稱呼，按「開始配對」'),
            h('li', null, '綁定成功，之後自動登入')),
          h('div', { class: 'note' }, h('b', { text: '體驗版已幫您綁好，不用登入。' }))
        ]
      };
    },
    start: function () {
      var body = [h('h1', { text: '開始前先說明' })];
      var iab = inAppBrowser();
      if (iab) {
        var link = BASE + '?openExternalBrowser=1' + bootHash;
        body.push(h('div', { class: 'big-note', role: 'alert' },
          '您目前在 App 內建的瀏覽器開啟，麥克風、相機可能無法使用。建議改用 Chrome 或 Safari 開啟。 ',
          iab === 'line' ? h('a', { href: link, text: '用預設瀏覽器開啟' }) : h('span', { text: '請從右上角選單選「用瀏覽器開啟」。' })));
      }
      body.push(h('div', { class: 'card' },
        h('p', null, '體驗資料只給這支手機使用，', h('b', { text: ttlText() + '後自動刪除' }), '。'),
        h('p', null, h('b', { text: '請勿輸入真實個資' }), '（姓名、電話、住址都請用假的）。'),
        h('p', { text: '過程中會詢問麥克風、相機、定位；拒絕也能繼續體驗。'}),
        h('p', { text: '建議使用 Chrome 或 Safari。' })));
      return { title: '開始前', body: body, last: true };
    }
  };
  function showIntro(replay) {
    introReplay = !!replay;
    introSteps = ['what', 'scene', 'flow', 'pair', 'start'];
    introIdx = 0; $('intro').hidden = false;
    $('app').querySelectorAll('.topbar, .stage').forEach(function (e) { e.inert = true; });
    renderIntro();
  }
  function closeIntro() {
    $('intro').hidden = true;
    $('app').querySelectorAll('.topbar, .stage').forEach(function (e) { e.inert = false; });
    applyLayout();
  }
  function renderIntro() {
    var root = $('intro'); if (root.hidden) return;
    var key = introSteps[introIdx], step = STEP[key](), last = introIdx === introSteps.length - 1;
    root.textContent = '';
    var dots = h('div', { class: 'dots', role: 'img', 'aria-label': '第 ' + (introIdx + 1) + ' 步，共 ' + introSteps.length + ' 步' });
    introSteps.forEach(function (_, i) { dots.appendChild(h('i', { class: i === introIdx ? 'on' : '' })); });
    var top = h('div', { class: 'intro-top' }, dots,
      !last ? h('button', { type: 'button', class: 'link', text: '略過說明', onclick: function () { introIdx = introSteps.length - 1; renderIntro(); } }) : (introReplay ? h('button', { type: 'button', class: 'link', text: '關閉', onclick: closeIntro }) : null));
    var body = h('div', { class: 'intro-body', tabindex: -1 });
    step.body.forEach(function (n) { body.appendChild(n); });
    var foot = h('div', { class: 'intro-foot' });
    if (last) {
      var ready = !!session;
      if (!introReplay) {
        if (sessionError) {
          foot.appendChild(h('div', { class: 'note err', role: 'alert', text: sessionError }));
          foot.appendChild(h('button', { type: 'button', class: 'btn ghost block', text: '重試', onclick: function () { ensureSession(true).then(renderIntro); renderIntro(); } }));
        } else if (!ready) foot.appendChild(h('p', { class: 'sub', role: 'status', text: '正在為您準備體驗…' }));
        else if (notice) foot.appendChild(h('div', { class: 'note', text: notice }));
        var go = function (r) { return function () { startExperience(r); }; };
        if (joinMode) foot.appendChild(h('button', { type: 'button', class: 'btn primary block', disabled: !ready, text: ready ? '開始體驗' + ROLE_NAME[onlyRole] : '準備中…', onclick: go(onlyRole) }));
        else {
          foot.appendChild(h('button', { type: 'button', class: 'btn primary block', disabled: !ready, text: ready ? '從長輩端開始' : '準備中…', onclick: go('elder') }));
          foot.appendChild(h('button', { type: 'button', class: 'btn family block', disabled: !ready, text: ready ? '從家屬端開始' : '準備中…', onclick: go('family') }));
        }
      } else foot.appendChild(h('button', { type: 'button', class: 'btn primary block', text: '回到體驗', onclick: closeIntro }));
      if (introIdx > 0) foot.appendChild(h('button', { type: 'button', class: 'link', text: '上一步', onclick: function () { introIdx--; renderIntro(); } }));
    } else {
      foot.appendChild(h('div', { class: 'nav' },
        introIdx > 0 ? h('button', { type: 'button', class: 'btn ghost', text: '上一步', onclick: function () { introIdx--; renderIntro(); } }) : null,
        h('button', { type: 'button', class: 'btn primary', text: '下一步', onclick: function () { introIdx++; renderIntro(); } })));
    }
    root.appendChild(top); root.appendChild(body); root.appendChild(foot);
    body.focus({ preventScroll: true });
  }

  /* ---------- 啟動 ---------- */
  function startExperience(role) {
    S.introDone = true; save();
    closeIntro();
    if (started) return;
    started = true;
    if (joinMode) { switchVisible = false; onlyRole = role; S.only = role; S.elderRemote = elderRemote = false; save(); }
    else if (S.only === role) { switchVisible = false; onlyRole = role; } // 加入的第二支手機：重新整理後維持同一端
    $('btn-menu').hidden = false;
    renderTaskCount();
    active = role; loadFrame(role); applyLayout(); renderPanels();
    if (notice && !joinMode) toast(notice);
    if (!S.seen[role]) setTimeout(function () { openRoleSheet(role); }, 400);
  }

  function boot() {
    renderTaskCount();
    var hp = new URLSearchParams(location.hash.replace(/^#/, ''));
    var jt = hp.get('join');
    if (jt) {
      joinMode = true; onlyRole = hp.get('role') === 'family' ? 'family' : 'elder';
      history.replaceState(null, '', location.pathname + location.search.replace(/[?&]openExternalBrowser=1/, ''));
      sessionPromise = getSession(jt).then(adopt, function (e) {
        if (e.status === 404) e.message = '這個連結已經過期或不存在。請回到第一支手機重新產生。';
        throw e;
      });
      sessionPromise.catch(function (e) { sessionError = e.message; renderIntro(); });
      showIntro(false);
      sessionPromise.then(function () { renderIntro(); });
      return;
    }
    ensureSession(false).then(function () { renderIntro(); if (S.introDone && !started && $('intro').hidden) startExperience(S.only || (elderRemote ? 'family' : active)); });
    if (!S.introDone || firstVisit) showIntro(false);
    else {
      // 回訪：不再出示完整說明，等 session 驗證完直接進入。
      $('stage').appendChild(h('div', { class: 'panel', id: 'boot-panel', role: 'status' }, h('div', { class: 'spinner', 'aria-hidden': 'true' }), h('p', { text: '正在恢復您的體驗…' })));
      sessionPromise.then(function () { var bp = $('boot-panel'); if (bp) bp.remove(); startExperience(S.only || (elderRemote ? 'family' : 'elder')); },
        function (e) { var bp = $('boot-panel'); if (bp) bp.remove(); sessionError = e.message; showIntro(false); introIdx = introSteps.length - 1; renderIntro(); });
    }
  }
  boot();
})();
