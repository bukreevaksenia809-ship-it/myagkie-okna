(() => {
  const cfg = window.OKNA_CONFIG || {};
  const project = cfg.projectId || 'okna-7dbf8';
  const apiKey = cfg.apiKey || '';
  const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
  const $ = (id) => document.getElementById(id);
  let secret = localStorage.getItem('okna_admin_key') || cfg.secret || '';
  let devices = [];
  let licenses = [];

  function valueOf(v) {
    if (!v) return null;
    if ('stringValue' in v) return v.stringValue;
    if ('integerValue' in v) return Number(v.integerValue);
    if ('doubleValue' in v) return Number(v.doubleValue);
    if ('booleanValue' in v) return v.booleanValue;
    if ('timestampValue' in v) return v.timestampValue;
    if ('nullValue' in v) return null;
    if ('arrayValue' in v) return (v.arrayValue.values || []).map(valueOf);
    if ('mapValue' in v) {
      const out = {};
      for (const [k, item] of Object.entries(v.mapValue.fields || {})) out[k] = valueOf(item);
      return out;
    }
    return null;
  }

  function dataOf(doc) {
    const out = {};
    for (const [k, v] of Object.entries(doc.fields || {})) out[k] = valueOf(v);
    return out;
  }

  async function query(collectionId, parent, key, field = 'key') {
    const root = parent ? `${base}/${parent}` : base;
    const url = `${root}:runQuery?key=${apiKey}`;
    const body = {
      structuredQuery: {
        from: [{ collectionId, ...(parent ? { allDescendants: false } : {}) }],
        where: {
          fieldFilter: {
            field: { fieldPath: field },
            op: 'EQUAL',
            value: { stringValue: key },
          },
        },
      },
    };
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`query ${res.status}`);
    const json = await res.json();
    return json.filter((item) => item.document).map((item) => item.document);
  }

  async function getDoc(path) {
    const res = await fetch(`${base}/${path}?key=${apiKey}`);
    if (!res.ok) return null;
    return dataOf(await res.json());
  }

  async function patchDoc(path, fields, mask = null) {
    const body = { fields };
    const query = mask
      ? mask.map((field) => `&updateMask.fieldPaths=${encodeURIComponent(field)}`).join('')
      : '';
    const res = await fetch(`${base}/${path}?key=${apiKey}${query}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`save ${res.status}`);
    return res.json();
  }

  const s = (v) => ({ stringValue: String(v ?? '') });
  const b = (v) => ({ booleanValue: !!v });
  const arr = (items) => ({ arrayValue: { values: items.map((x) => s(x)) } });

  function fmtDate(value) {
    if (!value) return '—';
    const date = new Date(value);
    return isNaN(date) ? value : date.toLocaleString('ru-RU');
  }

  function isOnline(value) {
    if (!value) return false;
    return Date.now() - new Date(value).getTime() < 24 * 3600 * 1000;
  }

  function renderDevices() {
    devices.sort((a, b) => String(b.lastSeen || '').localeCompare(String(a.lastSeen || '')));
    $('stat-count').textContent = devices.length;
    $('stat-online').textContent = devices.filter((d) => isOnline(d.lastSeen)).length;
    $('stat-version').textContent =
      devices.map((d) => d.version).filter(Boolean).sort().pop() || '—';
    const body = $('devices-body');
    body.innerHTML = '';
    for (const device of devices) {
      const tr = document.createElement('tr');
      const files = Array.isArray(device.device?.files) ? device.device.files.length : 0;
      tr.innerHTML = `
        <td><span class="dot ${isOnline(device.lastSeen) ? 'on' : ''}"></span>${escapeHtml(device.installId || '')}</td>
        <td>${escapeHtml(device.version || '')}</td>
        <td>${fmtDate(device.lastSeen)}</td>
        <td>${device.windowCount ?? '—'}</td>
        <td>${files}</td>
        <td>${escapeHtml(device.device?.hostname || '')}</td>`;
      tr.addEventListener('click', () => showDevice(device));
      body.appendChild(tr);
    }
  }

  function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, (ch) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[ch]));
  }

  function pretty(value) {
    try {
      return JSON.stringify(typeof value === 'string' ? JSON.parse(value) : value, null, 2);
    } catch {
      return String(value ?? '');
    }
  }

  function showDevice(device) {
    $('device-detail').classList.remove('hidden');
    $('detail-title').textContent = device.installId || 'Устройство';
    const info = device.device || {};
    const files = Array.isArray(info.files) ? info.files : [];
    const rows = [
      ['Версия', device.version],
      ['Первый запуск', fmtDate(device.firstSeen)],
      ['Последний запуск', fmtDate(device.lastSeen)],
      ['Окон в заказе', device.windowCount],
      ['ПК', info.hostname],
      ['ОС', `${info.os || ''} ${info.osVersion || ''}`],
      ['Папка', info.appDir],
      ['Файлов рядом', `${info.filesCount ?? files.length}, ${(info.filesBytes || 0) / 1024 / 1024 | 0} МБ`],
    ];
    const html = rows.map(([k, v]) => `<dt>${escapeHtml(k)}</dt><dd>${escapeHtml(v ?? '—')}</dd>`).join('');
    const filesHtml = files.slice(0, 300).map((f) =>
      `<tr><td>${escapeHtml(f.path)}</td><td>${(f.size / 1024).toFixed(1)} КБ</td><td>${fmtDate(f.modified)}</td></tr>`).join('');
    $('detail-body').innerHTML = `
      <dl>${html}</dl>
      <h3>Параметры выбранного окна</h3>
      <pre>${escapeHtml(pretty(device.selectedParams))}</pre>
      <h3>Заказ</h3>
      <pre>${escapeHtml(pretty(device.order))}</pre>
      <h3>Файлы рядом с приложением</h3>
      <div class="table-wrap"><table><thead><tr><th>Файл</th><th>Размер</th><th>Изменён</th></tr></thead><tbody>${filesHtml}</tbody></table></div>`;
  }

  async function loadDevices() {
    if (!secret) return;
    try {
      const docs = await query('installations', null, secret);
      devices = docs.map((doc) => ({ id: doc.name.split('/').pop(), ...dataOf(doc) }));
      renderDevices();
    } catch (error) {
      console.error(error);
    }
  }

  async function loadEvents() {
    const install = $('events-install').value.trim();
    if (!secret || !install) return;
    const docs = await query('events', `installations/${install}`, secret);
    docs.sort((a, b) => String(valueOf(b.fields?.at)).localeCompare(String(valueOf(a.fields?.at))));
    const list = $('events-list');
    list.innerHTML = '';
    for (const doc of docs.slice(0, 200)) {
      const data = dataOf(doc);
      const row = document.createElement('div');
      row.className = 'event';
      row.innerHTML = `<time>${fmtDate(data.at)}</time><b>${escapeHtml(data.type)}</b><pre>${escapeHtml(pretty(data.data))}</pre>`;
      list.appendChild(row);
    }
  }

  async function loadRelease() {
    const data = await getDoc('config/app');
    if (!data) return;
    $('rel-version').value = data.latestVersion || '';
    $('rel-url').value = data.url || '';
    $('rel-sha').value = data.sha256 || '';
    $('rel-notes').value = data.notes || '';
    $('rel-all').checked = data.rolloutAll !== false;
    $('rel-ids').value = Array.isArray(data.rollout) ? data.rollout.join(', ') : '';
    $('rel-enabled').checked = data.enabled !== false;
    $('rel-auto').checked = data.autoUpdate === true;
    $('release-current').textContent = JSON.stringify(data, null, 2);
  }

  async function saveRelease() {
    const ids = $('rel-ids').value.split(',').map((x) => x.trim()).filter(Boolean);
    try {
      await patchDoc('config/app', {
        adminKey: s(secret),
        latestVersion: s($('rel-version').value.trim()),
        url: s($('rel-url').value.trim()),
        sha256: s($('rel-sha').value.trim()),
        notes: s($('rel-notes').value.trim()),
        rolloutAll: b($('rel-all').checked),
        rollout: arr(ids),
        enabled: b($('rel-enabled').checked),
        autoUpdate: b($('rel-auto').checked),
      });
      $('release-status').textContent = 'Опубликовано. Клиенты увидят обновление при следующей проверке.';
      loadRelease();
    } catch (error) {
      $('release-status').textContent = `Ошибка: ${error.message}`;
    }
  }


  function generateKey() {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    const group = () =>
      Array.from({ length: 4 }, () =>
        alphabet[Math.floor(Math.random() * alphabet.length)]).join('');
    return [group(), group(), group(), group()].join('-');
  }

  async function ensureLicenseDoc(key, fields) {
    const res = await fetch(`${base}/licenses/${key}?key=${apiKey}`);
    if (res.status === 200) return false;
    await patchDoc(`licenses/${key}`, fields);
    return true;
  }

  async function createKey() {
    const type = $('key-type').value;
    const count = Math.max(1, Number($('key-count').value) || 1);
    const key = generateKey();
    try {
      const ok = await ensureLicenseDoc(key, {
        adminKey: s(secret),
        licenseKey: s(key),
        type: s(type),
        maxActivations: { integerValue: String(type === 'single' ? 1 : count) },
        activationsCount: { integerValue: '0' },
        enabled: b(true),
        note: s($('key-note').value.trim()),
        createdAt: { timestampValue: new Date().toISOString() },
      });
      $('key-status').textContent = ok
        ? `Ключ создан: ${key}`
        : 'Такой ключ уже есть, попробуйте ещё раз';
      loadKeys();
    } catch (error) {
      $('key-status').textContent = `Ошибка: ${error.message}`;
    }
  }

  async function loadKeys() {
    if (!secret) return;
    try {
      const docs = await query('licenses', null, secret, 'adminKey');
      licenses = docs.map((doc) => ({ id: doc.name.split('/').pop(), ...dataOf(doc) }));
      licenses.sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));
      const body = $('keys-body');
      body.innerHTML = '';
      for (const item of licenses) {
        const tr = document.createElement('tr');
        const used = item.activationsCount ?? 0;
        const max = item.maxActivations ?? 1;
        tr.innerHTML = `
          <td><b>${escapeHtml(item.id)}</b></td>
          <td>${item.type === 'single' ? 'одноразовый' : 'многоразовый'}</td>
          <td>${used} / ${max}</td>
          <td>${item.enabled === false ? '<span style="color:#ef6b6b">выключен</span>' : '<span style="color:#38c172">активен</span>'}</td>
          <td>${fmtDate(item.createdAt)}</td>
          <td></td>`;
        const actions = tr.lastElementChild;
        const copy = document.createElement('button');
        copy.textContent = 'Копировать';
        copy.className = 'ghost';
        copy.onclick = (event) => {
          event.stopPropagation();
          navigator.clipboard?.writeText(item.id);
        };
        const toggle = document.createElement('button');
        toggle.textContent = item.enabled === false ? 'Включить' : 'Выключить';
        toggle.onclick = async (event) => {
          event.stopPropagation();
          try {
            await patchDoc(
              `licenses/${item.id}`,
              {
                adminKey: s(secret),
                enabled: b(item.enabled === false),
              },
              ['adminKey', 'enabled'],
            );
            loadKeys();
          } catch (error) {
            $('key-status').textContent = `Ошибка: ${error.message}`;
          }
        };
        const remove = document.createElement('button');
        remove.textContent = 'Удалить';
        remove.onclick = async (event) => {
          event.stopPropagation();
          if (!confirm(`Удалить ключ ${item.id}?`)) return;
          await fetch(`${base}/licenses/${item.id}?key=${apiKey}`, { method: 'DELETE' });
          loadKeys();
        };
        actions.append(copy, toggle, remove);
        tr.addEventListener('click', () => showKeyActivations(item));
        body.appendChild(tr);
      }
    } catch (error) {
      $('key-status').textContent = `Ошибка: ${error.message}`;
    }
  }

  async function showKeyActivations(item) {
    $('key-detail').classList.remove('hidden');
    $('key-detail-title').textContent = `Активации: ${item.id}`;
    const docs = await query('activations', `licenses/${item.id}`, secret, 'adminKey');
    const rows = docs.map((doc) => {
      const data = dataOf(doc);
      return `<tr><td>${escapeHtml(data.installId)}</td><td>${escapeHtml(data.device?.hostname || '')}</td><td>${fmtDate(data.activatedAt)}</td><td>${fmtDate(data.lastSeen)}</td></tr>`;
    }).join('');
    $('key-detail-body').innerHTML = `
      <p class="hint">Занято ${item.activationsCount ?? 0} из ${item.maxActivations ?? 1}.</p>
      <div class="table-wrap"><table><thead><tr><th>installId</th><th>ПК</th><th>Активирован</th><th>Последний запуск</th></tr></thead><tbody>${rows}</tbody></table></div>`;
  }

  function enter() {
    const value = $('secret').value.trim();
    if (!value) return;
    secret = value;
    localStorage.setItem('okna_admin_key', value);
    $('gate').classList.add('hidden');
    $('app').classList.remove('hidden');
    loadDevices();
    loadRelease();
  }

  function logout() {
    localStorage.removeItem('okna_admin_key');
    secret = '';
    $('app').classList.add('hidden');
    $('gate').classList.remove('hidden');
    $('secret').value = '';
  }

  function switchTab(name) {
    for (const tab of document.querySelectorAll('.tabs button')) {
      tab.classList.toggle('active', tab.dataset.tab === name);
    }
    for (const id of ['devices', 'events', 'keys', 'release']) {
      $(id).classList.toggle('hidden', id !== name);
    }
    if (name === 'release') loadRelease();
    if (name === 'keys') loadKeys();
  }

  document.addEventListener('DOMContentLoaded', () => {
    $('enter').addEventListener('click', enter);
    $('logout').addEventListener('click', logout);
    $('refresh').addEventListener('click', loadDevices);
    $('close-detail').addEventListener('click', () => $('device-detail').classList.add('hidden'));
    $('load-events').addEventListener('click', loadEvents);
    $('save-release').addEventListener('click', saveRelease);
    $('create-key').addEventListener('click', createKey);
    $('close-key-detail').addEventListener('click', () => $('key-detail').classList.add('hidden'));
    for (const tab of document.querySelectorAll('.tabs button')) {
      tab.addEventListener('click', () => switchTab(tab.dataset.tab));
    }
    $('secret').value = secret;
    if (secret) enter();
    setInterval(() => {
      if (!$('app').classList.contains('hidden') && !$('devices').classList.contains('hidden')) {
        loadDevices();
      }
    }, 30000);
  });
})();
