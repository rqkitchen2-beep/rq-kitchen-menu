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
