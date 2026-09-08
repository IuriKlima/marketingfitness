export interface Health { service: 'api' | 'worker'; status: 'ok' | 'unavailable' }
export interface OutboxReference { id: string; organizationId: string; idempotencyKey: string }
export interface OutboxPort {
  claim(limit: number): Promise<OutboxReference[]>;
  acknowledge(id: string): Promise<void>;
  retry(id: string, availableAt: Date): Promise<void>;
}
