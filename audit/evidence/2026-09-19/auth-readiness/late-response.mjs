// Lead transport-race probe. Synthetic response only; no network or store access.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
const source = process.argv[2];
const hash = () => createHash('sha256').update(fs.readFileSync(source)).digest('hex');
const before = hash();
const { installTransport, inOperation } = await import(pathToFileURL(source));
let release, entered, cancelled = false, calls = 0;
const started = new Promise(resolve => { entered = resolve; });
const pending = new Promise(resolve => { release = resolve; });
installTransport(() => { calls++; entered(); return pending; });
const controller = new AbortController();
const request = inOperation({ signal: controller.signal }, () => fetch('https://auth.openai.com/oauth/token', {
  method: 'POST', body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: 'synthetic-only' }),
}));
await started;
controller.abort();
await assert.rejects(request);
const response = new Response(new ReadableStream({ cancel() { cancelled = true; } }));
release(response);
await new Promise(resolve => setTimeout(resolve, 50));
const record = { calls, lateBodyCancelled: cancelled, sourceSha256: before, sourceUnchanged: hash() === before };
console.log(JSON.stringify(record));
process.exitCode = cancelled && record.sourceUnchanged ? 0 : 1;
