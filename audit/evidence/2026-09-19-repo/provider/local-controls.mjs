// Offline component checks; synthetic OAuth stub, not pinned-provider integration.
// Run: node audit/evidence/2026-09-19-repo/provider/local-controls.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');
const { installTransport, createAuth } = await import(path.join(root, 'toolchain/harness/provider/auth/auth.mjs'));
const { schemas, structuredResult, continuation } = await import(path.join(root, 'toolchain/harness/provider/bridge/protocol.mjs'));
const { journal } = await import(path.join(root, 'toolchain/harness/provider/bridge/journal.mjs'));
let outbound = 0;
installTransport(async () => { outbound++; throw new Error('network forbidden'); });
const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'mo-audit-provider-'));
const passed = [];
async function test(name, fn) { await fn(); passed.push(name); }
try {
  await test('schemas reject duplicates, unknown tools and freeze exact arguments', async () => {
    assert.throws(() => schemas(['read_file', 'read_file']));
    assert.throws(() => schemas(['unknown']));
    assert.equal(schemas(['read_file'])[0].parameters.additionalProperties, false);
  });
  await test('structured command result rejects inconsistent success and marks uncertain execution terminal', async () => {
    const v = {version:1,run_id:'r',call_id:'c',workspace_id:'w',state:'success',exit_code:0,stdout:'error is ordinary text',stderr:'',stdout_truncated:false,stderr_truncated:false,elapsed_ms:1,error_code:'none',execution:'completed'};
    assert.deepEqual(structuredResult('command',JSON.stringify(v),false), {isError:false,terminal:false});
    assert.throws(() => structuredResult('command',JSON.stringify({...v,exit_code:1}),false));
    assert.deepEqual(structuredResult('command',JSON.stringify({state:'failure',error_code:'transport',execution:'unknown'}),false),{isError:true,terminal:true});
  });
  await test('continuation rejects changed tool args and prefix', async () => {
    const offered = {tool:'read_file',args:{path:'a'},tokens:2};
    const state = {outcome:'awaiting-recorded-tool',offered,prefix:[],callId:'native|id'};
    const transcript = [{n:1,kind:'model',name:'model',args:{},result:JSON.stringify({tool:offered.tool,args:offered.args}),tokens:2,took_ms:0,refused:false},{n:2,kind:'tool',name:'read_file',args:{path:'a'},result:'contents',tokens:0,took_ms:1,refused:false}];
    assert.equal(continuation(state,transcript).toolCallId,'native|id');
    const changed=structuredClone(transcript); changed[1].args.path='b';
    assert.throws(() => continuation(state,changed));
    assert.throws(() => continuation({...state,prefix:transcript},[...changed,...transcript]));
  });
  await test('journal serializes snapshots and refuses existing or symlink targets', async () => {
    const dir=path.join(temp,'journal'); await fs.mkdir(dir,{mode:0o700});
    const target=path.join(dir,'state'); const log=await journal(target);
    await Promise.all([log.write({n:1}),log.write({n:2})]);
    assert.deepEqual(JSON.parse(await fs.readFile(target)),{n:2});
    await assert.rejects(journal(target));
    await fs.symlink(target,path.join(dir,'alias'));
    await assert.rejects(journal(path.join(dir,'alias')));
  });
  await test('logout invalidates an in-flight synthetic login', async () => {
    let complete, entered;
    const started=new Promise(r=>{entered=r;});
    const oauth={login:async()=>{entered();return new Promise(r=>{complete=r;});}};
    const auth=createAuth({directory:path.join(temp,'auth-race'),candidateRoots:[path.join(temp,'candidate')],oauth});
    const login=auth.login({deadlineMs:2000}); await started;
    assert.deepEqual(await auth.logout(),{code:'missing'});
    complete({type:'oauth',access:'synthetic-access',refresh:'synthetic-refresh',accountId:'synthetic-account',expires:Date.now()+60000});
    assert.deepEqual(await login,{code:'conflict'});
    assert.equal((await auth.status()).state,'missing');
  });
  await test('deadline prevents late synthetic login persistence', async () => {
    let complete;
    const auth=createAuth({directory:path.join(temp,'auth-timeout'),candidateRoots:[path.join(temp,'candidate')],oauth:{login:()=>new Promise(r=>{complete=r;})}});
    assert.deepEqual(await auth.login({deadlineMs:50}),{code:'timeout'});
    complete({type:'oauth',access:'synthetic-access',refresh:'synthetic-refresh',accountId:'synthetic-account',expires:Date.now()+60000});
    await new Promise(r=>setTimeout(r,10));
    assert.equal((await auth.status()).state,'missing');
  });
  await test('corrupt store fails closed without overwriting bytes', async () => {
    const dir=path.join(temp,'corrupt'); await fs.mkdir(dir,{mode:0o700});
    const file=path.join(dir,'credential.json'); await fs.writeFile(file,'{bad',{mode:0o600});
    const auth=createAuth({directory:dir,candidateRoots:[path.join(temp,'candidate')],oauth:{}});
    assert.deepEqual(await auth.logout(),{code:'storage_failure'});
    assert.equal(await fs.readFile(file,'utf8'),'{bad');
  });
  assert.equal(outbound,0);
  console.log(JSON.stringify({kind:'offline-component-controls',oauth:'synthetic stub; no pinned runtime or inference exercised',node:process.version,passed,total:passed.length,outbound},null,2));
} finally { await fs.rm(temp,{recursive:true,force:true}); }
