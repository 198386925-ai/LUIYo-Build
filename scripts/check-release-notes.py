#!/usr/bin/env python3
import importlib.util,json,re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('release_renderer',root/'scripts/render-release-notes.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
notes=json.loads((root/'scripts/release-notes.json').read_text())
current=module.render('1.0.5',notes)
assert 'Version 1.0.5 <span>正式版</span>' in current
assert '该版本为首发测试。' in current and '修复已知问题。' in current
assert 'Build' not in current
assert current.count('Version 1.0.4</div>')==1
assert current.count('class="inlineVersion"')==6
for section in notes['exclusive_history_by_version']['1.0.5']:
 for entry in section['entries']:assert entry['text'] in current
future=module.render('1.0.6',notes)
assert future.count('class="inlineVersion"')==1
assert '1.0.5' not in future and '1.0.4' not in future and '首发测试' not in future
page=(root/'YouYouLUI_iOS/YouYouLUI/Web/index.html').read_text()
future_page=module.update(page,'1.0.6',notes)
assert 'Version 1.0.4' not in future_page and 'Version 1.0.5' not in future_page
print('Passed: supplied log belongs exclusively to 1.0.5; no Build labels or stale histories in later releases.')
