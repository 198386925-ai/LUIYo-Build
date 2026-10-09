'use strict';
(() => {
  const panels=[...document.querySelectorAll('[data-panel]')];
  if(!panels.length)return;
  function show(name) {
    if(!panels.some(p=>p.dataset.panel===name))name='overview';
    for(const panel of panels)panel.classList.toggle('active',panel.dataset.panel===name);
    for(const button of document.querySelectorAll('[data-nav]')) {
      const selected=button.dataset.nav===name;
      button.classList.toggle('active',selected);
      if(selected)button.setAttribute('aria-current','page');else button.removeAttribute('aria-current');
    }
    const url=new URL(location.href);url.searchParams.set('panel',name);history.replaceState(null,'',url);
    window.scrollTo(0,0);
  }
  for(const button of document.querySelectorAll('[data-nav],[data-goto]'))button.addEventListener('click',()=>show(button.dataset.nav||button.dataset.goto));
  show(document.body.dataset.serverPanel||'overview');
  for(const button of document.querySelectorAll('.step-control'))button.addEventListener('click',()=>{
    const field=document.getElementById(button.dataset.for);if(!field)return;
    button.dataset.dir==='-1'?field.stepDown():field.stepUp();field.dispatchEvent(new Event('change',{bubbles:true}));
  });
  async function copy(text){try{await navigator.clipboard.writeText(text);}catch{const field=document.createElement('textarea');field.value=text;document.body.append(field);field.select();document.execCommand('copy');field.remove();}}
  for(const button of document.querySelectorAll('.copy-code'))button.addEventListener('click',async()=>{await copy(button.dataset.copy);const label=button.textContent;button.textContent='已复制';setTimeout(()=>button.textContent=label,1500);});
  document.getElementById('history-select-all')?.addEventListener('change',e=>{for(const field of document.querySelectorAll('.history-select'))field.checked=e.target.checked;});
  document.getElementById('history-copy-selected')?.addEventListener('click',()=>{const selected=[...document.querySelectorAll('.history-select:checked')].map(f=>f.value);if(selected.length)copy(selected.join('\n'));else alert('请先选择卡密');});
  const legacy=document.getElementById('legacy-search');
  const filterLegacy=()=>{for(const row of document.querySelectorAll('.legacy-devices tbody tr'))row.hidden=!row.textContent.toLowerCase().includes(legacy.value.trim().toLowerCase());};
  legacy?.addEventListener('input',filterLegacy);
  document.getElementById('legacy-search-clear')?.addEventListener('click',()=>{legacy.value='';filterLegacy();});
  document.getElementById('license-search')?.addEventListener('input',e=>{const text=e.target.value.trim().toLowerCase();for(const item of document.querySelectorAll('.license-item'))item.hidden=!item.dataset.filter.toLowerCase().includes(text);});
  for(const form of document.querySelectorAll('.delete-license-form'))form.addEventListener('submit',e=>{if(!confirm('删除该卡密及关联设备授权？'))e.preventDefault();});
  const sync=()=>{for(const key of ['total','online','unlicensed']){const source=document.getElementById('presence-'+key),target=document.getElementById('home-presence-'+key);if(source&&target)target.textContent=source.textContent;}};
  for(const key of ['total','online','unlicensed']){const source=document.getElementById('presence-'+key);if(source)new MutationObserver(sync).observe(source,{childList:true,characterData:true,subtree:true});}sync();
  document.getElementById('dash-refresh')?.addEventListener('click',()=>document.getElementById('presence-refresh')?.click());
})();
