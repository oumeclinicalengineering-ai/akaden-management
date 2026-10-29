-- DESIGN STAGING ONLY: do not apply to production until Auth/RLS integration is reviewed.
-- Only server-side Edge Functions using service_role may access this table.
create table if not exists public.device_enrollment_invites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  token_hash text not null unique,
  issued_by uuid not null references auth.users(id),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  constraint token_hash_sha256 check (token_hash ~ '^[a-f0-9]{64}$'),
  constraint expiry_after_creation check (expires_at > created_at)
);
alter table public.device_enrollment_invites enable row level security;
revoke all on public.device_enrollment_invites from anon, authenticated;
-- No browser-facing policies. Server-only access; service_role bypasses RLS.
create index if not exists device_enrollment_invites_user_idx
  on public.device_enrollment_invites (user_id, created_at desc);
create index if not exists device_enrollment_invites_expiry_idx
  on public.device_enrollment_invites (expires_at)
  where consumed_at is null and revoked_at is null;

-- Atomically claim a token inside a trusted server-side transaction:
-- UPDATE public.device_enrollment_invites
-- SET consumed_at = now()
-- WHERE token_hash = :server_computed_sha256
--   AND consumed_at IS NULL AND revoked_at IS NULL AND expires_at > now()
-- RETURNING user_id;
-- This alone is NOT sufficient to issue a session: verify face-to-face approval
-- and use a supported Supabase Auth flow; never return service_role credentials.
