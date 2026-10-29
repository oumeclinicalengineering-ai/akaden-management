-- STAGING DRAFT. DO NOT APPLY TO PRODUCTION WITHOUT SECURITY REVIEW.
-- Atomic invitation redemption. Must only be called by a trusted server
-- AFTER an independent, face-to-face approval check.
-- This function does NOT authenticate a user or issue a session.
create or replace function public.consume_device_enrollment_invite(p_token_hash text)
returns table (invitation_id uuid, target_user_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_setting('request.jwt.claim.role', true) is distinct from 'service_role' then
    raise exception 'server-only operation' using errcode='42501';
  end if;
  if p_token_hash is null or p_token_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'invalid token hash' using errcode='22023';
  end if;
  return query
    update public.device_enrollment_invites i
       set consumed_at = now()
     where i.token_hash = p_token_hash
       and i.consumed_at is null
       and i.revoked_at is null
       and i.expires_at > now()
    returning i.id, i.user_id;
end;
$$;
revoke all on function public.consume_device_enrollment_invite(text) from public, anon, authenticated;
grant execute on function public.consume_device_enrollment_invite(text) to service_role;

-- Security note: role checking above is defense in depth; GRANT is the main boundary.
-- Do not call this RPC from a browser or before administrator approval.
