-- Disposable LOCAL Supabase only. Requires verified GoTrue user/session UUIDs.
-- The SQL runner seeds synthetic approval state; it does NOT exercise the admin UI
-- or prove that a human manager approved the confirmation code.
\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE qr_real_test_ids (user_id uuid NOT NULL, session_id uuid NOT NULL);
INSERT INTO qr_real_test_ids VALUES (:'staff_uid'::uuid, :'session_id'::uuid);
DO $test$
DECLARE
 v_uid uuid;
 v_sid uuid;
 v_req uuid;
 v_invite uuid;
 v_target uuid;
 v_ok boolean;
 v_events integer;
BEGIN
 SELECT user_id,session_id INTO v_uid,v_sid FROM qr_real_test_ids;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions WHERE id=v_sid AND user_id=v_uid)
 THEN RAISE EXCEPTION 'Expected real GoTrue auth.sessions row missing'; END IF;
 INSERT INTO public.profiles(user_id,role,active)
 VALUES(v_uid,'staff',true);
 INSERT INTO public.device_enrollment_invites(user_id,issued_by,token_hash,expires_at)
 VALUES(v_uid,v_uid,repeat('a',64),now()+interval '10 minutes') RETURNING id INTO v_invite;
 -- Mimics server-side service_role RPC context, only on disposable database.
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 SELECT public.start_device_enrollment(repeat('a',64),repeat('b',64),repeat('c',64))
 INTO v_req;
 IF v_req IS NULL THEN RAISE EXCEPTION 'Failed to create QR request'; END IF;
 SELECT target_user_id INTO v_target FROM public.claim_approved_face_to_face_auth(v_req,repeat('b',64));
 IF v_target IS NOT NULL THEN RAISE EXCEPTION 'Unapproved QR released a credential'; END IF;
 -- Synthetic admin approval: real approve_device_enrollment auth/UI is a
 -- separate test and must not be represented as having passed here.
 UPDATE app_private.device_enrollment_requests
 SET approved_by=v_uid, approved_at=now() WHERE id=v_req;
 SELECT target_user_id INTO v_target FROM public.claim_approved_face_to_face_auth(v_req,repeat('d',64));
 IF v_target IS NOT NULL THEN RAISE EXCEPTION 'Wrong browser proof claimed credential'; END IF;
 SELECT target_user_id INTO v_target FROM public.claim_approved_face_to_face_auth(v_req,repeat('b',64));
 IF v_target IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'Approved browser claim did not return staff'; END IF;
 SELECT target_user_id INTO v_target FROM public.claim_approved_face_to_face_auth(v_req,repeat('b',64));
 IF v_target IS NOT NULL THEN RAISE EXCEPTION 'One-use credential claim could be replayed'; END IF;
 SELECT public.finalize_approved_device_enrollment(
   v_req,repeat('d',64),v_uid,v_sid) INTO v_ok;
 IF v_ok THEN RAISE EXCEPTION 'Wrong browser proof registered a device'; END IF;
 SELECT public.finalize_approved_device_enrollment(
   v_req,repeat('b',64),v_uid,gen_random_uuid()) INTO v_ok;
 IF v_ok THEN RAISE EXCEPTION 'Fabricated session registered a device'; END IF;
 SELECT public.finalize_approved_device_enrollment(
   v_req,repeat('b',64),gen_random_uuid(),v_sid) INTO v_ok;
 IF v_ok THEN RAISE EXCEPTION 'Wrong staff identity registered a device'; END IF;
 SELECT public.finalize_approved_device_enrollment(
   v_req,repeat('b',64),v_uid,v_sid) INTO v_ok;
 IF NOT v_ok THEN RAISE EXCEPTION 'Real session was not registered'; END IF;
 IF NOT EXISTS (SELECT 1 FROM app_private.approved_device_sessions
                WHERE session_id=v_sid AND user_id=v_uid AND revoked_at IS NULL)
 THEN RAISE EXCEPTION 'Real session missing from allowlist'; END IF;
 SELECT public.finalize_approved_device_enrollment(
   v_req,repeat('b',64),v_uid,v_sid) INTO v_ok;
 IF v_ok THEN RAISE EXCEPTION 'Device enrollment replay was accepted'; END IF;
 SELECT count(*) INTO v_events FROM app_private.device_enrollment_audit
 WHERE request_id=v_req AND event_type IN ('REQUESTED','AUTH_CLAIMED','CLAIMED');
 IF v_events<>3 THEN RAISE EXCEPTION 'Expected 3 QR audit events, got %',v_events; END IF;
 RAISE NOTICE 'PASS: real auth.sessions binding, preapproval denial, one-time claim, fake/wrong/replay finalize denial, audit';
END $test$;
ROLLBACK;
