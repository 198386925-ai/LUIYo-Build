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
        || (filter.value === 'unlicensed' && d.status === '未授权')
        || (filter.value === 'udid' && (d.udid_verified_at || d.signing_udid));
      return matches && [d.device_code, d.udid, d.signing_udid, d.label, d.model].some(v => String(v || '').toLowerCase().includes(text));
    });
    rows.replaceChildren();
    for (const d of matching) {
      const row = document.createElement('tr');
      for (const value of [d.device_code, d.online ? '● 在线' : '离线', d.status + (d.label ? ' · ' + d.label : ''),
        [d.model, d.os_version && 'iOS ' + d.os_version, d.app_version && 'App ' + d.app_version].filter(Boolean).join(' / '),
        pages[d.page] || '—', format(d.last_seen), d.udid_verified_at ? d.udid + ' · 描述文件已校验' : (d.signing_udid ? d.signing_udid + ' · 签名文件提供（未校验）' : '未获取')]) {
        const cell = document.createElement('td'); cell.textContent = value; row.appendChild(cell);
      }
      row.title = '首次登记：' + format(d.created_at) + (d.udid_verified_at ? '\nUDID 校验时间：' + format(d.udid_verified_at) : '');
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
      const data = await response.json(); devices = data.devices;
      for (const key of ['total', 'online', 'unlicensed']) document.getElementById('presence-' + key).textContent = String(data[key]);
      update.textContent = '更新于 ' + format(data.server_time); render();
    } catch { update.textContent = '更新失败，请刷新页面确认登录状态'; }
    finally { inFlight = false; }
  }
  filter.addEventListener('change', render); query.addEventListener('input', render);
  document.getElementById('presence-refresh').addEventListener('click', refresh);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
  refresh(); setInterval(refresh, 15000);
})();
