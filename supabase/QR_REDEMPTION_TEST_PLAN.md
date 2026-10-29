# QR招待の消費処理 — 未適用・未テスト

`consume_device_enrollment_invite` is an atomic PostgreSQL UPDATE that returns exactly one row only for a valid, unexpired, unconsumed, unrevoked invite. Concurrent redemption of the same token cannot both succeed.

## Critical limitations
- **Do not call yet:** face-to-face admin approval has not been implemented. Consuming a QR without this gate is insecure.
- This RPC **does not log a staff member in**, issue a Supabase Auth session, or bind a device.
- The RPC must only be called by a server holding the service-role credential, after independently verifying admin approval. The browser must never receive the service-role key.
- A PostgreSQL role claim is not proof of a person; keep service-role key strictly server-side.
- Device revocation and RLS/RPC integration remain blockers.

## Staging test matrix
1. Valid invite returns target user once; second attempt returns zero rows.
2. Expired invite returns zero rows.
3. Revoked invite returns zero rows.
4. Two concurrent attempts: only one succeeds.
5. Malformed hash raises invalid parameter error.
6. anon/authenticated cannot execute.
7. Failed approval must never call the RPC.
8. Test with fake staff and fake orders only.

**Do not apply SQL to production.**
