import type { OutboxJob, OutboxPort } from '../../../packages/contracts/src/messaging.ts';

export async function runOutboxBatch(
  outbox:OutboxPort,
  processJob:(job:OutboxJob)=>Promise<void>,
  workerId:string,
  limit=10,
  leaseSeconds=60
) {
  const jobs=await outbox.claim(limit,workerId,leaseSeconds);
  const results=await Promise.allSettled(jobs.map(async job=>{
    try { await processJob(job);await outbox.complete(job.id,workerId);return {id:job.id,status:'completed' as const}; }
    catch(error) {
      const code=error instanceof Error&&/^[a-z0-9_]+$/.test(error.message)?error.message:'job_failed';
      await outbox.retry(job.id,workerId,code);return {id:job.id,status:'retried' as const,errorCode:code};
    }
  }));
  return {claimed:jobs.length,results};
}
