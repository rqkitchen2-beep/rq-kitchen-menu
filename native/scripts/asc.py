#!/usr/bin/env python3
"""Minimal App Store Connect API helper. Needs ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER."""
import jwt, time, sys, json, os, urllib.request, urllib.error
KID=os.environ["ASC_KEY_ID"]; ISS=os.environ["ASC_ISSUER"]
KEY=open(os.environ["ASC_KEY_PATH"]).read()
def tok():
    n=int(time.time())
    return jwt.encode({"iss":ISS,"iat":n,"exp":n+1100,"aud":"appstoreconnect-v1"},KEY,algorithm="ES256",headers={"kid":KID,"typ":"JWT"})
def call(method,path,body=None):
    req=urllib.request.Request("https://api.appstoreconnect.apple.com"+path,method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization":"Bearer "+tok(),"Content-Type":"application/json"})
    try:
        r=urllib.request.urlopen(req,timeout=60); return r.status,json.loads(r.read() or b'{}')
    except urllib.error.HTTPError as e:
        return e.code,json.loads(e.read() or b'{}')
def ensure_bundle(ident,name):
    s,j=call("GET",f"/v1/bundleIds?filter[identifier]={ident}&limit=5")
    for d in j.get("data",[]):
        if d["attributes"]["identifier"]==ident: return d
    s,j=call("POST","/v1/bundleIds",{"data":{"type":"bundleIds","attributes":{"identifier":ident,"name":name,"platform":"IOS"}}})
    if s>=300: print("bundle error",s,json.dumps(j),file=sys.stderr); sys.exit(1)
    return j["data"]
def find_app(ident):
    s,j=call("GET",f"/v1/apps?filter[bundleId]={ident}&limit=5")
    for d in j.get("data",[]):
        if d["attributes"]["bundleId"]==ident: return d
    return None
if __name__=="__main__":
    cmd=sys.argv[1]
    if cmd=="ensure-bundle":
        d=ensure_bundle(sys.argv[2],sys.argv[3]); print(d["attributes"].get("seedId",""))
    elif cmd=="find-app":
        d=find_app(sys.argv[2]); print(d["id"] if d else "")
    elif cmd=="raw":
        s,j=call(sys.argv[2],sys.argv[3],json.loads(sys.argv[4]) if len(sys.argv)>4 else None); print(s); print(json.dumps(j,indent=1)[:4000])
