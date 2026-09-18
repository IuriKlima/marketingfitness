import { lookup } from 'node:dns/promises';
import { isIP } from 'node:net';
import { HttpError } from './http.ts';

function forbiddenIpv4(value:string) {
  const p=value.split('.').map(Number);
  return p[0]===10||p[0]===127||p[0]===0||p[0]>=224||
    (p[0]===169&&p[1]===254)||(p[0]===172&&p[1]>=16&&p[1]<=31)||(p[0]===192&&p[1]===168)||
    (p[0]===100&&p[1]>=64&&p[1]<=127);
}
function forbiddenIp(value:string) {
  if(isIP(value)===4) return forbiddenIpv4(value);
  const lower=value.toLowerCase();
  const mapped=lower.match(/^::ffff:(\d{1,3}(?:[.]\d{1,3}){3})$/);
  return lower==='::1'||lower==='::'||lower.startsWith('fe80:')||lower.startsWith('fc')||lower.startsWith('fd')||Boolean(mapped&&forbiddenIpv4(mapped[1]));
}

export function detectedMime(body:Uint8Array) {
  const starts=(...bytes:number[])=>bytes.every((byte,index)=>body[index]===byte);
  if(starts(0xff,0xd8,0xff))return 'image/jpeg';
  if(starts(0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a))return 'image/png';
  if(starts(0x52,0x49,0x46,0x46)&&String.fromCharCode(...body.slice(8,12))==='WEBP')return 'image/webp';
  if(String.fromCharCode(...body.slice(0,4))==='OggS')return 'audio/ogg';
  if(String.fromCharCode(...body.slice(0,4))==='%PDF')return 'application/pdf';
  if(String.fromCharCode(...body.slice(0,3))==='ID3'||(body.length>1&&body[0]===0xff&&(body[1]&0xe0)===0xe0))return 'audio/mpeg';
  return null;
}

export async function assertSafeProviderUrl(value:unknown,allowLocal=false) {
  let url:URL;
  try { url=new URL(String(value)); } catch { throw new HttpError(400,'invalid_provider_url'); }
  if(url.username||url.password||url.search||url.hash||url.pathname!=='/'||url.port&&Number(url.port)>65535) throw new HttpError(400,'invalid_provider_url');
  const local=allowLocal&&url.protocol==='http:'&&['127.0.0.1','localhost'].includes(url.hostname);
  if(url.protocol!=='https:'&&!local) throw new HttpError(400,'invalid_provider_url');
  if(local) return url.origin;
  let addresses:{address:string}[];
  try { addresses=await lookup(url.hostname,{all:true,verbatim:true}); } catch { throw new HttpError(400,'provider_dns_failed'); }
  if(!addresses.length||addresses.some(entry=>forbiddenIp(entry.address))) throw new HttpError(400,'provider_private_address');
  return url.origin;
}

export async function guardedDownload(urlValue:string,allowedMime:Set<string>,maxBytes=15728640) {
  const origin=await assertSafeProviderUrl(new URL(urlValue).origin);
  let current=new URL(urlValue);
  for(let redirects=0;redirects<3;redirects++) {
    if(current.origin!==origin) throw new HttpError(400,'unsafe_media_redirect');
    const response=await fetch(current,{redirect:'manual',signal:AbortSignal.timeout(15000)});
    if(response.status>=300&&response.status<400) {
      const location=response.headers.get('location'); if(!location) throw new HttpError(502,'invalid_media_response');
      current=new URL(location,current); await assertSafeProviderUrl(current.origin); continue;
    }
    if(!response.ok||!response.body) throw new HttpError(502,'media_download_failed');
    const mime=response.headers.get('content-type')?.split(';')[0]??'';
    if(!allowedMime.has(mime)) throw new HttpError(415,'unsupported_media_type');
    const declared=Number(response.headers.get('content-length')??'0');
    if(declared>maxBytes) throw new HttpError(413,'media_too_large');
    const chunks:Uint8Array[]=[];let length=0;const reader=response.body.getReader();
    while(true){const {done,value}=await reader.read();if(done)break;const part=value;length+=part.length;if(length>maxBytes)throw new HttpError(413,'media_too_large');chunks.push(part);}
    const body=new Uint8Array(length);let offset=0;for(const chunk of chunks){body.set(chunk,offset);offset+=chunk.length;}
    if(detectedMime(body)!==mime)throw new HttpError(415,'media_type_mismatch');
    return {body,mime};
  }
  throw new HttpError(400,'too_many_media_redirects');
}
