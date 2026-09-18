export type MessagingChannel = 'whatsapp'|'instagram'|'tiktok';
export type ConversationState = 'ai_active'|'waiting_human'|'human_active'|'paused'|'closed';
export type MessageDirection = 'inbound'|'outbound';
export type MessageAuthor = 'contact'|'human'|'ai'|'system';

export type ProviderMessage = {
  externalId: string;
  conversationExternalId: string;
  from: string;
  to: string;
  text?: string;
  providerTimestamp: string;
  attachment?: {url:string;mimeType:string;filename?:string};
};

export type SendMessage = {
  connectionName: string;
  recipient: string;
  text: string;
  idempotencyKey: string;
};

export type ProviderAcceptance = {
  accepted: boolean;
  externalId?: string;
  rawStatus: string;
};

export interface MessagingProvider {
  readonly channel: MessagingChannel;
  health(): Promise<{ok:boolean;status:string}>;
  sendText(message:SendMessage): Promise<ProviderAcceptance>;
  normalizeWebhook(payload:unknown): ProviderMessage[];
}
export interface WhatsAppProvider extends MessagingProvider { readonly channel:'whatsapp' }
export interface ConversationRepository {
  appendInbound(message:ProviderMessage): Promise<{conversationId:string;messageId:string;created:boolean}>;
  markAccepted(messageId:string,externalId:string): Promise<void>;
}
export interface KnowledgeRepository {
  searchAuthorized(organizationId:string,unitId:string,query:string,limit:number):Promise<KnowledgeExcerpt[]>;
}
export type KnowledgeExcerpt={sourceId:string;versionId:string;content:string;validUntil?:string};
export interface EmbeddingProvider { embed(values:string[]):Promise<number[][]> }
export interface LLMProvider {
  complete(input:{system:string;messages:{role:'user'|'assistant';content:string}[];tools:string[]}):Promise<{
    text:string;inputTokens:number;outputTokens:number;model:string;toolCalls?:{name:string;arguments:unknown}[]
  }>;
}
export interface OutboxPort {
  claim(limit:number,workerId:string,leaseSeconds:number):Promise<OutboxJob[]>;
  complete(id:string,workerId:string):Promise<void>;
  retry(id:string,workerId:string,errorCode:string):Promise<void>;
}
export type OutboxJob={id:string;organizationId:string;unitId:string;eventType:string;entityId:string;payload:unknown;attempts:number;correlationId:string};
