const fs=require('fs'),vm=require('vm'),assert=require('assert');
const h=fs.readFileSync(process.argv[2]||'project/index.html','utf8');
const bridge=h.match(/<script id="true-native-card-glass-bridge-v103">([\s\S]*?)<\/script>/)[1];
for(const m of h.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g))new vm.Script(m[1]);
const specs=[
{id:'searchInput',left:15,top:240,width:340,height:48,classes:[],home:false},
{id:'',left:35,top:450,width:300,height:34,classes:['categorytabs'],home:false},
{id:'far-away',left:15,top:3200,width:160,height:140,classes:['card'],home:false},
{id:'materialModePicker',left:15,top:520,width:340,height:48,classes:[],home:false},
{id:'fillBtn',left:15,top:300,width:340,height:48,classes:[],home:true}
];
let payloads=[],listeners={},raf=[],selected=0,expanded=false;
const ctx={scrollX:0,scrollY:0,WeakMap,Math,JSON,parseFloat,setTimeout:()=>{},requestAnimationFrame:f=>{raf.push(f);return raf.length},addEventListener:(name,f)=>listeners[name]=f,getComputedStyle:e=>e.css||({display:'block',visibility:'visible',opacity:'1',borderTopLeftRadius:'999px'}),MutationObserver:class{observe(){}},ResizeObserver:class{observe(){}}};
const fold={tagName:'DETAILS',open:false,parentElement:null,classList:{contains:c=>c==='settingsFold'||(c==='is-expanded'&&expanded)},css:{display:'block',visibility:'visible',opacity:'1',overflow:'hidden'},getBoundingClientRect:()=>({left:0,top:400-ctx.scrollY,width:380,height:140})};
const nodes=specs.map((spec,i)=>({id:spec.id,dataset:{},parentElement:i===3?fold:null,classList:{contains:c=>spec.classes.includes(c)},matches:()=>spec.home,getBoundingClientRect:()=>({...spec,top:spec.top-ctx.scrollY,left:spec.left-ctx.scrollX}),querySelector:()=>i===2?{dataset:{systemIcon:'heart'},textContent:'♡',getBoundingClientRect:()=>({left:29-ctx.scrollX,top:3214-ctx.scrollY,width:28,height:28})}:null,querySelectorAll:()=>[0,1].map(i=>({classList:{contains:c=>c==='active'&&selected===i}}))}));
ctx.document={body:{classList:{add(){}}},addEventListener(){},querySelectorAll:()=>nodes};
ctx.window=ctx;ctx.webkit={messageHandlers:{cardGlassRects:{postMessage:r=>payloads.push(r)}}};
vm.runInNewContext(bridge,ctx);raf.shift()();
assert.equal(payloads[0].length,3,'closed fold must omit descendants despite their nonzero rectangles');
assert.equal(payloads[0][0].radius,24);assert.equal(payloads[0][0].forceLiquid,false);assert(!payloads[0].some(x=>x.key==='id:fillBtn'));assert.equal(payloads[0][1].radius,17);assert.equal(payloads[0][1].segment,'category');assert.equal(payloads[0][2].y,3200);assert.equal(payloads[0][2].systemIcon,'heart');assert.equal(payloads[0][2].iconX,14);assert.equal(payloads[0][2].iconY,14);assert.equal(payloads[0][2].iconWidth,28);assert.equal(listeners.scroll,undefined);
ctx.scrollY=600;ctx.__syncNativeCardGlass();raf.shift()();assert.equal(payloads.length,1,'scroll must not send different document frames');
selected=1;ctx.__syncNativeCardGlass();raf.shift()();assert.equal(payloads[1][1].selected,1);assert.equal(payloads[1][0].y,240);
fold.open=true;expanded=true;ctx.__syncNativeCardGlass();raf.shift()();
let picker=payloads.at(-1).find(x=>x.key==='id:materialModePicker');
assert.equal(picker.clipHeight,20,'material must clip to the animated fold bounds');
assert.equal(picker.clipY,520,'clip coordinates must stay in document space');
expanded=false;ctx.__syncNativeCardGlass();raf.shift()();
assert(!payloads.at(-1).some(x=>x.key==='id:materialModePicker'),'closing fold must remove native control before open becomes false');
assert(h.includes('id="specialThanks" hidden'));assert(!h.includes('data-material="solid"'));assert(h.includes('compact-category-and-system-dark-v103'));
console.log('Passed: hidden and closing fold cleanup, native clipping bounds, compact capsule geometry, stable scroll coordinates, category selection and settings visibility.');

function classes(){const values=new Set();return {contains:c=>values.has(c),toggle(c,on){on?values.add(c):values.delete(c)},add:c=>values.add(c),remove:c=>values.delete(c)}}
function style(){const values={};return {setProperty(k,v){values[k]=v},removeProperty(k){delete values[k]},get:k=>values[k]}}
// Real fold script: important height rules, completion cleanup and interrupted taps.
const foldScript=h.match(/<script id="native-feel-settings-fold-v102">([\s\S]*?)<\/script>/)[1];
let time=0,nextFrame=0,frames=new Map(),click;
const summary={getBoundingClientRect:()=>({height:48}),addEventListener:(n,f)=>click=f};
const body={getBoundingClientRect:()=>({height:250})};
const details={open:false,style:style(),classList:classes(),querySelector:s=>s==='summary'?summary:body,getBoundingClientRect(){return {height:this.style.get('height')?parseFloat(this.style.get('height')):this.open?298:48}}};
const foldCtx={WeakMap,Math,performance:{now:()=>time},requestAnimationFrame:f=>{frames.set(++nextFrame,f);return nextFrame},cancelAnimationFrame:id=>frames.delete(id),matchMedia:()=>({matches:false}),document:{querySelectorAll:()=>[details],documentElement:{style:style()}}};foldCtx.window=foldCtx;
vm.runInNewContext(foldScript,foldCtx);
function tick(){time+=16;const pending=[...frames.values()];frames.clear();pending.forEach(f=>f(time))}
function finish(){for(let i=0;frames.size&&i<100;i++)tick();assert.equal(frames.size,0)}
click({preventDefault(){}});assert.equal(details.getBoundingClientRect().height,48,'opening must retain its starting height');finish();assert.equal(details.getBoundingClientRect().height,298);assert(!details.style.get('height'),'animation must release its height');
click({preventDefault(){}});assert.equal(details.getBoundingClientRect().height,298);finish();assert.equal(details.getBoundingClientRect().height,48);
click({preventDefault(){}});tick();tick();const interrupted=details.getBoundingClientRect().height;click({preventDefault(){}});assert.equal(details.getBoundingClientRect().height,interrupted,'fast repeated taps must not snap');finish();
click({preventDefault(){}});tick();foldCtx.__resetSettingsFolds();assert.equal(frames.size,0);assert.equal(details.open,false);assert(!details.style.get('height'));
assert(foldCtx.__foldMotionChecks.every(c=>c.jump===0&&c.monotonic));
click({preventDefault(){}});tick();foldCtx.__settleSettingsFold(details);assert.equal(frames.size,0);assert.equal(details.getBoundingClientRect().height,298);assert(foldCtx.__foldMotionChecks.every(c=>c.jump===0&&c.monotonic));

// Explicit light/dark overrides and separate saved background colors.
const themeScript=h.match(/<script id="theme-settings-bridge-v102">([\s\S]*?)<\/script>/)[1];
const local=new Map([['youyou.theme.background','#FFFFFF'],['youyou.theme.buttonColor.light','#F4F2EE'],['youyou.theme.buttonColor.dark','#2C2C2E']]);let messages=[];
const root={dataset:{},style:style()};
function input(value=''){return {value,textContent:'',events:{},addEventListener(n,f){this.events[n]=f}}}
const fields=Object.fromEntries(['appBackgroundColor','resetBackgroundColor','appCardColor','resetCardColor','appButtonColor','resetButtonColor','backgroundHint','appearanceHint'].map(k=>[k,input()]));
const choices=['system','light','dark'].map(mode=>({...input(),dataset:{appearanceMode:mode},classList:classes(),setAttribute(){}}));
const media={matches:false,addEventListener:(n,f)=>media.changed=f};
const themeCtx={matchMedia:()=>media,localStorage:{getItem:k=>local.get(k)||null,setItem:(k,v)=>local.set(k,v),removeItem:k=>local.delete(k)},document:{documentElement:root,getElementById:k=>fields[k],querySelectorAll:()=>choices}};themeCtx.window=themeCtx;themeCtx.webkit={messageHandlers:Object.fromEntries(['appearanceMode','themeBackground','cardColor','buttonColor'].map(n=>[n,{postMessage:v=>messages.push({name:n,...v})}]))};
vm.runInNewContext(themeScript,themeCtx);assert.equal(root.dataset.appearance,'light');assert.equal(fields.appBackgroundColor.value,'#FFFFFF');
choices[2].events.click();assert.equal(root.dataset.appearance,'dark');assert.equal(fields.appBackgroundColor.value,'#121214');
fields.appBackgroundColor.value='#223344';fields.appBackgroundColor.events.input();assert.equal(local.get('youyou.theme.background.dark'),'#223344');
media.matches=true;choices[1].events.click();assert.equal(root.dataset.appearance,'light','forced light must win over a dark system');assert.equal(fields.appBackgroundColor.value,'#FFFFFF');
choices[0].events.click();assert.equal(root.dataset.appearance,'dark');assert.equal(fields.appBackgroundColor.value,'#223344');
fields.resetBackgroundColor.events.click();assert.equal(fields.appBackgroundColor.value,'#121214');
media.matches=false;media.changed();assert.equal(root.dataset.appearance,'light');assert.equal(fields.appBackgroundColor.value,'#FFFFFF');
assert.equal(root.style.get('--surface-border'),'transparent');assert(!h.includes('id="cardBorderEnabled"'));assert(h.includes('id="settingsCredits"'));assert(messages.some(m=>m.name==='appearanceMode'&&m.mode==='light'));
console.log('Passed: smooth fold completion and interrupted taps; forced light/dark; system changes; independent background colors; border removal.');

// Search moves without losing its handlers or UIKit glass; history uses stable groups.
assert.equal((h.match(/id="searchInput"/g)||[]).length,1);
const hero=h.match(/<section class="homeHero"[\s\S]*?<\/section>/)[0];
assert(hero.indexOf('id="searchInput"')>hero.indexOf('class="homeFeedback"'));
const rank={add:0,opt:1,fix:2};
for(const block of h.matchAll(/<section class="inlineVersion">([\s\S]*?)<\/section>/g)){
 const types=[...block[1].matchAll(/<b class="(add|opt|fix)">/g)].map(m=>rank[m[1]]);
 assert(types.length>0);assert(types.every((v,i)=>i===0||v>=types[i-1]));
 assert(!/changelogGroupTitle/.test(block[1]));
}
console.log('Passed: search below feedback, forced Liquid Glass, six native actions omitted, ordered changelog groups.');

// Upgrade former defaults to white; customization remains independent and persistent.
assert.equal(local.get('youyou.theme.buttonColor.light'),'#FFFFFF');assert.equal(local.get('youyou.theme.buttonColor.dark'),'#FFFFFF');
assert.equal(root.style.get('--home-action-text'),'#202832');
assert.equal(root.style.get('--home-blue-fill'),'#007AFE');assert.equal(root.style.get('--home-green-fill'),'#46D86A');
choices[1].events.click();fields.appButtonColor.value='#C58C48';fields.appButtonColor.events.input();
assert.equal(root.style.get('--home-action-fill'),'#C58C48');assert.equal(local.get('youyou.theme.buttonColor.light'),'#C58C48');assert.equal(root.style.get('--home-blue-fill'),'#C58C48');assert.equal(root.style.get('--home-green-fill'),'#C58C48');
choices[2].events.click();assert.equal(fields.appButtonColor.value,'#FFFFFF');fields.appButtonColor.value='#446078';fields.appButtonColor.events.input();
assert.equal(root.style.get('--home-action-text'),'#F2F2F7');assert(messages.some(m=>m.name==='buttonColor'&&m.color==='#446078'));
vm.runInNewContext(themeScript,themeCtx);assert.equal(fields.appButtonColor.value,'#446078');
choices[1].events.click();assert.equal(fields.appButtonColor.value,'#C58C48');fields.resetButtonColor.events.click();assert.equal(fields.appButtonColor.value,'#FFFFFF');assert.equal(root.style.get('--home-blue-fill'),'#007AFE');assert.equal(root.style.get('--home-green-fill'),'#46D86A');
choices[2].events.click();fields.resetButtonColor.events.click();assert.equal(fields.appButtonColor.value,'#FFFFFF');assert.equal(root.style.get('--home-action-text'),'#202832');
fields.appButtonColor.value='#2C2C2E';fields.appButtonColor.events.input();vm.runInNewContext(themeScript,themeCtx);assert.equal(fields.appButtonColor.value,'#2C2C2E','migration must only run once, preserving later custom choices');
fields.appButtonColor.value='#FFFFFF';fields.appButtonColor.events.input();vm.runInNewContext(themeScript,themeCtx);assert.equal(root.style.get('--home-blue-fill'),'#FFFFFF','explicit white customization must survive reload');fields.resetButtonColor.events.click();assert.equal(root.style.get('--home-blue-fill'),'#007AFE');
assert(h.includes('#homeTools .zip{background:#46D86A!important;color:#FFFFFF!important}'));
assert(h.includes('#homeTools .clear{background:#007AFE!important;color:#FFFFFF!important}'));
assert(!bridge.match(/const selector=.*?\.settingsFold,#homeTools,/));
console.log('Passed: fixed blue clear and white ZIP labels; solid tool card; semantic blue/green defaults, immutable green ZIP, white default migration, per-appearance customization, persistence, reset, readable white buttons and one-time migration.');

// Font imports, saved reloads and resets send the same bytes to the native tab bar.
(async()=>{
 const script=h.match(/<script id="custom-font-import-v102">([\s\S]*?)<\/script>/)[1];
 let saved, messages=[];
 const fields=Object.fromEntries(['customFontFile','chooseCustomFont','resetCustomFont','customFontName'].map(k=>[k,input()]));
 const fonts=new Set(), bodyClasses=classes();
 const db={objectStoreNames:{contains:()=>true},transaction(){const tx={objectStore(){return {get(){const r={};queueMicrotask(()=>{r.result=saved;r.onsuccess()});return r},put(rec){saved=rec;queueMicrotask(()=>tx.oncomplete())},delete(){saved=undefined;queueMicrotask(()=>tx.oncomplete())}}}};return tx}};
 const indexedDB={open(){const r={result:db};queueMicrotask(()=>r.onsuccess());return r}};
 const ctx={document:{getElementById:k=>fields[k],fonts,body:{classList:bodyClasses}},indexedDB,Blob,Uint8Array,String,btoa:v=>Buffer.from(v,'binary').toString('base64'),FontFace:class {constructor(family){this.family=family}async load(){return this}},alert:msg=>{throw new Error(msg)}};
 ctx.window=ctx;ctx.webkit={messageHandlers:{themeFont:{postMessage:r=>messages.push(r)}}};
 vm.runInNewContext(script,ctx);await new Promise(setImmediate);
 const buffer=Uint8Array.from([0,1,2,255]).buffer;
 fields.customFontFile.files=[{name:'Theme.ttf',type:'font/ttf',arrayBuffer:async()=>buffer}];
 await fields.customFontFile.events.change();
 assert.equal(messages.at(-1).data,'AAEC/w==');assert(bodyClasses.contains('custom-font-active'));assert.equal(saved.name,'Theme.ttf');
 vm.runInNewContext(script,ctx);await new Promise(setImmediate);
 assert.equal(messages.at(-1).data,'AAEC/w==','saved font must update native tab titles on startup');
 await fields.resetCustomFont.events.click();
 assert(messages.at(-1).reset);assert.equal(saved,undefined);assert(!bodyClasses.contains('custom-font-active'));
 console.log('Passed: font byte transfer, saved startup reload, native reset and font persistence cleanup.');
})().catch(e=>{console.error(e);process.exitCode=1});

// Bottom search persists, is mutually exclusive with top fields and routes to the current page.
const bottomScript=h.match(/<script id="bottom-search-bridge-build13">([\s\S]*?)<\/script>/)[1];
const bottomBody={classList:classes()},bottomFields={bottomSearchEnabled:input(),searchInput:input(),ruleSearch:input(),clearBottomSearch:input(),bottomSearchStatus:{hidden:true,querySelector:()=>bottomLabel,getBoundingClientRect:()=>({height:24})}};
const searchModes=['off','merged','separate'].map(mode=>({...input(),dataset:{bottomSearchMode:mode},classList:classes(),setAttribute(){}}));
bottomFields.bottomSearchModePicker={querySelectorAll:()=>searchModes};bottomFields.bottomSearchModeHint={textContent:''};
const bottomLabel={textContent:''},fallbackSearch={hidden:true};
bottomFields.searchInput.placeholder='首页搜索';bottomFields.ruleSearch.placeholder='规则搜索';
let searchEvents=[];
for(const id of ['searchInput','ruleSearch'])bottomFields[id].dispatchEvent=e=>{searchEvents.push(id);bottomFields[id].events[e.type]?.()};
const searchableFolds=['主题 卡片材质 背景 按钮 字体','使用说明 操作方法','更新日志 Version 1.0.4'].map(textContent=>({textContent,classList:classes()}));
let searchStorage=new Map(),bottomMessages=[];
const bottomCtx={Boolean,String,Event:class{constructor(type){this.type=type}},localStorage:{getItem:k=>searchStorage.get(k),setItem:(k,v)=>searchStorage.set(k,v)},document:{documentElement:{style:style()},body:bottomBody,getElementById:k=>bottomFields[k],querySelector:()=>fallbackSearch,querySelectorAll:()=>searchableFolds}};
bottomCtx.window=bottomCtx;bottomCtx.scrollTo=()=>{};bottomCtx.webkit={messageHandlers:{bottomSearch:{postMessage:v=>bottomMessages.push(v)}}};
vm.runInNewContext(bottomScript,bottomCtx);
assert(!bottomBody.classList.contains('bottom-search-enabled'));assert(fallbackSearch.hidden);
searchModes[1].events.click();
assert(bottomBody.classList.contains('bottom-search-enabled'));assert(!fallbackSearch.hidden);assert.equal(searchStorage.get('youyou.theme.bottomSearchEnabled'),'1');
bottomCtx.__applyBottomSearch('底栏微信');assert.equal(bottomFields.searchInput.value,'底栏微信');assert.equal(searchEvents.at(-1),'searchInput');
bottomBody.classList.add('nav-rules');bottomCtx.__applyBottomSearch('transfer');assert.equal(bottomFields.ruleSearch.value,'transfer');assert.equal(bottomCtx.__bottomSearchState().page,'rules');
bottomBody.classList.remove('nav-rules');bottomBody.classList.add('nav-settings');bottomCtx.__applyBottomSearch('更新日志');assert.equal(searchableFolds.filter(f=>!f.classList.contains('search-hidden')).length,1);
bottomCtx.__applyBottomSearch('');assert(searchableFolds.every(f=>!f.classList.contains('search-hidden')));
bottomCtx.__applyBottomSearch('no match');assert(searchableFolds.every(f=>f.classList.contains('search-hidden')));
bottomCtx.__openBottomSearch();assert.deepEqual(bottomMessages.at(-1),{open:true});
vm.runInNewContext(bottomScript,bottomCtx);assert(searchModes[1].classList.contains('active'),'merged setting must survive reload');
searchModes[2].events.click();assert.equal(bottomMessages.at(-1).layout,'separate');assert.equal(searchStorage.get('youyou.theme.bottomSearchMode'),'separate');
vm.runInNewContext(bottomScript,bottomCtx);assert(searchModes[2].classList.contains('active'),'separate setting must survive reload');
bottomCtx.__applyBottomSearch('更新日志');searchModes[0].events.click();
assert(!bottomBody.classList.contains('bottom-search-enabled'));assert(fallbackSearch.hidden);assert(searchableFolds.every(f=>!f.classList.contains('search-hidden')));
assert.equal(bottomCtx.__bottomSearchState().query,'');assert.equal(bottomFields.searchInput.value,'底栏微信','top field retains its previous query');
vm.runInNewContext(bottomScript,bottomCtx);assert(searchModes[0].classList.contains('active'),'disabled setting must survive reload');
searchStorage.delete('youyou.theme.bottomSearchMode');searchStorage.set('youyou.theme.bottomSearchEnabled','1');searchStorage.set('youyou.theme.bottomSearchLayout','separate');vm.runInNewContext(bottomScript,bottomCtx);assert(searchModes[2].classList.contains('active'),'legacy separate mode migrates');
console.log('Passed: bottom-search on/off persistence, page routing, current query, native opening, clear, zero matches and top-field restoration.');


// Legacy default migration must preserve explicit customization, including the old color.
for (const [seed, expected] of [
  [{'youyou.theme.background.light':'#F4F2EE'},'#F2F2F7'],
  [{'youyou.theme.background':'#F4F2EE'},'#F2F2F7'],
  [{'youyou.theme.background.light':'#123456'},'#123456'],
  [{'youyou.theme.background.light':'#F4F2EE','youyou.theme.background.custom.light':'1'},'#F4F2EE']
]) {
  const saved=new Map(Object.entries(seed));
  const controls=Object.fromEntries(Object.keys(fields).map(k=>[k,input()]));
  const context={...themeCtx,localStorage:{getItem:k=>saved.get(k)||null,setItem:(k,v)=>saved.set(k,v)},document:{...themeCtx.document,documentElement:{dataset:{},style:style()},getElementById:k=>controls[k]}};
  context.window=context;vm.runInNewContext(themeScript,context);
  assert.equal(controls.appBackgroundColor.value,expected);
  controls.appBackgroundColor.value='#345678';controls.appBackgroundColor.events.input();
  assert.equal(saved.get('youyou.theme.background.custom.light'),'1');
  vm.runInNewContext(themeScript,context);assert.equal(controls.appBackgroundColor.value,'#345678');
}
console.log('Passed: old background migration, explicit custom colors and relaunch preservation.');
