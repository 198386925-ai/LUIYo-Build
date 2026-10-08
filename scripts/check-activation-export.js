// Execute the full page and injected authorization UI, including fill -> ZIP -> native bridge.
const fs=require('fs'),assert=require('assert'),{JSDOM,VirtualConsole}=require('jsdom');
const htmlPath=process.argv[2]||'YouYouLUI_iOS/YouYouLUI/Web/index.html';
const swift=fs.readFileSync('YouYouLUI_iOS/YouYouLUI/WebViewController.swift','utf8');
const injected=swift.match(/activationPreviewScript = #"""([\s\S]*?)"""#/)[1];
const html=fs.readFileSync(htmlPath,'utf8').replace('<script src="jszip.min.js"></script>','');
const watchdog=setTimeout(()=>{console.error('Export regression timed out');process.exit(1)},10000);
const errors=[],messages=[],vc=new VirtualConsole();vc.on('jsdomError',e=>errors.push(e.message));
const dom=new JSDOM(html,{url:'https://test.local',runScripts:'dangerously',pretendToBeVisual:true,virtualConsole:vc,beforeParse(w){
 w.setImmediate=setImmediate;w.clearImmediate=clearImmediate;
 w.matchMedia=()=>({matches:false,addEventListener(){},addListener(){}});w.alert=()=>{};
 w.URL.createObjectURL=()=> 'blob:test';w.URL.revokeObjectURL=()=>{};
 w.indexedDB={open(){const r={};setTimeout(()=>r.onerror?.(),1);return r}};
 w.webkit={messageHandlers:new Proxy({},{get:(_,name)=>({postMessage:body=>messages.push({name,body})})})};
}});
(async()=>{const w=dom.window,d=w.document;await new Promise(r=>setTimeout(r,100));
 assert.deepEqual(errors,[],'Initial page execution must not throw');assert(d.querySelectorAll('#list .card').length>0,'Imports must render without switching categories');
 w.eval(injected);const form=d.getElementById('luiyoActivationForm'),field=d.getElementById('luiyoLicenseCode');
 assert(!form.hidden);d.getElementById('fillBtn').click();assert.equal(w.eval('chosen.size'),0,'Unlicensed fill must remain blocked');
 d.querySelector('#homeTools .zip').click();assert(!messages.some(m=>m.name==='zipName'),'Unlicensed export must remain blocked');
 field.value='TEST-CODE';form.dispatchEvent(new w.Event('submit',{bubbles:true,cancelable:true}));
 assert(messages.some(m=>m.name==='activationSubmit'&&m.body.code==='TEST-CODE'));
 w.__luiyoSetAuthorized(false,'检查中',true);assert(field.disabled);assert(!form.hidden);
 w.__luiyoSetAuthorized(true);assert(form.hidden);assert.equal(field.value,'');
 assert(swift.includes('syncAuthorization()\n        updateLayoutMetrics'),'Native authorization must replay after document load');
 assert(!fs.readFileSync('YouYouLUI_iOS/YouYouLUI/AppDelegate.swift','utf8').includes('openActivation()'),'No activation overlay');
 w.eval(fs.readFileSync(htmlPath.replace('index.html','jszip.min.js'),'utf8'));
 w.eval("const generate=JSZip.prototype.generateAsync;JSZip.prototype.generateAsync=async function(options){const bytes=await generate.call(this,{...options,type:'uint8array'});return new Blob([bytes],{type:'application/zip'})}");
 // Pixel conversion is independently tested; keep this regression focused on completion and bridges.
 w.eval("fillFile=new File(['test'],'fill.png',{type:'image/png'}); toPng=async()=>new Uint8Array([1,2,3]);toDarkPng=toPng;toSelectedPng=toPng;");
 d.getElementById('fillBtn').click();assert(w.eval('chosen.size')>0);
 await w.eval('makeZip()');
 assert(messages.some(m=>m.name==='zipName'),'Filled export must request native filename alert');
 w.__shareZipWithName('我的图标');await new Promise(r=>setTimeout(r,100));
 const share=messages.find(m=>m.name==='shareZip');assert(share);assert.equal(share.body.fileName,'我的图标.zip');assert(share.body.base64.startsWith('UEs'),'Share payload must be a ZIP archive');
 w.__luiyoSetAuthorized(false);assert(!form.hidden);assert(!field.disabled);
 console.log('Passed: initial imports, inline activation, busy/authorized/revoked states, full fill -> ZIP -> native rename -> native file share.');
 clearTimeout(watchdog);dom.window.close();
})().catch(e=>{console.error(e);clearTimeout(watchdog);dom.window.close();process.exitCode=1});
