import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
globalThis.fetch = () => { throw new Error('catalog generation network forbidden'); };
const { selected } = await import('./.cache/source/pi-36b60d2e8985899743c4cf5bd5f8929832a3f05d/packages/ai/scripts/offline-selected.ts');
const artifact = JSON.parse(readFileSync('.cache/artifact/package/dist/providers/data/openai-codex.json'))['openai-codex-responses']['gpt-6-astra'];
const differences = {};
for (const key of new Set([...Object.keys(artifact), ...Object.keys(selected)])) {
  if (JSON.stringify(artifact[key]) !== JSON.stringify(selected[key])) differences[key] = { artifact: artifact[key], pinnedGenerator: selected[key] };
}
assert.equal(selected.id, 'gpt-6-astra');
assert.equal(selected.thinkingLevelMap.low, 'low');
const catalog = JSON.stringify({ 'openai-codex-responses': { 'gpt-6-astra': selected } }, null, 2)+'\n';
writeFileSync('catalog.json', catalog);
writeFileSync('.cache/runtime/providers/data/openai-codex.json', catalog);
const hashes = JSON.parse(readFileSync('evidence/runtime-hashes.json'));
hashes['providers/data/openai-codex.json'] = createHash('sha256').update(catalog).digest('hex');
writeFileSync('evidence/runtime-hashes.json', JSON.stringify(hashes,null,2)+'\n');
writeFileSync('evidence/catalog-comparison.json', JSON.stringify({origin:'Exact pinned generator codexModels literal and its complete metadata pass, evaluated offline; no remote catalog inputs', artifact, selected, differences, selected_sha256:hashes['providers/data/openai-codex.json']},null,2)+'\n');
console.log(JSON.stringify({ differences, selected_sha256: hashes['providers/data/openai-codex.json'] },null,2));
