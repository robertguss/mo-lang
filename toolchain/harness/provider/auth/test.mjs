import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import dns from 'node:dns';
import dgram from 'node:dgram';
import { syncBuiltinESMExports } from 'node:module';
import { fork, spawn } from 'node:child_process';
import { once } from 'node:events';
import { createAuth, installTransport, loadOAuth, Operation, interaction, inOperation } from './auth.mjs';
import { PrivateStore, providerId } from './store.mjs';

// Deny non-fetch transports and listener creation BEFORE loading pinned OAuth.
let denied = 0;
const deny = () => { denied++; throw Error('offline_denied'); };
for (const [object, names] of [[http, ['request','get','createServer']], [https, ['request','get','createServer']],
  [net, ['connect','createConnection','createServer']], [tls, ['connect','createServer']],
  [dns, ['lookup','resolve','resolve4','resolve6']], [dns.promises, ['lookup','resolve','resolve4','resolve6']],
  [dgram, ['createSocket']]]) for (const name of names) object[name] = deny;
net.Socket.prototype.connect = deny;
globalThis.WebSocket = class { constructor() { deny(); } };
syncBuiltinESMExports();
let handler;
const requests = [];
const ordering = [];
const lateResponses = [];
installTransport(async (url, options) => {
  requests.push({ path: new URL(url).pathname, method: options.method });
  return handler(url, options);
});
const runtime = path.resolve(process.argv[2]);
const oauth = await loadOAuth(runtime);
const token = n => 'synthetic.' + Buffer.from(JSON.stringify({ 'https://api.openai.com/auth': { chatgpt_account_id: 'synthetic-account' }, marker: n })).toString('base64') + '.signature';
const cred = (n = 'one', expires = Date.now()+3600000) => ({ type:'oauth', access:token(n), refresh:'SYNTHETIC-REFRESH-CANARY-'+n, expires, accountId:'synthetic-account' });
const json = (value, status = 200) => new Response(JSON.stringify(value), {status});
function flow(n = 'one') {
  return async url => {
    if (url.endsWith('/usercode')) return json({ device_auth_id:'SYNTHETIC-DEVICE', user_code:'SYNTHETIC-CODE', interval:0 });
    if (url.endsWith('/deviceauth/token')) return json({ authorization_code:'SYNTHETIC-AUTH-CODE', code_verifier:'SYNTHETIC-VERIFIER' });
    return json({ access_token:token(n), refresh_token:cred(n).refresh, expires_in:3600 });
  };
}
const parent = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'mo-auth-offline-'));
fs.chmodSync(parent, 0o700);
const children = new Set();
let sequence = 0;
function fresh(overrides = {}) {
  const directory = path.join(parent, 'store-'+(++sequence));
  const events = [];
  const auth = createAuth({directory, candidateRoots:[process.cwd()], oauth, operatorSink:e=>events.push(e), ...overrides});
  return { auth, directory, events };
}
async function seed(auth, value = cred()) { await auth.credentialStore.modify(providerId, async () => value); }
async function state(auth, expected) { assert.deepEqual(await auth.status(), {providerId, state:expected}); }
const deferred = () => { let resolve; const promise = new Promise(r=>resolve=r); return {promise,resolve}; };
const delay = ms => new Promise(r=>setTimeout(r,ms));
async function lateResponseCleanup(reason) {
  const entered=deferred(),release=deferred();let cancelled=false,calls=0;
  handler=()=>{calls++;entered.resolve();return release.promise;};
  const controller=new AbortController();
  const pending=inOperation({signal:controller.signal,deadlineMs:40},()=>fetch('https://auth.openai.com/oauth/token',{
    method:'POST',body:new URLSearchParams({grant_type:'refresh_token',refresh_token:'synthetic-only'}),
  }));
  await entered.promise;
  if(reason==='abort')controller.abort();
  await assert.rejects(pending);
  release.resolve(new Response(new ReadableStream({cancel(){cancelled=true;}})));
  await delay(50);
  lateResponses.push({reason,calls,bodyCancelled:cancelled});
  assert.equal(calls,1);assert.equal(cancelled,true);
}
function child(directory, mode) {
  const p = fork(new URL('./child.mjs', import.meta.url), [directory, mode, process.cwd()], { stdio:['ignore','ignore','ignore','ipc'], env:{PATH:process.env.PATH, HOME:process.env.HOME} });
  children.add(p); p.once('exit',()=>children.delete(p)); return p;
}
async function cli(args) {
  const p = spawn(process.execPath, ['--import',path.resolve('offline.mjs'),path.resolve('cli.mjs'), ...args], {env:{PATH:process.env.PATH,HOME:process.env.HOME}, stdio:['ignore','pipe','pipe']});
  children.add(p); let output=''; p.stdout.on('data',x=>output+=x); p.stderr.on('data',x=>output+=x);
  const [exit] = await once(p,'exit'); children.delete(p); return {exit,output};
}
const tests = {
  async device_success() {
    handler=flow(); const {auth,events,directory}=fresh();
    assert.deepEqual(await auth.login(),{code:'authenticated'}); await state(auth,'authenticated');
    assert.equal(events.length,1); assert.equal(events[0].verificationUri,'https://auth.openai.com/codex/device');
    assert.equal(fs.statSync(directory).mode&0o777,0o700); assert.equal(fs.statSync(path.join(directory,'credential.json')).mode&0o777,0o600);
    const base=flow();handler=(url,opts)=>url.endsWith('/oauth/token') ? json({access_token:token('bad'),refresh_token:'synthetic',expires_in:-1}) : base(url,opts);
    const other=fresh();assert.equal((await other.auth.login()).code,'provider_failure');await state(other.auth,'missing');
  },
  async device_pending() {
    let polls=0; const base=flow(); handler=async (url,opts)=>url.endsWith('/deviceauth/token') && ++polls===1 ? json({},403) : base(url,opts);
    const {auth}=fresh(); assert.equal((await auth.login()).code,'authenticated'); assert.equal(polls,2);
  },
  async device_denial() {
    const base=flow(); handler=(url,opts)=>url.endsWith('/deviceauth/token') ? json({error:'access_denied',detail:'SECRET-UPSTREAM'},400) : base(url,opts);
    const {auth}=fresh(); assert.deepEqual(await auth.login(),{code:'provider_failure'}); await state(auth,'missing');
  },
  async device_expiry() {
    const base=flow(); handler=(url,opts)=>url.endsWith('/deviceauth/token') ? json({},403) : base(url,opts);
    const {auth}=fresh(); assert.deepEqual(await auth.login({deadlineMs:40}),{code:'timeout'}); await state(auth,'missing');
    handler=(url,opts)=>url.endsWith('/deviceauth/token') ? json({error:'expired_token'},400) : base(url,opts);
    assert.equal((await auth.login()).code,'provider_failure');
  },
  async abort_before() {
    handler=flow(); const {auth}=fresh(); const c=new AbortController(); c.abort(); const count=requests.length;
    assert.deepEqual(await auth.login({signal:c.signal}),{code:'cancelled'}); assert.equal(requests.length,count);
    assert.deepEqual(await auth.status({signal:c.signal}),{providerId,state:'unavailable'});
  },
  async abort_transport() {
    const entered=deferred(); let aborted=false;
    handler=(_,opts)=>{ opts.signal.addEventListener('abort',()=>aborted=true); entered.resolve(); return new Promise(()=>{}); };
    const {auth}=fresh(); const c=new AbortController(); const running=auth.login({signal:c.signal}); await entered.promise; c.abort();
    assert.deepEqual(await running,{code:'cancelled'}); assert.equal(aborted,true); await state(auth,'missing');
  },
  async response_bounds() {
    handler=()=>new Response('x'.repeat(65537)); const {auth}=fresh(); assert.equal((await auth.login()).code,'provider_failure');
    let cancelled=false;
    handler=()=>new Response(new ReadableStream({pull(){return new Promise(()=>{});},cancel(){cancelled=true;}}));
    assert.equal((await auth.login({deadlineMs:40})).code,'timeout'); await delay(5); assert.equal(cancelled,true);
    handler=()=>new Promise(()=>{});
    const started=Date.now(); assert.equal((await auth.login({deadlineMs:15000})).code,'timeout');
    assert.ok(Date.now()-started>=9900 && Date.now()-started<13000);
    await lateResponseCleanup('deadline');
  },
  async store_bounds() {
    const {auth,directory}=fresh(); await seed(auth); fs.writeFileSync(path.join(directory,'credential.json'),'x'.repeat(65537));
    await state(auth,'unavailable'); const count=requests.length; assert.equal((await auth.login()).code,'storage_failure'); assert.equal(requests.length,count);
  },
  async malformed_credential() {
    const {auth,directory}=fresh(); await seed(auth); const file=path.join(directory,'credential.json');
    const good=JSON.parse(fs.readFileSync(file));
    for (const value of [{...cred(),refresh:''},{...cred(),expires:null},{...cred(),extra:'bad'},'bad']) {
      fs.writeFileSync(file,JSON.stringify({...good,credential:value})); await state(auth,'unavailable');
    }
    fs.writeFileSync(file,'{'); await state(auth,'unavailable');
  },
  async interaction_validation() {
    const op=new Operation(1000); let events=0; const i=interaction(op,()=>events++);
    try {
      for (const p of [{type:'manual_code'},{type:'select',options:[{id:'browser'}]}]) await assert.rejects(i.prompt(p));
      for (const event of [{type:'auth_url'}, {type:'device_code',verificationUri:'https://evil.example',userCode:'SAFE',intervalSeconds:1,expiresInSeconds:900}]) assert.throws(()=>i.notify(event));
      assert.equal(events,0);
    } finally {op.close();}
  },
  async egress_rejection() {
    const count=requests.length;
    await inOperation({},async()=>{
      for (const [url,opts] of [['https://evil.example/oauth/token',{method:'POST'}],['https://auth.openai.com/oauth/token?x=1',{method:'POST'}],['https://auth.openai.com/oauth/token',{method:'GET'}],['https://auth.openai.com/oauth/token',{method:'POST',redirect:'follow'}],['https://auth.openai.com/oauth/token',{method:'POST',body:'x'.repeat(65537)}]]) await assert.rejects(fetch(url,opts));
    });
    assert.equal(requests.length,count);
    handler=()=>new Response(null,{status:302,headers:{location:'https://evil.example'}});
    const {auth}=fresh(); assert.equal((await auth.login()).code,'provider_failure');
    for (const fn of [()=>http.get('http://example.com'),()=>tls.connect(443),()=>dns.lookup('example.com'),()=>new WebSocket('wss://example.com')]) assert.throws(fn);
  },
  async valid_resolution() {
    const {auth}=fresh(); await seed(auth); const count=requests.length;
    assert.deepEqual(await auth.resolve(),{code:'authenticated',accessToken:cred().access}); assert.equal(requests.length,count);
  },
  async expired_refresh() {
    const {auth}=fresh(); await seed(auth,cred('old',1)); await state(auth,'expired'); handler=flow('rotated');
    const result=await auth.resolve(); assert.equal(result.accessToken,token('rotated'));
    assert.equal((await auth.credentialStore.read(providerId)).refresh,cred('rotated').refresh);
  },
  async concurrent_refresh() {
    const {auth}=fresh(); await seed(auth,cred('old',1)); const entered=deferred(), release=deferred(); let calls=0;
    handler=async (...args)=>{calls++;entered.resolve();await release.promise;return flow('rotated')(...args);};
    const first=auth.resolve(); await entered.promise; const second=auth.resolve(); release.resolve();
    const results=await Promise.all([first,second]); assert.equal(calls,1); assert.equal(results[0].accessToken,results[1].accessToken);
    await seed(auth,cred('old',1)); const entered2=deferred(),release2=deferred();
    handler=async(...args)=>{ordering.push('refresh-entered');entered2.resolve();await release2.promise;return flow('rotated')(...args);};
    const refresh=auth.resolve();await entered2.promise;const logout=auth.logout();ordering.push('logout-queued');release2.resolve();
    assert.equal((await refresh).code,'authenticated');ordering.push('refresh-persisted');assert.equal((await logout).code,'missing');ordering.push('logout-finished');await state(auth,'missing');
  },
  async modify_unchanged() {
    const {auth}=fresh(); await seed(auth); const before=await auth.credentialStore.read(providerId);
    assert.deepEqual(await auth.credentialStore.modify(providerId,async()=>undefined),before);
    const entered=deferred(),release=deferred();
    const modifying=auth.credentialStore.modify(providerId,async()=>{entered.resolve();await release.promise;return undefined;});
    await entered.promise; const deleting=auth.credentialStore.delete(providerId); release.resolve(); await Promise.all([modifying,deleting]); await state(auth,'missing');
  },
  async logout() {
    const {auth}=fresh(); await seed(auth); assert.deepEqual(await auth.logout(),{code:'missing'}); await state(auth,'missing');
    assert.deepEqual(await auth.logout(),{code:'missing'});
    assert.deepEqual(await auth.resolve(),{code:'missing'});
  },
  async login_logout_overlap() {
    const entered=deferred(),release=deferred(); handler=async (...args)=>{entered.resolve();await release.promise;return flow()(...args);};
    const {auth}=fresh(); const login=auth.login(); await entered.promise; ordering.push('login-polling');await auth.logout();ordering.push('logout-invalidated'); release.resolve();
    assert.deepEqual(await login,{code:'conflict'});ordering.push('old-login-conflict'); await state(auth,'missing');
  },
  async newer_login_overlap() {
    const entered=deferred(),release=deferred(); let starts=0;
    handler=async (...args)=>{if(args[0].endsWith('/usercode') && ++starts===1){entered.resolve();await release.promise;}return flow()(...args);};
    const {auth}=fresh(); const old=auth.login(); await entered.promise;ordering.push('old-login-polling'); assert.equal((await auth.login()).code,'authenticated');ordering.push('new-login-committed');release.resolve();
    assert.deepEqual(await old,{code:'conflict'});ordering.push('old-login-rejected');await state(auth,'authenticated');
  },
  async late_success() {
    const entered=deferred(),release=deferred(); handler=async (...args)=>{entered.resolve();await release.promise;return flow()(...args);};
    const {auth}=fresh(); const c=new AbortController();const login=auth.login({signal:c.signal});await entered.promise;c.abort();
    assert.deepEqual(await login,{code:'cancelled'});release.resolve();await delay(30);await state(auth,'missing');
    const release2=deferred();handler=async(...args)=>{await release2.promise;return flow()(...args);};
    assert.deepEqual(await auth.login({deadlineMs:20}),{code:'timeout'});release2.resolve();await delay(30);await state(auth,'missing');
    await lateResponseCleanup('abort');
  },
  async cross_process_lock() {
    const {auth,directory}=fresh(); await seed(auth); const p=child(directory,'hold'); assert.equal((await once(p,'message'))[0],'held');
    let done=false;const deleting=auth.logout().then(x=>{done=true;return x;});await delay(80);assert.equal(done,false);
    const exited=once(p,'exit');p.send('release');await exited;assert.equal((await deleting).code,'missing');await state(auth,'missing');
  },
  async killed_holder() {
    const {auth,directory}=fresh();await seed(auth);const p=child(directory,'hold');await once(p,'message');const exited=once(p,'exit');p.kill('SIGKILL');await exited;
    assert.equal((await auth.logout({deadlineMs:80})).code,'timeout');assert.equal(fs.existsSync(path.join(directory,'lock')),true);
    const started=Date.now();assert.equal((await auth.logout({deadlineMs:6000})).code,'storage_failure');assert.ok(Date.now()-started>=4900 && Date.now()-started<5800);
    fs.rmdirSync(path.join(directory,'lock')); // Explicit test operator recovery after proven death.
  },
  async atomic_failure() {
    const {auth}=fresh();await seed(auth,cred('old',1));handler=flow('new');const original=fs.renameSync;
    fs.renameSync=()=>{throw Error('SECRET-RENAME');};
    try {assert.deepEqual(await auth.resolve(),{code:'storage_failure'});} finally {fs.renameSync=original;}
    assert.equal((await auth.credentialStore.read(providerId)).access,token('old'));
    let renames=0;handler=flow('new');fs.renameSync=(...args)=>{if(++renames===2)throw Error('SECRET-RENAME');return original(...args);};
    try {assert.deepEqual(await auth.login(),{code:'storage_failure'});} finally {fs.renameSync=original;}
    assert.equal((await auth.credentialStore.read(providerId)).access,token('old'));
  },
  async unsafe_directory() {
    const {auth,directory}=fresh();fs.mkdirSync(directory,{mode:0o755});await state(auth,'unavailable');assert.equal(fs.statSync(directory).mode&0o777,0o755);
    assert.throws(()=>new PrivateStore(path.join(process.cwd(),'bad'),{forbiddenRoots:[process.cwd()]}));
    const unsafe=path.join(parent,'unsafe');fs.mkdirSync(unsafe,{mode:0o777});fs.chmodSync(unsafe,0o777);
    const other=fresh({directory:path.join(unsafe,'child')});await state(other.auth,'unavailable');
  },
  async unsafe_file() {
    const {auth,directory}=fresh();await seed(auth);const file=path.join(directory,'credential.json');fs.chmodSync(file,0o644);await state(auth,'unavailable');
    fs.unlinkSync(file);fs.mkdirSync(file);await state(auth,'unavailable');
  },
  async unsafe_links() {
    const {auth,directory}=fresh();await seed(auth);const file=path.join(directory,'credential.json');const link=path.join(directory,'hard');fs.linkSync(file,link);await state(auth,'unavailable');
    fs.unlinkSync(file);fs.symlinkSync(link,file);await state(auth,'unavailable');
    const linked=path.join(parent,'linked');fs.symlinkSync(directory,linked);const other=fresh({directory:linked});await state(other.auth,'unavailable');
  },
  async unknown_version() {
    const {auth,directory}=fresh();await seed(auth);const file=path.join(directory,'credential.json');const value=JSON.parse(fs.readFileSync(file));value.version=2;fs.writeFileSync(file,JSON.stringify(value));
    await state(auth,'unavailable');assert.equal((await auth.logout()).code,'storage_failure');assert.equal(JSON.parse(fs.readFileSync(file)).version,2);
  },
  async cli_sanitized() {
    const {auth,directory}=fresh();await seed(auth);const result=await cli(['status',directory,runtime,process.cwd()]);assert.equal(result.exit,0);
    assert.deepEqual(JSON.parse(result.output),{providerId,state:'authenticated'});
    const unsupported=await cli(['export',directory,runtime,process.cwd()]);assert.equal(unsupported.exit,1);assert.deepEqual(JSON.parse(unsupported.output),{code:'provider_failure'});
  },
  async secret_canaries() {
    handler=()=>{throw Error('SECRET-TOKEN-UPSTREAM');};const {auth,events}=fresh();const result=await auth.login();
    assert.equal(JSON.stringify(result),'\{"code":"provider_failure"\}');assert.equal(events.length,0);
    const {auth:other}=fresh();handler=()=>json({error:'SECRET-HEADER-BODY'},500);assert.deepEqual(await other.login(),{code:'provider_failure'});
  },
};
const selected=process.argv.slice(3);
if (!selected.length || selected.length>28 || new Set(selected).size!==selected.length || selected.some(name=>!Object.hasOwn(tests,name))) {
  process.stdout.write('invalid_control_selection\n');fs.rmSync(parent,{recursive:true});process.exit(2);
}
let failures=0;const results=[];
try {
  for(const name of selected){
    const before=requests.length;const start=Date.now();
    try {await tests[name]();results.push({name,pass:true,requests:requests.length-before,elapsedMs:Date.now()-start});console.log('PASS',name);}
    catch(e){failures++;results.push({name,pass:false,requests:requests.length-before,elapsedMs:Date.now()-start});console.log('FAIL',name,e?.constructor?.name);}
  }
} finally {
  for(const p of children)p.kill('SIGKILL');
  await Promise.all([...children].map(p=>once(p,'exit')));
  fs.rmSync(parent,{recursive:true,force:true});
}
console.log(JSON.stringify({controls:results,passed:selected.length-failures,total:selected.length,requests,ordering,lateResponses,denied,fixtureListeners:0,children:children.size,tempRemoved:!fs.existsSync(parent)}));
process.exitCode=failures?1:0;
