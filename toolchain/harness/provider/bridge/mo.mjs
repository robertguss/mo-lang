// This module is loaded only by the explicitly released Mo control.
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import { spawn } from 'node:child_process';

export async function moControl({root, start, finish, ports, token, realFetch, providerPort, tool, reasoning, events, observations}) {
  const release=JSON.parse(await fs.readFile(new URL('./release.json',import.meta.url)));
  assert.equal(release.explicitLeadRelease,true,'lead release missing');
  const project=path.resolve(release.ownedProject);
  const guard=path.join(project,'guard.py');
  const mo=path.join(project,'mo');
  const commands=[];
  async function run(args,seconds=60) {
    const command=['python3',guard,String(seconds),'--',...args];
    const child=spawn(command[0],command.slice(1),{cwd:project,detached:true,stdio:['ignore','pipe','pipe']});
    let stdout='',stderr='',timer;
    child.stdout.on('data',c=>{stdout+=c;if(Buffer.byteLength(stdout)>1048576)kill();});
    child.stderr.on('data',c=>{stderr+=c;if(Buffer.byteLength(stderr)>1048576)kill();});
    function kill(){try{process.kill(-child.pid,'SIGKILL');}catch{}}
    try {
      timer=setTimeout(kill,(seconds+3)*1000);
      const code=await new Promise((resolve,reject)=>{child.once('exit',resolve);child.once('error',reject);});
      commands.push({command,code,stdout,stderr});
      assert.equal(code,0,JSON.stringify(commands.at(-1)));
      return stdout;
    } finally {clearTimeout(timer);kill();}
  }
  try {
    await run([mo,'build','examples/programs/agent/main.mo','-o','bridge-fixture'],120);
    for(const mode of ['interpreter','compiled']) {
      const candidate=await fs.mkdtemp(path.join(root,`mo-${mode}-`));
      await fs.mkdir(path.join(candidate,'work'));
      let providerCalls=0, commandCalls=0, observed=[];
      async function recorded() {
        const data=await fs.readFile(path.join(candidate,'runs/r_1.log'),'utf8');
        return data.trim().split('\n').map(JSON.parse).filter(x=>x.step).map(x=>x.step);
      }
      const commandServer=http.createServer((req,res)=>{
        const chunks=[];
        req.on('data',c=>chunks.push(c));
        req.on('end',()=>{void (async()=>{
          const input=JSON.parse(Buffer.concat(chunks));
          const book=await recorded();
          assert.equal(req.url,'/fixture/v1/command'); assert.equal(book.length,1);
          assert.equal(input.command,'inert-test-key');assert.equal(input.run_id,'r_1');assert.equal(input.call_id,'2');
          assert.equal(input.workspace_id,'bridge-workspace');
          assert.equal(book[0].kind,'model');
          commandCalls++;observed.push({at:'command',book,input});
          const output={version:1,run_id:input.run_id,call_id:input.call_id,workspace_id:input.workspace_id,state:'success',exit_code:0,stdout:'literal error word is harmless',stderr:'',stdout_truncated:false,stderr_truncated:false,elapsed_ms:0,error_code:'none',execution:'completed'};
          const payload=JSON.stringify(output);res.writeHead(200,{'content-type':'application/json','content-length':Buffer.byteLength(payload)});res.end(payload);
        })().catch(e=>{observed.push({fixtureError:String(e)});res.destroy();});});
      });
      const commandSockets=new Set();
      commandServer.on('connection',s=>{commandSockets.add(s);s.setTimeout(2000,()=>s.destroy());s.once('close',()=>commandSockets.delete(s));});
      await new Promise(r=>commandServer.listen(0,'127.0.0.1',r));
      const port=commandServer.address().port;ports.add(port);
      try {
        const grants=['list_files','read_file','search','write_file','exact_edit','command'];
        const scenario=await start([{events:events([reasoning,tool('command',{command:'inert-test-key'})])},{}],{
          grants,
          fetch:async(_url,init)=>{
            const book=await recorded();
            assert.equal(book.length,providerCalls===0?0:2);
            const journal=JSON.parse(await fs.readFile(path.join(scenario.dir,'journal.json')));
            assert.deepEqual(journal.prefix,book);
            assert.equal(journal.outcome,'dispatch-intent');
            observed.push({at:'provider',book,journalPrefix:journal.prefix});providerCalls++;
            return realFetch(`http://127.0.0.1:${providerPort}/sse`,init);
          },
        });
        const args=['coding-fixture',candidate,'--model',`127.0.0.1:${scenario.bridge.port}`,'--command',`127.0.0.1:${port}`,'--workspace','bridge-workspace','fixture goal'];
        const stdout=await run(mode==='interpreter'?[mo,'run','examples/programs/agent/main.mo','--',...args]:[path.join(project,'zig-out/mo-build/bridge-fixture/bridge-fixture'),...args]);
        assert.equal(providerCalls,2);assert.equal(commandCalls,1);
        const report=stdout.trim().split('\n').map(JSON.parse);
        assert.equal(report.at(-1).event,'terminal');assert.equal(report.at(-1).payload.state,'done');
        const book=await recorded();assert.equal(book.length,3);
        assert.equal(book[1].kind,'tool');assert.equal(book[2].kind,'model');
        assert(scenario.requests[1].input.some(x=>x.type==='reasoning'&&x.encrypted_content==='opaque-native-signature'));
        assert(scenario.requests[1].input.some(x=>x.type==='function_call_output'&&x.call_id==='call_1'));
        assert.equal(scenario.bridge.inspect().messages[3].toolCallId,'call_1|fc_1');
        assert.equal(scenario.bridge.inspect().messages[3].isError,false);
        observations.push({mode,providerCalls,commandCalls,observed,book,report,release});
      } finally {
        observations.push({mode,providerCalls,commandCalls,observed});
        for(const s of commandSockets)s.destroy();commandServer.closeAllConnections();await new Promise(r=>commandServer.close(r));ports.delete(port);await finish();
      }
    }
  } finally {observations.push({moCommands:commands});}
}
