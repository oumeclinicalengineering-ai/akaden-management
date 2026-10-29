-- Ver.6 RPC definitions: READ-ONLY; functions are not executed.
-- IMPORTANT: review before sharing output. Function source might embed sensitive literals.
SELECT n.nspname AS schema_name,
       p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       p.prosecdef AS security_definer,
       pg_get_functiondef(p.oid) AS source
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN ('add_receipt','change_receipt','cancel_receipt')
ORDER BY p.proname, arguments;
