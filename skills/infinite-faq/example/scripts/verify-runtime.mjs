import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { createTestHarness, unstable_readConfig } from 'wrangler';

const source = unstable_readConfig({ config: resolve('wrangler.toml'), env: '' });
const output = mkdtempSync(resolve(tmpdir(), 'faq-runtime-'));
const main = resolve(output, 'index.js');
// Exercise the emitted Worker with local assets and no remote AI binding.
// This checks HTTP/template compatibility, not real model output or browser UI.
let harness;
try {
  execFileSync(
    process.execPath,
    [
      'node_modules/wrangler/bin/wrangler.js',
      'deploy',
      '--dry-run',
      '--config',
      resolve('wrangler.toml'),
      '--env=',
      '--outdir',
      output,
    ],
    { stdio: 'inherit' },
  );
  harness = createTestHarness({
    workers: [
      {
        config: {
          name: source.name,
          main,
          no_bundle: true,
          compatibility_date: source.compatibility_date,
          compatibility_flags: source.compatibility_flags,
          assets: { directory: resolve('public'), binding: 'ASSETS' },
        },
      },
    ],
  });
  await harness.listen();
  const page = await harness.fetch('/');
  assert.equal(page.status, 200);
  assert.match(page.headers.get('content-security-policy'), /script-src 'self'/);
  const html = await page.text();
  assert.match(html, /Ask anything else/);
  assert.match(html, /faq-island\.js/);
  for (const path of ['/faq.css', '/faq-island.js']) {
    const response = await harness.fetch(path);
    assert.equal(response.status, 200);
    assert.ok((await response.text()).length > 100);
  }
  for (const [body, expected] of [
    ['{}', 400],
    ['{', 400],
    [JSON.stringify({ question: 'x'.repeat(9000) }), 413],
  ]) {
    const response = await harness.fetch('/api/faq/ask', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body,
    });
    assert.equal(response.status, expected);
    assert.ok((await response.json()).error);
  }
  console.log(
    JSON.stringify({
      runtime: 'workerd',
      assertions: 'page, assets, input bounds',
      bundleSha256: createHash('sha256').update(readFileSync(main)).digest('hex'),
      modelRequests: 0,
      result: 'pass',
    }),
  );
} finally {
  try {
    await harness?.close();
  } finally {
    rmSync(output, { recursive: true, force: true });
  }
}
