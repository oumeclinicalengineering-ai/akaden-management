// Ver.6 QR registration REST bridge — STAGING ONLY. DO NOT DEPLOY YET.
// Gate is disabled by default; never publish until full Supabase Auth, RLS,
// CORS, admin bootstrap, rate limits and recovery are independently validated.
// Browser receives only public publishable key; service_role stays server-side.
import { createClient } from 'npm:@supabase/supabase-js@2.57.0';

type JsonObject = Record<string, unknown>;
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const hex64=/^[a-f0-9]{64}$/;
const encoder=new TextEncoder();
const sha256=async (value:string):Promise<string>=>{
  const bytes=await crypto.subtle.digest('SHA-256',encoder.encode(value));
  return Array.from(new Uint8Array(bytes),x=>x.toString(16).padStart(2,'0')).join('');
};
const token=()=>{
  const bytes=crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes,x=>x.toString(16).padStart(2,'0')).join('');
};
const getString=(obj:JsonObject,key:string)=>typeof obj[key]==='string'?obj[key] as string:'';
const jwtClaims=(jwt:string):JsonObject|null=>{
  try {
    const p=jwt.split('.')[1]; if(!p)return null;
    const base64=p.replace(/-/g,'+').replace(/_/g,'/');
    return JSON.parse(atob(base64.padEnd(Math.ceil(base64.length/4)*4,'=')));
  } catch {return null}
};

// Importable for isolated tests against disposable local Auth/PostgREST.
export type EnrollmentDependencies={env?:(name:string)=>string|undefined};
export const handleEnrollmentRequest=async (
  req:Request,deps:EnrollmentDependencies={}
):Promise<Response>=>{
  const env=deps.env ?? ((name:string)=>Deno.env.get(name));
  const origin=req.headers.get('origin') || '';
  const allowed=env('QR_ALLOWED_ORIGIN') || '';
  const cors:Record<string,string>={
    'Content-Type':'application/json; charset=utf-8',
    'Cache-Control':'no-store',
    'X-Content-Type-Options':'nosniff',
    'Vary':'Origin'
  };
  if(!allowed || !allowed.startsWith('https://') || origin !== allowed)
    return new Response(JSON.stringify({error:'Not an allowed origin'}),{status:403,headers:cors});
  Object.assign(cors,{
    'Access-Control-Allow-Origin':allowed,
    'Access-Control-Allow-Methods':'POST, OPTIONS',
    'Access-Control-Allow-Headers':'authorization, apikey, content-type'
  });
  const respond=(status:number,payload:JsonObject)=>
    new Response(JSON.stringify(payload),{status,headers:cors});

  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
  if(req.method!=='POST')return respond(405,{error:'POST required'});
  if(env('QR_ENROLLMENT_ENABLED')!=='true')
    return respond(503,{error:'QR enrollment is disabled until staging validation'});

  const url=env('SUPABASE_URL') || '';
  const publicKey=env('SUPABASE_PUBLISHABLE_KEY')
    || env('SUPABASE_ANON_KEY') || '';
  const secret=env('SUPABASE_SERVICE_ROLE_KEY') || '';
  if(!url || !publicKey || !secret)return respond(503,{error:'Server is not configured'});

  const authHeader=req.headers.get('authorization') || '';
  if(!/^Bearer\s+\S+$/.test(authHeader))return respond(401,{error:'Sign in first'});
  const jwt=authHeader.replace(/^Bearer\s+/,'');
  const auth=createClient(url,publicKey,{
    auth:{persistSession:false,autoRefreshToken:false}
  });
  const {data:verified,error:userError}=await auth.auth.getUser(jwt);
  const user=verified?.user;
  if(userError || !user)return respond(401,{error:'Invalid session'});

  const admin=createClient(url,secret,{
    auth:{persistSession:false,autoRefreshToken:false}
  });
  const scoped=createClient(url,publicKey,{
    global:{headers:{Authorization:'Bearer '+jwt}},
    auth:{persistSession:false,autoRefreshToken:false}
  });
  const {data:profile,error:profileError}=await admin.from('profiles')
    .select('role,active').eq('user_id',user.id).maybeSingle();
  if(profileError || !profile?.active)return respond(403,{error:'Inactive account'});

  let data:JsonObject;
  try {
    const body=await req.text();
    if(body.length>4096)return respond(413,{error:'Request too large'});
    const parsed:unknown=JSON.parse(body);
    if(!parsed || typeof parsed!=='object' || Array.isArray(parsed))
      return respond(400,{error:'Invalid JSON'});
    data=parsed as JsonObject;
  } catch {return respond(400,{error:'Invalid JSON'})}
  const action=getString(data,'action');
  const requireAdmin=async()=>{
    if(profile?.role!=='admin')return false;
    const {data:allowed,error}=await scoped.rpc('is_admin');
    return !error && allowed===true;
  };
  try {
    if(action==='issue'){
      if(!await requireAdmin())return respond(403,{error:'Approved admin required'});
      const userId=getString(data,'user_id');
      if(!uuid.test(userId))return respond(400,{error:'Invalid staff ID'});
      const {data:target}=await admin.from('profiles')
        .select('active,role').eq('user_id',userId).maybeSingle();
      if(!target?.active || target.role!=='staff')
        return respond(404,{error:'Active staff not found'});
      // Basic issuance throttling; proper central rate limiting is still required.
      const hourAgo=new Date(Date.now()-60*60*1000).toISOString();
      const {count,error:countError}=await admin.from('device_enrollment_invites')
        .select('id',{count:'exact',head:true})
        .eq('issued_by',user.id).gte('created_at',hourAgo);
      if(countError)return respond(503,{error:'Invite store unavailable'});
      if((count||0)>=5)return respond(429,{error:'QR issuance limit reached'});
      const inviteToken=token();
      const expiresAt=new Date(Date.now()+10*60*1000).toISOString();
      const {error}=await admin.from('device_enrollment_invites').insert({
        user_id:userId,issued_by:user.id,
        token_hash:await sha256(inviteToken),expires_at:expiresAt
      });
      if(error)return respond(503,{error:'Could not issue invitation'});
      return respond(201,{token:inviteToken,expires_at:expiresAt});
    }
    if(action==='start'){
      const inviteToken=getString(data,'invite_token');
      const browserSecret=getString(data,'browser_secret');
      const code=getString(data,'confirmation_code');
      if(!hex64.test(inviteToken) || !hex64.test(browserSecret)
         || !/^\d{6}$/.test(code))
        return respond(400,{error:'Invalid QR or verification code'});
      const hash=await sha256(inviteToken);
      const {data:invite,error:inviteError}=await admin.from('device_enrollment_invites')
        .select('user_id,expires_at,consumed_at,revoked_at')
        .eq('token_hash',hash).maybeSingle();
      if(inviteError || !invite || invite.user_id!==user.id ||
        invite.consumed_at || invite.revoked_at ||
        Date.parse(invite.expires_at)<=Date.now())
        return respond(403,{error:'QR expired, used, or for a different account'});
      const {data:requestId,error}=await admin.rpc('start_device_enrollment',{
        p_invite_hash:hash,
        p_browser_secret_hash:await sha256(browserSecret),
        p_confirmation_code_hash:await sha256(code)
      });
      if(error || !requestId)return respond(409,{error:'QR could not be registered'});
      return respond(201,{request_id:requestId});
    }
    if(action==='pending' || action==='devices'){
      if(!await requireAdmin())return respond(403,{error:'Approved admin required'});
      const name=action==='pending'?'list_pending_device_enrollments':'list_enrolled_devices';
      const {data:items,error}=await scoped.rpc(name);
      if(error)return respond(503,{error:'Admin list unavailable'});
      return respond(200,{items:items || []});
    }
    if(action==='approve'){
      if(!await requireAdmin())return respond(403,{error:'Approved admin required'});
      const requestId=getString(data,'request_id');
      const code=getString(data,'confirmation_code');
      if(!uuid.test(requestId) || !/^\d{6}$/.test(code))
        return respond(400,{error:'Invalid approval input'});
      const {data:ok,error}=await scoped.rpc('approve_device_enrollment',{
        p_request_id:requestId,
        p_confirmation_code_hash:await sha256(code)
      });
      if(error)return respond(403,{error:'Approval rejected'});
      return respond(ok ? 200 : 409,{approved:ok===true});
    }
    if(action==='finish'){
      const requestId=getString(data,'request_id');
      const browserSecret=getString(data,'browser_secret');
      if(!uuid.test(requestId) || !hex64.test(browserSecret))
        return respond(400,{error:'Invalid enrollment proof'});
      const claims=jwtClaims(jwt);
      const sessionId=claims?.session_id;
      if(claims?.sub!==user.id || typeof sessionId!=='string'
        || !uuid.test(sessionId))
        return respond(401,{error:'Missing verified Auth session'});
      const {data:ok,error}=await admin.rpc('finalize_approved_device_enrollment',{
        p_request_id:requestId,p_browser_secret_hash:await sha256(browserSecret),
        p_user_id:user.id,p_session_id:sessionId
      });
      if(error)return respond(503,{error:'Enrollment service unavailable'});
      return respond(ok===true ? 200 : 409,{enrolled:ok===true});
    }
    if(action==='revoke'){
      if(!await requireAdmin())return respond(403,{error:'Approved admin required'});
      const sessionId=getString(data,'session_id');
      if(!uuid.test(sessionId))return respond(400,{error:'Invalid session ID'});
      const {data:ok,error}=await scoped.rpc('revoke_enrolled_device',{
        p_session_id:sessionId
      });
      if(error)return respond(403,{error:'Revocation denied'});
      return respond(200,{revoked:ok===true});
    }
    return respond(400,{error:'Unknown action'});
  } catch {
    // Never print Authorization, raw QR token, browser proof or OTP to logs.
    return respond(500,{error:'Unexpected enrollment service error'});
  }
};
if(import.meta.main){
  Deno.serve(req=>handleEnrollmentRequest(req));
}
