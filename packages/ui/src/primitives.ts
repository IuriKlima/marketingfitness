export function escapeHtml(value:unknown) {
  return String(value ?? '')
    .replaceAll('&','&amp;')
    .replaceAll('<','&lt;')
    .replaceAll('>','&gt;')
    .replaceAll('"','&quot;')
    .replaceAll("'",'&#039;');
}

export function statusLabel(status:string) {
  const labels:Record<string,string> = {
    active:'Ativa',
    suspended:'Suspensa',
    draft:'Rascunho',
    submitted:'Em análise',
    approved:'Aprovado',
    rejected:'Ajustes solicitados'
  };
  return labels[status] ?? status;
}

export function fieldId(key:string) {
  return 'field-' + key.replace(/[^a-z0-9_-]/gi,'-');
}
