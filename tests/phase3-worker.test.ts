import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { OutboxJob, OutboxPort } from '../packages/contracts/src/messaging.ts';
import { runOutboxBatch } from '../apps/worker/src/runner.ts';

class FakeOutbox implements OutboxPort {
  private available:OutboxJob[];private claimed=new Set<string>();
  completed:string[]=[];retried:{id:string;code:string}[]=[];
  constructor(jobs:OutboxJob[]){this.available=[...jobs];}
  async claim(limit:number){const rows=this.available.filter(job=>!this.claimed.has(job.id)).slice(0,limit);rows.forEach(job=>this.claimed.add(job.id));return rows;}
  async complete(id:string){this.completed.push(id);}
  async retry(id:string,_workerId:string,errorCode:string){this.retried.push({id,code:errorCode});}
}
const job=(id:string):OutboxJob=>({id,organizationId:'org-a',unitId:'unit-a',eventType:'message.send',entityId:id,payload:{},attempts:1,correlationId:'correlation-a'});

test('concurrent workers claim each job once and acknowledge only successful work',async()=>{
  const outbox=new FakeOutbox([job('one'),job('two'),job('three')]);const processed:string[]=[];
  await Promise.all([
    runOutboxBatch(outbox,async value=>{processed.push(value.id);},'worker-a',2),
    runOutboxBatch(outbox,async value=>{processed.push(value.id);},'worker-b',2)
  ]);
  assert.deepEqual(processed.sort(),['one','three','two']);assert.deepEqual(outbox.completed.sort(),['one','three','two']);assert.equal(new Set(processed).size,3);
});

test('failed jobs are retried with redacted stable codes and are not acknowledged',async()=>{
  const outbox=new FakeOutbox([job('fail')]);
  await runOutboxBatch(outbox,async()=>{throw new Error('provider_did_not_accept');},'worker-a');
  assert.deepEqual(outbox.completed,[]);assert.deepEqual(outbox.retried,[{id:'fail',code:'provider_did_not_accept'}]);
});
