import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {blockers,required} from './check-ver6-g1.mjs';
const inventory=JSON.parse(readFileSync(new URL('../tests/g1-definition-inventory.json',import.meta.url),'utf8'));
test('current summaries do not satisfy G1',()=>assert.deepEqual(blockers(inventory),required));
test('omitted requirements remain blockers',()=>assert.deepEqual(blockers({gate:'G1',items:[]}),required));
test('review label without evidence does not satisfy requirement',()=>{
 const sample={gate:'G1',items:[{id:'schema',status:'reviewed',evidence:''}]};
 assert.ok(blockers(sample).includes('schema'));
});
test('duplicate requirements are rejected',()=>assert.throws(()=>blockers({gate:'G1',items:[inventory.items[0],inventory.items[0]]})));
