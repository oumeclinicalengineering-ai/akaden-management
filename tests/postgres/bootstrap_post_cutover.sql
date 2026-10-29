-- After cutover, approved admin is authorized, other device and staff are not.
SET request.jwt.claim.sub='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SET request.jwt.claim.role='authenticated';
SET request.jwt.claims='{"session_id":"aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"}';
SET ROLE authenticated;
DO $$
BEGIN
 IF NOT public.is_admin() OR NOT public.is_active_user()
 THEN RAISE EXCEPTION 'bootstrapped administrator locked out after cutover'; END IF;
 IF (SELECT count(*) FROM public.orders) <> 1
 THEN RAISE EXCEPTION 'approved admin lost order read'; END IF;
 -- Cannot revoke the final approved administrator handset.
 BEGIN
   PERFORM public.revoke_enrolled_device('aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa');
   RAISE EXCEPTION 'last admin device was revoked';
 EXCEPTION WHEN insufficient_privilege THEN
   RAISE NOTICE 'PASS: last admin device cannot be revoked';
 END;
END $$;
RESET ROLE;

SET request.jwt.claims='{"session_id":"aaaaaaaa-4444-4444-8444-aaaaaaaaaaaa"}';
SET ROLE authenticated;
DO $$
BEGIN
 IF public.is_admin() OR public.is_active_user()
 THEN RAISE EXCEPTION 'unregistered session got admin permissions'; END IF;
 IF (SELECT count(*) FROM public.orders) <> 0
 THEN RAISE EXCEPTION 'unregistered session read orders'; END IF;
END $$;
RESET ROLE;

SET request.jwt.claim.sub='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
SET request.jwt.claims='{"session_id":"bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb"}';
SET ROLE authenticated;
DO $$
BEGIN
 IF public.is_admin() OR public.is_active_user()
 THEN RAISE EXCEPTION 'staff bypassed device cutover'; END IF;
END $$;
RESET ROLE;
SELECT 'PASS: first admin survives RLS cutover and other sessions denied' AS result;
