-- STAGING DRAFT ONLY. Never run against the currently connected project.
-- Prerequisites: device_enrollment_invites, device_sessions, device_enrollment_approval.
-- This single transaction binds an approved QR request to a REAL Supabase Auth
-- session (auth.sessions) and records the allowed session + audit events.
-- Edge Function must validate access token with auth.getUser(jwt) and compare
-- jwt.sub and jwt.session_id with p_user_id and p_session_id before invoking.
BEGIN;
CREATE OR REPLACE FUNCTION public.finalize_approved_device_enrollment(
  p_request_id uuid, p_browser_secret_hash text, p_user_id uuid, p_session_id uuid
)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
DECLARE
  v_req app_private.device_enrollment_requests%rowtype;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'server only' USING ERRCODE='42501';
  END IF;
  IF p_request_id IS NULL OR p_user_id IS NULL OR p_session_id IS NULL
    OR p_browser_secret_hash IS NULL
    OR p_browser_secret_hash !~ '^[a-f0-9]{64}$' THEN
    RETURN false;
  END IF;
  SELECT * INTO v_req
  FROM app_private.device_enrollment_requests
  WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR v_req.user_id <> p_user_id OR v_req.consumed_at IS NOT NULL
    OR v_req.approved_at IS NULL OR v_req.approved_by IS NULL
    OR v_req.expires_at <= now()
    OR v_req.browser_secret_hash <> p_browser_secret_hash THEN
    RETURN false;
  END IF;
  -- Recheck account status at the state transition, not just at the Edge
  -- request/credential-claim boundary. An account may have been disabled or
  -- changed role after approval; that must not create a newly trusted device.
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE user_id = p_user_id AND active IS TRUE AND role = 'staff'
  ) THEN RETURN false;
  END IF;
  -- Database-side defense: session_id MUST exist and belong to the user.
  IF NOT EXISTS (
    SELECT 1 FROM auth.sessions
    WHERE id = p_session_id AND user_id = p_user_id
      AND (not_after IS NULL OR not_after > now())
  ) THEN RETURN false;
  END IF;
  IF EXISTS (
    SELECT 1 FROM app_private.approved_device_sessions WHERE session_id = p_session_id
  ) THEN RETURN false;
  END IF;
  INSERT INTO app_private.approved_device_sessions(session_id,user_id,enrolled_by)
    VALUES(p_session_id,p_user_id,v_req.approved_by);
  UPDATE app_private.device_enrollment_requests SET consumed_at=now()
    WHERE id=p_request_id;
  INSERT INTO app_private.device_security_events(event_type,user_id,session_id,actor_id)
    VALUES('DEVICE_ENROLLED',p_user_id,p_session_id,v_req.approved_by);
  INSERT INTO app_private.device_enrollment_audit(request_id,event_type,actor_id)
    VALUES(p_request_id,'CLAIMED',v_req.approved_by);
  RETURN true;
END;
$body$;
REVOKE ALL ON FUNCTION public.finalize_approved_device_enrollment(uuid,text,uuid,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_approved_device_enrollment(uuid,text,uuid,uuid)
  TO service_role;
COMMIT;
-- Supersedes claim_approved_device_enrollment. Never call old claim in new code.
-- Before production deployment, remove/deprecate the old claim function in a
-- reviewed migration, and test concurrent requests on the actual Supabase DB.
