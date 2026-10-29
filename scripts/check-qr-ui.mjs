import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const read=p=>fs.readFileSync(new URL('../'+p,import.meta.url),'utf8');
const page=read('ver6-qr-registration-dev.html');
const api=read('supabase/functions/ver6-enrollment-api/index.ts');
const finalize=read('supabase/migrations/20261029_finalize_device_enrollment_DRAFT.sql');
const adminView=read('supabase/migrations/20261029_enrollment_admin_views_DRAFT.sql');
const bootstrap=read('supabase/migrations/20261029_admin_bootstrap_DRAFT.sql');
const sessions=read('supabase/migrations/20261029_device_sessions_DRAFT.sql');

const scripts=[...page.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)];
let inlineCount=0;
for(const [,attrs,body] of scripts){
 if(/\bsrc\s*=/.test(attrs))continue;
 new vm.Script(body,{filename:'ver6-qr-registration-dev.html'});
 inlineCount++;
}
assert.ok(inlineCount>=2,'missing QR capture / application JS');
const capture=page.indexOf("sessionStorage.setItem('akaden_qr_invite'");
const external=page.indexOf('https://cdn.jsdelivr.net/');
assert.ok(capture>0 && external>capture,'fragment must be hidden before third-party scripts load');
assert.ok(page.includes('history.replaceState'),'QR fragment must be removed from URL');
assert.ok(page.includes('./vendor/qrcodejs/qrcode.min.js'),'QR rendered by local MIT library');
assert.ok(page.includes('signInWithOtp') && page.includes('shouldCreateUser:false'),
 'staff must use passwordless OTP without open registration');
assert.ok(page.includes('verifyOtp') && page.includes("type:'email'"),
 'official Supabase Auth OTP verification required');
for(const action of ['issue','start','pending','approve','finish','revoke','devices'])
 assert.ok(api.includes("action==='"+action+"'"),'API action missing: '+action);
assert.ok(api.includes("Deno.env.get('QR_ENROLLMENT_ENABLED')!=='true'"),
 'API must stay disabled until explicitly enabled');
assert.ok(api.includes('auth.auth.getUser(jwt)'),'every API action requires verified JWT');
assert.ok(api.includes("claims?.sub!==user.id"),'JWT/session ownership cross-check required');
assert.ok(!page.includes('SUPABASE_SERVICE_ROLE_KEY'),'browser must not reference secret key');
assert.ok(api.includes("origin !== allowed"),'API should require an explicit allowed origin');
assert.ok(finalize.includes('FROM auth.sessions'),'DB must verify official Auth session');
assert.ok(finalize.includes('FOR UPDATE'),'atomic request redemption requires row lock');
assert.ok(adminView.includes('list_pending_device_enrollments'),'admin request list required');
assert.ok(adminView.includes('list_enrolled_devices'),'admin device list required');
for(const id of ['prepareBootstrap','bootstrapUserId','bootstrapSessionId']) {
 assert.ok(page.includes('id="'+id+'"'),'missing safe operator bootstrap ID UI: '+id);
}
assert.ok(page.includes('showBootstrapIds') && page.includes('claims?.sub!==user.id'),
  'bootstrap screen must verify identity and session claim');
assert.ok(bootstrap.includes('FROM auth.sessions') || bootstrap.includes('JOIN public.profiles p ON p.user_id = s.user_id'),
  'bootstrap must verify a genuine Auth session');
assert.ok(bootstrap.includes('admin_bootstrap_receipt') &&
  bootstrap.includes('ON CONFLICT (singleton) DO NOTHING'),
  'bootstrap must be one-time only');
assert.ok(bootstrap.includes('FROM PUBLIC,anon,authenticated,service_role'),
  'bootstrap executable must be denied to all public API roles');
assert.ok(sessions.includes('最後の有効な管理者端末は無効化できません'),
  'revocation must preserve the last approved admin device');
console.log('PASS: HTML syntax, passwordless OTP, QR secret handling, API gates, admin bootstrap and session binding');
