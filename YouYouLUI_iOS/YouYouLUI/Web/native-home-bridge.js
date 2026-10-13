// Native UI calls the existing image/export engine; there is one shared state.
(() => {
  const handler = window.webkit?.messageHandlers?.nativeHomeState;
  let sequence = 0, nextImage = 0, queued = false, lastPayload = '';
  const imageKeys = new WeakMap();
  function theme() {
    const root = document.documentElement, style = getComputedStyle(root);
    const color = (name, fallback) => style.getPropertyValue(name).trim() || fallback;
    const dark = root.dataset.appearance === 'dark';
    return {background:color('--app-bg', dark ? '#121214' : '#F2F2F7'),
      card:color('--card-color',dark ? '#1C1C1E' : '#FFFFFF'),button:color('--home-action-fill','#FFFFFF'),
      actionText:color('--home-action-text','#202832'),dark,
      customButton:localStorage.getItem('youyou.theme.buttonColor.custom.'+(dark?'dark':'light')) === '1',
      toolbarOpacity:Number(color('--tool-opacity','1')),
      bottomSearchEnabled:document.body.classList.contains('bottom-search-enabled')};
  }
  function scheduleState() {
    if (queued) return; queued = true;
    requestAnimationFrame(() => { queued = false; state(); });
  }
  async function state() {
    const current = ++sequence, uploaded = {}, images = {}, pending = new Map();
    for (const [index, file] of chosen) {
      if (items[index].hiddenFromUI) continue;
      if (!imageKeys.has(file)) imageKeys.set(file, String(++nextImage));
      const key = imageKeys.get(file); uploaded[index] = key;
      if (!pending.has(key)) pending.set(key, thumbnailFor(file).then(url => { images[key] = url; }).catch(() => {}));
    }
    await Promise.all(pending.values());
    if (current === sequence) {
      const payload = {uploadedCount:Object.keys(uploaded).length,uploaded,images,theme:theme(),
        status:document.getElementById('status').textContent};
      const serialized = JSON.stringify(payload);
      if (serialized !== lastPayload) { lastPayload = serialized; handler?.postMessage(payload); }
    }
  }
  const originalStatus = updateStatus;
  updateStatus = function () { originalStatus(); state(); };
  new MutationObserver(scheduleState).observe(document.getElementById('status'), {childList:true,characterData:true,subtree:true});
  new MutationObserver(scheduleState).observe(document.documentElement, {attributes:true,attributeFilter:['style','data-appearance']});
  new MutationObserver(scheduleState).observe(document.body, {attributes:true,attributeFilter:['class']});
  function authorized() { return document.documentElement.dataset.luiyoAuthorized === 'yes'; }
  window.__nativeHomeCommand = async (action, payload = {}) => {
    if (!['state','category','search'].includes(action) && !authorized()) throw new Error('未授权用户，请授权后使用');
    if (action === 'state') return state();
    if (action === 'category') { switchCategory(payload.category); return state(); }
    if (action === 'search') {
      const input = document.getElementById('searchInput');
      input.value = payload.query || ''; input.dispatchEvent(new Event('input',{bubbles:true})); return state();
    }
    if (action === 'remove') { removeChosenWithSync(payload.id); return state(); }
    if (action === 'clear') { clearAll(); return state(); }
    if (action === 'fill') { document.getElementById('fillBtn').click(); return state(); }
    if (action === 'export') return makeZip(document.querySelector('button.zip'));
    if (action === 'colors') {
      for (const [id, value] of Object.entries(payload.values)) {
        const input = document.getElementById(id);
        if (!input) continue;
        if (typeof value === 'boolean') input.checked = value; else input.value = value;
        input.dispatchEvent(new Event('change', {bubbles:true}));
      }
      return state();
    }
    if (action === 'files') {
      const files = payload.files.map(raw => new File([Uint8Array.from(atob(raw.base64), c => c.charCodeAt(0))],raw.name,{type:raw.type}));
      if (payload.kind === 'upload') {
        if (!Number.isInteger(payload.id) || !items[payload.id]) throw new Error('图标入口无效');
        showFile(payload.id,files[0]); renderList(); return state();
      }
      const input = document.getElementById(payload.kind === 'batch' ? 'batchInput' : 'fillInput');
      const transfer = new DataTransfer(); files.forEach(file => transfer.items.add(file));
      input.files = transfer.files; input.dispatchEvent(new Event('change',{bubbles:true})); return state();
    }
    throw new Error('未知操作');
  };
  state();
})();
