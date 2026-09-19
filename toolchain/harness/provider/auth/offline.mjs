// CLI fixture preload: deny all transport before application/upstream imports.
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import dns from 'node:dns';
import dgram from 'node:dgram';
import { syncBuiltinESMExports } from 'node:module';
const deny = () => { throw Error('offline_denied'); };
globalThis.fetch = deny;
globalThis.WebSocket = class { constructor() { deny(); } };
for (const [object, names] of [[http,['request','get','createServer']], [https,['request','get','createServer']],
  [net,['connect','createConnection','createServer']], [tls,['connect','createServer']],
  [dns,['lookup','resolve','resolve4','resolve6']], [dns.promises,['lookup','resolve','resolve4','resolve6']],
  [dgram,['createSocket']]]) for (const name of names) object[name] = deny;
net.Socket.prototype.connect = deny;
syncBuiltinESMExports();
