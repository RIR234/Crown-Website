ALTER TABLE public.crown_demo_transactions
  DROP CONSTRAINT IF EXISTS crown_demo_transactions_type_check;
ALTER TABLE public.crown_demo_transactions
  ADD CONSTRAINT crown_demo_transactions_type_check
  CHECK (type = ANY (ARRAY['demo_credit','demo_order','admin_credit','admin_debit']::text[]));

CREATE OR REPLACE FUNCTION public.admin_adjust_crown_demo_balance(
  p_user_id uuid,
  p_amount numeric,
  p_action text,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_balance numeric(14,2);
  v_note text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF NOT public.is_crown_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Select a user';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_amount > 1000000000 THEN
    RAISE EXCEPTION 'Enter a valid amount greater than zero';
  END IF;
  IF p_action NOT IN ('add','deduct') THEN
    RAISE EXCEPTION 'Invalid balance action';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  INSERT INTO public.crown_demo_wallets(user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  PERFORM 1 FROM public.crown_demo_wallets
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF p_action = 'add' THEN
    UPDATE public.crown_demo_wallets
      SET balance = balance + p_amount, updated_at = now()
      WHERE user_id = p_user_id
      RETURNING balance INTO v_balance;
  ELSE
    UPDATE public.crown_demo_wallets
      SET balance = balance - p_amount, updated_at = now()
      WHERE user_id = p_user_id AND balance >= p_amount
      RETURNING balance INTO v_balance;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Insufficient demo balance for deduction';
    END IF;
  END IF;

  v_note := left(COALESCE(NULLIF(btrim(p_note), ''), 'Admin balance adjustment'), 200);
  INSERT INTO public.crown_demo_transactions(user_id, type, amount, note)
  VALUES (
    p_user_id,
    CASE WHEN p_action = 'add' THEN 'admin_credit' ELSE 'admin_debit' END,
    p_amount,
    v_note
  );

  RETURN jsonb_build_object('user_id', p_user_id, 'balance', v_balance, 'action', p_action, 'amount', p_amount);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_adjust_crown_demo_balance(uuid,numeric,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_adjust_crown_demo_balance(uuid,numeric,text,text) TO authenticated;
