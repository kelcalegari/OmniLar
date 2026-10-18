-- ==============================================================================
-- 0098: Parâmetros do Fôlego, do gasto variável, das recorrentes e da transição
-- Descrição:
--   houses.folego_params (jsonb, validado) guarda o que antes era fixo no app e
--   no banco. Chave ausente vale o padrão de sempre, então nada muda até um
--   administrador ajustar nos Ajustes:
--     warning_percent             15    Fôlego abaixo desta % dos aportes = atenção
--     commitment_warning_percent  65    barra de comprometimento em atenção
--     commitment_danger_percent   85    barra de comprometimento crítica
--     comfortable_daily_cents     5000  gasto diário seguro a partir daqui é confortável
--     recurring_horizon_months    3     meses à frente em que nascem as recorrentes (1 a 6)
--     transition_min_days         15    mínimo do ciclo de transição na troca do dia
--                                       (15 a 30; change_house_cycle_start_day, 0044,
--                                       aceita ciclos de 15 a 46 dias)
--   Os percentuais vão de 0 a 100 e o de atenção da barra fica abaixo do crítico.
--   Quem muda: administradores, por update_house_settings.
--
--   Gasto variável só pelo interruptor da categoria (is_variable_spend): o
--   palpite pelo nome sai do app e de notification_category_is_variable (0083).
--   Para o comportamento não mudar, as categorias sem escolha cujo nome seria
--   adivinhado como variável (mercado, alimenta, feira, luz, energia, água,
--   gás) ganham is_variable_spend = true, e as outras da mesma casa, false.
--   Casa em que nenhuma categoria parecia variável continua sem escolha. Categoria
--   nova sem escolha (as padrão de uma casa nova) recebe o mesmo palpite ao ser
--   criada, por trigger; o app cadastra com o interruptor explícito.
--
--   generate_recurring_expenses (0049) e notification_cycle_for (0070) leem o
--   horizonte e a transição da casa. update_house_settings (0097) grava e
--   devolve folego_params. O resto segue como nelas.
-- ==============================================================================

create or replace function public.folego_params_valid(p_params jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_params) = 'object'
    and not exists (
      select 1 from jsonb_each(p_params) e
      where e.key not in (
          'warning_percent', 'commitment_warning_percent', 'commitment_danger_percent',
          'comfortable_daily_cents', 'recurring_horizon_months', 'transition_min_days')
        or jsonb_typeof(e.value) <> 'number'
        or (e.value #>> '{}') !~ '^[0-9]+(\.[0-9]+)?$'
        or (e.key in ('warning_percent', 'commitment_warning_percent', 'commitment_danger_percent')
            and (e.value #>> '{}')::numeric > 100)
        or (e.key in ('comfortable_daily_cents', 'recurring_horizon_months', 'transition_min_days')
            and (e.value #>> '{}')::numeric <> trunc((e.value #>> '{}')::numeric))
        or (e.key = 'comfortable_daily_cents' and (e.value #>> '{}')::numeric > 100000000)
        or (e.key = 'recurring_horizon_months' and (e.value #>> '{}')::numeric not between 1 and 6)
        or (e.key = 'transition_min_days' and (e.value #>> '{}')::numeric not between 15 and 30)
    )
    and coalesce((p_params->>'commitment_warning_percent')::numeric, 65)
      < coalesce((p_params->>'commitment_danger_percent')::numeric, 85);
$$;

-- Valor inteiro de um parâmetro, ou o padrão quando a casa não definiu
create or replace function public.folego_param_int(p_params jsonb, p_key text, p_default integer)
returns integer
language sql
immutable
set search_path = public
as $$
  select coalesce((p_params->>p_key)::numeric::integer, p_default);
$$;

alter table public.houses
  add column if not exists folego_params jsonb not null default '{}'::jsonb
    check (public.folego_params_valid(folego_params));

comment on column public.houses.folego_params is
  'Parâmetros do Fôlego, das recorrentes e da transição do dia do ciclo; chave ausente vale o padrão (0098).';

-- ------------------------------------------------------------------------------
-- Gasto variável só pelo interruptor da categoria
-- ------------------------------------------------------------------------------
update public.categories c
set is_variable_spend = lower(coalesce(c.name, '')) ~ '(mercado|alimenta|feira|luz|energia|água|agua|gás|gas)'
where c.is_variable_spend is null
  and exists (
    select 1 from public.categories m
    where m.house_id = c.house_id
      and m.is_variable_spend is null
      and lower(coalesce(m.name, '')) ~ '(mercado|alimenta|feira|luz|energia|água|agua|gás|gas)'
  );

-- Categoria nova sem escolha (as padrão de uma casa nova, por exemplo) nasce com
-- o palpite de sempre gravado no próprio interruptor; daí em diante só ele vale
create or replace function public.categories_default_variable_spend()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.is_variable_spend is null then
    new.is_variable_spend :=
      lower(coalesce(new.name, '')) ~ '(mercado|alimenta|feira|luz|energia|água|agua|gás|gas)';
  end if;
  return new;
end;
$$;

create or replace trigger categories_default_variable_spend
  before insert on public.categories
  for each row execute function public.categories_default_variable_spend();

comment on column public.categories.is_variable_spend is
  'Gasto variável no Planejamento de Aportes (estimado pela média). Só este interruptor decide; nulo vale como não variável.';

create or replace function public.notification_category_is_variable(p_name text, p_flag boolean)
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(p_flag, false);
$$;

-- ------------------------------------------------------------------------------
-- Horizonte das recorrentes (resto como na 0049)
-- ------------------------------------------------------------------------------
create or replace function public.generate_recurring_expenses(p_house_id uuid, p_until date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_timezone text;
  v_until date;
  v_horizon integer;
  v_series public.house_expenses%rowtype;
  v_template public.house_expenses%rowtype;
  v_last_due date;
  v_next_due date;
  v_month date;
  v_due_day integer;
  v_new_id uuid;
  v_created integer := 0;
  v_guard integer;
begin
  if not public.is_house_member(p_house_id) then
    raise exception 'Acesso negado: você não é membro desta casa';
  end if;

  select timezone, public.folego_param_int(folego_params, 'recurring_horizon_months', 3)
  into v_timezone, v_horizon
  from public.houses where id = p_house_id;

  -- Nunca gera além do horizonte da casa (três meses, se ela não mudou), por
  -- mais longe que a tela navegue
  v_until := least(p_until, (current_date + make_interval(months => coalesce(v_horizon, 3)))::date);

  -- Duas telas abertas ao mesmo tempo não geram a mesma conta em dobro
  perform pg_advisory_xact_lock(hashtextextended('recurring-expenses:' || p_house_id::text, 0));

  for v_series in
    select * from public.house_expenses
    where house_id = p_house_id
      and is_recurring
      and is_active
      and recurring_series_id is null
      and project_id is null
  loop
    select max(due_date) into v_last_due
    from public.house_expenses
    where id = v_series.id or recurring_series_id = v_series.id;

    v_guard := 0;
    loop
      v_guard := v_guard + 1;
      exit when v_guard > 12;

      -- Modelo: a ocorrência mais recente ainda existente (carrega edições
      -- feitas com "esta e as próximas"); sem nenhuma, a matriz.
      select * into v_template
      from public.house_expenses
      where (id = v_series.id or recurring_series_id = v_series.id)
        and deleted_at is null
      order by due_date desc
      limit 1;
      if not found then
        v_template := v_series;
      end if;

      -- O dia de vencimento também vem do modelo: mudá-lo com "esta e as
      -- próximas" vale para as contas dos meses seguintes
      v_due_day := coalesce(
        v_template.due_day,
        v_series.due_day,
        extract(day from v_series.due_date)::integer
      );
      v_month := (date_trunc('month', v_last_due) + interval '1 month')::date;
      v_next_due := least(
        v_month + (v_due_day - 1),
        (v_month + interval '1 month - 1 day')::date
      );
      exit when v_next_due > v_until;

      insert into public.house_expenses (
        house_id, title, amount_cents, category_id, payment_method_id, paid_by_id,
        paid_out_of_pocket, due_date, cycle_start_date, split_type, notes, status,
        created_by, is_recurring, is_variable, due_day, is_active,
        recurring_series_id, date
      ) values (
        p_house_id, v_template.title, v_template.amount_cents, v_template.category_id,
        v_template.payment_method_id, v_template.paid_by_id,
        v_template.paid_out_of_pocket, v_next_due, v_next_due, v_template.split_type,
        v_template.notes, 'pending',
        coalesce(auth.uid(), v_series.created_by), true, v_template.is_variable, v_due_day, true,
        v_series.id, (v_next_due::timestamp + interval '12 hours') at time zone coalesce(v_timezone, 'America/Sao_Paulo')
      )
      on conflict (recurring_series_id, due_date) where recurring_series_id is not null do nothing
      returning id into v_new_id;

      if v_new_id is not null then
        insert into public.split_rules (
          expense_id, member_id, percentage_basis_points, fixed_amount_cents, calculated_cents
        )
        select v_new_id, member_id, percentage_basis_points, fixed_amount_cents, calculated_cents
        from public.split_rules
        where expense_id = v_template.id;

        insert into public.house_expense_items (
          expense_id, title, amount_cents, category_id, responsible_member_id, split_type
        )
        select v_new_id, title, amount_cents, category_id, responsible_member_id, split_type
        from public.house_expense_items
        where expense_id = v_template.id;

        v_created := v_created + 1;
      end if;

      v_new_id := null;
      v_last_due := v_next_due;
    end loop;
  end loop;

  return v_created;
end;
$$;

-- ------------------------------------------------------------------------------
-- Transição do dia do ciclo (resto como na 0070)
-- ------------------------------------------------------------------------------
create or replace function public.notification_cycle_for(
  p_house_id uuid, p_date date, out cycle_start date, out cycle_end date
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_day integer;
  v_schedule jsonb;
  v_change record;
  v_active_from date;
  v_active_day integer;
  v_base integer;
  v_first date;
  v_s date;
  v_first_regular date;
  v_transition integer;
begin
  select h.cycle_start_day, coalesce(h.cycle_day_schedule, '[]'::jsonb),
         public.folego_param_int(h.folego_params, 'transition_min_days', 15)
  into v_day, v_schedule, v_transition
  from public.houses h where h.id = p_house_id;

  for v_change in
    select (e->>'from')::date as from_date, (e->>'day')::integer as day
    from jsonb_array_elements(v_schedule) e
    where e->>'from' is not null and e->>'day' is not null
    order by (e->>'from')::date
  loop
    if v_change.from_date <= p_date then
      v_active_from := v_change.from_date;
      v_active_day := v_change.day;
    end if;
  end loop;

  if v_active_from is null then
    select (e->>'previous_day')::integer into v_base
    from jsonb_array_elements(v_schedule) e
    where e->>'from' is not null and e->>'previous_day' is not null
    order by (e->>'from')::date
    limit 1;
    select r.cycle_start, r.cycle_end into cycle_start, cycle_end
    from public.notification_regular_cycle(p_date, coalesce(v_base, v_day)) r;
    return;
  end if;

  -- Primeiro início regular no dia novo, transition_min_days (15 por padrão) depois da troca
  v_first := date_trunc('month', v_active_from + v_transition)::date;
  v_s := public.notification_month_day(v_first, v_active_day);
  if v_s >= v_active_from + v_transition then
    v_first_regular := v_s;
  else
    v_first_regular := public.notification_month_day((v_first + interval '1 month')::date, v_active_day);
  end if;

  if p_date < v_first_regular then
    cycle_start := v_active_from;
    cycle_end := v_first_regular - 1;
  else
    select r.cycle_start, r.cycle_end into cycle_start, cycle_end
    from public.notification_regular_cycle(p_date, v_active_day) r;
  end if;
end;
$$;

-- ------------------------------------------------------------------------------
-- update_house_settings: aceita folego_params
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

  update public.houses set
    opening_balance_rule = case when p_settings ? 'opening_balance_rule'
      then nullif(p_settings->>'opening_balance_rule', '') else opening_balance_rule end,
    opening_inflow_rules = coalesce(p_settings->'opening_inflow_rules', opening_inflow_rules),
    closing_defaults = coalesce(p_settings->'closing_defaults', closing_defaults),
    new_member_split_policy = coalesce(p_settings->>'new_member_split_policy', new_member_split_policy),
    folego_params = coalesce(p_settings->'folego_params', folego_params),
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
