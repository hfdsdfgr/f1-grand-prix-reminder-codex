// Run: node prototypes/car-viewer.test.mjs (Windows Edge, no npm dependencies).
import {spawn} from 'node:child_process';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';

const output=resolve('.tools/evolution-preview');
await mkdir(output,{recursive:true});
const profile=await mkdtemp(`${output}/profile-`);
const browser=spawn(process.env.EDGE_PATH||'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',[
 '--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check',
 '--remote-debugging-port=0',`--user-data-dir=${profile}`,'about:blank'
],{windowsHide:true,stdio:['ignore','ignore','pipe']});
let socket;
const errors=[];
try {
 let endpoint;
 browser.on('error',e=>errors.push(String(e)));
 for(let i=0;i<100;i++){
  try{const [port,path]=(await readFile(`${profile}/DevToolsActivePort`,'utf8')).trim().split(/\r?\n/);endpoint=`ws://127.0.0.1:${port}${path}`;break;}catch{}
  await new Promise(r=>setTimeout(r,200));
 }
 assert.ok(endpoint,'Edge startup timed out');
 socket=new WebSocket(endpoint);
 await new Promise((ok,fail)=>{socket.onopen=ok;socket.onerror=fail});
 let sequence=0;const pending=new Map();
 socket.onmessage=e=>{const m=JSON.parse(e.data);if(m.id){const p=pending.get(m.id);if(p){pending.delete(m.id);clearTimeout(p.timer);m.error?p.fail(new Error(JSON.stringify(m.error))):p.ok(m.result);}}if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails);};
 const send=(method,params={},sessionId)=>new Promise((ok,fail)=>{const id=++sequence,timer=setTimeout(()=>{pending.delete(id);fail(new Error(`CDP timeout: ${method}`))},15000);pending.set(id,{ok,fail,timer});socket.send(JSON.stringify({id,method,params,sessionId}));});
 const {targetId}=await send('Target.createTarget',{url:'about:blank'});
 const {sessionId}=await send('Target.attachToTarget',{targetId,flatten:true});
 const call=(method,params={})=>send(method,params,sessionId);
 const evaluate=async expression=>{const r=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw new Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
 await call('Runtime.enable');await call('Page.enable');
 await call('Emulation.setDeviceMetricsOverride',{width:1440,height:1050,deviceScaleFactor:1,mobile:false});
 await call('Page.navigate',{url:pathToFileURL(resolve('prototypes/car-viewer.html')).href});
 for(let i=0;i<40;i++){if(await evaluate("typeof components !== 'undefined' && typeof labelBoxes !== 'undefined' && width > 100"))break;await new Promise(r=>setTimeout(r,100));}
 const ids=await evaluate('components.map(c=>c.id)');assert.equal(ids.length,13);assert.equal(new Set(ids).size,13);assert.ok(!ids.includes('power_unit'));
 assert.ok(await evaluate('components.every(c=>c.faces.length>0 && c.faces.every(f=>f.points.flat().every(Number.isFinite)))'));
 const html=await readFile('prototypes/car-viewer.html','utf8');
 for(const expression of ['(e.clientX-old.x)*.01*state.speed','(e.clientY-old.y)*.01*state.speed','state.zoom*Math.exp(-e.deltaY*.001)','state.zoom*next/prevDistance'])assert.ok(html.includes(expression));
 const r=await evaluate("(()=>{const r=canvas.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()");
 await call('Input.dispatchMouseEvent',{type:'mousePressed',x:r.x,y:r.y,button:'left',clickCount:1});
 await call('Input.dispatchMouseEvent',{type:'mouseMoved',x:r.x+30,y:r.y+15,button:'left',buttons:1});
 await call('Input.dispatchMouseEvent',{type:'mouseReleased',x:r.x+30,y:r.y+15,button:'left',clickCount:1});
 const rotated=await evaluate('({yaw:state.yaw,pitch:state.pitch})');assert.ok(Math.abs(rotated.yaw-(-.35))<.0001);assert.ok(Math.abs(rotated.pitch-.7)<.0001);
 await call('Input.dispatchMouseEvent',{type:'mouseWheel',x:r.x,y:r.y,deltaX:0,deltaY:-100});
 assert.ok(Math.abs(await evaluate('state.zoom')-Math.exp(.1))<.001);
 await call('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:r.x-40,y:r.y,id:1},{x:r.x+40,y:r.y,id:2}]});
 const beforePinch=await evaluate('state.zoom');
 await call('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:r.x-60,y:r.y,id:1},{x:r.x+60,y:r.y,id:2}]});
 await call('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
 assert.ok(Math.abs(await evaluate('state.zoom')-beforePinch*1.5)<.01);
 for(const id of ids){await evaluate(`$('part').value=${JSON.stringify(id)};$('part').dispatchEvent(new Event('change'))`);assert.equal(await evaluate("$('detail').dataset.part"),id);}
 await evaluate("document.querySelector('[data-team=ferrari]').click();$('generation').value='prototype_ferrari_sf23';$('generation').dispatchEvent(new Event('change'))");
 assert.equal(await evaluate("$('official').hidden"),false);assert.match(await evaluate("$('official').href"),/^https:\/\/www.ferrari.com\//);
 await evaluate("document.querySelector('[data-team=neutral]').click();document.querySelector('[data-view=default]').click();$('part').value='halo';$('part').dispatchEvent(new Event('change'))");
 assert.equal(await evaluate("$('official').hidden"),true);
 const click=await evaluate("(()=>{ctx.save();ctx.setTransform(1,0,0,1,0,0);for(let y=height*.3;y<height*.7;y+=4)for(let x=width*.3;x<width*.7;x+=4){const hit=[...faces].reverse().find(f=>ctx.isPointInPath(f.path,x,y));if(hit&&hit.name!=='halo'){ctx.restore();const r=canvas.getBoundingClientRect();return {x:r.x+x,y:r.y+y,id:hit.name}}}ctx.restore();return null})()");
 assert.ok(click);await call('Input.dispatchMouseEvent',{type:'mousePressed',x:click.x,y:click.y,button:'left',clickCount:1});await call('Input.dispatchMouseEvent',{type:'mouseReleased',x:click.x,y:click.y,button:'left',clickCount:1});
 assert.equal(await evaluate('state.part'),click.id);
 await evaluate("$('part').value='halo';$('part').dispatchEvent(new Event('change'));canvas.blur()");
 const timing=await evaluate('(()=>{const t=performance.now();for(let i=0;i<60;i++)draw();return (performance.now()-t)/60})()');
 for(const [name,width,height,mobile] of [['desktop',1440,1050,false],['mobile',390,844,true],['small',320,740,true],['landscape',844,390,true]]){
  await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile});
  await evaluate('new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))');
  assert.ok(await evaluate('document.documentElement.scrollWidth<=innerWidth'),`${name}: overflow`);
  assert.ok(await evaluate('labelBoxes.every((a,i)=>labelBoxes.slice(i+1).every(b=>a.x+a.width<=b.x || b.x+b.width<=a.x || a.y+a.height<=b.y || b.y+b.height<=a.y))'),`${name}: label overlap`);
  const shot=await call('Page.captureScreenshot',{format:'png'});await writeFile(`${output}/${name}.png`,Buffer.from(shot.data,'base64'));
 }
 assert.deepEqual(errors,[]);
 const asset=await readFile(resolve('prototypes/assets/universal-car.glb'));assert.equal(asset.readUInt32LE(0),0x46546c67);assert.equal(asset.readUInt32LE(4),2);assert.equal(asset.readUInt32LE(8),asset.length);
 const gltf=JSON.parse(asset.subarray(20,20+asset.readUInt32LE(12)).toString());assert.deepEqual(gltf.meshes.map(m=>m.name),ids);
 console.log(JSON.stringify({result:'PASS',components:ids.length,faces:await evaluate('components.reduce((n,c)=>n+c.faces.length,0)'),meanDrawMs:timing,checks:['geometry + GLB structure','rotation delta','wheel + pinch zoom','visible mesh click','13 selections','team/generation link gating','4 responsive sizes','label collisions','no runtime errors'],screenshots:output},null,2));
 await send('Browser.close');
} finally {socket?.close();browser.kill();}
