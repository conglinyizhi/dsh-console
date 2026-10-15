import { spawn } from 'node:child_process'
const CDP_PORT = 9911
const [baseUrl] = process.argv.slice(2)
const chrome = spawn('chromium', ['--headless','--no-sandbox','--disable-gpu','--hide-scrollbars','--remote-debugging-port='+CDP_PORT,'--user-data-dir=/tmp/chrome-dbg-'+process.pid,'--window-size=1280,1000','about:blank'], { stdio: 'ignore' })
let page=null
for (let i=0;i<60&&!page;i++){ try{ const l=await (await fetch('http://127.0.0.1:'+CDP_PORT+'/json')).json(); page=l.find(t=>t.type==='page') }catch{} if(!page) await new Promise(r=>setTimeout(r,250)) }
const ws=new WebSocket(page.webSocketDebuggerUrl); let id=0; const pending=new Map()
ws.onmessage=e=>{const m=JSON.parse(e.data); if(m.id&&pending.has(m.id)){pending.get(m.id)(m);pending.delete(m.id)}}
await new Promise(r=>{ws.onopen=r})
const send=(m,p={})=>new Promise(res=>{const i=++id;pending.set(i,res);ws.send(JSON.stringify({id:i,method:m,params:p}))})
const ev=async(x)=>(await send('Runtime.evaluate',{expression:x,returnByValue:true,awaitPromise:true})).result?.result?.value
await send('Runtime.enable'); await send('Page.enable')
await send('Page.navigate',{url:baseUrl})
for (let i=0;i<40;i++){ await new Promise(r=>setTimeout(r,300)); if (await ev("document.querySelectorAll('[data-name=instance-card]').length")) break }
const dump = `(() => {
  const rows = [...document.querySelectorAll('.dsh-rows')];
  return JSON.stringify({
    containers: rows.length,
    perContainer: rows.map(r => [...r.children].map(c => c.dataset.instance || c.className)),
    allCards: [...document.querySelectorAll('[data-name=instance-card]')].map(c => c.dataset.instance),
  });
})()`
for (const t of [0, 1500, 3000]) {
  await new Promise(r=>setTimeout(r,t))
  console.log('t+'+t, await ev(dump))
}
// 页面里自己跑一遍排序期望
console.log('fetch order:', await ev(`fetch('/api/local/profiles').then(r=>r.json()).then(j=>JSON.stringify(j.data.profiles.map(p=>p.name)))`))
chrome.kill(); process.exit(0)
