// Readiness reporting only. Never executes SQL or authorizes deployment.
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
export const required=['schema','rls','grants','rpc','triggers','views','local_application','jwt_business_tests'];
export function blockers(inventory){
 if(inventory.gate!=='G1'||!Array.isArray(inventory.items))throw Error('Invalid G1 inventory');
 const seen=new Set();
 for(const item of inventory.items){
  if(!required.includes(item.id)||seen.has(item.id))throw Error('Unknown or duplicate requirement');
  seen.add(item.id);
  if(!['missing','summary_only','reviewed'].includes(item.status))throw Error('Invalid status');
 }
 return required.filter(id=>{
  const item=inventory.items.find(x=>x.id===id);
  return !item||item.status!=='reviewed'||typeof item.evidence!=='string'||!item.evidence.trim();
 });
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const inventory=JSON.parse(readFileSync(new URL('../tests/g1-definition-inventory.json',import.meta.url),'utf8'));
 const missing=blockers(inventory);
 console.log(missing.length?'G1 BLOCKED: '+missing.join(', '):'G1 inventory complete; human evidence review still required');
 if(missing.length)process.exitCode=2;
}
