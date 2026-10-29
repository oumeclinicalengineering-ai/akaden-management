-- Tests run ONLY in temporary PostgreSQL. Prior script creates rate_request.
-- Counters are persistent per operation and per REAL reference. No raw QR stored.
-- Regression: modern PostgREST sets JSON claims, NOT the legacy singular GUC.
SET request.jwt.claim.role='';
SET request.jwt.claims='{"role":"service_role"}';
-- Each psql -f runs in its own connection: create local fake references here.
INSERT INTO public.device_enrollment_invites
  (user_id,token_hash,issued_by,expires_at)
VALUES ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',repeat('3',64),
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',now()+interval '10 minutes');
CREATE TEMP TABLE rate_request(id uuid PRIMARY KEY);
INSERT INTO rate_request
SELECT public.start_device_enrollment(repeat('3',64),repeat('4',64),repeat('5',64));


DO $body$
DECLARE n integer;
BEGIN
  IF has_function_privilege('anon','public.consume_qr_enrollment_rate_budget(text,text)','EXECUTE')
    OR has_function_privilege('authenticated','public.consume_qr_enrollment_rate_budget(text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'Browser roles can bypass rate budget RPC';
  END IF;

  -- Malformed or unregistered reference never creates per-reference counter.
  IF public.consume_qr_enrollment_rate_budget('start',repeat('f',64))
  THEN RAISE EXCEPTION 'Unknown QR passed abuse preflight'; END IF;
  SELECT count(*) INTO n FROM app_private.qr_enrollment_rate_budgets
   WHERE action='start' AND scope=repeat('f',64);
  IF n<>0 THEN RAISE EXCEPTION 'Unknown QR allocated a persistent counter'; END IF;
  IF public.consume_qr_enrollment_rate_budget('redeem','12345')
  THEN RAISE EXCEPTION 'Malformed request ID passed abuse preflight'; END IF;

  -- The invite used by previous tests is still valid as a *reference*, even
  -- though its actual enrollment cannot be replayed.
  FOR n IN 1..3 LOOP
    IF NOT public.consume_qr_enrollment_rate_budget('start',repeat('6',64))
    THEN RAISE EXCEPTION 'Start rate budget rejected within allowance'; END IF;
  END LOOP;
  IF public.consume_qr_enrollment_rate_budget('start',repeat('6',64))
  THEN RAISE EXCEPTION '4th start attempt bypassed per-QR rate limit'; END IF;

  -- Simulate the next ten-minute window. No need to wait for real time.
  UPDATE app_private.qr_enrollment_rate_budgets
    SET window_started_at=now()-interval '11 minutes'
  WHERE action='start' AND scope=repeat('6',64);
  IF NOT public.consume_qr_enrollment_rate_budget('start',repeat('6',64))
  THEN RAISE EXCEPTION 'Start rate budget did not reset after window'; END IF;

  FOR n IN 1..6 LOOP
    IF NOT public.consume_qr_enrollment_rate_budget(
       'redeem',(SELECT id::text FROM rate_request))
    THEN RAISE EXCEPTION 'Redeem rate budget rejected within allowance'; END IF;
  END LOOP;
  IF public.consume_qr_enrollment_rate_budget(
      'redeem',(SELECT id::text FROM rate_request))
  THEN RAISE EXCEPTION '7th redeem attempt bypassed per-request rate limit'; END IF;

  UPDATE app_private.qr_enrollment_rate_budgets
    SET window_started_at=now()-interval '11 minutes'
  WHERE action='redeem' AND scope=(SELECT id::text FROM rate_request);
  IF NOT public.consume_qr_enrollment_rate_budget(
      'redeem',(SELECT id::text FROM rate_request))
  THEN RAISE EXCEPTION 'Redeem rate budget did not reset'; END IF;

  -- Exhaust the GLOBAL start budget, then confirm it resets automatically.
  UPDATE app_private.qr_enrollment_rate_budgets
    SET request_count=120,window_started_at=now()
  WHERE action='start' AND scope='global';
  IF public.consume_qr_enrollment_rate_budget('start',repeat('6',64))
  THEN RAISE EXCEPTION 'global start cap was bypassed'; END IF;

  UPDATE app_private.qr_enrollment_rate_budgets
    SET window_started_at=now()-interval '2 minutes'
  WHERE action='start' AND scope='global';
  IF NOT public.consume_qr_enrollment_rate_budget('start',repeat('6',64))
  THEN RAISE EXCEPTION 'global start cap did not reset'; END IF;

  UPDATE app_private.qr_enrollment_rate_budgets
    SET request_count=90,window_started_at=now()
  WHERE action='redeem' AND scope='global';
  IF public.consume_qr_enrollment_rate_budget(
    'redeem',(SELECT id::text FROM rate_request))
  THEN RAISE EXCEPTION 'global redeem cap was bypassed'; END IF;

  -- Private rate counters are not exposed to browsers.
  IF has_table_privilege('anon','app_private.qr_enrollment_rate_budgets','SELECT')
    OR has_table_privilege('authenticated','app_private.qr_enrollment_rate_budgets','SELECT') THEN
    RAISE EXCEPTION 'Rate counter tables exposed to browsers';
  END IF;
END;
$body$;

SELECT 'PASS: rate budget caps, window reset, no unknown-reference table growth, private RPC' AS result;

-- These service-only transitions must recognize the same modern JSON claim.
-- A missing request must return no result/false rather than 'server only'.
DO $modern_claims$
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN
   RAISE EXCEPTION 'JSON role not recognized';
 END IF;
 IF EXISTS (SELECT 1 FROM public.claim_approved_face_to_face_auth(
   '00000000-0000-4000-8000-000000000000',repeat('a',64))) THEN
   RAISE EXCEPTION 'unknown request claimed';
 END IF;
 IF public.finalize_approved_device_enrollment(
   '00000000-0000-4000-8000-000000000000',repeat('a',64),
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
   '00000000-0000-4000-8000-000000000001') THEN
   RAISE EXCEPTION 'unknown request finalized';
 END IF;
 -- GRANT checks remain primary; defense-in-depth rejects a wrong JSON role
 -- even when called as the test superuser.
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 BEGIN
   PERFORM public.consume_qr_enrollment_rate_budget('start',repeat('a',64));
   RAISE EXCEPTION 'non-service JSON role accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END;
$modern_claims$;
SELECT 'PASS: service RPCs support JSON claims and reject non-service JSON roles' AS result;
