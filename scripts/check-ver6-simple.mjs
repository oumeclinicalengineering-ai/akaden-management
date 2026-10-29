import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const s=readFileSync(new URL('../ver6-simple.html',import.meta.url),'utf8');
for (const item of ["signInWithPassword","auth.getUser","from('profiles')","from('orders')","from('receipts')","rpc('add_receipt'","rpc('change_receipt'","rpc('cancel_receipt'","document.addEventListener('visibilitychange'","架空データ専用"]) {
 assert.ok(s.includes(item), 'Required feature missing: '+item);
}
assert.ok(s.includes("data-edit-order"), 'Order edit control missing');
assert.ok(s.includes("data-cancel-order"), 'Order cancel control missing');
assert.ok(s.includes("update({deleted:true})"), 'Order cancellation must be a soft delete');
assert.ok(s.includes('受領済数量以上にしてください'), 'Order quantity must not go below received quantity');
assert.ok(!/sb_secret_[A-Za-z0-9_-]{10,}/.test(s), 'Secret key found');
assert.ok(!/service_role\s*[:=]\s*['"][A-Za-z0-9_-]{20,}/.test(s), 'Service-role key found');
console.log('Ver6 simple static checks passed. Not a live Supabase or browser test.');
