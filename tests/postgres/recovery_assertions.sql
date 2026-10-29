-- All values are fictional. The approval was done earlier by bootstrap pre_cutover.
-- Set up a second approved administrator and a staff device to ensure recovery
-- does not revoke other people's sessions.
SET request.jwt.claim.role='service_role';
SELECT public.register_approved_device_session(
 'cccccccc-2222-4222-8222-cccccccccccc',
 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
SELECT public.register_approved_device_session(
 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
SET request.jwt.claim.role='authenticated';

DO $$
BEGIN
 IF has_function_privilege('authenticated',
  'app_private.recover_administrator_device(uuid,uuid,text,text,boolean)','EXECUTE') THEN
    RAISE EXCEPTION 'staff could execute emergency recovery';
 END IF;
 IF has_function_privilege('service_role',
  'app_private.recover_administrator_device(uuid,uuid,text,text,boolean)','EXECUTE') THEN
    RAISE EXCEPTION 'Edge Function service role could execute emergency recovery';
 END IF;
 IF has_table_privilege('authenticated','app_private.admin_recovery_events','SELECT') THEN
    RAISE EXCEPTION 'staff can read private operator recovery audit';
 END IF;
END $$;

-- No browser, even with a valid login, can execute the project-owner function.
SET request.jwt.claim.sub='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SET request.jwt.claims='{"session_id":"aaaaaaaa-6666-4666-8666-aaaaaaaaaaaa"}';
SET ROLE authenticated;
DO $$
BEGIN
 BEGIN
  PERFORM app_private.recover_administrator_device(
     'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
     'aaaaaaaa-6666-4666-8666-aaaaaaaaaaaa',
     'DEVICE_LOST','REC-001',TRUE);
  RAISE EXCEPTION 'signed-in browser could execute SQL Editor recovery';
 EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS: unapproved login cannot invoke recovery';
 END;
END $$;
RESET ROLE;
SET ROLE service_role;
DO $$
BEGIN
 BEGIN
  PERFORM app_private.recover_administrator_device(
     'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
     'aaaaaaaa-6666-4666-8666-aaaaaaaaaaaa',
     'DEVICE_LOST','REC-001',TRUE);
  RAISE EXCEPTION 'service_role could invoke SQL Editor recovery';
 EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS: service_role cannot invoke recovery';
 END;
END $$;
RESET ROLE;

-- SQL Editor operator: wrong user/session/ticket/attestation are all refused.
DO $$
BEGIN
 BEGIN
  PERFORM app_private.recover_administrator_device(
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
   'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb','DEVICE_LOST','REC-001',TRUE);
  RAISE EXCEPTION 'staff could be recovered as an admin';
 EXCEPTION WHEN invalid_parameter_value THEN
  RAISE NOTICE 'PASS: staff account refused';
 END;

 BEGIN
  PERFORM app_private.recover_administrator_device(
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'cccccccc-2222-4222-8222-cccccccccccc','DEVICE_LOST','REC-001',TRUE);
  RAISE EXCEPTION 'session of other admin accepted';
 EXCEPTION WHEN invalid_parameter_value THEN
  RAISE NOTICE 'PASS: another admin session refused';
 END;

 BEGIN
  PERFORM app_private.recover_administrator_device(
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'aaaaaaaa-3333-4333-8333-aaaaaaaaaaaa','DEVICE_LOST','REC-001',TRUE);
  RAISE EXCEPTION 'expired Auth session accepted';
 EXCEPTION WHEN invalid_parameter_value THEN
  RAISE NOTICE 'PASS: expired Auth session refused';
 END;

 BEGIN
  PERFORM app_private.recover_administrator_device(
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'aaaaaaaa-6666-4666-8666-aaaaaaaaaaaa','DEVICE_LOST','REC-001',FALSE);
  RAISE EXCEPTION 'unattested operator recovery accepted';
 EXCEPTION WHEN invalid_parameter_value THEN
  RAISE NOTICE 'PASS: missing operator attestation refused';
 END;

 BEGIN
  PERFORM app_private.recover_administrator_device(
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'aaaaaaaa-6666-4666-8666-aaaaaaaaaaaa','DEVICE_LOST','bad ticket',TRUE);
  RAISE EXCEPTION 'bad ticket accepted';
 EXCEPTION WHEN invalid_parameter_value THEN
  RAISE NOTICE 'PASS: invalid ticket refused';
 END;
END $$;

-- A valid, independently verified admin's new Auth session may be recovered.
DO $$
DECLARE v_event bigint; v_revoked integer;
BEGIN
 SELECT recovery_event_id,prior_sessions_revoked
 INTO v_event,v_revoked
 FROM app_private.recover_administrator_device(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'aaaaaaaa-6666-4666-8666-aaaaaaaaaaaa',
  'DEVICE_LOST','REC-001',TRUE);
 IF v_event IS NULL OR v_revoked<>1 THEN
   RAISE EXCEPTION 'recovery event or revoked count incorrect';
 END IF;
 -- A replay of the same session must fail and leave the DB unchanged.
 BEGIN
  PERFORM app_private.recover_administrator_device(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'aaaaaaaa-6666-4666-8666-aaaaaaaaaaaa',
    'DEVICE_LOST','REC-001',TRUE);
  RAISE EXCEPTION 'replacement session reused';
 EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'PASS: recovery cannot reuse a session';
 END;
END $$;

-- Old admin device must lose all RLS access immediately.
SET request.jwt.claim.sub='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SET request.jwt.claims='{"session_id":"aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"}';
SET ROLE authenticated;
DO $$
BEGIN
 IF public.is_admin() OR public.is_active_user() OR
    (SELECT count(*) FROM public.orders)<>0 THEN
   RAISE EXCEPTION 'lost admin device retained DB access';
 END IF;
END $$;
RESET ROLE;

-- Newly verified admin session inherits exactly the intended rights.
SET request.jwt.claims='{"session_id":"aaaaaaaa-6666-4666-8666-aaaaaaaaaaaa"}';
SET ROLE authenticated;
DO $$
BEGIN
 IF NOT public.is_admin() OR (SELECT count(*) FROM public.orders)<>1 THEN
   RAISE EXCEPTION 'new administrator session is locked out';
 END IF;
END $$;
RESET ROLE;

-- Other administrator and staff remain approved.
SET request.jwt.claim.sub='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
SET request.jwt.claims='{"session_id":"cccccccc-2222-4222-8222-cccccccccccc"}';
SET ROLE authenticated;
DO $$
BEGIN
 IF NOT public.is_admin() OR (SELECT count(*) FROM public.orders)<>1 THEN
   RAISE EXCEPTION 'other administrator lost access';
 END IF;
END $$;
RESET ROLE;
SET request.jwt.claim.sub='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
SET request.jwt.claims='{"session_id":"bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb"}';
SET ROLE authenticated;
DO $$
BEGIN
 IF NOT public.is_active_user() OR (SELECT count(*) FROM public.orders)<>1 THEN
   RAISE EXCEPTION 'unrelated staff lost access';
 END IF;
END $$;
RESET ROLE;

DO $$
DECLARE v_events int; v_active_admin int; v_old_lost int;
BEGIN
 SELECT count(*) INTO v_events FROM app_private.admin_recovery_events
 WHERE reason_code='DEVICE_LOST' AND ticket_reference='REC-001';
 SELECT count(*) INTO v_active_admin FROM app_private.approved_device_sessions
 WHERE user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' AND revoked_at IS NULL;
 SELECT count(*) INTO v_old_lost FROM app_private.approved_device_sessions
 WHERE session_id='aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'
   AND revoked_at IS NOT NULL AND revocation_source='SQL_EDITOR_RECOVERY';
 IF v_events<>1 OR v_active_admin<>1 OR v_old_lost<>1 THEN
  RAISE EXCEPTION 'recovery was not atomically audited: %/%/%',
      v_events,v_active_admin,v_old_lost;
 END IF;
END $$;
-- A registered but signed-out OTHER administrator is NOT a viable
-- fallback for revoking the last currently working administrator handset.
DELETE FROM auth.sessions
 WHERE id='cccccccc-2222-4222-8222-cccccccccccc';
SET request.jwt.claim.sub='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SET request.jwt.claims='{"session_id":"aaaaaaaa-6666-4666-8666-aaaaaaaaaaaa"}';
SET ROLE authenticated;
DO $
BEGIN
 BEGIN
   PERFORM public.revoke_enrolled_device('aaaaaaaa-6666-4666-8666-aaaaaaaaaaaa');
   RAISE EXCEPTION 'final working admin device was revoked';
 EXCEPTION WHEN insufficient_privilege THEN
   RAISE NOTICE 'PASS: signed-out backup admin is not counted as active';
 END;
END $;
RESET ROLE;
SELECT 'PASS: operator-only admin recovery, audit, scoped revocation and RLS' AS result;
