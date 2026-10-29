# Staging validation before enabling hardening
1. Back up current schema, RLS policies, function definitions and triggers.
2. Apply draft migration to a dedicated staging project/branch, not live.
3. Verify function ownership and EXECUTE revocations; triggers still work after privileges removed.
4. Verify security_invoker view and RLS under anonymous, staff A, staff B, admin.
5. Check order quantity cannot be reduced below received total through REST or direct SQL as staff.
6. Check no deadlock or over-receipt with concurrent order quantity updates and receipt RPCs.
7. Test legacy Ver.6 CRUD and QR-design workflow.
8. Review downtime/rollback if a migration is ever approved for production.
**No migration has been run.**
