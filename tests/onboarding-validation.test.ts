import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateOnboardingDocument } from '../packages/contracts/src/onboarding.ts';

test('required fields reject whitespace, empty choices, invalid types and out-of-range values', () => {
  const fields = [
    {field_key:'name',label:'Nome',field_type:'short_text',required:true,validation:{minLength:2}},
    {field_key:'budget',label:'Orçamento',field_type:'currency',required:true,validation:{min:0}},
    {field_key:'voice',label:'Voz',field_type:'multi_select',required:true,options:['calm']}
  ];
  assert.equal(validateOnboardingDocument(fields,{name:' ',budget:-1,voice:[]}).length,3);
  assert.equal(validateOnboardingDocument(fields,{name:'Academia fictícia',budget:0,voice:['calm']}).length,0);
  assert.equal(validateOnboardingDocument(fields,{name:42,budget:'0',voice:['unknown']}).length,3);
});
