import assert from 'node:assert/strict';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import dns from 'node:dns';
import { syncBuiltinESMExports } from 'node:module';
import { zstdDecompressSync } from 'node:zlib';
import fs from 'node:fs/promises';
import path from 'node:path';
const registered=JSON.parse(await fs.readFile(new URL('./controls.json',import.meta.url)));
const selection=process.argv[2];
const names=selection==='independent'?registered.filter(x=>x!=='mo'):selection?.split(',');
assert(names?.length>0 && names.every(n=>registered.includes(n)) && new Set(names).size===names.length,'unknown/empty control selection');
const realFetch=globalThis.fetch, connect=net.Socket.prototype.connect;
const ports=new Set(), sockets=new Set(); let denied=0;
const deny=()=>{denied++;throw new Error('egress denied');};
net.Socket.prototype.connect=function(...args){const v=Array.isArray(args[0])?args[0][0]:args[0];if(typeof v!=='object'||v.host!=='127.0.0.1'||!ports.has(Number(v.port)))return deny();return connect.apply(this,args);};
http.request=http.get=https.request=https.get=tls.connect=dns.resolve=deny;
dns.lookup=(host,options,callback)=>{if(host!=='127.0.0.1')return deny();const cb=typeof options==='function'?options:callback;queueMicrotask(()=>cb(null,'127.0.0.1',4));};
for(const key of Object.keys(dns.promises))if(typeof dns.promises[key]==='function')dns.promises[key]=deny;
globalThis.fetch=globalThis.WebSocket=deny;
syncBuiltinESMExports();
// Egress is denied before the first provider import.
const { startBridge }=await import('./server.mjs');
const { schemas, structuredResult, LIMITS }=await import('./protocol.mjs');
const { journal }=await import('./journal.mjs');
const canary='synthetic-secret-CANARY-never-public';
const token='synthetic.'+Buffer.from(JSON.stringify({'https://api.openai.com/auth':{chatgpt_account_id:'fixture'}})).toString('base64url')+'.synthetic';
const usage=n=>({input_tokens:n,output_tokens:0,total_tokens:n,input_tokens_details:{cached_tokens:0,cache_write_tokens:0}});
const text={type:'message',id:'msg_1',role:'assistant',status:'completed',content:[{type:'output_text',text:'finished'}]};
const tool=(name='read_file',args={path:'a'})=>({type:'function_call',id:'fc_1',call_id:'call_1',name,arguments:JSON.stringify(args)});
const reasoning={type:'reasoning',id:'rs_1',encrypted_content:'opaque-native-signature',summary:[]};
const events=(items=[text],u=usage(15))=>[...items.map((item,output_index)=>({type:'response.output_item.done',item,output_index})),{type:'response.completed',response:{id:'resp_1',status:'completed',output:items,...(u===null?{}:{usage:u})}}];
const encode=es=>es.map(e=>'data: '+JSON.stringify(e)+'\n\n').join('');
const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
let scenario, observations=[], count=0;
const fixture=http.createServer((req,res)=>{
  let chunks=[];
  req.on('data',c=>chunks.push(c));
  req.on('end',()=>{
    const bytes=Buffer.concat(chunks);
    scenario.requests.push(JSON.parse((req.headers['content-encoding']==='zstd'?zstdDecompressSync(bytes):bytes).toString()));
    const f=scenario.responses.shift()??{};
    res.writeHead(f.status??200,{'content-type':'text/event-stream','x-secret':canary});
    if(f.hang){res.write(': wait\n\n');return;}
    res.end(f.raw??encode(f.events??events()));
  });
});
fixture.on('connection',s=>{sockets.add(s);s.on('close',()=>sockets.delete(s));});
await new Promise(r=>fixture.listen(0,'127.0.0.1',r));ports.add(fixture.address().port);
const root=await fs.mkdtemp(path.resolve('bridge/evidence/private-'));
const options=dir=>({runId:'r_1',goal:'fixture goal',grants:['read_file'],journalPath:path.join(dir,'journal.json'),accessToken:token,fetch:(_url,init)=>realFetch(`http://127.0.0.1:${fixture.address().port}/sse`,init)});
async function setup(responses=[],extra={}){
  const dir=await fs.mkdtemp(path.join(root,'case-'));await fs.chmod(dir,0o700);
  scenario={responses,requests:[],dir};
  scenario.bridge=await startBridge({...options(dir),...extra});ports.add(scenario.bridge.port);
  return scenario;
}
function request(transcript=[],extra={}){return {goal:'fixture goal',tools:['read_file'],transcript,...extra};}
async function send(value=request(),extra={}){
  const response=await realFetch(`http://127.0.0.1:${scenario.bridge.port}/complete`,{method:'POST',headers:{'content-type':'application/json','x-run':'r_1'},body:JSON.stringify(value),signal:AbortSignal.timeout(18000),...extra});
  return {status:response.status,body:await response.json()};
}
function steps(offer,n=1,result='file with literal error word',refused=false){return [{n,kind:'model',name:'model',args:{},result:JSON.stringify({tool:offer.tool,args:offer.args}),tokens:offer.tokens,took_ms:0,refused:false},{n:n+1,kind:'tool',name:offer.tool,args:offer.args,result,tokens:0,took_ms:1,refused}];}
async function rawRequest(wire){
  return await new Promise((resolve,reject)=>{const socket=net.connect({host:'127.0.0.1',port:scenario.bridge.port});let output='';socket.setTimeout(5000,()=>{socket.destroy();reject(new Error('raw timeout'));});socket.on('data',c=>output+=c);socket.on('close',()=>resolve(output));socket.on('error',()=>{});socket.on('connect',()=>socket.write(wire));});
}
async function reject(value,expectedCalls=1,extra={}){const r=await send(value,extra);assert.notEqual(r.status,200);assert.equal(scenario.requests.length,expectedCalls);assert(!JSON.stringify(r).includes(canary));return r;}
async function offered(extra={}){await setup([{events:events([reasoning,tool()])},{}],extra);const r=await send();assert.equal(r.status,200);return r.body;}
async function finish(){
  if(!scenario)return;
  if(scenario.bridge){await scenario.bridge.stop();assert.equal(scenario.bridge.resources().listening,false);await wait(0);assert.equal(scenario.bridge.resources().sockets,0);ports.delete(scenario.bridge.port);}
  for(const s of sockets)s.destroy();
  const state=scenario.bridge?.inspect();
  observations.push({control:count,requests:scenario.requests,state});
  const saved=await fs.readFile(path.join(scenario.dir,'journal.json'),'utf8').catch(()=>'');
  assert(!saved.includes(token));assert(!saved.includes(canary));
  scenario=null;
}
async function variant(fn){try{await fn();}finally{await finish();}}
const controls={
  final:async()=>{await setup();const r=await send();assert.deepEqual(r,{status:200,body:{done:'finished',tokens:15}});assert.equal(scenario.bridge.inspect().outcome,'final-offered');await reject(request(),1);},
  continuation:async()=>{const o=await offered();const t=steps(o);const r=await send(request(t));assert.equal(r.status,200);assert.equal(scenario.requests.length,2);const j=JSON.parse(await fs.readFile(path.join(scenario.dir,'journal.json')));assert.deepEqual(j.prefix,t);assert.equal(j.messages[3].toolCallId,'call_1|fc_1');assert.equal(j.messages[3].isError,false);},
  native:async()=>{const o=await offered();const native=scenario.bridge.inspect().messages[2];await send(request(steps(o)));const input=scenario.requests[1].input;assert(input.some(x=>x.type==='reasoning'&&x.encrypted_content==='opaque-native-signature'));assert(input.some(x=>x.type==='function_call'&&x.call_id==='call_1'&&x.id==='fc_1'));assert(input.some(x=>x.type==='function_call_output'&&x.call_id==='call_1'));assert.deepEqual(scenario.bridge.inspect().messages[2],native);},
  schemas:async()=>{assert.throws(()=>schemas(['read_file','read_file']));assert.throws(()=>schemas(['unknown']));for(const name of ['list_files','read_file','search','write_file','exact_edit','command']){const s=schemas([name])[0];assert.equal(s.parameters.additionalProperties,false);assert.deepEqual(s.parameters.required,Object.keys(s.parameters.properties));}for(const item of [tool('read_file',{path:12}),tool('read_file',{}),tool('read_file',{path:'a',extra:'x'}),tool('command',{command:'x'})])await variant(async()=>{await setup([{events:events([item])}]);await reject(request());});},
  usage:async()=>{await setup();assert.equal((await send()).body.tokens,15);assert.equal(scenario.bridge.inspect().tokens,15);},
  zero:async()=>{await setup([{events:events([text],usage(0))}]);assert.deepEqual((await send()).body,{done:'finished',tokens:0});},
  'unknown-usage':async()=>{for(const u of [null,{input_tokens:3}])await variant(async()=>{await setup([{events:events([tool()],u)}]);assert.equal((await reject(request())).body.error,'unknown_usage');assert.equal(scenario.bridge.inspect().offered,null);});},
  overflow:async()=>{await setup([{events:events([tool()],usage(Number.MAX_SAFE_INTEGER+1))}]);assert.equal((await reject(request())).body.error,'unknown_usage');},
  overshoot:async()=>{await setup([{events:events([tool()],usage(4097))}]);const o=(await send()).body;assert.equal(o.tokens,4097);await reject(request(steps(o)));assert.equal(scenario.requests.length,1);},
  duplicate:async()=>{await offered();await reject(request());await reject(request());},
  stale:async()=>{await setup([{events:events([tool()])},{events:events([tool()])}]);const o=(await send()).body,t=steps(o);assert.equal((await send(request(t))).status,200);await reject(request(t),2);},
  altered:async()=>{await setup([{events:events([tool()])},{events:events([tool()])}]);const o=(await send()).body,t=steps(o);const next=(await send(request(t))).body;t[1].result='altered';await reject(request([...t,...steps(next,3)]),2);},
  skipped:async()=>{for(const mutate of [t=>t.slice(0,1),t=>{t[0].n=2;return t;},t=>[...t,...t]])await variant(async()=>{const o=await offered();await reject(request(mutate(steps(o))));});},
  mismatched:async()=>{for(const mutate of [t=>t[1].name='search',t=>t[1].args.path='b',t=>t[0].tokens++,t=>t[1].tokens=1,t=>t[0].refused=true,t=>t[0].name='other',t=>t[0].args={path:'a'},t=>t[1].took_ms=-1,t=>t[1].refused='false',t=>t[0].result='{}',t=>t[1].extra=true])await variant(async()=>{const o=await offered();const t=steps(o);mutate(t);await reject(request(t));});},
  identity:async()=>{for(const value of [request([],{goal:'changed'}),request([],{tools:[]}),request([],{tools:['read_file','read_file']}),request([{n:1}])])await variant(async()=>{await setup();await reject(value,0);});await variant(async()=>{await setup();await reject(request(),0,{headers:{'content-type':'application/json','x-run':'foreign'}});});},
  concurrent:async()=>{await setup([{hang:true}]);const first=send().catch(()=>null);while(scenario.requests.length<1)await wait(5);const second=await send();assert.equal(second.status,409);const a=await first;assert(a===null||a.status!==200);assert.equal(scenario.requests.length,1);assert.equal(scenario.bridge.inspect().outcome,'uncertain');},
  restart:async()=>{const s=await setup();await scenario.bridge.stop();for(const bytes of ['', '{bad', '{}']){await fs.writeFile(path.join(s.dir,'journal.json'),bytes);await assert.rejects(startBridge(options(s.dir)));}const dir=await fs.mkdtemp(path.join(root,'unsafe-'));await fs.chmod(dir,0o755);await assert.rejects(startBridge(options(dir)));await fs.chmod(dir,0o700);await fs.symlink(path.join(s.dir,'journal.json'),path.join(dir,'journal.json'));await assert.rejects(startBridge(options(dir)));},
  journal:async()=>{await setup();const f=path.join(scenario.dir,'journal.json');await fs.unlink(f);await fs.mkdir(f);await reject(request(),0);assert.equal(scenario.bridge.inspect().outcome,'uncertain');},
  lost:async()=>{await setup([{hang:true}]);const controller=new AbortController();const pending=send(request(),{signal:controller.signal}).catch(()=>null);while(scenario.requests.length<1)await wait(5);controller.abort();await pending;await wait(50);assert.equal(scenario.bridge.inspect().outcome,'uncertain');await reject(request());},
  auth401:async()=>{await setup([{status:401,raw:JSON.stringify({error:{message:canary},token:canary})}]);assert.equal((await send()).status,401);await reject(request());},
  provider:async()=>{for(const f of [{status:503,raw:canary},{raw:'data: '+JSON.stringify({type:'error',message:canary})+'\n\n'}])await variant(async()=>{await setup([f]);await reject(request());await reject(request());});},
  deadlines:async()=>{await variant(async()=>{await setup([{hang:true}]);const before=Date.now();await reject(request());assert(Date.now()-before<5000);});await variant(async()=>{await setup();const socket=net.connect({host:'127.0.0.1',port:scenario.bridge.port});socket.on('error',()=>{});socket.write('POST /complete HTTP/1.1\r\nHost: localhost\r\nx-run: r_1\r\nContent-Type: application/json\r\nContent-Length: 100\r\n\r\n{');await wait(2300);socket.destroy();assert.equal(scenario.requests.length,0);assert(['uncertain','terminal'].includes(scenario.bridge.inspect().outcome));});await variant(async()=>{await setup();await wait(30200);assert.equal(scenario.bridge.inspect().reason,'session_timeout');assert.equal(scenario.requests.length,0);});},
  stop:async()=>{let resolve;await setup([],{fetch:()=>new Promise(r=>{resolve=r;})});const p=send().catch(()=>null);while(!resolve)await wait(5);await scenario.bridge.stop();const state=scenario.bridge.inspect();resolve(new Response(encode(events())));await p;await wait(50);assert.deepEqual(scenario.bridge.inspect(),state);assert.equal(state.offered,null);},
  limits:async()=>{await variant(async()=>{await setup();await reject(request([],{goal:'é'.repeat(40000)}),0);});await variant(async()=>{await setup([{events:events([tool('read_file',{path:'x'.repeat(31000)})])}]);const o=(await send()).body;assert(o.tool);await reject(request(steps(o,1,'x'.repeat(31000))));});await variant(async()=>{const goal='g'.repeat(30000);await setup([{events:events([{...reasoning,encrypted_content:'s'.repeat(10000)},tool()])}],{goal});const o=(await send(request([],{goal}))).body;assert(o.tool);const r=await reject(request(steps(o,1,'x'.repeat(30000)),{goal}));assert.equal(r.body.error,'context_limit');});
    await variant(async()=>{await setup(Array.from({length:8},()=>({events:events([tool()])})));let transcript=[];for(let i=0;i<8;i++){const r=await send(request(transcript));assert.equal(r.status,200);transcript.push(...steps(r.body,transcript.length+1));}const r=await reject(request(transcript),8);assert.equal(r.body.error,'budget');});
    const dir=await fs.mkdtemp(path.join(root,'limit-'));await fs.chmod(dir,0o700);const j=await journal(path.join(dir,'journal'));await assert.rejects(j.write({x:'x'.repeat(LIMITS.journalBytes)}));},
  structured:async()=>{for(const [name,result,refused,isError,terminal] of [['read_file','error: literal content',false,false,false],['exact_edit',JSON.stringify({state:'success',error_code:'none',execution:'completed'}),false,false,false],['exact_edit',JSON.stringify({state:'refusal',error_code:'missing_match',execution:'not_started'}),true,true,false],['command',JSON.stringify({state:'timeout',error_code:'transport',execution:'unknown'}),false,true,true]]){assert.deepEqual(structuredResult(name,result,refused),{isError,terminal});}assert.throws(()=>structuredResult('command','{"state":"success","execution":"unknown","error_code":"none"}',false));
    for(const state of ['success','failure','refusal'])await variant(async()=>{const result={version:1,run_id:'r_1',call_id:'2',workspace_id:'fixture',state,exit_code:state==='refusal'?null:state==='success'?0:2,stdout:'literal error word',stderr:'',stdout_truncated:false,stderr_truncated:false,elapsed_ms:0,error_code:state==='success'?'none':state==='failure'?'command_failed':'refused',execution:state==='refusal'?'not_started':'completed'};await setup([{events:events([tool('command',{command:'inert'})])},{}],{grants:['command']});const o=(await send(request([],{tools:['command']}))).body;const r=await send(request(steps(o,1,JSON.stringify(result),state==='refusal'),{tools:['command']}));assert.equal(r.status,200);assert.equal(scenario.bridge.inspect().messages[3].isError,state!=='success');assert.equal(scenario.bridge.inspect().messages[3].content[0].text,JSON.stringify(result));});await setup([{events:events([tool('exact_edit',{path:'a',old_text:'a',new_text:'b'})])}],{grants:['exact_edit']});const o=(await send(request([],{tools:['exact_edit']}))).body;const t=steps(o,1,JSON.stringify({state:'failure',error_code:'write',execution:'unknown'}));await reject(request(t,{tools:['exact_edit']}));assert.equal(scenario.bridge.inspect().reason,'tool_terminal');},
  sanitization:async()=>{assert.throws(()=>globalThis.fetch('https://outside.invalid'));assert.throws(()=>net.connect(443,'outside.invalid'));assert.throws(()=>https.get('https://outside.invalid'));assert(denied>=3);await setup([{raw:'data: {bad '+canary+'\n\n'}]);await reject(request());},
  http:async()=>{for(const extra of [{method:'PUT'},{headers:{'content-type':'text/plain','x-run':'r_1'}},{body:'{bad'},{body:'[]'}])await variant(async()=>{await setup();await reject(request(),0,extra);});
    for(const wire of ['POST /complete HTTP/1.1\r\nHost: localhost\r\nx-run: r_1\r\nx-run: r_1\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}', 'POST /complete HTTP/1.1\r\nHost: localhost\r\nx-run: r_1\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n10001\r\n'+'x'.repeat(65537)+'\r\n0\r\n\r\n'])await variant(async()=>{await setup();const response=await rawRequest(wire);assert(response.startsWith('HTTP/1.1 422'),response);assert.equal(scenario.requests.length,0);});},
  mo:async()=>{const {moControl}=await import('./mo.mjs');await moControl({root,start:setup,finish,ports,token,realFetch,providerPort:fixture.address().port,tool,reasoning,events,observations});},
};
try {
  assert(names?.length>0 && names.every(n=>Object.hasOwn(controls,n)) && new Set(names).size===names.length,'unknown/empty control selection');
  assert.deepEqual(Object.keys(controls),registered);assert(registered.length<=28);
  for(const name of names){count++;try{await controls[name]();console.log(`ok ${count} - ${name}`);}catch(e){console.log(`not ok ${count} - ${name}`);throw e;}finally{await finish();}}
  console.log(`PASS ${count} named controls; denied egress=${denied}; Node=${process.version}; Mo gate=${names.includes('mo')?'released':'not run'}`);
} finally {
  for(const s of sockets)s.destroy();fixture.closeAllConnections();await new Promise(r=>fixture.close(r));
  await fs.writeFile(process.argv[3],JSON.stringify(observations,null,2)+'\n');
  console.log('cleanup fixture sockets='+sockets.size+'; all bridge stop calls awaited');
}
