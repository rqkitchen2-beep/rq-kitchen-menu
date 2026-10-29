#!/usr/bin/env python3
"""Fill the App Store listing of the staff apps through the App Store Connect API:
category, subtitle, privacy URL, age rating, description, review notes, screenshots,
build, price (free) and availability (UAE).  Usage: store_meta.py <shots_dir> app [app...]"""
import os, sys, json, hashlib, time, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc import call, find_app

SHOTS = sys.argv[1]
ONLY = sys.argv[2:]
PRIVACY = "https://menu.rqkitchen.app/staff#privacy-en"
SUPPORT = "https://menu.rqkitchen.app/staff#support-en"
CONTACT = dict(contactFirstName="Ahmed", contactLastName="Deiab", contactPhone="+971504666123",
               contactEmail="rq.kitchen2@gmail.com")
UNLISTED = ("This is an internal app used only by the staff of RQ Kitchen, a restaurant in the UAE. "
            "We are requesting UNLISTED app distribution for it (employee resource).")

APPS = {
  "cashier": dict(
    bundle="com.rqkitchen.cashier",
    subtitle="RQ Kitchen point of sale",
    keywords="cashier,pos,restaurant,receipt,orders,RQ Kitchen,كاشير,نقاط البيع,مطعم",
    promo="The point-of-sale app for the RQ Kitchen team.",
    description=(
      "RQ Kitchen Cashier is the point-of-sale app used by the cashiers of RQ Kitchen restaurants in the UAE.\n\n"
      "• Fast order taking with the full RQ Kitchen menu and photos\n"
      "• Cash and card payments, or save an order and collect payment on pickup\n"
      "• Delivery-app orders with their own prices\n"
      "• Car plate or phone number on every order for drive-up pickup\n"
      "• Prints receipts and kitchen tickets on the branch's Epson network printer\n"
      "• All cashiers in a branch see the same live orders\n"
      "• Edit open orders; cancellations need the cashier's PIN\n"
      "• Day open/close with cash count, daily and monthly reports\n"
      "• Customers can scan a QR code on the receipt to be alerted when their order is ready\n"
      "• Arabic and English, light and dark mode\n\n"
      "This app is for RQ Kitchen staff only; accounts are created by the restaurant management.\n\n"
      "تطبيق الكاشير لموظفي مطاعم RQ Kitchen."),
    demo_name="Choose any branch, then enter this cashier PIN",
    notes=UNLISTED + "\n\nHow to sign in: tap any branch on the first screen, then type the PIN from the demo account "
          "password field and tap ✓. The demo cashier works in a separate demo branch, so test orders don't affect real sales. "
          "If asked to 'open the day', type any amount and tap the green button.\n\n"
          "Printing uses an Epson receipt printer on the restaurant's local network (port 9100), which is why the app asks for "
          "local network access. Without a printer you can still take orders and see receipts."),
  "attendance": dict(
    bundle="com.rqkitchen.attendance",
    subtitle="Staff clock-in for RQ Kitchen",
    keywords="attendance,time clock,clock in,staff,shifts,RQ Kitchen,حضور,انصراف,دوام",
    promo="Clock in and out at your RQ Kitchen branch.",
    description=(
      "RQ Kitchen Attendance is the time-clock app for the RQ Kitchen team in the UAE.\n\n"
      "• Clock in and out at your branch with one tap\n"
      "• Your location is checked only at the moment you clock in or out, to confirm you are at the branch\n"
      "• See your monthly report, working days, lateness and salary details\n"
      "• Excellence points for punctual staff\n"
      "• Request leave and receive notices from your manager\n"
      "• Managers see live attendance, schedules and payroll reports\n"
      "• Arabic and English, light and dark mode\n\n"
      "This app is for RQ Kitchen staff only; new accounts must be approved by the restaurant management.\n\n"
      "تطبيق الحضور والانصراف لموظفي RQ Kitchen."),
    demo_name="review@rqkitchen.app",
    notes=UNLISTED + "\n\nSign in with the demo email and PIN. Clocking in only works when the device is physically inside one of "
          "our branches in Abu Dhabi / Al Ain (GPS check at the moment of the tap), so outside the UAE the app will show that "
          "you are not at the branch - this is expected. You can still browse the employee screens such as 'My reports'.\n\n"
          "Account deletion: employee accounts are created and approved by the restaurant; an employee can ask for their "
          "account and data to be deleted at any time through the contact in the privacy policy (" + PRIVACY + ")."),
  "inventory": dict(
    bundle="com.rqkitchen.inventory",
    subtitle="Stock count for RQ Kitchen",
    keywords="inventory,stock count,stock,warehouse,restaurant,RQ Kitchen,جرد,مخزون,مستودع",
    promo="Stock counts and transfers for RQ Kitchen branches.",
    description=(
      "RQ Kitchen Inventory is the stock-count app used by RQ Kitchen branches and warehouse in the UAE.\n\n"
      "• Step-by-step stock count for each branch\n"
      "• Search items by name or SKU, with pack sizes and units\n"
      "• Material transfers from the warehouse to branches and between branches\n"
      "• Consumption calculated from sales and product recipes\n"
      "• Reports and Excel export for management\n\n"
      "This app is for RQ Kitchen staff only; access is given by the restaurant management.\n\n"
      "تطبيق الجرد لفروع RQ Kitchen."),
    demo_name="Enter this branch PIN on the keypad",
    notes=UNLISTED + "\n\nSign in by typing the PIN from the demo account password field on the keypad and tapping the button "
          "next to 0. The demo PIN opens a separate demo branch, so you can try the stock count freely."),
}

def ann(app, msg): print(f"::warning title=store {app}::{msg[:3000]}", flush=True)
def err(j): return json.dumps(j.get("errors", j))[:600]

def first(path):
    s, j = call("GET", path)
    d = j.get("data") if isinstance(j, dict) else None
    if isinstance(d, list): return d[0] if d else None
    return d

def upload_shot(app, set_id, path):
    data = open(path, "rb").read()
    s, j = call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots",
        "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})
    if s >= 300: ann(app, f"reserve shot {s} {err(j)}"); return
    sid = j["data"]["id"]
    for op in j["data"]["attributes"]["uploadOperations"]:
        part = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=part, method=op["method"],
                                     headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
        urllib.request.urlopen(req, timeout=120).read()
    s, j = call("PATCH", f"/v1/appScreenshots/{sid}", {"data": {"type": "appScreenshots", "id": sid,
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    if s >= 300: ann(app, f"commit shot {s} {err(j)}")

def do(app):
    c = APPS[app]
    a = find_app(c["bundle"])
    if not a: ann(app, "app record missing"); return
    aid = a["id"]; out = []

    s, j = call("PATCH", f"/v1/apps/{aid}", {"data": {"type": "apps", "id": aid,
        "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})
    out.append(f"rights {s}")

    s, j = call("GET", f"/v1/apps/{aid}/appInfos")
    info = j["data"][0]
    for d in j["data"]:
        if d["attributes"].get("appStoreState") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED") or d["attributes"].get("state") in ("PREPARE_FOR_SUBMISSION",):
            info = d
    iid = info["id"]
    s, j = call("PATCH", f"/v1/appInfos/{iid}", {"data": {"type": "appInfos", "id": iid, "relationships": {
        "primaryCategory": {"data": {"type": "appCategories", "id": "BUSINESS"}},
        "secondaryCategory": {"data": {"type": "appCategories", "id": "PRODUCTIVITY"}}}}})
    out.append(f"category {s}" + ("" if s < 300 else " " + err(j)))
    s, j = call("GET", f"/v1/appInfos/{iid}/appInfoLocalizations")
    for loc in j.get("data", []):
        s2, j2 = call("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", {"data": {"type": "appInfoLocalizations", "id": loc["id"],
            "attributes": {"subtitle": c["subtitle"], "privacyPolicyUrl": PRIVACY}}})
        out.append(f"info-loc {loc['attributes']['locale']} {s2}" + ("" if s2 < 300 else " " + err(j2)))
    s, j = call("GET", f"/v1/appInfos/{iid}/ageRatingDeclaration")
    if s < 300 and j.get("data"):
        ar = j["data"]; attrs = {}
        for k, v in ar["attributes"].items():
            if k in ("kidsAgeBand", "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride", "developerAgeRatingInfoUrl"): continue
            if isinstance(v, bool) or k.startswith("is") or k in ("gambling", "lootBox", "unrestrictedWebAccess", "advertising", "ageAssurance", "healthOrWellnessTopics", "messagingAndChat", "parentalControls", "userGeneratedContent"):
                attrs[k] = False
            else:
                attrs[k] = "NONE"
        s2, j2 = call("PATCH", f"/v1/ageRatingDeclarations/{ar['id']}", {"data": {"type": "ageRatingDeclarations", "id": ar["id"], "attributes": attrs}})
        out.append(f"age {s2}" + ("" if s2 < 300 else " " + err(j2)))

    s, j = call("GET", f"/v1/apps/{aid}/appStoreVersions?filter[platform]=IOS&limit=10")
    ver = None
    for d in j.get("data", []):
        if d["attributes"]["appStoreState"] in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"):
            ver = d
    if not ver: ann(app, "no editable version: " + err(j)); return
    vid = ver["id"]
    s, j = call("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {"type": "appStoreVersions", "id": vid,
        "attributes": {"copyright": "2026 RQ Kitchen", "releaseType": "MANUAL"}}})
    out.append(f"version {s}" + ("" if s < 300 else " " + err(j)))
    s, j = call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")
    locs = j.get("data", [])
    for loc in locs:
        s2, j2 = call("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
            "attributes": {"description": c["description"], "keywords": c["keywords"][:100], "supportUrl": SUPPORT,
                           "marketingUrl": "https://www.rqkitchen.ae", "promotionalText": c["promo"]}}})
        out.append(f"ver-loc {loc['attributes']['locale']} {s2}" + ("" if s2 < 300 else " " + err(j2)))

    rd = first(f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
    attrs = dict(CONTACT, demoAccountRequired=True, demoAccountName=c["demo_name"], notes=c["notes"][:3900])
    if rd:
        s, j = call("PATCH", f"/v1/appStoreReviewDetails/{rd['id']}", {"data": {"type": "appStoreReviewDetails", "id": rd["id"], "attributes": attrs}})
    else:
        s, j = call("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": attrs,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    out.append(f"review {s}" + ("" if s < 300 else " " + err(j)))

    # screenshots
    for dev, dtype in (("iphone", "APP_IPHONE_67"), ("ipad", "APP_IPAD_PRO_3GEN_129")):
        d = os.path.join(SHOTS, app, dev)
        files = sorted(f for f in (os.listdir(d) if os.path.isdir(d) else []) if f.endswith(".png") and not f.startswith("99"))
        if not files: out.append(f"shots {dev} none"); continue
        for loc in locs:
            s, j = call("GET", f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")
            sset = next((x for x in j.get("data", []) if x["attributes"]["screenshotDisplayType"] == dtype), None)
            if not sset:
                s, j = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": dtype},
                    "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})
                if s >= 300: out.append(f"set {dtype} {s} {err(j)}"); continue
                sset = j["data"]
            s, j = call("GET", f"/v1/appScreenshotSets/{sset['id']}/appScreenshots")
            for old in j.get("data", []): call("DELETE", f"/v1/appScreenshots/{old['id']}")
            for f in files: upload_shot(app, sset["id"], os.path.join(d, f))
            out.append(f"shots {dev} {len(files)}")

    # build
    b = None
    for _ in range(40):
        b = first(f"/v1/builds?filter[app]={aid}&filter[processingState]=VALID&sort=-uploadedDate&limit=1")
        if b: break
        time.sleep(30)
    if b:
        s, j = call("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": b["id"]}})
        out.append(f"build {b['attributes'].get('version')} {s}" + ("" if s < 300 else " " + err(j)))
    else:
        out.append("build: none processed yet")

    # price: free
    s, j = call("GET", f"/v1/apps/{aid}/appPricePoints?filter[territory]=USA&limit=200")
    pp = next((x for x in j.get("data", []) if float(x["attributes"].get("customerPrice") or 1) == 0), None)
    if pp:
        s, j = call("POST", "/v1/appPriceSchedules", {"data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": aid}}, "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
            "manualPrices": {"data": [{"type": "appPrices", "id": "${p0}"}]}}},
            "included": [{"type": "appPrices", "id": "${p0}", "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": pp["id"]}}}}]})
        out.append(f"price {s}" + ("" if s < 300 else " " + err(j)))
    else:
        out.append(f"price: free point not found {s}")

    # availability: United Arab Emirates
    s, j = call("POST", "/v2/appAvailabilities", {"data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": False},
        "relationships": {"app": {"data": {"type": "apps", "id": aid}},
                          "territoryAvailabilities": {"data": [{"type": "territoryAvailabilities", "id": "${t0}"}]}}},
        "included": [{"type": "territoryAvailabilities", "id": "${t0}", "attributes": {"available": True, "releaseDate": None, "preOrderEnabled": False},
                      "relationships": {"territory": {"data": {"type": "territories", "id": "ARE"}}}}]})
    out.append(f"availability {s}" + ("" if s < 300 else " " + err(j)))
    ann(app, " | ".join(out))

for app in ONLY:
    try: do(app)
    except Exception as e: ann(app, "EXC " + repr(e)[:500])
