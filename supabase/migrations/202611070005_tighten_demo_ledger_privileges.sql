-- Only vetted SECURITY DEFINER RPCs may mutate demo balances and orders.
REVOKE ALL ON TABLE public.crown_demo_wallets FROM anon, authenticated;
REVOKE ALL ON TABLE public.crown_demo_orders FROM anon, authenticated;
REVOKE ALL ON TABLE public.crown_demo_transactions FROM anon, authenticated;
REVOKE ALL ON TABLE public.crown_demo_task_catalog FROM anon, authenticated;

GRANT SELECT ON TABLE public.crown_demo_wallets TO authenticated;
GRANT SELECT ON TABLE public.crown_demo_orders TO authenticated;
GRANT SELECT ON TABLE public.crown_demo_transactions TO authenticated;

-- Admin cancellation/refund remains available through its guarded RPC only.
