#!/usr/bin/env python3
"""App Store screenshots of the staff apps (live sites, demo accounts).
Writes <out>/<app>/<device>/NN.png  (iphone = 1290x2796, ipad = 2048x2732)."""
import os, sys, time
from playwright.sync_api import sync_playwright

OUT = sys.argv[1]
ONLY = sys.argv[2:] or ["cashier", "attendance", "inventory"]
CASHIER_PIN = os.environ.get("DEMO_CASHIER", "")
INV_PIN = os.environ.get("DEMO_INVENTORY", "")
ATT_EMAIL = os.environ.get("SHOT_ATT_EMAIL", "")
ATT_PIN = os.environ.get("DEMO_ATTENDANCE", "")
DEVICES = {
    "iphone": dict(viewport={"width": 430, "height": 932}, device_scale_factor=3, is_mobile=True, has_touch=True,
                   user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
    "ipad": dict(viewport={"width": 1024, "height": 1366}, device_scale_factor=2, is_mobile=True, has_touch=True,
                 user_agent="Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
}

def log(*a): print("SHOT:", *a, flush=True)

def save(page, app, dev, n):
    d = os.path.join(OUT, app, dev); os.makedirs(d, exist_ok=True)
    p = os.path.join(d, "%02d.png" % n); page.screenshot(path=p); log(app, dev, n, "ok")

def click_if(page, sel, t=1500):
    try:
        page.locator(sel).first.click(timeout=t); return True
    except Exception:
        return False

def cashier(page, dev):
    page.goto("https://cashier.rqkitchen.app/", wait_until="networkidle")
    page.wait_for_selector("[data-br]", timeout=30000); time.sleep(1)
    page.locator("[data-br]").first.click(); time.sleep(0.6)
    save(page, "cashier", dev, 1)
    for k in CASHIER_PIN: page.locator(f'[data-k="{k}"]').click()
    page.locator('[data-k="✓"]').click()
    page.wait_for_selector("#grid [data-i]", timeout=30000); time.sleep(2.5)
    if page.locator("#opGo").is_visible():
        page.fill("#opCash", "500"); page.click("#opGo"); time.sleep(2)
    ids = page.eval_on_selector_all("#grid [data-i]", "e=>e.map(x=>x.dataset.i)")
    for i in [ids[1], ids[3], ids[3], ids[min(9, len(ids) - 1)]]:
        page.locator(f'#grid [data-i="{i}"]').click(); time.sleep(0.2)
    click_if(page, "#mbar")
    page.fill("#pnum", "45678"); click_if(page, '#colors [data-col]'); time.sleep(0.8)
    click_if(page, "#closeCart")
    save(page, "cashier", dev, 2)
    click_if(page, "#mbar"); page.click("#payCash"); time.sleep(1)
    save(page, "cashier", dev, 3)
    click_if(page, "#modal [data-x]"); time.sleep(0.5)

def attendance(page, dev):
    page.goto("https://attendance.rqkitchen.app/", wait_until="networkidle")
    page.wait_for_selector("#loginBox:not(.hidden), #ticket:not(.hidden)", timeout=30000); time.sleep(1)
    click_if(page, "#salawatGo")
    hide = "var s=document.createElement('style');s.textContent='#installBar,#starsBox{display:none!important}';document.head.appendChild(s)"
    page.evaluate(hide)
    save(page, "attendance", dev, 1)
    page.fill("#lgEmail", ATT_EMAIL); page.fill("#lgPin", ATT_PIN); page.click("#lgBtn")
    time.sleep(4); click_if(page, "#salawatGo", 3000); time.sleep(1.5); page.evaluate(hide)
    save(page, "attendance", dev, 2)
    if click_if(page, '[data-tab="mine"]'):
        time.sleep(3); save(page, "attendance", dev, 3)

def inventory(page, dev):
    page.goto("https://inventory.rqkitchen.app/", wait_until="networkidle")
    page.wait_for_selector(".pad [data-d]", timeout=30000); time.sleep(1)
    save(page, "inventory", dev, 1)
    for k in INV_PIN: page.locator(f'.pad [data-d="{k}"]').click()
    page.locator(".pad [data-enter]").click(); time.sleep(5)
    save(page, "inventory", dev, 2)
    btns = page.locator("button.step, .steps button, nav button")
    if btns.count() > 1:
        try:
            btns.nth(1).click(timeout=2000); time.sleep(3); save(page, "inventory", dev, 3)
        except Exception as e:
            log("inventory step2", e)

with sync_playwright() as p:
    b = p.chromium.launch()
    for app in ONLY:
        for dev, opts in DEVICES.items():
            ctx = b.new_context(locale="ar-AE", timezone_id="Asia/Dubai", **opts)
            ctx.grant_permissions([])
            page = ctx.new_page()
            try:
                {"cashier": cashier, "attendance": attendance, "inventory": inventory}[app](page, dev)
            except Exception as e:
                log("ERROR", app, dev, repr(e)[:300])
                try: save(page, app, dev, 99)
                except Exception: pass
            ctx.close()
    b.close()
