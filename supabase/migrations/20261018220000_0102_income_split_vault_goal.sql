-- ==============================================================================
-- 0102: Divisão por renda e meta mensal da caixinha dentro da cota
-- Descrição:
--   Tudo opcional: sem escolha vale o comportamento de sempre.
--
--   1. houses.income_visibility ('all' | 'admins' | 'self', padrão 'self'): quem
--      pode ler a renda mensal dos moradores. Imposto no banco pelas policies
--      de member_incomes: quem não pode ver a renda dos outros não a lê.
--   2. houses.split_basis ('manual' | 'income', padrão 'manual'): base do
--      rateio padrão da casa. 'income' calcula house_members.default_split_percent
--      proporcional às rendas informadas. Enquanto algum morador ativo não
--      tiver informado renda, nada muda e vale o rateio atual.
--   3. member_incomes (casa, morador, renda mensal em centavos): privada por
--      padrão. Cada morador lê e grava só a própria renda, por set_my_income;
--      a leitura da renda dos outros segue income_visibility
--      (can_view_member_incomes). Não há policy de escrita: só a RPC grava.
--   4. compute_income_split / apply_income_split: calculam e gravam os
--      percentuais (duas casas, a sobra do arredondamento vai a quem ganha
--      mais). Ficam fechadas ao app. get_income_split devolve só os percentuais
--      calculados, nunca a renda, para qualquer morador da casa.
--   5. savings_vaults.counts_in_quota (padrão false) e monthly_goal_cents: a
--      caixinha marcada soma a meta mensal à cota do Planejamento de Aportes
--      (sem meta mensal própria, o app usa o quanto guardar por mês até o
--      prazo). Só administradores e donos mudam as duas colunas.
--   6. update_house_settings parte da versão da 0101 e aceita income_visibility
--      e split_basis (só administradores), mantendo todos os campos anteriores.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Configurações da casa
-- ------------------------------------------------------------------------------
alter table public.houses
  add column if not exists income_visibility text not null default 'self'
    check (income_visibility in ('all', 'admins', 'self')),
  add column if not exists split_basis text not null default 'manual'
    check (split_basis in ('manual', 'income'));

comment on column public.houses.income_visibility is
  'Quem lê a renda mensal dos moradores: all, admins ou self (padrão) (0102).';
comment on column public.houses.split_basis is
  'Base do rateio padrão: manual (percentuais dos moradores) ou income (proporcional à renda) (0102).';

-- ------------------------------------------------------------------------------
-- 2. Renda mensal do morador (privada por padrão)
-- ------------------------------------------------------------------------------
create table if not exists public.member_incomes (
  house_id uuid not null references public.houses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  monthly_income_cents bigint not null check (monthly_income_cents > 0),
  updated_at timestamptz not null default now(),
  primary key (house_id, user_id)
);

alter table public.member_incomes enable row level security;

create or replace function public.can_view_member_incomes(p_house_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.is_house_member(p_house_id)
    and exists (
      select 1 from public.houses h
      where h.id = p_house_id
        and (h.income_visibility = 'all'
             or (h.income_visibility = 'admins' and public.is_house_admin(p_house_id)))
    );
$$;

revoke execute on function public.can_view_member_incomes(uuid) from public, anon;
grant execute on function public.can_view_member_incomes(uuid) to authenticated, service_role;

-- A própria renda sempre; a dos outros só se income_visibility permitir
drop policy if exists "member_incomes_select" on public.member_incomes;
create policy "member_incomes_select" on public.member_incomes for select
  using (
    (user_id = (select auth.uid()) and public.is_house_member(house_id))
    or public.can_view_member_incomes(house_id)
  );

-- Escrita só por set_my_income (sem policy de insert/update/delete)
revoke insert, update, delete on public.member_incomes from anon, authenticated;

-- ------------------------------------------------------------------------------
-- 3. Rateio proporcional à renda
-- ------------------------------------------------------------------------------
create or replace function public.compute_income_split(p_house_id uuid)
returns table (member_user_id uuid, share_percent numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_members integer;
  v_with_income integer;
  v_total bigint;
begin
  select count(*),
         count(mi.monthly_income_cents),
         coalesce(sum(mi.monthly_income_cents), 0)
    into v_members, v_with_income, v_total
  from public.house_members hm
  left join public.member_incomes mi
    on mi.house_id = hm.house_id and mi.user_id = hm.user_id
  where hm.house_id = p_house_id and hm.left_at is null;

  -- Sem renda de todos os moradores ativos, cai no rateio atual (sem linhas)
  if v_members = 0 or v_with_income <> v_members or v_total <= 0 then
    return;
  end if;

  return query
  with base as (
    select hm.user_id as uid,
           mi.monthly_income_cents as cents,
           hm.joined_at,
           round(mi.monthly_income_cents * 100.0 / v_total, 2) as pct
    from public.house_members hm
    join public.member_incomes mi
      on mi.house_id = hm.house_id and mi.user_id = hm.user_id
    where hm.house_id = p_house_id and hm.left_at is null
  ),
  ranked as (
    select b.*,
           100 - sum(b.pct) over () as diff,
           row_number() over (order by b.cents desc, b.joined_at, b.uid) as rn
    from base b
  )
  select r.uid, case when r.rn = 1 then r.pct + r.diff else r.pct end
  from ranked r;
end;
$$;

revoke execute on function public.compute_income_split(uuid) from public, anon, authenticated;
grant execute on function public.compute_income_split(uuid) to service_role;

create or replace function public.apply_income_split(p_house_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.house_members hm
  set default_split_percent = s.share_percent
  from public.compute_income_split(p_house_id) s
  where hm.house_id = p_house_id
    and hm.user_id = s.member_user_id
    and hm.left_at is null;
end;
$$;

revoke execute on function public.apply_income_split(uuid) from public, anon, authenticated;
grant execute on function public.apply_income_split(uuid) to service_role;

-- Só os percentuais calculados (nunca a renda), para qualquer morador da casa
create or replace function public.get_income_split(p_house_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_house_member(p_house_id) then
    raise exception 'Você não faz parte desta casa.';
  end if;
  return coalesce(
    (select jsonb_object_agg(s.member_user_id::text, s.share_percent)
     from public.compute_income_split(p_house_id) s),
    '{}'::jsonb
  );
end;
$$;

revoke execute on function public.get_income_split(uuid) from public, anon;
grant execute on function public.get_income_split(uuid) to authenticated, service_role;

-- Informa (ou limpa, com nulo) a própria renda mensal e refaz o rateio se a casa usa renda
create or replace function public.set_my_income(p_house_id uuid, p_income_cents bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_house_member(p_house_id) then
    raise exception 'Você não faz parte desta casa.';
  end if;
  if p_income_cents is not null and p_income_cents <= 0 then
    raise exception 'A renda deve ser maior que zero.';
  end if;

  if p_income_cents is null then
    delete from public.member_incomes
    where house_id = p_house_id and user_id = auth.uid();
  else
    insert into public.member_incomes (house_id, user_id, monthly_income_cents)
    values (p_house_id, auth.uid(), p_income_cents)
    on conflict (house_id, user_id) do update
      set monthly_income_cents = excluded.monthly_income_cents,
          updated_at = now();
  end if;

  if exists (select 1 from public.houses h where h.id = p_house_id and h.split_basis = 'income') then
    perform public.apply_income_split(p_house_id);
  end if;
end;
$$;

revoke execute on function public.set_my_income(uuid, bigint) from public, anon;
grant execute on function public.set_my_income(uuid, bigint) to authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 4. Caixinha dentro da cota
-- ------------------------------------------------------------------------------
alter table public.savings_vaults
  add column if not exists counts_in_quota boolean not null default false,
  add column if not exists monthly_goal_cents bigint
    check (monthly_goal_cents is null or monthly_goal_cents > 0);

comment on column public.savings_vaults.counts_in_quota is
  'Soma a meta mensal à cota do Planejamento de Aportes; false mantém o comportamento de antes (0102).';
comment on column public.savings_vaults.monthly_goal_cents is
  'Meta mensal de aporte; nulo usa o quanto guardar por mês até o prazo (0102).';

grant insert (counts_in_quota, monthly_goal_cents) on public.savings_vaults to authenticated;
grant update (counts_in_quota, monthly_goal_cents) on public.savings_vaults to authenticated;

create or replace function public.guard_savings_vault_quota()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if (tg_op = 'INSERT' and (new.counts_in_quota or new.monthly_goal_cents is not null))
     or (tg_op = 'UPDATE' and (
          new.counts_in_quota is distinct from old.counts_in_quota
          or new.monthly_goal_cents is distinct from old.monthly_goal_cents)) then
    if not public.is_house_admin(new.house_id) then
      raise exception 'Só administradores mudam a meta mensal da caixinha na cota.';
    end if;
  end if;
  return new;
end;
$$;

create or replace trigger trg_savings_vaults_guard_quota
  before insert or update on public.savings_vaults
  for each row execute function public.guard_savings_vault_quota();

-- ------------------------------------------------------------------------------
-- 5. update_house_settings: aceita income_visibility e split_basis (resto como na 0101)
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

  if p_settings ? 'import_matching' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam as janelas de casamento da importação.';
  end if;
  if p_settings ? 'import_matching' and not public.import_matching_valid(p_settings->'import_matching') then
    raise exception 'Janelas de casamento da importação inválidas.';
  end if;

  if p_settings ? 'import_defaults' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam o destino padrão da importação.';
  end if;
  if p_settings ? 'import_defaults' and not public.import_defaults_valid(p_settings->'import_defaults') then
    raise exception 'Destino padrão da importação inválido.';
  end if;

  if p_settings ? 'cash_label' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam o nome do Caixa.';
  end if;
  if p_settings ? 'cash_label' and not public.cash_label_valid(p_settings->'cash_label') then
    raise exception 'Nome do Caixa inválido.';
  end if;

  if p_settings ? 'shopping_units' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam as unidades de compra.';
  end if;
  if p_settings ? 'shopping_units' and not public.shopping_units_valid(p_settings->'shopping_units') then
    raise exception 'Unidades de compra inválidas.';
  end if;

  if p_settings ? 'income_visibility' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam quem vê a renda dos moradores.';
  end if;
  if p_settings ? 'income_visibility'
      and coalesce(p_settings->>'income_visibility', '') not in ('all', 'admins', 'self') then
    raise exception 'Visibilidade da renda inválida.';
  end if;

  if p_settings ? 'split_basis' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam a base da divisão padrão.';
  end if;
  if p_settings ? 'split_basis'
      and coalesce(p_settings->>'split_basis', '') not in ('manual', 'income') then
    raise exception 'Base da divisão padrão inválida.';
  end if;

  update public.houses set
    opening_balance_rule = case when p_settings ? 'opening_balance_rule'
      then nullif(p_settings->>'opening_balance_rule', '') else opening_balance_rule end,
    opening_inflow_rules = coalesce(p_settings->'opening_inflow_rules', opening_inflow_rules),
    closing_defaults = coalesce(p_settings->'closing_defaults', closing_defaults),
    new_member_split_policy = coalesce(p_settings->>'new_member_split_policy', new_member_split_policy),
    folego_params = coalesce(p_settings->'folego_params', folego_params),
    budget_alert_stages = coalesce(p_settings->'budget_alert_stages', budget_alert_stages),
    import_matching = coalesce(p_settings->'import_matching', import_matching),
    import_defaults = coalesce(p_settings->'import_defaults', import_defaults),
    cash_label = case when p_settings ? 'cash_label'
      then nullif(btrim(p_settings->>'cash_label'), '') else cash_label end,
    shopping_units = coalesce(p_settings->'shopping_units', shopping_units),
    income_visibility = coalesce(p_settings->>'income_visibility', income_visibility),
    split_basis = coalesce(p_settings->>'split_basis', split_basis),
    planner_history_cycles = coalesce((p_settings->>'planner_history_cycles')::smallint, planner_history_cycles),
    planner_mode = coalesce(p_settings->>'planner_mode', planner_mode),
    planner_adjust_percent = coalesce((p_settings->>'planner_adjust_percent')::smallint, planner_adjust_percent),
    planner_category_overrides = coalesce(p_settings->'planner_category_overrides', planner_category_overrides)
  where id = p_house_id
  returning * into v_row;

  -- Base "renda": recalcula o rateio padrão já com as rendas informadas
  if p_settings ? 'split_basis' and v_row.split_basis = 'income' then
    perform public.apply_income_split(p_house_id);
  end if;

  return jsonb_build_object(
    'opening_balance_rule', v_row.opening_balance_rule,
    'opening_inflow_rules', v_row.opening_inflow_rules,
    'closing_defaults', v_row.closing_defaults,
    'new_member_split_policy', v_row.new_member_split_policy,
    'folego_params', v_row.folego_params,
    'budget_alert_stages', v_row.budget_alert_stages,
    'import_matching', v_row.import_matching,
    'import_defaults', v_row.import_defaults,
    'cash_label', v_row.cash_label,
    'shopping_units', v_row.shopping_units,
    'income_visibility', v_row.income_visibility,
    'split_basis', v_row.split_basis,
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
