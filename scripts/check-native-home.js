const fs=require('fs'),assert=require('assert'),{JSDOM,VirtualConsole}=require('jsdom');
const root='YouYouLUI_iOS/YouYouLUI/',swift=fs.readFileSync(root+'WebViewController.swift','utf8');
const injected=swift.match(/activationPreviewScript = #"""([\s\S]*?)"""#/)[1];
const messages=[],errors=[],vc=new VirtualConsole();vc.on('jsdomError',e=>errors.push(e.message));
const watchdog=setTimeout(()=>{console.error('Native home test timed out');process.exit(1)},15000);
const dom=new JSDOM(fs.readFileSync(root+'Web/index.html','utf8').replace('<script src="jszip.min.js"></script>',''),{
 url:'https://test.local',runScripts:'dangerously',pretendToBeVisual:true,virtualConsole:vc,beforeParse(w){
  // Drive animation frames with cancellable timers so scroll assertions remain deterministic.
  const rafTimers=new Map();let rafId=0;
  w.requestAnimationFrame=cb=>{const id=++rafId;const timer=setTimeout(()=>{rafTimers.delete(id);cb(Date.now())},0);rafTimers.set(id,timer);return id};
  w.cancelAnimationFrame=id=>{clearTimeout(rafTimers.get(id));rafTimers.delete(id)};
  w.__clearTestRafs=()=>{for(const timer of rafTimers.values())clearTimeout(timer);rafTimers.clear()};
  w.matchMedia=()=>({matches:false,addEventListener(){}});w.alert=()=>{};w.setImmediate=setImmediate;w.clearImmediate=clearImmediate;
  w.URL.createObjectURL=()=> 'blob:test';w.URL.revokeObjectURL=()=>{};
  w.indexedDB={open(){const r={};setTimeout(()=>r.onerror?.(),1);return r}};
  w.webkit={messageHandlers:new Proxy({},{get:(_,name)=>({postMessage:body=>messages.push({name,body})})})};
 }});
(async()=>{const w=dom.window,d=w.document;await new Promise(r=>setTimeout(r,100));assert.deepEqual(errors,[]);
 assert.deepEqual([...d.querySelectorAll('.categorytabs button')].map(el=>el.id),['tabWechat','tabLui']);
 assert.equal(d.querySelector('.categorytabs button.active').id,'tabWechat');
 assert.equal(d.getElementById('sectionTitle').textContent,'原版微信图标');
 assert.equal(d.querySelectorAll('#list .card').length,199);
 const catalog=JSON.parse(fs.readFileSync(root+'Web/native-preview-catalog.json','utf8'));
 const runtime=JSON.parse(w.eval('JSON.stringify(items)'));
 for(const entry of catalog.entries){assert(!runtime[entry.id].hiddenFromUI);assert.equal(entry.category,runtime[entry.id].category);assert.equal(entry.title,runtime[entry.id].title.replace(/^LiquidUI\s*/,''));}
 assert.equal(catalog.entries.length,runtime.filter(x=>!x.hiddenFromUI).length);
 w.eval(injected);w.eval("thumbnailFor=async()=> 'data:image/png;base64,AQID'");
 w.scrollTo=()=>{};w.appNavTo('settings');
 const themeFold=d.querySelector('.themeFold');themeFold.open=true;themeFold.classList.add('is-expanded');
 for(const mode of ['merged','separate','off']){w.__setBottomSearchMode(mode);w.appNavTo('settings');assert(themeFold.open&&themeFold.classList.contains('is-expanded'),'Search layout keeps theme expanded: '+mode)}
 w.appNavTo('home');
 w.DataTransfer=class {constructor(){this.files=[];this.items={add:f=>this.files.push(f)}}};
 for(const id of ['batchInput','fillInput']){let files=[];Object.defineProperty(d.getElementById(id),'files',{get:()=>files,set:value=>files=value})}
 w.eval(fs.readFileSync(root+'Web/native-home-bridge.js','utf8'));
 const lastState=()=>messages.filter(m=>m.name==='nativeHomeState').at(-1).body;
 const input=(id,value)=>{d.getElementById(id).value=value;d.getElementById(id).dispatchEvent(new w.Event('input',{bubbles:true}))};
 input('appBackgroundColor','#dce7f2');input('appCardColor','#f3e8dc');input('appButtonColor','#385170');
 w.__applyToolbarTransparency(35);w.__setBottomSearchMode('off');await w.__nativeHomeCommand('state');
 assert.equal(lastState().theme.background,'#dce7f2');assert.equal(lastState().theme.card,'#FFFFFF','Brand card color must not tint homepage cards');
 assert.equal(w.localStorage.getItem('youyou.theme.heroCardColor.light'),'#f3e8dc');
 assert.equal(messages.filter(m=>m.name==='cardColor').at(-1).body.color,'#f3e8dc');
 assert.equal(lastState().theme.button,'#385170');assert.equal(lastState().theme.toolbarOpacity,.65);
 assert.equal(lastState().theme.customButton,true);assert.equal(lastState().theme.bottomSearchEnabled,false);
 d.querySelector('[data-appearance-mode=dark]').click();input('appBackgroundColor','#182b40');await w.__nativeHomeCommand('state');
 assert.equal(lastState().theme.dark,true);assert.equal(lastState().theme.background,'#182b40');
 d.querySelector('[data-appearance-mode=light]').click();await w.__nativeHomeCommand('state');
 assert.equal(lastState().theme.background,'#dce7f2','Light customization survives appearance switching');
 input('appCardColor','#223344');await w.__nativeHomeCommand('state');assert.equal(lastState().theme.card,'#FFFFFF');assert.equal(w.localStorage.getItem('youyou.theme.heroCardColor.light'),'#223344');
 d.querySelector('[data-appearance-mode=dark]').click();input('appCardColor','#ddeeff');await w.__nativeHomeCommand('state');assert.equal(lastState().theme.card,'#1C1C1E');assert.equal(w.localStorage.getItem('youyou.theme.heroCardColor.dark'),'#ddeeff');
 d.getElementById('resetCardColor').click();assert.equal(w.localStorage.getItem('youyou.theme.heroCardColor.dark'),'#1C1C1E');d.querySelector('[data-appearance-mode=light]').click();
 w.__setBrandSwitch('minimizeBottomBar',true);assert(d.getElementById('minimizeBottomBar').checked);w.__setBrandSwitch('minimizeBottomBar',false);assert(!d.getElementById('minimizeBottomBar').checked);
 assert(d.body.classList.contains('native-day-night-switches'));

 await w.__nativeHomeCommand('search',{query:'test'});assert.equal(d.getElementById('searchInput').value,'test');
 await w.__nativeHomeCommand('search',{query:''});
 const file={base64:'AQID',name:'底栏微信.png',type:'image/png'},cmd=w.__nativeHomeCommand;
 await assert.rejects(cmd('files',{kind:'upload',id:0,files:[file]}),/未授权/);assert.equal(w.eval('chosen.size'),0);
 w.__luiyoSetAuthorized(true);
 const id=w.eval("items.findIndex(x=>!x.hiddenFromUI&&x.category==='wechat')");
 await cmd('files',{kind:'upload',id,files:[file]});assert(w.eval(`chosen.has(${id})`));
 for(const [category,count] of [['wechat',199],['liquidui',126],['wechat',199]]) {
  await cmd('category',{category});assert.equal(d.querySelectorAll('#list .card').length,count,category+' switches the complete catalog');
 }
 await cmd('remove',{id});assert(!w.eval(`chosen.has(${id})`));
 await cmd('clear');
 await cmd('files',{kind:'batch',files:[file]});assert(w.eval('chosen.size')>0,'Batch keeps original filename keyword matching');
 const values={selectedLightEnabled:true,selectedDarkEnabled:true,allColorEnabled:true,selectedColor:'#123456',selectedDarkColor:'#abcdef',allColor:'#987654'};
 await cmd('colors',{values});for(const [key,value] of Object.entries(values))assert.equal(typeof value==='boolean'?d.getElementById(key).checked:d.getElementById(key).value,value);
 await cmd('files',{kind:'fillImage',files:[file]});assert.equal(w.eval('fillFile.name'),file.name);
 await cmd('fill');await cmd('state');
 const state=messages.filter(m=>m.name==='nativeHomeState').at(-1).body;
 assert.equal(state.uploadedCount,325);assert.equal(Object.keys(state.uploaded).length,325);assert.equal(w.eval('chosen.size'),388);
 w.__luiyoSetAuthorized(false);await assert.rejects(cmd('clear'),/未授权/);assert.equal(w.eval('chosen.size'),388);
 w.__luiyoSetAuthorized(true);
 w.eval(fs.readFileSync(root+'Web/jszip.min.js','utf8'));
 w.eval("const generate=JSZip.prototype.generateAsync;JSZip.prototype.generateAsync=async function(options){return new Blob([await generate.call(this,{...options,type:'uint8array'})],{type:'application/zip'})};toPng=async()=>({arrayBuffer:async()=>new Uint8Array([1,2,3]).buffer});toDarkPng=toPng;toSelectedPng=toPng;");
 await cmd('export');assert(messages.some(m=>m.name==='zipName'));
 w.__shareZipWithName('原生首页验证');await new Promise(r=>setTimeout(r,100));
 const share=messages.find(m=>m.name==='shareZip');assert(share?.body.base64.startsWith('UEs'));assert.equal(share.body.fileName,'原生首页验证.zip');
 await cmd('clear');await cmd('state');assert.equal(messages.filter(m=>m.name==='nativeHomeState').at(-1).body.uploadedCount,0);
 const scrollTargets=[];w.HTMLElement.prototype.scrollIntoView=function(){scrollTargets.push(this.id||this.className)};
 w.appNavTo('settings');
 const hero=d.getElementById('luiyoSettingsHero');assert.equal(hero.nextElementSibling.id,'luiyoActivationCard');
 for(const selector of ['.changelogInline','.guideInline']) {
  const fold=d.querySelector(selector).closest('.settingsFold');
  assert.equal(w.__toggleHeroSection(selector),true);assert.equal(fold.open,true);
  await new Promise(r=>setTimeout(r,30));assert(scrollTargets.at(-1).includes('settingsFold'));
  assert.equal(w.__toggleHeroSection(selector),false);assert.equal(fold.open,false);
  await new Promise(r=>setTimeout(r,30));assert.equal(scrollTargets.at(-1),'luiyoSettingsHero');
 }
 const before=scrollTargets.length;
 w.__toggleHeroSection('.changelogInline');w.__toggleHeroSection('.changelogInline');
 await new Promise(r=>setTimeout(r,30));assert.equal(scrollTargets.length,before+1,'Rapid taps retain only the final scroll target');
 assert.equal(scrollTargets.at(-1),'luiyoSettingsHero');
 console.log('Passed: hero stays above authorization; info/changelog open, scroll to content, close on a second tap and cancel stale scrolling.');
 console.log('Passed: native single/batch upload, 199 stock entries, removal, 325 visible/396 original filenames / 388 engine fill, colors, revocation, real ZIP and native rename/share.');
 await new Promise(r=>setTimeout(r,120));w.__clearTestRafs();clearTimeout(watchdog);dom.window.close();
})().catch(error=>{console.error(error);clearTimeout(watchdog);dom.window.close();process.exitCode=1});
