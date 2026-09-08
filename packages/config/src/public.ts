export function validatePublicKey(value: unknown): string {
  if (typeof value !== 'string' || !value.startsWith('sb_publishable_') || value.includes('example')) throw new Error('Configure uma chave publicável válida');
  return value;
}
