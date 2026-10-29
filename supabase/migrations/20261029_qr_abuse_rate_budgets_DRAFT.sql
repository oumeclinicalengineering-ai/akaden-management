-- DEVELOPMENT DRAFT ONLY. DO NOT APPLY TO LIVE SUPABASE.
-- Must run AFTER device_enrollment_invites_DRAFT and
-- device_enrollment_approval_DRAFT.
-- Persistent, atomic request budgets for an anonymous Edge Function.
-- This is abuse mitigation, NOT a user authentication or DDoS solution.
-- An adversary can exhaust global capacity and deny service. Platform WAF,
-- network-level blocking and operational monitoring remain necessary.
BEGIN;

CREATE TABLE IF NOT EXISTS app_private.qr_enrollment_rate_budgets (
  action text NOT NULL CHECK (action IN ('start','redeem')),
  scope text NOT NULL,
  window_started_at timestamptz NOT NULL DEFAULT now(),
  request_count integer NOT NULL DEFAULT 1 CHECK (request_count BETWEEN 0 AND 1000),
  PRIMARY KEY (action,scope)
);
ALTER TABLE app_private.qr_enrollment_rate_budgets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON app_private.qr_enrollment_rate_budgets
 FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.consume_qr_enrollment_rate_budget(
  p_action text,p_reference text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
DECLARE
  v_global_limit integer;
  v_per_reference_limit integer;
  v_reference_exists boolean;
  v_updated integer;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'server only' USING ERRCODE='42501';
  END IF;

  IF p_action='start' THEN
    IF p_reference IS NULL OR p_reference !~ '^[a-f0-9]{64}$' THEN
      RETURN false;
    END IF;
    v_global_limit:=120;
    v_per_reference_limit:=3;
  ELSIF p_action='redeem' THEN
    IF p_reference IS NULL OR p_reference !~
      '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' THEN
      RETURN false;
    END IF;
    v_global_limit:=90;
    v_per_reference_limit:=6;
  ELSE
    RETURN false;
  END IF;

  -- One global, transactional minute window per operation. This protects
  -- database work even when request IDs/QR tokens are fabricated or rotated.
  INSERT INTO app_private.qr_enrollment_rate_budgets
    (action,scope,window_started_at,request_count)
  VALUES(p_action,'global',now(),1)
  ON CONFLICT(action,scope) DO UPDATE
    SET request_count = CASE
      WHEN app_private.qr_enrollment_rate_budgets.window_started_at
        <= now()-interval '1 minute' THEN 1
      ELSE app_private.qr_enrollment_rate_budgets.request_count+1
    END,
    window_started_at=CASE
      WHEN app_private.qr_enrollment_rate_budgets.window_started_at
        <= now()-interval '1 minute' THEN now()
      ELSE app_private.qr_enrollment_rate_budgets.window_started_at
    END
  WHERE app_private.qr_enrollment_rate_budgets.window_started_at
        <= now()-interval '1 minute'
     OR app_private.qr_enrollment_rate_budgets.request_count < v_global_limit
  RETURNING request_count INTO v_updated;
  IF NOT FOUND THEN RETURN false; END IF;

  -- Do not allocate per-reference records for random attacker-supplied text.
  IF p_action='start' THEN
    SELECT EXISTS(
      SELECT 1 FROM public.device_enrollment_invites i
       WHERE i.token_hash=p_reference
    ) INTO v_reference_exists;
  ELSE
    SELECT EXISTS(
      SELECT 1 FROM app_private.device_enrollment_requests r
       WHERE r.id=p_reference::uuid
    ) INTO v_reference_exists;
  END IF;
  IF NOT v_reference_exists THEN RETURN false; END IF;

  -- A second budget limits repeated requests for the same real QR/request ID.
  -- The reference for START is SHA-256(QR), never the raw secret.
  INSERT INTO app_private.qr_enrollment_rate_budgets
    (action,scope,window_started_at,request_count)
  VALUES(p_action,p_reference,now(),1)
  ON CONFLICT(action,scope) DO UPDATE
    SET request_count=CASE
      WHEN app_private.qr_enrollment_rate_budgets.window_started_at
        <= now()-interval '10 minutes' THEN 1
      ELSE app_private.qr_enrollment_rate_budgets.request_count+1
    END,
    window_started_at=CASE
      WHEN app_private.qr_enrollment_rate_budgets.window_started_at
        <= now()-interval '10 minutes' THEN now()
      ELSE app_private.qr_enrollment_rate_budgets.window_started_at
    END
  WHERE app_private.qr_enrollment_rate_budgets.window_started_at
        <= now()-interval '10 minutes'
     OR app_private.qr_enrollment_rate_budgets.request_count < v_per_reference_limit
  RETURNING request_count INTO v_updated;
  RETURN FOUND;
END;
$body$;
REVOKE ALL ON FUNCTION public.consume_qr_enrollment_rate_budget(text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.consume_qr_enrollment_rate_budget(text,text)
 TO service_role;

COMMIT;
-- CAUTION: DB counters accumulate one row per real QR/request reference.
-- Before deployment, schedule controlled retention cleanup in SQL Editor,
-- confirm dedicated request rate limits with real load, and enable edge/WAF
-- protections. This does not prevent distributed exhaustion of global quotas.
