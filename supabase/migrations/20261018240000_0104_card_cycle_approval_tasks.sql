-- ==============================================================================
-- 0104: Ciclo da compra no cartão, aprovação por valor e tarefas com rodízio
-- Descrição:
--   Último item do plano de parametrizações. Sem escolha vale o comportamento
--   de sempre, então nada muda até alguém ajustar nos Ajustes ou na tarefa.
--
--   1. payment_methods.cycle_assignment: em qual ciclo a compra no cartão conta.
--        'invoice_due'   (padrão, o de sempre): no ciclo do vencimento da fatura
--                        ou, paga a fatura, no ciclo em que ela foi paga;
--        'purchase_date' : no ciclo da data da compra, com a fatura paga ou não.
--      Mesma regra do app (expenseBelongsToCycle). O único espelho no banco é
--      expense_counts_in_closed_cycle (trava de ciclo fechado), refeito aqui a
--      partir da 0030. Quem edita: quem edita formas de pagamento (policy da 0017).
--   2. houses.approval_threshold_cents: empréstimo acima desse valor, lançado
--      pelo app, nasce aguardando aprovação (p2p_loans.awaiting_approval), no
--      modelo do aceite da 0082: fica fora do fechamento do ciclo até um
--      morador com a permissão editar_configuracoes (administradores sempre)
--      aprovar ou recusar (decide_p2p_loan_approval). Recusar cancela. Quem
--      lançou só aprova o próprio empréstimo se não houver outro administrador.
--      Nulo (padrão) = não há aprovação por valor. Os que as funções do banco
--      criam (fechamento, fatura paga pelo Caixa) nascem aprovados, e os
--      empréstimos que já existem contam como aprovados. Gasto comum não tem
--      aprovação no banco: o limite vale só para empréstimos.
--   3. update_house_settings parte da 0103 e ganha approval_threshold_cents
--      (editar_configuracoes). Todos os campos anteriores, incluindo permissions,
--      seguem como estavam.
--   4. tasks.recurrence ('daily' | 'weekly' | 'monthly' | nulo), rotation_members
--      (uuid[] na ordem do rodízio) e next_assignee: ao concluir uma tarefa que
--      se repete, o gatilho cria a próxima ocorrência para o próximo do rodízio
--      (moradores que saíram da casa são pulados) e a concluída deixa de se
--      repetir. Tarefa sem recurrence (todas as atuais) não muda.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Ciclo da compra no cartão
-- ------------------------------------------------------------------------------
alter table public.payment_methods
  add column if not exists cycle_assignment text not null default 'invoice_due'
    check (cycle_assignment in ('invoice_due', 'purchase_date'));

comment on column public.payment_methods.cycle_assignment is
  'Ciclo em que a compra no cartão conta: invoice_due (vencimento/pagamento da fatura, padrão) ou purchase_date (data da compra) (0104).';

-- A despesa conta em um ciclo já fechado? (parte da 0030) Cartão com
-- purchase_date conta pela data da compra, paga ou não.
create or replace function public.expense_counts_in_closed_cycle(e public.house_expenses)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_timezone text;
  v_day date;
  v_is_card boolean := false;
  v_assignment text;
begin
  if e.project_id is not null or e.deleted_at is not null then
    return false;
  end if;
  if not public.is_house_member(e.house_id) then
    return false;
  end if;

  select timezone into v_timezone from public.houses where id = e.house_id;

  select true, pm.cycle_assignment into v_is_card, v_assignment
  from public.payment_methods pm
  where pm.id = e.payment_method_id and pm.type = 'card';
  v_is_card := coalesce(v_is_card, false);

  if v_is_card and v_assignment = 'purchase_date' and e.due_date is not null then
    v_day := (e.date at time zone v_timezone)::date;
    return public.is_date_in_closed_cycle(e.house_id, v_day);
  end if;

  if e.status <> 'paid' then
    return false;
  end if;

  if v_is_card then
    v_day := coalesce((e.paid_at at time zone v_timezone)::date, e.due_date);
  else
    v_day := coalesce(
      (e.paid_at at time zone v_timezone)::date,
      (e.date at time zone v_timezone)::date,
      e.due_date
    );
  end if;

  return public.is_date_in_closed_cycle(e.house_id, v_day);
end;
$$;

-- ------------------------------------------------------------------------------
-- 2. Aprovação por valor
-- ------------------------------------------------------------------------------
alter table public.houses
  add column if not exists approval_threshold_cents bigint
    check (approval_threshold_cents is null or approval_threshold_cents > 0);

comment on column public.houses.approval_threshold_cents is
  'Empréstimo acima deste valor (centavos) pede aprovação de quem administra; nulo = sem aprovação por valor (0104).';

alter table public.p2p_loans
  add column if not exists awaiting_approval boolean not null default false,
  add column if not exists approved_by uuid references auth.users(id) on delete set null,
  add column if not exists approved_at timestamptz;

-- Roda com as permissões de quem grava (sem security definer), como o aceite da
-- 0082: current_user diz se veio do app (authenticated) ou de uma função do banco.
create or replace function public.guard_p2p_loan_approval()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_by_app boolean := current_user = 'authenticated';
  v_threshold bigint;
begin
  if TG_OP = 'INSERT' then
    new.approved_by := null;
    new.approved_at := null;
    new.awaiting_approval := false;
    if v_by_app then
      select approval_threshold_cents into v_threshold from public.houses where id = new.house_id;
      if v_threshold is not null and new.total_amount_cents > v_threshold then
        new.awaiting_approval := true;
      end if;
    end if;
    return new;
  end if;

  -- Só decide_p2p_loan_approval tira o empréstimo da espera (ou o põe nela)
  if v_by_app and new.awaiting_approval is distinct from old.awaiting_approval then
    raise exception 'A aprovação do empréstimo é decidida por quem administra a casa.';
  end if;
  if v_by_app and (new.approved_by is distinct from old.approved_by
                   or new.approved_at is distinct from old.approved_at) then
    raise exception 'A aprovação do empréstimo é decidida por quem administra a casa.';
  end if;
  return new;
end;
$$;

create or replace trigger trg_guard_p2p_loan_approval
  before insert or update of awaiting_approval, approved_by, approved_at on public.p2p_loans
  for each row execute function public.guard_p2p_loan_approval();

create or replace function public.decide_p2p_loan_approval(p_loan_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.p2p_loans%rowtype;
  v_user uuid := auth.uid();
begin
  select * into v_loan from public.p2p_loans where id = p_loan_id for update;
  if not found or v_user is null or not public.is_house_member(v_loan.house_id) then
    raise exception 'Empréstimo não encontrado.';
  end if;
  if not public.has_house_permission(v_loan.house_id, 'editar_configuracoes') then
    raise exception 'Você não tem permissão para aprovar empréstimos.';
  end if;
  if not v_loan.awaiting_approval then
    raise exception 'Este empréstimo não está aguardando aprovação.';
  end if;
  -- Quem lançou não aprova o próprio empréstimo, salvo se for o único administrador
  if v_loan.created_by is not distinct from v_user and exists (
    select 1 from public.house_members hm
    where hm.house_id = v_loan.house_id
      and hm.user_id <> v_user
      and hm.role in ('owner', 'admin')
      and hm.left_at is null
  ) then
    raise exception 'Outra pessoa que administra a casa precisa aprovar este empréstimo.';
  end if;

  if p_approve then
    update public.p2p_loans
       set awaiting_approval = false, approved_by = v_user, approved_at = now(), updated_at = now()
     where id = p_loan_id;
  else
    update public.p2p_loans
       set awaiting_approval = false, status = 'cancelled', updated_at = now()
     where id = p_loan_id;
  end if;
end;
$$;

revoke execute on function public.decide_p2p_loan_approval(uuid, boolean) from public, anon;
grant execute on function public.decide_p2p_loan_approval(uuid, boolean) to authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 3. update_house_settings (parte da 0103): approval_threshold_cents
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
      and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam como a sobra entra no rateio.';
  end if;
  if p_settings ? 'opening_inflow_rules'
      and not public.opening_inflow_rules_valid(p_settings->'opening_inflow_rules') then
    raise exception 'Regra das entradas no Caixa inválida.';
  end if;
  if p_settings ? 'closing_defaults' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam os padrões do fechamento.';
  end if;
  if p_settings ? 'closing_defaults'
      and not public.closing_defaults_valid(p_settings->'closing_defaults') then
    raise exception 'Padrões do fechamento inválidos.';
  end if;
  if p_settings ? 'new_member_split_policy' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam a divisão para quem entra na casa.';
  end if;
  if p_settings ? 'new_member_split_policy'
      and coalesce(p_settings->>'new_member_split_policy', '') not in ('equal', 'keep_current', 'ask') then
    raise exception 'Política de divisão para novo morador inválida.';
  end if;

  if p_settings ? 'folego_params' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam os parâmetros do Fôlego.';
  end if;
  if p_settings ? 'folego_params' and not public.folego_params_valid(p_settings->'folego_params') then
    raise exception 'Parâmetros do Fôlego inválidos.';
  end if;

  if p_settings ? 'budget_alert_stages' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam os estágios do alerta de orçamento.';
  end if;
  if p_settings ? 'budget_alert_stages'
      and not public.budget_alert_stages_valid(p_settings->'budget_alert_stages') then
    raise exception 'Estágios do alerta de orçamento inválidos.';
  end if;

  if p_settings ? 'import_matching' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam as janelas de casamento da importação.';
  end if;
  if p_settings ? 'import_matching' and not public.import_matching_valid(p_settings->'import_matching') then
    raise exception 'Janelas de casamento da importação inválidas.';
  end if;

  if p_settings ? 'import_defaults' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam o destino padrão da importação.';
  end if;
  if p_settings ? 'import_defaults' and not public.import_defaults_valid(p_settings->'import_defaults') then
    raise exception 'Destino padrão da importação inválido.';
  end if;

  if p_settings ? 'cash_label' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam o nome do Caixa.';
  end if;
  if p_settings ? 'cash_label' and not public.cash_label_valid(p_settings->'cash_label') then
    raise exception 'Nome do Caixa inválido.';
  end if;

  if p_settings ? 'shopping_units' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam as unidades de compra.';
  end if;
  if p_settings ? 'shopping_units' and not public.shopping_units_valid(p_settings->'shopping_units') then
    raise exception 'Unidades de compra inválidas.';
  end if;

  if p_settings ? 'income_visibility' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam quem vê a renda dos moradores.';
  end if;
  if p_settings ? 'income_visibility'
      and coalesce(p_settings->>'income_visibility', '') not in ('all', 'admins', 'self') then
    raise exception 'Visibilidade da renda inválida.';
  end if;

  if p_settings ? 'split_basis' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam a base da divisão padrão.';
  end if;
  if p_settings ? 'split_basis'
      and coalesce(p_settings->>'split_basis', '') not in ('manual', 'income') then
    raise exception 'Base da divisão padrão inválida.';
  end if;

  if p_settings ? 'permissions' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam quem pode fazer cada ação.';
  end if;
  if p_settings ? 'permissions' and not public.house_permissions_valid(p_settings->'permissions') then
    raise exception 'Permissões inválidas.';
  end if;

  if p_settings ? 'approval_threshold_cents' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam o limite de aprovação por valor.';
  end if;
  if p_settings ? 'approval_threshold_cents'
      and jsonb_typeof(p_settings->'approval_threshold_cents') <> 'null'
      and (
        jsonb_typeof(p_settings->'approval_threshold_cents') <> 'number'
        or (p_settings->>'approval_threshold_cents')::numeric <= 0
        or (p_settings->>'approval_threshold_cents')::numeric > 100000000000
        or (p_settings->>'approval_threshold_cents')::numeric <> trunc((p_settings->>'approval_threshold_cents')::numeric)
      ) then
    raise exception 'Limite de aprovação por valor inválido.';
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
    planner_category_overrides = coalesce(p_settings->'planner_category_overrides', planner_category_overrides),
    permissions = coalesce(p_settings->'permissions', permissions),
    approval_threshold_cents = case when p_settings ? 'approval_threshold_cents'
      then (p_settings->>'approval_threshold_cents')::bigint else approval_threshold_cents end
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
    'planner_category_overrides', v_row.planner_category_overrides,
    'permissions', v_row.permissions,
    'approval_threshold_cents', v_row.approval_threshold_cents
  );
end;
$$;

revoke execute on function public.update_house_settings(uuid, jsonb) from public, anon;
grant execute on function public.update_house_settings(uuid, jsonb) to authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 4. Tarefas recorrentes com rodízio
-- ------------------------------------------------------------------------------
alter table public.tasks
  add column if not exists recurrence text check (recurrence in ('daily', 'weekly', 'monthly')),
  add column if not exists rotation_members uuid[] not null default '{}'
    check (cardinality(rotation_members) <= 20),
  add column if not exists next_assignee uuid references auth.users(id) on delete set null;

comment on column public.tasks.recurrence is
  'Repetição da tarefa (daily, weekly, monthly); nulo = tarefa única. Ao concluir nasce a próxima ocorrência (0104).';
comment on column public.tasks.rotation_members is
  'Moradores que se revezam na tarefa, na ordem do rodízio (0104).';
comment on column public.tasks.next_assignee is
  'Quem pega a próxima ocorrência; nulo = o seguinte do rodízio (0104).';

-- Quem vem depois de p_current no rodízio; fora dele (ou sem ninguém), o primeiro.
create or replace function public.task_rotation_after(p_members uuid[], p_current uuid)
returns uuid
language sql
immutable
set search_path = public
as $$
  select case
    when coalesce(cardinality(p_members), 0) = 0 then null
    else p_members[(coalesce(array_position(p_members, p_current), 0) % cardinality(p_members)) + 1]
  end;
$$;

create or replace function public.spawn_next_recurring_task()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_members uuid[];
  v_assignee uuid;
  v_timezone text;
  v_today date;
  v_due date;
begin
  select coalesce(timezone, 'America/Sao_Paulo') into v_timezone from public.houses where id = new.house_id;
  v_today := (now() at time zone coalesce(v_timezone, 'America/Sao_Paulo'))::date;

  -- Só entra no rodízio quem ainda mora na casa
  select coalesce(array_agg(t.m order by t.ord), '{}') into v_members
  from unnest(new.rotation_members) with ordinality as t(m, ord)
  where exists (
    select 1 from public.house_members hm
    where hm.house_id = new.house_id and hm.user_id = t.m and hm.left_at is null
  );

  if cardinality(v_members) = 0 then
    v_assignee := new.assigned_to;
  elsif new.next_assignee is not null and new.next_assignee = any (v_members) then
    v_assignee := new.next_assignee;
  else
    v_assignee := public.task_rotation_after(v_members, new.assigned_to);
  end if;

  -- Anda uma repetição e, se já passou, continua andando até hoje
  v_due := coalesce(new.due_date, v_today);
  loop
    v_due := case new.recurrence
      when 'daily' then v_due + 1
      when 'weekly' then v_due + 7
      else (v_due + interval '1 month')::date
    end;
    exit when v_due >= v_today;
  end loop;

  insert into public.tasks (
    house_id, title, description, due_date, due_time, assigned_to, priority, visibility,
    routine_id, cost_cents, created_by, recurrence, rotation_members, next_assignee
  ) values (
    new.house_id, new.title, new.description, v_due, new.due_time, v_assignee, new.priority, new.visibility,
    new.routine_id, new.cost_cents, new.created_by, new.recurrence, new.rotation_members,
    public.task_rotation_after(v_members, v_assignee)
  );

  -- A concluída deixa de se repetir: reabrir e concluir de novo não duplica
  update public.tasks set recurrence = null where id = new.id;
  return new;
end;
$$;

revoke execute on function public.spawn_next_recurring_task() from public, anon, authenticated;

create or replace trigger trg_tasks_spawn_next_recurring
  after update of is_completed on public.tasks
  for each row
  when (new.is_completed and not old.is_completed and new.recurrence is not null)
  execute function public.spawn_next_recurring_task();
