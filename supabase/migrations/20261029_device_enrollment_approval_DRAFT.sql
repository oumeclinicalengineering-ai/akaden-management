-- STAGING DRAFT ONLY: do not apply to live Supabase.
-- Requires device_enrollment_invites_DRAFT.sql and device_sessions_DRAFT.sql.
-- This implements request, admin approval, and one-time proof redemption.
-- These RPCs do NOT issue Supabase Auth sessions or authenticate QR possession.
BEGIN;

CREATE TABLE IF NOT EXISTS app_private.device_enrollment_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invite_id uuid NOT NULL UNIQUE REFERENCES public.device_enrollment_invites(id),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  browser_secret_hash text NOT NULL CHECK(browser_secret_hash ~ '^[a-f0-9]{64}$'),
  confirmation_code_hash text NOT NULL CHECK(confirmation_code_hash ~ '^[a-f0-9]{64}$'),
  requested_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  approval_attempts integer NOT NULL DEFAULT 0 CHECK(approval_attempts BETWEEN 0 AND 5),
  approved_by uuid REFERENCES auth.users(id),
  approved_at timestamptz,
  consumed_at timestamptz,
  CHECK ((approved_at IS NULL) = (approved_by IS NULL))
);
CREATE TABLE IF NOT EXISTS app_private.device_enrollment_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id uuid NOT NULL REFERENCES app_private.device_enrollment_requests(id),
  event_type text NOT NULL CHECK(event_type IN ('REQUESTED','APPROVED','CLAIMED')),
  actor_id uuid REFERENCES auth.users(id),
  occurred_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE app_private.device_enrollment_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON app_private.device_enrollment_audit FROM PUBLIC, anon, authenticated;

ALTER TABLE app_private.device_enrollment_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON app_private.device_enrollment_requests FROM PUBLIC, anon, authenticated;
CREATE INDEX IF NOT EXISTS device_enrollment_requests_target_idx
 ON app_private.device_enrollment_requests(user_id,requested_at DESC);

-- ONLY trusted Edge Function; hash the invite token and browser secret in server code.
-- The randomly generated confirmation code is shown on the staff device and
-- typed by the in-person administrator; never place it in the QR.
CREATE OR REPLACE FUNCTION public.start_device_enrollment(
  p_invite_hash text, p_browser_secret_hash text, p_confirmation_code_hash text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
DECLARE
  v_id uuid;
  v_invite_id uuid;
  v_user_id uuid;
  v_expires_at timestamptz;
BEGIN
  IF current_setting('request.jwt.claim.role',true) IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'server only' USING ERRCODE='42501';
  END IF;
  IF p_invite_hash !~ '^[a-f0-9]{64}$'
    OR p_browser_secret_hash !~ '^[a-f0-9]{64}$'
    OR p_confirmation_code_hash !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'invalid request' USING ERRCODE='22023';
  END IF;

  UPDATE public.device_enrollment_invites
    SET consumed_at=now()
    WHERE token_hash=p_invite_hash
      AND consumed_at IS NULL
      AND revoked_at IS NULL
      AND expires_at>now()
    RETURNING id,user_id,expires_at INTO v_invite_id,v_user_id,v_expires_at;

  IF NOT FOUND THEN
    RAISE EXCEPTION '招待が無効です。管理者に再発行を依頼してください'
      USING ERRCODE='22023';
  END IF;
  INSERT INTO app_private.device_enrollment_requests
    (invite_id,user_id,browser_secret_hash,confirmation_code_hash,expires_at)
  VALUES(v_invite_id,v_user_id,p_browser_secret_hash,p_confirmation_code_hash,
    LEAST(v_expires_at,now()+interval '10 minutes'))
  RETURNING id INTO v_id;
  INSERT INTO app_private.device_enrollment_audit(request_id,event_type)
    VALUES(v_id,'REQUESTED');
  RETURN v_id;
END;
$body$;
REVOKE ALL ON FUNCTION public.start_device_enrollment(text,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.start_device_enrollment(text,text,text)
  TO service_role;

-- The admin must be using their own pre-approved device. The typed code is
-- checked server-side and only 5 attempts are permitted.
CREATE OR REPLACE FUNCTION public.approve_device_enrollment(
  p_request_id uuid, p_confirmation_code_hash text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin()
    OR NOT app_private.has_approved_device_session() THEN
    RAISE EXCEPTION '承認済み端末の管理者のみ承認できます' USING ERRCODE='42501';
  END IF;
  IF p_request_id IS NULL OR p_confirmation_code_hash IS NULL
    OR p_confirmation_code_hash !~ '^[a-f0-9]{64}$' THEN
    RETURN false;
  END IF;

  UPDATE app_private.device_enrollment_requests
  SET approved_at=now(),approved_by=auth.uid()
  WHERE id=p_request_id
    AND approved_at IS NULL AND consumed_at IS NULL AND expires_at>now()
    AND approval_attempts<5
    AND confirmation_code_hash=p_confirmation_code_hash;
  IF FOUND THEN
    INSERT INTO app_private.device_enrollment_audit(request_id,event_type,actor_id)
      VALUES(p_request_id,'APPROVED',auth.uid());
    RETURN true;
  END IF;

  UPDATE app_private.device_enrollment_requests
  SET approval_attempts=approval_attempts+1
  WHERE id=p_request_id
    AND approved_at IS NULL AND consumed_at IS NULL AND expires_at>now()
    AND approval_attempts<5;
  RETURN false;
END;
$body$;
REVOKE ALL ON FUNCTION public.approve_device_enrollment(uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_device_enrollment(uuid,text)
  TO authenticated;

-- Called by trusted Edge Function ONLY after approval. This is an atomic
-- single-use claim bound to the 256-bit secret held by the scanning browser.
-- The Edge Function must additionally use a supported Supabase Auth flow
-- and verify target user_id before enrolling any actual session_id.
CREATE OR REPLACE FUNCTION public.claim_approved_device_enrollment(
  p_request_id uuid,p_browser_secret_hash text
) RETURNS TABLE (target_user_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
BEGIN
  IF current_setting('request.jwt.claim.role',true) IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'server only' USING ERRCODE='42501';
  END IF;
  IF p_request_id IS NULL OR p_browser_secret_hash IS NULL
     OR p_browser_secret_hash !~ '^[a-f0-9]{64}$' THEN
    RETURN;
  END IF;
  -- Atomic claim: the actor is a trusted server, not a browser user.
  RETURN QUERY
   UPDATE app_private.device_enrollment_requests r
      SET consumed_at=now()
    WHERE r.id=p_request_id AND r.browser_secret_hash=p_browser_secret_hash
      AND r.approved_at IS NOT NULL AND r.consumed_at IS NULL
      AND r.expires_at>now()
   RETURNING r.user_id;
  IF FOUND THEN
    INSERT INTO app_private.device_enrollment_audit(request_id,event_type)
      VALUES(p_request_id,'CLAIMED');
  END IF;
END;
$body$;
REVOKE ALL ON FUNCTION public.claim_approved_device_enrollment(uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_approved_device_enrollment(uuid,text)
  TO service_role;
COMMIT;

-- Still to be implemented in Edge Functions:
-- - rate limiting and safe browser request handling / CORS
-- - admin UI request selection and visual verification
-- - Supabase Auth magic-link/OTP handling and real user identity proof
-- - session_id binding to approved_device_sessions after verified Auth
-- - failed Auth recovery/reissue
