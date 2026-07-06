#!/usr/bin/env node

// graft-cookies.mjs — inject a domain's cookies into the running :9222 debug Chrome
// via CDP, WITHOUT closing or touching the user's real Chrome.
//
// This is the engine behind `chrome-debug-on.sh graft` / `chromectl graft`.
// It reads a cookie array (the JSON shape emitted by ~/tools/cookies-txt --format json)
// on stdin, maps each entry to CDP cookie params, and calls Storage.setCookies on the
// BROWSER-LEVEL CDP connection (no page/tab attach needed — cookies land in the profile's
// cookie store so every tab of that profile sees them).
//
// Requires Node 22+ (built-in WebSocket). Same WS approach as cdp.mjs (no deps).
//
// SECURITY: cookie VALUES are never printed. Only name/flags appear in any diagnostic,
// and stdout is a single success line with counts.
//
// Usage:
//   cookies-txt example.com --format json | node graft-cookies.mjs example.com
//   (optionally CHROME_DEBUG_PORT overrides 9222)

import { readFileSync } from 'fs';
import { homedir } from 'os';
import { resolve } from 'path';

const PORT = process.env.CHROME_DEBUG_PORT || '9222';
const TIMEOUT = 15000;

// ── browser-level WS endpoint discovery (mirrors cdp.mjs getWsUrl) ─────────────
async function getBrowserWsUrl() {
  try {
    const r = await fetch(`http://127.0.0.1:${PORT}/json/version`, {
      signal: AbortSignal.timeout(2000),
    });
    if (r.ok) {
      const j = await r.json();
      if (j && j.webSocketDebuggerUrl) return j.webSocketDebuggerUrl;
    }
  } catch {
    /* fall through */
  }
  // Fallback: cached DevToolsActivePort file written by chrome-debug-on.sh.
  const portFile = resolve(
    homedir(),
    'Library/Application Support/Google/Chrome/DevToolsActivePort',
  );
  const lines = readFileSync(portFile, 'utf8').trim().split('\n');
  return `ws://127.0.0.1:${lines[0]}${lines[1]}`;
}

// ── minimal CDP client over raw WebSocket (browser-level: no sessionId) ────────
class CDP {
  #ws;
  #id = 0;
  #pending = new Map();
  connect(wsUrl) {
    return new Promise((res, rej) => {
      this.#ws = new WebSocket(wsUrl);
      this.#ws.onopen = () => res();
      this.#ws.onerror = (e) => rej(new Error('WebSocket error: ' + (e.message || e.type)));
      this.#ws.onmessage = (ev) => {
        const msg = JSON.parse(ev.data);
        if (msg.id && this.#pending.has(msg.id)) {
          const { resolve, reject } = this.#pending.get(msg.id);
          this.#pending.delete(msg.id);
          if (msg.error) reject(new Error(msg.error.message));
          else resolve(msg.result);
        }
      };
    });
  }
  send(method, params = {}) {
    const id = ++this.#id;
    return new Promise((resolve, reject) => {
      this.#pending.set(id, { resolve, reject });
      this.#ws.send(JSON.stringify({ id, method, params }));
      setTimeout(() => {
        if (this.#pending.has(id)) {
          this.#pending.delete(id);
          reject(new Error(`Timeout: ${method}`));
        }
      }, TIMEOUT);
    });
  }
  close() {
    try {
      this.#ws.close();
    } catch {}
  }
}

// ── map cookies-txt JSON entry → CDP cookie param ──────────────────────────────
// cookies-txt JSON fields: domain, name, value, path, expirationDate, secure,
//   httpOnly, sameSite ('lax'|'strict'|'no_restriction'|'unspecified'), session.
function toCdpCookie(c) {
  const out = {
    name: c.name,
    value: c.value,
    domain: c.domain,
    path: c.path || '/',
    secure: !!c.secure,
    httpOnly: !!c.httpOnly,
  };
  // sameSite: CDP wants Strict|Lax|None; omit for unspecified so Chrome uses its default.
  const ss = (c.sameSite || '').toLowerCase();
  if (ss === 'strict') out.sameSite = 'Strict';
  else if (ss === 'lax') out.sameSite = 'Lax';
  else if (ss === 'no_restriction' || ss === 'none') out.sameSite = 'None';
  // expires: only for persistent cookies. Session cookies omit expires entirely.
  if (!c.session && typeof c.expirationDate === 'number' && c.expirationDate > 0) {
    out.expires = c.expirationDate; // CDP expects Unix seconds (float ok)
  }
  // CDP requires Secure when SameSite=None; Chrome rejects None+insecure.
  if (out.sameSite === 'None') out.secure = true;
  return out;
}

async function main() {
  const domain = process.argv[2] || '(unknown)';

  // Read the cookie JSON array from stdin.
  let raw = '';
  process.stdin.setEncoding('utf8');
  for await (const chunk of process.stdin) raw += chunk;
  raw = raw.trim();

  let cookies;
  try {
    cookies = JSON.parse(raw || '[]');
  } catch (e) {
    console.error(`graft: stdin was not valid JSON cookie array: ${e.message}`);
    process.exit(4);
  }
  if (!Array.isArray(cookies)) {
    console.error('graft: expected a JSON array of cookies on stdin');
    process.exit(4);
  }
  if (cookies.length === 0) {
    console.error(
      `graft: 0 cookies to inject for '${domain}' — nothing to graft (are you logged in there in real Chrome, on the right profile?)`,
    );
    process.exit(6);
  }

  const cdp = new CDP();
  try {
    await cdp.connect(await getBrowserWsUrl());
  } catch (e) {
    console.error(
      `graft: cannot reach debug Chrome on :${PORT} (${e.message}). Bring it up first.`,
    );
    process.exit(2);
  }

  // Prefer the bulk Storage.setCookies; fall back to per-cookie Network.setCookie
  // so one malformed cookie can't sink the whole graft (and so we get per-cookie
  // success accounting for the closed-loop proof).
  const cdpCookies = cookies.map(toCdpCookie);
  let ok = 0;
  const failed = [];

  let bulkOk = false;
  try {
    await cdp.send('Storage.setCookies', { cookies: cdpCookies });
    bulkOk = true;
    ok = cdpCookies.length;
  } catch (e) {
    // Bulk failed — fall through to per-cookie so we can report which ones stuck.
    process.stderr.write(
      `graft: Storage.setCookies bulk failed (${e.message}); retrying per-cookie…\n`,
    );
  }

  if (!bulkOk) {
    ok = 0;
    for (const cc of cdpCookies) {
      try {
        const r = await cdp.send('Network.setCookie', cc);
        if (r && r.success === false) failed.push(cc.name);
        else ok++;
      } catch {
        failed.push(cc.name);
      }
    }
  }

  cdp.close();

  // Single clean success line. Never print values.
  const via = bulkOk ? 'Storage.setCookies' : 'Network.setCookie';
  console.log(`grafted ${ok}/${cookies.length} cookies for ${domain} into :${PORT} (via ${via})`);
  if (failed.length) {
    process.stderr.write(
      `graft: ${failed.length} cookie(s) rejected by CDP: ${failed.join(', ')}\n`,
    );
  }
  process.exit(ok > 0 ? 0 : 5);
}

main().catch((e) => {
  console.error(`graft: ${e.message}`);
  process.exit(1);
});
