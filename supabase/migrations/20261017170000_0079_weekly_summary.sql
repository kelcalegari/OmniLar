-- ==============================================================================
-- 0079: Resumo semanal (fase 6 do plano de notificações)
-- Descrição:
--   Domingo, a partir das 18h no fuso da casa, cada morador com o resumo ligado
--   recebe um aviso com os gastos da casa nos últimos 7 dias e as contas que
--   vencem nos próximos 7 (semana sem nada disso não gera aviso). O resumo passa a vir ligado (decisão 4.2 de
--   plano_proximas_frentes.md): quem não tem linha em notification_settings
--   recebe; quem desligou na tela de preferências, não.
--   Não é essencial: segue o grupo "despesas" das preferências.
--   O Fôlego fica fora do texto: a conta dele é feita no app.
-- ==============================================================================

alter table public.notification_settings alter column weekly_summary set default true;
-- Ninguém escolheu ainda (a tela de preferências é nova): todos passam a receber
update public.notification_settings set weekly_summary = true where not weekly_summary;

create or replace function public.notification_sched_weekly(p_house_id uuid, p_today date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r jsonb := '{}'::jsonb;
  v_users uuid[];
  v_spent bigint;
  v_bills integer;
  v_bills_total bigint;
  v_tz text;
  v_body text;
begin
  select array_agg(m) into v_users
  from unnest(public.notification_house_member_ids(p_house_id)) m
  where not exists (
    select 1 from public.notification_settings ns where ns.user_id = m and not ns.weekly_summary
  );
  if v_users is null then
    return r;
  end if;

  select coalesce(nullif(timezone, ''), 'America/Sao_Paulo') into v_tz from public.houses where id = p_house_id;

  -- Gastos da casa lançados nos últimos 7 dias (sem projetos)
  select coalesce(sum(amount_cents), 0) into v_spent
  from public.house_expenses
  where house_id = p_house_id
    and deleted_at is null
    and project_id is null
    and (date at time zone v_tz)::date between p_today - 6 and p_today;

  -- Contas pendentes que vencem na semana que vem (compra no cartão entra na fatura)
  select count(*), coalesce(sum(x.amount_cents), 0) into v_bills, v_bills_total
  from public.house_expenses x
  left join public.payment_methods pm on pm.id = x.payment_method_id
  where x.house_id = p_house_id
    and x.status = 'pending'
    and x.deleted_at is null
    and x.paid_at is null
    and x.project_id is null
    and coalesce(pm.type, '') <> 'card'
    and x.due_date between p_today + 1 and p_today + 7;

  -- Semana sem gasto e sem conta pela frente: nada a contar
  if v_spent = 0 and v_bills = 0 then
    return r;
  end if;

  v_body := 'Gastos da semana: ' || public.notification_brl(v_spent) || '. '
    || case
         when v_bills = 0 then 'Nenhuma conta vence nos próximos 7 dias.'
         when v_bills = 1 then '1 conta vence nos próximos 7 dias: ' || public.notification_brl(v_bills_total) || '.'
         else v_bills || ' contas vencem nos próximos 7 dias, somando ' || public.notification_brl(v_bills_total) || '.'
       end;

  r := public.notification_bump(r, 'weekly_summary', public.enqueue_notification(
    p_house_id, v_users, 'weekly_summary', 'despesas',
    'Resumo da semana', v_body,
    '/casa', null, null,
    'weekly_summary:' || p_house_id || ':' || p_today, false, '{}'::jsonb,
    null, null, null, v_spent));
  return r;
end;
$$;

revoke execute on function public.notification_sched_weekly(uuid, date) from public, anon, authenticated;

create or replace function public.run_scheduled_notifications(
  p_now timestamptz default now(),
  p_strict boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_counts jsonb := '{}'::jsonb;
  v_part jsonb;
  v_item record;
  h record;
  v_local timestamp;
  v_today date;
  v_daily boolean;
  v_houses integer := 0;
begin
  for h in
    select id, coalesce(nullif(timezone, ''), 'America/Sao_Paulo') as tz from public.houses
  loop
    begin
      v_local := p_now at time zone h.tz;
      v_today := v_local::date;
      -- Lembretes de dia: a partir das 9h no fuso da casa
      v_daily := extract(hour from v_local) >= 9;
      v_houses := v_houses + 1;

      v_part := public.notification_sched_events(h.id, p_now, v_today, h.tz, v_daily);
      if v_daily then
        v_part := v_part
          || public.notification_sched_bills(h.id, v_today)
          || public.notification_sched_invoices(h.id, v_today)
          || public.notification_sched_cycle(h.id, v_today, h.tz)
          || public.notification_sched_loans(h.id, v_today)
          || public.notification_sched_tasks(h.id, v_today);
      end if;
      -- Resumo semanal: domingo, a partir das 18h no fuso da casa
      if extract(dow from v_local) = 0 and extract(hour from v_local) >= 18 then
        v_part := v_part || public.notification_sched_weekly(h.id, v_today);
      end if;

      for v_item in select key, value::integer as n from jsonb_each_text(v_part) loop
        v_counts := public.notification_bump(v_counts, v_item.key, v_item.n);
      end loop;
    exception when others then
      if p_strict then raise; end if;
      raise warning 'run_scheduled_notifications: casa % ignorada: %', h.id, sqlerrm;
    end;
  end loop;

  begin
    v_part := public.notification_sched_accounts(p_now);
    for v_item in select key, value::integer as n from jsonb_each_text(v_part) loop
      v_counts := public.notification_bump(v_counts, v_item.key, v_item.n);
    end loop;
  exception when others then
    if p_strict then raise; end if;
    raise warning 'run_scheduled_notifications: avisos de conta ignorados: %', sqlerrm;
  end;

  return jsonb_build_object('houses', v_houses, 'created', v_counts);
end;
$$;
