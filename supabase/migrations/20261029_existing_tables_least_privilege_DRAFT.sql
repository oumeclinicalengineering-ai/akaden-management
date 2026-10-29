-- DRAFT ONLY — DO NOT EXECUTE ON CONNECTED SUPABASE UNTIL REVIEW/APPROVAL.
-- Existing Ver6 table-level grants currently include TRUNCATE, TRIGGER,
-- REFERENCES, MAINTAIN and DELETE for anon/authenticated in exposed tables.
-- PostgreSQL RLS DOES NOT PROTECT TRUNCATE. No change to rows or functions here.
-- These GRANTs preserve the existing Ver6 preview's table/RPC contract.
-- Prerequisites: actual live grants/policies verified read-only, rollback
-- captured, separate operator approval. Tested only on fake PostgreSQL.
BEGIN;

-- Remove blanket schema-generated privileges for direct browser roles.
-- service_role and postgres are not modified by these statements.
REVOKE ALL PRIVILEGES ON TABLE
  public.orders,
  public.receipts,
  public.profiles,
  public.audit_logs
FROM PUBLIC, anon, authenticated;

-- The preview reads orders/receipts, and creates new orders directly.
-- Existing orders_insert / orders_update policies still enforce creator/admin
-- and active user restrictions: grants do NOT override RLS.
GRANT SELECT, INSERT, UPDATE ON TABLE public.orders TO authenticated;
GRANT SELECT ON TABLE public.receipts TO authenticated;

-- Staff select their own profiles; management can update profiles under
-- profiles_admin_update RLS. Auth signup trigger inserts via SECURITY DEFINER.
GRANT SELECT, UPDATE ON TABLE public.profiles TO authenticated;

-- Only admins can see audit logs, under the existing audit_select RLS policy.
-- Browser clients must NEVER directly write audit logs or truncate them.
GRANT SELECT ON TABLE public.audit_logs TO authenticated;

-- Security-invoker view keeps underlying tables' RLS; its data does not
-- need to be accessible to unauthenticated API callers.
REVOKE ALL PRIVILEGES ON TABLE public.order_receipt_totals
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.order_receipt_totals TO authenticated;

-- No trigger code, receipt RPCs, RLS policies, auth settings, or user data
-- are altered. service_role's existing explicit grants are retained.
COMMIT;

-- In PostgreSQL 17, verify TRUNCATE/TRIGGER/MAINTAIN/REFERENCES/DELETE grants.
-- After review, compare these results with the live pre-application snapshot:
-- SELECT ... has_table_privilege(..., 'TRUNCATE') ... ;
-- The user must explicitly approve applying these changes to the live DB.
