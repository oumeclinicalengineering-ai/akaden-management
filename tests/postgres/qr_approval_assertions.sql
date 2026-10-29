-- Read-only-by-design isolated fixtures; all data fictional in temporary Postgres.
-- Requires fixture.sql, device_fixture.sql, device invites, sessions and
-- approval migration (plus RLS cutover) in this order.

-- Bootstrap the administrator's pre-approved session using a trusted actor.
SET request.jwt.claim.role='service_role';
SELECT public.register_approved_device_session(
 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

INSERT INTO public.device_enrollment_invites
 (user_id,token_hash,issued_by,expires_at)
VALUES
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',repeat('a',64),
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',now()+interval '10 minutes'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',repeat('d',64),
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',now()+interval '10 minutes');


-- Expired and manually revoked QR invitations must never start enrollment.
INSERT INTO public.device_enrollment_invites
 (user_id,token_hash,issued_by,created_at,expires_at)
VALUES ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',repeat('1',64),
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 now()-interval '30 minutes',now()-interval '20 minutes');
INSERT INTO public.device_enrollment_invites
 (user_id,token_hash,issued_by,expires_at,revoked_at)
VALUES ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',repeat('2',64),
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 now()+interval '10 minutes',now());

DO $
BEGIN
 BEGIN
  PERFORM public.start_device_enrollment(repeat('1',64),repeat('3',64),repeat('4',64));
  RAISE EXCEPTION 'expired invite was accepted';
 EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS: expired invite denied';
 END;
 BEGIN
  PERFORM public.start_device_enrollment(repeat('2',64),repeat('3',64),repeat('4',64));
  RAISE EXCEPTION 'revoked invite was accepted';
 EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS: revoked invite denied';
 END;
END $;

CREATE TEMP TABLE test_request (id uuid PRIMARY KEY); 
GRANT SELECT ON test_request TO authenticated;
INSERT INTO test_request
SELECT public.start_device_enrollment(repeat('a',64),repeat('b',64),repeat('c',64));

-- Invite token is single-use: second start must be rejected.
DO $$
BEGIN
 BEGIN
   PERFORM public.start_device_enrollment(repeat('a',64),repeat('b',64),repeat('c',64));
   RAISE EXCEPTION 'reused invite was accepted';
 EXCEPTION WHEN invalid_parameter_value THEN
   RAISE NOTICE 'PASS: reused invitation denied';
 END;
END $$;

-- No approval: the browser secret alone cannot redeem a request.
DO $$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM public.claim_approved_device_enrollment(
   (SELECT id FROM test_request),repeat('b',64));
 IF n<>0 THEN RAISE EXCEPTION 'unapproved request redeemed'; END IF;
END $$;

-- Staff cannot approve their own enrollment.
SET request.jwt.claim.role='authenticated';
SET request.jwt.claim.sub='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
SET request.jwt.claims='{"session_id":"bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb"}';
SET ROLE authenticated;
DO $$
BEGIN
 BEGIN
   PERFORM public.approve_device_enrollment(
      (SELECT id FROM test_request),repeat('c',64));
   RAISE EXCEPTION 'staff approved enrollment';
 EXCEPTION WHEN insufficient_privilege THEN
   RAISE NOTICE 'PASS: staff approval denied';
 END;
END $$;
RESET ROLE;

-- Approved admin verifies the displayed code from the staff handset.
SET request.jwt.claim.sub='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SET request.jwt.claims='{"session_id":"aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"}';
SET ROLE authenticated;
DO $$
DECLARE rid uuid := (SELECT id FROM test_request);
BEGIN
 IF public.approve_device_enrollment(rid, repeat('e',64)) THEN
    RAISE EXCEPTION 'wrong confirmation code accepted';
 END IF;
 IF NOT public.approve_device_enrollment(rid, repeat('c',64)) THEN
    RAISE EXCEPTION 'valid confirmation code rejected';
 END IF;
 IF public.approve_device_enrollment(rid, repeat('c',64)) THEN
    RAISE EXCEPTION 'duplicate approval succeeded';
 END IF;
END $$;
RESET ROLE;

-- Wrong browser secret cannot redeem even after admin approval.
SET request.jwt.claim.role='service_role';
DO $$
DECLARE rid uuid := (SELECT id FROM test_request); n integer;
BEGIN
 SELECT count(*) INTO n FROM public.claim_approved_device_enrollment(rid,repeat('f',64));
 IF n<>0 THEN RAISE EXCEPTION 'wrong browser secret redeemed'; END IF;
 SELECT count(*) INTO n FROM public.claim_approved_device_enrollment(rid,repeat('b',64))
  WHERE target_user_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
 IF n<>1 THEN RAISE EXCEPTION 'approved enrollment proof not redeemable'; END IF;
 SELECT count(*) INTO n FROM public.claim_approved_device_enrollment(rid,repeat('b',64));
 IF n<>0 THEN RAISE EXCEPTION 'approved enrollment redeemed twice'; END IF;
END $$;

-- An incorrect code may be attempted at most 5 times.
CREATE TEMP TABLE locked_request(id uuid PRIMARY KEY); 
GRANT SELECT ON locked_request TO authenticated;
INSERT INTO locked_request
SELECT public.start_device_enrollment(repeat('d',64),repeat('a',64),repeat('b',64));
SET request.jwt.claim.role='authenticated';
SET ROLE authenticated;
DO $$
DECLARE rid uuid := (SELECT id FROM locked_request); n integer;
BEGIN
 FOR n IN 1..5 LOOP
   IF public.approve_device_enrollment(rid,repeat('f',64)) THEN
      RAISE EXCEPTION 'wrong code was accepted';
   END IF;
 END LOOP;
 IF public.approve_device_enrollment(rid,repeat('b',64)) THEN
    RAISE EXCEPTION 'code accepted after max attempts';
 END IF;
END $$;
RESET ROLE;

-- Event metadata is retained without raw QR or browser secrets.
DO $$
DECLARE n_req integer; n_approve integer; n_claim integer;
BEGIN
 SELECT count(*) INTO n_req FROM app_private.device_enrollment_audit WHERE event_type='REQUESTED';
 SELECT count(*) INTO n_approve FROM app_private.device_enrollment_audit WHERE event_type='APPROVED';
 SELECT count(*) INTO n_claim FROM app_private.device_enrollment_audit WHERE event_type='CLAIMED';
 IF n_req<>2 OR n_approve<>1 OR n_claim<>1 THEN
   RAISE EXCEPTION 'enrollment audit incomplete: %/%/%',n_req,n_approve,n_claim;
 END IF;
 IF has_table_privilege('authenticated','app_private.device_enrollment_requests','SELECT') THEN
   RAISE EXCEPTION 'enrollment requests exposed to authenticated role';
 END IF;
 IF has_function_privilege('authenticated',
    'public.claim_approved_device_enrollment(uuid,text)','EXECUTE') THEN
   RAISE EXCEPTION 'claim RPC exposed to browser';
 END IF;
END $$;

SELECT 'PASS: QR invitation single-use, admin face-to-face approval, browser proof and audit' AS result;
