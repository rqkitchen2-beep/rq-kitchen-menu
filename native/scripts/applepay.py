#!/usr/bin/env python3
"""Apple Pay setup for the customer app: merchant ID + Apple Pay capability on the
bundle ID, through the App Store Connect API. Prints what Apple answered."""
import json, sys
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from asc import call
MID = "merchant.com.rqkitchen.app"; BUNDLE = "com.rqkitchen.app"
def show(tag, s, j): print(tag, s, json.dumps(j)[:600])
s, j = call("GET", f"/v1/merchantIds?filter[identifier]={MID}&limit=5"); show("list-merchant", s, j)
mid = None
if s == 200:
    for d in j.get("data", []):
        if d["attributes"].get("identifier") == MID: mid = d["id"]
    if not mid:
        s, j = call("POST", "/v1/merchantIds", {"data": {"type": "merchantIds", "attributes": {"identifier": MID, "name": "RQ Kitchen"}}})
        show("create-merchant", s, j)
        if s < 300: mid = j["data"]["id"]
print("merchant_id:", mid or "NONE")
s, j = call("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE}&limit=5")
bid = next((d["id"] for d in j.get("data", []) if d["attributes"]["identifier"] == BUNDLE), None)
s, j = call("GET", f"/v1/bundleIds/{bid}/bundleIdCapabilities?limit=50")
caps = {c["attributes"]["capabilityType"]: c for c in j.get("data", [])}
print("caps:", list(caps))
if "APPLE_PAY" not in caps:
    body = {"data": {"type": "bundleIdCapabilities", "attributes": {"capabilityType": "APPLE_PAY"},
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}}
    if mid: body["data"]["relationships"]["merchantIds"] = {"data": [{"type": "merchantIds", "id": mid}]}
    s, j = call("POST", "/v1/bundleIdCapabilities", body); show("enable-applepay", s, j)
    if s >= 300 and mid:
        del body["data"]["relationships"]["merchantIds"]
        s, j = call("POST", "/v1/bundleIdCapabilities", body); show("enable-applepay-plain", s, j)
else:
    show("applepay-cap", 200, caps["APPLE_PAY"])
if mid:
    s, j = call("GET", f"/v1/merchantIds/{mid}/relationships/bundleIds"); show("merchant-bundles", s, j)
