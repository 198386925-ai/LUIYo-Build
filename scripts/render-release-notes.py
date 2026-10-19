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
    sections=[{'version':version,'entries':current['entries']}]
    history=notes.get('shared_history',[]) if version != '1.0.5' else notes.get('exclusive_history_by_version',{}).get(version,[])
    sections += [section for section in history if section['version'] != version]
    labels={'add':'新增','opt':'优化','fix':'修复'}
    result=[]
    for section in sections:
        title='Version '+html.escape(section['version'])
        if section['version']==version:title+=' <span>当前版本</span>'
        paragraphs=[]
        for entry in section['entries']:
            text=html.escape(entry['text'])
            kind=entry['kind']
            paragraphs.append('<p>'+('<b class="'+kind+'">'+labels[kind]+'</b> ' if kind in labels else '')+text+'</p>')
        result.append('<section class="inlineVersion"><div class="inlineVersionTitle">'+title+'</div>'+''.join(paragraphs)+'</section>')
    return '\n'.join(result)

UPDATE_BTN = '''
<button id="checkUpdateBtn" onclick="checkAppUpdate()" style="display:block;width:100%;margin:16px 0 0;padding:14px;background:#007aff;color:#fff;border:none;border-radius:14px;font-size:16px;">检查更新</button>
<div id="updateResult" style="margin-top:10px;font-size:14px;color:#666;text-align:center;"></div>
<script>
function checkAppUpdate(){
  var btn=document.getElementById('checkUpdateBtn');
  var res=document.getElementById('updateResult');
  btn.textContent='\u68c0\u67e5\u4e2d\u2026'; btn.disabled=true;
  fetch('https://mistoto.cc.cd/luiyo/version.php')
    .then(function(r){return r.json();})
    .then(function(d){
      btn.textContent='\u68c0\u67e5\u66f4\u65b0'; btn.disabled=false;
      if(!d.ok){ res.textContent='\u68c0\u67e5\u5931\u8d25\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5'; return; }
      var cur=17;
      if(d.build>cur){
        res.innerHTML='\u53d1\u73b0\u65b0\u7248 '+d.version;
        if(confirm('\u53d1\u73b0\u65b0\u7248\u672c '+d.version+'\n'+(d.changelog||'')+'\n\n\u662f\u5426\u4e0b\u8f7d\uff1f')){
          window.location.href=d.download_url;
        }
      }else{
        res.textContent='\u5df2\u662f\u6700\u65b0\u7248\u672c';
      }
    })
    .catch(function(e){ btn.textContent='\u68c0\u67e5\u66f4\u65b0'; btn.disabled=false; res.textContent='\u7f51\u7edc\u9519\u8bef'; });
}
</script>'''

def update(page,version,notes):
    body=render(version,notes) + UPDATE_BTN
    page,n=re.subn(r'(<div class="settingsFoldBody changelogInline">)[\s\S]*?(\n    </div>\n  </details>)',lambda m:m[1]+'\n'+body+m[2],page,count=1)
    assert n==1,'Missing changelog container'
    page=re.sub(r'<b>(?:更新日志|当前版本)</b><small>[^<]*(</small>)',lambda m:'<b>更新日志</b><small>'+'Version '+html.escape(version)+' · 当前版本'+m[1],page,count=1)
    # The old alternative info page must not expose a second stale history.
    page,n=re.subn(r'(<div class="logCards">)[\s\S]*?(\n  </div>\n</div>\n<script>\nfunction openInfoPage)',lambda m:m[1]+'\n'+body.replace('section class="inlineVersion"','article class="logCard"').replace('</section>','</article>').replace('inlineVersionTitle','logTitle')+m[2],page,count=1)
    assert n==1,'Missing alternate changelog container'
    return page

if __name__=='__main__':
    version=plistlib.loads((ROOT/'YouYouLUI_iOS/YouYouLUI/Info.plist').read_bytes())['CFBundleShortVersionString']
    notes=json.loads((ROOT/'scripts/release-notes.json').read_text())
    path=ROOT/'YouYouLUI_iOS/YouYouLUI/Web/index.html'
    path.write_text(update(path.read_text(),version,notes))
