(function () {
  'use strict';

  var sections = [
    {
      title: '系統名稱與定位',
      kicker: '開場',
      duration: '0:00–0:12',
      summary: 'Uban 是連結長輩、家屬與照護資訊的 AI 陪伴系統。',
      script: 'Uban 是一套 AI 陪伴與遠距照護系統，透過日常互動、定位、求助與即時回應，讓長輩安心生活，也讓家人放心陪伴。',
      hint: '顯示系統名稱、定位與核心價值',
      panel: 'identity'
    },
    {
      title: '問題情境',
      kicker: '開場 02',
      duration: '0:12–0:25',
      summary: '家人最擔心的，是不知道長輩是否平安。',
      script: '當長輩獨自在家，家人最擔心的不只是聯絡不到，而是不知道他是否安全。Uban 從日常主動關懷開始，讓需要被接住的訊號不再被錯過。',
      hint: '以情境卡說明照護痛點，不放入無關的手機畫面',
      panel: 'context'
    },
    {
      title: '早上：AI 主動關懷',
      kicker: '長輩的一天 01',
      duration: '0:25–0:50',
      summary: '只展示長輩端，從首頁進入聊天並開始語音互動。',
      script: '早上，Uban 主動向長輩問候。長輩不用學習複雜操作，只要進入聊天頁，就能用自然語音和 AI 好朋友小嘎互動。',
      role: 'elder',
      focus: true,
      steps: [
        { target: 'elder:home', caption: '首頁：看見今天的關懷入口', duration: 1800 },
        { target: 'elder:chat', caption: '聊天：進入 AI 對話與語音互動', duration: 4200 }
      ]
    },
    {
      title: '出門：GPS 行程摘要',
      kicker: '長輩的一天 02',
      duration: '0:50–1:12',
      summary: '只展示家屬端，從首頁進入移動軌跡地圖。',
      script: '當長輩外出時，家屬不需要一直打電話確認。家屬端可以看到今日位置、移動路線與時間軸，在不打擾長輩的情況下掌握行程。',
      role: 'family',
      focus: true,
      steps: [
        { target: 'fmain:home', caption: '家屬首頁：看到今日位置摘要', duration: 1800 },
        { target: 'map', caption: '移動軌跡：查看路線與時間軸', duration: 4800 }
      ]
    },
    {
      title: '迷路／不舒服：提出求助',
      kicker: '長輩的一天 03',
      duration: '1:12–1:35',
      summary: '只展示長輩端，從首頁切換至緊急通話。',
      script: '如果長輩迷路或感到不舒服，只要說出求助，系統就能進入緊急通話狀態，讓家屬知道需要立即回應。',
      role: 'elder',
      focus: true,
      steps: [
        { target: 'elder:home', caption: '首頁：看見「帶我回家」與求助入口', duration: 1500 },
        { target: 'call:emergency', caption: '緊急通話：進入即時求助狀態', duration: 5000 }
      ]
    },
    {
      title: '家屬回應：警示與通話',
      kicker: '長輩的一天 04',
      duration: '1:35–1:58',
      summary: '只展示家屬端，從警示中心進入通話回應。',
      script: '家屬收到通知後，可以先查看警示內容，再直接打電話回應。影像監測與即時通訊，讓家屬更快判斷狀況並採取行動。',
      role: 'family',
      focus: true,
      steps: [
        { target: 'alerts', caption: '警示中心：看見語音求助與事件內容', duration: 2200 },
        { target: 'fcall:voice', caption: '通話回應：立即聯絡長輩', duration: 4800 }
      ]
    },
    {
      title: '晚上：生活與情緒紀錄',
      kicker: '長輩的一天 05',
      duration: '1:58–2:15',
      summary: '只展示家屬端，回顧健康趨勢與人生故事。',
      script: '到了晚上，家屬可以從健康趨勢與人生故事，回顧長輩一天的生活狀態，讓照顧不只發生在出事的時候，而是成為持續的陪伴。',
      role: 'family',
      focus: true,
      steps: [
        { target: 'health', caption: '健康趨勢：回顧日常活動與狀態', duration: 4200 }
      ]
    },
    {
      title: '系統架構與特殊技術',
      kicker: '技術亮點',
      duration: '2:15–2:53',
      summary: '從前端、後端、AI、即時通訊到資料與安全服務。',
      script: 'Uban 不是單一功能的 App，而是由多層技術整合而成，讓語音、記憶、定位、通話、影像與通知共同完成照護閉環。',
      hint: '技術名稱以用途分組，不顯示正式環境資訊',
      panel: 'technical'
    },
    {
      title: '結語：讓關心即時發生',
      kicker: '結尾',
      duration: '2:53–3:00',
      summary: '讓長輩安心生活，也讓家人放心陪伴。',
      script: '我們希望透過 Uban，讓每一次關心都能被即時接住，讓長輩安心生活，也讓家人放心陪伴。',
      hint: '回到品牌定位與照護價值',
      panel: 'closing'
    }
  ];

  var technology = [
    ['使用者端', 'Flutter／Dart', '長輩端與家屬端的跨平台互動介面。'],
    ['服務端', 'FastAPI／Python', '串接帳號、照護資料、AI 與即時服務。'],
    ['AI 對話', 'Ollama／Gemma／Gemini', '主引擎、備援引擎與 Tool Calling。'],
    ['語音與記憶', 'Faster-Whisper／TTS／Pinecone', '語音轉文字、語音回應與 RAG 長期記憶。'],
    ['即時通訊', 'WebRTC／Socket.IO', '建立雙向視訊、語音與通話信令。'],
    ['網路連線', 'Coturn／Tailscale', '支援不同網路環境下的穿透與媒體中繼。'],
    ['影像辨識', 'YOLO／OpenCV／PyTorch／CUDA', '協助辨識跌倒等影像異常狀態。'],
    ['定位與資料', 'GPS／MySQL／SQLite', '保存位置、生活資料與離線待同步資料。'],
    ['通知與安全', 'Firebase FCM／APScheduler／JWT／bcrypt', '推送提醒、排程任務與保護角色權限。']
  ];

  var current = 0;
  var currentStep = 0;
  var mode = 'dual';
  var timer = 0;
  var paused = false;
  var nav = document.getElementById('sectionNav');
  var frameGrid = document.getElementById('frameGrid');
  var storyStage = document.getElementById('storyStage');
  var identityPanel = document.getElementById('identityPanel');
  var contextPanel = document.getElementById('contextPanel');
  var technicalPanel = document.getElementById('technicalPanel');
  var closingPanel = document.getElementById('closingPanel');
  var elderFrame = document.getElementById('elderFrame');
  var familyFrame = document.getElementById('familyFrame');
  var modeButton = document.getElementById('modeButton');

  function el(id) { return document.getElementById(id); }
  function clearTimer() { if (timer) { clearTimeout(timer); timer = 0; } }
  function send(frame, target) {
    if (!target || !frame.contentWindow) return;
    frame.contentWindow.postMessage({ app: 'uban-showcase', command: 'show', target: target }, '*');
  }
  function renderTechnology() {
    el('technologyGrid').innerHTML = technology.map(function (item) {
      return '<article class="technology-card"><h4>' + item[0] + '</h4><p><strong>' + item[1] + '</strong><br>' + item[2] + '</p></article>';
    }).join('');
  }
  function renderNav() {
    nav.innerHTML = sections.map(function (section, index) {
      return '<button class="section-button' + (index === current ? ' active' : '') + '" type="button" data-index="' + index + '"><span class="section-number">' + String(index + 1).padStart(2, '0') + '</span><span class="section-name">' + section.title + '</span></button>';
    }).join('');
  }
  function applyMode() {
    var section = sections[current];
    var elderCard = document.querySelector('[data-role="elder"]');
    var familyCard = document.querySelector('[data-role="family"]');
    var role = section.role || mode;
    var dual = role === 'dual';
    frameGrid.classList.toggle('single', !dual);
    frameGrid.classList.toggle('focus', !!section.focus);
    elderCard.hidden = role === 'family';
    familyCard.hidden = role === 'elder';
    modeButton.hidden = !dual;
    modeButton.textContent = mode === 'dual' ? '雙端展示' : mode === 'elder' ? '只看長輩端' : '只看家屬端';
  }
  function pulseFrame(role) {
    var card = document.querySelector('[data-role="' + role + '"]');
    var windowEl = card && card.querySelector('.frame-window');
    if (!windowEl) return;
    windowEl.classList.remove('step-pulse');
    void windowEl.offsetWidth;
    windowEl.classList.add('step-pulse');
    setTimeout(function () { windowEl.classList.remove('step-pulse'); }, 700);
  }
  function sendStep() {
    var section = sections[current];
    var steps = section.steps || [];
    var step = steps[currentStep];
    if (!step) return;
    var frame = step.target.indexOf('f') === 0 || step.target === 'map' || step.target === 'alerts' || step.target === 'health' ? familyFrame : elderFrame;
    send(frame, step.target);
    pulseFrame(section.role);
    el('stepIndicator').textContent = steps.length > 1 ? (currentStep + 1) + ' / ' + steps.length : '';
    el('screenHint').textContent = step.caption || section.hint || '';
    el('playStatus').textContent = paused ? '已暫停' : '播放第 ' + (currentStep + 1) + ' 步';
  }
  function scheduleNext() {
    clearTimer();
    var section = sections[current];
    var steps = section.steps || [];
    if (paused || steps.length < 2 || currentStep >= steps.length - 1) return;
    timer = setTimeout(function () {
      currentStep += 1;
      sendStep();
      scheduleNext();
    }, steps[currentStep].duration || 2500);
  }
  function startSection() {
    clearTimer();
    currentStep = 0;
    paused = false;
    el('pauseButton').textContent = '暫停';
    sendStep();
    scheduleNext();
  }
  function renderSection(restart) {
    var section = sections[current];
    clearTimer();
    el('sectionKicker').textContent = String(current + 1).padStart(2, '0') + ' / ' + section.kicker;
    el('sectionTitle').textContent = section.title;
    el('sectionSummary').textContent = section.summary;
    el('sectionDuration').textContent = section.duration;
    el('scriptText').textContent = section.script;
    el('progressBar').style.width = ((current + 1) / sections.length * 100) + '%';
    identityPanel.hidden = section.panel !== 'identity';
    contextPanel.hidden = section.panel !== 'context';
    technicalPanel.hidden = section.panel !== 'technical';
    closingPanel.hidden = section.panel !== 'closing';
    frameGrid.hidden = !section.role;
    storyStage.classList.toggle('panel-mode', !!section.panel);
    if (section.panel) {
      el('stepIndicator').textContent = '';
      el('screenHint').textContent = section.hint || '';
      el('playStatus').textContent = '靜態說明';
    } else if (restart !== false) {
      applyMode();
      startSection();
    } else {
      applyMode();
      sendStep();
    }
    Array.prototype.forEach.call(nav.children, function (button, index) { button.classList.toggle('active', index === current); });
    el('previousButton').disabled = current === 0;
    el('nextButton').textContent = current === sections.length - 1 ? '重新開始' : '下一段';
  }
  function select(index) {
    current = (index + sections.length) % sections.length;
    renderSection(true);
  }

  nav.addEventListener('click', function (event) {
    var button = event.target.closest('[data-index]');
    if (button) select(+button.dataset.index);
  });
  el('previousButton').addEventListener('click', function () { select(current === 0 ? 0 : current - 1); });
  el('nextButton').addEventListener('click', function () { select(current === sections.length - 1 ? 0 : current + 1); });
  el('replayButton').addEventListener('click', function () { renderSection(true); });
  el('pauseButton').addEventListener('click', function () {
    var section = sections[current];
    if (!section.steps || section.steps.length < 2) return;
    paused = !paused;
    el('pauseButton').textContent = paused ? '繼續' : '暫停';
    el('playStatus').textContent = paused ? '已暫停' : '播放第 ' + (currentStep + 1) + ' 步';
    if (paused) clearTimer(); else scheduleNext();
  });
  modeButton.addEventListener('click', function () {
    mode = mode === 'dual' ? 'elder' : mode === 'elder' ? 'family' : 'dual';
    applyMode();
  });
  el('fullscreenButton').addEventListener('click', function () {
    var target = document.documentElement;
    if (document.fullscreenElement) document.exitFullscreen();
    else if (target.requestFullscreen) target.requestFullscreen();
  });
  [elderFrame, familyFrame].forEach(function (frame) {
    frame.addEventListener('load', function () { sendStep(); });
  });
  window.addEventListener('message', function (event) {
    if (event.source !== elderFrame.contentWindow && event.source !== familyFrame.contentWindow) return;
    if (event.data && event.data.app === 'uban-prototype' && event.data.type === 'ready') sendStep();
  });

  renderTechnology();
  renderNav();
  renderSection(true);
})();
