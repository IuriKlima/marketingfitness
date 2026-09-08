import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
test('web build refuses unapproved public environment variables',()=>{
 const result=spawnSync(process.execPath,[resolve('node_modules/vite/bin/vite.js'),'build'],{
  cwd:resolve('apps/web'),env:{...process.env,VITE_UNAPPROVED:'fictitious-value'},encoding:'utf8'
 });
 assert.notEqual(result.status,0);
 assert.match(result.stderr,/Unapproved browser variable: VITE_UNAPPROVED/);
});
