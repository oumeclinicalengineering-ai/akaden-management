-- Execute with psql -v ON_ERROR_STOP=1. Fail fast on assertions.
DO $$
DECLARE v_count integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
    WHERE c.relname='orders' AND t.tgname='orders_quantity_receipt_guard' AND NOT t.tgisinternal
  ) THEN RAISE EXCEPTION 'quantity guard trigger not installed'; END IF;

  IF has_function_privilege('anon','public.is_admin()','EXECUTE')
     OR has_function_privilege('anon','public.is_active_user()','EXECUTE') THEN
    RAISE EXCEPTION 'anonymous can execute authorization helpers';
  END IF;
  IF NOT has_function_privilege('authenticated','public.is_admin()','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.is_active_user()','EXECUTE') THEN
    RAISE EXCEPTION 'RLS helpers lost authenticated execute privilege';
  END IF;
  IF has_function_privilege('anon','public.record_audit()','EXECUTE')
     OR has_function_privilege('authenticated','public.record_audit()','EXECUTE')
     OR has_function_privilege('anon','public.create_profile_for_user()','EXECUTE')
     OR has_function_privilege('authenticated','public.create_profile_for_user()','EXECUTE') THEN
    RAISE EXCEPTION 'trigger-only functions still expose direct EXECUTE';
  END IF;

  -- An update below the received total must fail with check_violation.
  BEGIN
    UPDATE public.orders SET quantity=2
    WHERE id='11111111-1111-4111-8111-111111111111';
    RAISE EXCEPTION 'update below received total unexpectedly succeeded';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS: quantity below receipts rejected';
  END;

  SELECT quantity INTO v_count FROM public.orders
   WHERE id='11111111-1111-4111-8111-111111111111';
  IF v_count<>5 THEN RAISE EXCEPTION 'rejected update changed stored quantity'; END IF;

  UPDATE public.orders SET quantity=3 WHERE id='11111111-1111-4111-8111-111111111111';
  SELECT quantity INTO v_count FROM public.orders
    WHERE id='11111111-1111-4111-8111-111111111111';
  IF v_count<>3 THEN RAISE EXCEPTION 'equal received total was rejected'; END IF;

  UPDATE public.orders SET quantity=8 WHERE id='11111111-1111-4111-8111-111111111111';
  SELECT COUNT(*) INTO v_count FROM public.audit_events WHERE object_name='orders' AND action_name='UPDATE';
  IF v_count<>2 THEN RAISE EXCEPTION 'audit trigger failed (% events)',v_count; END IF;
END
$$;

SET ROLE authenticated;
SELECT public.is_admin(), public.is_active_user();
INSERT INTO public.fake_auth_users(id) VALUES('33333333-3333-4333-8333-333333333333');
RESET ROLE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE user_id='33333333-3333-4333-8333-333333333333'
  ) THEN RAISE EXCEPTION 'profile creation trigger failed after EXECUTE revoke'; END IF;
END
$$;

SELECT 'PASS: all isolated hardening assertions' AS result;
