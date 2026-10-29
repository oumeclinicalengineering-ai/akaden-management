// Real local GoTrue HTTP only. No business schema or mock authorization.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const base=process.env.LOCAL_API_URL;
assert.equal(base,'http://127.0.0.1:54321','REFUSED: non-local Auth endpoint');
const anon=process.env.LOCAL_ANON_KEY, admin=process.env.LOCAL_SERVICE_ROLE_KEY;
assert.ok(anon && admin,'Missing disposable local keys');
async function request(path,method,key,token,body){
 const response=await fetch(base+'/auth/v1'+path,{method,redirect:'error',headers:{apikey:key,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
 let data={};try{data=await response.json()}catch{}
 return {ok:response.ok,data};
}
const users=[];
let checks=0;
try{
 for(let i=0;i<2;i++){
  const email=`local-ver6-${randomUUID()}@example.invalid`,password=randomUUID()+'Aa1!';
  const created=await request('/admin/users','POST',admin,admin,{email,password,email_confirm:true});
  assert.ok(created.ok && created.data.id,'Local fictional user creation failed');users.push(created.data.id);
  const login=await request('/token?grant_type=password','POST',anon,anon,{email,password});
  assert.ok(login.ok && login.data.user?.id===created.data.id && login.data.refresh_token,'Password login failed');checks++;
  // Serialized session is kept in memory only; no tokens written to files/logs.
  const saved=JSON.parse(JSON.stringify(login.data));
  const restored=await request('/user','GET',anon,saved.access_token);
  assert.ok(restored.ok && restored.data.id===created.data.id,'Saved access session restoration failed');checks++;
  const refreshed=await request('/token?grant_type=refresh_token','POST',anon,anon,{refresh_token:saved.refresh_token});
  assert.ok(refreshed.ok && refreshed.data.user?.id===created.data.id,'Refresh session restoration failed');checks++;
  const logout=await request('/logout?scope=global','POST',anon,refreshed.data.access_token);
  assert.ok(logout.ok,'Logout failed');checks++;
  const revoked=await request('/token?grant_type=refresh_token','POST',anon,anon,{refresh_token:refreshed.data.refresh_token});
  assert.equal(revoked.ok,false,'Refresh session survived logout');checks++;
 }
 assert.notEqual(users[0],users[1],'Two users must be independent');checks++;
 console.log(`PASS: ${checks} local Auth checks, two fictional users; no business RLS/RPC tested`);
}finally{
 for(const id of users){const removed=await request('/admin/users/'+id,'DELETE',admin,admin);assert.ok(removed.ok,'Local user cleanup failed')}
}
