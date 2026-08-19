#!/usr/bin/env python3
"""Regenerate archive/INDEX.md from archive/MANIFEST.json.

Usage:
    REPO_ROOT=/path/to/repo \
    REPO_GH=https://github.com/<user>/<repo> \
    python3 regen-archive-index.py

Or detect from git when run inside a repo:
    cd /path/to/repo && python3 ~/.claude/skills/magazine/scripts/regen-archive-index.py

Bakes in lessons from doge-phantom-winery (April 2026 fix):
- Always use full GitHub blob URLs (no relative paths from inside archive/)
- Honest archive_status taxonomy (no Incapsula stubs marked '✅ full')
- Wayback URLs use real timestamps when available, web/*/URL otherwise (never web/2026*/)
"""
import json
import os
import re
import subprocess
import sys
import urllib.parse
from collections import Counter, defaultdict


def detect_repo_root():
    if os.environ.get('REPO_ROOT'):
        return os.environ['REPO_ROOT']
    try:
        out = subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).strip()
        return out
    except Exception:
        sys.exit('Cannot detect repo root. Set REPO_ROOT or run inside a git repo.')


def detect_github_url(root):
    if os.environ.get('REPO_GH'):
        return os.environ['REPO_GH'].rstrip('/')
    try:
        url = subprocess.check_output(
            ['git', '-C', root, 'config', '--get', 'remote.origin.url'], text=True
        ).strip()
        m = re.match(r'(?:https://github\.com/|git@github\.com:)([^/]+)/([^/.]+?)(?:\.git)?$', url)
        if m:
            return f'https://github.com/{m.group(1)}/{m.group(2)}'
    except Exception:
        pass
    sys.exit('Cannot detect GitHub URL. Set REPO_GH=https://github.com/<user>/<repo>.')


INCAPSULA_RE = re.compile(rb'_Incapsula_Resource|incapsula', re.I)
LOGIN_HOSTS = ('linkedin.com', 'facebook.com', 'instagram.com')
ASSET_HOSTS = ('fonts.googleapis.com', 'fonts.gstatic.com')


def classify(entry, root):
    p = entry.get('archive_path')
    if not p:
        host = urllib.parse.urlparse(entry['url']).netloc.lower().replace('www.', '')
        if any(h in host for h in LOGIN_HOSTS):
            return ('🔒 login-walled', 0)
        if any(h in host for h in ASSET_HOSTS):
            return ('🔧 asset CDN', 0)
        return ('❌ no archive', 0)

    full = os.path.join(root, p)
    if not os.path.exists(full):
        return ('❌ missing', 0)
    sz = os.path.getsize(full)

    if p.endswith('.md'):
        return ('📝 note only', sz)
    if p.endswith('.pdf'):
        with open(full, 'rb') as f:
            head = f.read(8)
        return ('✅ full PDF' if head.startswith(b'%PDF-') else '⚠️ corrupt PDF', sz)
    if p.endswith(('.html', '.htm')):
        with open(full, 'rb') as f:
            buf = f.read(2048)
        if INCAPSULA_RE.search(buf):
            return ('🤖 bot-blocked', sz)
        if sz < 800:
            return ('⚠️ thin', sz)
        return ('✅ full HTML', sz)
    if p.endswith('.json'):
        return ('✅ JSON', sz)
    if p.endswith('.png'):
        return ('✅ PNG', sz)
    return ('? unknown', sz)


def normalize_wayback(entry):
    """Reject the bad web/2026*/ wildcard form. Use timestamp if available, else web/*/."""
    url = entry['url']
    ts = entry.get('wayback_timestamp')
    if ts:
        return f'https://web.archive.org/web/{ts}/{url}'
    return f'https://web.archive.org/web/*/{url}'


def main():
    root = detect_repo_root()
    gh = detect_github_url(root)
    manifest_path = os.path.join(root, 'archive', 'MANIFEST.json')
    index_path = os.path.join(root, 'archive', 'INDEX.md')

    if not os.path.exists(manifest_path):
        sys.exit(f'No manifest at {manifest_path}')

    with open(manifest_path) as f:
        manifest = json.load(f)

    for m in manifest:
        status, sz = classify(m, root)
        m['archive_status'] = status
        m['size_bytes'] = sz
        m['github_url'] = f'{gh}/blob/main/{m["archive_path"]}' if m.get('archive_path') else None
        m['wayback_url'] = normalize_wayback(m)

    with open(manifest_path, 'w') as f:
        json.dump(manifest, f, indent=2)

    cat_groups = defaultdict(list)
    for m in manifest:
        cat_groups[m.get('category', 'misc')].append(m)

    status_counter = Counter(m['archive_status'] for m in manifest)
    total_bytes = sum(m['size_bytes'] for m in manifest)

    out = []
    out.append('# Archive Index — Source-by-Source Backup Status')
    out.append('')
    out.append('Each row maps an original URL to its GitHub-hosted archive copy and a Wayback Machine snapshot when available. The status column indicates how complete the local capture is.')
    out.append('')
    out.append(f'**Total sources tracked:** {len(manifest)}')
    out.append(f'**Total local bytes archived:** {total_bytes:,}')
    out.append('')
    out.append('### Status legend')
    out.append('')
    out.append('| Symbol | Meaning |')
    out.append('|---|---|')
    out.append('| ✅ full HTML / full PDF / JSON / PNG | Complete local archive — open the GitHub link to view |')
    out.append('| 📝 note only | Markdown summary because upstream blocked automated capture (Akamai, etc.). Reference, not a backup. |')
    out.append('| 🤖 bot-blocked | Captured response is the bot-detection page (Incapsula etc.), not real content |')
    out.append('| ⚠️ thin / corrupt | File exists but is suspiciously small or malformed |')
    out.append('| 🔒 login-walled | LinkedIn / similar — cannot be archived without authenticated capture |')
    out.append('| 🔧 asset CDN | Font / asset URL, not a primary source |')
    out.append('| ❌ missing / no archive | Listed but not fetched |')
    out.append('')
    out.append('### Status distribution')
    out.append('')
    out.append('| Status | Count |')
    out.append('|---|---|')
    for s, c in status_counter.most_common():
        out.append(f'| {s} | {c} |')
    out.append('')
    out.append('---')
    out.append('')

    for cat in sorted(cat_groups):
        items = sorted(cat_groups[cat], key=lambda x: x['url'])
        out.append(f'## {cat.upper()} ({len(items)} sources)')
        out.append('')
        out.append('| # | Source URL | Local archive (GitHub) | Wayback snapshot | Status |')
        out.append('|---|---|---|---|---|')
        for i, m in enumerate(items, 1):
            url = m['url']
            display = url if len(url) < 80 else url[:77] + '…'
            gh_cell = f'[{os.path.basename(m["archive_path"])}]({m["github_url"]})' if m.get('github_url') else '—'
            wb_cell = f'[snapshot]({m["wayback_url"]})' if m.get('wayback_timestamp') else f'[search]({m["wayback_url"]})'
            sz = m['size_bytes']
            size_str = f' ({sz:,}B)' if sz else ''
            out.append(f'| {i} | [{display}]({url}) | {gh_cell} | {wb_cell} | {m["archive_status"]}{size_str} |')
        out.append('')

    out.append('---')
    out.append('')
    out.append('## How to add a new source')
    out.append('')
    out.append('1. Save the page locally under `archive/<category>/<slugified-filename>.<ext>`')
    out.append('2. Append an entry to `archive/MANIFEST.json` with `url`, `category`, `archive_path`, `fetched_at`')
    out.append('3. Regenerate this file with the script that produced it')
    out.append('4. Submit the URL to https://web.archive.org/save/<url> for an independent third-party snapshot')
    out.append('')

    with open(index_path, 'w') as f:
        f.write('\n'.join(out) + '\n')

    print(f'Wrote {index_path}: {len(out)} lines, {len(manifest)} sources, {total_bytes:,} bytes total')
    print(f'Status distribution: {dict(status_counter)}')


if __name__ == '__main__':
    main()
