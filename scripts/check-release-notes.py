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
assert current.count('class="inlineVersion"')==1
assert 'Version 1.0.6 <span>正式版</span>' in current
for entry in notes['releases'][version]['entries']:assert html.escape(entry['text']) in current
for section in notes['shared_history']:assert 'Version '+section['version'] not in current
assert notes['shared_history'] and notes['exclusive_history_by_version']['1.0.5']
page=(root/'YouYouLUI_iOS/YouYouLUI/Web/index.html').read_text()
updated=module.update(page,version,notes)
assert updated==page and module.update(updated,version,notes)==updated
assert updated.count('Version 1.0.6')==3
assert '<b>当前版本</b><small>Version 1.0.6 · 正式版</small>' in updated
assert not re.search(r'Version 1\.0\.[0-57]',updated)
print('Passed: only current 1.0.6 notes appear in both surfaces; edited history stays archived.')
