export type FieldDefinition = {
  field_key: string;
  label: string;
  field_type: string;
  required: boolean;
  validation?: { min?: number; minLength?: number; pattern?: string };
  options?: unknown;
};

export function validateOnboardingDocument(fields: FieldDefinition[], document: Record<string, unknown>) {
  const issues: { field: string; label: string; reason: string }[] = [];
  for (const field of fields) {
    const value = document[field.field_key];
    const empty = value === undefined || value === null ||
      (typeof value === 'string' && !value.trim()) || (Array.isArray(value) && value.length === 0);
    if (empty) {
      if (field.required) issues.push({field: field.field_key, label: field.label, reason: 'required'});
      continue;
    }
    let valid = true;
    const rules = field.validation ?? {};
    if (['number', 'currency'].includes(field.field_type)) {
      valid = typeof value === 'number' && Number.isFinite(value) && (rules.min === undefined || value >= rules.min);
    } else if (field.field_type === 'boolean') {
      valid = typeof value === 'boolean';
    } else if (field.field_type === 'multi_select') {
      valid = Array.isArray(value) && value.every(v => typeof v === 'string' && Array.isArray(field.options) && field.options.includes(v));
    } else {
      valid = typeof value === 'string';
      if (valid && typeof value === 'string') {
        valid = (rules.minLength === undefined || value.trim().length >= rules.minLength) &&
          (!rules.pattern || new RegExp(rules.pattern).test(value));
        if (field.field_type === 'single_select') valid &&= Array.isArray(field.options) && field.options.includes(value);
        if (field.field_type === 'email') valid &&= /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value);
        if (field.field_type === 'url') {
          try { valid &&= ['http:', 'https:'].includes(new URL(value).protocol); }
          catch { valid = false; }
        }
        if (field.field_type === 'date') valid &&= /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(value));
      }
    }
    if (!valid) issues.push({field: field.field_key, label: field.label, reason: 'invalid'});
  }
  return issues;
}
