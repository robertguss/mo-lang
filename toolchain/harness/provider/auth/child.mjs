import fs from 'node:fs';
import { PrivateStore, providerId } from './store.mjs';
import { Operation } from './auth.mjs';
const [directory, mode, forbidden] = process.argv.slice(2);
const store = new PrivateStore(directory, { forbiddenRoots: [forbidden] });
const op = new Operation(30000);
try {
  if (mode === 'hold') await store.locked(op, async () => {
    process.send('held');
    await new Promise(resolve => process.once('message', resolve));
  });
  else if (mode === 'delete') { await store.delete(providerId, op); process.send('deleted'); }
} finally { op.close(); }
process.disconnect();
