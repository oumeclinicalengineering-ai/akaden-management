-- STAGING DRAFT ONLY: not deployed.
-- Admin-only read APIs for the mobile enrollment management interface.
BEGIN;
CREATE OR REPLACE FUNCTION public.list_pending_device_enrollments()
RETURNS TABLE (
  request_id uuid,
  staff_user_id uuid,
  staff_name text,
  requested_at timestamptz,
  expires_at timestamptz,
  approval_attempts integer
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $body$
BEGIN
  IF (SELECT auth.uid()) IS NULL
    OR NOT (SELECT public.is_admin())
    OR NOT (SELECT app_private.has_approved_device_session()) THEN
    RAISE EXCEPTION '管理者のみ参照可能です' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
    SELECT r.id,r.user_id,p.display_name,r.requested_at,
           r.expires_at,r.approval_attempts
      FROM app_private.device_enrollment_requests r
      JOIN public.profiles p ON p.user_id=r.user_id
     WHERE r.approved_at IS NULL AND r.consumed_at IS NULL
       AND r.expires_at>now() AND r.approval_attempts<5 AND p.active
     ORDER BY r.requested_at DESC LIMIT 30;
END;
$body$;
REVOKE ALL ON FUNCTION public.list_pending_device_enrollments()
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.list_pending_device_enrollments()
  TO authenticated;

CREATE OR REPLACE FUNCTION public.list_enrolled_devices()
RETURNS TABLE (
  session_id uuid,
  staff_user_id uuid,
  staff_name text,
  enrolled_at timestamptz,
  revoked_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $body$
BEGIN
  IF (SELECT auth.uid()) IS NULL
    OR NOT (SELECT public.is_admin())
    OR NOT (SELECT app_private.has_approved_device_session()) THEN
    RAISE EXCEPTION '管理者のみ参照可能です' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
    SELECT s.session_id,s.user_id,p.display_name,s.enrolled_at,s.revoked_at
      FROM app_private.approved_device_sessions s
      JOIN public.profiles p ON p.user_id=s.user_id
     ORDER BY s.enrolled_at DESC LIMIT 100;
END;
$body$;
REVOKE ALL ON FUNCTION public.list_enrolled_devices()
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.list_enrolled_devices()
  TO authenticated;
COMMIT;
