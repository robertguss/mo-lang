import fs from 'node:fs/promises';
import { constants } from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { LIMITS, requireThat } from './protocol.mjs';

// The caller owns the private directory. No resume, even from an empty tombstone.
export async function journal(file) {
  requireThat(typeof file==='string' && path.isAbsolute(file) && path.normalize(file)===file, 'journal');
  let parent = path.dirname(file);
  for (let p=parent;; p=path.dirname(p)) {
    const st=await fs.lstat(p);
    requireThat(st.isDirectory() && !st.isSymbolicLink(), 'journal');
    if (p===parent) requireThat((st.mode & 0o077)===0 && st.uid===process.getuid(), 'journal');
    if (p===path.dirname(p)) break;
  }
  const handle=await fs.open(file,constants.O_CREAT|constants.O_EXCL|constants.O_WRONLY|constants.O_NOFOLLOW,0o600);
  await handle.close();
  let serial=Promise.resolve(), generation=0;
  return {
    invalidate() { generation++; },
    async write(value) {
      const bytes=Buffer.from(JSON.stringify(value)+'\n');
      requireThat(bytes.length<=LIMITS.journalBytes,'journal');
      const mine=generation;
      let expired=false, timer;
      const operation=serial.then(async()=>{
        const temp=path.join(parent,`.bridge-${randomUUID()}`);
        try {
          requireThat(!expired && mine===generation,'journal');
          await fs.writeFile(temp,bytes,{flag:'wx',mode:0o600});
          requireThat(!expired && mine===generation,'journal');
          const target=await fs.lstat(file);
          requireThat(target.isFile() && !target.isSymbolicLink() && (target.mode & 0o077)===0,'journal');
          requireThat(!expired && mine===generation,'journal');
          // No await between the final generation check and scheduling replacement.
          await fs.rename(temp,file);
        } finally { await fs.rm(temp,{force:true}).catch(()=>{}); }
      });
      serial=operation.catch(()=>{});
      try { await Promise.race([operation,new Promise((_,reject)=>{timer=setTimeout(()=>{expired=true;reject(new Error('journal'));},LIMITS.closeMs);})]); }
      finally { clearTimeout(timer); }
    },
  };
}
