import { escapeHtml } from './primitives.ts';

type Attributes=Record<string,string|number|boolean|undefined>;
function attrs(values:Attributes={}) {
  return Object.entries(values).filter(([,value])=>value!==undefined&&value!==false)
    .map(([key,value])=>' '+key+(value===true?'':'="'+escapeHtml(value)+'"')).join('');
}
export const GlassPanel=(content:string,className='')=>`<section class="glass-panel ${escapeHtml(className)}">${content}</section>`;
export const SolidPanel=(content:string,className='')=>`<section class="solid-panel ${escapeHtml(className)}">${content}</section>`;
export const Button=(label:string,values:Attributes={})=>`<button class="button ${escapeHtml(String(values.variant??'secondary'))}"${attrs({...values,variant:undefined})}>${escapeHtml(label)}</button>`;
export const Input=(label:string,name:string,values:Attributes={})=>`<label class="control"><span>${escapeHtml(label)}</span><input name="${escapeHtml(name)}"${attrs(values)}></label>`;
export const Select=(label:string,name:string,options:{value:string;label:string}[],values:Attributes={})=>`<label class="control"><span>${escapeHtml(label)}</span><select name="${escapeHtml(name)}"${attrs(values)}>${options.map(o=>`<option value="${escapeHtml(o.value)}">${escapeHtml(o.label)}</option>`).join('')}</select></label>`;
export const Badge=(label:string,tone='neutral')=>`<span class="ui-badge ${escapeHtml(tone)}">${escapeHtml(label)}</span>`;
export const Avatar=(name:string)=>`<span class="avatar" aria-label="${escapeHtml(name)}">${escapeHtml(name.trim().slice(0,2).toUpperCase())}</span>`;
export const Tabs=(items:{id:string;label:string;active?:boolean}[])=>`<div class="tabs" role="tablist">${items.map(i=>`<button role="tab" data-tab="${escapeHtml(i.id)}" aria-selected="${i.active?'true':'false'}">${escapeHtml(i.label)}</button>`).join('')}</div>`;
export const Table=(head:string[],body:string[][])=>`<div class="table-surface"><table><thead><tr>${head.map(h=>`<th>${escapeHtml(h)}</th>`).join('')}</tr></thead><tbody>${body.map(row=>`<tr>${row.map(cell=>`<td>${escapeHtml(cell)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
export const Skeleton=(lines=4)=>`<div class="skeleton" role="status" aria-label="Carregando">${Array.from({length:lines},()=>'<i></i>').join('')}</div>`;
export const EmptyState=(title:string,description:string,action='')=>`<div class="empty-state"><h3>${escapeHtml(title)}</h3><p>${escapeHtml(description)}</p>${action}</div>`;
export const Dialog=(id:string,title:string,content:string)=>`<dialog id="${escapeHtml(id)}"><header><h2>${escapeHtml(title)}</h2></header>${content}</dialog>`;
export const Drawer=Dialog;
export const Toast=(message:string,tone='neutral')=>`<div class="toast ${escapeHtml(tone)}" role="status">${escapeHtml(message)}</div>`;
export const Navigation=(label:string,items:{href:string;label:string;active?:boolean}[])=>`<nav aria-label="${escapeHtml(label)}">${items.map(item=>`<a href="${escapeHtml(item.href)}"${item.active?' aria-current="page"':''}>${escapeHtml(item.label)}</a>`).join('')}</nav>`;
