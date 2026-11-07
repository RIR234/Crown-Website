-- Crown user blocking and referral invitations
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_blocked boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS referral_code text,
  ADD COLUMN IF NOT EXISTS referred_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

UPDATE public.profiles
SET referral_code = upper(substr(replace(id::text,'-',''),1,8))
WHERE referral_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS profiles_referral_code_uidx ON public.profiles(referral_code);
CREATE INDEX IF NOT EXISTS profiles_referred_by_idx ON public.profiles(referred_by);

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_referral_code text;
DECLARE v_referrer uuid;
BEGIN
  v_referral_code := upper(trim(COALESCE(NEW.raw_user_meta_data ->> 'referral_code','')));
  IF v_referral_code <> '' THEN
    SELECT id INTO v_referrer FROM public.profiles
    WHERE referral_code = v_referral_code AND id <> NEW.id AND is_blocked = false
    LIMIT 1;
  END IF;
  INSERT INTO public.profiles (id,email,full_name,username,referral_code,referred_by)
  VALUES (NEW.id,NEW.email,COALESCE(NEW.raw_user_meta_data ->> 'full_name',''),
    NULLIF(lower(trim(NEW.raw_user_meta_data ->> 'username')),''),
    upper(substr(replace(NEW.id::text,'-',''),1,8)),v_referrer)
  ON CONFLICT (id) DO UPDATE
    SET email=EXCLUDED.email,full_name=EXCLUDED.full_name,
        username=COALESCE(public.profiles.username,EXCLUDED.username),
        referred_by=COALESCE(public.profiles.referred_by,EXCLUDED.referred_by);
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_crown_user_blocked(p_user_id uuid,p_blocked boolean,p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_crown_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF;
  IF p_user_id IS NULL OR p_user_id=auth.uid() THEN RAISE EXCEPTION 'Invalid user selection'; END IF;
  UPDATE public.profiles SET is_blocked=p_blocked WHERE id=p_user_id AND role <> 'admin';
  IF NOT FOUND THEN RAISE EXCEPTION 'User not found or cannot be blocked'; END IF;
  RETURN jsonb_build_object('user_id',p_user_id,'is_blocked',p_blocked);
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_set_crown_user_blocked(uuid,boolean,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_set_crown_user_blocked(uuid,boolean,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_crown_referral_summary()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid();
DECLARE v_code text;
DECLARE v_count bigint;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT referral_code INTO v_code FROM public.profiles WHERE id=v_uid;
  IF v_code IS NULL THEN RAISE EXCEPTION 'Referral profile not found'; END IF;
  SELECT count(*) INTO v_count FROM public.profiles WHERE referred_by=v_uid;
  RETURN jsonb_build_object('referral_code',v_code,'referral_count',v_count);
END;
$function$;
REVOKE ALL ON FUNCTION public.get_crown_referral_summary() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_crown_referral_summary() TO authenticated;

CREATE OR REPLACE FUNCTION public.place_crown_demo_order(p_task_index integer,p_task_title text,p_amount numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric(14,2);
  v_order public.crown_demo_orders%ROWTYPE;
  v_task public.crown_demo_task_catalog%ROWTYPE;
  v_next integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF EXISTS (SELECT 1 FROM public.profiles WHERE id=v_uid AND is_blocked=true) THEN
    RAISE EXCEPTION 'Your Crown account is blocked. Contact support.';
  END IF;
  IF p_task_index IS NULL OR p_task_index<0 OR p_task_index>49 THEN RAISE EXCEPTION 'Invalid demo order'; END IF;
  SELECT * INTO v_task FROM public.crown_demo_task_catalog WHERE task_index=p_task_index AND active=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task is unavailable'; END IF;
  INSERT INTO public.crown_demo_wallets(user_id) VALUES(v_uid) ON CONFLICT(user_id) DO NOTHING;
  PERFORM 1 FROM public.crown_demo_wallets WHERE user_id=v_uid FOR UPDATE;
  SELECT balance INTO v_balance FROM public.crown_demo_wallets WHERE user_id=v_uid;
  SELECT COALESCE(max(task_index)+1,0) INTO v_next FROM public.crown_demo_orders WHERE user_id=v_uid AND status='confirmed';
  IF p_task_index<>v_next THEN RAISE EXCEPTION 'Complete the previous task first'; END IF;
  IF v_balance<v_task.amount THEN RAISE EXCEPTION 'Insufficient demo balance'; END IF;
  UPDATE public.crown_demo_wallets SET balance=balance-v_task.amount,total_spent=total_spent+v_task.amount,updated_at=now() WHERE user_id=v_uid;
  INSERT INTO public.crown_demo_orders(user_id,task_index,task_title,amount) VALUES(v_uid,v_task.task_index,v_task.task_title,v_task.amount) RETURNING * INTO v_order;
  INSERT INTO public.crown_demo_transactions(user_id,order_id,type,amount,note) VALUES(v_uid,v_order.id,'demo_order',v_task.amount,'Demo order confirmed');
  RETURN jsonb_build_object('order_id',v_order.id,'balance',v_balance-v_task.amount,
    'spent',(SELECT total_spent FROM public.crown_demo_wallets WHERE user_id=v_uid),
    'task_index',v_task.task_index,'task_title',v_task.task_title,'amount',v_task.amount);
END;
$function$;
