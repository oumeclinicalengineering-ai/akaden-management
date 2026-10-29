-- Isolated PostgreSQL 17 Auth-session and completion tests.
-- Must run AFTER qr_approval_assertions.sql with the same test database.
-- No real Supabase credentials or data.
CREATE TABLE IF NOT EXISTS auth.sessions (
 id uuid PRIMARY KEY,
 user_id uuid NOT NULL REFERENCES auth.users(id),
 not_after timestamptz
);
INSERT INTO auth.sessions(id,user_id)
VALUES
 ('bbbbbbbb-4444-4444-8444-bbbbbbbbbbbb','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
 ('aaaaaaaa-5555-4555-8555-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

SET request.jwt.claim.role='service_role';
INSERT INTO public.device_enrollment_invites
 (user_id,token_hash,issued_by,expires_at)
VALUES ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',repeat('e',64),
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',now()+interval '10 minutes');
CREATE TEMP TABLE complete_request(id uuid PRIMARY KEY);
INSERT INTO complete_request
SELECT public.start_device_enrollment(repeat('e',64),repeat('f',64),repeat('9',64));
GRANT SELECT ON complete_request TO authenticated;

-- Before admin approval, finishing must be rejected without consuming request.
DO $$
BEGIN
 IF public.finalize_approved_device_enrollment(
  (SELECT id FROM complete_request),repeat('f',64),
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','bbbbbbbb-4444-4444-8444-bbbbbbbbbbbb') THEN
    RAISE EXCEPTION 'completed before approval';
 END IF;
END $$;

SET request.jwt.claim.role='authenticated';
SET request.jwt.claim.sub='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SET request.jwt.claims='{"session_id":"aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"}';
SET ROLE authenticated;
DO $$
BEGIN
 IF NOT public.approve_device_enrollment((SELECT id FROM complete_request),repeat('9',64))
 THEN RAISE EXCEPTION 'admin approval rejected'; END IF;
END $$;
RESET ROLE;

SET request.jwt.claim.role='service_role';
DO $$
DECLARE v_req uuid:=(SELECT id FROM complete_request);
BEGIN
 IF public.finalize_approved_device_enrollment(v_req,repeat('0',64),
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','bbbbbbbb-4444-4444-8444-bbbbbbbbbbbb')
 THEN RAISE EXCEPTION 'wrong browser secret accepted'; END IF;
 IF public.finalize_approved_device_enrollment(v_req,repeat('f',64),
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-4444-4444-8444-bbbbbbbbbbbb')
 THEN RAISE EXCEPTION 'mismatched user accepted'; END IF;
 IF public.finalize_approved_device_enrollment(v_req,repeat('f',64),
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','aaaaaaaa-5555-4555-8555-aaaaaaaaaaaa')
 THEN RAISE EXCEPTION 'session belonging to another user accepted'; END IF;
 IF public.finalize_approved_device_enrollment(v_req,repeat('f',64),
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','bbbbbbbb-6666-4666-8666-bbbbbbbbbbbb')
 THEN RAISE EXCEPTION 'nonexistent session accepted'; END IF;
 IF NOT public.finalize_approved_device_enrollment(v_req,repeat('f',64),
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','bbbbbbbb-4444-4444-8444-bbbbbbbbbbbb')
 THEN RAISE EXCEPTION 'valid approval and session failed to enroll'; END IF;
 IF public.finalize_approved_device_enrollment(v_req,repeat('f',64),
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','bbbbbbbb-4444-4444-8444-bbbbbbbbbbbb')
 THEN RAISE EXCEPTION 'completion reused'; END IF;
END $$;
-- Staff receives RLS access ONLY for the approved, real Auth session.
SET request.jwt.claim.role='authenticated';
SET request.jwt.claim.sub='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
SET request.jwt.claims='{"session_id":"bbbbbbbb-4444-4444-8444-bbbbbbbbbbbb"}';
SET ROLE authenticated;
DO $$
BEGIN
 IF NOT public.is_active_user() THEN
   RAISE EXCEPTION 'approved staff session not active';
 END IF;
 IF (SELECT count(*) FROM public.orders) <> 1 THEN
   RAISE EXCEPTION 'approved staff cannot read order via RLS';
 END IF;
END $$;
RESET ROLE;

-- After the administrator revokes that session, staff access is rejected.
SET request.jwt.claim.sub='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SET request.jwt.claims='{"session_id":"aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"}';
SET ROLE authenticated;
DO $$
BEGIN
 IF NOT public.revoke_enrolled_device('bbbbbbbb-4444-4444-8444-bbbbbbbbbbbb')
 THEN RAISE EXCEPTION 'admin revocation failed'; END IF;
END $$;
RESET ROLE;
SET request.jwt.claim.sub='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
SET request.jwt.claims='{"session_id":"bbbbbbbb-4444-4444-8444-bbbbbbbbbbbb"}';
SET ROLE authenticated;
DO $$
BEGIN
 IF public.is_active_user() OR (SELECT count(*) FROM public.orders) <> 0
 THEN RAISE EXCEPTION 'revoked session still has access'; END IF;
END $$;
RESET ROLE;

DO $$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM app_private.device_enrollment_audit
 WHERE event_type='CLAIMED';
 IF n <> 2 THEN RAISE EXCEPTION 'completion audit count mismatch: %',n; END IF;
 SELECT count(*) INTO n FROM app_private.device_security_events
 WHERE event_type='DEVICE_ENROLLED';
 IF n <> 2 THEN RAISE EXCEPTION 'device-enrolled audit count mismatch: %',n; END IF;
 IF has_function_privilege('authenticated','public.finalize_approved_device_enrollment(uuid,text,uuid,uuid)','EXECUTE')
 OR has_function_privilege('anon','public.finalize_approved_device_enrollment(uuid,text,uuid,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'finalization RPC not protected by service role'; END IF;
END $$;
SELECT 'PASS: passwordless session proof, atomic QR enrollment, revocation' AS result;
