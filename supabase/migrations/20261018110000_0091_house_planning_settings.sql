-- ==============================================================================
-- 0091: Configurações de planejamento e fechamento da casa
-- Descrição:
--   1. opening_balance_rule: o que o dinheiro que já está no Caixa no início
--      do ciclo (sobra do anterior, empréstimos do Caixa pagos de volta) faz no
--      rateio, no planejador e no fechamento (o cálculo é do app):
--      - reduce_quotas: abate o aporte de cada morador;
--      - cover_excess: só paga o que passar do valor fixo somado;
--      - keep: fica no Caixa como folga.
--      Nulo: a casa ainda não escolheu e vale o comportamento anterior.
--   2. Planejador de aportes guardado na casa (antes ficava só no aparelho e
--      se perdia ao reabrir): ciclos da média, modo, percentual dos modos
--      Econômico e Com folga, e valores ajustados à mão por categoria.
--   3. update_house_settings: qualquer morador ajusta o planejador; só
--      administradores mudam a regra do rateio.
--   4. O alerta de categoria (0083) passa a usar os mesmos ciclos da média
--      que o planejador (antes era sempre 3).
-- ==============================================================================

alter table public.houses
  add column if not exists opening_balance_rule text
    check (opening_balance_rule in ('reduce_quotas', 'cover_excess', 'keep')),
  add column if not exists planner_history_cycles smallint not null default 3
    check (planner_history_cycles between 1 and 12),
  add column if not exists planner_mode text not null default 'historical_average'
    check (planner_mode in ('economical', 'historical_average', 'comfortable')),
  add column if not exists planner_adjust_percent smallint not null default 10
    check (planner_adjust_percent between 0 and 50),
  add column if not exists planner_category_overrides jsonb not null default '{}'::jsonb
    check (jsonb_typeof(planner_category_overrides) = 'object');

create or replace function public.update_house_settings(p_house_id uuid, p_settings jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.houses%rowtype;
begin
  if auth.uid() is null or not public.is_house_member(p_house_id) then
    raise exception 'Você não faz parte desta casa.';
  end if;
  if p_settings ? 'opening_balance_rule' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam como a sobra entra no rateio.';
  end if;

  update public.houses set
    opening_balance_rule = case when p_settings ? 'opening_balance_rule'
      then nullif(p_settings->>'opening_balance_rule', '') else opening_balance_rule end,
    planner_history_cycles = coalesce((p_settings->>'planner_history_cycles')::smallint, planner_history_cycles),
    planner_mode = coalesce(p_settings->>'planner_mode', planner_mode),
    planner_adjust_percent = coalesce((p_settings->>'planner_adjust_percent')::smallint, planner_adjust_percent),
    planner_category_overrides = coalesce(p_settings->'planner_category_overrides', planner_category_overrides)
  where id = p_house_id
  returning * into v_row;

  return jsonb_build_object(
    'opening_balance_rule', v_row.opening_balance_rule,
    'planner_history_cycles', v_row.planner_history_cycles,
    'planner_mode', v_row.planner_mode,
    'planner_adjust_percent', v_row.planner_adjust_percent,
    'planner_category_overrides', v_row.planner_category_overrides
  );
end;
$$;

revoke execute on function public.update_house_settings(uuid, jsonb) from public, anon;
grant execute on function public.update_house_settings(uuid, jsonb) to authenticated, service_role;

-- Alerta de categoria com os ciclos da média da casa
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
  v_cycles integer;
  i integer;
begin
  select coalesce(planner_history_cycles, 3) into v_cycles from public.houses where id = p_house_id;
  v_cycles := coalesce(v_cycles, 3);

  select * into v_cycle from public.notification_cycle_for(p_house_id, p_today);
  -- Os ciclos anteriores que entram na média
  v_prev := v_cycle;
  for i in 1..v_cycles loop
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
    for i in 1..v_cycles loop
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
