-- Synthetic receipt contract for disposable databases ONLY; not live RPC code.
CREATE FUNCTION public.test_receipt_change(p_id uuid, p_delta integer) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_qty integer; v_total bigint;
BEGIN
  SELECT quantity INTO STRICT v_qty FROM public.orders
    WHERE id='11111111-1111-4111-8111-111111111111' FOR UPDATE;
  SELECT coalesce(sum(quantity),0) INTO v_total FROM public.receipts;
  IF v_total+p_delta>v_qty OR v_total+p_delta<0 THEN
    RAISE EXCEPTION 'receipt total out of bounds' USING ERRCODE='23514';
  END IF;
  IF EXISTS(SELECT 1 FROM public.receipts WHERE id=p_id) THEN
    UPDATE public.receipts SET quantity=quantity+p_delta WHERE id=p_id;
  ELSE
    INSERT INTO public.receipts(id,order_id,quantity)
      VALUES(p_id,'11111111-1111-4111-8111-111111111111',p_delta);
  END IF;
END $$;
CREATE FUNCTION public.test_receipt_cancel(p_id uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM 1 FROM public.orders
    WHERE id='11111111-1111-4111-8111-111111111111' FOR UPDATE;
  DELETE FROM public.receipts WHERE id=p_id;
END $$;
CREATE TRIGGER receipts_audit AFTER INSERT OR UPDATE OR DELETE ON public.receipts
FOR EACH ROW EXECUTE FUNCTION public.record_audit();
