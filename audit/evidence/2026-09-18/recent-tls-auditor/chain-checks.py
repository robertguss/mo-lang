"""Independent real brick handshakes; generated test-only Ed25519 chains.
Run from repository root after zig build-lib toolchain/src/bricks/tls.zig
-dynamic -lc -O ReleaseSafe -femit-bin=/tmp/libmo-audit-tls.so.
No private keys are persisted. OpenSSL checks the same certificates.
"""
import ctypes as C
import datetime as D
import json
import pathlib
import subprocess
import tempfile
from cryptography import x509
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization as S
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID, ObjectIdentifier
lib = C.CDLL('/tmp/libmo-audit-tls.so')
p = C.c_void_p
for name,args,ret in [
 ('server_new',[C.c_char_p,C.c_size_t,C.c_char_p,C.c_size_t],p),
 ('client_new',[C.c_char_p,C.c_size_t],p),('conn_new',[p],p),
 ('client_offer',[p,C.c_char_p,C.c_size_t],p),('server_offer',[p,C.c_char_p,C.c_size_t],p),
 ('connect',[p,C.c_char_p,C.c_size_t,C.c_int64],p),
 ('flush',[p,p,C.c_size_t,C.POINTER(C.c_size_t)],C.c_int),
 ('sent',[p,C.c_size_t],None),('feed',[p,p,C.c_size_t],C.c_int),
 ('ready',[p],C.c_bool),('alert',[p],C.c_int),
 ('conn_free',[p],None),('server_free',[p],None),('client_free',[p],None)]:
 f=getattr(lib,'mo_tls_'+name); f.argtypes=args; f.restype=ret

def cert(name,key,issuer,signer,ca=False,path=None,extra=[]):
 b=x509.CertificateBuilder().subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,name)])).issuer_name(issuer).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(D.datetime(2025,1,1)).not_valid_after(D.datetime(2035,1,1)).add_extension(x509.BasicConstraints(ca,path),critical=True)
 for e,c in extra: b=b.add_extension(e,c)
 return b.sign(signer,None)
def pem(c): return c.public_bytes(S.Encoding.PEM)
def run(case):
 keys=[ed25519.Ed25519PrivateKey.generate() for _ in range(4)]
 rootname=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'root')])
 root=cert('root',keys[0],rootname,keys[0],True)
 ext=[]
 if case=='ca-keyusage': ext=[(x509.KeyUsage(True,False,False,False,False,False,False,None,None),True)]
 inter=cert('inter',keys[1],root.subject,keys[0],True,0,ext)
 issuer,signer=inter,keys[1]; rest=[inter]
 if case=='pathlen':
  sub=cert('sub',keys[2],inter.subject,keys[1],True,0)
  issuer,signer=sub,keys[2]; rest=[sub,inter]
 extras=[(x509.SubjectAlternativeName([x509.DNSName('localhost')]),False)]
 if case=='eku-client-only': extras.append((x509.ExtendedKeyUsage([ExtendedKeyUsageOID.CLIENT_AUTH]),False))
 if case=='unknown-critical': extras.append((x509.UnrecognizedExtension(ObjectIdentifier('1.2.3.4.5.6'),b'\x05\x00'),True))
 leaf=cert('localhost',keys[3],issuer.subject,signer,extra=extras)
 chain=pem(leaf)+b''.join(map(pem,rest)); trust=pem(root)
 key=keys[3].private_bytes(S.Encoding.PEM,S.PrivateFormat.PKCS8,S.NoEncryption())
 server=lib.mo_tls_server_new(chain,len(chain),key,len(key)); client=lib.mo_tls_client_new(trust,len(trust))
 assert server and client
 if case == 'alpn-65':
  names=b'\x00'.join(('p%d'%i).encode() for i in range(65))
  new_client=lib.mo_tls_client_offer(client,names,len(names)); lib.mo_tls_client_free(client); client=new_client
  new_server=lib.mo_tls_server_offer(server,b'p64',3); lib.mo_tls_server_free(server); server=new_server
 s=lib.mo_tls_conn_new(server); c=lib.mo_tls_connect(client,b'localhost',9,1767225600)
 assert s and c
 buf=C.create_string_buffer(65536)
 for _ in range(20):
  moved=0
  for a,b in [(c,s),(s,c)]:
   n=C.c_size_t(); lib.mo_tls_flush(a,buf,len(buf),C.byref(n)); lib.mo_tls_sent(a,n.value)
   if n.value: lib.mo_tls_feed(b,buf,n.value); moved+=n.value
  if not moved: break
 result={'case':case,'brick_client_ready':lib.mo_tls_ready(c),'brick_server_ready':lib.mo_tls_ready(s),'brick_client_alert':lib.mo_tls_alert(c)}
 for obj in [s,c]: lib.mo_tls_conn_free(obj)
 lib.mo_tls_server_free(server); lib.mo_tls_client_free(client)
 with tempfile.TemporaryDirectory() as d:
  d=pathlib.Path(d)
  for name,data in [('root',trust),('leaf',pem(leaf)),('inter',b''.join(map(pem,rest)))]: (d/name).write_bytes(data)
  r=subprocess.run(['openssl','verify','-attime','1767225600','-purpose','sslserver','-verify_hostname','localhost','-CAfile',str(d/'root'),'-untrusted',str(d/'inter'),str(d/'leaf')],text=True,capture_output=True)
  result.update(openssl_exit=r.returncode,openssl_output=(r.stdout+r.stderr).replace(str(d),'TMP').strip())
 return result
print(json.dumps([run(s) for s in ['control','pathlen','ca-keyusage','eku-client-only','unknown-critical','alpn-65']],indent=2))
