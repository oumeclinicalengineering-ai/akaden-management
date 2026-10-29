-- Tests for staged session allowlisting, approval bootstrap and revocation.
-- Runs only against PostgreSQL 17 fictional fixture; NOT Supabase Auth integration.
SET request.jwt.claim.sub='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SET request.jwt.claims='{"session_id":"aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"}';
SET request.jwt.claim.role='authenticated';

-- Before approved sessions are registered, all reads through RLS must be blocked.
SET ROLE authenticated;
DO $$
BEGIN
 IF (SELECT count(*) FROM public.orders) <> 0 THEN
   RAISE EXCEPTION 'unapproved admin session could read orders';
 END IF;
 IF (SELECT app_private.has_approved_device_session()) THEN
   RAISE EXCEPTION 'unapproved session considered approved';
 END IF;
END $$;
RESET ROLE;

-- Register admin and staff sessions using a trusted server-only operation.
SET request.jwt.claim.role='service_role';
SELECT public.register_approved_device_session(
 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
SELECT public.register_approved_device_session(
 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
SET request.jwt.claim.role='authenticated';

SET ROLE authenticated;
DO $$
BEGIN
 IF (SELECT count(*) FROM public.orders) <> 1 THEN
   RAISE EXCEPTION 'approved admin cannot read orders';
 END IF;
 IF NOT (SELECT public.is_admin()) THEN
   RAISE EXCEPTION 'approved admin cannot pass is_admin';
 END IF;
END $$;
RESET ROLE;

-- One active staff session is allowed. Another one with the same user id is not.
SET request.jwt.claim.sub='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
SET request.jwt.claims='{"session_id":"bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb"}';
SET ROLE authenticated;
DO $$
BEGIN
 IF (SELECT count(*) FROM public.orders) <> 1 THEN
   RAISE EXCEPTION 'approved staff cannot read orders';
 END IF;
 IF (SELECT public.is_admin()) THEN
   RAISE EXCEPTION 'staff gained admin permissions';
 END IF;
 BEGIN
   PERFORM public.revoke_enrolled_device('aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa');
   RAISE EXCEPTION 'staff revoked admin session';
 EXCEPTION WHEN insufficient_privilege THEN
   RAISE NOTICE 'PASS: staff cannot revoke admin device';
 END;
END $$;
RESET ROLE;

-- Even if the signed access JWT has not expired, an expired or REMOVED
-- GoTrue Auth session must fail the DB-side allowlist check.
UPDATE auth.sessions SET not_after=now()-interval '1 minute'
 WHERE id='bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
SET ROLE authenticated;
DO $
BEGIN
 IF public.is_active_user() OR (SELECT count(*) FROM public.orders)<>0 THEN
   RAISE EXCEPTION 'expired GoTrue session retained DB access';
 END IF;
END $;
RESET ROLE;
UPDATE auth.sessions SET not_after=NULL
 WHERE id='bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
DELETE FROM auth.sessions
 WHERE id='bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
SET ROLE authenticated;
DO $
BEGIN
 IF public.is_active_user() OR (SELECT count(*) FROM public.orders)<>0 THEN
  RAISE EXCEPTION 'signed-out GoTrue session retained DB access';
 END IF;
END $;
RESET ROLE;
INSERT INTO auth.sessions(id,user_id)
 VALUES('bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');

-- A valid JWT for a DIFFERENT session of the same user is denied.
SET request.jwt.claims='{"session_id":"bbbbbbbb-3333-4333-8333-bbbbbbbbbbbb"}';
SET ROLE authenticated;
DO $$
BEGIN
 IF (SELECT count(*) FROM public.orders) <> 0 THEN
   RAISE EXCEPTION 'unapproved same-user session could read orders';
 END IF;
END $$;
RESET ROLE;

-- Revocation by approved admin succeeds once, is idempotent thereafter.
SET request.jwt.claim.sub='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SET request.jwt.claims='{"session_id":"aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"}';
SET ROLE authenticated;
DO $$
BEGIN
 IF NOT public.revoke_enrolled_device('bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb') THEN
   RAISE EXCEPTION 'admin failed to revoke staff session';
 END IF;
 IF public.revoke_enrolled_device('bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb') THEN
   RAISE EXCEPTION 'second revocation unexpectedly succeeded';
 END IF;
END $$;
RESET ROLE;

-- Previously approved but revoked staff session is immediately blocked in RLS.
SET request.jwt.claim.sub='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
SET request.jwt.claims='{"session_id":"bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb"}';
SET ROLE authenticated;
DO $$
BEGIN
 IF (SELECT count(*) FROM public.orders) <> 0 THEN
   RAISE EXCEPTION 'revoked staff still sees orders via RLS';
 END IF;
 IF (SELECT public.is_active_user()) THEN
   RAISE EXCEPTION 'revoked staff still treated as active';
 END IF;
END $$;
RESET ROLE;

-- Keep an audit trail for BOTH enrollment and revocation.
DO $$
DECLARE n_enrolled integer; n_revoked integer;
BEGIN
 SELECT count(*) INTO n_enrolled FROM app_private.device_security_events WHERE event_type='DEVICE_ENROLLED';
 SELECT count(*) INTO n_revoked FROM app_private.device_security_events WHERE event_type='DEVICE_REVOKED';
 IF n_enrolled<>2 OR n_revoked<>1 THEN
   RAISE EXCEPTION 'security audit counts incorrect: enrolled %, revoked %', n_enrolled,n_revoked;
 END IF;
 IF has_table_privilege('authenticated','app_private.approved_device_sessions','SELECT') THEN
   RAISE EXCEPTION 'authenticated can directly read device session table';
 END IF;
 IF has_function_privilege('anon','public.revoke_enrolled_device(uuid)','EXECUTE') THEN
   RAISE EXCEPTION 'anon can call revoke RPC';
 END IF;
END $$;

SELECT 'PASS: device allowlist, RLS cutover, staff restrictions, immediate revocation, audit' AS result;
