# Provider source review — 19 Sep 2026

Scope: read-only source/API research by `mo-provider`, GPT-6-Astra at low
reasoning in Herdr pane w4:pT, shared lead checkout. No source changes, package
installation, credentials, login or inference. The worker finished at 12:38 AM
ET, reported no writers, and the lead retained its report before closing the
owned pane. `receipt.json` binds the raw report bytes.

- `worker-pane.txt`: terminal capture, including the complete report and direct
  bibliography. Narrow terminal wrapping is preserved. This is a worker's
  research report, not executable proof or a lead acceptance verdict.
- `receipt.json`: agent/pin/capture identity and no-writer report.
- Lead scope/decisions (open after your own reading):
  `mo-wiki/plans/mo-provider-foundation.md` and the 19 Sep decision-log row.

Source: <https://github.com/earendil-works/pi/tree/36b60d2e8985899743c4cf5bd5f8929832a3f05d/packages/ai>.
The bibliography covers the package manifest, generated models, Models API,
Codex provider/transport, shared Responses parser and OAuth/credential types.
Official authentication guidance:
<https://developers.openai.com/codex/auth>.

Principal implementation questions: source/artifact/catalog correspondence;
native conversation preservation; usage presence before Pi's zero defaults;
hidden retries; sanitized errors; serialized credential persistence in a later
slice. API documentation and source interoperability do not establish this
account's model access or official support for an independent Mo client.

No test count or runtime acceptance is claimed by this bundle.
