import { readFileSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';

// Completes a manually configured, ignored .env without printing or replacing credentials.
const source = readFileSync('.env','utf8');
const lines = source.split(/\r?\n/);
const entries = lines.filter(line => /^SESSION_CONTEXT_SECRET=/.test(line));
if (entries.length !== 1) throw new Error('Expected exactly one SESSION_CONTEXT_SECRET entry in .env');
if (entries[0] !== 'SESSION_CONTEXT_SECRET=') {
  console.log('Existing context secret preserved.');
} else {
  const updated = lines.map(line => line === 'SESSION_CONTEXT_SECRET='
    ? 'SESSION_CONTEXT_SECRET=' + randomBytes(32).toString('base64url') : line).join('\n');
  writeFileSync('.env',updated,{mode:0o600});
  console.log('Local context secret generated. No credentials displayed.');
}
