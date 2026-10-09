'use strict';
(() => {
  const rows = document.getElementById('presence-rows');
  const filter = document.getElementById('presence-filter');
  const query = document.getElementById('presence-query');
  const update = document.getElementById('presence-update');
  const pages = { home: '首页', rules: '规则', settings: '设置' };
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
      const row = document.createElement('tr');
      const labels = ['设备编号', '在线', '授权', '设备 / 版本', '当前页面', '最近使用'];
      for (const [i, value] of [d.device_code + (d.installation_count > 1 ? ' · ' + d.installation_count + ' 次安装' : ''), d.online ? '● 在线' : '离线', d.status + (d.label ? ' · ' + d.label : ''),
        [d.model, d.os_version && 'iOS ' + d.os_version, d.app_version && 'App ' + d.app_version].filter(Boolean).join(' / '),
        pages[d.page] || '—', format(d.last_seen)].entries()) {
        const cell = document.createElement('td'); cell.dataset.label = labels[i]; cell.textContent = value; row.appendChild(cell);
      }
      row.title = '首次登记：' + format(d.created_at);
      const cell = document.createElement('td'); cell.dataset.label = '操作';
      const button = document.createElement('button');
      button.type = 'button'; button.className = 'danger';
      button.textContent = '移出列表';
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
      cell.appendChild(button); row.appendChild(cell);
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
