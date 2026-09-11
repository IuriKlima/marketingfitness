import './styles.css';
import { api, ApiError, jsonBody } from './api.ts';
import { escapeHtml, fieldId, statusLabel } from '../../../packages/ui/src/primitives.ts';

type ContextRow = {
  organization_id:string;
  organization_name:string;
  unit_id:string;
  unit_name:string;
  roles:string[];
};
type Session = {
  userId:string;
  platformRoles:string[];
  contexts:ContextRow[];
  currentContext:{organizationId:string;unitId:string}|null;
};
type FieldDefinition = {
  field_key:string;
  section:string;
  label:string;
  description:string|null;
  field_type:string;
  required:boolean;
  options:unknown;
  sort_order:number;
  validation?:{min?:number;minLength?:number;pattern?:string};
};
type Onboarding = {
  id:string;
  revision:number;
  version:number;
  schema_version:number;
  status:string;
  document:Record<string,unknown>;
};

function applicationRoot() {
  const element = document.querySelector<HTMLDivElement>('#app');
  if (!element) throw new Error('Application root not found');
  return element;
}
const root = applicationRoot();
let session:Session|null = null;
let disposePage = () => {};

function ambient() {
  return '<div class="ambient" aria-hidden="true"><span class="orb one"></span><span class="orb two"></span></div>';
}

function logo() {
  return '<a class="brand" href="/academy" data-link><span class="brand-mark">A</span><span>AcadeAI</span></a>';
}

function message(error:unknown) {
  if (error instanceof ApiError) {
    const labels:Record<string,string> = {
      invalid_credentials:'E-mail ou senha inválidos.',
      invalid_origin:'Origem da solicitação não autorizada.',
      invalid_csrf:'Sua sessão de segurança expirou. Atualize a página.',
      session_expired:'Sua sessão expirou. Entre novamente.',
      onboarding_incomplete:'Preencha os campos obrigatórios antes de enviar.',
      invitation_invalid_or_expired:'Este convite é inválido, expirou ou já foi utilizado.',
      invitation_delivery_failed:'Não foi possível enviar o convite agora.',
      tenant_context_required:'Selecione uma academia e uma unidade.',
      review_not_allowed:'Você não tem autorização para revisar este onboarding.'
      ,context_changed:'A unidade mudou. Abra o formulário novamente.'
      ,onboarding_changed:'O documento foi alterado em outra sessão. Atualize a página antes de continuar.'
      ,onboarding_save_failed:'O rascunho não foi salvo. Atualize a página e tente novamente.'
    };
    return labels[error.code] ?? 'Não foi possível concluir a operação.';
  }
  return 'Ocorreu um erro inesperado. Tente novamente.';
}

function authView(kind:'login'|'recover'|'invite'|'recovery') {
  const isLogin = kind === 'login';
  const title = isLogin ? 'Bem-vindo de volta' :
    kind === 'recover' ? 'Recuperar acesso' :
    kind === 'recovery' ? 'Validar recuperação' : 'Aceitar convite';
  const subtitle = isLogin ? 'Entre para continuar a operação da sua academia.' :
    kind === 'recover' ? 'Enviaremos um link seguro se o e-mail estiver cadastrado.' :
    kind === 'recovery' ? 'Validando seu link seguro para redefinir a senha.' :
    'Entre com o mesmo e-mail que recebeu o convite.';
  const form = isLogin || kind === 'invite'
    ? '<form id="login-form" class="stack"><div class="field"><label for="email">E-mail</label><input id="email" name="email" type="email" autocomplete="email" required></div><div class="field"><label for="password">Senha</label><input id="password" name="password" type="password" autocomplete="current-password" minlength="8" required></div><button class="btn btn-primary" type="submit">Entrar com segurança</button><a class="btn btn-quiet" href="/recover" data-link>Esqueci minha senha</a><p id="form-message" class="form-message" role="status"></p></form>'
    : kind === 'recover'
      ? '<form id="recover-form" class="stack"><div class="field"><label for="email">E-mail</label><input id="email" name="email" type="email" autocomplete="email" required></div><button class="btn btn-primary" type="submit">Enviar link seguro</button><a class="btn btn-quiet" href="/login" data-link>Voltar para o login</a><p id="form-message" class="form-message" role="status"></p></form>'
      : '<div class="stack"><p id="form-message" class="form-message" role="status">Validando link…</p><a class="btn btn-secondary" href="/login" data-link>Voltar para o login</a></div>';
  root.innerHTML = ambient() +
    '<main class="auth-layout"><section class="auth-story">' + logo() +
    '<div class="hero-copy"><p class="eyebrow">Marketing inteligente para academias</p><h1>Clareza para decidir.<br>Ritmo para crescer.</h1><p class="lead">Estratégia, conteúdo, campanhas e atendimento reunidos em uma operação segura para cada academia.</p></div><p class="muted">Seus dados permanecem isolados por empresa e unidade.</p></section>' +
    '<section class="auth-panel"><div class="auth-card glass"><p class="eyebrow">Acesso seguro</p><h2>' + title + '</h2><p class="muted">' + subtitle + '</p>' + form + '</div></section></main>';
  bindLinks();

  document.querySelector<HTMLFormElement>('#login-form')?.addEventListener('submit',async event => {
    event.preventDefault();
    const formElement = event.currentTarget as HTMLFormElement;
    const output = document.querySelector<HTMLParagraphElement>('#form-message');
    const button = formElement.querySelector<HTMLButtonElement>('button[type=submit]');
    if (button) button.disabled = true;
    try {
      const data = new FormData(formElement);
      await api('/auth/login',{method:'POST',body:jsonBody({
        email:data.get('email'),password:data.get('password')
      })},false);
      if (kind === 'invite') await acceptInvitation();
      await ensureSession();
      await navigate('/academy');
    } catch (error) {
      if (output) { output.textContent = message(error); output.className = 'form-message error'; }
    } finally {
      if (button) button.disabled = false;
    }
  });

  document.querySelector<HTMLFormElement>('#recover-form')?.addEventListener('submit',async event => {
    event.preventDefault();
    const output = document.querySelector<HTMLParagraphElement>('#form-message');
    try {
      const data = new FormData(event.currentTarget as HTMLFormElement);
      await api('/auth/recover',{method:'POST',body:jsonBody({email:data.get('email')})},false);
      if (output) {
        output.textContent = 'Se o e-mail estiver cadastrado, o link chegará em alguns minutos.';
        output.className = 'form-message success';
      }
    } catch (error) {
      if (output) { output.textContent = message(error); output.className = 'form-message error'; }
    }
  });

  if (kind === 'recovery') void verifyOtpFromUrl('recovery');
}

async function verifyOtpFromUrl(type:'recovery'|'invite'|'email') {
  const output = document.querySelector<HTMLParagraphElement>('#form-message');
  const tokenHash = new URL(location.href).searchParams.get('token_hash');
  history.replaceState({},'',type === 'recovery' ? '/recovery/callback' : '/invite');
  if (!tokenHash) {
    if (output) output.textContent = 'O link não contém um código válido.';
    return;
  }
  try {
    await api('/auth/verify-otp',{method:'POST',body:jsonBody({tokenHash,type})},false);
    session = null;
    await ensureSession();
    await navigate(type === 'recovery' ? '/password' : '/invite');
  } catch (error) {
    if (output) { output.textContent = message(error); output.className = 'form-message error'; }
  }
}

async function acceptInvitation() {
  const token = new URL(location.href).searchParams.get('invitation') ??
    sessionStorage.getItem('pending-invitation');
  if (!token) throw new ApiError(400,'invitation_invalid_or_expired');
  sessionStorage.setItem('pending-invitation',token);
  await api('/invitations/accept',{method:'POST',body:jsonBody({token})});
  sessionStorage.removeItem('pending-invitation');
}

function currentContextRow() {
  if (!session?.currentContext) return null;
  return session.contexts.find(context =>
    context.organization_id === session?.currentContext?.organizationId &&
    context.unit_id === session?.currentContext?.unitId
  ) ?? null;
}

function shell(title:string, content:string, active:string) {
  const context = currentContextRow();
  const platformLink = session?.platformRoles.some(role => role === 'supreme' || role === 'support')
    ? '<a class="nav-link ' + (active === 'platform' ? 'active' : '') + '" href="/platform" data-link>Painel da plataforma</a>'
    : '';
  root.innerHTML = ambient() +
    '<a class="skip-link" href="#content">Ir para o conteúdo</a><div class="shell">' +
    '<aside class="sidebar glass" id="sidebar">' + logo() + '<nav aria-label="Principal">' +
    '<a class="nav-link ' + (active === 'academy' ? 'active' : '') + '" href="/academy" data-link>Visão geral</a>' +
    '<a class="nav-link ' + (active === 'onboarding' ? 'active' : '') + '" href="/onboarding" data-link>Onboarding</a>' +
    (context?.roles.includes('academy_admin') ? '<a class="nav-link" href="/members" data-link>Convites</a>' : '') +
    platformLink + '</nav><div class="sidebar-footer">' +
    (context ? '<div class="context-chip"><strong>' + escapeHtml(context.organization_name) + '</strong><br><span class="muted">' + escapeHtml(context.unit_name) + '</span></div>' : '') +
    '<button class="btn btn-secondary" id="switch-context">Trocar unidade</button><button class="btn btn-quiet" id="logout">Sair</button></div></aside>' +
    '<main class="main" id="content"><header class="topbar glass"><button class="btn btn-secondary mobile-menu" id="menu" aria-controls="sidebar" aria-expanded="false">Menu</button><h1>' + escapeHtml(title) + '</h1><span class="badge">Ambiente seguro</span></header>' +
    '<div class="content">' + content + '</div></main></div>';
  bindLinks();
  document.querySelector('#menu')?.addEventListener('click',event => {
    const button = event.currentTarget as HTMLButtonElement;
    const sidebar = document.querySelector('#sidebar');
    const open = sidebar?.classList.toggle('open') ?? false;
    button.setAttribute('aria-expanded',String(open));
  });
  document.querySelector('#switch-context')?.addEventListener('click',() => {
    if (session) session.currentContext = null;
    void renderContextSelection();
  });
  document.querySelector('#logout')?.addEventListener('click',async () => {
    try {
      await api('/auth/logout',{method:'POST'});
      session = null;
      await navigate('/login');
    } catch { window.alert('Não foi possível encerrar a sessão. Tente novamente.'); }
  });
}

async function renderContextSelection() {
  if (!session) return authView('login');
  const cards = session.contexts.map(context =>
    '<button class="context-option" data-org="' + escapeHtml(context.organization_id) + '" data-unit="' + escapeHtml(context.unit_id) + '"><strong>' +
    escapeHtml(context.organization_name) + '</strong><span>' + escapeHtml(context.unit_name) + '</span></button>'
  ).join('');
  root.innerHTML = ambient() + '<main class="auth-layout"><section class="auth-story">' + logo() +
    '<div class="hero-copy"><p class="eyebrow">Contexto de trabalho</p><h1>Onde vamos trabalhar agora?</h1><p class="lead">Escolha uma das unidades disponíveis para seu acesso.</p></div></section>' +
    '<section class="auth-panel"><div class="auth-card glass"><h2>Escolha a unidade</h2><div class="context-grid">' +
    (cards || '<p class="empty">Nenhuma academia ativa está vinculada a este acesso.</p>') +
    '</div><p id="form-message" class="form-message" role="status"></p><a class="btn btn-quiet" href="/login" data-link>Voltar ao acesso</a></div></section></main>';
  bindLinks();
  document.querySelectorAll<HTMLButtonElement>('.context-option').forEach(button => {
    button.addEventListener('click',async () => {
      button.disabled = true;
      try {
        const result = await api<{context:ContextRow}>('/context/select',{
          method:'POST',
          body:jsonBody({organizationId:button.dataset.org,unitId:button.dataset.unit})
        });
        session!.currentContext = {
          organizationId:result.context.organization_id,
          unitId:result.context.unit_id
        };
        await navigate('/academy');
      } catch (error) {
        const output = document.querySelector<HTMLParagraphElement>('#form-message');
        if (output) { output.textContent = message(error); output.className = 'form-message error'; }
      } finally {
        button.disabled = false;
      }
    });
  });
}

function academyPage() {
  const context = currentContextRow();
  shell('Visão geral',
    '<div class="page-heading"><div><p class="eyebrow">Central de marketing</p><h2>' + escapeHtml(context?.organization_name ?? 'Academia') + '</h2><p class="muted">Acompanhe o que precisa da sua atenção nesta unidade.</p></div><a class="btn btn-primary" href="/onboarding" data-link>Continuar onboarding</a></div>' +
    '<section class="grid grid-4" aria-label="Indicadores"><article class="card metric"><span>Onboarding</span><strong>Em construção</strong><span class="badge warning">Ação necessária</span></article><article class="card metric"><span>Conteúdos do mês</span><strong>0</strong><span>A estratégia será gerada após aprovação</span></article><article class="card metric"><span>Leads no CRM</span><strong>0</strong><span>Disponível nas próximas fases</span></article><article class="card metric"><span>Próxima análise</span><strong>—</strong><span>Atualização semanal após ativação</span></article></section>' +
    '<section class="grid grid-2" style="margin-top:1rem"><article class="card"><p class="eyebrow">Próximo passo</p><h3>Complete a anamnese da academia</h3><p class="muted">Esses dados serão a fonte confiável da estratégia, do calendário e do atendimento por IA.</p><a class="btn btn-secondary" href="/onboarding" data-link>Abrir onboarding</a></article><article class="card"><p class="eyebrow">Segurança</p><h3>Empresa e unidade isoladas</h3><p class="muted">O contexto atual é assinado e revalidado a cada operação. Alterar a URL não muda suas permissões.</p></article></section>',
    'academy'
  );
}

async function platformPage() {
  if (!session?.platformRoles.some(role => role === 'supreme' || role === 'support')) {
    return academyPage();
  }
  const result = await api<{organizations:Array<{id:string;name:string;status:string;plan:string;units:Array<{id:string;name:string}>}>}>('/platform/organizations');
  const rows = result.organizations.map(org =>
    '<tr><td><strong>' + escapeHtml(org.name) + '</strong></td><td><span class="badge ' + (org.status === 'active' ? 'success' : 'warning') + '">' + escapeHtml(statusLabel(org.status)) + '</span></td><td>' + escapeHtml(org.plan) + '</td><td>' + escapeHtml(org.units?.length ?? 0) + '</td></tr>'
  ).join('');
  const create = session.platformRoles.includes('supreme')
    ? '<form id="organization-form" class="card form-grid" style="margin-bottom:1rem"><div class="field"><label for="org-name">Nome da academia</label><input id="org-name" name="name" required minlength="2"></div><div class="field"><label for="unit-name">Primeira unidade</label><input id="unit-name" name="unitName" required minlength="2"></div><div><button class="btn btn-primary" type="submit">Criar academia</button></div><p id="form-message" class="form-message" role="status"></p></form>'
    : '';
  shell('Painel da plataforma',
    '<div class="page-heading"><div><p class="eyebrow">Administração central</p><h2>Academias da plataforma</h2><p class="muted">Status comercial separado dos dados operacionais de cada tenant.</p></div></div>' + create +
    '<div class="table-wrap"><table><thead><tr><th>Academia</th><th>Status</th><th>Plano</th><th>Unidades</th></tr></thead><tbody>' + (rows || '<tr><td colspan="4" class="empty">Nenhuma academia disponível.</td></tr>') + '</tbody></table></div><section id="invitation-panel"></section><section id="review-panel"></section>',
    'platform'
  );
  if (session.platformRoles.includes('supreme')) mountInvitations(result.organizations.filter(org=>org.status==='active'));
  void mountReviews();
  document.querySelector<HTMLFormElement>('#organization-form')?.addEventListener('submit',async event => {
    event.preventDefault();
    const output = document.querySelector<HTMLParagraphElement>('#form-message');
    try {
      const data = new FormData(event.currentTarget as HTMLFormElement);
      await api('/platform/organizations',{method:'POST',body:jsonBody({
        name:data.get('name'),unitName:data.get('unitName'),plan:'trial'
      })});
      await platformPage();
    } catch (error) {
      if (output) { output.textContent = message(error); output.className = 'form-message error'; }
    }
  });
}

function invitationsPage() {
  const context=currentContextRow();
  if (!context?.roles.includes('academy_admin')) return academyPage();
  shell('Convites','<section id="invitation-panel"></section>','members');
  mountInvitations([{id:context.organization_id,name:context.organization_name,units:session!.contexts.filter(c=>c.organization_id===context.organization_id).map(c=>({id:c.unit_id,name:c.unit_name}))}]);
}

function mountInvitations(organizations:Array<{id:string;name:string;units:Array<{id:string;name:string}>}>) {
  const panel=document.querySelector('#invitation-panel');
  if (!panel) return;
  panel.innerHTML='<div class="card management-card"><h2>Convidar uma pessoa</h2><p class="muted">O convite expira em 72 horas e vale para o e-mail informado.</p><form id="invitation-form" class="form-grid"><div class="field"><label for="invite-email">E-mail</label><input id="invite-email" name="email" type="email" required></div><div class="field"><label for="invite-role">Papel</label><select id="invite-role" name="role"><option value="viewer">Leitura</option><option value="academy_admin">Administrador da academia</option><option value="marketing_operator">Operador de marketing</option><option value="academy_attendant">Atendente</option></select></div><div class="field"><label for="invite-org">Academia</label><select id="invite-org" name="organizationId">'+organizations.map(o=>'<option value="'+escapeHtml(o.id)+'">'+escapeHtml(o.name)+'</option>').join('')+'</select></div><div class="field"><label for="invite-unit">Unidade</label><select id="invite-unit" name="unitId"></select></div><label><input type="checkbox" name="allUnits"> Todas as unidades (exige permissão para toda a academia)</label><button class="btn btn-primary" type="submit"'+(!organizations.length?' disabled':'')+'>Enviar convite</button><p id="invite-message" class="form-message field-wide" role="status"></p></form></div>';
  const orgSelect=document.querySelector<HTMLSelectElement>('#invite-org')!;
  const unitSelect=document.querySelector<HTMLSelectElement>('#invite-unit')!;
  const updateUnits=()=> {unitSelect.innerHTML=(organizations.find(o=>o.id===orgSelect.value)?.units ?? []).map(u=>'<option value="'+escapeHtml(u.id)+'">'+escapeHtml(u.name)+'</option>').join('');};
  orgSelect.addEventListener('change',updateUnits);updateUnits();
  document.querySelector<HTMLFormElement>('#invitation-form')!.addEventListener('submit',async event=>{
    event.preventDefault();
    const form=event.currentTarget as HTMLFormElement;
    const output=document.querySelector('#invite-message')!;
    const button=form.querySelector<HTMLButtonElement>('button')!;
    button.disabled=true;
    try {
      const data=new FormData(form);
      await api('/invitations',{method:'POST',body:jsonBody({email:data.get('email'),role:data.get('role'),organizationId:data.get('organizationId'),unitId:data.get('unitId'),allUnits:data.has('allUnits')})});
      output.textContent='Convite enviado.';output.className='form-message success field-wide';
    } catch(error) {output.textContent=message(error);output.className='form-message error field-wide';}
    finally {button.disabled=false;}
  });
}

async function mountReviews() {
  const panel=document.querySelector('#review-panel');
  if (!panel) return;
  try {
    const result=await api<{onboardings:Array<{id:string;organization_name:string;unit_name:string;version:number}>}>('/platform/onboarding');
    panel.innerHTML='<div class="card management-card"><h2>Onboardings para revisão</h2><div class="stack">'+(result.onboardings.map(v=>'<button class="context-option" data-review="'+escapeHtml(v.id)+'"><strong>'+escapeHtml(v.organization_name)+'</strong><span>'+escapeHtml(v.unit_name)+' · versão '+v.version+'</span></button>').join('')||'<p class="muted">Nenhum documento aguardando revisão no seu escopo.</p>')+'</div><div id="review-detail"></div></div>';
    panel.querySelectorAll<HTMLButtonElement>('[data-review]').forEach(button=>button.addEventListener('click',()=>{void loadReview(button.dataset.review!).catch(error=>{const detail=document.querySelector('#review-detail');if(detail)detail.textContent=message(error);});}));
  } catch(error) {panel.textContent=message(error);}
}

async function loadReview(id:string) {
  const result=await api<{onboarding:Onboarding;fields:FieldDefinition[];attachments:Array<{id:string;filename:string}>}>('/platform/onboarding/detail?id='+encodeURIComponent(id));
  const panel=document.querySelector('#review-detail');
  if (!panel) return;
  panel.innerHTML='<div class="management-card"><h3>Versão '+result.onboarding.version+'</h3><dl class="review-values">'+result.fields.map(f=>'<dt>'+escapeHtml(f.label)+'</dt><dd>'+escapeHtml(Array.isArray(result.onboarding.document[f.field_key])?(result.onboarding.document[f.field_key] as unknown[]).join(', '):result.onboarding.document[f.field_key] ?? 'Não informado')+'</dd>').join('')+'</dl>'+result.attachments.map(a=>'<p><a href="/api/onboarding/attachments/content?review=true&id='+encodeURIComponent(a.id)+'">'+escapeHtml(a.filename)+'</a></p>').join('')+'<form id="review-form" class="stack"><div class="field"><label for="review-notes">Parecer</label><textarea id="review-notes" name="notes" minlength="3" required></textarea></div><fieldset><legend>Campos que precisam de ajuste</legend>'+result.fields.map(f=>'<label class="review-check"><input type="checkbox" name="requestedFields" value="'+escapeHtml(f.field_key)+'"> '+escapeHtml(f.label)+'</label>').join('')+'</fieldset><div><button class="btn btn-primary" type="submit" name="decision" value="approved">Aprovar</button> <button class="btn btn-secondary" type="submit" name="decision" value="changes_requested">Solicitar ajustes</button></div><p id="review-message" class="form-message" role="status"></p></form></div>';
  document.querySelector<HTMLFormElement>('#review-form')!.addEventListener('submit',async event=>{
    event.preventDefault();
    const form=event.currentTarget as HTMLFormElement;
    const data=new FormData(form);
    const decision=(event as SubmitEvent).submitter?.getAttribute('value');
    const output=document.querySelector('#review-message')!;
    form.querySelectorAll<HTMLButtonElement>('button').forEach(b=>b.disabled=true);
    try {
      if(decision==='changes_requested'&&!data.getAll('requestedFields').length) {output.textContent='Selecione os campos que precisam de ajuste.';return;}
      await api('/onboarding/review',{method:'POST',body:jsonBody({onboardingId:id,decision,notes:data.get('notes'),requestedFields:data.getAll('requestedFields')})});
      await mountReviews();
    } catch(error) {output.textContent=message(error);}
    finally {form.querySelectorAll<HTMLButtonElement>('button').forEach(b=>b.disabled=false);}
  });
}

function optionLabel(value:string) {
  return value.replaceAll('_',' ').replace(/^\w/,letter => letter.toUpperCase());
}

function renderField(field:FieldDefinition, value:unknown, disabled:boolean) {
  const id = fieldId(field.field_key);
  const common = ' id="' + id + '" name="' + escapeHtml(field.field_key) + '" data-field="' + escapeHtml(field.field_key) + '"' + (disabled ? ' disabled' : '') + (field.required ? ' aria-required="true"' : '');
  let control = '';
  if (field.field_type === 'long_text') {
    control = '<textarea' + common + '>' + escapeHtml(value ?? '') + '</textarea>';
  } else if (field.field_type === 'single_select') {
    const options = Array.isArray(field.options) ? field.options : [];
    control = '<select' + common + '><option value="">Selecione</option>' + options.map(option =>
      '<option value="' + escapeHtml(option) + '"' + (value === option ? ' selected' : '') + '>' + escapeHtml(optionLabel(String(option))) + '</option>'
    ).join('') + '</select>';
  } else if (field.field_type === 'multi_select') {
    const options = Array.isArray(field.options) ? field.options : [];
    const selected = Array.isArray(value) ? value : [];
    control = '<div class="grid grid-2">' + options.map(option =>
      '<label><input type="checkbox" name="' + escapeHtml(field.field_key) + '" data-multi="' + escapeHtml(field.field_key) + '" value="' + escapeHtml(option) + '"' +
      (selected.includes(option) ? ' checked' : '') + (disabled ? ' disabled' : '') + '> ' + escapeHtml(optionLabel(String(option))) + '</label>'
    ).join('') + '</div>';
  } else if (field.field_type === 'boolean') {
    control = '<input type="checkbox"' + common + (value === true ? ' checked' : '') + '>';
  } else {
    const type = field.field_type === 'number' || field.field_type === 'currency' ? 'number' :
      field.field_type === 'date' ? 'date' : field.field_type === 'email' ? 'email' :
      field.field_type === 'url' ? 'url' : field.field_type === 'phone' ? 'tel' : 'text';
    control = '<input type="' + type + '"' + common + (type === 'number' ? ' step="any"' : '') + ' value="' + escapeHtml(value ?? '') + '">';
  }
  return '<div class="field ' + (field.field_type === 'long_text' || field.field_type === 'multi_select' ? 'field-wide' : '') + '"><label for="' + id + '">' +
    escapeHtml(field.label) + (field.required ? ' <span aria-label="obrigatório">*</span>' : '') + '</label>' +
    (field.description ? '<small>' + escapeHtml(field.description) + '</small>' : '') + control + '</div>';
}

async function onboardingPage() {
  disposePage();
  const current = await api<{onboarding:Onboarding|null;attachments:Array<{id:string;filename:string}>;reviews:Array<{notes:string;decision:string;requested_fields:string[]}>}>('/onboarding/current');
  const definition = await api<{fields:FieldDefinition[];schemaVersion:number}>('/onboarding/definition?schemaVersion='+(current.onboarding?.schema_version ?? 1));
  let onboarding = current.onboarding;
  const documentValue:Record<string,unknown> = {...(onboarding?.document ?? {})};
  const readOnly = !currentContextRow()?.roles.includes('academy_admin') || onboarding?.status === 'submitted' || onboarding?.status === 'approved';
  const sections = [...new Set(definition.fields.map(field => field.section))];
  const nav = sections.map(section =>
    '<a href="#section-' + escapeHtml(section.replace(/\W+/g,'-')) + '">' + escapeHtml(section) + '</a>'
  ).join('');
  const forms = sections.map(section =>
    '<section class="card form-section" id="section-' + escapeHtml(section.replace(/\W+/g,'-')) + '"><h3>' + escapeHtml(section) + '</h3><div class="form-grid">' +
    definition.fields.filter(field => field.section === section).map(field =>
      renderField(field,documentValue[field.field_key],readOnly)
    ).join('') + '</div></section>'
  ).join('');
  const required = definition.fields.filter(field => field.required);
  const complete = required.filter(field => {
    const value = documentValue[field.field_key];
    return value !== undefined && value !== null && value !== '' && (!Array.isArray(value) || value.length > 0);
  }).length;
  const percent = required.length ? Math.round(complete / required.length * 100) : 0;
  const review = current.reviews.at(-1);
  shell('Onboarding',
    '<div class="page-heading"><div><p class="eyebrow">Anamnese da academia</p><h2>Base estratégica</h2><p class="muted">Versão ' + escapeHtml(onboarding?.version ?? 1) + ' · <span class="badge">' + escapeHtml(statusLabel(onboarding?.status ?? 'draft')) + '</span></p></div></div>' +
    (review?.decision === 'changes_requested' ? '<div class="callout"><strong>Ajustes solicitados</strong><p>' + escapeHtml(review.notes) + '</p><p>'+escapeHtml(review.requested_fields.join(', '))+'</p></div>' : '') +
    '<div class="card" style="margin-bottom:1rem"><div style="display:flex;justify-content:space-between;gap:1rem"><strong>Progresso</strong><span id="progress-label">' + percent + '%</span></div><div class="progress" aria-label="Progresso do onboarding"><span id="progress-bar" style="width:' + percent + '%"></span></div></div>' +
    '<div class="onboarding-layout"><nav class="section-nav glass" aria-label="Seções do onboarding">' + nav + '</nav><form class="onboarding-form" id="onboarding-form">' + forms +
    '<section class="card form-section"><h3>Anexos</h3><p class="muted">Envie identidade visual, fotos e documentos em JPG, PNG, WEBP ou PDF, até 10 MB.</p>'+current.attachments.map(a=>'<p><a href="/api/onboarding/attachments/content?id='+encodeURIComponent(a.id)+'">'+escapeHtml(a.filename)+'</a></p>').join('')+'<input id="attachment" type="file" accept=".jpg,.jpeg,.png,.webp,.pdf"' + (!onboarding?.id || readOnly ? ' disabled' : '') + '><p id="attachment-message" class="form-message" role="status"></p></section>' +
    '<div class="sticky-actions glass"><span id="autosave-status" class="muted">' + (readOnly ? 'Documento bloqueado para edição.' : 'Alterações são salvas automaticamente.') + '</span><div><button class="btn btn-secondary" id="save-now" type="button"' + (readOnly ? ' disabled' : '') + '>Salvar agora</button> <button class="btn btn-primary" id="submit-onboarding" type="button"' + (readOnly ? ' disabled' : '') + '>Enviar para análise</button></div></div></form></div>',
    'onboarding'
  );

  const form = document.querySelector<HTMLFormElement>('#onboarding-form');
  let timer:number|undefined;
  let disposed = false;
  let saving:Promise<void> = Promise.resolve();
  const contextAtOpen = session?.currentContext;
  disposePage = () => {disposed=true;window.clearTimeout(timer);};
  function collect() {
    if (!form) return;
    for (const field of definition.fields) {
      if (field.field_type === 'multi_select') {
        documentValue[field.field_key] = Array.from(form.querySelectorAll<HTMLInputElement>('[data-multi="' + field.field_key + '"]:checked')).map(input => input.value);
      } else {
        const input = form.querySelector<HTMLInputElement|HTMLTextAreaElement|HTMLSelectElement>('[data-field="' + field.field_key + '"]');
        if (!input) continue;
        documentValue[field.field_key] = field.field_type === 'number' || field.field_type === 'currency'
          ? (input.value === '' ? '' : Number(input.value))
          : field.field_type === 'boolean' ? (input as HTMLInputElement).checked : input.value;
      }
    }
    const done = required.filter(field => {
      const value = documentValue[field.field_key];
      return value !== undefined && value !== null && value !== '' && (!Array.isArray(value) || value.length > 0);
    }).length;
    const next = required.length ? Math.round(done / required.length * 100) : 0;
    const label = document.querySelector('#progress-label');
    const bar = document.querySelector<HTMLElement>('#progress-bar');
    if (label) label.textContent = next + '%';
    if (bar) bar.style.width = next + '%';
  }
  async function save() {
    if (readOnly || disposed) return;
    window.clearTimeout(timer);
    collect();
    const snapshot = {...documentValue};
    const operation = async () => {
    if (disposed || session?.currentContext !== contextAtOpen) throw new Error('context_changed');
    const output = document.querySelector('#autosave-status');
    if (output) output.textContent = 'Salvando…';
    try {
      const result = await api<{onboarding:Onboarding}>('/onboarding/draft',{
        method:'PUT',body:jsonBody({schemaVersion:definition.schemaVersion,document:snapshot,expectedVersionId:onboarding?.id ?? null,expectedRevision:onboarding?.revision,expectedOrganizationId:contextAtOpen?.organizationId,expectedUnitId:contextAtOpen?.unitId})
      });
      onboarding = result.onboarding;
      const attachment = document.querySelector<HTMLInputElement>('#attachment');
      if (attachment && !disposed) attachment.disabled = false;
      if (output) output.textContent = 'Salvo com segurança.';
    } catch (error) {
      if (output) output.textContent = message(error);
      throw error;
    }
    };
    const next = saving.then(operation,operation);
    saving = next.catch(()=>undefined);
    return next;
  }
  form?.addEventListener('input',() => {
    collect();
    window.clearTimeout(timer);
    timer = window.setTimeout(() => {void save().catch(()=>undefined);},900);
  });
  document.querySelector('#save-now')?.addEventListener('click',() => {void save().catch(()=>undefined);});
  document.querySelector('#submit-onboarding')?.addEventListener('click',async () => {
    const output = document.querySelector('#autosave-status');
    try {
      await save();
      await api('/onboarding/submit',{method:'POST',body:jsonBody({expectedVersionId:onboarding?.id,expectedRevision:onboarding?.revision})});
      await onboardingPage();
    } catch (error) {
      if (output) output.textContent = message(error);
    }
  });
  document.querySelector<HTMLInputElement>('#attachment')?.addEventListener('change',async event => {
    const file = (event.currentTarget as HTMLInputElement).files?.[0];
    const output = document.querySelector('#attachment-message');
    if (!file || !onboarding?.id) return;
    try {
      const signed = await api<{attachmentId:string}>('/onboarding/attachments/upload-url',{
        method:'POST',
        body:jsonBody({onboardingId:onboarding.id,filename:file.name,mimeType:file.type,byteSize:file.size})
      });
      await api('/onboarding/attachments/content?id='+encodeURIComponent(signed.attachmentId),{method:'PUT',headers:{'Content-Type':file.type},body:file},false);
      if (output) { output.textContent = 'Arquivo enviado com segurança.'; output.className = 'form-message success'; }
    } catch (error) {
      if (output) { output.textContent = message(error); output.className = 'form-message error'; }
    }
  });
}

function passwordPage() {
  shell('Definir nova senha',
    '<div class="auth-card card"><h2>Crie uma nova senha</h2><p class="muted">Use pelo menos 12 caracteres e não reutilize uma senha antiga.</p><form id="password-form" class="stack"><div class="field"><label for="password">Nova senha</label><input id="password" name="password" type="password" minlength="12" autocomplete="new-password" required></div><button class="btn btn-primary" type="submit">Atualizar senha</button><p id="form-message" class="form-message" role="status"></p></form></div>',
    ''
  );
  document.querySelector<HTMLFormElement>('#password-form')?.addEventListener('submit',async event => {
    event.preventDefault();
    const output = document.querySelector<HTMLParagraphElement>('#form-message');
    try {
      const data = new FormData(event.currentTarget as HTMLFormElement);
      await api('/auth/password',{method:'POST',body:jsonBody({password:data.get('password')})});
      if (output) { output.textContent = 'Senha atualizada.'; output.className = 'form-message success'; }
      window.setTimeout(() => void navigate('/academy'),700);
    } catch (error) {
      if (output) { output.textContent = message(error); output.className = 'form-message error'; }
    }
  });
}

function bindLinks() {
  document.querySelectorAll<HTMLAnchorElement>('a[data-link]').forEach(link => {
    link.addEventListener('click',event => {
      if (link.origin !== location.origin) return;
      event.preventDefault();
      void navigate(link.pathname + link.search);
    });
  });
}

async function ensureSession() {
  try {
    session = await api<Session>('/auth/session');
    return true;
  } catch {
    session = null;
    return false;
  }
}

async function render() {
  disposePage();
  const path = location.pathname;
  if (path === '/login') return authView('login');
  if (path === '/recover') return authView('recover');
  if (path === '/recovery/callback') return authView('recovery');
  if (path === '/invite' && new URL(location.href).searchParams.has('token_hash')) {
    const params = new URL(location.href).searchParams;
    if (params.get('invitation')) sessionStorage.setItem('pending-invitation',params.get('invitation')!);
    authView('invite');
    await verifyOtpFromUrl(params.get('type') === 'email' ? 'email' : 'invite');
    return;
  }
  if (path === '/invite' && !session) {
    const token = new URL(location.href).searchParams.get('invitation');
    if (token) sessionStorage.setItem('pending-invitation',token);
    if (!(await ensureSession())) return authView('invite');
  }
  if (!session && !(await ensureSession())) return authView(path === '/invite' ? 'invite' : 'login');
  if (path === '/invite') {
    if (!new URL(location.href).searchParams.has('invitation') && !sessionStorage.getItem('pending-invitation') && session?.platformRoles.includes('supreme')) return navigate('/password');
    try { await acceptInvitation(); await ensureSession(); return navigate('/password'); }
    catch (error) {
      authView('invite');
      const output = document.querySelector<HTMLParagraphElement>('#form-message');
      if (output) { output.textContent = message(error); output.className = 'form-message error'; }
      return;
    }
  }
  if (path === '/password') return passwordPage();
  if (!session?.currentContext && session?.platformRoles.some(r=>['supreme','support'].includes(r))) return platformPage();
  if (!session?.currentContext && path !== '/platform') return renderContextSelection();
  if (path === '/platform') return platformPage();
  if (path === '/onboarding') return onboardingPage();
  if (path === '/members') return invitationsPage();
  return academyPage();
}

async function navigate(path:string) {
  history.pushState({},'',path);
  await safeRender();
}

async function safeRender() {
  try { await render(); }
  catch (error) { root.innerHTML=ambient()+'<main class="auth-panel"><div class="auth-card card"><h1>Não foi possível abrir esta tela</h1><p>'+escapeHtml(message(error))+'</p><a class="btn btn-primary" href="/login">Voltar ao acesso</a></div></main>'; }
}
window.addEventListener('popstate',() => void safeRender());
void safeRender();
