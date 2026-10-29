-- DRAFT ONLY: operator-assisted recovery when an administrator loses the
-- final approved handset. NEVER AUTO-APPLY TO THE CONNECTED SUPABASE PROJECT.
-- Requires 20261029_device_sessions_DRAFT.sql and
-- 20261029_admin_bootstrap_DRAFT.sql, with a completed initial bootstrap.
-- This function is not callable through PostgREST or an Edge Function.
-- A project owner with the SQL Editor must confirm the administrator's
-- identity, the NEW device, a fresh Supabase Auth session and a support ticket.
BEGIN;
CREATE TABLE IF NOT EXISTS app_private.admin_recovery_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  admin_user_id uuid NOT NULL REFERENCES auth.users(id),
  replacement_session_id uuid NOT NULL UNIQUE,
  prior_active_session_count integer NOT NULL CHECK(prior_active_session_count >= 0),
  reason_code text NOT NULL CHECK(reason_code IN ('DEVICE_LOST','DEVICE_UNUSABLE')),
  ticket_reference text NOT NULL CHECK(ticket_reference ~ '^[A-Za-z0-9._/-]{4,80}$'),
  operator_attestation boolean NOT NULL CHECK(operator_attestation IS TRUE),
  performed_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE app_private.admin_recovery_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON app_private.admin_recovery_events FROM PUBLIC,anon,authenticated,service_role;
-- Labels allow investigation to distinguish an operator-initiated recovery
-- from a normal administrator-triggered device revocation. Existing revoked_by
-- is a compatibility column: on SQL Editor recovery it stores the admin's ID,
-- while the ticket is the authoritative record of which operator approved it.
ALTER TABLE app_private.approved_device_sessions
  ADD COLUMN IF NOT EXISTS revocation_source text NOT NULL DEFAULT 'ADMIN_UI';
DO $constraint$
BEGIN
 IF NOT EXISTS (
   SELECT 1 FROM pg_constraint
   WHERE conname = 'approved_device_sessions_revocation_source_check'
     AND conrelid = 'app_private.approved_device_sessions'::regclass
 ) THEN
  ALTER TABLE app_private.approved_device_sessions
    ADD CONSTRAINT approved_device_sessions_revocation_source_check
    CHECK (revocation_source IN ('ADMIN_UI','SQL_EDITOR_RECOVERY'));
 END IF;
END;
$constraint$;

CREATE OR REPLACE FUNCTION app_private.recover_administrator_device(
  p_admin_user_id uuid,
  p_new_session_id uuid,
  p_reason_code text,
  p_ticket_reference text,
  p_operator_attested boolean
) RETURNS TABLE (recovery_event_id bigint, prior_sessions_revoked integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
DECLARE
  v_count integer;
  v_recovery_id bigint;
BEGIN
  IF p_operator_attested IS DISTINCT FROM TRUE OR p_admin_user_id IS NULL
      OR p_new_session_id IS NULL
      OR p_reason_code NOT IN ('DEVICE_LOST','DEVICE_UNUSABLE')
      OR p_reason_code IS NULL
      OR p_ticket_reference IS NULL
      OR p_ticket_reference !~ '^[A-Za-z0-9._/-]{4,80}$' THEN
    RAISE EXCEPTION 'Explicit operator verification and ticket reference required'
      USING ERRCODE='22023';
  END IF;

  -- This function is for RECOVERY after a previously approved first admin,
  -- not an alternate way to grant arbitrary staff their first admin rights.
  IF NOT EXISTS(SELECT 1 FROM app_private.admin_bootstrap_receipt) THEN
    RAISE EXCEPTION 'Initial administrator enrollment has not been completed'
      USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM app_private.approved_device_sessions
    WHERE user_id=p_admin_user_id
  ) THEN
    RAISE EXCEPTION 'Target administrator never had an approved device'
      USING ERRCODE='22023';
  END IF;

  -- The replacement login must be an authentic, still present Auth session
  -- belonging to an ACTIVE admin; a caller-provided UUID alone is insufficient.
  IF NOT EXISTS(
    SELECT 1 FROM auth.sessions s
    JOIN public.profiles p ON p.user_id=s.user_id
    WHERE s.id=p_new_session_id AND s.user_id=p_admin_user_id
      AND (s.not_after IS NULL OR s.not_after > now())
      AND p.active IS TRUE AND p.role='admin'
  ) THEN
    RAISE EXCEPTION 'No active matching administrator Auth session'
      USING ERRCODE='22023';
  END IF;

  -- Serialize operator recovery against admin UI revocation and another
  -- operator recovery. A second call with the same session cannot replay.
  LOCK TABLE app_private.approved_device_sessions IN SHARE ROW EXCLUSIVE MODE;
  IF EXISTS(
    SELECT 1 FROM app_private.approved_device_sessions
    WHERE session_id=p_new_session_id
  ) THEN
    RAISE EXCEPTION 'Replacement session was already registered'
      USING ERRCODE='23505';
  END IF;

  -- The previous sessions of THIS admin are revoked atomically before allowing
  -- the replacement. Another administrator or staff device is not touched.
  UPDATE app_private.approved_device_sessions
  SET revoked_at=now(),
      revoked_by=p_admin_user_id,
      revocation_source='SQL_EDITOR_RECOVERY'
  WHERE user_id=p_admin_user_id AND revoked_at IS NULL;
  GET DIAGNOSTICS v_count=ROW_COUNT;

  INSERT INTO app_private.approved_device_sessions(session_id,user_id,enrolled_by)
  VALUES(p_new_session_id,p_admin_user_id,p_admin_user_id);
  INSERT INTO app_private.device_security_events(event_type,user_id,session_id,actor_id)
  VALUES('DEVICE_ENROLLED',p_admin_user_id,p_new_session_id,p_admin_user_id);
  INSERT INTO app_private.admin_recovery_events(
    admin_user_id,replacement_session_id,prior_active_session_count,
    reason_code,ticket_reference,operator_attestation
  ) VALUES (
    p_admin_user_id,p_new_session_id,v_count,
    p_reason_code,p_ticket_reference,TRUE
  ) RETURNING id INTO v_recovery_id;
  RETURN QUERY SELECT v_recovery_id,v_count;
END;
$body$;
REVOKE ALL ON FUNCTION app_private.recover_administrator_device(uuid,uuid,text,text,boolean)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION app_private.recover_administrator_device(uuid,uuid,text,text,boolean)
  TO postgres;
COMMIT;

-- This does NOT terminate refresh tokens in Supabase Auth; it immediately
-- prevents access only through policies and RPCs checking the approved
-- device allowlist. The recovery runbook must separately handle Auth sessions.
-- See docs/VER6_ADMIN_DEVICE_RECOVERY_RUNBOOK_20261029.md.
