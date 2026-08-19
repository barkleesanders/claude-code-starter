#!/usr/bin/env python3
"""Submit every URL in archive/MANIFEST.json to Wayback Save Page Now.

Anonymous saves are heavily rate-limited (~30s per URL, ~70% HTTP 429 fail rate
on bulk submissions). For reliable bulk minting, set WB_S3_ACCESS and WB_S3_SECRET
env vars (free at https://archive.org/account/s3.php).

Usage:
    cd /path/to/repo && python3 ~/.claude/skills/magazine/scripts/wb-save.py
    # with auth (recommended for bulk):
    WB_S3_ACCESS=... WB_S3_SECRET=... python3 wb-save.py

After this completes, run wb-availability.py to materialize the new snapshot
URLs into MANIFEST.json, then regen-archive-index.py to rebuild INDEX.md.
"""
import json
import os
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed


def detect_repo_root():
    if os.environ.get('REPO_ROOT'):
        return os.environ['REPO_ROOT']
    try:
        return subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).strip()
    except Exception:
        sys.exit('Cannot detect repo root. Set REPO_ROOT or run inside a git repo.')


SKIP_HOSTS = ('fonts.googleapis.com', 'fonts.gstatic.com', 'linkedin.com')

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

UA = 'Mozilla/5.0 (compatible; archive-index-bot/1.0)'

ACCESS = os.environ.get('WB_S3_ACCESS')
SECRET = os.environ.get('WB_S3_SECRET')


def skippable(url):
    host = urllib.parse.urlparse(url).netloc.lower().replace('www.', '')
    return any(s in host for s in SKIP_HOSTS)


def save(url):
    if skippable(url):
        return (url, None, 'skipped')
    save_url = 'https://web.archive.org/save/' + url
    headers = {'User-Agent': UA}
    if ACCESS and SECRET:
        headers['Authorization'] = f'LOW {ACCESS}:{SECRET}'
    try:
        req = urllib.request.Request(save_url, headers=headers)
        with urllib.request.urlopen(req, timeout=60, context=ctx) as r:
            cl = r.headers.get('Content-Location', '')
            if cl and cl.startswith('/web/'):
                return (url, 'https://web.archive.org' + cl, 'saved')
            return (url, None, f'saved-no-cl ({r.status})')
    except urllib.error.HTTPError as e:
        return (url, None, f'http_{e.code}')
    except Exception as e:
        return (url, None, f'err: {type(e).__name__}')


def main():
    root = detect_repo_root()
    manifest_path = os.path.join(root, 'archive', 'MANIFEST.json')
    if not os.path.exists(manifest_path):
        sys.exit(f'No manifest at {manifest_path}')
    with open(manifest_path) as f:
        manifest = json.load(f)

    workers = 4 if not (ACCESS and SECRET) else 8
    auth_note = '(authenticated)' if (ACCESS and SECRET) else '(anonymous — many will hit 429)'
    print(f'Submitting {len(manifest)} URLs to Wayback Save Page Now {auth_note}, parallel={workers}...')

    results = {}
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futures = {ex.submit(save, m['url']): m['url'] for m in manifest}
        for i, fut in enumerate(as_completed(futures), 1):
            url, snap, status = fut.result()
            results[url] = (snap, status)
            if i % 10 == 0:
                print(f'  {i}/{len(manifest)}')
            time.sleep(0.2)

    out_path = os.path.join('/tmp', 'wb_save_results.json')
    with open(out_path, 'w') as f:
        json.dump({u: list(v) for u, v in results.items()}, f, indent=2)

    status_count = Counter(v[1] for v in results.values())
    saved = sum(1 for v in results.values() if v[0])
    print(f'\nResults: {dict(status_count)}')
    print(f'Got direct snapshot URL: {saved}/{len(results)}')
    print(f'Raw results: {out_path}')
    print('\nNext: run wb-availability.py to materialize fresh snapshots into MANIFEST.json,')
    print('then regen-archive-index.py to rebuild INDEX.md.')


if __name__ == '__main__':
    main()
