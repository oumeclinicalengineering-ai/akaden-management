// Disposable LOCAL Supabase only: real GoTrue, actual Edge handlers and DRAFT RPCs.
// Never log credentials or connect to a cloud project.
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2.57.0';
import { handleFaceToFaceRequest } from '../../supabase/functions/ver6-face-to-face-enrollment/index.ts';
import { handleEnrollmentRequest } from '../../supabase/functions/ver6-enrollment-api/index.ts';
function check(value: unknown, message: string): asserts value {
  if (!value) {
    // Messages are fixed assertions, never SQL, credentials or remote responses.
    // Expose the failed invariant in public CI annotations without requiring logs.
    console.error('::error title=QR full-chain assertion::' + message);
    throw new Error(message);
  }
}
const idPattern = /^[0-9a-f-]{36}$/;
const hex = () => Array.from(crypto.getRandomValues(new Uint8Array(32)), n => n.toString(16).padStart(2, '0')).join('');
const hash = async (value: string) => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))), n => n.toString(16).padStart(2, '0')).join('');
Deno.test('Real admin approval -> one-time QR Auth -> approved device -> revocation', async () => {
  const url = Deno.env.get('LOCAL_API_URL') ?? '';
  const dbUrl = Deno.env.get('LOCAL_DB_URL') ?? '';
  const anon = Deno.env.get('LOCAL_ANON_KEY') ?? '';
  const service = Deno.env.get('LOCAL_SERVICE_ROLE_KEY') ?? '';
  check(url === 'http://127.0.0.1:54321', 'REFUSED non-local Auth URL');
  check(/^postgres(?:ql)?:\/\/[^@]+@127\.0\.0\.1:54322\/postgres(?:\?.*)?$/.test(dbUrl), 'REFUSED non-local database');
  check(anon.length > 30 && service.length > 30, 'Missing disposable credentials');
  const opts = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } };
  const server = createClient(url, service, opts);
  const browser = () => createClient(url, anon, opts);
  let fixtureStep = 0;
  const sql = async (statement: string) => {
    fixtureStep++;
    const child = new Deno.Command('psql', {
      args: ['--dbname', dbUrl, '-X', '-tA', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate'],
      stdin: 'piped', stdout: 'piped', stderr: 'piped',
    }).spawn();
    const writer = child.stdin.getWriter();
    await writer.write(new TextEncoder().encode(statement)); await writer.close();
    const result = await child.output();
    // Avoid printing SQL, credentials, invitation hashes or PostgreSQL diagnostics.
    const state = new TextDecoder().decode(result.stderr).match(/(?:ERROR|FATAL):\s+([0-9A-Z]{5})\b/)?.[1] ?? 'unavailable';
    check(result.success, `Disposable fixture SQL failed at step ${fixtureStep} (SQLSTATE ${state})`);
    return new TextDecoder().decode(result.stdout).trim();
  };
  const newUser = async (role: 'admin' | 'staff') => {
    const email = 'qr-' + crypto.randomUUID() + '@example.invalid';
    const { data, error } = await server.auth.admin.createUser({ email, email_confirm: true });
    check(!error && data.user?.id && idPattern.test(data.user.id), 'Fake user creation failed');
    const id = data.user.id;
    await sql(`INSERT INTO public.profiles(user_id,role,active) VALUES('${id}','${role}',true);`);
    return { id, email };
  };
  const login = async (email: string, client: SupabaseClient) => {
    const { data: link, error } = await server.auth.admin.generateLink({ type: 'magiclink', email });
    check(!error && link.properties?.hashed_token, 'Official magiclink creation failed');
    const { data, error: verifyError } = await client.auth.verifyOtp({ type: 'magiclink', token_hash: link.properties.hashed_token });
    check(!verifyError && data.session, 'Official Auth verification failed');
    const { data: verified, error: userError } = await client.auth.getUser(data.session.access_token);
    check(!userError && verified.user?.id === data.user?.id, 'Official Auth identity verification failed');
    const claims = JSON.parse(atob(data.session.access_token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    check(claims.sub === data.user.id && idPattern.test(claims.session_id), 'Real session claims missing');
    return { jwt: data.session.access_token, sid: claims.session_id as string };
  };
  const manager = await newUser('admin'), staff = await newUser('staff');
  const managerBrowser = browser(), staffBrowser = browser(), unregisteredAdmin = browser();
  const adminSession = await login(manager.email, managerBrowser);
  const rogueAdminSession = await login(manager.email, unregisteredAdmin);
  // The only bootstrap privilege: approve the fixture manager's REAL auth.sessions row.
  await sql(`INSERT INTO app_private.approved_device_sessions(session_id,user_id,enrolled_by)
    SELECT id,user_id,'${manager.id}'::uuid FROM auth.sessions WHERE id='${adminSession.sid}' AND user_id='${manager.id}';
    INSERT INTO public.akaden_local_device_rls_probe(owner_id) VALUES('${staff.id}');`);
  const origin = 'https://qr-test.example.invalid';
  const config: Record<string, string> = { SUPABASE_URL: url, SUPABASE_ANON_KEY: anon,
    SUPABASE_SERVICE_ROLE_KEY: service, QR_ALLOWED_ORIGIN: origin,
    QR_ENROLLMENT_ENABLED: 'true', QR_FACE_TO_FACE_ENABLED: 'true' };
  const env = (key: string) => config[key];
  const request = (body: Record<string, unknown>, jwt?: string) => new Request(origin + '/test', {
    method: 'POST', headers: { origin, 'content-type': 'application/json', ...(jwt ? { authorization: 'Bearer ' + jwt } : {}) }, body: JSON.stringify(body),
  });
  const edge = async (body: Record<string, unknown>, jwt = adminSession.jwt) => {
    const response = await handleEnrollmentRequest(request(body, jwt), { env });
    return { status: response.status, body: await response.json() };
  };
  const face = async (body: Record<string, unknown>) => {
    const response = await handleFaceToFaceRequest(request(body), { env });
    return { status: response.status, body: await response.json() };
  };
  const issue = async () => {
    const result = await edge({ action: 'issue', user_id: staff.id });
    check(result.status === 201 && /^[a-f0-9]{64}$/.test(result.body.token), 'Admin QR issue failed');
    return result.body.token as string;
  };
  const start = async (invite: string, code = '042719') => {
    const secret = hex();
    const result = await face({ action: 'start', invite_token: invite, browser_secret: secret, confirmation_code: code });
    check(result.status === 201 && idPattern.test(result.body.request_id), 'QR enrollment request failed');
    return { id: result.body.request_id as string, secret, code };
  };
  const approve = (req: { id: string; code: string }, code = req.code, jwt = adminSession.jwt) => edge({ action: 'approve', request_id: req.id, confirmation_code: code }, jwt);
  const redeem = (req: { id: string; secret: string }) => face({ action: 'redeem', request_id: req.id, browser_secret: req.secret });
  const invite = await issue(), enrollment = await start(invite);
  check((await face({ action: 'start', invite_token: invite, browser_secret: hex(), confirmation_code: '123456' })).status === 409, 'QR reuse accepted');
  check((await redeem(enrollment)).status === 409, 'Credential released before approval');
  check((await approve(enrollment, enrollment.code, rogueAdminSession.jwt)).status === 403, 'Unregistered manager device approved');
  check((await approve(enrollment, '999999')).status === 409, 'Wrong six-digit code approved');
  check(await sql(`SELECT approval_attempts FROM app_private.device_enrollment_requests WHERE id='${enrollment.id}';`) === '1', 'Wrong-code attempt not persisted');
  check((await approve(enrollment)).status === 200, 'Formal manager Auth approval failed');
  check((await approve(enrollment)).status === 409, 'Repeated approval accepted');
  check((await redeem({ ...enrollment, secret: hex() })).status === 409, 'Wrong browser secret accepted');
  // Concurrent requests must yield precisely one credential, never two.
  const claims = await Promise.all([redeem(enrollment), redeem(enrollment)]);
  check(claims.filter(r => r.status === 200).length === 1 && claims.filter(r => r.status === 409).length === 1, 'Concurrent credential claim not single-use');
  const credential = claims.find(r => r.status === 200)!.body;
  const { data: auth, error: authError } = await staffBrowser.auth.verifyOtp({ type: 'magiclink', token_hash: credential.token_hash });
  check(!authError && auth.user?.id === staff.id && auth.session, 'QR credential did not issue official staff Auth');
  const { data: verified, error: verifiedError } = await staffBrowser.auth.getUser(auth.session.access_token);
  check(!verifiedError && verified.user?.id === staff.id, 'Staff access token identity invalid');
  const sid = JSON.parse(atob(auth.session.access_token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).session_id;
  check(idPattern.test(sid), 'Staff session id missing');
  check(await sql(`SELECT count(*) FROM auth.sessions WHERE id='${sid}' AND user_id='${staff.id}';`) === '1', 'Real staff auth.sessions row missing');
  const { error: replayError, data: replay } = await browser().auth.verifyOtp({ type: 'magiclink', token_hash: credential.token_hash });
  check(replayError && !replay.session, 'QR Auth credential replay accepted');
  const accessRows = async (client: SupabaseClient) => {
    const { data, error } = await client.from('akaden_local_device_rls_probe').select('owner_id');
    check(!error, 'Device RLS request failed'); return data;
  };
  check((await accessRows(staffBrowser)).length === 0, 'Unregistered real Auth session accessed device data');
  const finish = (secret = enrollment.secret, jwt = auth.session!.access_token) => edge({ action: 'finish', request_id: enrollment.id, browser_secret: secret }, jwt);
  check((await finish(hex())).status === 409, 'Wrong browser finalized');
  check((await finish(enrollment.secret, adminSession.jwt)).status === 409, 'Other user finalized staff request');
  const fakeSession = await server.rpc('finalize_approved_device_enrollment', { p_request_id: enrollment.id, p_browser_secret_hash: await hash(enrollment.secret), p_user_id: staff.id, p_session_id: crypto.randomUUID() });
  check(!fakeSession.error && fakeSession.data === false, 'Fabricated session finalized');
  const finishes = await Promise.all([finish(), finish()]);
  check(finishes.filter(r => r.status === 200).length === 1 && finishes.filter(r => r.status === 409).length === 1, 'Concurrent finalize not single-use');
  check((await accessRows(staffBrowser)).length === 1, 'Approved device denied RLS data');
  check((await finish()).status === 409, 'Device double registration accepted');
  const otherStaffBrowser = browser(); await login(staff.email, otherStaffBrowser);
  check((await accessRows(otherStaffBrowser)).length === 0, 'Unapproved second Auth session accessed data');
  check((await edge({ action: 'revoke', session_id: sid }, auth.session.access_token)).status === 403, 'Staff revoked a device');
  check((await edge({ action: 'revoke', session_id: sid })).body.revoked === true, 'Manager device revocation failed');
  check((await staffBrowser.auth.getUser(auth.session.access_token)).data.user?.id === staff.id, 'Revocation test lost valid Auth token unexpectedly');
  check((await accessRows(staffBrowser)).length === 0, 'Revoked device retained data access with valid Auth token');
  check((await edge({ action: 'revoke', session_id: adminSession.sid })).status === 403, 'Last manager device could be revoked');
  check(await sql(`SELECT string_agg(event_type,',' ORDER BY id) FROM app_private.device_enrollment_audit WHERE request_id='${enrollment.id}';`) === 'REQUESTED,APPROVED,AUTH_CLAIMED,CLAIMED', 'Full-chain audit mismatch');
  // Five invitations total exercise expiry/lockout without bypassing the real issuance budget.
  const expiredInvite = await issue();
  await sql(`UPDATE public.device_enrollment_invites SET created_at=now()-interval '20 minutes',expires_at=now()-interval '1 minute' WHERE token_hash='${await hash(expiredInvite)}';`);
  check((await face({ action: 'start', invite_token: expiredInvite, browser_secret: hex(), confirmation_code: '123456' })).status === 409, 'Expired QR accepted');
  const expiredRequest = await start(await issue()); await approve(expiredRequest);
  await sql(`UPDATE app_private.device_enrollment_requests SET expires_at=now()-interval '1 minute' WHERE id='${expiredRequest.id}';`);
  check((await redeem(expiredRequest)).status === 409, 'Expired approval released credential');
  const expiredFinish = await start(await issue());
  check((await approve(expiredFinish)).status === 200, 'Expiry fixture approval failed');
  const expiryCredential = await redeem(expiredFinish);
  check(expiryCredential.status === 200, 'Expiry fixture credential claim failed');
  const { data: expiryAuth, error: expiryError } = await browser().auth.verifyOtp({ type: 'magiclink', token_hash: expiryCredential.body.token_hash });
  check(!expiryError && expiryAuth.session && expiryAuth.user?.id === staff.id, 'Expiry fixture real Auth failed');
  await sql(`UPDATE app_private.device_enrollment_requests SET expires_at=now()-interval '1 minute' WHERE id='${expiredFinish.id}';`);
  check((await edge({ action: 'finish', request_id: expiredFinish.id, browser_secret: expiredFinish.secret }, expiryAuth.session.access_token)).status === 409, 'Expired request registered a device');
  const locked = await start(await issue());
  for (let i = 0; i < 5; i++) check((await approve(locked, '999999')).status === 409, 'Wrong code accepted during lockout');
  check((await approve(locked)).status === 409, 'Correct code accepted after five failures');
  check(await sql(`SELECT approval_attempts FROM app_private.device_enrollment_requests WHERE id='${locked.id}';`) === '5', 'Five-attempt cap missing');
  console.log('PASS: real Edge/GoTrue/PostgreSQL chain; formal manager session and six-digit code; QR reuse/expiry, proof mismatch, concurrent claim/finalize, Auth replay, device RLS/revocation, attempt cap, last-admin protection, audit');
});
