(() => {
  'use strict';

  const STORAGE_KEY = 'okna_pwa_v2';
  const DEFAULT_PRICES = {
    pvc: 950,
    tinted: 1100,
    screen: 700,
    edge: 140,
    eyelet: 90,
    fastener: 120,
    zipper: 780,
    install: 700,
  };

  const MATERIAL_LABEL = { pvc: 'ПВХ', tinted: 'Тонированный', screen: 'Скрин' };
  const TYPE_LABEL = { fixed: 'Глухое', lifting: 'Подъёмное' };

  let state = {
    orderName: '',
    customer: '',
    items: [],
    prices: { ...DEFAULT_PRICES },
    install: false,
    signature: '',
  };

  let editing = null;
  let toastTimer = null;
  let deferredInstall = null;
  const $ = (id) => document.getElementById(id);
  const form = $('windowForm');
  const widthInput = $('width');
  const heightInput = $('height');
  const qtyInput = $('qty');
  const zipperInput = $('zipper');
  const editId = $('editId');
  const addBtn = $('addBtn');
  const cancelEdit = $('cancelEdit');
  let selectedType = 'fixed';
  let selectedMaterial = 'pvc';

  function safeParse(raw) {
    try { return JSON.parse(raw); } catch (e) { return null; }
  }

  function load() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      const saved = raw ? safeParse(raw) : null;
      if (saved && typeof saved === 'object') {
        state.orderName = typeof saved.orderName === 'string' ? saved.orderName : '';
        state.customer = typeof saved.customer === 'string' ? saved.customer : '';
        state.items = Array.isArray(saved.items) ? saved.items.filter(validItem) : [];
        state.prices = { ...DEFAULT_PRICES, ...(saved.prices || {}) };
        state.install = Boolean(saved.install);
        state.signature = typeof saved.signature === 'string' ? saved.signature : '';
      }
    } catch (e) { /* приватный режим — работаем без сохранения */ }
    $('orderName').value = state.orderName;
    $('customer').value = state.customer;
    $('install').checked = state.install;
  }

  function validItem(item) {
    return item && Number.isFinite(Number(item.w)) && Number.isFinite(Number(item.h)) &&
      Number(item.w) >= 300 && Number(item.h) >= 300;
  }

  function save() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    } catch (e) { /* ignore quota/private mode */ }
  }

  function money(value) {
    return new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 0 }).format(Math.round(value)) + ' ₽';
  }

  function num(value, digits = 2) {
    return new Intl.NumberFormat('ru-RU', { maximumFractionDigits: digits }).format(value);
  }

  function area(item) {
    return (Number(item.w) * Number(item.h)) / 1e6;
  }

  function perimeterM(item) {
    return (2 * (Number(item.w) + Number(item.h))) / 1000;
  }

  function itemCost(item) {
    const p = state.prices;
    const a = area(item);
    const perimeter = perimeterM(item);
    const material = Number(p[item.material] || p.pvc || 0) * a;
    const edge = item.material === 'screen'
      ? perimeter * Number(p.edge || 0) * 0.7
      : perimeter * Number(p.edge || 0);
    const eyelets = Math.ceil((2 * (Number(item.w) + Number(item.h))) / 300) + 4;
    const fasteners = item.type === 'lifting'
      ? Math.max(2, Math.ceil((Number(item.w) + Number(item.h)) / 300)) * 2
      : 0;
    const zipperLength = item.zipper ? Number(item.h) / 1000 : 0;
    const total = material + edge +
      eyelets * Number(p.eyelet || 0) +
      fasteners * Number(p.fastener || 0) +
      zipperLength * Number(p.zipper || 0);
    return {
      area: a,
      perimeter,
      material,
      edge,
      eyelets,
      fasteners,
      zipperLength,
      total,
    };
  }

  function quote() {
    const p = state.prices;
    const sum = {
      area: 0, perimeter: 0, material: 0, edge: 0,
      eyeletCount: 0, eyeletCost: 0,
      fastenerCount: 0, fastenerCost: 0,
      zipperLength: 0, zipperCost: 0,
    };
    for (const item of state.items) {
      const m = itemCost(item);
      const qty = Math.max(1, Number(item.qty) || 1);
      sum.area += m.area * qty;
      sum.perimeter += m.perimeter * qty;
      sum.material += m.material * qty;
      sum.edge += m.edge * qty;
      sum.eyeletCount += m.eyelets * qty;
      sum.fastenerCount += m.fasteners * qty;
      sum.zipperLength += m.zipperLength * qty;
      sum.eyeletCost += m.eyelets * qty * Number(p.eyelet || 0);
      sum.fastenerCost += m.fasteners * qty * Number(p.fastener || 0);
      sum.zipperCost += m.zipperLength * qty * Number(p.zipper || 0);
    }
    const install = state.install ? sum.area * Number(p.install || 0) : 0;
    return { ...sum, install, total: sum.material + sum.edge + sum.eyeletCost + sum.fastenerCost + sum.zipperCost + install };
  }

  function currentFormItem() {
    return {
      w: Number(widthInput.value),
      h: Number(heightInput.value),
      type: selectedType,
      material: selectedMaterial,
      qty: Math.max(1, Math.min(50, Number(qtyInput.value) || 1)),
      zipper: zipperInput.checked,
    };
  }

  function updatePreview() {
    const item = currentFormItem();
    if (!Number.isFinite(item.w) || !Number.isFinite(item.h) || item.w < 300 || item.h < 300) {
      $('previewArea').textContent = '—';
      $('previewPrice').textContent = '—';
      return;
    }
    const m = itemCost(item);
    $('previewArea').textContent = num(m.area * item.qty) + ' м²';
    $('previewPrice').textContent = money(m.total * item.qty);
  }

  function windowTitle(item) {
    return `${num(item.w, 0)} × ${num(item.h, 0)} мм`;
  }

  function windowSub(item) {
    return `${TYPE_LABEL[item.type] || 'Окно'} · ${MATERIAL_LABEL[item.material] || 'ПВХ'}` +
      ` · ${item.qty} шт${item.zipper ? ' · молния' : ''}`;
  }

  function card(item, index) {
    const wrap = document.createElement('div');
    wrap.className = 'window-card';
    const number = document.createElement('div');
    number.className = 'window-num';
    number.textContent = String(index + 1);
    const main = document.createElement('div');
    main.className = 'window-main';
    const title = document.createElement('div');
    title.className = 'window-title';
    title.textContent = windowTitle(item);
    const sub = document.createElement('div');
    sub.className = 'window-sub';
    sub.textContent = windowSub(item);
    main.append(title, sub);
    const price = document.createElement('div');
    price.className = 'window-price';
    price.textContent = money(itemCost(item).total * item.qty);
    const actions = document.createElement('div');
    actions.className = 'window-actions';
    const edit = document.createElement('button');
    edit.type = 'button';
    edit.className = 'mini-btn';
    edit.setAttribute('aria-label', 'Изменить окно');
    edit.textContent = '✎';
    edit.addEventListener('click', () => startEdit(item.id));
    const del = document.createElement('button');
    del.type = 'button';
    del.className = 'mini-btn';
    del.setAttribute('aria-label', 'Удалить окно');
    del.textContent = '×';
    del.addEventListener('click', () => removeItem(item.id));
    actions.append(edit, del);
    wrap.append(number, main, price, actions);
    return wrap;
  }

  function emptyState(text) {
    const div = document.createElement('div');
    div.className = 'window-list empty-state';
    div.innerHTML = '<div class="empty-mark">◎</div><b>Пока пусто</b><span></span>';
    div.querySelector('span').textContent = text;
    return div;
  }

  function renderLists() {
    for (const id of ['quickList', 'fullList']) {
      const target = $(id);
      target.replaceChildren();
      if (!state.items.length) {
        target.className = 'window-list empty-state';
        target.innerHTML = '<div class="empty-mark">◎</div><b>Пока пусто</b><span></span>';
        target.querySelector('span').textContent = 'Добавьте первое окно — список появится здесь.';
      } else {
        target.className = 'window-list';
        for (let i = 0; i < state.items.length; i++) target.append(card(state.items[i], i));
      }
    }
    $('windowCount').textContent = String(state.items.length);
  }

  function line(name, qty, amount) {
    const row = document.createElement('div');
    row.className = 'line-row';
    const left = document.createElement('div');
    const n = document.createElement('span');
    n.className = 'name';
    n.textContent = name;
    const q = document.createElement('span');
    q.className = 'qty';
    q.textContent = qty;
    left.append(n, q);
    const b = document.createElement('b');
    b.textContent = money(amount);
    row.append(left, b);
    return row;
  }

  function renderEstimate() {
    const q = quote();
    $('totalPrice').textContent = money(q.total);
    $('totalDetails').textContent = state.items.length
      ? `${state.items.length} окон · ${num(q.area)} м² · ${num(q.perimeter)} м канта`
      : 'Добавьте окна';
    const meta = $('printMeta');
    meta.replaceChildren();
    const metaTitle = document.createElement('b');
    metaTitle.textContent = state.orderName || 'Замер мягких окон';
    meta.append(metaTitle);
    if (state.customer) {
      const metaCustomer = document.createElement('div');
      metaCustomer.textContent = 'Клиент: ' + state.customer;
      meta.append(metaCustomer);
    }
    const target = $('estimateLines');
    target.replaceChildren();
    if (!state.items.length) {
      const p = document.createElement('div');
      p.className = 'muted';
      p.style.padding = '14px 0';
      p.textContent = 'Смета появится после добавления окон.';
      target.append(p);
      return;
    }
    target.append(
      line('Полотно', `${num(q.area)} м²`, q.material),
      line('Кант', `${num(q.perimeter)} м`, q.edge),
      line('Люверсы', `${num(q.eyeletCount, 0)} шт`, q.eyeletCost),
    );
    if (q.fastenerCount > 0) target.append(line('Крепёж', `${num(q.fastenerCount, 0)} шт`, q.fastenerCost));
    if (q.zipperLength > 0) target.append(line('Молния', `${num(q.zipperLength)} м`, q.zipperCost));
    if (state.install) target.append(line('Монтаж', `${num(q.area)} м²`, q.install));
  }

  function renderAll() {
    renderLists();
    renderEstimate();
    updatePreview();
    save();
  }

  function resetForm() {
    editing = null;
    editId.value = '';
    widthInput.value = '1500';
    heightInput.value = '2500';
    qtyInput.value = '1';
    zipperInput.checked = false;
    selectedType = 'fixed';
    selectedMaterial = 'pvc';
    document.querySelectorAll('[data-type]').forEach((b) => b.classList.toggle('active', b.dataset.type === selectedType));
    document.querySelectorAll('[data-material]').forEach((b) => b.classList.toggle('active', b.dataset.material === selectedMaterial));
    addBtn.textContent = 'Добавить окно';
    cancelEdit.hidden = true;
    updatePreview();
  }

  function startEdit(id) {
    const item = state.items.find((x) => x.id === id);
    if (!item) return;
    editing = id;
    editId.value = id;
    widthInput.value = String(item.w);
    heightInput.value = String(item.h);
    qtyInput.value = String(item.qty);
    zipperInput.checked = Boolean(item.zipper);
    selectedType = item.type === 'lifting' ? 'lifting' : 'fixed';
    selectedMaterial = MATERIAL_LABEL[item.material] ? item.material : 'pvc';
    document.querySelectorAll('[data-type]').forEach((b) => b.classList.toggle('active', b.dataset.type === selectedType));
    document.querySelectorAll('[data-material]').forEach((b) => b.classList.toggle('active', b.dataset.material === selectedMaterial));
    addBtn.textContent = 'Сохранить окно';
    cancelEdit.hidden = false;
    switchView('measureView');
    window.scrollTo({ top: 0, behavior: 'smooth' });
    updatePreview();
  }

  function removeItem(id) {
    state.items = state.items.filter((x) => x.id !== id);
    if (editing === id) resetForm();
    renderAll();
    toast('Окно удалено');
  }

  function newId() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    return 'w' + Date.now() + Math.random().toString(16).slice(2);
  }

  function validate(value, min, max) {
    const n = Number(value);
    return Number.isFinite(n) && n >= min && n <= max ? n : null;
  }

  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const w = validate(widthInput.value, 300, 6000);
    const h = validate(heightInput.value, 300, 6000);
    const qty = Math.max(1, Math.min(50, Number(qtyInput.value) || 1));
    if (w === null || h === null) {
      toast('Ширина и высота — от 300 до 6000 мм');
      return;
    }
    const item = {
      id: editing || newId(),
      w,
      h,
      type: selectedType,
      material: selectedMaterial,
      qty,
      zipper: zipperInput.checked,
    };
    if (editing) {
      state.items = state.items.map((x) => (x.id === editing ? item : x));
      toast('Окно сохранено');
    } else {
      state.items.push(item);
      toast('Окно добавлено');
    }
    resetForm();
    renderAll();
  });

  cancelEdit.addEventListener('click', () => {
    resetForm();
    toast('Редактирование отменено');
  });

  document.querySelectorAll('[data-type]').forEach((button) => {
    button.addEventListener('click', () => {
      selectedType = button.dataset.type;
      document.querySelectorAll('[data-type]').forEach((b) => b.classList.toggle('active', b === button));
      updatePreview();
    });
  });

  document.querySelectorAll('[data-material]').forEach((button) => {
    button.addEventListener('click', () => {
      selectedMaterial = button.dataset.material;
      document.querySelectorAll('[data-material]').forEach((b) => b.classList.toggle('active', b === button));
      updatePreview();
    });
  });

  $('minusQty').addEventListener('click', () => {
    qtyInput.value = String(Math.max(1, (Number(qtyInput.value) || 1) - 1));
    updatePreview();
  });
  $('plusQty').addEventListener('click', () => {
    qtyInput.value = String(Math.min(50, (Number(qtyInput.value) || 1) + 1));
    updatePreview();
  });

  [widthInput, heightInput, qtyInput].forEach((input) => input.addEventListener('input', updatePreview));
  zipperInput.addEventListener('change', updatePreview);

  $('orderName').addEventListener('input', (e) => { state.orderName = e.target.value; save(); renderEstimate(); });
  $('customer').addEventListener('input', (e) => { state.customer = e.target.value; save(); });
  $('install').addEventListener('change', (e) => { state.install = e.target.checked; renderAll(); });

  document.querySelectorAll('[data-view]').forEach((button) => {
    button.addEventListener('click', () => switchView(button.dataset.view));
  });

  function switchView(id) {
    document.querySelectorAll('.view').forEach((view) => view.classList.toggle('active', view.id === id));
    document.querySelectorAll('[data-view]').forEach((button) => button.classList.toggle('active', button.dataset.view === id));
    if (id === 'estimateView') {
      requestAnimationFrame(() => {
        resizeCanvas();
        if (state.signature) restoreSignature();
      });
    }
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function toast(text) {
    const el = $('toast');
    el.textContent = text;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('show'), 2200);
  }

  function openSettings() {
    const map = { pricePvc: 'pvc', priceTinted: 'tinted', priceScreen: 'screen', priceEdge: 'edge', priceEyelet: 'eyelet', priceFastener: 'fastener', priceZipper: 'zipper', priceInstall: 'install' };
    for (const [id, key] of Object.entries(map)) $(id).value = String(state.prices[key]);
    const dialog = $('settingsDialog');
    if (typeof dialog.showModal === 'function') dialog.showModal();
    else dialog.setAttribute('open', '');
  }

  $('settingsBtn').addEventListener('click', openSettings);
  $('saveSettings').addEventListener('click', (event) => {
    event.preventDefault();
    const map = { pricePvc: 'pvc', priceTinted: 'tinted', priceScreen: 'screen', priceEdge: 'edge', priceEyelet: 'eyelet', priceFastener: 'fastener', priceZipper: 'zipper', priceInstall: 'install' };
    for (const [id, key] of Object.entries(map)) {
      const value = Number($(id).value);
      state.prices[key] = Number.isFinite(value) && value >= 0 ? value : DEFAULT_PRICES[key];
    }
    save();
    renderAll();
    $('settingsDialog').close();
    toast('Цены сохранены');
  });

  function quoteText() {
    const q = quote();
    const lines = [
      state.orderName ? `Заказ: ${state.orderName}` : 'Заказ: мягкие окна',
      state.customer ? `Клиент: ${state.customer}` : '',
      `Окон: ${state.items.length}, площадь ${num(q.area)} м²`,
      `Итого: ${money(q.total)}`,
      'Смета сформирована в «Мягкие окна Excl».',
    ];
    return lines.filter(Boolean).join('\n');
  }

  $('shareBtn').addEventListener('click', async () => {
    const text = quoteText();
    try {
      if (navigator.share) await navigator.share({ title: 'Смета — мягкие окна', text });
      else {
        await navigator.clipboard.writeText(text);
        toast('Смета скопирована');
      }
    } catch (e) { toast('Не удалось отправить'); }
  });

  $('printBtn').addEventListener('click', () => {
    if (!state.items.length) { toast('Сначала добавьте окна'); return; }
    window.print();
  });

  // Подпись пальцем: canvas с высоким DPI и сохранением между открытиями.
  const canvas = $('signature');
  const ctx = canvas.getContext('2d');
  let drawing = false;
  let last = null;
  let signatureDirty = false;

  function resizeCanvas() {
    const rect = canvas.getBoundingClientRect();
    if (!rect.width) return;
    const dpr = Math.min(window.devicePixelRatio || 1, 2.5);
    const old = canvas.width ? canvas.toDataURL('image/png') : null;
    canvas.width = Math.round(rect.width * dpr);
    canvas.height = Math.round(rect.height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.lineWidth = 2.3;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = '#16202e';
    if (old) {
      const img = new Image();
      img.onload = () => ctx.drawImage(img, 0, 0, rect.width, rect.height);
      img.src = old;
    }
  }

  function pointFrom(event) {
    const rect = canvas.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  }

  canvas.addEventListener('pointerdown', (event) => {
    event.preventDefault();
    drawing = true;
    signatureDirty = true;
    last = pointFrom(event);
    canvas.setPointerCapture?.(event.pointerId);
    ctx.beginPath();
    ctx.moveTo(last.x, last.y);
  });
  canvas.addEventListener('pointermove', (event) => {
    if (!drawing || !last) return;
    event.preventDefault();
    const p = pointFrom(event);
    ctx.lineTo(p.x, p.y);
    ctx.stroke();
    last = p;
  });
  const stopDraw = () => {
    if (!drawing) return;
    drawing = false;
    last = null;
    state.signature = canvas.toDataURL('image/png');
    save();
  };
  canvas.addEventListener('pointerup', stopDraw);
  canvas.addEventListener('pointercancel', stopDraw);
  canvas.addEventListener('pointerleave', stopDraw);

  $('clearSignature').addEventListener('click', () => {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    state.signature = '';
    signatureDirty = false;
    save();
  });

  function restoreSignature() {
    if (!state.signature) return;
    const img = new Image();
    img.onload = () => {
      const rect = canvas.getBoundingClientRect();
      if (!rect.width) return;
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.drawImage(img, 0, 0, rect.width, rect.height);
    };
    img.src = state.signature;
  }

  window.addEventListener('resize', () => {
    if (!signatureDirty) resizeCanvas();
  });

  // Установка PWA: Android/Chrome — системный prompt, iPhone — подсказка.
  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    deferredInstall = event;
    $('installBtn').hidden = false;
  });
  $('installBtn').addEventListener('click', async () => {
    if (!deferredInstall) return;
    deferredInstall.prompt();
    await deferredInstall.userChoice;
    deferredInstall = null;
    $('installBtn').hidden = true;
  });
  function isStandalone() {
    return window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
  }
  function showIosHint() {
    if (isStandalone()) return;
    const ua = navigator.userAgent || '';
    const ios = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    if (!ios) return;
    try { if (localStorage.getItem('okna_ios_hint_seen') === '1') return; } catch (e) {}
    $('iosHint').hidden = false;
  }
  $('iosHintClose').addEventListener('click', () => {
    $('iosHint').hidden = true;
    try { localStorage.setItem('okna_ios_hint_seen', '1'); } catch (e) {}
  });

  if ('serviceWorker' in navigator && location.protocol.startsWith('http')) {
    navigator.serviceWorker.register('/pwa/sw.js', { scope: '/pwa/' }).catch(() => {});
  }

  load();
  resetForm();
  renderAll();
  requestAnimationFrame(() => {
    resizeCanvas();
    restoreSignature();
  });
  showIosHint();
})();
