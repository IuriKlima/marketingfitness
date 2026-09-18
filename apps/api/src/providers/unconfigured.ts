import type { MessagingChannel, MessagingProvider, ProviderAcceptance, ProviderMessage, SendMessage } from '../../../../packages/contracts/src/messaging.ts';

export class UnconfiguredMessagingProvider implements MessagingProvider {
  readonly channel:MessagingChannel;
  constructor(channel:'instagram'|'tiktok'){this.channel=channel;}
  async health(){return {ok:false,status:'unconfigured'};}
  async sendText(message:SendMessage):Promise<ProviderAcceptance>{void message;return {accepted:false,rawStatus:'unconfigured'};}
  normalizeWebhook(payload:unknown):ProviderMessage[]{void payload;return [];}
}
