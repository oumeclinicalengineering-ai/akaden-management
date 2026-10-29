-- Fictional PostgreSQL-only tests for passwordless, email-free enrollment.
SET request.jwt.claim.role='service_role';
INSERT INTO public.device_enrollment_invites(user_id,token_hash,issued_by,expires_at)
VALUES
('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',repeat('6',64),'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',now()+interval '10 minutes'),
('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',repeat('7',64),'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',now()+interval '10 minutes');

CREATE TEMP TABLE face_request(id uuid PRIMARY KEY);
INSERT INTO face_request SELECT public.start_device_enrollment(repeat('6',64),repeat('8',64),repeat('9',64));
GRANT SELECT ON face_request TO authenticated;

DO $$
DECLARE n int;
BEGIN
 SELECT count(*) INTO n FROM public.claim_approved_face_to_face_auth((SELECT id FROM face_request),repeat('8',64));
 IF n<>0 THEN RAISE EXCEPTION 'unapproved login proof issued'; END IF;
END $$;

SET request.jwt.claim.role='authenticated';
SET ROLE authenticated;
DO $$
BEGIN
 BEGIN
  PERFORM public.claim_approved_face_to_face_auth((SELECT id FROM face_request),repeat('8',64));
  RAISE EXCEPTION 'authenticated user called service-only claim';
 EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS: only service role can claim';
 END;
END $$;
RESET ROLE;
SET request.jwt.claim.sub='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SET request.jwt.claims='{"session_id":"aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"}';
SET ROLE authenticated;
DO $$
BEGIN
 IF NOT public.approve_device_enrollment((SELECT id FROM face_request),repeat('9',64))
 THEN RAISE EXCEPTION 'face to face approval failed'; END IF;
END $$;
RESET ROLE;
SET request.jwt.claim.role='service_role';
DO $$
DECLARE n int;
BEGIN
 SELECT count(*) INTO n FROM public.claim_approved_face_to_face_auth((SELECT id FROM face_request),repeat('a',64));
 IF n<>0 THEN RAISE EXCEPTION 'wrong 256bit browser proof accepted'; END IF;
 SELECT count(*) INTO n FROM public.claim_approved_face_to_face_auth((SELECT id FROM face_request),repeat('8',64))
  WHERE target_user_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
 IF n<>1 THEN RAISE EXCEPTION 'approved browser not granted one-time exchange'; END IF;
 SELECT count(*) INTO n FROM public.claim_approved_face_to_face_auth((SELECT id FROM face_request),repeat('8',64));
 IF n<>0 THEN RAISE EXCEPTION 'replayed proof succeeded'; END IF;
 IF NOT EXISTS(SELECT 1 FROM app_private.device_enrollment_requests
   WHERE id=(SELECT id FROM face_request) AND credential_claimed_at IS NOT NULL AND consumed_at IS NULL)
 THEN RAISE EXCEPTION 'Auth claim incorrectly marked final device enrolled'; END IF;
END $$;

CREATE TEMP TABLE face_expired(id uuid PRIMARY KEY);
INSERT INTO face_expired SELECT public.start_device_enrollment(repeat('7',64),repeat('c',64),repeat('d',64));
GRANT SELECT ON face_expired TO authenticated;
SET request.jwt.claim.role='authenticated';
SET ROLE authenticated;
DO $$
BEGIN
 IF NOT public.approve_device_enrollment((SELECT id FROM face_expired),repeat('d',64))
 THEN RAISE EXCEPTION 'expired test approval failed'; END IF;
END $$;
RESET ROLE;
SET request.jwt.claim.role='service_role';
UPDATE app_private.device_enrollment_requests SET expires_at=now()-interval '1 minute'
 WHERE id=(SELECT id FROM face_expired);
DO $$
DECLARE n int;
BEGIN
 SELECT count(*) INTO n FROM public.claim_approved_face_to_face_auth((SELECT id FROM face_expired),repeat('c',64));
 IF n<>0 THEN RAISE EXCEPTION 'expired face-to-face approval issued Auth proof'; END IF;
 SELECT count(*) INTO n FROM app_private.device_enrollment_audit WHERE event_type='AUTH_CLAIMED';
 IF n<>1 THEN RAISE EXCEPTION 'Auth claim audit event count expected 1, got %',n; END IF;
 IF has_function_privilege('anon','public.claim_approved_face_to_face_auth(uuid,text)','EXECUTE')
 OR has_function_privilege('authenticated','public.claim_approved_face_to_face_auth(uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'browser roles can execute Auth issuance RPC'; END IF;
END $$;
SELECT 'PASS: no-email Auth claim requires admin, device proof, expiry and single use' AS result;
