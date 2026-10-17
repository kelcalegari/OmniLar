-- ==============================================================================
-- 0083: Alertas do Assistente por categoria (opção a de plano_proximas_frentes.md, 4.5)
-- Descrição:
--   Uma vez por dia (a partir das 9h no fuso da casa), cada categoria de gasto
--   variável é comparada com a média dela nos últimos ciclos:
--   - previsto = média dos ciclos com gasto na categoria, entre os 3 anteriores
--     ao ciclo em andamento (sem histórico, não avisa);
--   - avisa ao chegar a 90% do previsto e de novo ao passar de 100%, uma vez
--     por etapa, categoria e ciclo (proactive_alert).
--   Gasto variável: o interruptor da categoria (is_variable_spend) ou, sem
--   escolha, o nome, como o app faz (ExpenseCategory.looksLikeVariableSpend).
--   O gasto do ciclo é o das despesas da casa (sem projeto) pela data em que
--   foram pagas ou lançadas; é uma aproximação do planejamento do app.
--   Quem recebe: os moradores; numa categoria com dono, só o dono. É do grupo
--   "assistente" das preferências e não é essencial.
-- ==============================================================================

create or replace function public.notification_category_is_variable(p_name text, p_flag boolean)
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(p_flag,
    lower(coalesce(p_name, '')) ~ '(mercado|alimenta|feira|luz|energia|água|agua|gás|gas)');
$$;

create or replace function public.notification_sched_category_budget(p_house_id uuid, p_today date, p_tz text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r jsonb := '{}'::jsonb;
  v_cycle record;
  v_prev record;
  v_starts date[] := '{}';
  v_ends date[] := '{}';
  c record;
  v_current bigint;
  v_spent bigint;
  v_hist bigint;
  v_hist_count integer;
  v_avg bigint;
  v_pct integer;
  v_stage integer;
  v_users uuid[];
  i integer;
begin
  select * into v_cycle from public.notification_cycle_for(p_house_id, p_today);
  -- Os 3 ciclos anteriores
  v_prev := v_cycle;
  for i in 1..3 loop
    select * into v_prev from public.notification_cycle_for(p_house_id, v_prev.cycle_start - 1);
    v_starts := v_starts || v_prev.cycle_start;
    v_ends := v_ends || v_prev.cycle_end;
  end loop;

  for c in
    select id, name, owner_member_id from public.categories
    where house_id = p_house_id
      and public.notification_category_is_variable(name, is_variable_spend)
  loop
    select coalesce(sum(amount_cents), 0) into v_current
    from public.house_expenses
    where house_id = p_house_id and category_id = c.id
      and deleted_at is null and project_id is null
      and (coalesce(paid_at, date) at time zone p_tz)::date between v_cycle.cycle_start and v_cycle.cycle_end;
    if v_current = 0 then
      continue;
    end if;

    v_hist := 0;
    v_hist_count := 0;
    for i in 1..3 loop
      select coalesce(sum(amount_cents), 0) into v_spent
      from public.house_expenses
      where house_id = p_house_id and category_id = c.id
        and deleted_at is null and project_id is null
        and (coalesce(paid_at, date) at time zone p_tz)::date between v_starts[i] and v_ends[i];
      if v_spent > 0 then
        v_hist := v_hist + v_spent;
        v_hist_count := v_hist_count + 1;
      end if;
    end loop;
    if v_hist_count = 0 then
      continue;
    end if;
    v_avg := v_hist / v_hist_count;

    v_pct := (v_current * 100 / greatest(v_avg, 1))::integer;
    v_stage := case when v_pct > 100 then 100 when v_pct >= 90 then 90 else 0 end;
    if v_stage = 0 then
      continue;
    end if;

    v_users := case when c.owner_member_id is not null then array[c.owner_member_id]
                    else public.notification_house_member_ids(p_house_id) end;

    r := public.notification_bump(r, 'proactive_alert', public.enqueue_notification(
      p_house_id, v_users, 'proactive_alert', 'assistente',
      case when v_stage = 100 then c.name || ' passou do previsto'
           else c.name || ' perto do previsto' end,
      c.name || case when v_stage = 100
                     then ' já passou do previsto para o ciclo: '
                     else ' já está em ' || v_pct || '% do previsto para o ciclo: ' end
        || public.notification_brl(v_current) || ' de ' || public.notification_brl(v_avg)
        || ' (média dos últimos ciclos).',
      '/casa', 'category', c.id,
      'proactive_alert:' || c.id || ':' || v_cycle.cycle_start || ':' || v_stage, false, '{}'::jsonb,
      null, null, null, v_current));
  end loop;
  return r;
end;
$$;

revoke execute on function public.notification_sched_category_budget(uuid, date, text) from public, anon, authenticated;

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
          || public.notification_sched_tasks(h.id, v_today)
          || public.notification_sched_category_budget(h.id, v_today, h.tz);
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
