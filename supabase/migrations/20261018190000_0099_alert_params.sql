-- ==============================================================================
-- 0099: Parâmetros dos alertas (orçamento por categoria, lembretes e resumo semanal)
-- Descrição:
--   Tudo o que antes era fixo nos agendadores de notificação (0070, 0079, 0083)
--   passa a ser escolha. Sem escolha vale o comportamento de sempre, então nada
--   muda até alguém ajustar nos Ajustes.
--
--   1. Estágios do alerta de orçamento (notification_sched_category_budget):
--      - houses.budget_alert_stages: lista de percentuais da média, em ordem
--        crescente (1 a 4 estágios, de 1 a 300). Padrão [90, 100].
--      - categories.budget_alert_stages: o mesmo por categoria; nulo segue a casa.
--      Um estágio abaixo de 100 vale ao chegar nele (pct >= estágio); de 100 para
--      cima, ao passar dele (pct > estágio), como o "passou do previsto" de
--      sempre. Avisa uma vez por estágio, categoria e ciclo.
--      Quem muda a da casa: administradores, por update_house_settings.
--   2. member_settings (0095) ganha, por morador:
--      - alert_hour: a partir de que hora (0 a 23, no fuso da casa) os lembretes
--        do dia chegam para ele (padrão 9);
--      - muted_reminders: grupos de lembrete que ele não quer: bills, invoices,
--        cycle, loans, tasks, budget (padrão: nenhum);
--      - weekly_day e weekly_hour: dia (0 = domingo a 6) e hora do resumo semanal
--        (padrão: domingo, 18h).
--      Avisos essenciais ignoram o silêncio e o horário. O filtro mora num
--      trigger de notifications que só age durante run_scheduled_notifications
--      (que informa a hora local da casa): o que ficou de fora não é gravado e
--      chega na rodada seguinte em que o morador estiver liberado, pois a chave
--      de repetição só vale para o que foi gravado.
--   3. notification_sched_weekly (0079) escolhe os moradores pelo dia e hora
--      de cada um, e run_scheduled_notifications (0083) chama os lembretes do dia
--      a partir da hora mais cedo entre os moradores.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Estágios do alerta de orçamento
-- ------------------------------------------------------------------------------
create or replace function public.budget_alert_stages_valid(p_stages jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_stages) = 'array'
    and jsonb_array_length(p_stages) between 1 and 4
    and not exists (
      select 1 from jsonb_array_elements(p_stages) e
      where jsonb_typeof(e.value) <> 'number'
        or (e.value #>> '{}') !~ '^[0-9]+(\.0+)?$'
        or (e.value #>> '{}')::numeric not between 1 and 300
    )
    and not exists (
      select 1
      from jsonb_array_elements(p_stages) with ordinality a(value, n)
      join jsonb_array_elements(p_stages) with ordinality b(value, n) on b.n = a.n + 1
      where (a.value #>> '{}')::numeric >= (b.value #>> '{}')::numeric
    );
$$;

alter table public.houses
  add column if not exists budget_alert_stages jsonb not null default '[90, 100]'::jsonb
    check (public.budget_alert_stages_valid(budget_alert_stages));

comment on column public.houses.budget_alert_stages is
  'Percentuais da média em que o alerta de orçamento da categoria avisa (0099). Padrão 90 e 100.';

alter table public.categories
  add column if not exists budget_alert_stages jsonb
    check (budget_alert_stages is null or public.budget_alert_stages_valid(budget_alert_stages));

comment on column public.categories.budget_alert_stages is
  'Estágios do alerta de orçamento só desta categoria; nulo segue houses.budget_alert_stages (0099).';

-- Maior estágio atingido (0 = nenhum): abaixo de 100 vale ao chegar, de 100 em diante ao passar
create or replace function public.notification_budget_stage(p_pct integer, p_stages jsonb)
returns integer
language sql
immutable
set search_path = public
as $$
  select coalesce(max((e.value #>> '{}')::integer), 0)
  from jsonb_array_elements(p_stages) e
  where case when (e.value #>> '{}')::integer < 100
             then p_pct >= (e.value #>> '{}')::integer
             else p_pct > (e.value #>> '{}')::integer end;
$$;

-- Alerta de categoria com os estágios da casa e da categoria (resto como na 0091)
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
  v_house_stages jsonb;
  i integer;
begin
  select coalesce(planner_history_cycles, 3), coalesce(budget_alert_stages, '[90, 100]'::jsonb)
  into v_cycles, v_house_stages
  from public.houses where id = p_house_id;
  v_cycles := coalesce(v_cycles, 3);
  v_house_stages := coalesce(v_house_stages, '[90, 100]'::jsonb);

  select * into v_cycle from public.notification_cycle_for(p_house_id, p_today);
  -- Os ciclos anteriores que entram na média
  v_prev := v_cycle;
  for i in 1..v_cycles loop
    select * into v_prev from public.notification_cycle_for(p_house_id, v_prev.cycle_start - 1);
    v_starts := v_starts || v_prev.cycle_start;
    v_ends := v_ends || v_prev.cycle_end;
  end loop;

  for c in
    select id, name, owner_member_id, budget_alert_stages from public.categories
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
    v_stage := public.notification_budget_stage(v_pct, coalesce(c.budget_alert_stages, v_house_stages));
    if v_stage = 0 then
      continue;
    end if;

    v_users := case when c.owner_member_id is not null then array[c.owner_member_id]
                    else public.notification_house_member_ids(p_house_id) end;

    r := public.notification_bump(r, 'proactive_alert', public.enqueue_notification(
      p_house_id, v_users, 'proactive_alert', 'assistente',
      case when v_stage >= 100 then c.name || ' passou do previsto'
           else c.name || ' perto do previsto' end,
      c.name || case when v_stage >= 100
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

-- ------------------------------------------------------------------------------
-- 2. Lembretes e resumo semanal por morador (member_settings, 0095)
-- ------------------------------------------------------------------------------
create or replace function public.member_settings_valid(p_settings jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_settings) = 'object'
    and not exists (
      select 1 from jsonb_each(p_settings) e
      where (e.key = 'launch_payer'
             and (jsonb_typeof(e.value) <> 'string' or e.value #>> '{}' not in ('me', 'house')))
        or (e.key in ('launch_payment_method_id', 'launch_category_id')
            and (jsonb_typeof(e.value) <> 'string'
                 or e.value #>> '{}' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))
        or (e.key in ('alert_hour', 'weekly_hour')
            and (jsonb_typeof(e.value) <> 'number'
                 or (e.value #>> '{}') !~ '^[0-9]+$'
                 or (e.value #>> '{}')::integer not between 0 and 23))
        or (e.key = 'weekly_day'
            and (jsonb_typeof(e.value) <> 'number'
                 or (e.value #>> '{}') !~ '^[0-9]+$'
                 or (e.value #>> '{}')::integer not between 0 and 6))
        or (e.key = 'muted_reminders'
            and (jsonb_typeof(e.value) <> 'array'
                 or exists (
                   select 1 from jsonb_array_elements(e.value) m
                   where jsonb_typeof(m.value) <> 'string'
                      or m.value #>> '{}' not in ('bills', 'invoices', 'cycle', 'loans', 'tasks', 'budget')
                 )))
    );
$$;

-- Grupo de lembrete de cada tipo do dia (nulo = não é lembrete do dia)
create or replace function public.notification_reminder_group(p_type text)
returns text
language sql
immutable
set search_path = public
as $$
  select case p_type
    when 'bill_due_soon' then 'bills'
    when 'bill_overdue' then 'bills'
    when 'recurring_generated' then 'bills'
    when 'invoice_closing' then 'invoices'
    when 'invoice_due_soon' then 'invoices'
    when 'cycle_closing_soon' then 'cycle'
    when 'cycle_ended' then 'cycle'
    when 'transfer_pending' then 'cycle'
    when 'contribution_pending' then 'cycle'
    when 'installment_due_soon' then 'loans'
    when 'installment_overdue' then 'loans'
    when 'task_due_soon' then 'tasks'
    when 'task_overdue' then 'tasks'
    when 'proactive_alert' then 'budget'
    else null
  end;
$$;

-- Durante run_scheduled_notifications (que grava a hora local da casa em
-- omnilar.sched_local), segura o lembrete do dia que o morador silenciou ou
-- que ainda não chegou na hora dele. Fora do agendador, não faz nada.
create or replace function public.notifications_member_alert_gate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_local text := current_setting('omnilar.sched_local', true);
  v_group text;
  v_settings jsonb;
begin
  if v_local is null or v_local = '' or new.is_essential then
    return new;
  end if;
  v_group := public.notification_reminder_group(new.type);
  if v_group is null then
    return new;
  end if;
  select settings into v_settings
  from public.member_settings
  where house_id = new.house_id and user_id = new.user_id;
  if v_settings is null then
    return new;
  end if;
  if v_settings->'muted_reminders' ? v_group
      or extract(hour from v_local::timestamp) < coalesce((v_settings->>'alert_hour')::integer, 9) then
    return null;
  end if;
  return new;
end;
$$;

create or replace trigger trg_notifications_member_alert_gate
  before insert on public.notifications
  for each row execute function public.notifications_member_alert_gate();

-- Resumo semanal: cada morador no dia e hora dele (padrão: domingo, 18h)
drop function if exists public.notification_sched_weekly(uuid, date);

create or replace function public.notification_sched_weekly(p_house_id uuid, p_today date, p_local timestamp)
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
  left join public.member_settings ms on ms.house_id = p_house_id and ms.user_id = m
  where not exists (
    select 1 from public.notification_settings ns where ns.user_id = m and not ns.weekly_summary
  )
    and extract(dow from p_local) = coalesce((ms.settings->>'weekly_day')::integer, 0)
    and extract(hour from p_local) >= coalesce((ms.settings->>'weekly_hour')::integer, 18);
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

revoke execute on function public.notification_sched_weekly(uuid, date, timestamp) from public, anon, authenticated;

-- ------------------------------------------------------------------------------
-- 3. Agendador (resto como na 0083)
-- ------------------------------------------------------------------------------
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
  v_reminders boolean;
  v_first_hour integer;
  v_houses integer := 0;
begin
  for h in
    select id, coalesce(nullif(timezone, ''), 'America/Sao_Paulo') as tz from public.houses
  loop
    begin
      v_local := p_now at time zone h.tz;
      v_today := v_local::date;
      -- Lembretes de evento: a partir das 9h no fuso da casa
      v_daily := extract(hour from v_local) >= 9;
      -- Demais lembretes do dia: a partir da hora mais cedo escolhida por um
      -- morador (9h para quem não escolheu); o gatilho segura os de cada um
      select coalesce(min(coalesce((ms.settings->>'alert_hour')::integer, 9)), 9) into v_first_hour
      from public.house_members m
      left join public.member_settings ms on ms.house_id = m.house_id and ms.user_id = m.user_id
      where m.house_id = h.id and m.left_at is null;
      v_reminders := extract(hour from v_local) >= v_first_hour;
      v_houses := v_houses + 1;

      perform set_config('omnilar.sched_local', v_local::text, true);

      v_part := public.notification_sched_events(h.id, p_now, v_today, h.tz, v_daily);
      if v_reminders then
        v_part := v_part
          || public.notification_sched_bills(h.id, v_today)
          || public.notification_sched_invoices(h.id, v_today)
          || public.notification_sched_cycle(h.id, v_today, h.tz)
          || public.notification_sched_loans(h.id, v_today)
          || public.notification_sched_tasks(h.id, v_today)
          || public.notification_sched_category_budget(h.id, v_today, h.tz);
      end if;
      -- Resumo semanal: o dia e a hora de cada morador (domingo, 18h, sem escolha)
      v_part := v_part || public.notification_sched_weekly(h.id, v_today, v_local);

      perform set_config('omnilar.sched_local', '', true);

      for v_item in select key, value::integer as n from jsonb_each_text(v_part) loop
        v_counts := public.notification_bump(v_counts, v_item.key, v_item.n);
      end loop;
    exception when others then
      perform set_config('omnilar.sched_local', '', true);
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

-- ------------------------------------------------------------------------------
-- 4. update_house_settings: aceita budget_alert_stages (resto como na 0098)
-- ------------------------------------------------------------------------------
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
  if (p_settings ? 'opening_balance_rule' or p_settings ? 'opening_inflow_rules')
      and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam como a sobra entra no rateio.';
  end if;
  if p_settings ? 'opening_inflow_rules'
      and not public.opening_inflow_rules_valid(p_settings->'opening_inflow_rules') then
    raise exception 'Regra das entradas no Caixa inválida.';
  end if;
  if p_settings ? 'closing_defaults' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam os padrões do fechamento.';
  end if;
  if p_settings ? 'closing_defaults'
      and not public.closing_defaults_valid(p_settings->'closing_defaults') then
    raise exception 'Padrões do fechamento inválidos.';
  end if;
  if p_settings ? 'new_member_split_policy' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam a divisão para quem entra na casa.';
  end if;
  if p_settings ? 'new_member_split_policy'
      and coalesce(p_settings->>'new_member_split_policy', '') not in ('equal', 'keep_current', 'ask') then
    raise exception 'Política de divisão para novo morador inválida.';
  end if;

  if p_settings ? 'folego_params' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam os parâmetros do Fôlego.';
  end if;
  if p_settings ? 'folego_params' and not public.folego_params_valid(p_settings->'folego_params') then
    raise exception 'Parâmetros do Fôlego inválidos.';
  end if;

  if p_settings ? 'budget_alert_stages' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam os estágios do alerta de orçamento.';
  end if;
  if p_settings ? 'budget_alert_stages'
      and not public.budget_alert_stages_valid(p_settings->'budget_alert_stages') then
    raise exception 'Estágios do alerta de orçamento inválidos.';
  end if;

  update public.houses set
    opening_balance_rule = case when p_settings ? 'opening_balance_rule'
      then nullif(p_settings->>'opening_balance_rule', '') else opening_balance_rule end,
    opening_inflow_rules = coalesce(p_settings->'opening_inflow_rules', opening_inflow_rules),
    closing_defaults = coalesce(p_settings->'closing_defaults', closing_defaults),
    new_member_split_policy = coalesce(p_settings->>'new_member_split_policy', new_member_split_policy),
    folego_params = coalesce(p_settings->'folego_params', folego_params),
    budget_alert_stages = coalesce(p_settings->'budget_alert_stages', budget_alert_stages),
    planner_history_cycles = coalesce((p_settings->>'planner_history_cycles')::smallint, planner_history_cycles),
    planner_mode = coalesce(p_settings->>'planner_mode', planner_mode),
    planner_adjust_percent = coalesce((p_settings->>'planner_adjust_percent')::smallint, planner_adjust_percent),
    planner_category_overrides = coalesce(p_settings->'planner_category_overrides', planner_category_overrides)
  where id = p_house_id
  returning * into v_row;

  return jsonb_build_object(
    'opening_balance_rule', v_row.opening_balance_rule,
    'opening_inflow_rules', v_row.opening_inflow_rules,
    'closing_defaults', v_row.closing_defaults,
    'new_member_split_policy', v_row.new_member_split_policy,
    'folego_params', v_row.folego_params,
    'budget_alert_stages', v_row.budget_alert_stages,
    'planner_history_cycles', v_row.planner_history_cycles,
    'planner_mode', v_row.planner_mode,
    'planner_adjust_percent', v_row.planner_adjust_percent,
    'planner_category_overrides', v_row.planner_category_overrides
  );
end;
$$;

revoke execute on function public.update_house_settings(uuid, jsonb) from public, anon;
grant execute on function public.update_house_settings(uuid, jsonb) to authenticated, service_role;

notify pgrst, 'reload schema';
