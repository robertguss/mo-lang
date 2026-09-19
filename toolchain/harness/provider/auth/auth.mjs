import { AsyncLocalStorage } from 'node:async_hooks';
import { pathToFileURL, fileURLToPath } from 'node:url';
import path from 'node:path';
import { AuthError, fail, credential, PrivateStore, providerId } from './store.mjs';

export class Operation {
  constructor(maximum, { deadlineMs = maximum, signal } = {}) {
    if (!Number.isSafeInteger(deadlineMs) || deadlineMs < 1 || deadlineMs > maximum) fail('provider_failure');
    this.deadline = Date.now() + deadlineMs;
    this.controller = new AbortController(); this.signal = this.controller.signal;
    this.external = signal;
    this.cancel = () => this.controller.abort(new AuthError('cancelled'));
    if (signal?.aborted) this.cancel();
    signal?.addEventListener('abort', this.cancel, { once: true });
    this.timer = setTimeout(() => this.controller.abort(new AuthError('timeout')), deadlineMs);
  }
  check() {
    if (this.signal.aborted) throw this.signal.reason;
    if (Date.now() >= this.deadline) { this.controller.abort(new AuthError('timeout')); throw this.signal.reason; }
  }
  async wait(promise) {
    this.check();
    let listener;
    try {
      return await Promise.race([promise, new Promise((_, reject) => {
        listener = () => reject(this.signal.reason);
        this.signal.addEventListener('abort', listener, { once: true });
      })]);
    } finally { this.signal.removeEventListener('abort', listener); }
  }
  close() { clearTimeout(this.timer); this.external?.removeEventListener('abort', this.cancel); }
}

const paths = new Set(['/api/accounts/deviceauth/usercode', '/api/accounts/deviceauth/token', '/oauth/token']);
const context = new AsyncLocalStorage();
let installed = false;
// Install exactly once in a dedicated process. No inference or other global-fetch
// consumer may share this process. Context keeps overlapping auth operations apart.
export function installTransport(transport) {
  if (installed || typeof transport !== 'function') fail('provider_failure');
  installed = true;
  globalThis.fetch = async (input, init = {}) => {
    const op = context.getStore();
    if (!op) fail('provider_failure');
    op.check();
    if (typeof input !== 'string') fail('provider_failure');
    const url = new URL(input);
    if (url.origin !== 'https://auth.openai.com' || !paths.has(url.pathname) ||
        input !== url.origin + url.pathname || init.method !== 'POST' ||
        init.redirect && init.redirect !== 'error') fail('provider_failure');
    if (!(typeof init.body === 'string' || init.body instanceof URLSearchParams) ||
        Buffer.byteLength(String(init.body)) > 65536) fail('provider_failure');
    const request = new Operation(Math.min(10000, Math.max(1, op.deadline - Date.now())), { signal: op.signal });
    let reader, response, closed = false;
    const cancelBody = value => {
      try { void value?.body?.cancel().catch(() => {}); } catch {}
    };
    try {
      const pending = Promise.resolve()
        .then(() => transport(input, { ...init, redirect: 'error', signal: request.signal }))
        .then(value => {
          response = value;
          if (closed || request.signal.aborted || op.signal.aborted) cancelBody(value);
          return value;
        });
      await request.wait(pending);
      request.check();
      if (response.redirected || response.status >= 300 && response.status < 400 || response.url && response.url !== input) fail('provider_failure');
      const chunks = []; let size = 0;
      reader = response.body?.getReader();
      if (reader) while (true) {
        const { done, value } = await request.wait(reader.read());
        request.check(); if (done) break;
        size += value.byteLength;
        if (size > 65536) fail('provider_failure');
        chunks.push(value);
      }
      return new Response(Buffer.concat(chunks), { status: response.status, headers: { 'content-type': 'application/json' } });
    } catch (e) {
      if (request.signal.aborted && request.signal.reason?.code === 'timeout')
        op.controller.abort(new AuthError('timeout'));
      request.controller.abort();
      if (e instanceof AuthError) throw e;
      fail('provider_failure');
    } finally {
      closed = true;
      if (reader) void reader.cancel().catch(() => {});
      else cancelBody(response);
      request.close();
    }
  };
}

export function interaction(op, sink) {
  return {
    signal: op.signal,
    async prompt(prompt) {
      op.check();
      if (prompt?.type !== 'select' || !Array.isArray(prompt.options) ||
          prompt.options.length !== 2 || prompt.options[0]?.id !== 'browser' || prompt.options[1]?.id !== 'device_code') fail('provider_failure');
      return 'device_code';
    },
    notify(event) {
      op.check();
      if (event?.type !== 'device_code' || event.verificationUri !== 'https://auth.openai.com/codex/device' ||
          typeof event.userCode !== 'string' || !/^[A-Za-z0-9-]{1,64}$/.test(event.userCode) ||
          !Number.isFinite(event.intervalSeconds) || event.intervalSeconds < 0 || event.intervalSeconds > 900 ||
          !Number.isInteger(event.expiresInSeconds) || event.expiresInSeconds < 1 || event.expiresInSeconds > 900) fail('provider_failure');
      sink({ type: 'device_code', verificationUri: event.verificationUri, userCode: event.userCode,
        intervalSeconds: event.intervalSeconds, expiresInSeconds: event.expiresInSeconds });
    },
  };
}
const codes = new Set(['authenticated', 'missing', 'cancelled', 'timeout', 'conflict', 'storage_failure', 'provider_failure']);
const outcome = e => ({ code: e instanceof AuthError && codes.has(e.code) ? e.code : 'provider_failure' });

export async function loadOAuth(runtimeDirectory) {
  if (!path.isAbsolute(runtimeDirectory)) fail('provider_failure');
  // Trusted setup verifies the complete runtime before supplying this explicit path.
  return (await import(pathToFileURL(path.join(runtimeDirectory, 'auth/oauth/openai-codex.ts')).href)).openaiCodexOAuth;
}

export function createAuth({ directory, candidateRoots, oauth, operatorSink = () => {} }) {
  if (!installed || !Array.isArray(candidateRoots)) fail('provider_failure');
  const repo = fileURLToPath(new URL('../../../../', import.meta.url));
  const store = new PrivateStore(directory, { forbiddenRoots: [path.resolve(repo), ...candidateRoots] });
  async function run(max, options, fn) {
    let op;
    try {
      op = new Operation(max, options);
      return await context.run(op, async () => { op.check(); return await fn(op); });
    } catch (e) { return outcome(op?.signal.aborted ? op.signal.reason : e); }
    finally { op?.close(); }
  }
  return {
    login(options) {
      return run(900000, options, async op => {
        const generation = await store.begin(op);
        const value = credential(await op.wait(oauth.login(interaction(op, operatorSink))));
        if (value.expires <= Date.now()) fail('provider_failure');
        op.check(); await store.commit(generation, value, op);
        return { code: 'authenticated' };
      });
    },
    status(options) {
      return run(30000, options, async op => {
        try {
          const value = await store.read(providerId, op);
          return { providerId, state: !value ? 'missing' : value.expires <= Date.now() ? 'expired' : 'authenticated' };
        } catch { return { providerId, state: 'unavailable' }; }
      }).then(result => result.state ? result : { providerId, state: 'unavailable' });
    },
    logout(options) {
      return run(30000, options, async op => { await store.delete(providerId, op); return { code: 'missing' }; });
    },
    resolve(options) {
      return run(30000, options, async op => {
        // One lock covers reread, refresh and persistence. No Models nested lock.
        const value = await store.modify(providerId, async current => {
          if (!current) return undefined;
          if (current.expires > Date.now()) return undefined;
          const refreshed = credential(await op.wait(oauth.refresh(current, op.signal)));
          if (refreshed.expires <= Date.now()) fail('provider_failure');
          return refreshed;
        }, op);
        if (!value) return { code: 'missing' };
        op.check();
        if (value.expires <= Date.now()) fail('provider_failure');
        const auth = await op.wait(oauth.toAuth(value));
        op.check();
        if (auth.apiKey !== value.access) fail('provider_failure');
        return { code: 'authenticated', accessToken: auth.apiKey };
      });
    },
    // Exact Pi CredentialStore surface; no token is ever written to stdout.
    credentialStore: Object.fromEntries(['read', 'list', 'modify', 'delete'].map(name => [name, async (...args) => {
      const count = { read: 1, list: 0, modify: 2, delete: 1 }[name];
      const op = new Operation(30000, args[count]);
      try { return await context.run(op, () => store[name](...args.slice(0, count), op)); }
      finally { op.close(); }
    }])),
  };
}

// Test-only access to the same transport context; no ambient operation permitted.
export async function inOperation(options, fn) {
  const op = new Operation(30000, options);
  try { return await context.run(op, () => fn(op)); } finally { op.close(); }
}
