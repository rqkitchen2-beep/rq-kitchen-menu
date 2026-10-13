#!/usr/bin/env python3
"""Link the merchant ID to the customer app's Apple Pay capability and show the
entitlements a fresh profile gets."""
import json, sys, base64, re
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from asc import call
def show(tag, s, j): print(tag, s, json.dumps(j)[:700])
cap = "XDMXMQT8QU_APPLE_PAY"
for key in ["APPLE_PAY_MERCHANT_IDS", "MERCHANT_IDS", "APPLE_PAY_PAYMENT_PROCESSING"]:
    body = {"data": {"type": "bundleIdCapabilities", "id": cap, "attributes": {"capabilityType": "APPLE_PAY",
            "settings": [{"key": key, "options": [{"key": "merchant.com.rqkitchen.app", "enabled": True}]}]}}}
    s, j = call("PATCH", f"/v1/bundleIdCapabilities/{cap}", body); show("patch " + key, s, j)
    if s < 300: break
s, j = call("GET", f"/v1/bundleIdCapabilities/{cap}"); show("cap", s, j)
s, j = call("GET", "/v1/profiles?filter[name]=RQ%20AppStore%20com.rqkitchen.app&limit=5")
for p in j.get("data", []):
    raw = base64.b64decode(p["attributes"]["profileContent"]).decode("latin1")
    m = re.search(r"<key>Entitlements</key>\s*<dict>(.*?)</dict>", raw, re.S)
    print("profile", p["attributes"]["name"], p["attributes"]["profileState"], (m.group(1) if m else "?")[:1500])
