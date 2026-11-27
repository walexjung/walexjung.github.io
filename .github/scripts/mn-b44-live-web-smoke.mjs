import { chromium } from 'playwright';
import { PNG } from 'pngjs';
import fs from 'node:fs';
import path from 'node:path';

const lang = process.env.QA_LANG || 'ko';
const url = 'https://walexjung.github.io/myeongnyang-test/?lang='+lang+'&qa=MN-B44-live';
const out = path.join('web-qa',lang);
fs.mkdirSync(out,{recursive:true});
const report = {lang,url,started:new Date().toISOString(),steps:[],consoleErrors:[],httpErrors:[],requestsFailed:[],frames:[]};
let browser=null;
const pass=(step,info={})=>{report.steps.push({step,pass:true,...info});console.log('PASS',step,JSON.stringify(info))};
const error=(step,message)=>{report.steps.push({step,pass:false,message:String(message)});console.error('FAIL',step,message)};
const save=()=>fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));
try {
  browser = await chromium.launch({headless:true, args:[
    '--use-gl=angle','--use-angle=swiftshader','--ignore-gpu-blocklist',
    '--enable-unsafe-swiftshader','--enable-webgl','--disable-dev-shm-usage',
    '--autoplay-policy=no-user-gesture-required'
  ]});
  const context=await browser.newContext({viewport:{width:1280,height:720},locale:lang==='ko'?'ko-KR':'en-US',deviceScaleFactor:1});
  const page=await context.newPage();
  page.on('pageerror', e=>report.consoleErrors.push('pageerror: '+e.message));
  page.on('console',m=>{if(m.type()==='error')report.consoleErrors.push('console: '+m.text())});
  page.on('requestfailed',r=>report.requestsFailed.push(r.url()+' '+(r.failure()?.errorText||'')));
  page.on('response',r=>{if(r.status()>=400)report.httpErrors.push(r.status()+' '+r.url())});
  page.setDefaultTimeout(180000);
  const response=await page.goto(url,{waitUntil:'domcontentloaded',timeout:90000});
  if(response.status()!==200)throw new Error('Website HTTP '+response.status());
  pass('site HTTP 200');
  await page.waitForSelector('#canvas');
  const rawConfig=await page.evaluate(()=>JSON.parse(document.documentElement.innerHTML.match(/const GODOT_CONFIG = (\{.*?\});/)?.[1]||'{}'));
  if(rawConfig.fileSizes?.['index.pck']!==70699300)throw new Error('Outdated PCK size in live HTML: '+rawConfig.fileSizes?.['index.pck']);
  pass('MN-B44 full website config',{pckBytes:rawConfig.fileSizes['index.pck'],args:rawConfig.args});
  // The Godot loading overlay is removed only if engine.startGame() resolves.
  await page.waitForFunction(()=>!document.querySelector('#status'),{timeout:180000});
  pass('Godot WebAssembly and PCK runtime fully booted');
  const sound = page.locator('#mn-enable-audio');
  await sound.waitFor({state:'visible',timeout:30000});
  const label=await page.locator('#mn-audio-title').innerText();
  if(lang==='en'&&!label.includes('Enable sound'))throw new Error('Audio overlay not English: '+label);
  if(lang==='ko'&&!label.includes('소리를 켜고'))throw new Error('Audio overlay not Korean: '+label);
  await sound.click();
  await page.waitForFunction(()=>!document.querySelector('#mn-enable-audio'));
  pass('Localized sound-enable overlay and keyboard/canvas focus',{label});
  await page.waitForTimeout(3000);
  const canvas=page.locator('#canvas');
  const box=await canvas.boundingBox();
  if(!box||box.width<600||box.height<300)throw new Error('Canvas not visible or too small');
  pass('Visible game canvas',{box});
  const analyze=async(tag)=>{
    const buf=await canvas.screenshot({path:path.join(out,tag+'.png')});
    const png=PNG.sync.read(buf);
    let varied=0, samples=0, rs=0, gs=0, bs=0;
    // Skip black border, sample 1 in 60 pixels.
    for(let y=5;y<png.height;y+=7)for(let x=5;x<png.width;x+=7){
      const k=(y*png.width+x)*4,r=png.data[k],g=png.data[k+1],b=png.data[k+2];
      if(Math.max(r,g,b)>26) varied++;
      rs+=r;gs+=g;bs+=b;samples++;
    }
    const frame={tag,width:png.width,height:png.height,nonDarkRatio:varied/samples,avgRGB:[rs/samples,gs/samples,bs/samples].map(v=>Math.round(v))};
    report.frames.push(frame);
    console.log('FRAME',JSON.stringify(frame));
    if(frame.nonDarkRatio<0.005)throw new Error('Rendered canvas almost entirely black: '+tag);
    return frame;
  };
  await analyze('launch');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(1400);
  await analyze('after-escape');
  // Mouse and keyboard events reach the live Godot canvas. Screenshots are artifacts,
  // not evidence of completing any puzzles or hearing sound.
  await canvas.click({position:{x:Math.floor(box.width*0.5),y:Math.floor(box.height*0.55)}});
  await page.waitForTimeout(2000);
  await analyze('after-mouse-click');
  pass('Live WebGL rendering and actual mouse/keyboard input accepted',{frames:report.frames.length});
  // HTTP failures, fatal page errors distinguish navigation from successful boot.
  const critical=report.consoleErrors.filter(x=>/Uncaught|out of memory|WebAssembly\.RuntimeError|SCRIPT ERROR|Failed loading file/i.test(x));
  if(critical.length)throw new Error('Fatal JS/game errors: '+critical.slice(0,5).join(' | '));
  if(report.httpErrors.length)throw new Error('Failed HTTP responses: '+report.httpErrors.join(' | '));
  pass('No fatal JS exceptions or HTTP request errors',{consoleErrorCount:report.consoleErrors.length,failedRequests:report.requestsFailed.length});
  report.success=true;
} catch(e){
  report.success=false;
  error('Live browser smoke',String(e?.stack||e));
  process.exitCode=1;
} finally {
  report.finished=new Date().toISOString();
  save();
  if(browser)await browser.close();
}
