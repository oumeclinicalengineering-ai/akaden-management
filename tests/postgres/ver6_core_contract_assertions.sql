-- Contract summary checks in disposable schema only; not full live schema/RLS.
DO $$
DECLARE q integer;
BEGIN
  FOREACH q IN ARRAY ARRAY[0,-1,100000001] LOOP
    BEGIN
      UPDATE public.orders SET quantity=q;
      RAISE EXCEPTION 'invalid order quantity accepted: %',q;
    EXCEPTION WHEN check_violation THEN NULL;
    END;
  END LOOP;
  UPDATE public.orders SET quantity=100000000;
  IF (SELECT quantity FROM public.orders)<>100000000 THEN
    RAISE EXCEPTION 'contract maximum rejected';
  END IF;
  BEGIN
    UPDATE public.receipts SET quantity=0;
    RAISE EXCEPTION 'zero receipt accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;
SELECT 'PASS: contract quantity bounds (5 checks)';
