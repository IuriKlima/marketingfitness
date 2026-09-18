import type { OutboxJob } from '../../../packages/contracts/src/messaging.ts';
import type { RuntimeConfig } from '../../api/src/config.ts';
import { EvolutionWhatsAppProvider } from '../../api/src/providers/evolution.ts';
import { adminSupabase } from '../../api/src/supabase.ts';
import { assertSafeProviderUrl } from '../../api/src/network-security.ts';

export function jobProcessor(config:RuntimeConfig) {
  const admin=adminSupabase(config);
  return async (job:OutboxJob) => {
    if(job.eventType==='message.send') {
      const message=await admin.from('messages').select('id,body,channel_connection_id,conversation_id').eq('id',job.entityId).single();
      if(message.error||!message.data)throw new Error('message_not_found');
      const prior=await admin.from('message_delivery_events').select('id').eq('message_id',message.data.id).in('state',['accepted','sent','delivered','read']).limit(1).maybeSingle();
      if(prior.error)throw new Error('delivery_state_unavailable');if(prior.data)return;
      const conversation=await admin.from('conversations').select('contact_id').eq('id',message.data.conversation_id).single();
      if(conversation.error||!conversation.data)throw new Error('conversation_not_found');
      const phone=await admin.from('crm_contact_identifiers').select('normalized_value').eq('organization_id',job.organizationId)
        .eq('contact_id',conversation.data.contact_id).eq('kind','phone').limit(1).maybeSingle();
      if(phone.error||!phone.data)throw new Error('recipient_phone_missing');
      const runtime=await admin.rpc('channel_runtime_secret',{p_connection_id:message.data.channel_connection_id});
      if(runtime.error||!runtime.data)throw new Error('channel_secret_unavailable');
      const secret=runtime.data as Record<string,unknown>;const baseUrl=await assertSafeProviderUrl(String(secret.base_url),!config.production);
      const provider=new EvolutionWhatsAppProvider({baseUrl,instance:String(secret.external_instance),apiKey:String(secret.api_key)});
      const accepted=await provider.sendText({connectionName:String(secret.external_instance),recipient:phone.data.normalized_value,text:message.data.body,idempotencyKey:job.id});
      if(!accepted.accepted||!accepted.externalId)throw new Error('provider_did_not_accept');
      const delivery=await admin.rpc('record_delivery_event',{p_message_id:message.data.id,p_state:'accepted',p_provider_event_id:accepted.externalId,p_provider_at:new Date().toISOString(),p_error_code:null});
      if(delivery.error)throw new Error('delivery_event_failed');return;
    }
    if(job.eventType==='evolution.webhook') {
      if(!job.payload||typeof job.payload!=='object'||Array.isArray(job.payload))throw new Error('invalid_webhook_job');
      const envelope=job.payload as Record<string,unknown>;const connectionId=String(envelope.connectionId??'');
      const runtime=await admin.rpc('channel_runtime_secret',{p_connection_id:connectionId});if(runtime.error||!runtime.data)throw new Error('channel_secret_unavailable');
      const secret=runtime.data as Record<string,unknown>;const baseUrl=await assertSafeProviderUrl(String(secret.base_url),!config.production);
      const provider=new EvolutionWhatsAppProvider({baseUrl,instance:String(secret.external_instance),apiKey:String(secret.api_key)});
      const incoming=provider.normalizeWebhook(envelope.event);
      for(const message of incoming) {
        const result=await admin.rpc('ingest_inbound_message',{p_connection_id:connectionId,p_receipt_id:job.entityId,p_external_message_id:message.externalId,
          p_external_thread_id:message.conversationExternalId,p_sender_e164:message.from,p_sender_name:message.from,p_body:message.text??'[anexo]',
          p_provider_at:message.providerTimestamp,p_idempotency_key:'inbound:'+connectionId+':'+message.externalId});
        if(result.error)throw new Error('inbound_ingest_failed');
      }
      for(const event of provider.normalizeDeliveryEvents(envelope.event)) {
        const accepted=await admin.from('message_delivery_events').select('message_id').eq('provider_event_id',event.externalId).limit(1).maybeSingle();
        if(accepted.error)throw new Error('delivery_lookup_failed');if(!accepted.data)continue;
        const delivery=await admin.rpc('record_delivery_event',{p_message_id:accepted.data.message_id,p_state:event.state,p_provider_event_id:event.externalId+':'+event.state,
          p_provider_at:event.providerAt,p_error_code:event.errorCode});if(delivery.error)throw new Error('delivery_event_failed');
      }
      return;
    }
    throw new Error('unsupported_event_type');
  };
}
