(function () {
  'use strict';

  var sections = [
    { title: '問題情境', kicker: '開場', duration: '0:00–0:20', summary: '長輩獨自在家，家人最擔心的是不知道是否平安。', script: '當長輩獨自在家，家人最擔心的，不只是聯絡不到，更是不知道他是否安全。', hint: '雙端畫面：先聚焦長輩端，再切到家屬端', elder: 'elder:home', family: 'fmain:home' },
    { title: '早上：AI 主動關懷', kicker: '長輩的一天 01', duration: '0:20–0:45', summary: 'Heartbeat 主動問候，長輩以語音自然互動。', script: '早上，Heartbeat 主動向長輩問候。透過語音辨識、AI 對話與長期記憶，長輩不用學習複雜操作，也能自然互動。', hint: '長輩端：聊天；家屬端：首頁', elder: 'elder:chat', family: 'fmain:home' },
    { title: '出門：GPS 行程摘要', kicker: '長輩的一天 02', duration: '0:45–1:05', summary: '長輩外出後，家屬端同步看到今日行程。', script: '當長輩外出時，GPS 會記錄移動軌跡，家屬端則能看到今日外出摘要，在不打擾長輩的情況下掌握行程。', hint: '長輩端：首頁；家屬端：移動軌跡地圖', elder: 'elder:home', family: 'map' },
    { title: '迷路／不舒服：提出求助', kicker: '長輩的一天 03', duration: '1:05–1:25', summary: '語音求助觸發定位與家屬通知。', script: '如果長輩迷路或感到不舒服，只要說出「帶我回家」或提出求助，系統就會取得目前位置，並即時通知家屬。', hint: '長輩端：緊急通話；家屬端：警示中心', elder: 'call:emergency', family: 'alerts' },
    { title: '家屬回應：通話與監測', kicker: '長輩的一天 04', duration: '1:25–1:55', summary: '家屬收到通知後，可直接通話並查看監測畫面。', script: '家屬收到通知後，可以直接發起雙向視訊通話；影像監測則透過 YOLO 協助辨識異常情況，讓家屬更快做出反應。', hint: '長輩端：監視模式；家屬端：監看畫面', elder: 'call:cctv', family: 'fcall:monitor' },
    { title: '晚上：生活與情緒紀錄', kicker: '長輩的一天 05', duration: '1:55–2:15', summary: '家屬從心情、生活足跡與故事回顧一天。', script: '到了晚上，家屬可以透過 AI 心情雷達、生活足跡與人生故事，了解長輩一天的生活狀態，讓照顧成為持續陪伴。', hint: '長輩端：我的；家屬端：健康趨勢', elder: 'elder:profile', family: 'health' },
    { title: '系統架構與特殊技術', kicker: '技術亮點', duration: '2:15–2:53', summary: '從前端、後端、AI、即時通訊到資料與安全服務。', script: 'Uban 不是單一功能的 App，而是由多層技術整合而成，讓語音、記憶、定位、通話、影像與通知共同完成照護閉環。', hint: '技術頁：不顯示正式環境連線資訊', technical: true },
    { title: '結語：讓關心即時發生', kicker: '結尾', duration: '2:53–3:00', summary: '讓長輩安心生活，也讓家人放心陪伴。', script: '我們希望透過 Uban，讓每一次關心都能被即時接住，讓長輩安心生活，也讓家人放心陪伴。', hint: '顯示 Logo、團隊與致謝', closing: true }
  ];

  var technology = [
    ['App 前端', 'Flutter／Dart', '長輩端與家屬端跨平台互動介面。'],
    ['AI 對話', 'Ollama／Gemma 4／Gemini', '主引擎、備援引擎與 Tool Calling。'],
    ['語音與記憶', 'Faster-Whisper／TTS／Pinecone', '語音轉文字、語音回應與 RAG 長期記憶。'],
    ['即時通訊', 'WebRTC／Socket.IO', '建立雙向視訊與通話信令。'],
    ['網路連線', 'Coturn／Tailscale', '支援不同網路環境下的穿透與媒體中繼。'],
    ['影像辨識', 'YOLO／OpenCV／PyTorch／CUDA', '協助偵測跌倒等影像異常狀態。'],
    ['定位與資料', 'GPS／MySQL／SQLite', '保存位置、生活資料與離線待同步資料。'],
    ['通知與排程', 'Firebase FCM／APScheduler', '推送警報、提醒與主動關懷任務。'],
    ['安全與角色', 'JWT／bcrypt／權限控管', '保護帳號、角色與照護資料的存取範圍。']
  ];

  var current = 0;
  var mode = 'dual';
  var nav = document.getElementById('sectionNav');
  var frameGrid = document.getElementById('frameGrid');
  var technicalPanel = document.getElementById('technicalPanel');
  var closingPanel = document.getElementById('closingPanel');
  var elderFrame = document.getElementById('elderFrame');
  var familyFrame = document.getElementById('familyFrame');
  var modeButton = document.getElementById('modeButton');

  function el(id) { return document.getElementById(id); }
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
    var elderCard = document.querySelector('[data-role="elder"]');
    var familyCard = document.querySelector('[data-role="family"]');
    frameGrid.classList.toggle('single', mode !== 'dual');
    elderCard.hidden = mode === 'family';
    familyCard.hidden = mode === 'elder';
    modeButton.textContent = mode === 'dual' ? '雙端展示' : mode === 'elder' ? '只看長輩端' : '只看家屬端';
  }
  function renderSection() {
    var section = sections[current];
    el('sectionKicker').textContent = String(current + 1).padStart(2, '0') + ' / ' + section.kicker;
    el('sectionTitle').textContent = section.title;
    el('sectionSummary').textContent = section.summary;
    el('sectionDuration').textContent = section.duration;
    el('screenHint').textContent = section.hint;
    el('scriptText').textContent = section.script;
    el('progressBar').style.width = ((current + 1) / sections.length * 100) + '%';
    technicalPanel.hidden = !section.technical;
    closingPanel.hidden = !section.closing;
    frameGrid.hidden = !!section.technical || !!section.closing;
    if (!section.technical && !section.closing) {
      send(elderFrame, section.elder);
      send(familyFrame, section.family);
    }
    applyMode();
    Array.prototype.forEach.call(nav.children, function (button, index) { button.classList.toggle('active', index === current); });
    el('previousButton').disabled = current === 0;
    el('nextButton').textContent = current === sections.length - 1 ? '重新開始' : '下一段';
  }
  function select(index) {
    current = (index + sections.length) % sections.length;
    renderSection();
  }

  nav.addEventListener('click', function (event) {
    var button = event.target.closest('[data-index]');
    if (button) select(+button.dataset.index);
  });
  el('previousButton').addEventListener('click', function () { select(current === 0 ? 0 : current - 1); });
  el('nextButton').addEventListener('click', function () { select(current === sections.length - 1 ? 0 : current + 1); });
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
    frame.addEventListener('load', function () { renderSection(); });
  });
  window.addEventListener('message', function (event) {
    if (event.source !== elderFrame.contentWindow && event.source !== familyFrame.contentWindow) return;
    if (event.data && event.data.app === 'uban-prototype' && event.data.type === 'ready') renderSection();
  });

  renderTechnology();
  renderNav();
  renderSection();
})();
