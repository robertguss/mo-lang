import assert from 'node:assert/strict';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import dns from 'node:dns';
import { syncBuiltinESMExports } from 'node:module';
import { zstdDecompressSync } from 'node:zlib';
import { writeFileSync } from 'node:fs';
import { Type } from 'typebox';

const canary = 'synthetic-secret-CANARY-never-public';
const token = 'synthetic.' + Buffer.from(JSON.stringify({ 'https://api.openai.com/auth': { chatgpt_account_id: 'fixture-account' } })).toString('base64url') + '.synthetic';
const realFetch = globalThis.fetch;
const server = http.createServer();
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const port = server.address().port;
const originalConnect = net.Socket.prototype.connect;
let denied = 0;
const deny = () => { denied++; throw new Error('unexpected egress rejected'); };
net.Socket.prototype.connect = function(...args) {
  const options = Array.isArray(args[0]) ? args[0][0] : args[0];
  if (typeof options !== 'object' || options.host !== '127.0.0.1' || Number(options.port) !== port) return deny();
  return originalConnect.apply(this, args);
};
http.request = http.get = https.request = https.get = tls.connect = dns.lookup = dns.resolve = deny;
Object.keys(dns.promises).forEach(key => { if (typeof dns.promises[key] === 'function') dns.promises[key] = deny; });
globalThis.fetch = globalThis.WebSocket = deny;
syncBuiltinESMExports();
const { turn, legacyUsage } = await import('./turn.mjs');
const tools = [{ name: 'read', description: 'Read a fixture', parameters: Type.Object({ path: Type.String() }, { additionalProperties: false }) }];
const context = { messages: [{ role: 'user', content: 'fixture', timestamp: 1 }] };
const usage = { input_tokens: 10, output_tokens: 5, total_tokens: 15, input_tokens_details: { cached_tokens: 3, cache_write_tokens: 2 }, output_tokens_details: { reasoning_tokens: 1 } };
const textItem = { type: 'message', id: 'msg_1', role: 'assistant', status: 'completed', content: [{ type: 'output_text', text: 'hello' }] };
const callItem = { type: 'function_call', id: 'fc_1', call_id: 'call_1', name: 'read', arguments: '{"path":"a"}' };
const reasoning = { type: 'reasoning', id: 'rs_1', encrypted_content: 'opaque-signature', summary: [] };
function events(items = [textItem], u = usage, status = 'completed') {
  return [...items.map((item, output_index) => ({ type: 'response.output_item.done', item, output_index })),
    { type: 'response.completed', response: { id: 'resp_1', status, output: items, ...(u === null ? {} : { usage: u }) } }];
}
const encode = es => es.map(e => 'data: ' + JSON.stringify(e) + '\n\n').join('');
let fixture, requests = [], observations = [], count = 0;
server.on('request', (req, res) => {
  const chunks = [];
  req.on('data', c => chunks.push(c));
  req.on('end', () => {
    const bytes = Buffer.concat(chunks);
    const body = JSON.parse((req.headers['content-encoding'] === 'zstd' ? zstdDecompressSync(bytes) : bytes).toString());
    requests.push(body);
    res.writeHead(fixture.status ?? 200, { 'content-type': 'text/event-stream', 'x-fixture-canary': canary });
    if (fixture.hang) { res.write(': waiting\n\n'); return; }
    res.end(fixture.raw ?? encode(fixture.events ?? events()));
  });
});
async function invoke(f = {}, extra = {}) {
  fixture = f; requests = [];
  const result = await turn({ context, tools, accessToken: token, fetch: (_url, init) => realFetch(`http://127.0.0.1:${port}/fixture`, init), ...extra });
  observations.push({ case: count, requests: structuredClone(requests), result: result.kind, usage: result.usage, error: result.error });
  if (result.kind === 'error') assert(!JSON.stringify(result).includes(canary));
  return result;
}
async function check(name, fn) {
  count++;
  try { await fn(); console.log(`ok ${count} - ${name}`); }
  catch (e) { console.log(`not ok ${count} - ${name}`); throw e; }
}
try {
  await check('final text and complete positive cache accounting', async () => {
    const r = await invoke(); assert.equal(r.text, 'hello'); assert.deepEqual(r.usage, {status:'reported',input:5,output:5,cacheRead:3,cacheWrite:2,total:15,reasoning:1});
    assert.equal(requests[0].parallel_tool_calls, false); assert.equal(requests[0].reasoning.effort, 'low'); assert.equal(requests[0].model, 'gpt-6-astra'); assert.equal(requests[0].stream, true);
  });
  await check('tool result next turn and native signatures', async () => {
    const r = await invoke({ events: events([reasoning, callItem]) }); assert.equal(r.kind, 'tool'); assert.equal(r.call.id, 'call_1|fc_1');
    assert.equal(JSON.parse(r.message.content[0].thinkingSignature).encrypted_content, 'opaque-signature');
    const history = [...context.messages, r.message, { role:'toolResult', toolCallId:r.call.id, toolName:'read', content:[{type:'text',text:'file'}], isError:false, timestamp:2 }];
    const saved = JSON.stringify(history);
    const next = await invoke({}, {context:{messages:history}}); assert.equal(next.kind,'final'); assert.equal(JSON.stringify(history),saved);
    assert(requests[0].input.some(x=>x.type==='function_call_output' && x.call_id==='call_1'));
    assert(requests[0].input.some(x=>x.type==='reasoning' && x.encrypted_content==='opaque-signature'));
  });
  await check('multiple calls rejected', async()=>assert.equal((await invoke({events:events([callItem,{...callItem,id:'fc_2',call_id:'call_2'}])})).error.code,'unsupported'));
  await check('non-string wire arguments rejected', async()=>assert.equal((await invoke({events:events([{...callItem,arguments:{path:'a'}}])})).error.code,'unsupported'));
  await check('argument shape cannot coerce number to string', async()=>assert.equal((await invoke({events:events([{...callItem,arguments:'{"path":12}'}])})).error.code,'unsupported'));
  await check('malformed argument JSON rejected', async()=>assert.equal((await invoke({events:events([{...callItem,arguments:'{"path":'}])})).error.code,'unsupported'));
  await check('complete reported zero', async()=>assert.equal((await invoke({events:events([textItem],{input_tokens:0,output_tokens:0,total_tokens:0,input_tokens_details:{cached_tokens:0,cache_write_tokens:0}})})).usage.status,'reported'));
  await check('missing usage unknown', async()=>assert.deepEqual((await invoke({events:events([textItem],null)})).usage,{status:'unknown'}));
  await check('partial usage unknown', async()=>assert.equal((await invoke({events:events([textItem],{input_tokens:10})})).usage.status,'unknown'));
  await check('negative usage unknown', async()=>assert.equal((await invoke({events:events([textItem],{...usage,output_tokens:-1})})).usage.status,'unknown'));
  await check('invalid cache sum unknown', async()=>assert.equal((await invoke({events:events([textItem],{...usage,input_tokens_details:{cached_tokens:20,cache_write_tokens:2}})})).usage.status,'unknown'));
  await check('missing cache-write presence unknown', async()=>assert.equal((await invoke({events:events([textItem],{...usage,input_tokens_details:{cached_tokens:3}})})).usage.status,'unknown'));
  await check('HTTP 401 one attempt and secret isolation', async()=>{const r=await invoke({status:401,raw:JSON.stringify({error:{message:canary},access_token:canary})}); assert.equal(r.error.code,'authentication');assert.equal(requests.length,1);});
  await check('HTTP 503 no retry', async()=>{assert.equal((await invoke({status:503,raw:canary})).error.code,'provider');assert.equal(requests.length,1);});
  await check('upstream SSE error sanitization', async()=>assert.equal((await invoke({events:[{type:'error',message:canary,code:canary}]})).error.code,'provider'));
  await check('caller cancellation', async()=>{const c=new AbortController();const timer=setTimeout(()=>c.abort(),40);try{assert.equal((await invoke({hang:true},{signal:c.signal})).error.code,'cancelled');}finally{clearTimeout(timer);}});
  await check('finite deadline', async()=>assert.equal((await invoke({hang:true},{deadlineMs:40})).error.code,'timeout'));
  await check('stream truncation', async()=>assert.equal((await invoke({events:events().slice(0,1)})).error.code,'incomplete'));
  await check('upstream incomplete distinct', async()=>assert.equal((await invoke({events:events([textItem],usage,'incomplete')})).error.code,'incomplete'));
  await check('malformed SSE', async()=>assert.equal((await invoke({raw:'data: {bad '+canary+'\n\n'})).error.code,'incomplete'));
  await check('64 KiB response limit', async()=>assert.equal((await invoke({raw:'data: '+ 'x'.repeat(65537)+'\n\n'})).error.code,'unsupported'));
  await check('unexpected network paths rejected', async()=>{assert.throws(()=>globalThis.fetch('https://unexpected.invalid'),/egress/);assert.throws(()=>net.connect(443,'unexpected.invalid'),/egress/);assert.throws(()=>https.get('https://unexpected.invalid'),/egress/);assert(denied>=3);});
  await check('legacy unknown usage fails', async()=>assert.throws(()=>legacyUsage({status:'unknown'}),/cannot represent unknown/));
  await check('uncooperative transport still has finite deadline', async()=>assert.equal((await invoke({}, {deadlineMs:40,fetch:()=>new Promise(()=>{})})).error.code,'timeout'));
  await check('unknown tool rejected', async()=>assert.equal((await invoke({events:events([{...callItem,name:'unknown'}])})).error.code,'unsupported'));
  await check('JSON array arguments rejected', async()=>assert.equal((await invoke({events:events([{...callItem,arguments:'[]'}])})).error.code,'unsupported'));
  await check('upstream cancelled distinct', async()=>assert.equal((await invoke({events:events([textItem],usage,'cancelled')})).error.code,'cancelled'));
  await check('native tool schema changes rejected before egress', async()=>{assert.equal((await invoke({}, {context:{messages:[{role:'system',content:'',toolsAdded:tools,timestamp:1}]}})).error.code,'unsupported');assert.equal(requests.length,0);});
  assert(count > 0 && count <= 30);
  console.log(`PASS ${count} fixed cases; unexpected egress rejected=${denied}; Node=${process.version}`);
} finally {
  writeFileSync(process.argv[2] ?? 'evidence/outbound.json',JSON.stringify(observations,null,2)+'\n');
  server.closeAllConnections();
  await new Promise(resolve=>server.close(resolve));
}
