# QR invite issuer — staging only

This is a **server-side invite issuer only**, not a passwordless login implementation. Do not deploy to production until reviewed.

- Requires Supabase Edge Functions, the draft migration, and environment secrets.
- Only POST; verifies Supabase Auth bearer token with `auth.getUser`.
- Looks up actor's `profiles.role = admin` and `active = true` on the server.
- Requires an active target profile. Generates 256-bit random token, stores SHA-256 hash only, expires in 10 minutes.
- Rejects browser-origin requests until an explicit trusted-origin/CORS and CSRF policy is established.
- Token returned once to the trusted caller; never embed service role credentials in client code.
- **Not implemented:** invitation consumption, separate face-to-face approval, Supabase Auth session issuance, audit logging, device revocation, rate limiting. These are deployment blockers.
- Never put the raw token in logs, analytics, or a third-party QR generation service.

## Manual test checklist (after isolated staging setup)
1. Missing/invalid bearer -> 401.
2. Staff bearer -> 403.
3. Inactive admin -> 403.
4. Invalid target -> 404.
5. Active admin and active target -> 201, 64-character random token, expires_at ~10 minutes.
6. DB contains only SHA-256 hash, not the raw token.
7. Browser Origin header -> 403.
8. No secrets exposed in git or response.
