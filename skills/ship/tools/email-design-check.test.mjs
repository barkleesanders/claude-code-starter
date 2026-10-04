import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { inspectContract } from './email-design-check.mjs';
test('missing contract is unmeasured, never a pass', () => {
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'email-gate-'));
 assert.equal(inspectContract(root).status,'unmeasured');
});
test('known-bad missing sender and test paths block the release', () => {
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'email-gate-'));
 const contract={version:1,brand:'Fixture',paper:'#faf8f2',ink:'#19324f',accent:'#19324f',senders:['missing.ts'],tests:['missing.test.ts'],command:['node','test.mjs']};
 fs.writeFileSync(path.join(root,'email-design.json'),JSON.stringify(contract));
 assert.equal(inspectContract(root).status,'bad');
 fs.writeFileSync(path.join(root,'missing.ts'),'fixture');fs.writeFileSync(path.join(root,'missing.test.ts'),'fixture');
 assert.equal(inspectContract(root).status,'ok');
});

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
test('CLI fails closed on failed, missing and empty test runners', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'email-gate-cli-'));
  fs.writeFileSync(path.join(root, 'sender.ts'), 'fixture');
  fs.writeFileSync(path.join(root, 'sender.test.ts'), 'fixture');
  const contract = { version: 1, brand: 'Fixture', paper: '#faf8f2', ink: '#19324f', accent: '#19324f', senders: ['sender.ts'], tests: ['sender.test.ts'] };
  const cli = fileURLToPath(new URL('./email-design-check.mjs', import.meta.url));
  for (const [command, expected] of [
    [[process.execPath, '-e', 'process.exit(1)'], 1],
    [['/missing/email-test-runner'], 2],
    [[process.execPath, '-e', 'console.log("0 tests")'], 2],
    [[process.execPath, '-e', 'console.log("Tests 2 passed")'], 0],
  ]) {
    fs.writeFileSync(path.join(root, 'email-design.json'), JSON.stringify({ ...contract, command }));
    assert.equal(spawnSync(process.execPath, [cli, root], { encoding: 'utf8' }).status, expected);
  }
});
