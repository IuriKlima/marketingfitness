export * from './ai.ts';
export * from './crm.ts';
export * from './messaging.ts';
export * from './onboarding.ts';

export interface Health { service:'api'|'worker';status:'ok'|'unavailable' }
