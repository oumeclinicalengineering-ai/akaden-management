-- Test ADMIN BOOTSTRAP before device_cutover: all data is fictional.
DO $$
BEGIN
 IF has_function_privilege('authenticated',
     'app_private.initialize_first_admin_session(uuid,uuid)','EXECUTE') THEN
   RAISE EXCEPTION 'authenticated users can bootstrap a new admin device';
 END IF;
 IF has_function_privilege('anon',
     'app_private.initialize_first_admin_session(uuid,uuid)','EXECUTE') THEN
   RAISE EXCEPTION 'anon users can bootstrap a new admin device';
 END IF;
 IF has_function_privilege('service_role',
     'app_private.initialize_first_admin_session(uuid,uuid)','EXECUTE') THEN
   RAISE EXCEPTION 'service_role can bootstrap first admin via Edge API';
 END IF;
END $$;
SET ROLE authenticated;
DO $$
BEGIN
 BEGIN
  PERFORM app_private.initialize_first_admin_session(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa');
  RAISE EXCEPTION 'authenticated unexpectedly permitted to bootstrap';
 EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS: bootstrap denied to authenticated';
 END;
END $$;
RESET ROLE;
SET ROLE service_role;
DO $$
BEGIN
 BEGIN
  PERFORM app_private.initialize_first_admin_session(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa');
  RAISE EXCEPTION 'service_role unexpectedly permitted to bootstrap';
 EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS: bootstrap denied to service_role';
 END;
END $$;
RESET ROLE;
DO $$
BEGIN
 BEGIN
  PERFORM app_private.initialize_first_admin_session(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');
  RAISE EXCEPTION 'staff obtained initial admin rights';
 EXCEPTION WHEN invalid_parameter_value THEN
  RAISE NOTICE 'PASS: staff bootstrap rejected';
 END;
 BEGIN
  PERFORM app_private.initialize_first_admin_session(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');
  RAISE EXCEPTION 'wrong session owner was accepted';
 EXCEPTION WHEN invalid_parameter_value THEN
  RAISE NOTICE 'PASS: mismatched session rejected';
 END;
 BEGIN
  PERFORM app_private.initialize_first_admin_session(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'aaaaaaaa-3333-4333-8333-aaaaaaaaaaaa');
  RAISE EXCEPTION 'expired Auth session was accepted';
 EXCEPTION WHEN invalid_parameter_value THEN
  RAISE NOTICE 'PASS: expired session rejected';
 END;
 IF NOT app_private.initialize_first_admin_session(
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa') THEN
   RAISE EXCEPTION 'valid administrator first session rejected';
 END IF;
 BEGIN
  PERFORM app_private.initialize_first_admin_session(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'aaaaaaaa-4444-4444-8444-aaaaaaaaaaaa');
  RAISE EXCEPTION 'second admin bootstrap succeeded';
 EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'PASS: one-time bootstrap cannot be replayed';
 END;
END $$;
DO $$
DECLARE count_approvals integer; count_events integer; count_receipts integer;
BEGIN
 SELECT count(*) INTO count_approvals FROM app_private.approved_device_sessions;
 SELECT count(*) INTO count_events FROM app_private.device_security_events WHERE event_type='DEVICE_ENROLLED';
 SELECT count(*) INTO count_receipts FROM app_private.admin_bootstrap_receipt;
 IF count_approvals<>1 OR count_events<>1 OR count_receipts<>1 THEN
  RAISE EXCEPTION 'one-time bootstrap not atomic: %/%/%',count_approvals,count_events,count_receipts;
 END IF;
END $$;
SELECT 'PASS: admin bootstrap authenticated, privileged and single-use' AS result;
