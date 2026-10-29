-- Only for ephemeral local GoTrue integration test. NEVER use on hospital DB.
BEGIN;
CREATE TABLE public.akaden_local_auth_rls_probe (
  owner_id uuid PRIMARY KEY,
  note text NOT NULL DEFAULT 'FAKE DATA ONLY'
);
ALTER TABLE public.akaden_local_auth_rls_probe ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.akaden_local_auth_rls_probe FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.akaden_local_auth_rls_probe TO authenticated;
GRANT ALL ON public.akaden_local_auth_rls_probe TO service_role;
CREATE POLICY local_staff_session_only ON public.akaden_local_auth_rls_probe
  FOR SELECT TO authenticated
  USING (
    owner_id = (SELECT auth.uid())
    AND (SELECT auth.jwt() ->> 'session_id') IS NOT NULL
  );
COMMIT;
