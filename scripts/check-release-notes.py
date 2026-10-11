#!/usr/bin/env python3
import importlib.util,json,re,plistlib,html
from pathlib import Path
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('release_renderer',root/'scripts/render-release-notes.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
notes=json.loads((root/'scripts/release-notes.json').read_text())
version=plistlib.loads((root/'YouYouLUI_iOS/YouYouLUI/Info.plist').read_bytes())['CFBundleShortVersionString']
assert version=='1.0.6'
current=module.render(version,notes)
assert current.count('class="inlineVersion"')==7
assert 'Version 1.0.6 <span>当前版本</span>' in current
for entry in notes['releases'][version]['entries']:assert html.escape(entry['text']) in current
assert current.count('<span>当前版本</span>')==1
assert '正式版' not in current
for section in notes['shared_history']:
 assert 'Version '+section['version'] in current
 for entry in section['entries']:assert html.escape(entry['text']) in current
assert notes['shared_history'] and notes['exclusive_history_by_version']['1.0.5']
page=(root/'YouYouLUI_iOS/YouYouLUI/Web/index.html').read_text()
updated=module.update(page,version,notes)
assert updated==page and module.update(updated,version,notes)==updated
assert updated.count('Version 1.0.6')==3
assert '<b>更新日志</b><small>Version 1.0.6 · 当前版本</small>' in updated
for section in notes['shared_history']:assert updated.count('Version '+section['version'])==2
assert updated.count('<span>当前版本</span>')==2
assert 'Version 1.0.7' not in updated
# A subsequent release must move the badge instead of marking old sections current.
future_notes=json.loads(json.dumps(notes));future_notes['shared_history'].insert(0,{'version':version,'entries':notes['releases'][version]['entries']})
future_notes['releases']['1.0.8']={'entries':[{'kind':'fix','text':'下一版本验证。'}]}
future=module.render('1.0.8',future_notes)
assert 'Version 1.0.8 <span>当前版本</span>' in future
assert 'Version 1.0.6</div>' in future and future.count('<span>当前版本</span>')==1
print('Passed: full edited history restored in both surfaces; only latest version carries current badge.')
