import type { OutboxJob, OutboxPort } from '../../../packages/contracts/src/messaging.ts';
import { adminSupabase } from '../../api/src/supabase.ts';
import type { RuntimeConfig } from '../../api/src/config.ts';

export class SupabaseOutbox implements OutboxPort {
  private readonly client;
  constructor(config:RuntimeConfig){this.client=adminSupabase(config);}
  async claim(limit:number,workerId:string,leaseSeconds:number):Promise<OutboxJob[]> {
    const result=await this.client.rpc('claim_outbox',{p_worker_id:workerId,p_limit:limit,p_lease_seconds:leaseSeconds});
    if(result.error)throw new Error('outbox_claim_failed');
    return (result.data??[]).map((row:Record<string,unknown>)=>({id:String(row.id),organizationId:String(row.organization_id),unitId:String(row.unit_id),eventType:String(row.event_type),
      entityId:String(row.entity_id),payload:row.payload,attempts:Number(row.attempts),correlationId:String(row.correlation_id)})) as OutboxJob[];
  }
  async complete(id:string,workerId:string){const result=await this.client.rpc('complete_outbox',{p_id:id,p_worker_id:workerId});if(result.error||!result.data)throw new Error('outbox_complete_failed');}
  async retry(id:string,workerId:string,errorCode:string){const result=await this.client.rpc('retry_outbox',{p_id:id,p_worker_id:workerId,p_error_code:errorCode});if(result.error||!result.data)throw new Error('outbox_retry_failed');}
}
