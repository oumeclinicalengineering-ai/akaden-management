-- DRAFT ONLY. DO NOT APPLY TO LIVE DATABASE.
-- Tighten function EXECUTE privilege and protect order qty consistency.
-- Requires staging validation and review of dependent application queries.
BEGIN;

-- Anonymous callers do not need any of these helpers or trigger functions.
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_active_user() FROM PUBLIC, anon;
-- Explicitly retain RLS helper execution for signed-in users, even when a
-- staging project lacks the explicit grants found in the current DB.
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_active_user() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.record_audit() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.create_profile_for_user() FROM PUBLIC, anon, authenticated;
-- These trigger-only functions are invoked internally by PostgreSQL; test
-- their automatic triggers after applying the migration in staging.
-- RLS helpers remain callable by authenticated users; anon stays revoked.
-- Keep authenticated EXECUTE on add/change/cancel receipt: UI relies on these.

CREATE OR REPLACE FUNCTION public.prevent_order_quantity_below_received()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
DECLARE v_received bigint;
BEGIN
  -- The UPDATE already obtains a row lock on the order. The existing receipt
  -- RPCs also lock this order, preventing racing receipt changes.
  SELECT coalesce(sum(r.quantity),0) INTO v_received
    FROM public.receipts r WHERE r.order_id = NEW.id;
  IF NEW.quantity < v_received THEN
    RAISE EXCEPTION '発注数量を受領済数量（%）より少なくできません', v_received
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$body$;
REVOKE EXECUTE ON FUNCTION public.prevent_order_quantity_below_received()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS orders_quantity_receipt_guard ON public.orders;
CREATE TRIGGER orders_quantity_receipt_guard
  BEFORE UPDATE OF quantity ON public.orders
  FOR EACH ROW WHEN (OLD.quantity IS DISTINCT FROM NEW.quantity)
  EXECUTE FUNCTION public.prevent_order_quantity_below_received();

COMMIT;

-- Staging test matrix:
-- 1. Existing order with receipt total N -> UPDATE quantity=N-1 rejects, N succeeds.
-- 2. Two concurrent transactions: receipt insertion vs order qty reduction.
-- 3. Current add_receipt/change_receipt/cancel_receipt still work.
-- 4. Public/anon/authenticated EXECUTE permissions for helpers/trigger functions.
-- 5. Auth sign-up still creates profile and order/receipt auditing still works.
-- 6. No regressions in admin/active-user RLS policy evaluation.
