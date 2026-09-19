import http from 'node:http';
import { randomUUID, createHash } from 'node:crypto';
import fs from 'node:fs/promises';
import { turn } from '../turn.mjs';
import { journal } from './journal.mjs';
import { LIMITS, instruction, schemas, continuation, fields, same, integer, validArgs, requireThat } from './protocol.mjs';
const size = v => Buffer.byteLength(JSON.stringify(v));
const digest = v => createHash('sha256').update(v).digest('hex');

/** Trusted operator API. Provision once, outside candidate storage; no auth lookup. */
export async function startBridge({runId, goal, grants, journalPath, accessToken, fetch:transport, port=0}) {
  requireThat(typeof runId==='string' && runId.length>0 && typeof goal==='string' && typeof accessToken==='string' && accessToken.length>0 && typeof transport==='function' && port===0);
  const tools=schemas(grants);
  grants=structuredClone(grants);
  requireThat(size({goal,tools})<=LIMITS.bytes);
  const identity={provider:'openai-codex',model:'gpt-6-astra',reasoning:'low',transport:'sse',retries:0,
    source:'36b60d2e8985899743c4cf5bd5f8929832a3f05d',catalog:digest(await fs.readFile(new URL('../catalog.json',import.meta.url))),
    adapter:digest(await fs.readFile(new URL('../turn.mjs',import.meta.url))),bridge:await Promise.all(['server.mjs','protocol.mjs','journal.mjs'].map(async name=>({name,sha256:digest(await fs.readFile(new URL(name,import.meta.url)))}))),schemas:digest(JSON.stringify(tools)),instruction:digest(instruction),limits:LIMITS};
  const log=await journal(journalPath);
  const state={version:1,session:randomUUID(),runId,goal,grants,identity,prefix:[],offered:null,callId:null,
    messages:[{role:'system',content:instruction,timestamp:Date.now()},{role:'user',content:goal,timestamp:Date.now()}],calls:[],tokens:0,outcome:'ready'};
  requireThat(size({messages:state.messages,tools})<=LIMITS.bytes);
  await log.write(state);
  const expires=performance.now()+LIMITS.sessionMs;
  let active=null, terminal=false, stopping=null;
  const sockets=new Set();
  const remaining=()=>Math.max(0,Math.min(LIMITS.waitMs,expires-performance.now()));
  async function end(code, uncertain=false) {
    if (terminal) return;
    terminal=true;
    if(state.outcome==='final-offered' && !active && ['stopped','session_timeout'].includes(code)) return;
    state.outcome=uncertain?'uncertain':'terminal'; state.reason=code;
    active?.controller.abort();
    log.invalidate();
    try { await log.write(state); } catch { /* Existing journal is still a non-resumable tombstone. */ }
  }
  function error(res,status,code) {
    if (res.destroyed || res.writableEnded) return;
    const payload=JSON.stringify({error:code});
    res.writeHead(status,{'content-type':'application/json','content-length':Buffer.byteLength(payload),'connection':'close'});
    res.end(payload);
  }
  async function bounded(promise, ms, code) {
    let timer;
    try { return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error(code)),ms);})]); }
    finally { clearTimeout(timer); }
  }
  async function body(req) {
    const chunks=[]; let bytes=0;
    await bounded(new Promise((resolve,reject)=>{
      req.on('data',chunk=>{ bytes+=chunk.length; if(bytes>LIMITS.bytes) {reject(new Error('body_limit')); req.pause();} else chunks.push(chunk); });
      req.once('end',resolve); req.once('error',()=>reject(new Error('disconnect'))); req.once('aborted',()=>reject(new Error('disconnect')));
    }),remaining(),'body_timeout');
    return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks)));
  }
  async function handle(req,res) {
    req.socket.setTimeout(LIMITS.waitMs+LIMITS.closeMs,()=>req.socket.destroy());
    if (terminal || state.outcome==='final-offered') { await end('reused'); error(res,409,'terminal'); return; }
    if (active) { await end('concurrent',true); error(res,409,'concurrent'); return; }
    const current={controller:new AbortController()}; active=current;
    let delivered=false;
    const disconnected=()=>{if(!delivered) void end('disconnect',true);};
    res.once('close',disconnected);
    try {
      requireThat(remaining()>0,'session_timeout');
      const headers=req.rawHeaders;
      const runs=headers.filter((_,i)=>i%2===0 && headers[i].toLowerCase()==='x-run');
      requireThat(req.method==='POST' && req.url==='/complete' && runs.length===1 && req.headers['x-run']===runId &&
        /^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(req.headers['content-type']??''),'protocol');
      const value=await body(req);
      requireThat(!terminal,'terminal');
      requireThat(fields(value,['goal','tools','transcript']) && value.goal===goal && same(value.tools,grants),'protocol');
      const native=continuation(state,value.transcript);
      if(native) {
        const {terminal:toolTerminal,...message}=native;
        state.prefix=structuredClone(value.transcript); state.messages.push(message);
        state.offered=null; state.callId=null;
        await log.write(state); // Acknowledged continuation is persisted before any dispatch intent.
        if(toolTerminal) { await end('tool_terminal'); error(res,422,'tool_terminal'); return; }
      }
      requireThat(!terminal && remaining()>0,'terminal');
      requireThat(state.tokens<LIMITS.tokens && state.prefix.length<LIMITS.steps,'budget');
      requireThat(size({messages:state.messages,tools})<=LIMITS.bytes,'context_limit');
      state.outcome='dispatch-intent';
      state.calls.push({n:state.calls.length+1,usage:{status:'unknown'},outcome:'dispatch-intent'});
      await log.write(state);
      requireThat(!terminal && remaining()>0,'terminal');
      const result=await bounded(turn({context:{messages:structuredClone(state.messages)},tools,accessToken,fetch:transport,
        signal:current.controller.signal,deadlineMs:remaining()}),remaining(),'provider_timeout');
      requireThat(!terminal && !current.controller.signal.aborted && remaining()>0,'terminal');
      const call=state.calls.at(-1);
      call.usage=result.usage; call.outcome=result.kind;
      if(result.kind==='error') {
        await end(result.error.code);
        error(res,result.error.code==='authentication'?401:422,result.error.code); return;
      }
      if(result.usage.status!=='reported' || !integer(result.usage.total) || !integer(state.tokens+result.usage.total)) {
        await end('unknown_usage'); error(res,422,'unknown_usage'); return;
      }
      const projection=result.kind==='tool'?{tool:result.call.name,args:result.call.arguments,tokens:result.usage.total}:{done:result.text,tokens:result.usage.total};
      requireThat(result.kind==='final' || (grants.includes(projection.tool) && validArgs(projection.tool,projection.args)),'arguments');
      requireThat(size(projection)<=LIMITS.bytes,'reply_limit');
      requireThat(size({messages:[...state.messages,result.message],tools})<=LIMITS.bytes,'context_limit');
      state.tokens+=result.usage.total;
      state.messages.push(result.message); // Preserve the complete native message, never its Mo projection.
      state.offered=projection; state.callId=result.kind==='tool'?result.call.id:null;
      state.outcome=result.kind==='tool'?'awaiting-recorded-tool':'final-offered';
      await log.write(state);
      requireThat(!terminal && !current.controller.signal.aborted && remaining()>0,'terminal');
      await bounded(new Promise((resolve,reject)=>{
        res.once('error',()=>reject(new Error('reply')));
        res.once('close',()=>{if(!delivered) reject(new Error('disconnect'));});
        res.once('finish',()=>{delivered=true;resolve();});
        const payload=JSON.stringify(projection);
        res.writeHead(200,{'content-type':'application/json','content-length':Buffer.byteLength(payload),'connection':'close'});
        res.end(payload);
      }),remaining(),'reply_timeout');
    } catch(e) {
      const allowed=['protocol','budget','context_limit','reply_limit','body_limit','body_timeout','provider_timeout','reply_timeout','disconnect','arguments','session_timeout','terminal'];
      const code=allowed.includes(e?.message)?e.message:'invalid';
      await end(code,state.outcome==='dispatch-intent' || ['disconnect','reply_timeout'].includes(code));
      error(res,422,code);
    } finally {
      res.removeListener('close',disconnected);
      if(active===current) active=null;
      if(!res.writableEnded) res.destroy();
    }
  }
  const server=http.createServer({maxHeaderSize:8192},(req,res)=>{void handle(req,res);});
  server.requestTimeout=2000; server.headersTimeout=2000; server.timeout=2000; server.keepAliveTimeout=1;
  server.on('connection',socket=>{sockets.add(socket); socket.on('close',()=>sockets.delete(socket)); socket.setTimeout(2000,()=>socket.destroy());});
  server.on('clientError',(_err,socket)=>{void end('protocol');socket.destroy();});
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,'127.0.0.1',resolve);});
  const sessionTimer=setTimeout(()=>{void stop('session_timeout');},LIMITS.sessionMs);
  async function stop(reason='stopped') {
    if(stopping) return stopping;
    stopping=(async()=>{
      clearTimeout(sessionTimer);
      const saved=end(reason,Boolean(active));
      const closed=new Promise(resolve=>server.close(resolve));
      for(const socket of sockets) socket.destroy();
      await bounded(Promise.all([saved,closed]),LIMITS.closeMs,'close_timeout');
    })();
    return stopping;
  }
  return {port:server.address().port,session:state.session,stop,inspect:()=>structuredClone(state),resources:()=>({listening:server.listening,sockets:sockets.size,active:Boolean(active)})};
}
