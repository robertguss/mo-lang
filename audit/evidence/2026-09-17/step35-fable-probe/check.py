import json, sys
exp=json.load(open(sys.argv[1])); got={}
for line in open(sys.argv[2]):
    k,_,v=line.strip().partition(' '); got[k]=v
bad=[]
for k,v in exp.items():
    if got.get(k)!=v: bad.append((k, got.get(k,'MISSING')[:40], v[:40]))
truths={"gcm_open_ok":"true","gcm_open_flipped_tag":"true","gcm_open_short":"true","gcm_open_wrong_aad":"true","gcm_empty":"16","cc_open_ok":"true","cc_big_roundtrip":"true","verify_ok":"true","verify_wrong_msg":"false","verify_bad_key":"false","shared_low_order":"true","from_hex_upper":"true","from_hex_odd":"true","from_hex_bad":"true","from_hex_empty":"true","equal_sizes":"false true","phc_verify":"true false","random_size":"40"}
for k,v in truths.items():
    if got.get(k)!=v: bad.append((k, got.get(k,'MISSING'), v))
print("lines", len(got), "mismatches", len(bad), bad)
