-- STAGING DRAFT. DO NOT APPLY TO CURRENT SUPABASE PROJECT.
-- Requires device_enrollment_approval_DRAFT.sql and all earlier QR migrations.
-- A trusted Edge Function may release ONE Supabase Auth credential ONLY AFTER:
-- face-to-face admin approval, valid unique browser proof, ten-minute expiry,
-- and active staff. No credentials are stored in this table.
-- The server calls auth.admin.generateLink({type:'magiclink', email:...})
-- AFTER this atomic claim. If issuing a link fails, issue a NEW QR: never
-- reset a credential_claimed_at value because the outcome may be unknown.
BEGIN;

ALTER TABLE app_private.device_enrollment_requests
  ADD COLUMN IF NOT EXISTS credential_claimed_at timestamptz;

ALTER TABLE app_private.device_enrollment_audit
  DROP CONSTRAINT IF EXISTS device_enrollment_audit_event_type_check;
ALTER TABLE app_private.device_enrollment_audit
  ADD CONSTRAINT device_enrollment_audit_event_type_check
  CHECK(event_type IN ('REQUESTED','APPROVED','AUTH_CLAIMED','CLAIMED'));

CREATE OR REPLACE FUNCTION public.claim_approved_face_to_face_auth(
  p_request_id uuid, p_browser_secret_hash text
) RETURNS TABLE (target_user_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'server only' USING ERRCODE = '42501';
  END IF;
  IF p_request_id IS NULL OR p_browser_secret_hash IS NULL
    OR p_browser_secret_hash !~ '^[a-f0-9]{64}$' THEN RETURN;
  END IF;

  -- UPDATE gives single-use/atomic semantics even with simultaneous calls.
  -- Never return email, Auth OTP, token hash, or credentials via PostgREST.
  RETURN QUERY
  WITH claimed AS (
    UPDATE app_private.device_enrollment_requests r
    SET credential_claimed_at=now()
    FROM public.profiles p
    WHERE r.id=p_request_id
      AND r.browser_secret_hash=p_browser_secret_hash
      AND r.user_id=p.user_id
      AND p.active IS TRUE
      AND p.role='staff'
      AND r.approved_at IS NOT NULL
      AND r.approved_by IS NOT NULL
      AND r.consumed_at IS NULL
      AND r.credential_claimed_at IS NULL
      AND r.expires_at>now()
    RETURNING r.id,r.user_id
  ), logged AS (
    INSERT INTO app_private.device_enrollment_audit(request_id,event_type)
      SELECT c.id,'AUTH_CLAIMED' FROM claimed c
    RETURNING request_id
  )
  SELECT c.user_id FROM claimed c JOIN logged l ON l.request_id=c.id;
END;
$body$;

REVOKE ALL ON FUNCTION public.claim_approved_face_to_face_auth(uuid,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_approved_face_to_face_auth(uuid,text)
  TO service_role;

COMMIT;

-- IMPORTANT:
-- 1. This function DOES NOT create an authenticated session.
-- 2. The Edge Function must call Supabase Auth generateLink on an EXISTING
--    staff email, verify generated user.id matches target_user_id, and expose
--    ONLY the one-time hashed_token to the scanning browser.
-- 3. The browser calls supabase.auth.verifyOtp({
--      token_hash: '<server-issued-hash>', type:'magiclink'
--    }) to obtain a REAL session from Supabase Auth.
-- 4. Only then may the normal finalize_approved_device_enrollment RPC bind
--    the REAL auth.sessions ID, with same original request/browser proof.
-- 5. Never bypass a REAL Supabase Auth session with locally forged JWTs.
