#!/usr/bin/env python3
"""Build native/<app>/www: the bundled page + its images, plus the live-update loader."""
import json, os, sys, glob, shutil, time
app = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.abspath(os.path.join(here, '..', '..'))
adir = os.path.join(root, 'native', app)
cfg = json.load(open(os.path.join(adir, 'loader.json')))
www = os.path.join(adir, 'www')
shutil.rmtree(www, ignore_errors=True); os.makedirs(www)
if cfg.get('mode') == 'remote':
    # the app opens the live site directly (capacitor server.url); these pages only show
    # when the site can't be reached
    off = ('<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">'
           '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
           '<style>body{margin:0;height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;'
           'font-family:-apple-system,system-ui,sans-serif;background:%s;color:#222;text-align:center;padding:24px;box-sizing:border-box}'
           'button{margin-top:18px;font-size:18px;padding:14px 34px;border:0;border-radius:14px;background:#F28C28;color:#fff;font-weight:700}'
           'p{color:#666;margin:6px 0}</style></head><body><h2>لا يوجد اتصال بالإنترنت</h2><p>No internet connection</p>'
           '<p>تأكد من الإنترنت ثم اضغط إعادة المحاولة</p><button onclick="location.href=\'%s\'">إعادة المحاولة · Retry</button>'
           '</body></html>') % (cfg['bg'], cfg['remote'])
    open(os.path.join(www, 'offline.html'), 'w').write(off)
    open(os.path.join(www, 'index.html'), 'w').write(off.replace('<h2>', '<script>location.href=%r</script><h2>' % cfg['remote'], 1))
    print('www ready (remote):', cfg['remote']); sys.exit(0)
for pat in cfg['files']:
    for f in glob.glob(os.path.join(root, pat)):
        shutil.copy(f, www)
page = os.path.join(www, cfg['page'])
if not os.path.exists(page): sys.exit('missing page ' + cfg['page'])
html = open(os.path.join(root, 'native', 'loader', 'index.html')).read()
html = (html.replace('__PAGE__', cfg['page']).replace('__REMOTE__', cfg['remote'])
            .replace('__BUILD__', str(int(time.time() * 1000))).replace('__BG__', cfg['bg']))
open(os.path.join(www, 'index.html'), 'w').write(html)
print('www ready:', len(os.listdir(www)), 'files')
