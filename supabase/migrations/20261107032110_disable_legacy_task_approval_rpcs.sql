-- Legacy Task Request approvals are no longer part of Crown's order flow.
-- Orders are confirmed immediately when the authenticated user's demo balance is sufficient.
-- Remove client execution access to the retired approval/rejection RPCs.
REVOKE EXECUTE ON FUNCTION public.admin_approve_task(uuid,numeric,text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_reject_task(uuid,text) FROM PUBLIC, anon, authenticated;
