"""Compare shipped sourcemap sources with the exact git archive, before patching."""
import hashlib, json, pathlib, difflib
root = pathlib.Path(__file__).resolve().parent
artifact = root / '.cache/artifact/package'
source = root / '.cache/source/pi-36b60d2e8985899743c4cf5bd5f8929832a3f05d/packages/ai'
rows = []
diffs = []
for path in sorted((artifact / 'dist').rglob('*.js.map')):
    data = json.loads(path.read_text())
    for name, content in zip(data['sources'], data.get('sourcesContent', [])):
        relative = (path.parent / name).resolve().relative_to(artifact.resolve())
        original = source / relative
        if original.exists() and str(relative) in ('src/api/openai-codex-responses.ts', 'src/api/openai-responses-shared.ts', 'src/models.ts', 'src/auth/resolve.ts', 'src/auth/oauth/openai-codex.ts', 'src/types.ts', 'src/api/transform-messages.ts'):
            diffs.extend(difflib.unified_diff(original.read_text().splitlines(True), content.splitlines(True), fromfile='git-pin/'+str(relative), tofile='npm-artifact/'+str(relative)))
        rows.append({'file': str(relative), 'match': original.exists() and original.read_text() == content, 'source_present': original.exists(), 'shipped_source_sha256': hashlib.sha256(content.encode()).hexdigest()})
catalog = artifact / 'dist/providers/data/openai-codex.json'
receipt = {'source_revision': '36b60d2e8985899743c4cf5bd5f8929832a3f05d', 'execution': 'Exact git TypeScript in .cache/runtime plus upstream.patch; npm provider implementation is not executed', 'selected_catalog': 'catalog.json generated offline from the pinned generator; see evidence/catalog-comparison.json', 'comparison': 'Embedded sourcemap TypeScript vs exact git archive; not a reproducible-build claim', 'files': rows, 'catalog': {'path': 'dist/providers/data/openai-codex.json', 'bytes': catalog.stat().st_size, 'sha256': hashlib.sha256(catalog.read_bytes()).hexdigest(), 'origin': 'npm artifact 0.85.1; generation inputs not attested by registry'}, 'artifact_integrity': json.loads((root/'evidence/downloads.json').read_text())['registry']['dist']}
(root / 'pin.json').write_text(json.dumps(receipt, indent=2)+'\n')
print('matched',sum(r['match'] for r in rows),'total',len(rows))
print('differences',json.dumps([r for r in rows if not r['match']],indent=2))

(root/'evidence/artifact-source.diff').write_text(''.join(diffs))
