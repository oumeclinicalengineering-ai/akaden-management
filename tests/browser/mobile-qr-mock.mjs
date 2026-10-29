import assert from 'node:assert/strict';
import { chromium } from 'playwright';

const base='http://127.0.0.1:8765/ver6-qr-registration-dev.html';
const project='https://mock-project.supabase.co';
const STAFF='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const ADMIN='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const SESSION='bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
const QR_TOKEN='a'.repeat(64);
const REQUEST='11111111-1111-4111-8111-111111111111';
const config={user:null,request:null,approved:false,deviceRevoked:false};
const events=[];

// Only a fake SDK is loaded. NO requests to real Supabase and NO real emails.
const mockSupabaseSdk=String.raw`(function(){
 const STAFF='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
 const ADMIN='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 const SESSION='bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
 const state={user:null,otpCalls:[],linkValidated:false};
 function jwt(){
   if(!state.user)return null;
   const p={sub:state.user.id,session_id:SESSION};
   return 'test.'+btoa(JSON.stringify(p)).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_')+'.sig';
 }
 const client={
   auth:{
     async getSession(){return {data:{session:state.user?{access_token:jwt()}:null},error:null}},
     async getUser(){return {data:{user:state.user},error:null}},
     async signInWithOtp(args){state.otpCalls.push(args);return {data:{user:null,session:null},error:null}},
     async verifyOtp(args){
       if(args.type!=='email'||args.token!=='123456')return {error:{message:'wrong OTP'}};
       state.user={id:STAFF,email:args.email};return {error:null};
     },
     async signInWithPassword(args){
       if(!args.email||!args.password)return {error:{message:'invalid'}};
       state.user={id:ADMIN,email:args.email};return {error:null};
     },
     async signOut(){state.user=null;return {error:null}}
   },
   from(name){
     return {
       select(){return this;},eq(){return this;},
       async order(){
         return {data:[{user_id:STAFF,display_name:'試験スタッフB'}],error:null};
       },
       async maybeSingle(){
         return {data:{active:true,role:state.user?.id===ADMIN?'admin':'staff'},error:null};
       }
     }
   }
 };
 window.__fakeAuth={
   state,
   completeLink(email){state.user={id:STAFF,email};state.linkValidated=true}
 };
 window.supabase={createClient(){return client}};
})();`;

const browser=await chromium.launch({headless:true});
try{
 for (const {device,width,height} of [
    {device:'iPhone-like',width:390,height:844},
    {device:'Android-like',width:360,height:800}
 ]) {
   const context=await browser.newContext({
     viewport:{width,height},isMobile:true,hasTouch:true,
     deviceScaleFactor:2
   });
   const leak=[];
   await context.route(/^https?:\/\/(?!127\.0\.0\.1:8765).+/,async route=>{
     const url=route.request().url();
     if(url.includes('cdn.jsdelivr.net/npm/@supabase/supabase-js')) {
       await route.fulfill({status:200,contentType:'application/javascript',body:mockSupabaseSdk});
       return;
     }
     if(url===project+'/functions/v1/ver6-enrollment-api'){
       const req=route.request().postDataJSON();
       const action=req.action;
       events.push({device,action});
       let status=200,body={};
       if(action==='issue'){
         body={token:QR_TOKEN,expires_at:'2030-01-01T00:00:00Z'};
       }else if(action==='start'){
         assert.equal(req.invite_token,QR_TOKEN);
         config.request={code:req.confirmation_code,request_id:REQUEST};
         config.approved=false;
         body={request_id:REQUEST};
       }else if(action==='pending'){
         body={items:config.request?[{
           request_id:REQUEST,staff_name:'試験スタッフB',
           requested_at:'2026-10-29T08:00:00Z'
         }]:[]};
       }else if(action==='approve'){
         config.approved=!!(config.request &&
           req.request_id===REQUEST &&
           req.confirmation_code===config.request.code);
         body={approved:config.approved};
       }else if(action==='finish'){
         if(!config.approved){status=409;body={error:'not approved'};}
         else{body={enrolled:true};}
       }else if(action==='devices'){
         body={items:[{
           session_id:SESSION,staff_name:'試験スタッフB',
           enrolled_at:'2026-10-29T08:00:00Z',revoked_at:config.deviceRevoked?new Date().toISOString():null
         }]};
       }else if(action==='revoke'){
         config.deviceRevoked=true;body={revoked:true};
       }else{status=400;body={error:'mock: unknown action'};}
       await route.fulfill({status,contentType:'application/json',
         headers:{'access-control-allow-origin':'*'},body:JSON.stringify(body)});
       return;
     }
     leak.push(url);
     await route.abort();
   });
   const admin=await context.newPage();
   const errors=[];
   admin.on('pageerror',e=>errors.push('admin: '+e.message));
   await admin.goto(base);
   await admin.locator('#projectUrl').fill(project);
   await admin.locator('#publicKey').fill('sb_publishable_mock_only');
   await admin.locator('#connect').click();
   await admin.locator('#adminTab').click();
   await admin.locator('#adminEmail').fill('admin@example.invalid');
   await admin.locator('#adminPassword').fill('fake-password');
   await admin.locator('#adminLogin').click();
   await admin.locator('#prepareBootstrap').click();
   await admin.locator('#bootstrapUserId').waitFor({state:'visible'});
   assert.equal((await admin.locator('#bootstrapUserId').textContent()).trim(),ADMIN);
   await admin.locator('#staffChoice').selectOption(STAFF);
   await admin.locator('#issueQr').click();
   await admin.locator('#qr img, #qr canvas').first().waitFor({state:'visible'});
   assert.ok((await admin.locator('#notice').textContent()).includes('QRを発行'));

   const staff=await context.newPage();
   staff.on('pageerror',e=>errors.push('staff: '+e.message));
   await staff.goto(base+'#invite='+QR_TOKEN);
   assert.equal(new URL(staff.url()).hash,'','QR token must leave URL immediately');
   assert.equal(await staff.evaluate(()=>sessionStorage.getItem('akaden_qr_invite')),QR_TOKEN);
   await staff.locator('#projectUrl').fill(project);
   await staff.locator('#publicKey').fill('sb_publishable_mock_only');
   await staff.locator('#connect').click();

   assert.equal(await staff.locator('#authMethod').inputValue(),'magic');
   // Email fallback is now an optional collapsed section; open it explicitly.
   await staff.locator('#emailAlternative summary').click();
   await staff.locator('#staffEmail').fill('staff@example.invalid');
   await staff.locator('#sendOtp').click();
   const option=await staff.evaluate(()=>window.__fakeAuth.state.otpCalls.at(-1));
   assert.equal(option.options.shouldCreateUser,false);
   assert.equal(option.options.emailRedirectTo,base);
   assert.equal(await staff.locator('#otpSection').isVisible(),false);

   // A Magic Link opens in the same browser. Model that login, return to QR tab,
   // and explicitly refresh Auth status. This is a UI simulation only.
   await staff.evaluate(()=>window.__fakeAuth.completeLink('staff@example.invalid'));
   await staff.locator('#refreshLogin').click();
   await staff.locator('#startRequest').click();
   await staff.locator('#staffCode').waitFor({state:'visible'});
   const code=(await staff.locator('#staffCode').textContent()).trim();
   assert.match(code,/^\d{6}$/);

   await staff.locator('#finishRequest').click();
   await staff.waitForFunction(()=>document.querySelector('#notice').textContent.includes('not approved'));

   await admin.locator('#refreshPending').click();
   await admin.locator('#requestChoice').selectOption(REQUEST);
   await admin.locator('#approveCode').fill(code);
   await admin.locator('#approveRequest').click();
   await admin.waitForFunction(()=>document.querySelector('#notice').textContent.includes('対面承認'));

   await staff.locator('#finishRequest').click();
   await staff.locator('#openVer6').waitFor({state:'visible'});
   await staff.waitForFunction(()=>document.querySelector('#notice').textContent.includes('登録が完了'));

   await admin.locator('#refreshDevices').click();
   await admin.locator('#deviceChoice').selectOption(SESSION);
   admin.once('dialog',d=>d.accept());
   await admin.locator('#revokeDevice').click();
   await admin.waitForFunction(()=>document.querySelector('#notice').textContent.includes('旧端末の承認を無効化'));
   assert.equal(config.deviceRevoked,true);

   const pageWidth=await staff.evaluate(()=>({
     viewport:window.innerWidth,
     scroll:document.documentElement.scrollWidth
   }));
   assert.ok(pageWidth.scroll<=pageWidth.viewport+2,
     device+' horizontal overflow: '+JSON.stringify(pageWidth));
   assert.deepEqual(errors,[],device+' JavaScript errors');
   assert.deepEqual(leak,[],device+' unexpected external network calls');
   console.log('PASS: '+device+' '+width+'x'+height+
     ' QR fragment, Magic Link mode, admin approval, revocation, responsive layout (mock only)');
   await context.close();
   config.request=null;config.approved=false;config.deviceRevoked=false;
 }
 assert.ok(events.some(x=>x.action==='finish'));
 assert.ok(events.some(x=>x.action==='revoke'));
 console.log('PASS: no real Supabase project, actual email, or production database was contacted.');
}finally{await browser.close()}
