-- Crown demo wallet, confirmed orders and admin dashboard.
-- Demo credits have no cash value. This migration does not enable deposits, withdrawals or crypto transfers.

CREATE TABLE IF NOT EXISTS public.crown_demo_wallets (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  balance numeric(14,2) NOT NULL DEFAULT 100000.00 CHECK (balance >= 0),
  total_spent numeric(14,2) NOT NULL DEFAULT 0 CHECK (total_spent >= 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.crown_demo_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  task_index integer NOT NULL CHECK (task_index BETWEEN 0 AND 49),
  task_title text NOT NULL,
  amount numeric(14,2) NOT NULL CHECK (amount > 0),
  status text NOT NULL DEFAULT 'confirmed' CHECK (status IN ('confirmed','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, task_index)
);

CREATE TABLE IF NOT EXISTS public.crown_demo_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  order_id uuid REFERENCES public.crown_demo_orders(id) ON DELETE SET NULL,
  type text NOT NULL CHECK (type IN ('demo_credit','demo_order')),
  amount numeric(14,2) NOT NULL CHECK (amount > 0),
  note text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.crown_demo_wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crown_demo_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crown_demo_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own demo wallet" ON public.crown_demo_wallets;
CREATE POLICY "Users read own demo wallet" ON public.crown_demo_wallets
FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()) OR public.is_crown_admin());

DROP POLICY IF EXISTS "Admins read all demo wallets" ON public.crown_demo_wallets;
CREATE POLICY "Admins read all demo wallets" ON public.crown_demo_wallets
FOR SELECT TO authenticated USING (public.is_crown_admin());

DROP POLICY IF EXISTS "Users read own demo orders" ON public.crown_demo_orders;
CREATE POLICY "Users read own demo orders" ON public.crown_demo_orders
FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()) OR public.is_crown_admin());

DROP POLICY IF EXISTS "Admins update demo orders" ON public.crown_demo_orders;
CREATE POLICY "Admins update demo orders" ON public.crown_demo_orders
FOR UPDATE TO authenticated USING (public.is_crown_admin()) WITH CHECK (public.is_crown_admin());

DROP POLICY IF EXISTS "Users read own demo transactions" ON public.crown_demo_transactions;
CREATE POLICY "Users read own demo transactions" ON public.crown_demo_transactions
FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()) OR public.is_crown_admin());

DROP POLICY IF EXISTS "Admins read all profiles" ON public.profiles;
CREATE POLICY "Admins read all profiles" ON public.profiles
FOR SELECT TO authenticated USING (public.is_crown_admin());

CREATE OR REPLACE FUNCTION public.get_crown_demo_wallet()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_wallet public.crown_demo_wallets%ROWTYPE;
  v_completed integer[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  INSERT INTO public.crown_demo_wallets(user_id) VALUES (v_uid)
  ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO v_wallet FROM public.crown_demo_wallets WHERE user_id = v_uid;
  SELECT COALESCE(array_agg(task_index ORDER BY task_index), ARRAY[]::integer[])
    INTO v_completed FROM public.crown_demo_orders
    WHERE user_id = v_uid AND status = 'confirmed';
  RETURN jsonb_build_object(
    'balance', v_wallet.balance,
    'spent', v_wallet.total_spent,
    'completed', to_jsonb(v_completed)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.place_crown_demo_order(
  p_task_index integer,
  p_task_title text,
  p_amount numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric(14,2);
  v_order public.crown_demo_orders%ROWTYPE;
  v_next integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF p_task_index < 0 OR p_task_index > 49 OR p_amount <= 0 OR p_amount > 10000000
     OR length(trim(COALESCE(p_task_title,''))) = 0 THEN
    RAISE EXCEPTION 'Invalid demo order';
  END IF;

  INSERT INTO public.crown_demo_wallets(user_id) VALUES (v_uid)
  ON CONFLICT (user_id) DO NOTHING;
  PERFORM 1 FROM public.crown_demo_wallets WHERE user_id = v_uid FOR UPDATE;
  SELECT balance INTO v_balance FROM public.crown_demo_wallets WHERE user_id = v_uid;

  SELECT COALESCE(max(task_index) + 1, 0) INTO v_next
    FROM public.crown_demo_orders WHERE user_id = v_uid AND status = 'confirmed';
  IF p_task_index <> v_next THEN RAISE EXCEPTION 'Complete the previous task first'; END IF;
  IF v_balance < p_amount THEN RAISE EXCEPTION 'Insufficient demo balance'; END IF;

  UPDATE public.crown_demo_wallets
    SET balance = balance - p_amount,
        total_spent = total_spent + p_amount,
        updated_at = now()
    WHERE user_id = v_uid;

  INSERT INTO public.crown_demo_orders(user_id, task_index, task_title, amount)
    VALUES (v_uid, p_task_index, trim(p_task_title), p_amount)
    RETURNING * INTO v_order;

  INSERT INTO public.crown_demo_transactions(user_id, order_id, type, amount, note)
    VALUES (v_uid, v_order.id, 'demo_order', p_amount, 'Demo order confirmed');

  RETURN jsonb_build_object(
    'order_id', v_order.id,
    'balance', v_balance - p_amount,
    'spent', (SELECT total_spent FROM public.crown_demo_wallets WHERE user_id = v_uid),
    'task_index', p_task_index
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.add_crown_demo_credit()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric(14,2);
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  INSERT INTO public.crown_demo_wallets(user_id) VALUES (v_uid)
  ON CONFLICT (user_id) DO NOTHING;
  UPDATE public.crown_demo_wallets
    SET balance = balance + 100000, updated_at = now()
    WHERE user_id = v_uid RETURNING balance INTO v_balance;
  INSERT INTO public.crown_demo_transactions(user_id, type, amount, note)
    VALUES (v_uid, 'demo_credit', 100000, 'Demo-only test credit');
  RETURN jsonb_build_object('balance', v_balance);
END;
$$;

REVOKE ALL ON FUNCTION public.get_crown_demo_wallet() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.place_crown_demo_order(integer,text,numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.add_crown_demo_credit() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_crown_demo_wallet() TO authenticated;
GRANT EXECUTE ON FUNCTION public.place_crown_demo_order(integer,text,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_crown_demo_credit() TO authenticated;

GRANT SELECT ON public.crown_demo_wallets, public.crown_demo_orders, public.crown_demo_transactions TO authenticated;
GRANT UPDATE ON public.crown_demo_orders TO authenticated;
