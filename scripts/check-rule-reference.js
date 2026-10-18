// Verify the rendered rules page, including exact pairing and search.
const fs=require('fs'),assert=require('assert'),{JSDOM,VirtualConsole}=require('jsdom');
const html=fs.readFileSync('YouYouLUI_iOS/YouYouLUI/Web/index.html','utf8').replace('<script src="jszip.min.js"></script>','');
const errors=[],vc=new VirtualConsole();vc.on('jsdomError',e=>errors.push(e.message));
const dom=new JSDOM(html,{url:'https://test.local',runScripts:'dangerously',pretendToBeVisual:true,virtualConsole:vc,beforeParse(w){
  w.matchMedia=()=>({matches:false,addEventListener(){},addListener(){}});w.alert=()=>{};
  w.indexedDB={open(){const r={};setTimeout(()=>r.onerror?.(),1);return r}};
  w.URL.createObjectURL=()=> 'blob:test';w.URL.revokeObjectURL=()=>{};
  w.scrollTo=()=>{};
}});
try{
  const w=dom.window,d=w.document;
  assert.deepEqual(errors,[],'Page scripts must run without errors');
  const original=w.eval('JSON.stringify(namingRules)'),rules=JSON.parse(original);
  const cardFor=section=>Array.from(d.querySelectorAll('#ruleList .ruleCard')).find(c=>c.dataset.section===section);
  const pairs=rules.filter(r=>r.title.endsWith('选中')&&!r.title.endsWith('未选中')&&rules.some(b=>b.section===r.section&&b.title===r.title.slice(0,-2)));
  assert.equal(pairs.length,10,'The current rules have ten exact state pairs');
  for(const selected of pairs){
    const base=selected.title.slice(0,-2),card=cardFor(selected.section);
    const rows=Array.from(card.querySelectorAll('.ruleRow'));
    const combined=rows.find(row=>row.querySelector('.ruleName').textContent===base+' + 选中');
    assert(combined,base+' must combine in its original section');
    const normal=rules.find(r=>r.section===selected.section&&r.title===base);
    assert.deepEqual(Array.from(combined.querySelectorAll('.ruleFileName'),e=>e.textContent),[normal.file,selected.file]);
    assert.deepEqual(Array.from(combined.querySelectorAll('.ruleState'),e=>e.textContent),['（不选中）','（选中）']);
    assert(!rows.some(row=>row.querySelector('.ruleName').textContent===selected.title));
  }
  const dock=cardFor('LiquidUI 底栏 dock（各款底栏通用）');
  assert.deepEqual(Array.from(dock.querySelectorAll('.ruleName'),e=>e.textContent),['微信','通讯录','发现','我的'].map(t=>'LiquidUI 底栏'+t+' + 选中'));
  assert.equal(dock.querySelector('.ruleGroupHead>span').textContent,'4 项');
  assert.deepEqual(Array.from(d.querySelectorAll('#ruleList .ruleFileName'),e=>e.textContent).sort(),rules.map(r=>r.file).sort(),'Every reference filename must remain visible');
  assert(d.querySelector('#ruleList').textContent.includes('LiquidUI「群聊」选中'),'Unmatched selected titles remain separate');
  assert(d.querySelector('#ruleList').textContent.includes('多选联系人勾选框 · 未选中'),'Unselected states remain separate');
  const search=d.getElementById('ruleSearch');
  for(const query of ['lui_tab_main_filled@3x.png','LiquidUI 底栏微信选中','LiquidUI 底栏微信 + 选中']){
    search.value=query;search.dispatchEvent(new w.Event('input'));
    const match=d.querySelector('#ruleList .ruleRow');assert(match,query);
    assert.equal(match.querySelector('.ruleName').textContent,'LiquidUI 底栏微信 + 选中');
    assert.equal(match.querySelectorAll('.ruleFile').length,2);
  }
  // Reversed ordering must still put the pair at the normal row's position;
  // differing prefixes, spaces, sections and 未选中 must not pair.
  w.eval(`namingRules.splice(0,namingRules.length,
    {section:'A',title:'按钮选中',file:'selected.png'},
    {section:'A',title:'中间',file:'middle.png'},
    {section:'A',title:'按钮',file:'normal.png'},
    {section:'A',title:'LiquidUI 按钮选中',file:'prefix.png'},
    {section:'A',title:'按 钮选中',file:'space.png'},
    {section:'A',title:'按钮未选中',file:'unselected.png'},
    {section:'B',title:'按钮选中',file:'other-section.png'});`);
  search.value='';w.renderRuleReference();
  assert.deepEqual(Array.from(cardFor('A').querySelectorAll('.ruleName'),e=>e.textContent),['中间','按钮 + 选中','LiquidUI 按钮选中','按 钮选中','按钮未选中']);
  assert.equal(cardFor('B').querySelector('.ruleName').textContent,'按钮选中');
  w.eval('namingRules.splice(0,namingRules.length,...'+original+')');w.renderRuleReference();
  assert.equal(w.eval('JSON.stringify(namingRules)'),original,'Reference grouping must not change source/export rules');
  console.log('Passed: ten exact pairs, original placement, both filenames, unmatched states, section isolation and search.');
}finally{dom.window.close()}
