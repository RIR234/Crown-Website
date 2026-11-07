-- Retire the old Task Request workflow; new orders are balance-checked and confirmed immediately.
DROP POLICY IF EXISTS "Users can submit pending requests" ON public.crown_task_requests;
DROP POLICY IF EXISTS "Users and admins can view requests" ON public.crown_task_requests;
CREATE POLICY "Admins can view legacy task request history"
ON public.crown_task_requests
FOR SELECT
TO authenticated
USING ((SELECT public.is_crown_admin()));
REVOKE INSERT ON TABLE public.crown_task_requests FROM anon, authenticated;

-- Consolidate duplicate SELECT policies while preserving user-own and admin-wide visibility.
DROP POLICY IF EXISTS "Admins read all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
CREATE POLICY "Users and admins can view profiles"
ON public.profiles
FOR SELECT
TO authenticated
USING (id = (SELECT auth.uid()) OR (SELECT public.is_crown_admin()));

DROP POLICY IF EXISTS "Admins read all demo wallets" ON public.crown_demo_wallets;
DROP POLICY IF EXISTS "Users read own demo wallet" ON public.crown_demo_wallets;
CREATE POLICY "Users and admins can view demo wallets"
ON public.crown_demo_wallets
FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()) OR (SELECT public.is_crown_admin()));

-- Cover the legacy reviewer foreign key for admin history queries.
CREATE INDEX IF NOT EXISTS crown_task_requests_reviewed_by_idx
ON public.crown_task_requests (reviewed_by);
