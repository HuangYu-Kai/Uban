/* 示意監視機：在 canvas 上畫客廳與王奶奶，並以 Socket.IO + WebRTC 回應家屬端的即時觀看。 */
(function () {
  'use strict';
  var W = 480, H = 900, FONT = '"Noto Sans TC","PingFang TC","Microsoft JhengHei",sans-serif';

  // ---------- 繪圖小工具 ----------
  function rr(c, x, y, w, h, r, fill) {
    c.beginPath();
    c.moveTo(x + r, y); c.lineTo(x + w - r, y); c.quadraticCurveTo(x + w, y, x + w, y + r);
    c.lineTo(x + w, y + h - r); c.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
    c.lineTo(x + r, y + h); c.quadraticCurveTo(x, y + h, x, y + h - r);
    c.lineTo(x, y + r); c.quadraticCurveTo(x, y, x + r, y); c.closePath();
    if (fill) { c.fillStyle = fill; c.fill(); }
  }
  function ell(c, x, y, rx, ry, fill) {
    c.beginPath(); c.ellipse(x, y, rx, ry, 0, 0, Math.PI * 2); c.fillStyle = fill; c.fill();
  }
  function seg(c, x1, y1, x2, y2, w, col) {
    c.beginPath(); c.moveTo(x1, y1); c.lineTo(x2, y2);
    c.lineWidth = w; c.lineCap = 'round'; c.strokeStyle = col; c.stroke();
  }
  function lin(c, x0, y0, x1, y1, stops) {
    var g = c.createLinearGradient(x0, y0, x1, y1);
    for (var i = 0; i < stops.length; i++) g.addColorStop(stops[i][0], stops[i][1]);
    return g;
  }
  function pad(n) { return (n < 10 ? '0' : '') + n; }

  // ---------- 靜態背景（只畫一次，480x900 直式） ----------
  function makeBg() {
    var b = document.createElement('canvas'); b.width = W; b.height = H;
    var c = b.getContext('2d'), i, x;
    c.fillStyle = lin(c, 0, 0, 0, 444, [[0, '#EBDCC4'], [1, '#E0C8A8']]); c.fillRect(0, 0, W, 446);
    // 木地板（淡透視：橫縫漸寬、直縫向消失點收斂）
    c.fillStyle = lin(c, 0, 440, 0, H, [[0, '#C99C6D'], [1, '#B07F52']]); c.fillRect(0, 440, W, H - 440);
    c.strokeStyle = 'rgba(110,70,40,0.25)'; c.lineWidth = 1.5;
    for (i = 0; i < 12; i++) { var yy = 444 + Math.pow(i, 1.55) * 9; c.beginPath(); c.moveTo(0, yy); c.lineTo(W, yy); c.stroke(); }
    for (x = -600; x <= 1080; x += 100) { c.beginPath(); c.moveTo(240 + (x - 240) * 0.3, 444); c.lineTo(x, H); c.stroke(); }
    rr(c, 0, 430, W, 16, 0, '#B38660');
    // 窗戶與窗簾（左上）
    rr(c, 70, 100, 150, 190, 6, '#F6F1E8');
    c.fillStyle = lin(c, 0, 110, 0, 280, [[0, '#CDE7F4'], [1, '#F8F3D8']]); c.fillRect(80, 110, 130, 170);
    ell(c, 165, 190, 22, 10, 'rgba(255,255,255,0.8)'); ell(c, 186, 184, 16, 8, 'rgba(255,255,255,0.8)');
    c.fillStyle = '#F6F1E8'; c.fillRect(142, 110, 6, 170); c.fillRect(80, 190, 130, 6);
    rr(c, 62, 288, 166, 10, 4, '#E9E0D0');
    rr(c, 36, 84, 44, 246, 10, '#D9826B'); rr(c, 210, 84, 44, 246, 10, '#D9826B');
    c.strokeStyle = 'rgba(120,50,40,0.25)'; c.lineWidth = 3;
    for (i = 0; i < 3; i++) { c.beginPath(); c.moveTo(48 + i * 12, 90); c.lineTo(48 + i * 12, 324); c.stroke(); c.beginPath(); c.moveTo(222 + i * 12, 90); c.lineTo(222 + i * 12, 324); c.stroke(); }
    rr(c, 28, 72, 234, 11, 5, '#8A5A3B');
    // 窗光灑在地板
    c.fillStyle = 'rgba(255,244,205,0.24)'; c.beginPath();
    c.moveTo(70, 446); c.lineTo(230, 446); c.lineTo(400, H); c.lineTo(20, H); c.closePath(); c.fill();
    // 相框
    rr(c, 292, 236, 110, 84, 4, '#8A5A3B'); c.fillStyle = '#BFD9C9'; c.fillRect(300, 244, 94, 68);
    ell(c, 366, 264, 9, 9, '#F4D88A');
    c.fillStyle = '#8FB59A'; c.beginPath(); c.moveTo(300, 312); c.lineTo(326, 274); c.lineTo(356, 312); c.fill();
    c.fillStyle = '#76A184'; c.beginPath(); c.moveTo(336, 312); c.lineTo(366, 284); c.lineTo(394, 312); c.fill();
    // 沙發（中段）
    rr(c, 110, 336, 250, 92, 18, '#7E9B8A'); rr(c, 94, 376, 36, 70, 14, '#6E8A7A'); rr(c, 340, 376, 36, 70, 14, '#6E8A7A');
    rr(c, 128, 384, 214, 54, 12, '#8CAA98'); rr(c, 150, 346, 40, 36, 9, '#E5B77A'); rr(c, 282, 346, 40, 36, 9, '#D9826B');
    seg(c, 112, 444, 112, 456, 7, '#5C4030'); seg(c, 358, 444, 358, 456, 7, '#5C4030');
    // 立燈（右側）
    seg(c, 436, 260, 436, 440, 6, '#6B5A4A'); ell(c, 436, 444, 22, 6, '#6B5A4A');
    c.fillStyle = '#F2D79A'; c.beginPath(); c.moveTo(412, 262); c.lineTo(460, 262); c.lineTo(450, 214); c.lineTo(422, 214); c.closePath(); c.fill();
    // 盆栽（左下角落）
    rr(c, 28, 392, 40, 40, 6, '#B5654F');
    for (i = 0; i < 5; i++) { c.beginPath(); c.ellipse(48 + (i - 2) * 11, 372 - (i % 2) * 14, 8, 24, (i - 2) * 0.35, 0, Math.PI * 2); c.fillStyle = i % 2 ? '#6E9A62' : '#82AE72'; c.fill(); }
    // 地毯與茶几
    ell(c, 240, 640, 215, 86, '#B5654F'); ell(c, 240, 640, 182, 68, '#D79A7C'); ell(c, 240, 640, 140, 48, '#C37B63');
    rr(c, 160, 520, 160, 18, 5, '#7A5236'); seg(c, 174, 538, 170, 566, 7, '#5C4030'); seg(c, 306, 538, 310, 566, 7, '#5C4030');
    rr(c, 232, 498, 22, 20, 5, '#F6F1E8'); seg(c, 243, 498, 243, 492, 2, '#F6F1E8');
    // 下方不留空：地墊與毛線籃
    ell(c, 130, 800, 78, 34, '#E5B77A'); ell(c, 130, 794, 62, 24, '#F0CB93'); ell(c, 130, 792, 14, 6, '#D9A86A');
    ell(c, 372, 812, 52, 22, '#9B6B47'); ell(c, 372, 802, 46, 18, '#B58259'); ell(c, 360, 796, 14, 12, '#D9826B'); ell(c, 384, 798, 12, 10, '#7E9B8A');
    // 暈影
    var v = c.createRadialGradient(W / 2, 520, 280, W / 2, 520, 700);
    v.addColorStop(0, 'rgba(0,0,0,0)'); v.addColorStop(1, 'rgba(0,0,0,0.28)');
    c.fillStyle = v; c.fillRect(0, 0, W, H);
    return b;
  }

  // ---------- 王奶奶（原點在腳底，面向 +x） ----------
  function person(c, swing, closed, slippers, wig) {
    var s, a, fx, fy, SK = '#F3D2B0', CA = '#C4564A';
    c.scale(1.1, 1.1);
    for (s = -1; s <= 1; s += 2) {            // 腿（先後腳）
      a = s * swing * 0.5; fx = Math.sin(a) * 85; fy = -85 + Math.cos(a) * 85 - (swing * s > 0 ? 4 : 0);
      seg(c, 0, -85, fx, fy - 8, 17, s < 0 ? '#2F333D' : '#3B3F4A');
      if (slippers) ell(c, fx + 7, fy - 4, 14, 6.5, '#7C5C9E'); else ell(c, fx + 6, fy - 5, 12, 5.5, SK);
    }
    for (s = -1; s <= 1; s += 2) {            // 手臂
      a = (wig === undefined ? -s * swing * 0.55 : (s < 0 ? 0.35 : 0.5 + wig)) ;
      var hx = Math.sin(a) * 58, hy = -150 + Math.cos(a) * 58;
      if (s < 0) { seg(c, 0, -150, hx, hy, 13, '#A9473C'); ell(c, hx, hy + 4, 6.5, 6.5, SK); }
    }
    rr(c, -20, -92, 40, 20, 8, '#3B3F4A');
    rr(c, -23, -160, 46, 78, 15, CA); rr(c, -7, -156, 14, 64, 5, '#F2E3CF');
    for (a = 0; a < 3; a++) ell(c, 0, -146 + a * 20, 2.5, 2.5, '#8E3A31');
    for (s = -1; s <= 1; s += 2) {
      if (s > 0 || wig !== undefined) {
        a = (wig === undefined ? -s * swing * 0.55 : 0.5 + wig);
        if (s > 0) { var qx = Math.sin(a) * 58, qy = -150 + Math.cos(a) * 58; seg(c, 0, -150, qx, qy, 13, CA); ell(c, qx, qy + 4, 6.5, 6.5, SK); }
      }
    }
    rr(c, -5, -176, 10, 16, 4, SK);
    ell(c, -13, -198, 11, 10, '#E8E6E1'); ell(c, 0, -181, 20, 20, SK);
    c.beginPath(); c.arc(0, -183, 21, Math.PI * 1.02, Math.PI * 1.98); c.lineTo(8, -190); c.closePath(); c.fillStyle = '#E8E6E1'; c.fill();
    ell(c, 9, -173, 5, 3.2, 'rgba(232,130,120,0.35)');
    c.strokeStyle = '#4A3A30'; c.lineWidth = 2; c.lineCap = 'round';
    if (closed) { c.beginPath(); c.moveTo(4, -182); c.quadraticCurveTo(8, -179, 12, -182); c.stroke(); }
    else ell(c, 8, -182, 2.4, 2.8, '#3A2D26');
    c.beginPath(); c.moveTo(6, -168); c.quadraticCurveTo(10, -165, 14, -168); c.stroke();
  }

  // ---------- 對外 ----------
  function create(opts) {
    opts = opts || {};
    var canvas = document.createElement('canvas'); canvas.width = W; canvas.height = H;
    canvas.style.cssText = 'display:block;width:100%;height:100%;object-fit:cover;object-position:50% 62%;';
    var ctx = canvas.getContext('2d'), bg = makeBg();
    var holder = document.createElement('div');
    holder.setAttribute('aria-hidden', 'true');
    holder.style.cssText = 'position:fixed;left:-10000px;top:0;width:2px;height:2px;overflow:hidden;';
    (document.body || document.documentElement).appendChild(holder);
    holder.appendChild(canvas);

    var self = { canvas: canvas }, scene = 'normal', online = false, viewing = false;
    var mounted = false, stopped = true, dead = false;
    // 奶奶狀態
    var fallX = 200, g = { x: 200, face: 1, mode: 'pause', tmr: 1.5, phase: 0, amp: 0, prog: 0 };
    var rafId = 0, intId = 0, lastDraw = 0, lastT = 0;
    // 連線狀態
    var ws = null, gen = 0, retryN = 0, retryTimer = 0, watchdog = 0, onlineTimer = 0, sid = null;
    var pc = null, peerId = null, callId = null, pendingCands = [], remoteSet = false;
    var connTimer = 0, discTimer = 0;

    function notify() {
      try { if (opts.onState) opts.onState({ online: online, viewing: viewing, scene: scene }); } catch (e) {}
    }
    function setViewing(v) {
      if (viewing === v) return;
      viewing = v; try { if (opts.onView) opts.onView(v); } catch (e) {}
      updateLoop(); notify();
    }
    function setOnline(v) { if (online !== v) { online = v; if (v) retryN = 0; notify(); } }

    // ----- 繪製 -----
    function ease(p) { return p * p * (3 - 2 * p); }
    function step(dt) {
      var target = scene === 'fallen' ? 1 : 0;
      if (g.prog < target) g.prog = Math.min(target, g.prog + dt / 1.0);
      else if (g.prog > target) g.prog = Math.max(target, g.prog - dt / 1.5);
      var still = g.prog > 0 || target > 0;
      if (target > 0) g.x += (fallX - g.x) * Math.min(1, dt * 5);
      if (!still) {
        g.tmr -= dt;
        if (g.mode === 'walk') {
          g.x += g.face * 28 * dt;
          if (g.x > 370) { g.x = 370; g.face = -1; g.mode = 'pause'; g.tmr = 2 + Math.random() * 2; }
          else if (g.x < 110) { g.x = 110; g.face = 1; g.mode = 'pause'; g.tmr = 2 + Math.random() * 2; }
          else if (g.tmr <= 0) { g.mode = 'pause'; g.tmr = 2 + Math.random() * 3; }
        } else if (g.tmr <= 0) {
          g.mode = 'walk'; g.tmr = 4 + Math.random() * 5;
          if (Math.random() < 0.4) g.face = -g.face;
          if (g.x > 330) g.face = -1; else if (g.x < 150) g.face = 1;
        }
      }
      var want = (!still && g.mode === 'walk') ? 1 : 0;
      g.amp += (want - g.amp) * Math.min(1, dt * 4);
      g.phase += dt * 4.2 * g.amp;
    }
    function draw(n) {
      var t = n / 1000; step(lastT ? Math.min(0.2, (n - lastT) / 1000) : 0); lastT = n; lastDraw = n;
      ctx.clearRect(0, 0, W, H); ctx.drawImage(bg, 0, 0);
      var feetY = 630, e = ease(g.prog), lying = e > 0.02, swing = Math.sin(g.phase) * 0.9 * g.amp;
      ell(ctx, g.x + (lying ? g.face * 110 * e : 0), feetY + 2, lying ? 44 + 80 * e : 40, 9, 'rgba(60,35,20,0.22)');
      ctx.save();
      ctx.translate(g.x, feetY - 22 * e + (lying ? 0 : Math.sin(t * 1.6) * 0.8));
      ctx.rotate(g.face * e * Math.PI / 2); ctx.scale(g.face, 1);
      person(ctx, lying ? 0.1 : swing, e > 0.7, e < 0.5, lying && e > 0.95 ? 0.18 * Math.sin(t * 2.4) : undefined);
      ctx.restore();
      if (e > 0.5) {  // 拖鞋掉在腳邊
        ell(ctx, g.x - g.face * 40, feetY + 10, 16, 7.5, '#7C5C9E'); ell(ctx, g.x - g.face * 72, feetY + 18, 16, 7.5, '#7C5C9E');
      }
      overlay(t, g.prog >= 1 && scene === 'fallen');
    }
    function overlay(t, alarm) {
      var d = new Date();
      if (alarm) {   // 紅框緊貼躺姿：沿身體方向 -16..+240、垂直 ±36
        var x0 = g.face > 0 ? g.x - 16 : g.x - 240, by = 572;
        ctx.strokeStyle = '#E53935'; ctx.lineWidth = 3; ctx.strokeRect(x0, by, 256, 82);
        rr(ctx, x0 - 1.5, by - 30, 108, 30, 4, '#E53935');
        ctx.fillStyle = '#fff'; ctx.font = 'bold 20px ' + FONT; ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
        ctx.fillText('疑似跌倒', x0 + 10, by - 14);
      }
      rr(ctx, 40, 180, 204, 34, 17, 'rgba(25,25,25,0.62)');
      if (Math.floor(t * 1.4) % 2 === 0) ell(ctx, 60, 197, 6.5, 6.5, '#FF3B30');
      ctx.fillStyle = '#fff'; ctx.font = '19px ' + FONT; ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
      ctx.fillText('客廳 · 示意畫面', 76, 198);
      rr(ctx, 304, 180, 136, 34, 17, 'rgba(25,25,25,0.62)');
      ctx.fillStyle = '#fff'; ctx.textAlign = 'center'; ctx.fillText(pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds()), 372, 198);
    }
    function needLoop() { return !dead && (mounted || !!pc); }
    function updateLoop() {
      if (needLoop()) {
        if (!rafId) rafId = requestAnimationFrame(frame);
        if (!intId) intId = setInterval(function () {
          if (!needLoop()) { updateLoop(); return; }
          if (Date.now() - lastDraw > 400) draw(Date.now());
        }, 250);
      } else {
        if (rafId) cancelAnimationFrame(rafId); rafId = 0;
        if (intId) clearInterval(intId); intId = 0; lastT = 0;
      }
    }
    function frame() {
      rafId = 0; if (!needLoop()) return;
      var n = Date.now(); if (n - lastDraw >= 66) draw(n);
      rafId = requestAnimationFrame(frame);
    }

    // ----- WebRTC -----
    function emit(name, data) {
      try { if (ws && ws.readyState === 1) ws.send('42' + JSON.stringify([name, data])); } catch (e) {}
    }
    function closePeer() {
      clearTimeout(connTimer); clearTimeout(discTimer);
      var p = pc; pc = null; remoteSet = false;
      if (p) { try { p.onconnectionstatechange = null; p.onicecandidate = null; p.close(); } catch (e) {} }
    }
    function teardown() {
      closePeer(); pendingCands = []; callId = null; peerId = null;
      setViewing(false); updateLoop();
    }
    function onConnState(p) {
      return function () {
        if (p !== pc) return;
        var s = p.connectionState;
        if (s === 'connected') { clearTimeout(connTimer); clearTimeout(discTimer); setViewing(true); }
        else if (s === 'failed' || s === 'closed') teardown();
        else if (s === 'disconnected') { clearTimeout(discTimer); discTimer = setTimeout(function () { if (p === pc) teardown(); }, 8000); }
      };
    }
    function flushCands() {
      var q = pendingCands; pendingCands = [];
      q.forEach(function (c) { try { pc.addIceCandidate(c).catch(function () {}); } catch (e) {} });
    }
    function handleOffer(d) {
      var reuse = pc && peerId === d.senderId && pc.signalingState === 'stable' &&
        pc.connectionState !== 'closed' && pc.connectionState !== 'failed';
      peerId = d.senderId; if (d.callId) callId = d.callId;
      var p;
      if (reuse) p = pc;
      else {
        closePeer();
        p = pc = new RTCPeerConnection({ iceServers: opts.iceServers || [] });
        var stream = canvas.captureStream(15), tr = stream.getVideoTracks()[0];
        if (tr) { try { tr.contentHint = 'detail'; } catch (e) {} p.addTrack(tr, stream); } // 線條與文字清楚優先
        p.onicecandidate = function (ev) {
          if (!ev.candidate || p !== pc) return;
          emit('candidate', { room: opts.room, candidate: ev.candidate.candidate, sdpMid: ev.candidate.sdpMid,
            sdpMLineIndex: ev.candidate.sdpMLineIndex, targetId: peerId });
        };
        p.onconnectionstatechange = onConnState(p);
        clearTimeout(connTimer);
        connTimer = setTimeout(function () { if (p === pc && p.connectionState !== 'connected') teardown(); }, 20000);
        updateLoop(); draw(Date.now());
      }
      remoteSet = false;
      return p.setRemoteDescription({ type: 'offer', sdp: d.sdp }).then(function () {
        remoteSet = true; flushCands(); return p.createAnswer();
      }).then(function (ans) {
        return p.setLocalDescription(ans).then(function () {
          emit('answer', { room: opts.room, targetId: peerId, type: 'answer', sdp: ans.sdp });
        });
      }).catch(function () { if (p === pc && !viewing) teardown(); });
    }
    function sameCall(d) { return !d || !d.callId || !callId || d.callId === callId; }

    // ----- Socket.IO -----
    function onEvent(name, d) {
      d = d || {};
      if (name === 'emergency-call' || name === 'call-request') {
        if (!d.senderId) return;
        peerId = d.senderId; callId = d.callId || callId;
        emit('call-accept', { targetId: d.senderId, callId: d.callId });
      } else if (name === 'offer') {
        if (d.sdp && d.senderId) handleOffer(d);
      } else if (name === 'candidate') {
        if (!d.candidate) return;
        var ci = { candidate: d.candidate, sdpMid: d.sdpMid, sdpMLineIndex: d.sdpMLineIndex };
        if (pc && remoteSet) { try { pc.addIceCandidate(ci).catch(function () {}); } catch (e) {} }
        else pendingCands.push(ci);
      } else if (name === 'end-call' || name === 'cancel-call' || name === 'call-busy') {
        if (sameCall(d)) teardown();
      } else if (name === 'elder-devices-update') {
        if (ws && sid) { clearTimeout(onlineTimer); setOnline(true); }
      } else if (name === 'join-failed') {
        clearTimeout(onlineTimer); setOnline(false); closeSocket(); scheduleRetry(5000);
      }
    }
    function onMessage(msg) {
      if (typeof msg !== 'string' || !msg) return;
      var t = msg.charAt(0);
      if (t === '0') {
        var o = {}; try { o = JSON.parse(msg.slice(1)); } catch (e) {}
        armWatchdog((o.pingInterval || 25000) + (o.pingTimeout || 20000) + 5000);
        wsSend('40');
      } else if (t === '2') { wsSend('3'); armWatchdog(); }
      else if (msg.indexOf('40') === 0) {
        try { sid = JSON.parse(msg.slice(2) || '{}').sid || 'x'; } catch (e) { sid = 'x'; }
        usePost().then(function () {
          if (!ws || !sid) return;
          emit('join', { room: opts.room, role: 'elder', deviceName: opts.deviceName, deviceMode: 'monitor',
            userId: opts.userId, fcmToken: null, appState: 'foreground' });
          clearTimeout(onlineTimer); onlineTimer = setTimeout(function () { setOnline(true); }, 400);
        });
      } else if (msg.indexOf('42') === 0) {
        var i = msg.indexOf('['); if (i < 0) return;
        try { var arr = JSON.parse(msg.slice(i)); onEvent(arr[0], arr[1]); } catch (e) {}
      } else if (msg.indexOf('41') === 0 || msg.indexOf('44') === 0) { closeSocket(); scheduleRetry(); }
    }
    var wdMs = 50000;
    function armWatchdog(ms) {
      if (ms) wdMs = ms; clearTimeout(watchdog);
      watchdog = setTimeout(function () { closeSocket(); scheduleRetry(); }, wdMs);
    }
    function wsSend(s) { try { if (ws && ws.readyState === 1) ws.send(s); } catch (e) {} }
    function usePost() {   // 每次(重新)加入前都重新登記監視機；失敗不影響
      try {
        return fetch('../api/demo/session/' + encodeURIComponent(opts.token) + '/monitor', { method: 'POST' })
          .then(function () {}, function () {});
      } catch (e) { return Promise.resolve(); }
    }
    function closeSocket() {
      gen++; clearTimeout(watchdog); clearTimeout(onlineTimer);
      var s = ws; ws = null; sid = null;
      if (s) { try { s.onopen = s.onmessage = s.onclose = s.onerror = null; s.close(); } catch (e) {} }
      teardown(); setOnline(false);
    }
    function scheduleRetry(min) {
      if (stopped) return;
      clearTimeout(retryTimer);
      var d = Math.min(15000, 1000 * Math.pow(2, retryN++));
      retryTimer = setTimeout(openSocket, Math.max(d, min || 0));
    }
    function openSocket() {
      if (stopped) return;
      var my = ++gen, s;
      try { s = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/socket.io/?EIO=4&transport=websocket'); }
      catch (e) { scheduleRetry(); return; }
      ws = s; armWatchdog(30000);
      s.onmessage = function (ev) { if (my === gen) { try { onMessage(ev.data); } catch (e) {} } };
      s.onclose = function () { if (my === gen) { closeSocket(); scheduleRetry(); } };
      s.onerror = function () {};
    }

    // ----- 公開介面 -----
    self.start = function () {
      if (!stopped) return; stopped = false; retryN = 0;
      updateLoop();
      usePost().then(openSocket);
    };
    self.stop = function () {
      stopped = true; dead = true; clearTimeout(retryTimer); closeSocket(); updateLoop();
      try { if (holder.parentNode) holder.parentNode.removeChild(holder); } catch (e) {}
    };
    self.mount = function (el) { if (el) { el.appendChild(canvas); mounted = true; updateLoop(); draw(Date.now()); } };
    self.unmount = function () { holder.appendChild(canvas); mounted = false; updateLoop(); };
    self.setScene = function (name) {
      var n = name === 'fallen' ? 'fallen' : 'normal';
      if (n === scene) return; scene = n;
      if (n === 'fallen') { g.mode = 'pause'; g.amp = 0; if (g.x < 240) { g.face = 1; fallX = Math.min(210, g.x); } else { g.face = -1; fallX = Math.max(270, g.x); } } // 往畫面內側倒
      else g.tmr = 1.5;
      if (!rafId) draw(Date.now()); notify();
    };
    Object.defineProperty(self, 'scene', { get: function () { return scene; } });
    Object.defineProperty(self, 'online', { get: function () { return online; } });
    Object.defineProperty(self, 'viewing', { get: function () { return viewing; } });
    draw(Date.now());
    return self;
  }

  window.UbanMonitor = { create: create };
})();
