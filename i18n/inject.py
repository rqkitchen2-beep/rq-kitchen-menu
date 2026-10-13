#!/usr/bin/env python3
"""Inline i18n/i18n.js (+ dict.json) into the app pages, between i18n markers in <head>."""
import json, re, sys, os
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
d = json.load(open(os.path.join(here, 'dict.json')))
js = open(os.path.join(here, 'i18n.js')).read().replace('__DICT__', json.dumps(d, ensure_ascii=False))
block = '<!--i18n:start--><script>' + js + '</script><!--i18n:end-->'
pages = sys.argv[1:] or ['app.html', 'driver.html', 'branch.html', '/home/claude/app/site/app.html']
for p in pages:
    p = p if os.path.isabs(p) else os.path.join(root, p)
    s = open(p).read()
    if '<!--i18n:start-->' in s:
        s = re.sub(r'<!--i18n:start-->.*?<!--i18n:end-->', lambda m: block, s, flags=re.S)
    else:
        m = re.search(r'<meta charset="?utf-8"?\s*/?>', s, re.I)
        i = m.end() if m else s.index('<head>') + 6
        s = s[:i] + block + s[i:]
    open(p, 'w').write(s)
    print('injected', p)
