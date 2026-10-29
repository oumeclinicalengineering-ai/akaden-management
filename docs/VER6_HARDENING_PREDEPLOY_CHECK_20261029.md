# Ver.6 Security Hardening — Pre-deployment check (2026-10-29)

## Scope and execution
- Connected Supabase project: the existing Akaden Ver.6 test project.
- All Supabase queries this pass were **SELECT-only**. No migrations, data updates, Edge Functions, or branch creation.
- Current database contains 2 test orders; **0** have total received quantity greater than ordered quantity (aggregate count only; no personal data retrieved).
- `orders_quantity_receipt_guard` trigger is **not installed**, as expected.
- There are **no Supabase development branches**, so migrations were not applied. Branches may incur costs and need explicit approval.

## Draft safety fix applied on GitHub
- The draft migration revokes anonymous execution of `is_admin`/`is_active_user`.
- It now explicitly **GRANTs execution to `authenticated`**, preserving RLS policy helper calls even if a staging DB does not have preexisting explicit grants.
- Privileged trigger-only functions are proposed to lose direct public execution.
- `orders_quantity_receipt_guard` draft blocks decreasing order quantity below existing receipts, using the order row lock consistent with receipt RPCs.
- Static CI assertions were added for the order guard and necessary RLS helper grants.

## Remaining gates
1. Apply the migration only to a separate, user-approved Supabase staging environment.
2. Verify privileges, trigger behavior, and order/receipt concurrent operations with fictional accounts.
3. Confirm Auth signup and audit triggers still work.
4. Check security advisors after applying staging changes.
5. Only then consider an explicitly approved production migration.

**This report does NOT mean a database migration was deployed or runtime-tested.**
