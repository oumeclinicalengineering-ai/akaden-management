import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const read=p=>fs.readFileSync(new URL('../'+p,import.meta.url),'utf8');
const page=read('ver6-qr-registration-dev.html');
const api=read('supabase/functions/ver6-enrollment-api/index.ts');
const finalize=read('supabase/migrations/20261029_finalize_device_enrollment_DRAFT.sql');
const adminView=read('supabase/migrations/20261029_enrollment_admin_views_DRAFT.sql');
const bootstrap=read('supabase/migrations/20261029_admin_bootstrap_DRAFT.sql');
const recovery=read('supabase/migrations/20261029_admin_device_recovery_DRAFT.sql');
const sessions=read('supabase/migrations/20261029_device_sessions_DRAFT.sql');
const noEmailApi=read('supabase/functions/ver6-face-to-face-enrollment/index.ts');
const noEmailSql=read('supabase/migrations/20261029_face_to_face_auth_claim_DRAFT.sql');
const noEmailConfig=read('supabase/config.toml');

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
assert.ok(page.includes('id="authMethod"') && page.includes('value="magic"'),
 'Magic Link default needed on new Free projects');
assert.ok(page.includes("options.emailRedirectTo=location.origin+location.pathname"),
 'Magic Link return URL required');
assert.ok(page.includes('detectSessionInUrl:true'),
 'Supabase must be able to process email link callbacks');
assert.ok(page.includes("localStorage.setItem('akaden-ver6-public-config'"),
 'Only public Supabase settings should persist for cross-tab Auth callbacks');
assert.ok(page.includes("localStorage.setItem('akaden-ver6-public-config',JSON.stringify({url,key}))"),
 'Supabase public config storage must not be accidentally inside a comment');
assert.ok(page.includes('shouldCreateUser:false'),'email Auth must not create accounts');

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
const showStart=page.indexOf('const showBootstrapIds=async()=>{');
const showEnd=page.indexOf('const loadStaff=async()=>{',showStart);
assert.ok(showStart>0 && showEnd>showStart,
 'Bootstrap/recovery ID display handler missing');
const showHandler=page.slice(showStart,showEnd);
assert.ok(showHandler.includes('auth.getUser(token)'),
 'Recovery ID display must use official authenticated Auth user');
assert.ok(!showHandler.includes(".from('profiles')"),
 'Unapproved replacement device cannot rely on profiles RLS to show session IDs');
assert.ok(recovery.includes('FROM PUBLIC,anon,authenticated,service_role'),
 'Emergency recovery must be denied to public and service-role API callers');
assert.ok(recovery.includes('JOIN public.profiles p ON p.user_id=s.user_id'),
 'Emergency recovery must check existing active admin profile');
assert.ok(recovery.includes("revocation_source='SQL_EDITOR_RECOVERY'"),
 'Recovery-induced revocation must be auditable');
assert.ok(sessions.includes('JOIN auth.sessions auth_s'),
 'Approved sessions must also exist in live Supabase Auth');
// Guard against malformed single-dollar PL/pgSQL delimiters in fixtures.
for (const filename of fs.readdirSync(new URL('../tests/postgres/',import.meta.url))) {
 if(!filename.endsWith('.sql'))continue;
 const sql=read('tests/postgres/'+filename);
 assert.ok(!/^\s*(?:DO \$|END \$;)\s*$/m.test(sql),
   'Malformed PL/pgSQL delimiter in '+filename);
}
for(const id of ['startNoEmail','finishNoEmail']) {
 assert.ok(page.includes('id="'+id+'"'),'Missing no-email staff UI: '+id);
}
assert.ok(page.includes("type:'magiclink'") && page.includes('publicEnrollmentRpc'),
 'Email-free flow must use official Auth verifyOtp after restricted server proof');
assert.ok(noEmailApi.includes("client.auth.admin.generateLink") &&
 noEmailApi.includes("type:'magiclink'"),'Email-free proof must be real GoTrue magiclink');
assert.ok(noEmailApi.includes("QR_FACE_TO_FACE_ENABLED") &&
 noEmailApi.includes("QR_ENROLLMENT_ENABLED"),'Disabled-by-default feature gates required');
assert.ok(noEmailApi.includes('origin!==allowed'),'Restrict trusted browser Origin');
assert.ok(noEmailSql.includes('credential_claimed_at IS NULL') &&
 noEmailSql.includes('r.approved_at IS NOT NULL') &&
 noEmailSql.includes('r.browser_secret_hash=p_browser_secret_hash') &&
 noEmailSql.includes('r.expires_at>now()'),'SQL must require approval, proof, expiry and one-time claim');
assert.ok(noEmailSql.includes('TO service_role') &&
 noEmailSql.includes('FROM PUBLIC,anon,authenticated'),
 'No anonymous direct credential claim RPC');
assert.ok(noEmailConfig.includes('verify_jwt = false') &&
 noEmailConfig.includes('[functions.ver6-face-to-face-enrollment]'),
 'Unauthenticated QR bootstrap requires explicit JWT-off function config');
console.log('PASS: email-free staff QR proof, official GoTrue Auth, operator-only recovery, RLS guards');
