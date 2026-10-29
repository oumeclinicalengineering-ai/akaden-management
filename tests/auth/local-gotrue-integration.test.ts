// Actual disposable local GoTrue and PostgREST, not Auth mocks.
// Never test against hospital Supabase project or real staff accounts.
import { createClient } from 'npm:@supabase/supabase-js@2.57.0';
function check(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
Deno.test('Real local GoTrue magiclink -> session -> RLS; replay denied', async () => {
  const url = Deno.env.get('LOCAL_API_URL') ?? '';
  const anonKey = Deno.env.get('LOCAL_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('LOCAL_SERVICE_ROLE_KEY') ?? '';
  const idsFile = Deno.env.get('LOCAL_SESSION_IDS_FILE') ?? '';
  check(url === 'http://127.0.0.1:54321', 'REFUSED: real Auth test must use localhost:54321');
  check(anonKey.length > 30 && serviceKey.length > 30, 'Missing LOCAL credentials');
  check(idsFile.length > 5, 'Missing disposable output path');
  const opts = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } };
  const admin = createClient(url, serviceKey, opts);
  const staff = createClient(url, anonKey, opts);
  const unrelatedBrowser = createClient(url, anonKey, opts);
  const email = 'local-ver6-' + crypto.randomUUID() + '@example.invalid';
  const { data: created, error: createdError } = await admin.auth.admin.createUser({
    email, email_confirm: true,
  });
  check(!createdError && created.user?.id, 'Could not create fictitious confirmed Auth staff');
  const staffId = created.user.id;
  const { data: link, error: linkError } = await admin.auth.admin.generateLink({
    type: 'magiclink', email,
  });
  check(!linkError && link?.user?.id === staffId, 'Real generateLink returned wrong user/error');
  const tokenHash = link.properties?.hashed_token;
  check(typeof tokenHash === 'string' && /^[a-zA-Z0-9_-]{32,128}$/.test(tokenHash),
    'Real GoTrue hashed_token missing/invalid: length=' + (typeof tokenHash === 'string' ? tokenHash.length : 'absent'));
  console.log('Real GoTrue hashed_token shape: length=' + tokenHash.length +
    ', legacyHex64=' + /^[0-9a-f]{64}$/i.test(tokenHash));
  const { data: unauthSession } = await unrelatedBrowser.auth.getSession();
  check(unauthSession.session === null, 'Unapproved browser already had a session');
  const { data: verified, error: verificationError } = await staff.auth.verifyOtp({
    token_hash: tokenHash, type: 'magiclink',
  });
  check(!verificationError && verified?.user?.id === staffId && verified.session,
    'Real GoTrue verifyOtp did not issue a valid Supabase session');
  const session = verified.session;
  check(Boolean(session.access_token && session.refresh_token),
    'Real session is missing access or refresh token');
  const { data: verifiedUser, error: getUserError } = await staff.auth.getUser(session.access_token);
  check(!getUserError && verifiedUser.user?.id === staffId, 'getUser did not validate token identity');
  const jwtPart = session.access_token.split('.')[1];
  check(Boolean(jwtPart), 'Access token has no JWT payload');
  // Claims provide test evidence only. Never authorize by locally parsing JWT.
  const claims: { sub?: string; role?: string; session_id?: string } = JSON.parse(
    atob(jwtPart.replace(/-/g, '+').replace(/_/g, '/'))
  );
  check(claims.sub === staffId && claims.role === 'authenticated', 'JWT identity/role mismatch');
  check(typeof claims.session_id === 'string' && uuid.test(claims.session_id),
    'Real GoTrue JWT missing valid session_id');
  const { error: seedError } = await admin.from('akaden_local_auth_rls_probe')
    .insert({ owner_id: staffId });
  check(!seedError, 'Service role could not insert fake RLS row');
  const { data: anonRows, error: anonError } = await unrelatedBrowser
    .from('akaden_local_auth_rls_probe').select('owner_id');
  check(!anonError && anonRows?.length === 0, 'Anonymous browser bypassed RLS');
  const { data: ownerRows, error: ownerError } = await staff
    .from('akaden_local_auth_rls_probe').select('owner_id');
  check(!ownerError && ownerRows?.length === 1 && ownerRows[0].owner_id === staffId,
    'Official session could not access its RLS-protected row');
  const { data: replayed, error: replayError } = await unrelatedBrowser.auth.verifyOtp({
    token_hash: tokenHash, type: 'magiclink',
  });
  check(Boolean(replayError) && !replayed?.session, 'A second browser reused Auth credential');
  // Only non-secret UUIDs pass to SQL; never write the JWT, refresh token or hashes.
  await Deno.writeTextFile(idsFile, staffId + '\n' + claims.session_id + '\n');
  console.log('PASS real GoTrue: generateLink, verifyOtp, getUser, RLS, replay rejection');
  console.log('NOT tested: QR approval RPCs, device revocation, real mobile browsers');
});
