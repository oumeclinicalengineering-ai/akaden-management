-- Checks the EXISTING isolated DRAFT fixture, NOT live RLS or Auth.
-- Do not invent staff/admin/inactive policies from audit summaries.
BEGIN;
UPDATE public.orders SET quantity=5;
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    UPDATE public.orders SET quantity=2;
    RAISE EXCEPTION 'authenticated bypassed draft quantity guard';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  UPDATE public.orders SET quantity=3;
  IF (SELECT quantity FROM public.orders)<>3 THEN
    RAISE EXCEPTION 'authenticated could not update to received total';
  END IF;
  BEGIN
    UPDATE public.receipts SET quantity=1;
    RAISE EXCEPTION 'authenticated directly changed receipts';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
SET LOCAL ROLE anon;
DO $$
BEGIN
  BEGIN
    UPDATE public.orders SET quantity=4;
    RAISE EXCEPTION 'anon updated orders in draft fixture';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
ROLLBACK;
SELECT 'PASS: draft fixture role assertions (4 checks); real user RLS NOT tested';
