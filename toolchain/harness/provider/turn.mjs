import { createModels } from './.cache/runtime/models.ts';
import { openaiCodexProvider } from './.cache/runtime/providers/openai-codex.ts';
import { Value } from 'typebox/value';

const endpoint = 'https://chatgpt.com/backend-api/codex/responses';
const unknown = () => ({ status: 'unknown' });
const fail = (code) => ({ kind: 'error', error: { code }, usage: unknown() });
const counter = (n) => Number.isSafeInteger(n) && n >= 0;
function usageOf(u) {
  const input = u?.input_tokens, output = u?.output_tokens;
  const read = u?.input_tokens_details?.cached_tokens;
  const write = u?.input_tokens_details?.cache_write_tokens;
  const total = u?.total_tokens;
  if (![input, output, read, write, total].every(counter) || read + write > input || total !== input + output)
    return unknown();
  const reasoning = u?.output_tokens_details?.reasoning_tokens;
  if (reasoning !== undefined && (!counter(reasoning) || reasoning > output)) return unknown();
  return { status: 'reported', input: input - read - write, output, cacheRead: read,
    cacheWrite: write, total, ...(reasoning === undefined ? {} : { reasoning }) };
}

/** One native Pi turn; caller supplies transport and an already resolved access token. */
export async function turn({ context, tools, accessToken, fetch: transport, signal, deadlineMs = 5000 }) {
  if (!accessToken || typeof accessToken !== 'string') return fail('authentication');
  if (typeof transport !== 'function' || !Number.isFinite(deadlineMs) || deadlineMs <= 0 || deadlineMs > 5000)
    return fail('unsupported');
  if (signal?.aborted) return fail('cancelled');
  if (!context || !Array.isArray(context.messages) || !Array.isArray(tools) ||
      tools.some(t => !t || typeof t.name !== 'string' || !t.parameters || t.grammar) ||
      new Set(tools.map(t => t.name)).size !== tools.length ||
      context.messages.some(m => m.role === 'system' && (m.toolsAdded?.length || m.toolsRemoved?.length)))
    return fail('unsupported');
  const controller = new AbortController();
  let timedOut = false, status, terminal, rejected = false, upstreamFailed = false, overflow = false;
  let usage = unknown();
  const onAbort = () => controller.abort();
  signal?.addEventListener('abort', onAbort, { once: true });
  const timer = setTimeout(() => { timedOut = true; controller.abort(); }, deadlineMs);
  const calls = new Map();
  const observe = (event) => {
    if (!event || typeof event.type !== 'string') { rejected = true; return; }
    if (event.type === 'response.output_item.done' && !['function_call', 'message', 'reasoning'].includes(event.item?.type)) rejected = true;
    if (event.type === 'response.function_call_arguments.done' && typeof event.arguments !== 'string') rejected = true;
    if (event.type === 'error' || event.type === 'response.failed') upstreamFailed = true;
    if (event.type === 'response.output_item.done' && event.item?.type === 'function_call') {
      const item = event.item;
      if (calls.has(item.call_id)) rejected = true;
      try {
        if (typeof item.arguments !== 'string' || typeof item.call_id !== 'string' || !item.call_id) throw 0;
        const args = JSON.parse(item.arguments);
        const tool = tools.find(t => t.name === item.name);
        if (!tool || !args || Array.isArray(args) || typeof args !== 'object' || !Value.Check(tool.parameters, args)) throw 0;
        calls.set(item.call_id, args);
      } catch { rejected = true; }
    }
    if (['response.done', 'response.completed', 'response.incomplete'].includes(event.type)) {
      terminal = event.response?.status;
      usage = usageOf(event.response?.usage);
    }
  };
  try {
    const models = createModels({ authContext: { env: async () => undefined, fileExists: async () => false } });
    // Request-scoped resolved credentials only: no OAuth refresh/login/storage path.
    const provider = openaiCodexProvider();
    models.setProvider({ ...provider, auth: { apiKey: { name: 'Caller supplied access token', resolve: async ({ credential }) =>
      credential?.key ? { auth: { apiKey: credential.key }, source: 'supplied' } : undefined } } });
    const model = models.getModel('openai-codex', 'gpt-6-astra');
    if (!model) return fail('unsupported');
    const message = await models.complete(model, { ...context, tools }, {
      apiKey: accessToken, transport: 'sse', reasoningEffort: 'low', maxRetries: 0,
      signal: controller.signal, timeoutMs: deadlineMs, onSseEvent: observe,
      onPayload: body => ({ ...body, parallel_tool_calls: false }),
      fetch: async (url, init) => {
        if (String(url) !== endpoint || init.method !== 'POST') { rejected = true; throw new Error('egress rejected'); }
        const response = await new Promise((resolve, reject) => {
          const aborted = () => reject(new Error('cancelled'));
          controller.signal.addEventListener('abort', aborted, { once: true });
          if (controller.signal.aborted) { aborted(); return; }
          Promise.resolve().then(() => transport(url, { ...init, redirect: 'error' })).then(response => {
            if (controller.signal.aborted) { void response.body?.cancel().catch(() => {}); return; }
            resolve(response);
          }, reject).finally(() => controller.signal.removeEventListener('abort', aborted));
        });
        status = response.status;
        if (!response.body) return response;
        let bytes = 0;
        const bounded = response.body.pipeThrough(new TransformStream({ transform(chunk, out) {
          bytes += chunk.byteLength;
          if (bytes > 65536) { overflow = true; throw new Error('response limit'); }
          out.enqueue(chunk);
        } }), { signal: controller.signal });
        return new Response(bounded, { status: response.status, headers: response.headers });
      },
    });
    if (timedOut) return fail('timeout');
    if (signal?.aborted) return fail('cancelled');
    if (status === 401) return fail('authentication');
    if (overflow || rejected) return fail('unsupported');
    if ((status !== undefined && status >= 400) || upstreamFailed) return fail('provider');
    if (terminal === 'incomplete') return fail('incomplete');
    if (terminal === 'cancelled') return fail('cancelled');
    if (terminal !== 'completed') return fail(status === undefined ? 'provider' : 'incomplete');
    if (message.stopReason === 'error' || message.stopReason === 'aborted') return fail('unsupported');
    const toolCalls = message.content.filter(c => c.type === 'toolCall');
    if (toolCalls.length > 1 || calls.size > 1) return fail('unsupported');
    if (toolCalls.length === 1) {
      const call = toolCalls[0];
      const args = calls.get(call.id.split('|')[0]);
      if (!args || JSON.stringify(args) !== JSON.stringify(call.arguments)) return fail('unsupported');
      return { kind: 'tool', call, message, usage };
    }
    const text = message.content.filter(c => c.type === 'text').map(c => c.text).join('');
    if (!text || calls.size) return fail('unsupported');
    return { kind: 'final', text, message, usage };
  } catch {
    return fail(timedOut ? 'timeout' : signal?.aborted ? 'cancelled' : status === 401 ? 'authentication' :
      overflow || rejected ? 'unsupported' : status !== undefined && status < 400 ? 'incomplete' : 'provider');
  } finally {
    clearTimeout(timer);
    controller.abort();
    signal?.removeEventListener('abort', onAbort);
  }
}

export function legacyUsage(usage) {
  if (usage.status !== 'reported') throw new Error('legacy contract cannot represent unknown usage');
  return usage;
}
