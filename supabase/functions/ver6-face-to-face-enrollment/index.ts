// Development-only, disabled-by-default, EMAIL-FREE enrollment bootstrap.
// Auth is granted by a manager's *in-person approval*, never by QR possession
// alone. A new Supabase Auth session is created only via official verifyOtp.
// IMPORTANT: this function must be deployed with verify_jwt=false for anonymous
// QR start/redeem; DO NOT DEPLOY before exhaustive independent review.
import { createClient } from 'npm:@supabase/supabase-js@2.57.0';

type Body = Record<string,unknown>;
const hex64=/^[a-f0-9]{64}$/;
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const hash=async(value:string):Promise<string>=> {
  const bytes=new TextEncoder().encode(value);
  const digest=await crypto.subtle.digest('SHA-256',bytes);
  return Array.from(new Uint8Array(digest),n=>n.toString(16).padStart(2,'0')).join('');
};
const field=(obj:Body,k:string):string=>typeof obj[k]==='string'?obj[k] as string:'';

// The exported handler allows isolated HTTP tests with a mock Supabase
// client. In normal Edge deployment import.meta.main is true and serves HTTP.
export type FaceToFaceDependencies = {
  env?: (name:string)=>string|undefined;
  client?: ReturnType<typeof createClient>;
};
export const handleFaceToFaceRequest=async (
  request:Request,deps:FaceToFaceDependencies={}
):Promise<Response>=>{
  const env=deps.env ?? ((name:string)=>Deno.env.get(name));
  const origin=request.headers.get('origin')??'';
  const allowed=env('QR_ALLOWED_ORIGIN')??'';
  const headers:Record<string,string>={
    'Content-Type':'application/json; charset=utf-8',
    'Cache-Control':'no-store, no-cache, max-age=0',
    'Pragma':'no-cache',
    'X-Content-Type-Options':'nosniff',
    'Referrer-Policy':'no-referrer',
    'Vary':'Origin',
  };
  const reply=(status:number,body:Body)=>new Response(
    JSON.stringify(body),{status,headers});
  if(!allowed.startsWith('https://')||origin!==allowed)
    return reply(403,{error:'Origin not allowed'});
  headers['Access-Control-Allow-Origin']=allowed;
  headers['Access-Control-Allow-Methods']='POST, OPTIONS';
  headers['Access-Control-Allow-Headers']='apikey, authorization, content-type';
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(request.method!=='POST')return reply(405,{error:'POST only'});
  if(env('QR_ENROLLMENT_ENABLED')!=='true' ||
     env('QR_FACE_TO_FACE_ENABLED')!=='true')
    return reply(503,{error:'Face-to-face enrollment not enabled'});
  const url=env('SUPABASE_URL')??'';
  const serviceKey=env('SUPABASE_SERVICE_ROLE_KEY')??'';
  if(!url || !serviceKey)return reply(503,{error:'Server not configured'});
  let body:Body;
  try{
    const raw=await request.text();
    if(raw.length>1024)return reply(413,{error:'Request too large'});
    const value:unknown=JSON.parse(raw);
    if(!value||typeof value!=='object'||Array.isArray(value))
      return reply(400,{error:'Invalid input'});
    body=value as Body;
  }catch{return reply(400,{error:'Invalid JSON'})}
  const client=deps.client ?? createClient(url,serviceKey,{
    auth:{persistSession:false,autoRefreshToken:false}
  });
  // Persistent, transactional Postgres budgets. The platform's Auth rate
  // limits do not automatically protect this anonymous Edge Function.
  // Any DB error FAILS CLOSED. Do not use an in-memory per-isolate counter.
  const budget=async(action:'start'|'redeem',reference:string):Promise<'allow'|'deny'|'error'>=>{
    const {data,error}=await client.rpc('consume_qr_enrollment_rate_budget',{
      p_action:action,p_reference:reference
    });
    if(error)return 'error';
    return data===true?'allow':'deny';
  };
  try{
    const action=field(body,'action');
    if(action==='start'){
      // No Auth session yet. 256-bit QR and 256-bit scanning-browser proof
      // are necessary, but NOT sufficient for login: admin approval follows.
      const qr=field(body,'invite_token');
      const secret=field(body,'browser_secret');
      const code=field(body,'confirmation_code');
      if(!hex64.test(qr)||!hex64.test(secret)||!/^\d{6}$/.test(code))
        return reply(400,{error:'Invalid invite or request'});
      const inviteHash=await hash(qr);
      const gate=await budget('start',inviteHash);
      if(gate==='error')return reply(503,{error:'Enrollment protection unavailable'});
      if(gate==='deny'){
        headers['Retry-After']='60';
        return reply(429,{error:'Too many enrollment requests or invalid invitation'});
      }
      const {data,error}=await client.rpc('start_device_enrollment',{
        p_invite_hash:inviteHash,
        p_browser_secret_hash:await hash(secret),
        p_confirmation_code_hash:await hash(code)
      });
      if(error||typeof data!=='string'||!uuid.test(data))
        return reply(409,{error:'QR unavailable; request a new one'});
      return reply(201,{request_id:data});
    }
    if(action==='redeem'){
      const requestId=field(body,'request_id');
      const secret=field(body,'browser_secret');
      if(!uuid.test(requestId)||!hex64.test(secret))
        return reply(400,{error:'Invalid request'});
      const gate=await budget('redeem',requestId);
      if(gate==='error')return reply(503,{error:'Enrollment protection unavailable'});
      if(gate==='deny'){
        headers['Retry-After']='60';
        return reply(429,{error:'Too many requests or invalid enrollment request'});
      }
      // Atomically marks one approved browser claim, once only.
      // Do NOT return staff name or email on a missing/invalid proof.
      const {data,error}=await client.rpc('claim_approved_face_to_face_auth',{
        p_request_id:requestId,
        p_browser_secret_hash:await hash(secret)
      });
      if(error||!Array.isArray(data)||data.length!==1 ||
          !uuid.test(String(data[0]?.target_user_id??'')))
        return reply(409,{error:'Not approved, expired, or already redeemed'});
      const targetId=data[0].target_user_id as string;
      const {data:userResult,error:userError}=await client.auth.admin.getUserById(targetId);
      const user=userResult?.user;
      if(userError || !user || !user.email || user.id!==targetId)
        return reply(503,{error:'Approved staff Auth account unavailable'});
      // Generates official GoTrue verification token without sending an email.
      // Never use generateLink for arbitrary user input: target comes only from
      // the server-side approved DB request.
      const {data:link,error:linkError}=await client.auth.admin.generateLink({
        type:'magiclink',email:user.email
      });
      if(linkError || link?.user?.id!==targetId ||
          !hex64.test(String(link?.properties?.hashed_token??'')))
        return reply(503,{error:'Could not issue an Auth proof; ask for new QR'});
      // This is an actual LOGIN CREDENTIAL. Return it once, ONLY to browser
      // holding request_id + private 256-bit secret AFTER admin approval.
      return reply(200,{token_hash:link.properties.hashed_token,type:'magiclink'});
    }
    return reply(400,{error:'Unknown action'});
  }catch{
    // Do not log QR text, browser proof, Auth token_hash, or service role key.
    return reply(503,{error:'Enrollment temporarily unavailable'});
  }
};
if(import.meta.main){
  Deno.serve(request=>handleFaceToFaceRequest(request));
}
