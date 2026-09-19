import fs from 'node:fs';
import { createAuth, installTransport, loadOAuth } from './auth.mjs';

// Deliberately no defaults, credential discovery, environment flags or export verb.
const [command, directory, runtime, candidateRoot, operatorFd, ...extra] = process.argv.slice(2);
try {
  if (!['login', 'status', 'logout'].includes(command) || extra.length || !directory || !runtime || !candidateRoot ||
      command === 'login' && (!/^\d+$/.test(operatorFd ?? '') || Number(operatorFd) < 3)) throw Error();
  const transport = globalThis.fetch;
  installTransport(transport);
  const oauth = await loadOAuth(runtime);
  const controller = new AbortController();
  process.once('SIGINT', () => controller.abort());
  process.once('SIGTERM', () => controller.abort());
  process.once('disconnect', () => controller.abort());
  const auth = createAuth({ directory, candidateRoots: [candidateRoot], oauth,
    operatorSink: event => fs.writeSync(Number(operatorFd), JSON.stringify(event) + '\n') });
  const result = await auth[command]({ signal: controller.signal });
  process.stdout.write(JSON.stringify(result) + '\n');
  if (result.code && !['authenticated', 'missing'].includes(result.code)) process.exitCode = 1;
} catch {
  process.stdout.write('{"code":"provider_failure"}\n'); process.exitCode = 1;
}
