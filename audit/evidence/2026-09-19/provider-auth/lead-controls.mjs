// Independent response cleanup controls; synthetic streams, no network or store.
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
const { installTransport, inOperation } = await import(pathToFileURL(process.argv[2]));
let transport, calls = 0;
installTransport((...args) => { calls++; return transport(...args); });
const request = options => inOperation(options, () => fetch('https://auth.openai.com/oauth/token', {
  method: 'POST', body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: 'synthetic' }),
}));
let release, entered, lateCancelled = false;
const started = new Promise(resolve => { entered = resolve; });
const pending = new Promise(resolve => { release = resolve; });
transport = () => { entered(); return pending; };
const controller = new AbortController();
const first = request({ signal: controller.signal });
await started;
controller.abort();
await assert.rejects(first);
release(new Response(new ReadableStream({ cancel() { lateCancelled = true; } })));
await new Promise(resolve => setTimeout(resolve, 50));
assert.equal(lateCancelled, true);
assert.equal(calls, 1);
let redirectCancelled = false;
transport = () => new Response(new ReadableStream({ cancel() { redirectCancelled = true; } }), {
  status: 302, headers: { location: 'https://example.invalid/forbidden' },
});
await assert.rejects(request({}));
await new Promise(resolve => setTimeout(resolve, 10));
assert.equal(redirectCancelled, true);
assert.equal(calls, 2);
console.log(JSON.stringify({ controls: 2, passed: 2, lateCancelled, redirectCancelled, calls, networkRequests: 0 }));
