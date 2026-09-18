import type { IncomingMessage, ServerResponse } from 'node:http';
import type { RuntimeConfig } from './config.ts';

export type AuthenticatedRequest={userId:string;accessToken:string;cookies:Record<string,string>;names:{access:string;refresh:string;context:string;csrf:string}};
export type TenantRequest={context:{organizationId:string;unitId:string};available:{organization_id:string;unit_id:string;roles:string[]}};
export type DomainArgs={
  req:IncomingMessage;res:ServerResponse;url:URL;path:string;config:RuntimeConfig;
  auth:AuthenticatedRequest;tenant:TenantRequest;
};
