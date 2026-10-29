import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';

const html=readFileSync(new URL('../ver6-simple.html',import.meta.url),'utf8');
const code=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1].replace(/boot\(\);\s*$/, '');
function setup(quantity=3, failure=null, received=3){
 const elements=new Map(), writes=[];
 const element=id=>{if(!elements.has(id))elements.set(id,{classList:{toggle(){},contains(){return false}},textContent:'',innerHTML:''});return elements.get(id)};
 const answers=['架空物品',String(quantity),'2026-10-29'];
 const context=vm.createContext({document:{getElementById:element,addEventListener(){}},window:{scrollTo(){}},prompt:()=>answers.shift(),confirm:()=>true,console});
 vm.runInContext(code,context);
 context.mock={from:()=>({update:value=>({eq:async()=>{writes.push(value);return {error:failure}}})})};
 vm.runInContext("db=mock;orders=[{id:'demo',item_name:'架空物品',quantity:5}];receipts=[{order_id:'demo',quantity:3}];load=async()=>{}",context);
 context.received=received;
 vm.runInContext('receipts[0].quantity=received',context);
 return {context,element,writes};
}
for(const quantity of [0,-1,0.5,9007199254740992])test(`reject invalid quantity ${quantity} with no receipts`,async()=>{
 const s=setup(quantity,null,0);await s.element('ordersRows').onclick({target:{dataset:{editOrder:'demo'}}});assert.equal(s.writes.length,0);
});
test('allow quantity one with no receipts',async()=>{
 const s=setup(1,null,0);await s.element('ordersRows').onclick({target:{dataset:{editOrder:'demo'}}});assert.equal(s.writes[0].quantity,1);
});
for(const quantity of [0,2,1.5])test(`reject invalid quantity ${quantity}`,async()=>{
 const s=setup(quantity);await s.element('ordersRows').onclick({target:{dataset:{editOrder:'demo'}}});assert.equal(s.writes.length,0);
});
test('allow quantity equal to received total',async()=>{
 const s=setup();await s.element('ordersRows').onclick({target:{dataset:{editOrder:'demo'}}});assert.equal(s.writes[0].quantity,3);
});
test('show database error without reporting success',async()=>{
 const s=setup(4,{message:'test denied'});await s.element('ordersRows').onclick({target:{dataset:{editOrder:'demo'}}});assert.match(s.element('status').textContent,/修正できません/);
});
test('cancellation uses soft deletion',async()=>{
 const s=setup();await s.element('ordersRows').onclick({target:{dataset:{cancelOrder:'demo'}}});assert.equal(s.writes[0].deleted,true);
});
