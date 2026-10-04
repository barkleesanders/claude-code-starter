#!/usr/bin/env node
/** Release contract, not an inbox-delivery probe. No network calls or email sends. */
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
export function inspectContract(repo) {
  try {
    const contract = JSON.parse(fs.readFileSync(path.join(repo, 'email-design.json'), 'utf8'));
    const problems = [];
    if (contract.version !== 1) problems.push('Unsupported or missing contract version');
    for (const key of ['brand', 'paper', 'ink', 'accent']) {
      if (typeof contract[key] !== 'string' || !contract[key].trim()) problems.push(`Missing ${key}`);
    }
    if (!Array.isArray(contract.senders) || !contract.senders.length) problems.push('No sending seams inventoried');
    if (!Array.isArray(contract.tests) || !contract.tests.length) problems.push('No sender tests declared');
    for (const entry of [...(contract.senders || []), ...(contract.tests || [])]) {
      if (typeof entry !== 'string' || path.isAbsolute(entry) || entry.split('/').includes('..') || !fs.existsSync(path.join(repo, entry))) problems.push(`Missing or unsafe contract path: ${entry}`);
    }
    if (!Array.isArray(contract.command) || !contract.command.length || contract.command.some(x => typeof x !== 'string')) problems.push('Missing test command');
    return { status: problems.length ? 'bad' : 'ok', problems, contract };
  } catch (error) { return { status: 'unmeasured', problems: [error.message] }; }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const repo = path.resolve(process.argv[2] || '.');
  const result = inspectContract(repo);
  if (result.status !== 'ok') { console.error(JSON.stringify(result)); process.exit(result.status === 'bad' ? 1 : 2); }
  const [command, ...args] = result.contract.command;
  const run = spawnSync(command, args, {cwd: repo, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, timeout: 180000, shell: false});
  process.stdout.write(run.stdout || '');
  process.stderr.write(run.stderr || '');
  if (run.error || run.signal || run.status === null) { console.error('email_design=unmeasured: test runner did not complete'); process.exit(2); }
  if (run.status !== 0) { console.error('email_design=bad: sender contract tests failed'); process.exit(1); }
  const output = ((run.stdout || '') + (run.stderr || '')).replace(/\x1b\[[0-9;]*m/g, '');
  const count = output.match(/Tests\s+(\d+) passed/) || output.match(/test result: ok\. (\d+) passed/);
  if (!count || Number(count[1]) < 1) { console.error('email_design=unmeasured: no completed sender tests reported'); process.exit(2); }
  console.log(JSON.stringify({status:'ok', check:'email-design-contract', brand:result.contract.brand, senders:result.contract.senders, delivery:'not-tested', visual:'requires-rendered-review'}));
}
