-- DEVELOPMENT DRAFT: first administrator device bootstrap, WITHOUT public enrollment.
-- THIS SCRIPT MUST NEVER BE AUTOMATICALLY APPLIED TO THE CURRENT SUPABASE PROJECT.
-- Pre-req: 20261029_device_sessions_DRAFT.sql and existing profiles/auth.sessions.
-- Operator access: Postgres dashboard SQL Editor only, never a browser RPC or Edge Function.
--
-- CAUTION: This script only DEFINES a one-time, operator-controlled function.
-- It does NOT bootstrap any account until a separate SQL Editor call is reviewed.
BEGIN;
CREATE TABLE IF NOT EXISTS app_private.admin_bootstrap_receipt (
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  admin_user_id uuid NOT NULL REFERENCES auth.users(id),
  admin_session_id uuid NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE app_private.admin_bootstrap_receipt ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON app_private.admin_bootstrap_receipt FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SCHEMA app_private FROM service_role;

CREATE OR REPLACE FUNCTION app_private.initialize_first_admin_session(
  p_admin_user_id uuid, p_admin_session_id uuid
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
DECLARE
  v_bootstrapped boolean;
BEGIN
  IF p_admin_user_id IS NULL OR p_admin_session_id IS NULL THEN
    RAISE EXCEPTION 'Admin user ID and verified session ID required'
      USING ERRCODE='22023';
  END IF;

  -- Supabase Auth is authoritative. The session must belong to the active admin.
  IF NOT EXISTS (
    SELECT 1 FROM auth.sessions s
    JOIN public.profiles p ON p.user_id = s.user_id
    WHERE s.id = p_admin_session_id
      AND s.user_id = p_admin_user_id
      AND (s.not_after IS NULL OR s.not_after > now())
      AND p.active IS TRUE AND p.role = 'admin'
  ) THEN
    RAISE EXCEPTION 'No active administrator with matching Supabase Auth session'
      USING ERRCODE='22023';
  END IF;

  -- This is for the FIRST admin, never a general-purpose device approver.
  -- The unique singleton guarantees at most one successful bootstrap,
  -- even when two SQL Editor calls race.
  INSERT INTO app_private.admin_bootstrap_receipt
    (singleton,admin_user_id,admin_session_id)
  SELECT true,p_admin_user_id,p_admin_session_id
   WHERE NOT EXISTS (
      SELECT 1 FROM app_private.approved_device_sessions
   )
  ON CONFLICT (singleton) DO NOTHING
  RETURNING true INTO v_bootstrapped;

  IF NOT COALESCE(v_bootstrapped,false) THEN
    RAISE EXCEPTION 'Admin bootstrap was already completed or a device already exists'
      USING ERRCODE='23505';
  END IF;

  -- Record the approved Auth session and audit in the very same transaction.
  INSERT INTO app_private.approved_device_sessions
     (session_id,user_id,enrolled_by)
  VALUES (p_admin_session_id,p_admin_user_id,p_admin_user_id);
  INSERT INTO app_private.device_security_events
     (event_type,user_id,session_id,actor_id)
  VALUES ('DEVICE_ENROLLED',p_admin_user_id,p_admin_session_id,p_admin_user_id);

  RETURN true;
END;
$body$;

-- Only the SQL Editor's privileged database operator can call the bootstrap.
-- In particular, service_role cannot call this function from Edge Functions.
REVOKE ALL ON FUNCTION app_private.initialize_first_admin_session(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION app_private.initialize_first_admin_session(uuid,uuid)
  TO postgres;
COMMIT;

-- Do not use the SQL Editor to invoke this function without confirming the
-- admin's identity and matching session ID (both are UUIDs, NOT a JWT).
-- Example of a separate, manually reviewed one-time call:
-- SELECT app_private.initialize_first_admin_session(
--   '<verified-admin-user-uuid>'::uuid,
--   '<verified-admin-session-uuid>'::uuid
-- );
-- Even after its call, do NOT apply the full device_cutover migration until
-- ALL exposed RLS/RPCs and a tested rollback have been reviewed.
