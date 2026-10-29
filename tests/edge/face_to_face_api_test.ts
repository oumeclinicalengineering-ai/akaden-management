// No live Supabase, no emails, no real patient data.
// Call the exact Edge handler with a forged-but-local Supabase client.
import {
  handleFaceToFaceRequest,
  type FaceToFaceDependencies
} from '../../supabase/functions/ver6-face-to-face-enrollment/index.ts';

const ORIGIN='https://example.invalid';
const TARGET='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const REQ='11111111-1111-4111-8111-111111111111';
const QR='a'.repeat(64);
const SECRET='b'.repeat(64);
// Real local GoTrue issued a 56-character URL-safe hashed token.
const TOKEN_HASH='e'.repeat(56);
const checks:(truth:unknown,what:string)=>asserts truth=(truth,what)=>{
 if(!truth)throw new Error(what);
};
type MockState={
  calls:string[];
  rate:'allow'|'deny'|'error';
  approved:boolean;
  issued:boolean;
  mismatch:boolean;
  failAuth:boolean;
  emailCount:number;
};
const newState=():MockState=>({
 calls:[],rate:'allow',approved:false,issued:false,
 mismatch:false,failAuth:false,emailCount:0
});
const settings={
 QR_ALLOWED_ORIGIN:ORIGIN,
 QR_ENROLLMENT_ENABLED:'true',
 QR_FACE_TO_FACE_ENABLED:'true',
 SUPABASE_URL:'https://example.supabase.co',
 SUPABASE_SERVICE_ROLE_KEY:'dummy-only-not-real',
};
const makeDependencies=(state:MockState,overrides:Record<string,string>={}):FaceToFaceDependencies=>{
 const env=(name:string)=>({...settings,...overrides} as Record<string,string>)[name];
 const client={
  rpc:async(name:string,args:Record<string,string>)=>{
    state.calls.push(name);
    if(name==='consume_qr_enrollment_rate_budget')
      return state.rate==='error'
        ?{data:null,error:{message:'mock db unavailable'}}
        :{data:state.rate==='allow',error:null};
    if(name==='start_device_enrollment'){
      checks(args.p_invite_hash!==QR,'raw QR leaked to database');
      checks(args.p_browser_secret_hash!==SECRET,'raw browser proof leaked to database');
      return {data:REQ,error:null};
    }
    if(name==='claim_approved_face_to_face_auth'){
      if(!state.approved||state.issued)return {data:[],error:null};
      state.issued=true;
      return {data:[{target_user_id:TARGET}],error:null};
    }
    return {data:null,error:{message:'unknown mocked RPC'}};
  },
  auth:{admin:{
    getUserById:async(id:string)=>{
      state.calls.push('getUserById');
      if(id!==TARGET || state.failAuth)return {data:{user:null},error:{message:'invalid'}};
      return {data:{user:{id:TARGET,email:'staff@example.invalid'}},error:null};
    },
    generateLink:async(opts:{type:string,email:string})=>{
      state.calls.push('generateLink');
      checks(opts.type==='magiclink','wrong official Auth link type');
      checks(opts.email==='staff@example.invalid','wrong Auth staff account email');
      return {data:{user:{id:state.mismatch?REQ:TARGET},properties:{hashed_token:TOKEN_HASH}},
              error:null};
    }
  }}
 };
 return {env,client:client as unknown as NonNullable<FaceToFaceDependencies['client']>};
};
const request=(body:Record<string,unknown>,origin=ORIGIN,method='POST')=>
 new Request('https://example.supabase.co/functions/v1/ver6-face-to-face-enrollment',{
  method,headers:{Origin:origin,'Content-Type':'application/json'},
  body:method==='POST'?JSON.stringify(body):undefined
 });

Deno.test('default-disabled, Origin-check, OPTIONS and method restrictions',async()=>{
 const st=newState();
 const missingGate=makeDependencies(st,{QR_ENROLLMENT_ENABLED:'false'});
 const disabled=await handleFaceToFaceRequest(request({action:'start'}),missingGate);
 checks(disabled.status===503,'default disabled gate must return 503');
 checks(st.calls.length===0,'disabled handler must not touch DB');
 const badOrigin=await handleFaceToFaceRequest(
  request({action:'start'},'https://attacker.invalid'),makeDependencies(st));
 checks(badOrigin.status===403,'foreign Origin should fail before DB');
 const preflight=await handleFaceToFaceRequest(
  new Request('https://example.supabase.co/functions/v1/ver6-face-to-face-enrollment',{
   method:'OPTIONS',headers:{Origin:ORIGIN}
  }),makeDependencies(st));
 checks(preflight.status===204,'valid OPTIONS preflight must succeed');
 const get=await handleFaceToFaceRequest(
  new Request('https://example.supabase.co/functions/v1/ver6-face-to-face-enrollment',{
   method:'GET',headers:{Origin:ORIGIN}
  }),makeDependencies(st));
 checks(get.status===405,'GET should never be allowed');
});

Deno.test('start: valid QR hashes secrets, persistent limiter, no login',async()=>{
 const st=newState();
 const deps=makeDependencies(st);
 const response=await handleFaceToFaceRequest(
  request({action:'start',invite_token:QR,browser_secret:SECRET,confirmation_code:'123456'}),deps);
 const body=await response.json();
 checks(response.status===201,'valid QR should generate pending request');
 checks(body.request_id===REQ,'wrong pending request ID');
 checks(st.calls.join(',')==='consume_qr_enrollment_rate_budget,start_device_enrollment',
  'start must rate limit before claiming QR');
 checks(!JSON.stringify(body).includes(SECRET),'secret exposed in response');
 checks(response.headers.get('Cache-Control')?.includes('no-store'),
  'QR API must never cache token responses');
 st.calls.length=0;st.rate='deny';
 const limited=await handleFaceToFaceRequest(
  request({action:'start',invite_token:QR,browser_secret:SECRET,confirmation_code:'123456'}),deps);
 checks(limited.status===429,'exceeded budget must 429');
 checks(limited.headers.get('Retry-After')==='60','rate-limit should provide retry hint');
 checks(!st.calls.includes('start_device_enrollment'),'throttled QR must not claim');
 st.calls.length=0;st.rate='error';
 const outage=await handleFaceToFaceRequest(
  request({action:'start',invite_token:QR,browser_secret:SECRET,confirmation_code:'123456'}),deps);
 checks(outage.status===503,'rate-limit datastore outage must fail closed');
 checks(!st.calls.includes('start_device_enrollment'),'datastore outage must not claim');
});

Deno.test('redeem: admin approval and original browser proof required',async()=>{
 const st=newState();
 const deps=makeDependencies(st);
 const payload={action:'redeem',request_id:REQ,browser_secret:SECRET};
 const before=await handleFaceToFaceRequest(request(payload),deps);
 checks(before.status===409,'unapproved Auth issuance must fail');
 checks(!st.calls.includes('generateLink'),'unapproved request created Auth token');
 st.approved=true;
 const approved=await handleFaceToFaceRequest(request(payload),deps);
 const json=await approved.json();
 checks(approved.status===200,'approved browser must get Auth proof once');
 checks(json.token_hash===TOKEN_HASH && json.type==='magiclink',
  'official Auth proof was not returned');
 checks(st.calls.includes('getUserById')&&st.calls.includes('generateLink'),
  'official Auth lookup and generation must be called after claim');
 checks(!JSON.stringify(json).includes(SECRET),'browser secret leaked into response');
 const second=await handleFaceToFaceRequest(request(payload),deps);
 checks(second.status===409,'replay must fail without new Auth token');
 checks(st.calls.filter(x=>x==='generateLink').length===1,
  'replay invoked Auth generation more than once');
 checks(st.emailCount===0,'email send was attempted');
});

Deno.test('redeem: malformed proof, throttling, forged Auth identity rejected',async()=>{
 const st=newState();
 const deps=makeDependencies(st);
 const malformed=await handleFaceToFaceRequest(
  request({action:'redeem',request_id:REQ,browser_secret:'wrong'}),deps);
 checks(malformed.status===400,'malformed secret should fail before the database');
 checks(st.calls.length===0,'malformed request hit database');
 st.rate='deny';
 const denied=await handleFaceToFaceRequest(
  request({action:'redeem',request_id:REQ,browser_secret:SECRET}),deps);
 checks(denied.status===429,'redeem attempts must obey rate budget');
 checks(!st.calls.includes('claim_approved_face_to_face_auth'),
  'limited redeemer got to claim');
 st.rate='allow';st.approved=true;st.mismatch=true;
 const mismatch=await handleFaceToFaceRequest(
  request({action:'redeem',request_id:REQ,browser_secret:SECRET}),deps);
 checks(mismatch.status===503,'mismatched Auth user must fail without credential');
 const data=await mismatch.json();
 checks(!data.token_hash,'Auth token was given for mismatched user');
});
