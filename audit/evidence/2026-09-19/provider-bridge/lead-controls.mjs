// Independent actual-parser HTTP controls; all credentials/data are synthetic.
import assert from 'node:assert/strict';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import dns from 'node:dns';
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { syncBuiltinESMExports } from 'node:module';
import { zstdDecompressSync } from 'node:zlib';
const provider=path.resolve(process.argv[2]);
const output=path.resolve(process.argv[3]);
const realFetch=globalThis.fetch;
const connect=net.Socket.prototype.connect;
const ports=new Set(), sockets=new Set();
let denied=0;
function deny(){denied++;throw new Error('unexpected egress');}
net.Socket.prototype.connect=function(...args){const v=Array.isArray(args[0])?args[0][0]:args[0];if(typeof v!=='object'||v.host!=='127.0.0.1'||!ports.has(Number(v.port)))return deny();return connect.apply(this,args);};
http.request=http.get=https.request=https.get=tls.connect=dns.resolve=deny;
dns.lookup=(host,options,callback)=>{if(host!=='127.0.0.1')return deny();queueMicrotask(()=>(typeof options==='function'?options:callback)(null,'127.0.0.1',4));};
for(const key of Object.keys(dns.promises))if(typeof dns.promises[key]==='function')dns.promises[key]=deny;
globalThis.fetch=globalThis.WebSocket=deny;
syncBuiltinESMExports();
const {startBridge}=await import(pathToFileURL(path.join(provider,'bridge/server.mjs')));
const temp=await fs.mkdtemp(path.join(path.dirname(output),'extra-private-'));
const token='synthetic.'+Buffer.from(JSON.stringify({'https://api.openai.com/auth':{chatgpt_account_id:'lead-fixture'}})).toString('base64url')+'.synthetic';
const goal='Read café / é and report 🌙';
const args={path:'café/é-🌙.txt'};
const content='literal error\n中文 café é 🌙\n{"nested":"data"}';
const final='Lu 👩🏽‍💻\ncompleted 🌙';
const requests=[],checks=[];let bridge;
function usage(n){return {input_tokens:n,output_tokens:0,total_tokens:n,input_tokens_details:{cached_tokens:0,cache_write_tokens:0}};}
function sse(items,n){return [...items.map((item,output_index)=>({type:'response.output_item.done',item,output_index})),{type:'response.completed',response:{id:'lead-response',status:'completed',output:items,usage:usage(n)}}].map(x=>'data: '+JSON.stringify(x)+'\n\n').join('');}
const fixture=http.createServer((req,res)=>{
 let bytes=0,chunks=[];
 req.on('data',c=>{bytes+=c.length;if(bytes>65536)req.destroy();else chunks.push(c);});
 req.on('end',()=>{
  const wire=Buffer.concat(chunks);
  requests.push(JSON.parse((req.headers['content-encoding']==='zstd'?zstdDecompressSync(wire):wire).toString()));
  const items=requests.length===1?[{type:'reasoning',id:'rs_lead',encrypted_content:'opaque-lead-signature',summary:[]},{type:'function_call',id:'fc_lead',call_id:'call_lead',name:'read_file',arguments:JSON.stringify(args)}]:[{type:'message',id:'msg_lead',role:'assistant',status:'completed',content:[{type:'output_text',text:final}]}];
  res.writeHead(200,{'content-type':'text/event-stream'});res.end(sse(items,requests.length===1?0:7));
 });
});
fixture.on('connection',s=>{sockets.add(s);s.setTimeout(2000,()=>s.destroy());s.on('close',()=>sockets.delete(s));});
await new Promise(r=>fixture.listen(0,'127.0.0.1',r));ports.add(fixture.address().port);
async function start(name){const dir=path.join(temp,name);await fs.mkdir(dir,{mode:0o700});bridge=await startBridge({runId:'lead-run',goal,grants:['read_file'],journalPath:path.join(dir,'journal.json'),accessToken:token,fetch:(_url,init)=>realFetch(`http://127.0.0.1:${fixture.address().port}/sse`,init)});ports.add(bridge.port);return dir;}
async function stop(){if(bridge){await bridge.stop();await new Promise(r=>setTimeout(r,10));assert.deepEqual(bridge.resources(),{listening:false,sockets:0,active:false});ports.delete(bridge.port);bridge=null;}}
async function send(body){const r=await realFetch(`http://127.0.0.1:${bridge.port}/complete`,{method:'POST',headers:{'content-type':'application/json','x-run':'lead-run'},body,signal:AbortSignal.timeout(5000)});const wire=Buffer.from(await r.arrayBuffer());assert.equal(Number(r.headers.get('content-length')),wire.length);return {status:r.status,body:JSON.parse(wire.toString())};}
try{
 const dir=await start('unicode');
 const first=await send(JSON.stringify({goal,tools:['read_file'],transcript:[]}));
 assert.deepEqual(first,{status:200,body:{tool:'read_file',args,tokens:0}});
 const steps=[{n:1,kind:'model',name:'model',args:{},result:JSON.stringify({tool:'read_file',args}),tokens:0,took_ms:0,refused:false},{n:2,kind:'tool',name:'read_file',args,result:content,tokens:0,took_ms:1,refused:false}];
 const second=await send(JSON.stringify({goal,tools:['read_file'],transcript:steps}));
 assert.deepEqual(second,{status:200,body:{done:final,tokens:7}});
 assert.equal(requests.length,2);
 const state=JSON.parse(await fs.readFile(path.join(dir,'journal.json'),'utf8'));
 assert.deepEqual(state.prefix,steps);assert.equal(state.tokens,7);assert.equal(state.outcome,'final-offered');
 assert.equal(state.messages[3].toolCallId,'call_lead|fc_lead');assert.equal(state.messages[3].content[0].text,content);assert.equal(state.messages[3].isError,false);
 assert(requests[1].input.some(x=>x.type==='reasoning'&&x.encrypted_content==='opaque-lead-signature'));
 assert(requests[1].input.some(x=>x.type==='function_call_output'&&x.call_id==='call_lead'&&x.output===content));
 checks.push({name:'unicode-native-continuation',passed:true,provider_calls:2,reported_tokens:7,steps,final:second.body});
 await stop();
 await start('invalid-utf8');
 const invalid=await send(Buffer.from([0x7b,0x22,0x78,0x22,0x3a,0x22,0xc3,0x28,0x22,0x7d]));
 assert.equal(invalid.status,422);assert.equal(requests.length,2);assert.equal(bridge.inspect().calls.length,0);
 checks.push({name:'invalid-utf8-before-dispatch',passed:true,provider_calls:0,status:invalid.status});
 await stop();
 assert.equal(denied,0);console.log('PASS 2 independent bridge controls; actual HTTP provider calls=2');
}finally{
 await stop();for(const s of sockets)s.destroy();fixture.closeAllConnections();await new Promise(r=>fixture.close(r));await new Promise(r=>setTimeout(r,10));
 await fs.writeFile(output,JSON.stringify({checks,requests,denied,fixtureSockets:sockets.size},null,2)+'\n');await fs.rm(temp,{recursive:true,force:true});assert.equal(sockets.size,0);
}
