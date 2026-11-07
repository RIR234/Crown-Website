-- Secure profile column updates, reverse referral rewards on refunds, and add exact admin summary counts.
revoke update on table public.profiles from authenticated;
grant update (full_name, username) on table public.profiles to authenticated;

alter table public.crown_demo_transactions drop constraint if exists crown_demo_transactions_type_check;
alter table public.crown_demo_transactions add constraint crown_demo_transactions_type_check
check (type = any (array['demo_credit','demo_order','admin_credit','admin_debit','referral_bonus','referral_bonus_reversal']::text[]));

create unique index if not exists crown_demo_referral_bonus_reversal_once
on public.crown_demo_transactions(order_id)
where type='referral_bonus_reversal' and order_id is not null;

create or replace function public.admin_cancel_crown_demo_order(p_order_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
  v_order public.crown_demo_orders%rowtype;
  v_balance numeric(14,2);
  v_bonus_tx public.crown_demo_transactions%rowtype;
  v_bonus_reversed numeric(14,2):=0;
  v_referrer_balance numeric(14,2);
begin
  if not public.is_crown_admin() then raise exception 'Admin access required'; end if;
  select * into v_order from public.crown_demo_orders where id=p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if v_order.status<>'confirmed' then raise exception 'Only confirmed orders can be cancelled'; end if;
  if exists(select 1 from public.crown_demo_orders where user_id=v_order.user_id and task_index>v_order.task_index and status='confirmed') then
    raise exception 'Only the latest confirmed demo order can be cancelled';
  end if;
  select * into v_bonus_tx from public.crown_demo_transactions
    where order_id=p_order_id and type='referral_bonus' limit 1 for update;
  if found then
    if exists(select 1 from public.crown_demo_transactions where order_id=p_order_id and type='referral_bonus_reversal') then
      raise exception 'Referral bonus was already reversed for this order';
    end if;
    update public.crown_demo_wallets set balance=balance-v_bonus_tx.amount,updated_at=now()
      where user_id=v_bonus_tx.user_id and balance>=v_bonus_tx.amount returning balance into v_referrer_balance;
    if not found then
      raise exception 'The inviter has already used this referral bonus. The bonus must be restored before this order can be refunded.';
    end if;
    insert into public.crown_demo_transactions(user_id,order_id,type,amount,note)
      values(v_bonus_tx.user_id,p_order_id,'referral_bonus_reversal',v_bonus_tx.amount,
      'Referral bonus reversed because the referred order was cancelled and refunded');
    v_bonus_reversed:=v_bonus_tx.amount;
  end if;
  update public.crown_demo_wallets set balance=balance+v_order.amount,
    total_spent=greatest(0,total_spent-v_order.amount),updated_at=now()
    where user_id=v_order.user_id returning balance into v_balance;
  update public.crown_demo_orders set status='cancelled' where id=p_order_id;
  insert into public.crown_demo_transactions(user_id,order_id,type,amount,note)
    values(v_order.user_id,p_order_id,'demo_credit',v_order.amount,'Demo order cancelled and demo credit returned');
  return jsonb_build_object('order_id',p_order_id,'balance',v_balance,'referral_bonus_reversed',v_bonus_reversed);
end;
$function$;

create or replace function public.get_crown_referral_summary()
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_code text;
  v_count bigint;
  v_bonus numeric(14,2);
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select referral_code into v_code from public.profiles where id=v_uid;
  if v_code is null then raise exception 'Referral profile not found'; end if;
  select count(*) into v_count from public.profiles where referred_by=v_uid;
  select coalesce(sum(case when type='referral_bonus' then amount else -amount end),0)
    into v_bonus from public.crown_demo_transactions
    where user_id=v_uid and type in ('referral_bonus','referral_bonus_reversal');
  return jsonb_build_object('referral_code',v_code,'referral_count',v_count,'referral_bonus_total',v_bonus);
end;
$function$;

create or replace function public.get_crown_admin_dashboard_summary()
returns jsonb language plpgsql security definer set search_path=''
as $function$
begin
  if not public.is_crown_admin() then raise exception 'Admin access required'; end if;
  return jsonb_build_object(
    'total_users',(select count(*) from public.profiles),
    'total_confirmed_orders',(select count(*) from public.crown_demo_orders where status='confirmed'),
    'confirmed_order_volume',(select coalesce(sum(amount),0) from public.crown_demo_orders where status='confirmed'),
    'total_orders',(select count(*) from public.crown_demo_orders),
    'total_ledger_entries',(select count(*) from public.crown_demo_transactions)
  );
end;
$function$;
revoke all on function public.get_crown_admin_dashboard_summary() from public,anon;
grant execute on function public.get_crown_admin_dashboard_summary() to authenticated;
