#!/usr/bin/env python3
"""Query Wayback Machine availability API for every URL in archive/MANIFEST.json.

Finds existing snapshots created by anyone (us, IA bots, other archivers) and
patches the manifest with `wayback_url` (real timestamp form) and
`wayback_timestamp` fields.

Usage:
    cd /path/to/repo && python3 ~/.claude/skills/magazine/scripts/wb-availability.py
    # or
    REPO_ROOT=/path/to/repo python3 ~/.claude/skills/magazine/scripts/wb-availability.py
"""
import json
import os
import ssl
import subprocess
import sys
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor


def detect_repo_root():
    if os.environ.get('REPO_ROOT'):
        return os.environ['REPO_ROOT']
    try:
        return subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).strip()
    except Exception:
        sys.exit('Cannot detect repo root. Set REPO_ROOT or run inside a git repo.')


ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE


def avail(url):
    try:
        api = 'https://archive.org/wayback/available?url=' + urllib.parse.quote(url, safe=':/?=&')
        with urllib.request.urlopen(api, timeout=20, context=ctx) as r:
            d = json.load(r)
        snap = d.get('archived_snapshots', {}).get('closest', {})
        if snap.get('available') and snap.get('status') == '200':
            return (url, snap['url'], snap.get('timestamp', ''))
    except Exception as e:
        return (url, None, f'err:{type(e).__name__}')
    return (url, None, None)


def main():
    root = detect_repo_root()
    manifest_path = os.path.join(root, 'archive', 'MANIFEST.json')
    if not os.path.exists(manifest_path):
        sys.exit(f'No manifest at {manifest_path}')
    with open(manifest_path) as f:
        manifest = json.load(f)

    print(f'Querying {len(manifest)} URLs against Wayback availability (parallel=8)...')
    results = {}
    with ThreadPoolExecutor(max_workers=8) as ex:
        for i, (url, snap, ts) in enumerate(ex.map(avail, [m['url'] for m in manifest]), 1):
            results[url] = (snap, ts)
            if i % 20 == 0:
                print(f'  {i}/{len(manifest)}')

    got = 0
    for m in manifest:
        snap, ts = results.get(m['url'], (None, None))
        if snap and isinstance(ts, str) and ts and not ts.startswith('err'):
            m['wayback_url'] = snap
            m['wayback_timestamp'] = ts
            got += 1
        else:
            m['wayback_url'] = f'https://web.archive.org/web/*/{m["url"]}'
            m.pop('wayback_timestamp', None)

    with open(manifest_path, 'w') as f:
        json.dump(manifest, f, indent=2)

    print(f'Real snapshots: {got}/{len(manifest)} (rest get web/*/URL search redirector)')
    print('Now run regen-archive-index.py to rebuild INDEX.md from the updated manifest.')


if __name__ == '__main__':
    main()
