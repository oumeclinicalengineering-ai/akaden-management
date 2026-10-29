-- STAGING DRAFT ONLY. DO NOT RUN ON LIVE SUPABASE!
-- DEPENDENCIES: approved_device_sessions migration and admin bootstrap.
-- CUTOVER: BLOCKS ALL EXISTING PASSWORD SESSIONS NOT IN THE ALLOWLIST.
-- This is NOT safe until admin + staff sessions have been approved and tested.
BEGIN;
CREATE OR REPLACE FUNCTION public.is_active_user()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $body$
  SELECT EXISTS(
    SELECT 1 FROM public.profiles p
    WHERE p.user_id=(SELECT auth.uid()) AND p.active
  ) AND (SELECT app_private.has_approved_device_session());
$body$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $body$
  SELECT EXISTS(
    SELECT 1 FROM public.profiles p
    WHERE p.user_id=(SELECT auth.uid()) AND p.active AND p.role='admin'
  ) AND (SELECT app_private.has_approved_device_session());
$body$;

-- Staff formerly could SELECT their own profile without device enrollment.
-- After cutover, even this read must require a currently approved session.
DROP POLICY IF EXISTS profiles_select ON public.profiles;
CREATE POLICY profiles_select ON public.profiles FOR SELECT TO authenticated
USING (
  (SELECT app_private.has_approved_device_session())
  AND (user_id = (SELECT auth.uid()) OR (SELECT public.is_admin()))
);

-- All original orders/receipts/audit policies and receipt RPCs use
-- public.is_active_user()/public.is_admin() and now inherit this guard.
-- Validate no other exposed RPC or RLS policy bypasses these helpers.
COMMIT;
