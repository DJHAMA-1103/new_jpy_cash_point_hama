'use strict';

const APPS = [
  { id: 'paypay', name: 'PayPay', mark: 'P', kind: 'お支払い' },
  { id: 'rakuten', name: '楽天ペイ', mark: 'R', kind: 'お支払い' },
  { id: 'vpoint', name: 'Vポイント', mark: 'V', kind: 'ポイント' },
  { id: 'dpoint', name: 'dポイント', mark: 'd', kind: 'ポイント' },
  { id: 'suica', name: 'Suica', mark: 'Su', kind: 'お支払い' },
  { id: 'waon', name: 'WAON', mark: 'WA', kind: 'お支払い' }
];
const PLACES = [
  { id: 'market', name: 'こもれびマルシェ', area: '吉祥寺本町 · スーパー', icon: 'store', x: 29, y: 37 },
  { id: 'drug', name: 'みどり薬局', area: '吉祥寺東町 · ドラッグストア', icon: 'cross', x: 71, y: 52 },
  { id: 'coffee', name: '喫茶 余白', area: '吉祥寺南町 · カフェ', icon: 'coffee', x: 25, y: 75 },
  { id: 'daily', name: 'ひだまりストア', area: '吉祥寺本町 · コンビニ', icon: 'store', x: 73, y: 32 },
  { id: 'bread', name: 'パンと日々', area: '吉祥寺南町 · ベーカリー', icon: 'store', x: 65, y: 78 }
];
const STORAGE_KEY = 'point-home-design-v1';
const clone = value => JSON.parse(JSON.stringify(value));
const initialState = () => ({ version: 1, apps: ['paypay', 'rakuten', 'vpoint', 'dpoint'], places: [
  { ...PLACES[0], apps: ['paypay', 'vpoint'] },
  { ...PLACES[1], apps: ['rakuten', 'dpoint'] },
  { ...PLACES[2], apps: ['paypay'] }
] });
const emptyState = () => ({ version: 1, apps: [], places: [] });
const appById = id => APPS.find(app => app.id === id);
const escapeHTML = text => String(text).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const icon = name => `<svg aria-hidden="true"><use href="#i-${name}"/></svg>`;
const appLogo = id => { const app = appById(id); return `<span class="app-logo ${app.id}" aria-hidden="true">${app.mark}</span>`; };
const appChips = ids => ids.map(id => `<span class="app-chip">${appLogo(id)}${appById(id).name}</span>`).join('');

function validateState(value) {
  if (!value || value.version !== 1 || !Array.isArray(value.apps) || !Array.isArray(value.places)) return false;
  if (value.apps.length > APPS.length || new Set(value.apps).size !== value.apps.length || value.apps.some(id => !appById(id))) return false;
  if (value.places.length > 100 || new Set(value.places.map(place => place && place.id)).size !== value.places.length) return false;
  return value.places.every(place => place && typeof place.id === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(place.id)
    && typeof place.name === 'string' && place.name.trim().length > 0 && place.name.length <= 50
    && typeof place.area === 'string' && place.area.length <= 100
    && ['store', 'cross', 'coffee', 'pin'].includes(place.icon)
    && Number.isFinite(place.x) && place.x >= 10 && place.x <= 90
    && Number.isFinite(place.y) && place.y >= 25 && place.y <= 85
    && Array.isArray(place.apps) && place.apps.length <= APPS.length
    && new Set(place.apps).size === place.apps.length && place.apps.every(id => value.apps.includes(id)));
}

let loadWarning = '';
let state;
try {
  const saved = localStorage.getItem(STORAGE_KEY);
  if (saved === null) state = initialState();
  else {
    const parsed = JSON.parse(saved);
    if (!validateState(parsed)) throw new Error('invalid saved data');
    state = parsed;
  }
} catch {
  state = initialState();
  loadWarning = '保存内容を読み込めなかったため、サンプルを表示しています。';
}

let demo = 'saved';
let firstTimeState = emptyState();
let activeTab = 'places';
let selectedPlace = state.places[0]?.id || null;
let draft = null;
let opener = null;
let toastTimer;
const $ = selector => document.querySelector(selector);
const dialog = $('#dialog');
const data = () => demo === 'empty' ? firstTimeState : state;

function toast(message) {
  clearTimeout(toastTimer);
  $('#toast').textContent = message;
  $('#toast').classList.add('show');
  toastTimer = setTimeout(() => $('#toast').classList.remove('show'), 5200);
}

function save(next, message) {
  if (!validateState(next)) { toast('保存できませんでした。登録内容を確認してください。'); return false; }
  if (demo === 'empty') firstTimeState = next;
  else {
    // Keep edits usable if this browser forbids file:// storage; never claim persistence succeeded.
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(next)); }
    catch { toast('保存できませんでした。ブラウザの保存設定をご確認ください。'); return false; }
    state = next;
  }
  render();
  toast(demo === 'empty' ? `${message}（はじめて表示内）` : message);
  return true;
}

function render() {
  const current = data();
  $('#place-count').textContent = current.places.length;
  $('#app-count').textContent = current.apps.length;
  $('#section-title').textContent = activeTab === 'places' ? '登録した場所' : 'マイアプリ';
  document.querySelectorAll('[data-tab]').forEach(button => {
    const selected = button.dataset.tab === activeTab;
    button.setAttribute('aria-selected', String(selected));
    button.tabIndex = selected ? 0 : -1;
  });
  $('#list-panel').setAttribute('aria-labelledby', activeTab === 'places' ? 'places-tab' : 'apps-tab');
  $('#add').setAttribute('aria-label', activeTab === 'places' ? '場所を登録' : 'アプリを登録');
  $('#you-dot').hidden = demo === 'denied';
  const hint = $('#management-hint');
  hint.classList.toggle('denied', demo === 'denied');
  hint.innerHTML = demo === 'denied'
    ? `${icon('pin')}<span>位置情報はオフ。場所は手動で登録できます。</span>`
    : `${icon('bell')}<span>${activeTab === 'places' ? '場所ごとに、知らせてほしいアプリを登録。' : '使っているアプリを選んで、場所につなげよう。'}</span>`;
  $('#map-pins').innerHTML = current.places.map(place => `<button class="map-pin ${place.id === selectedPlace ? 'selected' : ''}" style="left:${place.x}%;top:${place.y}%" data-pin="${escapeHTML(place.id)}" aria-label="${escapeHTML(place.name)}を選択" aria-pressed="${place.id === selectedPlace}"><span class="map-pin-inner">${icon(place.icon)}${escapeHTML(place.name)}</span></button>`).join('');
  if (activeTab === 'places') {
    $('#list-panel').innerHTML = current.places.length ? current.places.map(place => `
      <button class="place-card ${place.id === selectedPlace ? 'selected' : ''}" data-edit-place="${escapeHTML(place.id)}" aria-label="${escapeHTML(place.name)}の登録を編集">
        <div class="place-heading"><span class="place-icon">${icon(place.icon)}</span><div class="place-heading-text"><h3>${escapeHTML(place.name)}</h3><p>${escapeHTML(place.area)}</p></div><svg class="row-chevron" aria-hidden="true"><use href="#i-arrow"/></svg></div>
        <div class="linked-apps">${place.apps.length ? appChips(place.apps) : '<span class="no-links">アプリ未登録 · 編集して追加</span>'}</div>
      </button>`).join('') : `<div class="empty-state"><div class="empty-icon">${icon('pin')}</div><h3>いつもの場所から、はじめよう。</h3><p>お店と、そこで使うアプリを選ぶだけ。<br>あなたのお買い物に合う組み合わせを。</p><button class="primary" data-action="add-place">${icon('plus')}はじめての場所を登録</button></div>`;
  } else {
    $('#list-panel').innerHTML = current.apps.length ? current.apps.map(id => {
      const app = appById(id);
      const count = current.places.filter(place => place.apps.includes(id)).length;
      return `<button class="app-row" data-app-detail="${id}" aria-label="${app.name}の登録を確認">${appLogo(id)}<span><strong>${app.name}</strong><small>${app.kind} · ${count ? `${count}か所に登録` : 'まだ場所に未登録'}</small></span>${icon('arrow')}</button>`;
    }).join('') : `<div class="empty-state"><div class="empty-icon">${icon('grid')}</div><h3>使っているアプリを、ここに。</h3><p>お支払いも、ポイントも。<br>自分のアプリを選んで登録しましょう。</p><button class="primary" data-action="add-app">${icon('plus')}アプリを追加</button></div>`;
  }
}

function showDialog(html) {
  $('#dialog-content').innerHTML = html;
  if (!dialog.open) {
    opener = document.activeElement;
    dialog.showModal();
  }
  const heading = $('#dialog-title');
  if (heading) { heading.tabIndex = -1; heading.focus({ preventScroll: true }); }
}

function dialogTitle(eyebrow, title, description = '') {
  return `<p class="dialog-eyebrow">${eyebrow}</p><h2 id="dialog-title">${title}</h2>${description ? `<p class="description">${description}</p>` : ''}`;
}

function beginPlace() {
  draft = { editing: false, place: null, apps: [] };
  placePicker();
}

function placePicker() {
  showDialog(`${dialogTitle('STEP 01 / PLACE', 'いつもの場所を選ぶ', '検索して選ぶか、地図のサンプルに自分の場所を追加できます。')}
    <label class="visually-hidden" for="place-search">場所を検索</label><input type="search" id="place-search" placeholder="場所の名前で検索" maxlength="50" autocomplete="off">
    <div class="choice-list" id="place-options"></div><button class="text-button full-width" data-action="custom-place">見つからない場所を自分で追加</button><p class="dialog-note">表示されるお店はすべて架空のサンプルです。</p>`);
  filterPlaces('');
}

function filterPlaces(query) {
  const normalized = query.trim().toLocaleLowerCase('ja');
  const available = PLACES.filter(place => !data().places.some(saved => saved.id === place.id));
  const matches = available.filter(place => `${place.name} ${place.area}`.toLocaleLowerCase('ja').includes(normalized));
  $('#place-options').innerHTML = matches.length ? matches.map(place => `<button class="choice" data-pick-place="${place.id}"><span class="place-icon">${icon(place.icon)}</span><span><strong>${place.name}</strong><small>${place.area}</small></span>${icon('arrow')}</button>`).join('') : '<p class="dialog-note">一致する未登録の場所がありません。自分で場所を追加できます。</p>';
}

function customPlace() {
  showDialog(`${dialogTitle('STEP 01 / PLACE', '場所を自分で追加', '場所の名前を入力し、サンプル地図上の位置を確認してください。')}
    <form id="custom-place-form"><label class="field-label" for="custom-name">場所の名前</label><input type="text" id="custom-name" maxlength="50" required placeholder="例：いつものスーパー" autocomplete="off">
    <label class="field-label">登録する位置</label><button type="button" class="mini-map" id="custom-map" aria-label="サンプル地図上の位置を変更">${icon('pin')}<span>タップして位置を変更 · サンプル</span></button>
    <p class="dialog-note">実際の地図・住所には反映されません。</p><div class="dialog-actions"><button type="button" class="secondary" data-action="back-places">戻る</button><button type="submit" class="primary">アプリを選ぶ</button></div><p class="form-error" id="form-error" role="alert"></p></form>`);
  draft.coordinates = { x: 50, y: 50 };
}

function appPicker() {
  const label = draft.editing ? 'EDIT / CONNECTIONS' : 'STEP 02 / APPS';
  showDialog(`${dialogTitle(label, draft.editing ? '登録アプリを編集' : '知らせてほしいアプリは？', `<strong>${escapeHTML(draft.place.name)}</strong> に関連付けるアプリを選びます。`)}
    <form id="apps-form"><div class="choice-list">${APPS.map(app => `<label class="choice">${appLogo(app.id)}<span><strong>${app.name}</strong><small>${app.kind}${data().apps.includes(app.id) ? ' · マイアプリ' : ' · マイアプリにも追加'}</small></span><input type="checkbox" name="linked-app" value="${app.id}" ${draft.apps.includes(app.id) ? 'checked' : ''}></label>`).join('')}</div>
    <p class="dialog-note">あなたが使うアプリの組み合わせです。店舗の対応状況は確認していません。</p><div class="dialog-actions"><button type="button" class="secondary" data-action="${draft.editing ? 'close' : 'back-places'}">${draft.editing ? 'キャンセル' : '戻る'}</button><button type="submit" class="primary">内容を確認</button></div><p class="form-error" id="form-error" role="alert"></p></form>
    ${draft.editing ? '<button class="text-button delete-link full-width" data-action="delete-place">この場所の登録を削除</button>' : ''}`);
}

function confirmPlace() {
  showDialog(`${dialogTitle('LAST STEP / CONFIRM', draft.editing ? 'この内容に変更しますか？' : 'この組み合わせを登録', 'いつでもホームから見直せます。')}
    <div class="confirmation-card"><h3>${escapeHTML(draft.place.name)}</h3><p>${escapeHTML(draft.place.area)}</p><div class="linked-apps">${appChips(draft.apps)}</div></div>
    <p class="dialog-note">到着時に案内するための登録です。このサンプルでは実際の通知は届きません。</p><div class="dialog-actions"><button class="secondary" data-action="back-apps">戻る</button><button class="primary" data-action="save-place">${icon('check')}保存する</button></div>`);
}

function savePlace() {
  const next = clone(data());
  const place = { ...draft.place, apps: [...draft.apps] };
  next.apps = [...new Set([...next.apps, ...draft.apps])];
  const index = next.places.findIndex(existing => existing.id === place.id);
  if (index >= 0) next.places[index] = place;
  else next.places.push(place);
  const priorTab = activeTab;
  activeTab = 'places';
  if (save(next, '場所とアプリを保存しました。')) { selectedPlace = place.id; render(); dialog.close(); }
  else { activeTab = priorTab; showSaveError(); }
}

function showSaveError() {
  let error = $('#dialog-content .dialog-toast');
  if (!error) { error = document.createElement('p'); error.className = 'dialog-toast'; error.setAttribute('role', 'alert'); $('#dialog-content').append(error); }
  error.textContent = '保存できませんでした。登録内容は変更していません。ブラウザの保存設定をご確認ください。';
}

function deletePlace() {
  showDialog(`${dialogTitle('REMOVE PLACE', 'この場所を削除しますか？', `${escapeHTML(draft.place.name)} の関連付けを削除します。マイアプリの登録は残ります。`)}<div class="dialog-actions"><button class="secondary" data-action="back-apps">キャンセル</button><button class="danger" data-action="confirm-delete-place">削除する</button></div>`);
}

function addApps() {
  const available = APPS.filter(app => !data().apps.includes(app.id));
  showDialog(`${dialogTitle('MY APPS', '使っているアプリを追加', '追加したアプリは、場所ごとの登録に使えます。')}
    ${available.length ? `<form id="add-apps-form"><div class="choice-list">${available.map(app => `<label class="choice">${appLogo(app.id)}<span><strong>${app.name}</strong><small>${app.kind}</small></span><input type="checkbox" name="new-app" value="${app.id}"></label>`).join('')}</div><button class="primary full-width" type="submit">選んだアプリを追加</button><p class="form-error" id="form-error" role="alert"></p></form>` : '<div class="empty-state"><div class="empty-icon">' + icon('check') + '</div><h3>すべて登録済みです</h3><p>このサンプルで選べるアプリを<br>すべてマイアプリに追加しています。</p><button class="secondary" data-action="close">閉じる</button></div>'}`);
}

function appDetails(id) {
  const app = appById(id);
  const places = data().places.filter(place => place.apps.includes(id));
  showDialog(`${dialogTitle('MY APPS', `${appLogo(id)} ${app.name}`, `${places.length ? `${places.length}か所に関連付けています。` : 'まだ場所には関連付けていません。'} アプリの登録を管理できます。`)}
    <div class="choice-list">${places.map(place => `<button class="choice" data-edit-place="${escapeHTML(place.id)}"><span class="place-icon">${icon(place.icon)}</span><span><strong>${escapeHTML(place.name)}</strong><small>場所の登録を編集</small></span>${icon('arrow')}</button>`).join('')}</div>
    <button class="danger full-width" data-remove-app="${id}">マイアプリから削除</button><p class="dialog-note">この画面から他のアプリを開いたり、端末からアンインストールしたりすることはありません。</p>`);
}

function removeApp(id) {
  const app = appById(id);
  const linked = data().places.filter(place => place.apps.includes(id));
  showDialog(`${dialogTitle('REMOVE APP', `${app.name}の登録を削除？`, linked.length ? `${linked.length}か所（${linked.map(place => escapeHTML(place.name)).join('、')}）との関連付けも解除します。ほかの登録アプリと場所は残ります。` : 'マイアプリの登録から削除します。端末のアプリは削除されません。')}
    ${linked.length ? '<p class="dialog-note">関連付けがなくなった場所には「アプリ未登録」と表示します。</p>' : ''}<div class="dialog-actions"><button class="secondary" data-app-detail="${id}">キャンセル</button><button class="danger" data-confirm-remove-app="${id}">${linked.length ? '関連付けも削除' : '削除する'}</button></div>`);
}

function settings() {
  showDialog(`${dialogTitle('SETTINGS', '自分に合う、お知らせを。', '登録した場所への到着時に、選んだアプリを思い出すための設定です。')}
    <div class="settings-row"><span>位置情報<small>登録場所への到着を知るために使います。</small></span><span class="state-pill ${demo === 'denied' ? 'off' : ''}">${demo === 'denied' ? 'オフの表示' : 'サンプル表示'}</span></div>
    <div class="settings-row"><span>到着のお知らせ<small>場所ごとに選んだアプリを案内します。</small></span><span class="state-pill off">未接続</span></div>
    <div class="settings-row"><span>登録内容<small>このブラウザ内に保存します。</small></span><span>${data().places.length}か所 / ${data().apps.length}アプリ</span></div>
    <p class="dialog-note">この画面はデザインサンプルです。実際の位置情報・通知の権限は変更しません。</p><div class="preview-controls" aria-label="サンプル表示"><button data-demo="saved" class="${demo === 'saved' ? 'active' : ''}" aria-pressed="${demo === 'saved'}">登録済み</button><button data-demo="empty" class="${demo === 'empty' ? 'active' : ''}" aria-pressed="${demo === 'empty'}">はじめて</button><button data-demo="denied" class="${demo === 'denied' ? 'active' : ''}" aria-pressed="${demo === 'denied'}">位置情報オフ</button></div><button class="primary full-width" data-action="close" style="margin-top:20px">ホームに戻る</button>`);
}

function editPlace(id) {
  const place = data().places.find(item => item.id === id);
  if (!place) return;
  draft = { editing: true, place: clone(place), apps: [...place.apps] };
  selectedPlace = id;
  render();
  appPicker();
}

document.addEventListener('click', event => {
  const button = event.target.closest('button');
  if (!button) return;
  if (button.dataset.demo) {
    demo = button.dataset.demo;
    activeTab = 'places';
    selectedPlace = data().places[0]?.id || null;
    document.querySelectorAll('[data-demo]').forEach(control => { const selected = control.dataset.demo === demo; control.classList.toggle('active', selected); control.setAttribute('aria-pressed', String(selected)); });
    render();
    if (dialog.open) dialog.close();
  } else if (button.dataset.tab) {
    activeTab = button.dataset.tab;
    render();
  } else if (button.dataset.pin) {
    selectedPlace = button.dataset.pin;
    activeTab = 'places';
    render();
    const row = [...document.querySelectorAll('[data-edit-place]')].find(item => item.dataset.editPlace === selectedPlace);
    if (row) $('#list-panel').scrollTop = row.offsetTop - $('#list-panel').offsetTop;
    const pin = [...document.querySelectorAll('[data-pin]')].find(item => item.dataset.pin === selectedPlace);
    pin?.focus({ preventScroll: true });
  } else if (button.dataset.editPlace) editPlace(button.dataset.editPlace);
  else if (button.dataset.pickPlace) { draft.place = { ...PLACES.find(place => place.id === button.dataset.pickPlace) }; appPicker(); }
  else if (button.dataset.appDetail) appDetails(button.dataset.appDetail);
  else if (button.dataset.removeApp) removeApp(button.dataset.removeApp);
  else if (button.dataset.confirmRemoveApp) {
    const id = button.dataset.confirmRemoveApp;
    const next = clone(data());
    next.apps = next.apps.filter(app => app !== id);
    next.places.forEach(place => { place.apps = place.apps.filter(app => app !== id); });
    if (save(next, 'アプリの登録を削除しました。')) dialog.close(); else showSaveError();
  } else if (button.id === 'settings') settings();
  else if (button.id === 'search') beginPlace();
  else if (button.id === 'add') activeTab === 'places' ? beginPlace() : addApps();
  else if (button.id === 'close-dialog') dialog.close();
  else if (button.id === 'locate') {
    if (demo === 'denied') settings();
    else toast('サンプルの現在地を表示しています。実際の位置は取得していません。');
  } else if (button.id === 'custom-map') {
    draft.coordinates = draft.coordinates.x === 50 ? { x: 68, y: 65 } : { x: 50, y: 50 };
    button.querySelector('svg').style.transform = draft.coordinates.x === 50 ? '' : 'translate(45px, 16px)';
    button.querySelector('span').textContent = '位置を選択しました · サンプル';
  } else {
    switch (button.dataset.action) {
      case 'add-place': beginPlace(); break;
      case 'add-app': addApps(); break;
      case 'close': dialog.close(); break;
      case 'back-places': placePicker(); break;
      case 'custom-place': customPlace(); break;
      case 'back-apps': appPicker(); break;
      case 'save-place': savePlace(); break;
      case 'delete-place': deletePlace(); break;
      case 'confirm-delete-place': {
        const next = clone(data());
        next.places = next.places.filter(place => place.id !== draft.place.id);
        if (save(next, '場所の登録を削除しました。')) { selectedPlace = next.places[0]?.id || null; render(); dialog.close(); } else showSaveError();
        break;
      }
    }
  }
});

document.addEventListener('input', event => { if (event.target.id === 'place-search') filterPlaces(event.target.value); });
document.addEventListener('submit', event => {
  if (!['custom-place-form', 'apps-form', 'add-apps-form'].includes(event.target.id)) return;
  event.preventDefault();
  if (event.target.id === 'custom-place-form') {
    const name = $('#custom-name').value.trim();
    if (!name) { $('#form-error').textContent = '場所の名前を入力してください。'; return; }
    if (data().places.some(place => place.name === name)) { $('#form-error').textContent = '同じ名前の場所が登録されています。名前を変えるか、登録済みの場所を編集してください。'; return; }
    const id = `custom-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
    draft.place = { id, name, area: '自分で追加した場所 · サンプル位置', icon: 'pin', ...draft.coordinates };
    appPicker();
  } else if (event.target.id === 'apps-form') {
    const selected = [...new FormData(event.target).getAll('linked-app')];
    if (!selected.length) { $('#form-error').textContent = 'アプリを1つ以上選んでください。'; return; }
    draft.apps = selected;
    confirmPlace();
  } else {
    const selected = [...new FormData(event.target).getAll('new-app')];
    if (!selected.length) { $('#form-error').textContent = '追加するアプリを選んでください。'; return; }
    const next = clone(data());
    next.apps = [...new Set([...next.apps, ...selected])];
    if (save(next, 'マイアプリに追加しました。')) dialog.close(); else showSaveError();
  }
});

$('.bottom-tabs').addEventListener('keydown', event => {
  if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
  event.preventDefault();
  activeTab = event.key === 'Home' ? 'places' : event.key === 'End' ? 'apps' : activeTab === 'places' ? 'apps' : 'places';
  render();
  $(`[data-tab="${activeTab}"]`).focus();
});
dialog.addEventListener('close', () => { draft = null; if (opener?.isConnected) opener.focus({ preventScroll: true }); else $('#add').focus({ preventScroll: true }); });

function selfTest() {
  const valid = initialState();
  const invalidLink = clone(valid); invalidLink.places[0].apps.push('unknown');
  const duplicate = clone(valid); duplicate.apps.push('paypay');
  const hostile = clone(valid); hostile.places[0].id = '"><script>';
  const badCoordinate = clone(valid); badCoordinate.places[0].x = '20;display:none';
  if (!validateState(valid) || !validateState(emptyState()) || validateState(null) || validateState(invalidLink) || validateState(duplicate) || validateState(hostile) || validateState(badCoordinate)) throw new Error('POINT state validation self-check failed');
  return '7 state validation checks passed';
}
window.PointPrototype = Object.freeze({ validateState, selfTest });
selfTest();
render();
if (loadWarning) toast(loadWarning);
