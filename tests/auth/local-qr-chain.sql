-- ISOLATED CI ONLY. Real GoTrue auth.sessions, actual DRAFT enrollment RPCs.
-- Never execute against the hospital Supabase project.
\set ON_ERROR_STOP on
BEGIN;
CREATE SCHEMA IF NOT EXISTS app_private;
CREATE TABLE public.profiles (
 user_id uuid PRIMARY KEY REFERENCES auth.users(id), role text NOT NULL, active boolean NOT NULL DEFAULT true
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION public.is_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$ SELECT EXISTS(SELECT 1 FROM public.profiles p WHERE p.user_id=(SELECT auth.uid()) AND p.role='admin' AND p.active) $$;
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
COMMIT;
\ir ../../supabase/migrations/20261029_device_enrollment_invites_DRAFT.sql
\ir ../../supabase/migrations/20261029_device_sessions_DRAFT.sql
\ir ../../supabase/migrations/20261029_device_enrollment_approval_DRAFT.sql
\ir ../../supabase/migrations/20261029_face_to_face_auth_claim_DRAFT.sql
\ir ../../supabase/migrations/20261029_finalize_device_enrollment_DRAFT.sql
\ir ../../supabase/migrations/20261029_qr_abuse_rate_budgets_DRAFT.sql
-- Prove expected DRAFT functions exist, with restricted grants.
DO $$
BEGIN
 IF to_regprocedure('public.start_device_enrollment(text,text,text)') IS NULL
 OR to_regprocedure('public.approve_device_enrollment(uuid,text)') IS NULL
 OR to_regprocedure('public.claim_approved_face_to_face_auth(uuid,text)') IS NULL
 OR to_regprocedure('public.finalize_approved_device_enrollment(uuid,text,uuid,uuid)') IS NULL
 THEN RAISE EXCEPTION 'Missing enrollment RPC'; END IF;
 IF has_function_privilege('anon','public.claim_approved_face_to_face_auth(uuid,text)','EXECUTE')
 OR has_function_privilege('authenticated','public.finalize_approved_device_enrollment(uuid,text,uuid,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Privileged enrollment RPC exposed'; END IF;
END $$;

-- Authorization regression: untrusted roles must never be able to claim
-- a signed-in credential or register an approved session.
DO $security$
DECLARE
  v_blocked boolean;
BEGIN
  v_blocked := NOT has_function_privilege('anon',
    'public.claim_approved_face_to_face_auth(uuid,text)','EXECUTE');
  IF NOT v_blocked THEN RAISE EXCEPTION 'anon can claim Auth credential'; END IF;
  IF has_function_privilege('authenticated',
    'public.claim_approved_face_to_face_auth(uuid,text)','EXECUTE')
  THEN RAISE EXCEPTION 'authenticated can claim Auth credential'; END IF;
  IF has_function_privilege('anon',
    'public.finalize_approved_device_enrollment(uuid,text,uuid,uuid)','EXECUTE')
  THEN RAISE EXCEPTION 'anon can register device'; END IF;
  IF has_function_privilege('authenticated',
    'public.finalize_approved_device_enrollment(uuid,text,uuid,uuid)','EXECUTE')
  THEN RAISE EXCEPTION 'authenticated can register device'; END IF;
  IF has_table_privilege('anon','app_private.approved_device_sessions','SELECT')
    OR has_table_privilege('authenticated','app_private.device_enrollment_requests','SELECT')
  THEN RAISE EXCEPTION 'private enrollment data exposed'; END IF;
  RAISE NOTICE 'PASS: enrollment credentials and device allowlist cannot be read or mutated by client roles';
END $security$;

-- Device-aware test RLS uses the actual session predicate, not just JWT presence.
CREATE TABLE public.akaden_local_device_rls_probe (
 owner_id uuid PRIMARY KEY REFERENCES auth.users(id)
);
ALTER TABLE public.akaden_local_device_rls_probe ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.akaden_local_device_rls_probe FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.akaden_local_device_rls_probe TO authenticated;
CREATE POLICY approved_local_device ON public.akaden_local_device_rls_probe
 FOR SELECT TO authenticated USING (
 owner_id=(SELECT auth.uid()) AND (SELECT app_private.has_approved_device_session())
 );
NOTIFY pgrst, 'reload schema';
