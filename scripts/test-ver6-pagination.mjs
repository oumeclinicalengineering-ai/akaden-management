import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';
const id=n=>String(n).padStart(8,'0');
function setup(file,n,inject=()=>null){
 const elements=new Map(),calls=[];
 const get=k=>{if(!elements.has(k))elements.set(k,{innerHTML:'',textContent:'',classList:{toggle(){},contains(){return false}}});return elements.get(k)};
 const data={orders:Array.from({length:n},(_,i)=>({id:id(i+1),created_at:'2026-10-30',item_name:'架空品',quantity:n+5,deleted:false})),receipts:Array.from({length:n},(_,i)=>({id:id(i+1),order_id:id(1),quantity:1,receipt_date:'2026-10-30'}))};
 const context=vm.createContext({document:{getElementById:get,addEventListener(){}},window:{scrollTo(){}},console});
 const code=[...readFileSync(new URL('../'+file,import.meta.url),'utf8').matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1].replace(/boot\(\);\s*$/,'');
 vm.runInContext(code,context);
 context.client={from(table){let cursor=null,size=Infinity,active=false;const q={select(){return q},eq(k,v){assert.equal(k,'deleted');assert.equal(v,false);active=true;return q},order(k,o){assert.equal(k,'id');assert.equal(o.ascending,true);return q},limit(v){size=v;return q},gt(k,v){assert.equal(k,'id');cursor=v;return q},async then(resolve,reject){try{
  const call={table,cursor,size,active,index:calls.filter(c=>c.table===table).length};calls.push(call);
  const override=await inject(call,data);
  const rows=data[table].filter(r=>(!active||!r.deleted)&&(cursor===null||r.id>cursor)).slice(0,Math.min(size,1000));
  resolve(override??{data:rows.map(r=>({...r})),error:null});
 }catch(e){reject(e)}}};return q}};
 vm.runInContext("db=client;user={id:'fake'};profile={role:'staff'};orders=[{id:'old'}];receipts=[{id:'old'}]",context);
 return {context,data,calls,get,load:()=>vm.runInContext('load()',context),state:()=>JSON.parse(vm.runInContext('JSON.stringify({orders,receipts})',context))};
}
for(const file of ['ver6-simple.html','ver6-preview.html']){
 for(const n of [999,1000,1001,2000])test(`${file}: complete ${n} orders/receipts and correct totals`,async()=>{
  const s=setup(file,n);await s.load();const state=s.state();assert.equal(state.orders.length,n);assert.equal(state.receipts.length,n);
  assert.equal(new Set(state.receipts.map(r=>r.id)).size,n);
  assert.equal(s.calls.filter(c=>c.table==='receipts').length,Math.floor(n/1000)+1);
  assert.ok(s.calls.filter(c=>c.table==='orders').every(c=>c.active));
  if(n){assert.equal(state.receipts.reduce((sum,r)=>sum+r.quantity,0),n);assert.ok(s.get('ordersRows').innerHTML.includes(file==='ver6-simple.html'?`data-label="受領済">${n}</td>`:`<td>${n}</td>`));
   vm.runInContext(`selected=orders.find(o=>o.id==='${id(1)}');renderHistory()`,s.context);
   assert.equal((s.get('receiptHistory').innerHTML.match(/class="panel"/g)||[]).length,n);
   const target=state.orders.find(o=>o.id===id(1));assert.equal(target.quantity-n,5);
   assert.ok(s.get('ordersRows').innerHTML.includes(file==='ver6-simple.html'?'data-label="残数">5</td>':'<td>5</td>'));
  }
 });
 test(`${file}: partial/full receipt, correction, cancellation, and history remain complete after page boundary`,async()=>{
  const s=setup(file,1001);
  // Three receipts are deliberately placed around the first page boundary.
  // The remaining synthetic rows only make the result cross the API limit.
  s.data.orders[0].quantity=5;
  for(let i=2;i<1000;i++)s.data.receipts[i].order_id=id(2);
  s.data.receipts[0]={id:id(1),order_id:id(1),quantity:2,receipt_date:'2026-10-30'};
  s.data.receipts[1]={id:id(2),order_id:id(1),quantity:2,receipt_date:'2026-10-31'};
  s.data.receipts[1000]={id:id(1001),order_id:id(1),quantity:1,receipt_date:'2026-11-01'};
  await s.load();
  const order=()=>s.state().orders.find(o=>o.id===id(1));
  const totals=()=>s.state().receipts.filter(r=>r.order_id===id(1)).reduce((sum,r)=>sum+r.quantity,0);
  assert.equal(totals(),5); // all three rows, including the second page, were read
  assert.equal(order().quantity,5);
  vm.runInContext(`selected=orders.find(o=>o.id==='${id(1)}');renderHistory()`,s.context);
  assert.equal((s.get('receiptHistory').innerHTML.match(/class="panel"/g)||[]).length,3);
  // Simulate the server result after correcting the middle receipt, then cancelling the last.
  s.data.receipts[1].quantity=1;
  await s.load();
  assert.equal(totals(),4);
  assert.ok(s.get('ordersRows').innerHTML.includes(file==='ver6-simple.html'?'data-label="残数">1</td>':'<td>1</td>'));
  s.data.receipts.splice(1000,1);
  await s.load();
  assert.equal(totals(),3); // the preceding two partial receipts remain available
  assert.ok(s.get('ordersRows').innerHTML.includes(file==='ver6-simple.html'?'data-label="残数">2</td>':'<td>2</td>'));
  vm.runInContext(`selected=orders.find(o=>o.id==='${id(1)}');renderHistory()`,s.context);
  assert.equal((s.get('receiptHistory').innerHTML.match(/class="panel"/g)||[]).length,2);
 });
 test(`${file}: middle-page error retains previous complete state and retry works`,async()=>{
  let fail=true;const s=setup(file,1001,c=>fail&&c.table==='receipts'&&c.index===1?{data:null,error:Error('offline')}:null);
  await assert.rejects(s.load(),/offline/);assert.equal(s.state().orders[0].id,'old');assert.equal(s.state().receipts[0].id,'old');
  fail=false;await s.load();assert.equal(s.state().receipts.length,1001);
 });
 test(`${file}: repeated/non-increasing page rejected without partial publish`,async()=>{
  const s=setup(file,1001,c=>c.table==='receipts'&&c.index===1?{data:[{id:id(1000)}],error:null}:null);
  await assert.rejects(s.load(),/取得順序/);assert.equal(s.state().orders[0].id,'old');
 });
 test(`${file}: deletion before cursor does not shift/skip later rows`,async()=>{
  const s=setup(file,1001,(c,data)=>{if(c.table==='receipts'&&c.index===1)data.receipts.shift()});
  await s.load();assert.equal(s.state().receipts.length,1001);assert.equal(s.state().receipts.at(-1).id,id(1001));
 });
 test(`${file}: cancelled orders excluded`,async()=>{
  const s=setup(file,17);s.data.orders[0].deleted=true;await s.load();assert.equal(s.state().orders.length,16);
 });
 test(`${file}: insert ahead of cursor is retrieved without duplicates`,async()=>{
  const s=setup(file,1000,(c,data)=>{if(c.table==='receipts'&&c.index===1)data.receipts.push({id:id(1001),order_id:id(1),quantity:1})});
  await s.load();assert.equal(s.state().receipts.length,1001);assert.equal(new Set(s.state().receipts.map(r=>r.id)).size,1001);
 });
 test(`${file}: late insert behind cursor is visible on next refresh`,async()=>{
  let inserted=false;const s=setup(file,1001,(c,data)=>{if(!inserted&&c.table==='receipts'&&c.index===1){inserted=true;data.receipts.unshift({id:id(0),order_id:id(1),quantity:1})}});
  await s.load();assert.equal(s.state().receipts.length,1001);await s.load();assert.equal(s.state().receipts.length,1002);
 });
 test(`${file}: stale load cannot overwrite a newer refresh`,async()=>{
  let release;let signal;const started=new Promise(r=>signal=r);
  const s=setup(file,17,async(c,data)=>{if(c.table==='orders'&&c.index===0)return {data:data.orders.map(r=>({...r})),error:null};if(c.table==='receipts'&&c.index===0){signal();await new Promise(r=>release=r)}});
  const old=s.load();await started;s.data.orders[0].item_name='架空更新';await s.load();release();await old;assert.equal(s.state().orders[0].item_name,'架空更新');
 });
}
