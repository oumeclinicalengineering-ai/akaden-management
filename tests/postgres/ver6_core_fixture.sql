-- Isolated PostgreSQL 17 fixture. This runs only inside a GitHub Actions service container.
-- All IDs and content are synthetic; no live Supabase credentials or data.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;

CREATE TABLE public.orders (
  id uuid PRIMARY KEY,
  quantity integer NOT NULL CHECK (quantity BETWEEN 1 AND 100000000)
);

CREATE TABLE public.receipts (
  id uuid PRIMARY KEY,
  order_id uuid NOT NULL REFERENCES public.orders(id),
  quantity integer NOT NULL CHECK (quantity > 0)
);

CREATE TABLE public.audit_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  object_name text NOT NULL,
  action_name text NOT NULL
);

CREATE FUNCTION public.is_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$ SELECT true $$;

CREATE FUNCTION public.is_active_user() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$ SELECT true $$;

CREATE FUNCTION public.record_audit() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.audit_events(object_name, action_name)
    VALUES (TG_TABLE_NAME, TG_OP);
  RETURN NEW;
END;
$$;

CREATE TABLE public.fake_auth_users(id uuid PRIMARY KEY);
CREATE TABLE public.profiles(user_id uuid PRIMARY KEY);

CREATE FUNCTION public.create_profile_for_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles(user_id) VALUES (NEW.id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER orders_audit AFTER UPDATE ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.record_audit();

CREATE TRIGGER on_fake_auth_user_created AFTER INSERT ON public.fake_auth_users
FOR EACH ROW EXECUTE FUNCTION public.create_profile_for_user();

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT, UPDATE ON public.orders TO authenticated;
GRANT INSERT ON public.fake_auth_users TO authenticated;

INSERT INTO public.orders(id, quantity)
VALUES ('11111111-1111-4111-8111-111111111111',5);
INSERT INTO public.receipts(id, order_id, quantity)
VALUES ('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111',3);
