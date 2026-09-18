import './phase3.css';
import { api, jsonBody } from './api.ts';
import { escapeHtml, statusLabel } from '../../../packages/ui/src/primitives.ts';

type Json = Record<string, unknown>;
type Phase3Context = {
  shell:(title:string,content:string,active:string)=>void;
  navigate:(path:string)=>Promise<void>;
  message:(error:unknown)=>string;
  setDispose?:(dispose:()=>void)=>void;
};

const routeTitles:Record<string,string>={
  crm:'CRM',pipelines:'Pipeline comercial',agenda:'Agenda comercial',inbox:'Atendimento',channels:'Canais',
  assistant:'Assistente de IA',knowledge:'Base de conhecimento',queues:'Filas'
};

export function isPhase3Path(path:string) {
  return path==='/app/crm'||path==='/app/crm/pipelines'||path.startsWith('/app/crm/contatos/')||
    path==='/app/agenda'||path==='/app/atendimento'||path.startsWith('/app/atendimento/')||
    path==='/app/canais'||path==='/app/assistente-ia'||path==='/app/base-conhecimento'||path==='/app/filas';
}

export function phase3Navigation(active:string) {
  const links=[
    ['crm','/app/crm','CRM'],['pipelines','/app/crm/pipelines','Pipeline'],['agenda','/app/agenda','Agenda'],
    ['inbox','/app/atendimento','Atendimento'],['channels','/app/canais','Canais'],
    ['assistant','/app/assistente-ia','Assistente IA'],['knowledge','/app/base-conhecimento','Conhecimento'],['queues','/app/filas','Filas']
  ];
  return '<div class="nav-section-label">Operação</div>'+links.map(([key,href,label])=>
    '<a class="nav-link '+(active===key?'active':'')+'" href="'+href+'" data-link>'+label+'</a>'
  ).join('');
}

const records=(value:unknown):Json[]=>Array.isArray(value)?value.filter(item=>item!==null&&typeof item==='object') as Json[]:[];
const record=(value:unknown):Json=>value!==null&&typeof value==='object'&&!Array.isArray(value)?value as Json:{};
const text=(value:unknown,fallback='—')=>typeof value==='string'&&value.length?value:fallback;
const number=(value:unknown)=>typeof value==='number'?value:Number(value??0)||0;
const relation=(value:unknown)=>Array.isArray(value)?record(value[0]):record(value);
const formatDate=(value:unknown,withTime=true)=>{
  const date=new Date(String(value??''));
  return Number.isFinite(date.valueOf())?new Intl.DateTimeFormat('pt-BR',withTime?{dateStyle:'short',timeStyle:'short'}:{dateStyle:'short'}).format(date):'—';
};
const money=(value:unknown)=>new Intl.NumberFormat('pt-BR',{style:'currency',currency:'BRL'}).format(number(value)/100);
const badge=(value:unknown,kind='')=>'<span class="badge '+kind+'">'+escapeHtml(statusLabel(text(value,'Sem status')))+'</span>';
const skeleton=()=>'<div class="page-heading"><div class="skeleton line wide"></div></div><div class="grid grid-4">'+
  Array.from({length:4},()=>'<div class="card skeleton-block"></div>').join('')+'</div><div class="card skeleton-block tall"></div>';
const empty=(title:string,description:string)=>'<div class="empty-state"><div class="empty-symbol" aria-hidden="true"></div><h3>'+escapeHtml(title)+'</h3><p>'+escapeHtml(description)+'</p></div>';
const idempotency=()=>crypto.randomUUID();

function loading(ctx:Phase3Context,title:string,active:string){ctx.shell(title,skeleton(),active);}
function fail(ctx:Phase3Context,title:string,active:string,error:unknown,retry:string){
  ctx.shell(title,'<div class="error-state" role="alert"><h2>Não foi possível carregar</h2><p>'+escapeHtml(ctx.message(error))+'</p><a class="btn btn-secondary" href="'+retry+'" data-link>Tentar novamente</a></div>',active);
}
function announce(value:string,tone:'success'|'error'='success'){
  document.querySelector('#phase3-toast')?.remove();
  const output=document.createElement('div');output.id='phase3-toast';output.className='toast '+tone;output.role='status';output.textContent=value;
  document.body.append(output);window.setTimeout(()=>output.remove(),3500);
}
function field(form:FormData,key:string){return String(form.get(key)??'').trim();}

async function crmPage(ctx:Phase3Context){
  loading(ctx,routeTitles.crm,'crm');
  try {
    const params=new URLSearchParams(location.search);const query=params.get('q')??'';
    const [dashboard,contacts]=await Promise.all([
      api<Json>('/crm/dashboard'),api<Json>('/crm/contacts?limit=12&q='+encodeURIComponent(query))
    ]);
    const summary=record(dashboard.summary),tasks=records(dashboard.tasks),visits=records(dashboard.appointments),leads=records(dashboard.recentLeads),contactRows=records(contacts.items);
    const metrics=[['Oportunidades abertas',summary.open_opportunities],['Ganhos no mês',summary.won_this_month],['Tarefas próximas',summary.tasks_due],['Próximas visitas',summary.next_visits]];
    ctx.shell(routeTitles.crm,
      '<div class="page-heading"><div><p class="eyebrow">Operação comercial</p><h2>Visão geral do CRM</h2><p class="muted">Funil, contatos e compromissos da unidade atual.</p></div><a class="btn btn-primary" href="/app/crm/pipelines" data-link>Abrir pipeline</a></div>'+
      '<section class="grid grid-4" aria-label="Indicadores">'+metrics.map(([label,value])=>'<article class="card metric"><span>'+escapeHtml(label)+'</span><strong>'+number(value)+'</strong></article>').join('')+'</section>'+
      '<section class="grid grid-2 phase-section"><article class="solid-panel"><div class="section-title"><h3>Leads recentes</h3><a href="/app/crm/pipelines" data-link>Ver pipeline</a></div>'+
      (leads.length?'<div class="compact-list">'+leads.map(lead=>{const contact=relation(lead.crm_contacts);return '<a class="list-row" href="/app/crm/contatos/'+encodeURIComponent(text(contact.id,''))+'" data-link><span><strong>'+escapeHtml(text(contact.display_name,text(lead.title)))+'</strong><small>'+escapeHtml(text(relation(lead.crm_pipeline_stages).name,'Sem etapa'))+'</small></span>'+badge(lead.status)+'</a>';}).join('')+'</div>':empty('Nenhum lead','Crie um contato e uma oportunidade para iniciar o funil.'))+'</article>'+
      '<article class="solid-panel"><div class="section-title"><h3>Tarefas abertas</h3><span>'+tasks.length+' itens</span></div>'+(tasks.length?'<div class="compact-list">'+tasks.map(task=>'<div class="list-row"><span><strong>'+escapeHtml(text(task.title))+'</strong><small>'+escapeHtml(formatDate(task.due_at))+'</small></span>'+badge(task.priority)+'</div>').join('')+'</div>':empty('Tudo em dia','Não há tarefas abertas para esta unidade.'))+'</article></section>'+
      '<section class="solid-panel phase-section"><div class="section-title"><h3>Próximas visitas e aulas</h3><a href="/app/agenda" data-link>Ver agenda</a></div>'+(visits.length?'<div class="responsive-table"><table><thead><tr><th>Contato</th><th>Tipo</th><th>Horário</th><th>Status</th></tr></thead><tbody>'+visits.map(visit=>'<tr><td>'+escapeHtml(text(relation(visit.crm_contacts).display_name))+'</td><td>'+escapeHtml(text(visit.kind))+'</td><td>'+escapeHtml(formatDate(visit.starts_at))+'</td><td>'+badge(visit.status)+'</td></tr>').join('')+'</tbody></table></div>':empty('Agenda livre','Nenhuma visita futura foi encontrada.'))+'</section>'+
      '<section class="solid-panel phase-section"><div class="section-title"><h3>Contatos</h3><span>'+contactRows.length+' nesta página</span></div><form id="contact-search" class="filter-bar" role="search"><label class="sr-only" for="contact-query">Buscar contato</label><input id="contact-query" name="q" value="'+escapeHtml(query)+'" placeholder="Buscar por nome"><button class="btn btn-secondary" type="submit">Buscar</button></form>'+
      (contactRows.length?'<div class="responsive-table"><table><thead><tr><th>Nome</th><th>Cidade</th><th>Origem</th><th>Cadastro</th></tr></thead><tbody>'+contactRows.map(contact=>'<tr><td><a href="/app/crm/contatos/'+encodeURIComponent(text(contact.id,''))+'" data-link><strong>'+escapeHtml(text(contact.display_name))+'</strong></a></td><td>'+escapeHtml(text(contact.city))+'</td><td>'+escapeHtml(text(contact.source))+'</td><td>'+escapeHtml(formatDate(contact.created_at,false))+'</td></tr>').join('')+'</tbody></table></div>':empty('Nenhum contato encontrado','Ajuste a busca ou aguarde a entrada de novos leads.'))+'</section>','crm');
    document.querySelector<HTMLFormElement>('#contact-search')?.addEventListener('submit',event=>{event.preventDefault();const q=field(new FormData(event.currentTarget as HTMLFormElement),'q');void ctx.navigate('/app/crm'+(q?'?q='+encodeURIComponent(q):''));});
  } catch(error){fail(ctx,routeTitles.crm,'crm',error,'/app/crm');}
}

async function pipelinePage(ctx:Phase3Context){
  loading(ctx,routeTitles.pipelines,'pipelines');
  try {
    const data=await api<Json>('/crm/pipelines');const pipelines=records(data.pipelines),opportunities=records(data.opportunities),pipeline=pipelines[0]??{};
    const stages=records(pipeline.crm_pipeline_stages).sort((a,b)=>number(a.position)-number(b.position));
    ctx.shell(routeTitles.pipelines,'<div class="page-heading"><div><p class="eyebrow">Funil de vendas</p><h2>'+escapeHtml(text(pipeline.name,'Pipeline comercial'))+'</h2><p class="muted">Use os botões de mover com mouse ou teclado. A alteração volta ao estado anterior se a API recusar.</p></div><div class="view-toggle" role="group" aria-label="Visualização"><button class="btn btn-secondary active" id="show-board" type="button">Kanban</button><button class="btn btn-secondary" id="show-table" type="button">Tabela</button></div></div>'+
      (stages.length?'<div id="pipeline-board" class="kanban" tabindex="0">'+stages.map((stage,index)=>'<section class="kanban-column" data-stage="'+escapeHtml(stage.id)+'"><header><h3>'+escapeHtml(text(stage.name))+'</h3><span>'+opportunities.filter(item=>item.stage_id===stage.id).length+'</span></header><div class="kanban-items">'+opportunities.filter(item=>item.stage_id===stage.id).map(item=>opportunityCard(item,stages,index)).join('')+'</div></section>').join('')+'</div>':empty('Pipeline ainda não configurado','Cadastre etapas para começar a organizar oportunidades.'))+
      '<div id="pipeline-table" class="responsive-table" hidden><table><thead><tr><th>Oportunidade</th><th>Contato</th><th>Etapa</th><th>Valor</th><th>Atualização</th></tr></thead><tbody>'+opportunities.map(item=>'<tr><td>'+escapeHtml(text(item.title))+'</td><td>'+escapeHtml(text(relation(item.crm_contacts).display_name))+'</td><td>'+escapeHtml(text(relation(item.crm_pipeline_stages).name))+'</td><td>'+money(item.value_cents)+'</td><td>'+formatDate(item.updated_at)+'</td></tr>').join('')+'</tbody></table></div>','pipelines');
    const board=document.querySelector<HTMLElement>('#pipeline-board'),table=document.querySelector<HTMLElement>('#pipeline-table');
    document.querySelector('#show-board')?.addEventListener('click',()=>{if(board&&table){board.hidden=false;table.hidden=true;}});
    document.querySelector('#show-table')?.addEventListener('click',()=>{if(board&&table){board.hidden=true;table.hidden=false;}});
    document.querySelectorAll<HTMLButtonElement>('[data-move-opportunity]').forEach(button=>button.addEventListener('click',async()=>{
      const card=button.closest<HTMLElement>('[data-opportunity]');const target=document.querySelector<HTMLElement>('[data-stage="'+CSS.escape(button.dataset.targetStage??'')+'"] .kanban-items');
      const original=card?.parentElement;if(!card||!target||!original)return;target.prepend(card);card.setAttribute('aria-busy','true');
      try{await api('/crm/opportunities/move',{method:'POST',headers:{'Idempotency-Key':idempotency()},body:jsonBody({opportunityId:button.dataset.moveOpportunity,expectedStageId:button.dataset.currentStage,toStageId:button.dataset.targetStage,reason:'Movido no Kanban'})});announce('Oportunidade movida.');await pipelinePage(ctx);}
      catch(error){original.append(card);card.removeAttribute('aria-busy');announce(ctx.message(error),'error');}
    }));
  } catch(error){fail(ctx,routeTitles.pipelines,'pipelines',error,'/app/crm/pipelines');}
}

function opportunityCard(item:Json,stages:Json[],stageIndex:number){
  const contact=relation(item.crm_contacts);const previous=stages[stageIndex-1],next=stages[stageIndex+1];
  const move=(target:Json|undefined,label:string)=>target?'<button class="icon-button" type="button" data-move-opportunity="'+escapeHtml(item.id)+'" data-current-stage="'+escapeHtml(item.stage_id)+'" data-target-stage="'+escapeHtml(target.id)+'" aria-label="'+label+'">'+(label.includes('anterior')?'←':'→')+'</button>':'';
  return '<article class="opportunity-card" data-opportunity="'+escapeHtml(item.id)+'"><div><strong>'+escapeHtml(text(item.title))+'</strong><small>'+escapeHtml(text(contact.display_name))+'</small></div><div class="card-footer"><span>'+money(item.value_cents)+'</span><div>'+move(previous,'Mover para etapa anterior')+move(next,'Mover para próxima etapa')+'</div></div></article>';
}

async function contactPage(ctx:Phase3Context,id:string){
  loading(ctx,'Contato','crm');
  try{
    const data=await api<Json>('/crm/contacts/detail?id='+encodeURIComponent(id));const contact=record(data.contact),identifiers=records(contact.crm_contact_identifiers),consents=records(contact.crm_consents);
    const opportunities=records(data.opportunities),tasks=records(data.tasks),appointments=records(data.appointments),activities=records(data.activities),notes=records(data.notes);
    ctx.shell(text(contact.display_name,'Contato'),'<div class="page-heading"><div><a class="back-link" href="/app/crm" data-link>← Voltar ao CRM</a><h2>'+escapeHtml(text(contact.display_name))+'</h2><p class="muted">'+escapeHtml(text(contact.city,'Cidade não informada'))+' · '+escapeHtml(text(contact.source,'Origem não informada'))+'</p></div>'+badge(contact.anonymized_at?'anonymized':'active')+'</div>'+
      '<div class="contact-layout"><aside class="solid-panel"><h3>Dados e consentimentos</h3><dl class="detail-list">'+identifiers.map(item=>'<dt>'+escapeHtml(text(item.kind))+'</dt><dd>'+escapeHtml(text(item.normalized_value))+'</dd>').join('')+'</dl><h3>Consentimentos</h3>'+(consents.length?consents.map(item=>'<p>'+badge(item.revoked_at?'revogado':'ativo',item.revoked_at?'warning':'success')+' '+escapeHtml(text(item.channel))+' · '+escapeHtml(text(item.purpose))+'</p>').join(''):empty('Sem consentimento registrado','Automações permanecem bloqueadas até existir uma base válida.'))+'</aside><main class="contact-timeline">'+
      contactSection('Oportunidades',opportunities,item=>'<strong>'+escapeHtml(text(item.title))+'</strong><span>'+escapeHtml(text(relation(item.crm_pipeline_stages).name))+'</span>'+badge(item.status))+
      contactSection('Próximos compromissos',appointments,item=>'<strong>'+escapeHtml(text(item.kind))+'</strong><span>'+escapeHtml(formatDate(item.starts_at))+'</span>'+badge(item.status))+
      contactSection('Tarefas',tasks,item=>'<strong>'+escapeHtml(text(item.title))+'</strong><span>'+escapeHtml(formatDate(item.due_at))+'</span>'+badge(item.priority))+
      contactSection('Linha do tempo',[...activities,...notes].sort((a,b)=>text(b.occurred_at,text(b.created_at,'')).localeCompare(text(a.occurred_at,text(a.created_at,'')))),item=>'<strong>'+escapeHtml(text(item.summary,'Anotação'))+'</strong><p>'+escapeHtml(text(item.body,''))+'</p><small>'+escapeHtml(formatDate(item.occurred_at??item.created_at))+'</small>')+'</main></div>','crm');
  }catch(error){fail(ctx,'Contato','crm',error,'/app/crm');}
}
function contactSection(title:string,items:Json[],render:(item:Json)=>string){return '<section class="solid-panel"><div class="section-title"><h3>'+escapeHtml(title)+'</h3><span>'+items.length+'</span></div>'+(items.length?'<div class="timeline">'+items.map(item=>'<article>'+render(item)+'</article>').join('')+'</div>':empty('Sem registros','Ainda não existem itens nesta seção.'))+'</section>';}

async function agendaPage(ctx:Phase3Context){
  loading(ctx,routeTitles.agenda,'agenda');
  try{const data=await api<Json>('/crm/appointments?limit=50');const items=records(data.items);const groups=new Map<string,Json[]>();for(const item of items){const key=new Date(String(item.starts_at)).toISOString().slice(0,10);groups.set(key,[...(groups.get(key)??[]),item]);}
    ctx.shell(routeTitles.agenda,'<div class="page-heading"><div><p class="eyebrow">Visitas e aulas experimentais</p><h2>Agenda comercial</h2><p class="muted">Resultados são registrados junto à oportunidade em uma única transação.</p></div></div><div class="agenda-grid"><aside class="solid-panel agenda-calendar"><h3>Próximas datas</h3>'+([...groups.entries()].map(([day,rows])=>'<a href="#day-'+day+'"><strong>'+formatDate(day,false)+'</strong><span>'+rows.length+' compromisso(s)</span></a>').join('')||empty('Agenda livre','Nenhum compromisso futuro.'))+'</aside><main class="agenda-list">'+([...groups.entries()].map(([day,rows])=>'<section class="solid-panel" id="day-'+day+'"><h3>'+formatDate(day,false)+'</h3>'+rows.map(item=>'<article class="appointment-row"><time>'+escapeHtml(new Intl.DateTimeFormat('pt-BR',{timeStyle:'short'}).format(new Date(String(item.starts_at))))+'</time><span><strong>'+escapeHtml(text(relation(item.crm_contacts).display_name))+'</strong><small>'+escapeHtml(text(item.kind))+'</small></span>'+badge(item.status)+'</article>').join('')+'</section>').join('')||'')+'</main></div>','agenda');
  }catch(error){fail(ctx,routeTitles.agenda,'agenda',error,'/app/agenda');}
}

async function inboxPage(ctx:Phase3Context,conversationId?:string){
  loading(ctx,routeTitles.inbox,'inbox');
  try{const list=await api<Json>('/inbox/conversations?limit=30');const conversations=records(list.items);let detail:Json|null=null;if(conversationId)detail=await api<Json>('/inbox/conversation?id='+encodeURIComponent(conversationId));
    const current=record(detail?.conversation),messages=records(detail?.messages);
    ctx.shell(routeTitles.inbox,'<div class="inbox-shell '+(conversationId?'has-detail':'')+'"><aside class="conversation-list solid-panel"><div class="section-title"><h2>Conversas</h2><span>'+conversations.length+'</span></div><div class="filter-bar"><input aria-label="Buscar conversa" placeholder="Buscar conversa"><select aria-label="Filtrar status"><option>Todos os estados</option><option>Esperando humano</option><option>Com humano</option></select></div>'+
      (conversations.length?conversations.map(item=>{const contact=relation(item.crm_contacts);return '<a class="conversation-row '+(item.id===conversationId?'active':'')+'" href="/app/atendimento/'+encodeURIComponent(text(item.id,''))+'" data-link><span class="avatar">'+escapeHtml(text(contact.display_name,'?').slice(0,1).toUpperCase())+'</span><span><strong>'+escapeHtml(text(contact.display_name,'Contato'))+'</strong><small>'+escapeHtml(text(item.subject,text(relation(item.channel_connections).name)))+'</small></span><span><time>'+escapeHtml(formatDate(item.last_message_at))+'</time>'+(number(item.unread_count)?'<b>'+number(item.unread_count)+'</b>':'')+'</span></a>';}).join(''):empty('Caixa vazia','Novas conversas aparecerão aqui quando o canal receber mensagens.'))+'</aside>'+
      (conversationId?'<main class="conversation-detail solid-panel"><header class="conversation-header"><a class="back-link mobile-only" href="/app/atendimento" data-link>← Conversas</a><div><h2>'+escapeHtml(text(relation(current.crm_contacts).display_name,'Contato'))+'</h2><p>'+badge(current.state)+'</p></div><div><button id="takeover" class="btn btn-secondary" type="button">Assumir</button> <button id="return-ai" class="btn btn-quiet" type="button">Devolver à IA</button></div></header><div class="message-history" aria-live="polite">'+(messages.length?messages.map(message=>'<article class="message '+(message.direction==='outbound'?'outbound':'inbound')+'"><p>'+escapeHtml(text(message.body))+'</p><footer>'+escapeHtml(text(message.author_kind))+' · '+escapeHtml(formatDate(message.provider_at??message.created_at))+' '+badge(message.delivery_state)+'</footer></article>').join(''):empty('Sem mensagens','A conversa ainda não possui conteúdo.'))+'</div><form id="composer" class="composer"><label class="sr-only" for="message-body">Mensagem</label><textarea id="message-body" name="body" maxlength="20000" placeholder="Escreva uma mensagem" required></textarea><button class="btn btn-primary" type="submit">Enviar</button></form></main><aside class="lead-context solid-panel"><h3>Contexto do lead</h3><dl class="detail-list"><dt>Estado</dt><dd>'+escapeHtml(text(current.state))+'</dd><dt>Prioridade</dt><dd>'+escapeHtml(text(current.priority))+'</dd><dt>Fila</dt><dd>'+escapeHtml(text(relation(current.conversation_queues).name))+'</dd><dt>Responsável</dt><dd>'+escapeHtml(text(current.assigned_to,'Não atribuído'))+'</dd></dl></aside>':'<main class="inbox-placeholder">'+empty('Selecione uma conversa','Abra um atendimento para visualizar o histórico e responder.')+'</main>')+'</div>','inbox');
    if(conversationId)bindConversationActions(ctx,conversationId);
    const timer=window.setInterval(()=>{if(!document.hidden&&location.pathname.startsWith('/app/atendimento')){window.clearInterval(timer);void inboxPage(ctx,conversationId);}},15000);
    ctx.setDispose?.(()=>window.clearInterval(timer));
  }catch(error){fail(ctx,routeTitles.inbox,'inbox',error,'/app/atendimento');}
}

function bindConversationActions(ctx:Phase3Context,id:string){
  document.querySelector('#takeover')?.addEventListener('click',async()=>{try{await api('/inbox/takeover',{method:'POST',headers:{'Idempotency-Key':idempotency()},body:jsonBody({conversationId:id,reason:'Atendimento assumido pela central'})});announce('Conversa assumida.');await inboxPage(ctx,id);}catch(error){announce(ctx.message(error),'error');}});
  document.querySelector('#return-ai')?.addEventListener('click',async()=>{try{await api('/inbox/return-to-ai',{method:'POST',body:jsonBody({conversationId:id,reason:'Devolução explícita pelo atendente'})});announce('Conversa devolvida à IA.');await inboxPage(ctx,id);}catch(error){announce(ctx.message(error),'error');}});
  document.querySelector<HTMLFormElement>('#composer')?.addEventListener('submit',async event=>{event.preventDefault();const form=event.currentTarget as HTMLFormElement;const body=field(new FormData(form),'body');const button=form.querySelector<HTMLButtonElement>('button')!;button.disabled=true;try{await api('/inbox/messages',{method:'POST',headers:{'Idempotency-Key':idempotency()},body:jsonBody({conversationId:id,body})});form.reset();announce('Mensagem aceita para envio pelo provedor.');await inboxPage(ctx,id);}catch(error){announce(ctx.message(error),'error');}finally{button.disabled=false;}});
}

async function channelsPage(ctx:Phase3Context){
  loading(ctx,routeTitles.channels,'channels');
  try{const data=await api<Json>('/channels');const channels=records(data.channels);
    ctx.shell(routeTitles.channels,'<div class="page-heading"><div><p class="eyebrow">Integrações</p><h2>Canais de atendimento</h2><p class="muted">Credenciais ficam no Vault e nunca são devolvidas ao navegador.</p></div></div><div class="channel-grid">'+channels.map(channel=>'<article class="solid-panel channel-card"><div class="section-title"><h3>'+escapeHtml(text(channel.name,text(channel.provider)))+'</h3>'+badge(channel.status,channel.status==='active'?'success':channel.status==='degraded'?'warning':'')+'</div><dl class="detail-list"><dt>Provider</dt><dd>'+escapeHtml(text(channel.provider))+'</dd><dt>Último diagnóstico</dt><dd>'+escapeHtml(formatDate(channel.last_synced_at))+'</dd><dt>Erro redigido</dt><dd>'+escapeHtml(text(channel.last_error_code,'Nenhum'))+'</dd></dl>'+(channel.provider==='whatsapp'&&channel.status==='unconfigured'?'<button class="btn btn-primary" id="open-channel-form" type="button">Configurar Evolution API</button>':channel.id?'<div class="button-row"><button class="btn btn-secondary" data-pause="'+escapeHtml(channel.id)+'" data-paused="'+(channel.status==='paused'?'true':'false')+'" type="button">'+(channel.status==='paused'?'Retomar e diagnosticar':'Pausar canal')+'</button><button class="btn btn-danger" data-revoke="'+escapeHtml(channel.id)+'" type="button">Revogar conexão</button></div>':'<p class="muted">Adapter preparado; conexão ainda não autorizada.</p>')+'</article>').join('')+'</div><dialog id="channel-dialog"><form id="channel-form" class="stack"><div class="section-title"><h2>Conectar Evolution API</h2><button class="icon-button" value="cancel" formmethod="dialog" aria-label="Fechar">×</button></div><div class="field"><label for="channel-name">Nome</label><input id="channel-name" name="name" value="WhatsApp principal" required></div><div class="field"><label for="channel-url">URL HTTPS</label><input id="channel-url" name="baseUrl" type="url" required></div><div class="field"><label for="channel-instance">Instância</label><input id="channel-instance" name="instance" required></div><div class="field"><label for="channel-key">API key</label><input id="channel-key" name="apiKey" type="password" autocomplete="off" minlength="20" required></div><button class="btn btn-primary" type="submit">Salvar e diagnosticar</button></form></dialog>','channels');
    const dialog=document.querySelector<HTMLDialogElement>('#channel-dialog');document.querySelector('#open-channel-form')?.addEventListener('click',()=>dialog?.showModal());
    document.querySelector<HTMLFormElement>('#channel-form')?.addEventListener('submit',async event=>{event.preventDefault();const form=event.currentTarget as HTMLFormElement,data=new FormData(form);try{await api('/channels/evolution',{method:'POST',body:jsonBody({name:field(data,'name'),baseUrl:field(data,'baseUrl'),instance:field(data,'instance'),apiKey:field(data,'apiKey')})});dialog?.close();announce('Canal configurado; confira o diagnóstico.');await channelsPage(ctx);}catch(error){announce(ctx.message(error),'error');}});
    document.querySelectorAll<HTMLButtonElement>('[data-pause]').forEach(button=>button.addEventListener('click',async()=>{try{await api('/channels/pause',{method:'POST',body:jsonBody({connectionId:button.dataset.pause,paused:button.dataset.paused!=='true'})});announce(button.dataset.paused==='true'?'Canal retomado após diagnóstico.':'Canal pausado.');await channelsPage(ctx);}catch(error){announce(ctx.message(error),'error');}}));
    document.querySelectorAll<HTMLButtonElement>('[data-revoke]').forEach(button=>button.addEventListener('click',async()=>{try{await api('/channels/revoke',{method:'POST',body:jsonBody({connectionId:button.dataset.revoke})});announce('Conexão revogada e segredos removidos.');await channelsPage(ctx);}catch(error){announce(ctx.message(error),'error');}}));
  }catch(error){fail(ctx,routeTitles.channels,'channels',error,'/app/canais');}
}

async function assistantPage(ctx:Phase3Context){
  loading(ctx,routeTitles.assistant,'assistant');
  try{const [data,history]=await Promise.all([api<Json>('/ai/config'),api<Json>('/ai/history?limit=20')]);const config=record(data.config),runs=records(history.items);
    ctx.shell(routeTitles.assistant,'<div class="page-heading"><div><p class="eyebrow">Atendimento governado</p><h2>Assistente de IA</h2><p class="muted">A simulação usa somente fatos e versões aprovadas.</p></div>'+badge(data.providerConfigured?'provider_configured':'provider_unconfigured',data.providerConfigured?'success':'warning')+'</div><div class="assistant-layout"><form id="assistant-form" class="solid-panel form-grid"><div class="field"><label for="assistant-name">Nome</label><input id="assistant-name" name="assistantName" value="'+escapeHtml(text(config.assistant_name,'Assistente'))+'" required></div><div class="field"><label for="assistant-tone">Tom de voz</label><input id="assistant-tone" name="tone" value="'+escapeHtml(text(config.tone,'acolhedor e objetivo'))+'" required></div><div class="field"><label for="assistant-max">Limite por conversa</label><input id="assistant-max" name="maxMessages" type="number" min="1" max="200" value="'+number(config.max_messages_per_conversation||30)+'"></div><div class="field"><label for="assistant-daily">Orçamento diário (centavos)</label><input id="assistant-daily" name="dailyBudgetCents" type="number" min="0" value="'+number(config.daily_budget_cents||1000)+'"></div><div class="field field-wide"><label for="assistant-objectives">Objetivos, um por linha</label><textarea id="assistant-objectives" name="objectives">'+escapeHtml(recordsAsLines(config.objectives))+'</textarea></div><div class="field field-wide"><label for="assistant-rules">Regras comerciais aprovadas, uma por linha</label><textarea id="assistant-rules" name="commercialRules">'+escapeHtml(recordsAsLines(config.commercial_rules))+'</textarea></div><label class="field-wide"><input type="checkbox" name="enabled" '+(config.enabled?'checked':'')+'> Ativar assistente nesta unidade</label><button class="btn btn-primary" type="submit">Salvar configuração</button></form><section class="solid-panel"><h3>Simulação segura</h3><form id="simulate-form" class="stack"><div class="field"><label for="simulation-message">Mensagem do cliente</label><textarea id="simulation-message" name="message" required></textarea></div><button class="btn btn-secondary" type="submit" '+(!data.providerConfigured?'disabled':'')+'>Simular resposta</button><div id="simulation-output" class="simulation-output" aria-live="polite"></div></form></section></div><section class="solid-panel phase-section"><div class="section-title"><h3>Histórico de execuções</h3><span>'+runs.length+'</span></div>'+(runs.length?'<div class="responsive-table"><table><thead><tr><th>Início</th><th>Status</th><th>Modelo</th><th>Tokens</th><th>Resultado</th></tr></thead><tbody>'+runs.map(run=>'<tr><td>'+formatDate(run.started_at)+'</td><td>'+badge(run.status)+'</td><td>'+escapeHtml(text(run.model))+'</td><td>'+number(run.input_tokens)+' / '+number(run.output_tokens)+'</td><td>'+escapeHtml(text(run.result_code,run.error_code as string))+'</td></tr>').join('')+'</tbody></table></div>':empty('Sem execuções','As simulações e respostas aparecerão aqui.'))+'</section>','assistant');
    document.querySelector<HTMLFormElement>('#assistant-form')?.addEventListener('submit',async event=>{event.preventDefault();const form=event.currentTarget as HTMLFormElement,d=new FormData(form);try{await api('/ai/config',{method:'PUT',body:jsonBody({assistantName:field(d,'assistantName'),tone:field(d,'tone'),enabled:d.has('enabled'),maxMessages:Number(d.get('maxMessages')),dailyBudgetCents:Number(d.get('dailyBudgetCents')),monthlyBudgetCents:number(config.monthly_budget_cents||20000),objectives:lines(field(d,'objectives')),commercialRules:lines(field(d,'commercialRules'))})});announce('Configuração salva.');await assistantPage(ctx);}catch(error){announce(ctx.message(error),'error');}});
    document.querySelector<HTMLFormElement>('#simulate-form')?.addEventListener('submit',async event=>{event.preventDefault();const form=event.currentTarget as HTMLFormElement,output=document.querySelector('#simulation-output')!;output.textContent='Consultando fontes aprovadas…';try{const result=await api<Json>('/ai/simulate',{method:'POST',body:jsonBody({message:field(new FormData(form),'message')})});output.innerHTML='<strong>'+escapeHtml(text(result.status))+'</strong><p>'+escapeHtml(text(result.answer))+'</p><small>'+records(result.sources).length+' fonte(s) registrada(s)</small>';}catch(error){output.textContent=ctx.message(error);}});
  }catch(error){fail(ctx,routeTitles.assistant,'assistant',error,'/app/assistente-ia');}
}
const lines=(value:string)=>value.split('\n').map(item=>item.trim()).filter(Boolean);
const recordsAsLines=(value:unknown)=>Array.isArray(value)?value.filter(item=>typeof item==='string').join('\n'):'';

async function knowledgePage(ctx:Phase3Context){
  loading(ctx,routeTitles.knowledge,'knowledge');
  try{const data=await api<Json>('/knowledge');const sources=records(data.sources),documents=records(data.documents);
    const options=sources.map(source=>'<option value="'+escapeHtml(source.id)+'">'+escapeHtml(text(source.name))+'</option>').join('');
    const documentRows=documents.map(doc=>{const versions=records(doc.knowledge_document_versions),latest=versions.sort((a,b)=>number(b.version)-number(a.version))[0]??{};
      const approve=latest.status==='draft'&&latest.indexing_status==='ready'?'<button class="btn btn-secondary" type="button" data-approve-source="'+escapeHtml(doc.source_id)+'" data-approve-version="'+escapeHtml(latest.id)+'">Aprovar</button>':'';
      return '<div class="list-row"><span><strong>'+escapeHtml(text(doc.title))+'</strong><small>Versão '+number(latest.version)+' · '+escapeHtml(text(latest.indexing_status))+'</small></span><span class="row-actions">'+badge(latest.status)+approve+'</span></div>';}).join('');
    ctx.shell(routeTitles.knowledge,'<div class="page-heading"><div><p class="eyebrow">Fontes verificadas</p><h2>Base de conhecimento</h2><p class="muted">Rascunhos só entram nas respostas após indexação e aprovação explícita.</p></div><div class="button-row"><button class="btn btn-secondary" id="new-source" type="button">Nova fonte</button><button class="btn btn-primary" id="new-document" type="button" '+(!sources.length?'disabled':'')+'>Novo documento</button></div></div><div class="grid grid-2"><section class="solid-panel"><div class="section-title"><h3>Fontes</h3><span>'+sources.length+'</span></div>'+(sources.length?'<div class="compact-list">'+sources.map(source=>'<div class="list-row"><span><strong>'+escapeHtml(text(source.name))+'</strong><small>'+escapeHtml(text(source.source_kind))+' · '+escapeHtml(text(source.origin,'origem interna'))+'</small></span>'+badge(source.status)+'</div>').join('')+'</div>':empty('Nenhuma fonte','Cadastre fatos ou documentos para preparar a assistente.'))+'</section><section class="solid-panel"><div class="section-title"><h3>Documentos e versões</h3><span>'+documents.length+'</span></div>'+(documentRows?'<div class="compact-list">'+documentRows+'</div>':empty('Nenhum documento','Adicione conteúdo textual a uma fonte cadastrada.'))+'</section></div>'+
      '<dialog id="source-dialog"><form id="source-form" class="stack"><div class="section-title"><h2>Nova fonte</h2><button class="icon-button" value="cancel" formmethod="dialog" aria-label="Fechar">×</button></div><div class="field"><label for="source-name">Nome</label><input id="source-name" name="name" required></div><div class="field"><label for="source-kind">Tipo</label><select id="source-kind" name="kind"><option value="manual">Manual</option><option value="document">Documento</option><option value="academy_facts">Fatos da academia</option></select></div><div class="field"><label for="source-origin">Origem</label><input id="source-origin" name="origin"></div><button class="btn btn-primary" type="submit">Criar rascunho</button></form></dialog>'+
      '<dialog id="document-dialog"><form id="document-form" class="stack"><div class="section-title"><h2>Novo documento</h2><button class="icon-button" value="cancel" formmethod="dialog" aria-label="Fechar">×</button></div><div class="field"><label for="document-source">Fonte</label><select id="document-source" name="sourceId" required>'+options+'</select></div><div class="field"><label for="document-title">Título</label><input id="document-title" name="title" required></div><div class="field"><label for="document-content">Conteúdo aprovado para revisão</label><textarea id="document-content" name="content" maxlength="200000" required></textarea></div><button class="btn btn-primary" type="submit">Indexar como rascunho</button></form></dialog>','knowledge');
    const sourceDialog=document.querySelector<HTMLDialogElement>('#source-dialog'),documentDialog=document.querySelector<HTMLDialogElement>('#document-dialog');
    document.querySelector('#new-source')?.addEventListener('click',()=>sourceDialog?.showModal());document.querySelector('#new-document')?.addEventListener('click',()=>documentDialog?.showModal());
    document.querySelector<HTMLFormElement>('#source-form')?.addEventListener('submit',async event=>{event.preventDefault();const d=new FormData(event.currentTarget as HTMLFormElement);try{await api('/knowledge/sources',{method:'POST',body:jsonBody({name:field(d,'name'),kind:field(d,'kind'),origin:field(d,'origin')})});sourceDialog?.close();announce('Fonte criada como rascunho.');await knowledgePage(ctx);}catch(error){announce(ctx.message(error),'error');}});
    document.querySelector<HTMLFormElement>('#document-form')?.addEventListener('submit',async event=>{event.preventDefault();const d=new FormData(event.currentTarget as HTMLFormElement);try{await api('/knowledge/documents',{method:'POST',body:jsonBody({sourceId:field(d,'sourceId'),title:field(d,'title'),content:field(d,'content')})});documentDialog?.close();announce('Documento indexado como rascunho.');await knowledgePage(ctx);}catch(error){announce(ctx.message(error),'error');}});
    document.querySelectorAll<HTMLButtonElement>('[data-approve-version]').forEach(button=>button.addEventListener('click',async()=>{try{await api('/knowledge/approve',{method:'POST',body:jsonBody({sourceId:button.dataset.approveSource,versionId:button.dataset.approveVersion})});announce('Versão aprovada e disponível para a IA.');await knowledgePage(ctx);}catch(error){announce(ctx.message(error),'error');}}));
  }catch(error){fail(ctx,routeTitles.knowledge,'knowledge',error,'/app/base-conhecimento');}
}

async function queuesPage(ctx:Phase3Context){
  loading(ctx,routeTitles.queues,'queues');
  try{const data=await api<Json>('/queues');const queues=records(data.queues);
    ctx.shell(routeTitles.queues,'<div class="page-heading"><div><p class="eyebrow">Distribuição de atendimento</p><h2>Filas e SLA</h2><p class="muted">Prioridade, capacidade e tempo de primeira resposta por unidade.</p></div><button class="btn btn-primary" id="new-queue" type="button">Nova fila</button></div><div class="queue-grid">'+(queues.length?queues.map(queue=>'<article class="solid-panel"><div class="section-title"><h3>'+escapeHtml(text(queue.name))+'</h3><span>Prioridade '+number(queue.priority)+'</span></div><div class="sla"><strong>'+Math.round(number(queue.sla_first_response_seconds)/60)+' min</strong><span>SLA de primeira resposta</span></div><h4>Membros</h4><div class="avatar-stack">'+(records(queue.queue_members).map(member=>'<span class="avatar" title="Capacidade '+number(member.capacity)+'">'+escapeHtml(text(member.user_id).slice(0,2).toUpperCase())+'</span>').join('')||'<span class="muted">Sem membros ativos</span>')+'</div></article>').join(''):empty('Nenhuma fila','Crie uma fila antes de distribuir conversas.'))+'</div><dialog id="queue-dialog"><form id="queue-form" class="stack"><div class="section-title"><h2>Nova fila</h2><button class="icon-button" value="cancel" formmethod="dialog" aria-label="Fechar">×</button></div><div class="field"><label for="queue-name">Nome</label><input id="queue-name" name="name" required></div><div class="field"><label for="queue-priority">Prioridade</label><input id="queue-priority" name="priority" type="number" min="0" max="1000" value="100"></div><div class="field"><label for="queue-sla">SLA em segundos</label><input id="queue-sla" name="slaSeconds" type="number" min="60" value="900"></div><button class="btn btn-primary" type="submit">Criar fila</button></form></dialog>','queues');
    const dialog=document.querySelector<HTMLDialogElement>('#queue-dialog');document.querySelector('#new-queue')?.addEventListener('click',()=>dialog?.showModal());document.querySelector<HTMLFormElement>('#queue-form')?.addEventListener('submit',async event=>{event.preventDefault();const d=new FormData(event.currentTarget as HTMLFormElement);try{await api('/queues',{method:'POST',body:jsonBody({name:field(d,'name'),priority:Number(d.get('priority')),slaSeconds:Number(d.get('slaSeconds'))})});dialog?.close();announce('Fila criada.');await queuesPage(ctx);}catch(error){announce(ctx.message(error),'error');}});
  }catch(error){fail(ctx,routeTitles.queues,'queues',error,'/app/filas');}
}

export async function renderPhase3(path:string,ctx:Phase3Context){
  if(path==='/app/crm')return crmPage(ctx);
  if(path==='/app/crm/pipelines')return pipelinePage(ctx);
  if(path.startsWith('/app/crm/contatos/'))return contactPage(ctx,decodeURIComponent(path.slice('/app/crm/contatos/'.length)));
  if(path==='/app/agenda')return agendaPage(ctx);
  if(path==='/app/atendimento')return inboxPage(ctx);
  if(path.startsWith('/app/atendimento/'))return inboxPage(ctx,decodeURIComponent(path.slice('/app/atendimento/'.length)));
  if(path==='/app/canais')return channelsPage(ctx);
  if(path==='/app/assistente-ia')return assistantPage(ctx);
  if(path==='/app/base-conhecimento')return knowledgePage(ctx);
  return queuesPage(ctx);
}
