"""Hydrate exact source, frozen catalog, and a disclosed SSE observation hook."""
import pathlib, shutil, hashlib, json, difflib
root = pathlib.Path(__file__).resolve().parent
source = root / '.cache/source/pi-36b60d2e8985899743c4cf5bd5f8929832a3f05d/packages/ai/src'
runtime = root / '.cache/runtime'
shutil.copytree(source, runtime, dirs_exist_ok=True)
(runtime/'package.json').write_text('{"type":"module"}\n')
shutil.copytree(root/'.cache/artifact/package/dist/providers/data', runtime/'providers/data', dirs_exist_ok=True)
path = runtime/'api/openai-codex-responses.ts'
before = path.read_text()
after = before.replace('export interface OpenAICodexResponsesOptions extends StreamOptions {', 'export interface OpenAICodexResponsesOptions extends StreamOptions {\n\tonSseEvent?: (event: Record<string, unknown>) => void;')
after = after.replace('parseSSE(response, options?.signal)', 'parseSSE(response, options?.signal, options?.onSseEvent)')
after = after.replace('signal?: AbortSignal): AsyncGenerator<Record<string, unknown>>', 'signal?: AbortSignal, observe?: (event: Record<string, unknown>) => void): AsyncGenerator<Record<string, unknown>>')
after = after.replace('yield JSON.parse(data) as Record<string, unknown>;', 'const event = JSON.parse(data) as Record<string, unknown>;\n\t\t\t\t\t\t\tobserve?.(event);\n\t\t\t\t\t\t\tyield event;')
assert before != after
path.write_text(after)
(root/'upstream.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True), fromfile='src/api/openai-codex-responses.ts', tofile='src/api/openai-codex-responses.ts')))
files = {str(p.relative_to(runtime)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(runtime.rglob('*')) if p.is_file()}
(root/'evidence/runtime-hashes.json').write_text(json.dumps(files, indent=2)+'\n')
print('runtime files', len(files), 'patch sha256', hashlib.sha256((root/'upstream.patch').read_bytes()).hexdigest())

# Make an offline entrypoint alongside the pinned generator dependencies.
# Its original network-driving main remains defined but is never invoked.
generator = source.parent/'scripts/generate-models.ts'
text = generator.read_text()
base = text[:text.index('// Run the generator')]
start = text.index('\tconst CODEX_BASE_URL =')
end = text.index('\tallModels.push(...codexModels);', start)
loop_start = text.index('\tfor (const model of allModels) {\n\t\tapplyOpenAICompletionsCompatMetadata(model);')
loop_end = text.index('\n\tapplyAnthropicAllowedFallbackModelMetadata', loop_start)
selected = text[start:end] + '\nconst allModels = codexModels;\n' + text[loop_start:loop_end] + '\nexport const selected = codexModels.find(m => m.id === "gpt-6-astra");\n'
(generator.parent/'offline-selected.ts').write_text(base + selected)
