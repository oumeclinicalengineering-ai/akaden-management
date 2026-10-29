// Supabase Edge Function: admin-only invite issuance (STAGING; not deployed).
// Required secret: SUPABASE_SERVICE_ROLE_KEY (server-side only).
import { createClient } from 'npm:@supabase/supabase-js@2';
const headers = { 'Content-Type':'application/json','Cache-Control':'no-store' };
const reply=(status:number,message:string)=>new Response(JSON.stringify({message}),{status,headers});
Deno.serve(async req=>{
  if(req.method!=='POST')return reply(405,'Method not allowed');
  const origin=req.headers.get('origin');
  // Browser access is intentionally disabled until an explicit allowed-origin policy is configured.
  if(origin)return reply(403,'Browser requests are disabled in staging');
  const bearer=req.headers.get('authorization')||'';
  if(!/^Bearer\s+\S+$/.test(bearer))return reply(401,'Authentication required');
  const url=Deno.env.get('SUPABASE_URL');
  const publicKey=Deno.env.get('SUPABASE_ANON_KEY');
  const secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if(!url||!publicKey||!secret)return reply(503,'Server configuration missing');
  const auth=createClient(url,publicKey,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:identity,error:authError}=await auth.auth.getUser(bearer.replace(/^Bearer\s+/,''));
  if(authError||!identity.user)return reply(401,'Invalid session');
  const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:actor,error:actorError}=await admin.from('profiles').select('role,active').eq('user_id',identity.user.id).single();
  if(actorError||!actor?.active||actor.role!=='admin')return reply(403,'Admin permission required');
  let body:unknown;
  try{body=await req.json()}catch{return reply(400,'Invalid JSON')}
  if(!body||typeof body!=='object'||!('user_id' in body)||typeof body.user_id!=='string'||!/^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(body.user_id))return reply(400,'Invalid user_id');
  const targetId=body.user_id;
  const {data:target,error:targetError}=await admin.from('profiles').select('active').eq('user_id',targetId).single();
  if(targetError||!target?.active)return reply(404,'Active staff not found');
  const bytes=crypto.getRandomValues(new Uint8Array(32));
  const token=Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(token));
  const tokenHash=Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,'0')).join('');
  const expiresAt=new Date(Date.now()+10*60*1000).toISOString();
  const {error:insertError}=await admin.from('device_enrollment_invites').insert({user_id:targetId,issued_by:identity.user.id,token_hash:tokenHash,expires_at:expiresAt});
  if(insertError)return reply(500,'Could not issue invitation');
  // Token is returned exactly once; never log it. Do not use as an authentication credential.
  return new Response(JSON.stringify({token,expires_at:expiresAt}),{status:201,headers});
});
