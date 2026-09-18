import type { LLMProvider } from '../../../../packages/contracts/src/messaging.ts';

export class OpenAICompatibleProvider implements LLMProvider {
  private readonly options:{baseUrl:string;apiKey:string;model:string};
  constructor(options:{baseUrl:string;apiKey:string;model:string}){this.options=options;}
  async complete(input:{system:string;messages:{role:'user'|'assistant';content:string}[];tools:string[]}) {
    const response=await fetch(this.options.baseUrl+'/v1/chat/completions',{method:'POST',redirect:'error',signal:AbortSignal.timeout(30000),
      headers:{Authorization:'Bearer '+this.options.apiKey,'Content-Type':'application/json'},
      body:JSON.stringify({model:this.options.model,temperature:0.2,max_tokens:600,messages:[{role:'system',content:input.system},...input.messages]})});
    const payload=await response.json().catch(()=>({})) as Record<string,unknown>;
    if(!response.ok)throw new Error('llm_http_'+response.status);
    const choices=payload.choices as {message?:{content?:unknown}}[]|undefined;const usage=payload.usage as Record<string,unknown>|undefined;
    const text=choices?.[0]?.message?.content;if(typeof text!=='string'||!text.trim())throw new Error('llm_invalid_response');
    return {text:text.trim(),inputTokens:Number(usage?.prompt_tokens??0),outputTokens:Number(usage?.completion_tokens??0),model:this.options.model};
  }
}
