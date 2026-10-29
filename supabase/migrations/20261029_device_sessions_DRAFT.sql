-- STAGING DRAFT ONLY: NOT APPLIED TO LIVE SUPABASE.
-- Session allowlist for approved devices. Auth access tokens carry session_id.
-- Verify auth.sessions presence too: an Auth sign-out/session deletion must
-- immediately deny DB access even if a previously signed JWT has not expired.
-- This migration alone does NOT enforce access restrictions; the separate
-- DEVICE_CUTOVER draft must be applied after admin session bootstrap.
-- No browser secret or service_role credentials belong in public source.

BEGIN;
CREATE SCHEMA IF NOT EXISTS app_private;
REVOKE ALL ON SCHEMA app_private FROM PUBLIC, anon, authenticated;
-- Needed solely for RLS's call to a narrowly-scoped function; schema must
-- NOT be listed under Supabase exposed API schemas.
GRANT USAGE ON SCHEMA app_private TO authenticated;

CREATE TABLE IF NOT EXISTS app_private.approved_device_sessions (
  session_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  enrolled_by uuid NOT NULL REFERENCES auth.users(id),
  enrolled_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  revoked_by uuid REFERENCES auth.users(id),
  CHECK ((revoked_at IS NULL AND revoked_by IS NULL)
       OR (revoked_at IS NOT NULL AND revoked_by IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS approved_device_sessions_by_user
  ON app_private.approved_device_sessions(user_id);
ALTER TABLE app_private.approved_device_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON app_private.approved_device_sessions FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS app_private.device_security_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_type text NOT NULL CHECK(event_type IN ('DEVICE_ENROLLED','DEVICE_REVOKED')),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  session_id uuid NOT NULL,
  actor_id uuid NOT NULL REFERENCES auth.users(id),
  occurred_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE app_private.device_security_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON app_private.device_security_events FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION app_private.has_approved_device_session()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $body$
  SELECT EXISTS(
    SELECT 1 FROM app_private.approved_device_sessions s
    JOIN auth.sessions auth_s
      ON auth_s.id = s.session_id AND auth_s.user_id = s.user_id
    WHERE s.user_id = (SELECT auth.uid())
      AND s.session_id::text = (SELECT auth.jwt() ->> 'session_id')
      AND s.revoked_at IS NULL
      AND (auth_s.not_after IS NULL OR auth_s.not_after > now())
  );
$body$;
REVOKE ALL ON FUNCTION app_private.has_approved_device_session() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION app_private.has_approved_device_session() TO authenticated;

-- Enrollment is intentionally SERVICE-ONLY and the narrow RPC is in public\n-- because app_private is not an exposed PostgREST schema. The Edge Function must check:
-- 1) current admin's Supabase Auth identity and authorization,
-- 2) staff's face-to-face registration request / challenge and expiration,
-- 3) verified target's *actual* Supabase Auth session_id,
-- BEFORE calling this function. Do not call for an arbitrary supplied UUID.
CREATE OR REPLACE FUNCTION public.register_approved_device_session(
  p_session_id uuid, p_user_id uuid, p_approver uuid
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'server only' USING ERRCODE='42501';
  END IF;
  IF p_session_id IS NULL OR p_user_id IS NULL OR p_approver IS NULL THEN
    RAISE EXCEPTION 'invalid enrollment' USING ERRCODE='22023';
  END IF;
  INSERT INTO app_private.approved_device_sessions
    (session_id,user_id,enrolled_by)
  VALUES(p_session_id,p_user_id,p_approver);
  INSERT INTO app_private.device_security_events
    (event_type,user_id,session_id,actor_id)
  VALUES('DEVICE_ENROLLED',p_user_id,p_session_id,p_approver);
END;
$body$;
REVOKE ALL ON FUNCTION public.register_approved_device_session(uuid,uuid,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_approved_device_session(uuid,uuid,uuid)
  TO service_role;

-- Admin-initiated revocation. This function will be callable from a signed-in
-- staff browser but both active-admin and approved-device checks are server-side.
CREATE OR REPLACE FUNCTION public.revoke_enrolled_device(p_session_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
DECLARE
  v_target_user_id uuid;
BEGIN
  IF (SELECT auth.uid()) IS NULL OR NOT (SELECT public.is_admin())
      OR NOT (SELECT app_private.has_approved_device_session()) THEN
    RAISE EXCEPTION '管理者の承認済み端末からのみ操作できます' USING ERRCODE='42501';
  END IF;
  -- Serialize simultaneous revocations so two admins cannot each revoke the
  -- other's last active device and accidentally lock out all administrators.
  LOCK TABLE app_private.approved_device_sessions IN SHARE ROW EXCLUSIVE MODE;
  SELECT s.user_id INTO v_target_user_id
  FROM app_private.approved_device_sessions s
  WHERE s.session_id = p_session_id AND s.revoked_at IS NULL;
  IF NOT FOUND THEN RETURN false; END IF;
  IF EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.user_id = v_target_user_id AND p.active AND p.role = 'admin'
  ) AND NOT EXISTS (
    SELECT 1 FROM app_private.approved_device_sessions s
      JOIN public.profiles p ON p.user_id = s.user_id
      JOIN auth.sessions a ON a.id=s.session_id AND a.user_id=s.user_id
    WHERE s.session_id <> p_session_id AND s.revoked_at IS NULL
      AND (a.not_after IS NULL OR a.not_after > now())
      AND p.active AND p.role = 'admin'
  ) THEN
    RAISE EXCEPTION '最後の有効な管理者端末は無効化できません'
      USING ERRCODE = '42501';
  END IF;
  UPDATE app_private.approved_device_sessions
  SET revoked_at = now(), revoked_by = (SELECT auth.uid())
  WHERE session_id = p_session_id AND revoked_at IS NULL;
  INSERT INTO app_private.device_security_events
    (event_type,user_id,session_id,actor_id)
  VALUES('DEVICE_REVOKED',v_target_user_id,p_session_id,(SELECT auth.uid()));
  RETURN true;
END;
$body$;
REVOKE ALL ON FUNCTION public.revoke_enrolled_device(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_enrolled_device(uuid) TO authenticated;
COMMIT;

-- IMPORTANT: Revocation blocks the requests protected by
-- app_private.has_approved_device_session; it does NOT automatically erase
-- the browser's stored access/refresh tokens. Existing RPCs must invoke the
-- cutover's is_active_user()/is_admin() predicates to enforce access denial.
-- This file must never be deployed without completing authorization review.
