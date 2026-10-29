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
