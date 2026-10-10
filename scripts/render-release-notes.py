#!/usr/bin/env python3
"""Render the selected release and the user-approved edited history."""
from pathlib import Path
import html
import json
import plistlib
import re

ROOT=Path(__file__).resolve().parents[1]

def render(version, notes):
    current=notes['releases'].get(version, {'status':'正式版','entries':[{'kind':'opt','text':'修复已知问题。'}]})
    sections=[{'version':version,'status':current['status'],'entries':current['entries']}]
    history=notes.get('shared_history',[]) if version != '1.0.5' else notes.get('exclusive_history_by_version',{}).get(version,[])
    sections += [section for section in history if section['version'] != version]
    labels={'add':'新增','opt':'优化','fix':'修复'}
    result=[]
    for section in sections:
        title='Version '+html.escape(section['version'])
        if section.get('status'):title+=' <span>'+html.escape(section['status'])+'</span>'
        paragraphs=[]
        for entry in section['entries']:
            text=html.escape(entry['text'])
            kind=entry['kind']
            paragraphs.append('<p>'+('<b class="'+kind+'">'+labels[kind]+'</b> ' if kind in labels else '')+text+'</p>')
        result.append('<section class="inlineVersion"><div class="inlineVersionTitle">'+title+'</div>'+''.join(paragraphs)+'</section>')
    return '\n'.join(result)

def update(page,version,notes):
    body=render(version,notes)
    page,n=re.subn(r'(<div class="settingsFoldBody changelogInline">)[\s\S]*?(\n    </div>\n  </details>)',lambda m:m[1]+'\n'+body+m[2],page,count=1)
    assert n==1,'Missing changelog container'
    page=re.sub(r'(<b>更新日志</b><small>)[^<]*(</small>)',lambda m:m[1]+'Version '+html.escape(version)+' · 正式版'+m[2],page,count=1)
    # The old alternative info page must not expose a second stale history.
    page,n=re.subn(r'(<div class="logCards">)[\s\S]*?(\n  </div>\n</div>\n<script>\nfunction openInfoPage)',lambda m:m[1]+'\n'+body.replace('section class="inlineVersion"','article class="logCard"').replace('</section>','</article>').replace('inlineVersionTitle','logTitle')+m[2],page,count=1)
    assert n==1,'Missing alternate changelog container'
    return page

if __name__=='__main__':
    version=plistlib.loads((ROOT/'YouYouLUI_iOS/YouYouLUI/Info.plist').read_bytes())['CFBundleShortVersionString']
    notes=json.loads((ROOT/'scripts/release-notes.json').read_text())
    path=ROOT/'YouYouLUI_iOS/YouYouLUI/Web/index.html'
    path.write_text(update(path.read_text(),version,notes))
