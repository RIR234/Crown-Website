alter table public.crown_demo_transactions
  drop constraint if exists crown_demo_transactions_type_check;
alter table public.crown_demo_transactions
  add constraint crown_demo_transactions_type_check
  check (type = any (array['demo_credit','demo_order','admin_credit','admin_debit','referral_bonus']::text[]));

create unique index if not exists crown_demo_referral_bonus_once_per_order
  on public.crown_demo_transactions(order_id, type)
  where type = 'referral_bonus' and order_id is not null;

create or replace function public.place_crown_demo_order(
  p_task_index integer, p_task_title text, p_amount numeric
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_balance numeric(14,2);
  v_order public.crown_demo_orders%rowtype;
  v_task public.crown_demo_task_catalog%rowtype;
  v_next integer;
  v_referrer uuid;
  v_bonus numeric(14,2);
  v_bonus_awarded boolean := false;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if exists (select 1 from public.profiles where id=v_uid and is_blocked=true) then raise exception 'Your Crown account is blocked. Contact support.'; end if;
  if p_task_index is null or p_task_index < 0 or p_task_index > 49 then raise exception 'Invalid demo order'; end if;
  select * into v_task from public.crown_demo_task_catalog where task_index=p_task_index and active=true;
  if not found then raise exception 'Task is unavailable'; end if;
  insert into public.crown_demo_wallets(user_id) values(v_uid) on conflict(user_id) do nothing;
  perform 1 from public.crown_demo_wallets where user_id=v_uid for update;
  select balance into v_balance from public.crown_demo_wallets where user_id=v_uid;
  select coalesce(max(task_index)+1,0) into v_next from public.crown_demo_orders where user_id=v_uid and status='confirmed';
  if p_task_index<>v_next then raise exception 'Complete the previous task first'; end if;
  if v_balance<v_task.amount then raise exception 'Insufficient demo balance'; end if;
  update public.crown_demo_wallets set balance=balance-v_task.amount,total_spent=total_spent+v_task.amount,updated_at=now() where user_id=v_uid;
  insert into public.crown_demo_orders(user_id,task_index,task_title,amount) values(v_uid,v_task.task_index,v_task.task_title,v_task.amount) returning * into v_order;
  insert into public.crown_demo_transactions(user_id,order_id,type,amount,note) values(v_uid,v_order.id,'demo_order',v_task.amount,'Demo order confirmed');
  select referred_by into v_referrer from public.profiles where id=v_uid;
  if v_referrer is not null and v_referrer<>v_uid
     and exists(select 1 from public.profiles where id=v_referrer and role<>'admin' and coalesce(is_blocked,false)=false) then
    v_bonus:=round(v_task.amount*0.10,2);
    if v_bonus>0 then
      insert into public.crown_demo_wallets(user_id) values(v_referrer) on conflict(user_id) do nothing;
      perform 1 from public.crown_demo_wallets where user_id=v_referrer for update;
      insert into public.crown_demo_transactions(user_id,order_id,type,amount,note)
      values(v_referrer,v_order.id,'referral_bonus',v_bonus,'10% referral bonus for confirmed order')
      on conflict(order_id,type) where type='referral_bonus' and order_id is not null do nothing;
      if found then
        update public.crown_demo_wallets set balance=balance+v_bonus,updated_at=now() where user_id=v_referrer;
        v_bonus_awarded:=true;
      end if;
    end if;
  end if;
  return jsonb_build_object('order_id',v_order.id,
    'balance',(select balance from public.crown_demo_wallets where user_id=v_uid),
    'spent',(select total_spent from public.crown_demo_wallets where user_id=v_uid),
    'task_index',v_task.task_index,'task_title',v_task.task_title,'amount',v_task.amount,
    'referral_bonus_awarded',v_bonus_awarded,'referral_bonus',case when v_bonus_awarded then v_bonus else 0 end);
end;
$function$;

create or replace function public.get_crown_referral_summary()
returns jsonb language plpgsql security definer set search_path = ''
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
  select coalesce(sum(amount),0) into v_bonus from public.crown_demo_transactions where user_id=v_uid and type='referral_bonus';
  return jsonb_build_object('referral_code',v_code,'referral_count',v_count,'referral_bonus_total',v_bonus);
end;
$function$;