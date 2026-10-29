-- Free isolated PostgreSQL 17 fixture — all rows and users are synthetic.
-- Run after tests/postgres/fixture.sql and device_fixture.sql.
-- Recreate the overly broad table privileges seen by read-only metadata in the
-- current Supabase project. This DOES NOT copy records from live Supabase.
ALTER TABLE public.orders
  ADD COLUMN created_by uuid NOT NULL
    DEFAULT 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
ALTER TABLE public.orders ADD COLUMN deleted boolean NOT NULL DEFAULT false;

CREATE POLICY orders_insert ON public.orders
  FOR INSERT TO authenticated
  WITH CHECK (public.is_active_user() AND created_by=auth.uid());
CREATE POLICY orders_update ON public.orders
  FOR UPDATE TO authenticated
  USING(public.is_active_user() AND
       (created_by=auth.uid() OR public.is_admin()))
  WITH CHECK(public.is_active_user() AND
       (created_by=auth.uid() OR public.is_admin()));

CREATE POLICY profiles_select ON public.profiles FOR SELECT TO authenticated
  USING(user_id=auth.uid() OR public.is_admin());
CREATE POLICY profiles_admin_update ON public.profiles FOR UPDATE TO authenticated
  USING(public.is_admin()) WITH CHECK(public.is_admin());

ALTER TABLE public.receipts ENABLE ROW LEVEL SECURITY;
CREATE POLICY receipts_select ON public.receipts FOR SELECT TO authenticated
  USING(public.is_active_user());

CREATE TABLE public.audit_logs (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  detail text NOT NULL
);
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_select ON public.audit_logs FOR SELECT TO authenticated
  USING(public.is_admin());
INSERT INTO public.audit_logs(detail) VALUES('synthetic audit record');

CREATE VIEW public.order_receipt_totals WITH (security_invoker=true) AS
  SELECT o.id, o.quantity,coalesce(sum(r.quantity),0)::bigint AS received
  FROM public.orders o LEFT JOIN public.receipts r ON r.order_id=o.id
  GROUP BY o.id, o.quantity;

-- Simulate the exact *classes* of pre-migration grants observed in the
-- current project, including all dangerous TRUNCATE, MAINTAIN, TRIGGER etc.
GRANT ALL PRIVILEGES ON TABLE
  public.orders, public.profiles, public.audit_logs TO anon, authenticated;
GRANT ALL PRIVILEGES ON TABLE public.receipts TO anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.receipts FROM anon, authenticated;
GRANT ALL PRIVILEGES ON TABLE public.order_receipt_totals TO anon, authenticated;

-- Include explicit service-role permissions, which the migration must retain.
GRANT ALL PRIVILEGES ON TABLE
  public.orders,public.receipts,public.profiles,public.audit_logs,
  public.order_receipt_totals TO service_role;
