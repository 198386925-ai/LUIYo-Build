const fs=require('fs'),vm=require('vm'),assert=require('assert');
const html=fs.readFileSync(process.argv[2]||'YouYouLUI_iOS/YouYouLUI/Web/index.html','utf8');
const raw=JSON.parse(html.match(/const items=(\[[^\n]*\]);/)[1]);
const beforeFiles=raw.flatMap(x=>[x.file,...(x.files||[]),...(x.selectedFiles||[])]);
const declarations=html.slice(html.indexOf('const tabSets='),html.indexOf('function normalizeSearchText'));
const ctx={items:structuredClone(raw),chosen:new Map(),excluded:new Set(),document:{getElementById:()=>({})},renderList(){},updateStatus(){}};
vm.createContext(ctx);
vm.runInContext(html.match(/function syncTitleKey[\s\S]*?\n}/)[0]+declarations+'\nglobalThis.chosen=chosen;',ctx);
const entries=ctx.items,visible=entries.filter(x=>!x.hiddenFromUI);
for(const title of ['底栏微信','底栏通讯录','底栏发现','底栏我的']){
 const group=entries.filter(x=>x.title.replace(/^LiquidUI\s*/,'')===title);
 assert.equal(group.filter(x=>!x.hiddenFromUI).length,1);
 assert.equal(group.find(x=>!x.hiddenFromUI).category,'wechat');
 const index=entries.indexOf(group.find(x=>!x.hiddenFromUI)),file={name:'custom.png'};
 ctx.setChosenWithSync(index,file);
 assert(group.every(x=>ctx.chosen.get(entries.indexOf(x))===file));
 const generated=group.flatMap(x=>[...(x.files||[x.file]),...(x.selectedFiles||[])]);
 assert(generated.some(n=>n.startsWith('lui_tab_'))&&generated.some(n=>!n.startsWith('lui_tab_')));
 ctx.removeChosenWithSync(index);assert(group.every(x=>!ctx.chosen.has(entries.indexOf(x))));
}
assert.deepEqual([...new Set(entries.flatMap(x=>[x.file,...(x.files||[]),...(x.selectedFiles||[])]))].sort(),[...new Set(beforeFiles)].sort(),'Merging entries must not discard any export filename');
for(const role of ['扫一扫','搜索','收付款','转账','返回','表情','相册','文件','位置','发消息']){
 const match=visible.filter(x=>ctx.uploadRole(x)==='shared:'+role);
 assert.equal(match.length,1,role+' must have one import entry');assert.equal(match[0].category,'wechat');
}
assert(visible.filter(x=>x.category==='liquidui').every(x=>/^lui_/.test(x.file)||/第二投放口/.test(x.section||'')));
const flash=visible.filter(x=>/flash_(on|off)/.test(x.file));assert(flash.length>=2,'Different flash states must not merge');
vm.runInContext(html.match(/function previewBounds[\s\S]*?\n}/)[0],ctx);
const alpha=new Uint8ClampedArray(100*100*4);for(let y=40;y<60;y++)for(let x=45;x<55;x++)alpha[(y*100+x)*4+3]=255;
assert.deepEqual(JSON.parse(JSON.stringify(ctx.previewBounds(alpha,100,100))),{left:45,top:40,width:10,height:20});
assert.equal(ctx.previewBounds(new Uint8Array(16),2,2),null);
console.log('Passed: shared entry deduplication, stock category, distinct states, full export filename preservation, upload/remove propagation and transparent thumbnail bounds.');
const script=html.match(/<script id="advanced-theme-build18">([\s\S]*?)<\/script>/)[1];
const fields=Object.fromEntries(['toolbarTransparency','toolbarTransparencyValue','minimizeBottomBar','backgroundImageFile','backgroundImageName','chooseBackgroundImage','resetBackgroundImage'].map(id=>[id,{value:'',events:{},addEventListener(k,f){this.events[k]=f}}]));
const local=new Map(),records=new Map([['customFont',{name:'font.ttf'}]]),messages=[],classes=new Set(),properties={};
const db={objectStoreNames:{contains:()=>true},close(){},transaction(){const tx={objectStore(){return {get(key){const r={};queueMicrotask(()=>{r.result=records.get(key);r.onsuccess();tx.oncomplete()});return r},put(rec,key){records.set(key,rec);queueMicrotask(()=>tx.oncomplete())},delete(key){records.delete(key);queueMicrotask(()=>tx.oncomplete())}}}};return tx}};
const theme={document:{getElementById:id=>fields[id],documentElement:{classList:{toggle(c,on){on?classes.add(c):classes.delete(c)}},style:{setProperty(k,v){properties[k]=v}}}},localStorage:{getItem:k=>local.get(k),setItem:(k,v)=>local.set(k,v)},indexedDB:{open(){const r={result:db};queueMicrotask(()=>r.onsuccess());return r}},URL,FileReader:class{readAsDataURL(){this.result='data:image/jpeg;base64,YWJj';this.onload()}},alert(msg){throw Error(msg)}};
theme.window=theme;theme.webkit={messageHandlers:Object.fromEntries(['backgroundImage','minimizeBottomBar'].map(name=>[name,{postMessage:body=>messages.push({name,...body})}]))};
(async()=>{
 vm.runInNewContext(script,theme);await new Promise(setImmediate);
 fields.toolbarTransparency.value='35';fields.toolbarTransparency.events.input();assert.equal(properties['--tool-opacity'],'0.65');
 fields.minimizeBottomBar.checked=true;fields.minimizeBottomBar.events.change();assert(messages.some(x=>x.name==='minimizeBottomBar'&&x.enabled));
 await theme.__importBackgroundForTest({name:'wallpaper.jpg',blob:new Blob(['abc'])});assert(classes.has('has-background-image'));assert.equal(messages.at(-1).data,'YWJj');
 vm.runInNewContext(script,theme);await new Promise(setImmediate);
 assert.equal(fields.toolbarTransparency.value,35);assert(fields.minimizeBottomBar.checked);assert.equal(fields.backgroundImageName.textContent,'wallpaper.jpg');
 await fields.resetBackgroundImage.events.click();assert(!classes.has('has-background-image'));assert(messages.at(-1).reset);assert.equal(records.get('customFont').name,'font.ttf','Removing background must preserve imported font');
 console.log('Passed: toolbar transparency, scroll minimization and background reload, native byte transfer, removal without deleting custom font.');
})().catch(e=>{console.error(e);process.exitCode=1});
