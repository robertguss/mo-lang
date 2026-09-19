import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

export const providerId = 'openai-codex';
export class AuthError extends Error {
  constructor(code) { super(code); this.code = code; }
}
export const fail = code => { throw new AuthError(code); };
const safeString = (s, max) => typeof s === 'string' && s.length > 0 && s.length <= max && !/[\x00-\x20\x7f]/.test(s);
export function credential(value) {
  if (!value || Object.keys(value).sort().join(',') !== 'access,accountId,expires,refresh,type' ||
      value.type !== 'oauth' || !safeString(value.access, 16384) || !safeString(value.refresh, 16384) ||
      !safeString(value.accountId, 256) || !Number.isSafeInteger(value.expires) || value.expires < 0)
    fail('storage_failure');
  return { ...value };
}
const inside = (p, root) => p === root || p.startsWith(root + path.sep);
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

// Synchronous filesystem sections deliberately contain no callback/await between
// final validation and rename. Ancestors and same-UID code must be trusted.
export class PrivateStore {
  constructor(directory, { forbiddenRoots } = {}) {
    if (!path.isAbsolute(directory) || path.normalize(directory) !== directory ||
        !Array.isArray(forbiddenRoots) || forbiddenRoots.length === 0 ||
        forbiddenRoots.some(root => !path.isAbsolute(root) || inside(directory, path.resolve(root))) ||
        directory.split(path.sep).some(s => ['.codex', '.pi', '.amp', '.config'].includes(s))) fail('storage_failure');
    this.directory = directory;
    this.file = path.join(directory, 'credential.json');
    this.lock = path.join(directory, 'lock');
  }
  checkDirectory() {
    let current = path.parse(this.directory).root;
    const parts = this.directory.slice(current.length).split(path.sep);
    for (let i = 0; i < parts.length; i++) {
      current = path.join(current, parts[i]);
      const final = i === parts.length - 1;
      let stat;
      try { stat = fs.lstatSync(current); }
      catch (e) {
        if (e.code !== 'ENOENT' || !final) throw e;
        fs.mkdirSync(current, { mode: 0o700 }); stat = fs.lstatSync(current);
      }
      if (!stat.isDirectory() || stat.isSymbolicLink() ||
          (stat.uid !== process.getuid() && stat.uid !== 0) ||
          (final ? stat.uid !== process.getuid() || (stat.mode & 0o777) !== 0o700
            : (stat.mode & 0o022) !== 0 && !(stat.uid === 0 && (stat.mode & 0o1000)))) fail('storage_failure');
    }
  }
  readState() {
    this.checkDirectory();
    let fd;
    try {
      // lstat before open avoids opening FIFOs/devices; O_NOFOLLOW closes symlink races.
      let st;
      try { st = fs.lstatSync(this.file); } catch (e) {
        if (e.code === 'ENOENT') return { version: 1, generation: randomUUID() };
        throw e;
      }
      if (!st.isFile() || st.nlink !== 1 || st.uid !== process.getuid() || (st.mode & 0o777) !== 0o600 || st.size > 65536) fail('storage_failure');
      fd = fs.openSync(this.file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
      const opened = fs.fstatSync(fd);
      if (opened.ino !== st.ino || opened.dev !== st.dev || opened.size > 65536) fail('storage_failure');
      const data = Buffer.alloc(65537);
      const count = fs.readSync(fd, data, 0, data.length, 0);
      if (count > 65536) fail('storage_failure');
      const state = JSON.parse(data.subarray(0, count).toString('utf8'));
      if (!state || state.version !== 1 || typeof state.generation !== 'string' ||
          !/^[0-9a-f-]{36}$/.test(state.generation) ||
          Object.keys(state).some(k => !['version', 'generation', 'credential'].includes(k))) fail('storage_failure');
      if (state.credential !== undefined) credential(state.credential);
      return state;
    } finally { if (fd !== undefined) fs.closeSync(fd); }
  }
  writeState(state, op) {
    op.check(); this.readState();
    if (state.credential !== undefined) credential(state.credential);
    const data = JSON.stringify(state);
    if (Buffer.byteLength(data) > 65536) fail('storage_failure');
    const temp = path.join(this.directory, `.write-${randomUUID()}`);
    let fd;
    try {
      fd = fs.openSync(temp, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o600);
      fs.writeFileSync(fd, data); fs.closeSync(fd); fd = undefined;
      op.check(); this.readState(); fs.renameSync(temp, this.file);
    } finally {
      if (fd !== undefined) fs.closeSync(fd);
      try { fs.unlinkSync(temp); } catch (e) { if (e.code !== 'ENOENT') throw e; }
    }
  }
  async locked(op, fn) {
    const end = Math.min(op.deadline, Date.now() + 5000);
    let held = false;
    try {
      while (!held) {
        op.check(); this.checkDirectory();
        try {
          fs.mkdirSync(this.lock, { mode: 0o700 }); held = true;
          const st = fs.lstatSync(this.lock);
          if (!st.isDirectory() || st.uid !== process.getuid() || (st.mode & 0o777) !== 0o700) fail('storage_failure');
        }
        catch (e) {
          if (e.code !== 'EEXIST') throw e;
          if (Date.now() >= end) fail('storage_failure');
          await pause(Math.min(20, Math.max(1, end - Date.now())));
        }
      }
      op.check(); return await fn(this.readState());
    } catch (e) { if (e instanceof AuthError) throw e; fail('storage_failure'); }
    finally {
      if (held) try { fs.rmdirSync(this.lock); } catch { fail('storage_failure'); }
    }
  }
  async read(id, op) { this.id(id); return this.locked(op, state => state.credential); }
  async list(op) { return this.locked(op, state => state.credential ? [{ providerId, type: 'oauth' }] : []); }
  id(id) { if (id !== providerId) fail('storage_failure'); }
  async modify(id, fn, op) {
    this.id(id);
    return this.locked(op, async state => {
      const next = await op.wait(Promise.resolve().then(() => fn(state.credential)));
      op.check();
      if (next === undefined) return state.credential;
      const checked = credential(next);
      this.writeState({ ...state, credential: checked }, op);
      return checked;
    });
  }
  async delete(id, op) {
    this.id(id);
    await this.locked(op, () => this.writeState({ version: 1, generation: randomUUID() }, op));
  }
  async begin(op) {
    return this.locked(op, state => {
      const generation = randomUUID();
      this.writeState({ ...state, generation }, op); return generation;
    });
  }
  async commit(generation, value, op) {
    return this.locked(op, state => {
      if (state.generation !== generation) fail('conflict');
      this.writeState({ ...state, credential: credential(value) }, op);
    });
  }
}
