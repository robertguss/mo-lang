// Independent parser controls over real loopback HTTP and deterministic byte chunks.
import assert from 'node:assert/strict';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import dns from 'node:dns';
import { syncBuiltinESMExports } from 'node:module';
import { pathToFileURL } from 'node:url';
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';

const nativeFetch = globalThis.fetch;
const server = http.createServer();
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const port = server.address().port;
const connect = net.Socket.prototype.connect;
const deny = () => { throw new Error('unexpected network path'); };
net.Socket.prototype.connect = function (...args) {
  const options = Array.isArray(args[0]) ? args[0][0] : args[0];
  if (typeof options !== 'object' || options.host !== '127.0.0.1' || Number(options.port) !== port) return deny();
  return connect.apply(this, args);
};
http.request = http.get = https.request = https.get = tls.connect = dns.lookup = dns.resolve = deny;
for (const key of Object.keys(dns.promises)) if (typeof dns.promises[key] === 'function') dns.promises[key] = deny;
globalThis.fetch = globalThis.WebSocket = deny;
syncBuiltinESMExports();
const { turn } = await import(pathToFileURL(join(process.argv[2], 'turn.mjs')));
const accessToken = 'synthetic.' + Buffer.from(JSON.stringify({ 'https://api.openai.com/auth': { chatgpt_account_id: 'lead-fixture' } })).toString('base64url') + '.synthetic';
const text = 'Mo café 🦉 漢字';
const item = { type: 'message', id: 'msg_lead', role: 'assistant', status: 'completed', content: [{ type: 'output_text', text }] };
let usage, requests = 0, byteChunks = 0;
server.on('request', (req, res) => {
  requests++;
  req.resume();
  req.on('end', () => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    const events = [
      { type: 'response.output_item.done', output_index: 0, item },
      { type: 'response.completed', response: { id: 'resp_lead', status: 'completed', output: [item], usage } },
    ];
    res.end(events.map(event => 'data: ' + JSON.stringify(event) + '\n\n').join(''));
  });
});
const observations = [];
try {
  for (const invalid of [false, true]) {
    usage = { input_tokens: 10, output_tokens: 5, total_tokens: invalid ? true : 15,
      input_tokens_details: { cached_tokens: 0, cache_write_tokens: 0 } };
    const start = requests;
    const result = await turn({ context: { messages: [{ role: 'user', content: 'lead fixture', timestamp: 1 }] }, tools: [], accessToken,
      fetch: async (_url, init) => {
        const response = await nativeFetch(`http://127.0.0.1:${port}/`, init);
        const split = response.body.pipeThrough(new TransformStream({ transform(chunk, out) {
          for (const byte of chunk) { out.enqueue(Uint8Array.of(byte)); byteChunks++; }
        } }));
        return new Response(split, { status: response.status, headers: response.headers });
      },
    });
    assert.equal(result.kind, 'final');
    assert.equal(result.text, text);
    assert.equal(requests - start, 1);
    assert.equal(result.usage.status, invalid ? 'unknown' : 'reported');
    observations.push({ case: invalid ? 'boolean total is unknown' : 'UTF-8 split at every byte', passed: true,
      requests: requests - start, usage: result.usage, text: result.text });
  }
  assert(byteChunks > 0);
  console.log(JSON.stringify({ passed: 2, controls: observations, byte_chunks: byteChunks, node: process.version }, null, 2));
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  writeFileSync(process.argv[3], JSON.stringify({ observations, requests, byteChunks, server_closed: true }, null, 2) + '\n');
}
