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
future=module.render('1.0.7',notes)
assert 'Version 1.0.7 <span>正式版</span>' in future
assert 'Build' not in future
assert future.count('Version 1.0.4</div>')==1
assert future.count('class="inlineVersion"')==7
for section in notes['shared_history']:
 for entry in section['entries']:assert entry['text'] in future
page=(root/'YouYouLUI_iOS/YouYouLUI/Web/index.html').read_text()
future_page=module.update(page,'1.0.7',notes)
assert future_page.count('Version 1.0.4')==2 # Both original log surfaces keep the edited text.
assert '该版本为首发测试。' in future_page
print('Passed: the complete user-edited history is preserved in both log surfaces without Build labels.')
