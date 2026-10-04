#!/usr/bin/env python3
"""Pre-deploy guard: does this wrangler config pin the public surface CLOSED?

Why (2026-09-24): `wrangler deploy` from a config that omits `workers_dev` /
`preview_urls` silently RE-ENABLES the worker's *.workers.dev address and its
*.cloudflare.app preview host. /ship Phase 4.09 closed them again AFTER each
deploy, but only for the repo being shipped — so a deploy from any other path
(a bare `wrangler deploy`, a Codex session, the mini) left an unprotected
duplicate of prod open. Measured: traks-api + traks-collect were closed via API
2026-09-01 and found open again 2026-09-24; the 2026-09-12 traks-collect deploy
also dropped three custom domains. The durable fix is declarative: the config
itself must say `workers_dev = false` and `preview_urls = false`.

Rules (checked on the effective config, i.e. top level merged with --env <x>):
  * preview_urls must be explicitly false.
  * a worker with routes / custom domains must set workers_dev explicitly.
      - workers_dev = false            -> ok
      - workers_dev = true             -> ok ONLY if the worker is on the opt-in
                                          list (shared/workers-dev-optin.txt),
                                          e.g. grok-voice-bridge, whose console
                                          and CLI live on workers.dev on purpose.
      - absent                         -> BLOCK (this is the silent re-enable).
  * a worker with no routes is workers.dev-canonical: workers_dev may be
    absent or true.

Usage: wrangler-surface-config-check.py <config> [--env NAME]
Exit: 0 ok · 2 block · 3 could not measure (never a pass; caller stays advisory)
"""
import json
import os
import re
import sys
import tomllib

OPTIN = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'shared', 'workers-dev-optin.txt')


def strip_jsonc(t):
    out, i, n = [], 0, len(t)
    in_str = False
    while i < n:
        c = t[i]
        if in_str:
            out.append(c)
            if c == '\\' and i + 1 < n:
                out.append(t[i + 1])
                i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            out.append(c)
        elif t.startswith('//', i):
            while i < n and t[i] != '\n':
                i += 1
            continue
        elif t.startswith('/*', i):
            end = t.find('*/', i + 2)
            i = n if end < 0 else end + 2
            continue
        else:
            out.append(c)
        i += 1
    return re.sub(r',(\s*[}\]])', r'\1', ''.join(out))


def load(path):
    with open(path, 'rb') as f:
        raw = f.read()
    if path.endswith('.toml'):
        return tomllib.loads(raw.decode())
    return json.loads(strip_jsonc(raw.decode()))


def optin_names():
    try:
        with open(OPTIN) as f:
            return {ln.split('#')[0].strip() for ln in f if ln.split('#')[0].strip()}
    except OSError:
        return set()


def resolve_from_command(cmd, cwd):
    """Find the config + env a `wrangler deploy` command will actually use.

    Mirrors wrangler: explicit -c/--config wins; else the vite-plugin redirect
    (.wrangler/deploy/config.json -> configPath); else walk UP from the working
    directory (a `cd X &&` prefix counts). Returns (path|None, env|None).
    """
    segs = re.split(r'&&|;|\|\|', cmd)
    d = cwd
    for seg in segs:
        m = re.match(r'\s*cd\s+("[^"]+"|\'[^\']+\'|\S+)', seg)
        if m:
            d = os.path.join(d, os.path.expanduser(m.group(1).strip('"\'')))
        if re.search(r'wrangler(\s+versions|\s+pages)?\s+deploy', seg):
            env = None
            me = re.search(r'(?:--env|-e)[= ](\S+)', seg)
            if me:
                env = me.group(1)
            mc = re.search(r'(?:--config|-c)[= ](\S+)', seg)
            if mc:
                return os.path.normpath(os.path.join(d, os.path.expanduser(mc.group(1).strip('"\'')))), env
            red = os.path.join(d, '.wrangler', 'deploy', 'config.json')
            if os.path.isfile(red):
                try:
                    cp = json.load(open(red))['configPath']
                    return os.path.normpath(os.path.join(os.path.dirname(red), cp)), env
                except Exception:  # noqa: BLE001
                    pass
            p = os.path.abspath(d)
            while True:
                for f in ('wrangler.jsonc', 'wrangler.json', 'wrangler.toml'):
                    if os.path.isfile(os.path.join(p, f)):
                        return os.path.join(p, f), env
                if p == os.path.dirname(p):
                    return None, env
                p = os.path.dirname(p)
    return None, None


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 3
    if args[0] == '--cmd':
        path, env = resolve_from_command(args[1], args[3] if len(args) > 3 and args[2] == '--cwd' else os.getcwd())
        if not path:
            print('wrangler-surface: no wrangler config resolved for this command — UNMEASURED')
            return 3
    else:
        path, env = args[0], None
    if '--env' in args:
        env = args[args.index('--env') + 1]
    try:
        cfg = load(path)
    except Exception as e:  # noqa: BLE001 — any parse failure is "unmeasured"
        print(f'wrangler-surface: could not parse {path}: {e} — UNMEASURED')
        return 3
    eff = dict(cfg)
    if env:
        eff.update((cfg.get('env') or {}).get(env) or {})
    name = eff.get('name') or cfg.get('name') or '?'
    has_routes = bool(eff.get('routes') or eff.get('route'))
    problems = []
    if eff.get('preview_urls') is not False:
        problems.append(f'preview_urls is {eff.get("preview_urls", "absent")!r} — must be false '
                        '(wrangler re-opens <name>.cloudflare.app otherwise)')
    wd = eff.get('workers_dev', None)
    if has_routes:
        if wd is None:
            problems.append('workers_dev is absent on a custom-domain worker — wrangler will '
                            're-enable <name>.<acct>.workers.dev (an unprotected duplicate of prod). '
                            'Set workers_dev = false')
        elif wd is True and name not in optin_names():
            problems.append('workers_dev = true on a custom-domain worker that is not on the opt-in list '
                            f'({os.path.normpath(OPTIN)}). Set false, or add the name there if '
                            'workers.dev is deliberately public')
    tag = f'{name}' + (f' (env {env})' if env else '')
    if problems:
        print(f'🛑 wrangler-surface: {tag} — {path}')
        for p in problems:
            print(f'   - {p}')
        return 2
    print(f'wrangler-surface: {tag} OK (workers_dev={wd}, preview_urls=false, routes={has_routes})')
    return 0


if __name__ == '__main__':
    sys.exit(main())
