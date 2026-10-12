#!/usr/bin/env python3
"""Create an Apple Distribution certificate and App Store profiles through the App Store Connect API."""
import sys, os, base64, json
sys.path.insert(0, os.path.dirname(__file__))
from asc import call
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12

def die(msg, j=None):
    print("ERROR:", msg, json.dumps(j)[:1500] if j else "", file=sys.stderr); sys.exit(1)

def make_cert(outdir, password):
    s, j = call("GET", "/v1/certificates?limit=200")
    if s >= 300: die("list certs", j)
    for c in j.get("data", []):
        if c["attributes"]["certificateType"] in ("DISTRIBUTION", "IOS_DISTRIBUTION"):
            call("DELETE", f"/v1/certificates/{c['id']}")
            print("revoked old cert", c["id"], file=sys.stderr)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = x509.CertificateSigningRequestBuilder().subject_name(x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, "RQ Kitchen CI"),
        x509.NameAttribute(NameOID.EMAIL_ADDRESS, "ci@rqkitchen.app"),
        x509.NameAttribute(NameOID.COUNTRY_NAME, "AE")])).sign(key, hashes.SHA256())
    pem = csr.public_bytes(serialization.Encoding.PEM).decode()
    s, j = call("POST", "/v1/certificates", {"data": {"type": "certificates",
        "attributes": {"certificateType": "DISTRIBUTION", "csrContent": pem}}})
    if s >= 300: die("create cert", j)
    cid = j["data"]["id"]
    cert = x509.load_der_x509_certificate(base64.b64decode(j["data"]["attributes"]["certificateContent"]))
    p12 = pkcs12.serialize_key_and_certificates(b"rq", key, cert, None,
        serialization.BestAvailableEncryption(password.encode()))
    os.makedirs(outdir, exist_ok=True)
    open(os.path.join(outdir, "dist.p12"), "wb").write(p12)
    print(cid)

def make_profile(ident, cert_id, outpath):
    s, j = call("GET", f"/v1/bundleIds?filter[identifier]={ident}&limit=5")
    bid = next((d["id"] for d in j.get("data", []) if d["attributes"]["identifier"] == ident), None)
    if not bid: die("bundle not found " + ident, j)
    name = f"RQ AppStore {ident}"
    s, j = call("GET", f"/v1/bundleIds/{bid}/profiles?limit=50")
    for p in j.get("data", []):
        call("DELETE", f"/v1/profiles/{p['id']}")
    s, j = call("POST", "/v1/profiles", {"data": {"type": "profiles",
        "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}},
                          "certificates": {"data": [{"type": "certificates", "id": cert_id}]}}}})
    if s >= 300: die("create profile", j)
    a = j["data"]["attributes"]
    open(outpath, "wb").write(base64.b64decode(a["profileContent"]))
    print(a["uuid"], name, sep="|")

if __name__ == "__main__":
    if sys.argv[1] == "make-cert": make_cert(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "make-profile": make_profile(sys.argv[2], sys.argv[3], sys.argv[4])
