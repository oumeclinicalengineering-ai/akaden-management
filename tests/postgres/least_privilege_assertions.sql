-- Post-migration least-privilege regression checks. Fictional DB only.
-- Assert the preview's necessary operations still work, while dangerous DDL-
-- like table privileges and audit-log writes are denied.
DO $body$
DECLARE t text; priv text; role_name text; allowed boolean;
BEGIN
  FOREACH t IN ARRAY ARRAY['orders','receipts','profiles','audit_logs'] LOOP
    FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
      FOREACH priv IN ARRAY ARRAY['TRUNCATE','TRIGGER','REFERENCES','DELETE','MAINTAIN'] LOOP
        EXECUTE format('SELECT has_table_privilege(%L,%L,%L)',
          role_name,'public.'||t,priv) INTO allowed;
        IF allowed THEN
          RAISE EXCEPTION '% still has % on %',role_name,priv,t;
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  FOREACH t IN ARRAY ARRAY['orders','receipts','profiles','audit_logs'] LOOP
    FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE'] LOOP
      EXECUTE format('SELECT has_table_privilege(%L,%L,%L)',
        'anon','public.'||t,priv) INTO allowed;
      IF allowed THEN RAISE EXCEPTION 'anon still can % %',priv,t; END IF;
    END LOOP;
    IF NOT has_table_privilege('service_role','public.'||t,'TRUNCATE') THEN
      RAISE EXCEPTION 'service_role privileges unexpectedly changed on %',t;
    END IF;
  END LOOP;

  IF NOT has_table_privilege('authenticated','public.orders','SELECT')
     OR NOT has_table_privilege('authenticated','public.orders','INSERT')
     OR NOT has_table_privilege('authenticated','public.orders','UPDATE')
     OR NOT has_table_privilege('authenticated','public.receipts','SELECT')
     OR NOT has_table_privilege('authenticated','public.profiles','SELECT')
     OR NOT has_table_privilege('authenticated','public.profiles','UPDATE')
     OR NOT has_table_privilege('authenticated','public.audit_logs','SELECT')
  THEN RAISE EXCEPTION 'Required Ver6 preview permissions were removed'; END IF;

  IF has_table_privilege('authenticated','public.receipts','INSERT')
     OR has_table_privilege('authenticated','public.receipts','UPDATE')
     OR has_table_privilege('authenticated','public.receipts','DELETE')
     OR has_table_privilege('authenticated','public.audit_logs','INSERT')
     OR has_table_privilege('authenticated','public.audit_logs','UPDATE')
     OR has_table_privilege('authenticated','public.audit_logs','DELETE')
     OR has_table_privilege('authenticated','public.profiles','INSERT')
     OR has_table_privilege('authenticated','public.profiles','DELETE')
  THEN RAISE EXCEPTION 'Browser gained unintended write permission'; END IF;

  IF has_table_privilege('anon','public.order_receipt_totals','SELECT')
     OR NOT has_table_privilege('authenticated','public.order_receipt_totals','SELECT')
     OR NOT has_table_privilege('service_role','public.order_receipt_totals','SELECT')
  THEN RAISE EXCEPTION 'Security-invoker view grants are incorrect'; END IF;
END;
$body$;

-- Exercise actual PostgreSQL privileges (not just has_table_privilege).
SET request.jwt.claim.sub='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SET ROLE authenticated;
DO $body$
BEGIN
 BEGIN
  EXECUTE 'TRUNCATE TABLE public.audit_logs';
  RAISE EXCEPTION 'Audit log TRUNCATE was allowed';
 EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS: cannot truncate audit history';
 END;
 BEGIN
  INSERT INTO public.audit_logs(detail) VALUES('spoofed audit');
  RAISE EXCEPTION 'Audit log INSERT was allowed';
 EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS: cannot fake an audit entry';
 END;
 BEGIN
  DELETE FROM public.orders;
  RAISE EXCEPTION 'Order hard DELETE was allowed';
 EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS: no hard DELETE through browser';
 END;
 BEGIN
  INSERT INTO public.receipts(id,order_id,quantity) VALUES(
    '33333333-3333-4333-8333-333333333333',
    '11111111-1111-4111-8111-111111111111',1);
  RAISE EXCEPTION 'Direct receipt INSERT bypassed receipt RPC';
 EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS: direct receipt insert denied';
 END;
END;
$body$;

-- Check actual Ver6 read/new-order/edit workflows remain functional.
SELECT count(*) AS visible_orders FROM public.orders;
SELECT count(*) AS visible_receipts FROM public.receipts;
SELECT count(*) AS visible_profiles FROM public.profiles;
SELECT count(*) AS visible_audits FROM public.audit_logs;
INSERT INTO public.orders(id,quantity,created_by)
VALUES('44444444-4444-4444-8444-444444444444',2,
       'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
UPDATE public.orders SET quantity=4
 WHERE id='44444444-4444-4444-8444-444444444444';
UPDATE public.profiles SET display_name='合成テスト管理者'
 WHERE user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
RESET ROLE;

DO $body$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM public.orders
  WHERE id='44444444-4444-4444-8444-444444444444' AND quantity=4;
 IF n<>1 THEN RAISE EXCEPTION 'New order/edit was broken'; END IF;
 SELECT count(*) INTO n FROM public.audit_events
  WHERE object_name='orders' AND action_name='UPDATE';
 IF n<>1 THEN RAISE EXCEPTION 'Order update did not trigger audit'; END IF;
 SELECT count(*) INTO n FROM public.audit_logs;
 IF n<>1 THEN RAISE EXCEPTION 'Original audit log changed unexpectedly'; END IF;
END;
$body$;
SELECT 'PASS: least-privilege revokes TRUNCATE and preserves order, audit, profile, receipt reads' AS result;
