'use strict';
/* LUIYo admin-devices v3: toggle switch (添加授权/取消授权) */
(() => {
  console.log('[LUIYo] admin-devices v3 loaded: toggle switch active');
  const rows = document.getElementById('presence-rows');
  const filter = document.getElementById('presence-filter');
  const query = document.getElementById('presence-query');
  const update = document.getElementById('presence-update');
  const pages = { home: '首页', rules: '规则', settings: '设置' };
  // An isolated card prevents legacy td:nth-child styles from changing the layout.
  const style=document.createElement('style');
  style.textContent=`
    #device-overview .presence-scroll{overflow:visible!important}
    #device-overview .presence-scroll table{display:block!important;width:100%!important;min-width:0!important}
    #device-overview .presence-scroll tbody{display:grid!important;gap:6px!important;width:100%!important}
    #device-overview .presence-scroll thead{display:none!important}
    #device-overview .presence-scroll tr.presence-device-row{display:block!important;padding:0!important;margin:0!important;border:0!important;background:transparent!important}
    #device-overview .presence-scroll td.presence-card-cell{display:block!important;width:auto!important;padding:0!important;border:0!important;white-space:normal!important}
    #device-overview .presence-scroll td.presence-card-cell::before{display:none!important}
    .presence-device-card{display:grid;grid-template-columns:minmax(0,1fr) auto;grid-template-areas:'heading heading' 'meta action' 'time action';gap:4px 12px;padding:10px 11px;border:1px solid #e2e9f4;border-radius:13px;background:#fff;min-width:0;box-sizing:border-box}
    .presence-card-heading{grid-area:heading;display:flex;align-items:center;gap:10px;min-width:0;line-height:1.45;font-size:11px;color:#414d61;white-space:nowrap}
    .presence-card-code{color:#2674ef;font-size:12px;font-weight:700;flex:0 0 auto}
    .presence-card-status{overflow:hidden;text-overflow:ellipsis;min-width:0;flex:0 1 auto}
    .presence-card-online,.presence-card-page{flex:0 0 auto}
    .presence-card-page{color:#66758d}
    .presence-card-meta{grid-area:meta;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;min-width:0;font-size:11px;line-height:1.5;color:#66758d}
    .presence-card-time{grid-area:time;white-space:nowrap;font-size:10px;line-height:1.5;color:#66758d}
    .presence-card-actions{grid-area:action;align-self:center;justify-self:end;display:flex;gap:6px;flex-wrap:wrap;justify-content:flex-end;max-width:190px}
    .presence-device-card button.presence-card-action{flex:0 0 auto;height:auto!important;min-height:28px!important;padding:6px 9px!important;margin:0!important;line-height:1.4;font-size:10.5px!important;border-radius:10px!important;white-space:nowrap!important}
    .presence-device-card button.presence-card-revoke{background:#fff!important;color:#e2475a!important;border:1px solid #f4a0a9!important}
    .presence-device-card button.presence-card-grant{background:#2878f4!important;color:#fff!important}
    @media(max-width:350px){.presence-card-heading{gap:7px;font-size:10px}.presence-card-code{font-size:11px}.presence-device-card{gap:3px 8px;padding:9px}}
  `;
  document.head.appendChild(style);

  let devices = [], inFlight = false;
  const format = stamp => stamp ? new Date(Number(stamp) * 1000).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai', hour12: false }) : '—';
  function render() {
    const text = query.value.trim().toLowerCase();
    const matching = devices.filter(d => {
      const matches = filter.value === 'all' || (filter.value === 'online' && d.online)
        || (filter.value === 'licensed' && d.status === '已授权')
        || (filter.value === 'unlicensed' && d.status === '未授权');
      return matches && [d.device_code, d.label, d.model].some(v => String(v || '').toLowerCase().includes(text));
    });
    rows.replaceChildren();
    const count = document.getElementById('presence-list-count');
    if (count) count.textContent = `显示 ${matching.length} 台 · 设备 ${devices.length} 台（安装记录 ${window.__luiyoInstallations ?? devices.length} 条）`;
    for (const d of matching) {
      const row=document.createElement('tr');row.className='presence-device-row';
      const cell=document.createElement('td');cell.colSpan=7;cell.className='presence-card-cell';
      const card=document.createElement('div');card.className='presence-device-card';
      const heading=document.createElement('div');heading.className='presence-card-heading';
      const part=(tag,className,text)=>{const el=document.createElement(tag);el.className=className;el.textContent=text;return el;};
      heading.append(
        part('strong','presence-card-code',d.device_code),
        part('span','presence-card-status',d.status+(d.label?' · '+d.label:'')),
        part('span','presence-card-online',d.online?'● 在线':'离线'),
        part('span','presence-card-page',pages[d.page]||'—')
      );
      const meta=[d.model,d.os_version&&'iOS '+d.os_version,d.app_version&&'App '+d.app_version].filter(Boolean).join(' / ');
      card.append(heading,part('div','presence-card-meta',meta),part('div','presence-card-time',format(d.last_seen)));
      row.title='首次登记：'+format(d.created_at)+(d.installation_count>1?'\n安装记录：'+d.installation_codes.join('、'):'');
      const actions=document.createElement('div');actions.className='presence-card-actions';
      // Single toggle switch: 取消授权 when an active device-code grant exists, otherwise 添加授权.
      const hasGrant = Number(d.active_grant || 0) > 0;
      const toggleAction = hasGrant ? 'revoke_device' : 'grant_device';
      const toggleLabel = hasGrant ? '取消授权' : '添加授权';
      const toggleClass = hasGrant ? 'presence-card-action presence-card-revoke' : 'presence-card-action presence-card-grant';
      {
        const toggle=part('button',toggleClass,toggleLabel);toggle.type='button';
        toggle.addEventListener('click', async () => {
          const doing = toggleAction === 'revoke_device' ? '取消' : '添加';
          if (!confirm(doing + ' ' + d.device_code + ' 的设备码授权？')) return;
          toggle.disabled = true; toggle.textContent = '处理中…';
          try {
            const payload = new URLSearchParams({
              csrf: document.getElementById('presence-csrf').value,
              action: toggleAction, return_panel: 'devices',
              device_code: d.device_code
            });
            const response = await fetch('admin.php', {
              method: 'POST', credentials: 'same-origin', cache: 'no-store',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'X-Requested-With': 'fetch' },
              body: payload
            });
            const data = await response.json().catch(() => null);
            if (!response.ok) throw new Error((data && data.error) || ('HTTP ' + response.status));
            await refresh();
          } catch (error) {
            alert(doing + '授权失败：' + error.message + '。请重新登录后台重试。');
          } finally { toggle.disabled = false; toggle.textContent = toggleLabel; }
        });
        actions.appendChild(toggle);
      }
      const button=part('button','danger presence-card-action','移出列表');button.type='button';
      button.addEventListener('click', async () => {
        const codes = Array.isArray(d.installation_codes) ? d.installation_codes : [d.device_code];
        if (!confirm('将 ' + codes.join('、') + ' 移出设备列表？\\n再次打开 APP 并联网后会自动显示；不会删除授权。')) return;
        button.disabled = true; button.textContent = '处理中…';
        try {
          const payload = new URLSearchParams({
            csrf: document.getElementById('presence-csrf').value,
            action: 'hide_installations', return_panel: 'devices',
            installation_codes: codes.join(',')
          });
          const response = await fetch('admin.php', {
            method: 'POST', credentials: 'same-origin', cache: 'no-store',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: payload
          });
          if (!response.ok) throw new Error('HTTP ' + response.status);
          await refresh();
        } catch (error) {
          alert('移出设备失败，请重新登录后台重试。' + error.message);
        } finally { button.disabled = false; button.textContent = '移出列表'; }
      });
      actions.appendChild(button);card.appendChild(actions);cell.appendChild(card);row.appendChild(cell);
      rows.appendChild(row);
    }
    if (!matching.length) { const row = document.createElement('tr'), cell = document.createElement('td'); cell.colSpan = 7; cell.textContent = '暂无符合条件的设备'; row.appendChild(cell); rows.appendChild(row); }
  }
  async function refresh() {
    if (inFlight || document.hidden) return;
    inFlight = true;
    try {
      const response = await fetch('admin.php?snapshot=1', { cache: 'no-store', credentials: 'same-origin' });
      if (!response.ok || !response.headers.get('content-type')?.includes('application/json')) throw new Error('session');
      const data = await response.json(); devices = Array.isArray(data.devices) ? data.devices : []; window.__luiyoTotalDevices = Number(data.total ?? 0); window.__luiyoInstallations = Number(data.installation_total ?? devices.length);
      for (const key of ['total', 'online', 'unlicensed']) document.getElementById('presence-' + key).textContent = String(data[key]);
      update.textContent = '更新于 ' + format(data.server_time); render();
    } catch { update.textContent = '更新失败，请刷新页面确认登录状态'; }
    finally { inFlight = false; }
  }
  filter.addEventListener('change', render); query.addEventListener('input', render);
  document.getElementById('presence-refresh').addEventListener('click', refresh);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
  refresh(); setInterval(refresh, 10000);
  window.addEventListener('focus', refresh);
  document.querySelector('[data-nav="devices"]')?.addEventListener('click', refresh);
})();
