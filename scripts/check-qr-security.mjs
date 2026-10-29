import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const read=p=>readFileSync(new URL(p,import.meta.url),'utf8');
const preview=read('../ver6-preview.html');
const issuer=read('../supabase/functions/issue-enrollment-invite/index.ts');
const invite=read('../supabase/migrations/20261029_device_enrollment_invites_DRAFT.sql');
const consume=read('../supabase/migrations/20261029_consume_enrollment_invite_DRAFT.sql');
const prototype=read('../qr-enrollment-ui-prototype.html');
const checks=[
  ['existing preview uses password login',preview.includes('signInWithPassword')],
  ['existing preview warns QR not implemented',preview.includes('QR初回登録は未実装')],
  ['issuer authenticates user',issuer.includes('auth.getUser(')],
  ['issuer checks admin role',issuer.includes("actor.role!=='admin'")],
  ['issuer uses cryptographic random bytes',issuer.includes('crypto.getRandomValues(new Uint8Array(32))')],
  ['issuer stores token hash',issuer.includes('token_hash:tokenHash')],
  ['issuer never persists raw token',!issuer.includes('token_hash:token,')],
  ['invite table has RLS',invite.includes('enable row level security')],
  ['invite table revokes public access',invite.includes('from anon, authenticated')],
  ['consume requires unused token',consume.includes('i.consumed_at is null')],
  ['consume requires nonexpired token',consume.includes('i.expires_at > now()')],
  ['consume requires nonrevoked token',consume.includes('i.revoked_at is null')],
  ['consume disallows authenticated RPC',consume.includes('from public, anon, authenticated')],
  ['UI explicitly labeled prototype',prototype.includes('画面のみの試作品')],
  ['UI has no working enrollment button',prototype.includes('QR発行（未接続）')&&prototype.includes('id="issue" disabled')]
];
for(const [name,ok] of checks){assert.ok(ok,name);console.log('PASS '+name)}
console.log('STATIC checks only: Auth, RLS, and SQL execution remain unverified.');
