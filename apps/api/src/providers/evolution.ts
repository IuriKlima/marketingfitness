import type { ProviderAcceptance, ProviderMessage, SendMessage, WhatsAppProvider } from '../../../../packages/contracts/src/messaging.ts';

type Options={baseUrl:string;instance:string;apiKey:string};
export class EvolutionWhatsAppProvider implements WhatsAppProvider {
  readonly channel='whatsapp' as const;
  private readonly options:Options;
  constructor(options:Options) { this.options=options; }
  private async request(path:string,init:RequestInit={}) {
    const response=await fetch(this.options.baseUrl+path,{...init,redirect:'error',headers:{apikey:this.options.apiKey,'Content-Type':'application/json',...init.headers},signal:AbortSignal.timeout(15000)});
    const body=await response.json().catch(()=>({})) as Record<string,unknown>;
    if(!response.ok) throw new Error('evolution_http_'+response.status);
    return body;
  }
  async health() {
    try {const body=await this.request('/instance/connectionState/'+encodeURIComponent(this.options.instance));return {ok:true,status:String((body.instance as Record<string,unknown>|undefined)?.state??body.state??'available')};}
    catch(error){return {ok:false,status:error instanceof Error?error.message:'evolution_unavailable'};}
  }
  async sendText(message:SendMessage) : Promise<ProviderAcceptance> {
    const body=await this.request('/message/sendText/'+encodeURIComponent(this.options.instance),{
      method:'POST',body:JSON.stringify({number:message.recipient.replace(/^\+/,''),text:message.text,delay:0,linkPreview:false})
    });
    const key=body.key as Record<string,unknown>|undefined;
    const externalId=typeof key?.id==='string'?key.id:typeof body.id==='string'?body.id:undefined;
    return {accepted:Boolean(externalId),externalId,rawStatus:externalId?'accepted':'unconfirmed'};
  }
  async configureWebhook(url:string,secret:string) {
    await this.request('/webhook/set/'+encodeURIComponent(this.options.instance),{
      method:'POST',body:JSON.stringify({webhook:{enabled:true,url,webhookByEvents:false,
        headers:{'x-acadeai-webhook-secret':secret},events:['MESSAGES_UPSERT','MESSAGES_UPDATE','CONNECTION_UPDATE']}})
    });
  }
  normalizeWebhook(payload:unknown):ProviderMessage[] {
    if(!payload||typeof payload!=='object'||Array.isArray(payload)) return [];
    const root=payload as Record<string,unknown>; const event=String(root.event??'').toLowerCase();
    if(!event.includes('messages.upsert')&&!event.includes('messages_upsert')) return [];
    const records=Array.isArray(root.data)?root.data:[root.data];
    const messages:ProviderMessage[]=[];
    for(const recordValue of records) {
      if(!recordValue||typeof recordValue!=='object') continue;
      const record=recordValue as Record<string,unknown>; const key=(record.key??{}) as Record<string,unknown>;
      if(key.fromMe===true) continue;
      const externalId=String(key.id??''); const remote=String(key.remoteJid??'');
      const content=(record.message??{}) as Record<string,unknown>;
      const text=typeof content.conversation==='string'?content.conversation:
        typeof (content.extendedTextMessage as Record<string,unknown>|undefined)?.text==='string'?String((content.extendedTextMessage as Record<string,unknown>).text):undefined;
      if(!externalId||!remote||!text) continue;
      const digits=remote.split('@')[0].replace(/\D/g,''); if(digits.length<8) continue;
      const epoch=Number(record.messageTimestamp??Date.now()/1000);
      messages.push({externalId,conversationExternalId:remote,from:'+'+digits,to:'',text,providerTimestamp:new Date(epoch*1000).toISOString()});
    }
    return messages;
  }
  normalizeDeliveryEvents(payload:unknown) {
    if(!payload||typeof payload!=='object'||Array.isArray(payload))return [];
    const root=payload as Record<string,unknown>,event=String(root.event??'').toLowerCase();
    if(!event.includes('messages.update')&&!event.includes('messages_update'))return [];
    const values=Array.isArray(root.data)?root.data:[root.data];const result:{externalId:string;state:'accepted'|'sent'|'delivered'|'read'|'failed';providerAt:string;errorCode:string|null}[]=[];
    for(const value of values){if(!value||typeof value!=='object')continue;const row=value as Record<string,unknown>,key=(row.key??{}) as Record<string,unknown>;
      const externalId=String(key.id??row.id??'');const raw=String(row.status??row.update??'').toUpperCase();if(!externalId)continue;
      const state=raw.includes('ERROR')||raw.includes('FAIL')?'failed':raw.includes('READ')||raw.includes('PLAYED')?'read':raw.includes('DELIVERY')?'delivered':raw.includes('SERVER')?'sent':'accepted';
      const epoch=Number(row.messageTimestamp??Date.now()/1000);result.push({externalId,state,providerAt:new Date(epoch*1000).toISOString(),errorCode:state==='failed'?'provider_delivery_failed':null});
    }
    return result;
  }
}
