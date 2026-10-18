'use strict';
(() => {
  const panels = [...document.querySelectorAll('main[data-panel]')];
  const tabs = [...document.querySelectorAll('.bottom-nav [data-nav]')];
  if (!panels.length || !tabs.length) return;
  const keys = new Set(panels.map(node => node.dataset.panel));
  const flash = document.getElementById('admin-flash');
  function display(name, remember = true) {
    const selected = keys.has(name) ? name : 'overview';
    for (const panel of panels) panel.classList.toggle('active', panel.dataset.panel === selected);
    for (const tab of tabs) {
      const active = tab.dataset.nav === selected;
      tab.classList.toggle('active', active);
      if (active) tab.setAttribute('aria-current', 'page'); else tab.removeAttribute('aria-current');
    }
    document.body.dataset.currentPanel = selected;
    if (remember) {
      try { sessionStorage.setItem('luiyo-admin-panel', selected); } catch {}
      try {
        const u = new URL(location.href);
        u.searchParams.delete('snapshot');
        u.searchParams.set('panel', selected);
        history.replaceState(null, '', u.pathname + u.search);
      } catch {}
    }
    scrollTo(0, 0);
  }
  for (const tab of tabs) tab.addEventListener('click', e => { e.preventDefault(); display(tab.dataset.nav); });
  document.querySelectorAll('[data-goto]').forEach(el => el.addEventListener('click', e => { e.preventDefault(); display(el.dataset.goto); }));

  document.querySelectorAll('.step-control').forEach(btn => btn.addEventListener('click', e => {
    e.preventDefault(); e.stopPropagation();
    const input = document.getElementById(btn.dataset.for);
    if (!input) return;
    const low = Number(input.min || 0), high = Number(input.max || 100);
    const value = Number(input.value), next = (Number.isFinite(value) ? value : low) + Number(btn.dataset.dir);
    input.value = String(Math.max(low, Math.min(high, next)));
    input.dispatchEvent(new Event('input', {bubbles:true}));
    input.dispatchEvent(new Event('change', {bubbles:true}));
  }));

  // Fix same-page postback and Safari's storage partitioning by honoring the server-confirmed panel.
  let initial = document.body.dataset.serverPanel || 'overview';
  const fromURL = new URLSearchParams(location.search).get('panel');
  if (fromURL && keys.has(fromURL)) initial = fromURL;
  else if (initial === 'overview') {
    try { initial = sessionStorage.getItem('luiyo-admin-panel') || initial; } catch {}
  }
  if (flash && /成功生成|生成失败/.test(flash.textContent)) initial = 'codes';
  display(initial, false);
  if (flash) document.querySelector(initial === 'overview' ? 'main[data-panel="overview"]' : `main[data-panel="${initial}"]`)?.prepend(flash);

  // Only use request panel as the postback target, never reset to Home after posting.
  document.querySelectorAll('main[data-panel] form[method="post"]').forEach(form => {
    const panel = form.closest('main[data-panel]')?.dataset.panel || 'overview';
    form.action = 'admin.php?panel=' + encodeURIComponent(panel);
    form.addEventListener('submit', () => {
      let hidden = form.querySelector('input[name="return_panel"]');
      if (!hidden) { hidden = document.createElement('input'); hidden.type='hidden'; hidden.name='return_panel'; form.append(hidden); }
      hidden.value = panel;
      try { sessionStorage.setItem('luiyo-admin-panel', panel); } catch {}
    });
  });

  const mirror = [['presence-total','home-presence-total'], ['presence-online','home-presence-online'], ['presence-unlicensed','home-presence-unlicensed']];
  for (const [source,target] of mirror) {
    const node=document.getElementById(source), home=document.getElementById(target);
    if(!node || !home) continue;
    const sync=()=>{home.textContent=node.textContent;}; sync();
    new MutationObserver(sync).observe(node,{childList:true,characterData:true,subtree:true});
  }
  document.getElementById('dash-refresh')?.addEventListener('click', e => {
    e.preventDefault();document.getElementById('presence-refresh')?.click();
  });
  const legacy=document.getElementById('legacy-search');
  if (legacy) {
    const rows=[...document.querySelectorAll('.legacy-devices tbody tr')];
    const apply=()=>{const q=legacy.value.trim().toLocaleLowerCase();rows.forEach(row=>row.hidden=!row.textContent.toLocaleLowerCase().includes(q));};
    legacy.addEventListener('input',apply);
    document.getElementById('legacy-search-clear')?.addEventListener('click',()=>{legacy.value='';apply();legacy.focus();});
  }
  const licenseSearch=document.getElementById('license-search');
  if (licenseSearch) licenseSearch.addEventListener('input',()=>{
    const q=licenseSearch.value.trim().toLocaleLowerCase();
    document.querySelectorAll('.license-item').forEach(el=>el.hidden=!el.dataset.filter.includes(q));
  });

  function fallbackCopy(value) {
    const el=document.createElement('textarea');el.value=value;el.readOnly=true;
    Object.assign(el.style,{position:'fixed',left:'0',top:'0',width:'1px',height:'1px',opacity:'0.01',fontSize:'16px'});
    document.body.append(el);
    el.focus();el.select();el.setSelectionRange(0,el.value.length);
    let ok=false;
    try { ok=Boolean(document.execCommand('copy')); } catch {}
    el.remove();return ok;
  }
  async function copyText(value) {
    // iOS Safari usually requires synchronous selection as the first step of a click gesture.
    if (fallbackCopy(value)) return true;
    if (navigator.clipboard?.writeText && window.isSecureContext) {
      try { await navigator.clipboard.writeText(value); return true; } catch {}
    }
    return false;
  }
  function copied(button) { const previous=button.textContent;button.textContent='已复制';setTimeout(()=>{button.textContent=previous;},1400); }
  function manualCopy(value) {
    // User can select and copy in the native iOS prompt if WebKit denies clipboard access.
    window.prompt('浏览器禁止自动复制，请长按下面的卡密并选择复制：',value);
  }
  document.querySelectorAll('.copy-code').forEach(button => button.addEventListener('click', async e => {
    e.preventDefault();e.stopPropagation();
    const value=button.dataset.copy || '';
    if (!value) return;
    if (await copyText(value)) copied(button); else manualCopy(value);
  }));
  const all=document.getElementById('history-select-all');
  all?.addEventListener('change',()=>document.querySelectorAll('.history-select').forEach(c=>{c.checked=all.checked;}));
  document.getElementById('history-copy-selected')?.addEventListener('click',async e=>{
    e.preventDefault();
    const button=e.currentTarget;
    const selected=[...document.querySelectorAll('.history-select:checked')].map(c=>c.value);
    if(!selected.length){alert('请先勾选需要复制的卡密');return;}
    const value=selected.join('\n');
    if (await copyText(value)) copied(button); else manualCopy(value);
  });
  document.querySelectorAll('.delete-license-form').forEach(form=>form.addEventListener('submit',e=>{
    if (!confirm('确定永久删除该卡密及其已绑定设备的授权记录吗？此操作不可撤销。')) e.preventDefault();
  }));
  // Do not intercept touchend: iOS synthesizes button clicks from it and preventing it breaks controls.
})();
