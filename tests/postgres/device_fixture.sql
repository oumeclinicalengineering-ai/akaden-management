-- Synthetic Supabase-Auth fixtures (isolated PostgreSQL service container only).
-- Never run this file on a Supabase project.
CREATE SCHEMA auth;
CREATE TABLE auth.users (id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE
AS $body$
SELECT NULLIF(current_setting('request.jwt.claim.sub',true),'')::uuid
$body$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE
AS $body$
SELECT COALESCE(NULLIF(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb)
$body$;

CREATE ROLE service_role NOLOGIN;
GRANT USAGE ON SCHEMA public, auth TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION auth.jwt() TO authenticated, anon;

ALTER TABLE public.profiles ADD COLUMN role text NOT NULL DEFAULT 'staff';
ALTER TABLE public.profiles ADD COLUMN active boolean NOT NULL DEFAULT true;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.profiles TO authenticated;

CREATE POLICY orders_select ON public.orders
FOR SELECT TO authenticated USING (public.is_active_user());
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

INSERT INTO auth.users(id) VALUES
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
INSERT INTO public.profiles(user_id,role,active) VALUES
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','admin',true),
('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','staff',true);
