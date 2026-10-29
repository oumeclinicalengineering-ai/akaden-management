-- Ver.6 security snapshot: READ-ONLY. No patient/order/receipt rows are read.
-- Purpose: inspect current RLS, grants, policies, views, triggers and RPC metadata.
-- Safe in Supabase SQL Editor when run by a project administrator.
-- Output: section | object_name | finding | detail (JSON).
-- IMPORTANT: no ALTER/UPDATE/INSERT/DELETE/GRANT/REVOKE/EXECUTE here.
WITH
target_tables(name) AS (
  VALUES ('profiles'), ('orders'), ('receipts'), ('audit_logs'),
         ('device_enrollment_invites')
),
table_info AS (
  SELECT t.name,
         c.oid, c.relrowsecurity, c.relforcerowsecurity
  FROM target_tables t
  LEFT JOIN pg_namespace n ON n.nspname = 'public'
  LEFT JOIN pg_class c ON c.relnamespace = n.oid AND c.relname = t.name
    AND c.relkind IN ('r','p')
),
table_results AS (
  SELECT '01_TABLE'::text section, t.name::text object_name,
         CASE
           WHEN t.oid IS NULL THEN 'NOT_PRESENT'
           WHEN NOT t.relrowsecurity THEN 'REVIEW_RLS_OFF'
           WHEN t.name = 'receipts'
             AND (has_table_privilege('authenticated', t.oid, 'INSERT')
               OR has_table_privilege('authenticated', t.oid, 'UPDATE')
               OR has_table_privilege('authenticated', t.oid, 'DELETE'))
             THEN 'REVIEW_DIRECT_RECEIPT_WRITE'
           ELSE 'CHECK_POLICIES_AND_TRIGGERS'
         END::text finding,
         jsonb_build_object(
           'rls_enabled', t.relrowsecurity,
           'force_rls', t.relforcerowsecurity,
           'anon_select', CASE WHEN t.oid IS NULL THEN null ELSE has_table_privilege('anon', t.oid, 'SELECT') END,
           'anon_insert', CASE WHEN t.oid IS NULL THEN null ELSE has_table_privilege('anon', t.oid, 'INSERT') END,
           'authenticated_select', CASE WHEN t.oid IS NULL THEN null ELSE has_table_privilege('authenticated', t.oid, 'SELECT') END,
           'authenticated_insert', CASE WHEN t.oid IS NULL THEN null ELSE has_table_privilege('authenticated', t.oid, 'INSERT') END,
           'authenticated_update', CASE WHEN t.oid IS NULL THEN null ELSE has_table_privilege('authenticated', t.oid, 'UPDATE') END,
           'authenticated_delete', CASE WHEN t.oid IS NULL THEN null ELSE has_table_privilege('authenticated', t.oid, 'DELETE') END
         ) detail
  FROM table_info t
),
policy_results AS (
  SELECT '02_POLICY'::text section, (schemaname || '.' || tablename || '.' || policyname)::text object_name,
         'REVIEW'::text finding,
         jsonb_build_object('command',cmd,'roles',roles,'permissive',permissive,
                            'using',qual,'with_check',with_check) detail
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename IN ('profiles','orders','receipts','audit_logs','device_enrollment_invites')
),
target_functions(name) AS (
  VALUES ('add_receipt'), ('change_receipt'), ('cancel_receipt'),
         ('is_admin'), ('is_active_user'), ('consume_device_enrollment_invite')
),
function_results AS (
  SELECT '03_FUNCTION'::text section,
         (f.name || coalesce('(' || pg_get_function_identity_arguments(p.oid) || ')',''))::text object_name,
         CASE WHEN p.oid IS NULL THEN 'NOT_PRESENT'
              WHEN has_function_privilege('anon',p.oid,'EXECUTE') THEN 'REVIEW_ANON_EXECUTE'
              ELSE 'CHECK_AUTH_AND_BODY'
         END::text finding,
         jsonb_build_object(
           'security_definer', p.prosecdef,
           'owner', pg_get_userbyid(p.proowner),
           'config', p.proconfig,
           'anon_execute', CASE WHEN p.oid IS NULL THEN null ELSE has_function_privilege('anon',p.oid,'EXECUTE') END,
           'authenticated_execute', CASE WHEN p.oid IS NULL THEN null ELSE has_function_privilege('authenticated',p.oid,'EXECUTE') END,
           'service_role_execute', CASE WHEN p.oid IS NULL THEN null ELSE has_function_privilege('service_role',p.oid,'EXECUTE') END
         ) detail
  FROM target_functions f
  LEFT JOIN pg_namespace n ON n.nspname = 'public'
  LEFT JOIN pg_proc p ON p.pronamespace = n.oid AND p.proname = f.name
),
view_results AS (
  SELECT '04_VIEW'::text section, c.relname::text object_name,
         CASE
           WHEN c.oid IS NULL THEN 'NOT_PRESENT'
           WHEN coalesce('security_invoker=true'=ANY(c.reloptions),false) THEN 'CHECK_VIEW_FILTERING'
           ELSE 'REVIEW_SECURITY_DEFINER_VIEW'
         END::text finding,
         jsonb_build_object('reloptions', c.reloptions,
             'anon_select', CASE WHEN c.oid IS NULL THEN null ELSE has_table_privilege('anon',c.oid,'SELECT') END,
             'authenticated_select', CASE WHEN c.oid IS NULL THEN null ELSE has_table_privilege('authenticated',c.oid,'SELECT') END) detail
  FROM (SELECT 'order_receipt_totals'::text name) v
  LEFT JOIN pg_namespace n ON n.nspname = 'public'
  LEFT JOIN pg_class c ON c.relnamespace=n.oid AND c.relname=v.name AND c.relkind IN ('v','m')
),
trigger_results AS (
  SELECT '05_TRIGGER'::text section, (c.relname || '.' || t.tgname)::text object_name,
         'REVIEW'::text finding,
         jsonb_build_object('definition',pg_get_triggerdef(t.oid,true)) detail
  FROM pg_trigger t
  JOIN pg_class c ON c.oid=t.tgrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname IN ('orders','receipts')
    AND NOT t.tgisinternal
)
SELECT section, object_name, finding, detail FROM table_results
UNION ALL SELECT section, object_name, finding, detail FROM policy_results
UNION ALL SELECT section, object_name, finding, detail FROM function_results
UNION ALL SELECT section, object_name, finding, detail FROM view_results
UNION ALL SELECT section, object_name, finding, detail FROM trigger_results
ORDER BY section, object_name;
