-- ==============================================================================
-- 0103: Permissões por ação
-- Descrição:
--   Cada ação que hoje exige administrador passa a ter um nível configurável
--   pela casa: só administradores, todos os moradores ou moradores escolhidos.
--   Sem configuração vale o comportamento de sempre (administradores), então
--   nada muda até um administrador ajustar nos Ajustes.
--
--   1. houses.permissions (jsonb): mapa ação -> { "level": "admins" | "all" |
--      "chosen", "members": [uuid, ...] }. "members" só existe com "chosen".
--      Validado por house_permissions_valid.
--   2. has_house_permission(p_house_id, p_action): administradores SEMPRE
--      passam, em qualquer ação (ninguém tranca a casa). Os demais seguem o
--      nível configurado; ação sem configuração = só administradores.
--   3-11. As RPCs e o gatilho abaixo trocam is_house_admin por
--      has_house_permission, partindo da versão mais recente de cada função.
--
--   Lista estável de ações (nomes não mudam; a mesma lista está em
--   HousePermissionAction, no app):
--     editar_configuracoes   update_house_settings (todos os campos, menos permissions)
--     fechar_ciclo           confirm_cycle_settlement, save_settlement_snapshot
--     reabrir_ciclo          reopen_cycle_settlement
--     mudar_dia_do_ciclo     change_house_cycle_start_day
--     gerenciar_categorias   delete_category_moving_expenses
--     emprestimos_da_casa    create_house_loan (empréstimo do Caixa)
--     saldo_inicial          set_house_initial_balance
--     ajustar_aportes        guard_savings_vault_quota (meta mensal da caixinha na cota)
--
--   Ficam de fora desta migration (seguem só administradores, policies e
--   funções não trocadas): convidar moradores e papéis (house_members,
--   house_invites), p2p_loans/p2p_installments da casa como credora,
--   house_inflows, update_event_series e as demais policies da 0077.
--   A coluna permissions só muda por administradores (update_house_settings).
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Coluna e validação
-- ------------------------------------------------------------------------------
create or replace function public.house_permission_actions()
returns text[]
language sql
immutable
set search_path = public
as $$
  select array[
    'editar_configuracoes', 'fechar_ciclo', 'reabrir_ciclo', 'mudar_dia_do_ciclo',
    'gerenciar_categorias', 'emprestimos_da_casa', 'saldo_inicial', 'ajustar_aportes'
  ];
$$;

create or replace function public.house_permissions_valid(p_permissions jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_permissions is not null
    and jsonb_typeof(p_permissions) = 'object'
    and not exists (
      select 1 from jsonb_each(p_permissions) e
      where not (e.key = any (public.house_permission_actions()))
        or jsonb_typeof(e.value) <> 'object'
        or jsonb_typeof(e.value->'level') is distinct from 'string'
        or (e.value->>'level') not in ('admins', 'all', 'chosen')
        or (
          (e.value->>'level') = 'chosen'
          and (
            jsonb_typeof(e.value->'members') is distinct from 'array'
            or jsonb_array_length(e.value->'members') > 50
            or exists (
              select 1 from jsonb_array_elements(e.value->'members') m
              where jsonb_typeof(m) <> 'string'
                or (m #>> '{}') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            )
          )
        )
        or ((e.value->>'level') <> 'chosen' and e.value ? 'members')
    );
$$;

alter table public.houses
  add column if not exists permissions jsonb not null default '{}'::jsonb
    check (public.house_permissions_valid(permissions));

comment on column public.houses.permissions is
  'Quem pode fazer cada ação: ação -> {level: admins|all|chosen, members: [uuid]}; vazio = só administradores (0103).';

-- ------------------------------------------------------------------------------
-- 2. has_house_permission
-- ------------------------------------------------------------------------------
create or replace function public.has_house_permission(p_house_id uuid, p_action text)
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_perm jsonb;
begin
  if v_uid is null then
    return false;
  end if;
  -- Administrador sempre passa: ninguém tranca a casa
  if public.is_house_admin(p_house_id) then
    return true;
  end if;
  if not public.is_house_member(p_house_id) then
    return false;
  end if;
  select permissions -> p_action into v_perm from public.houses where id = p_house_id;
  case coalesce(v_perm ->> 'level', 'admins')
    when 'all' then
      return true;
    when 'chosen' then
      return coalesce((v_perm -> 'members') ? v_uid::text, false);
    else
      return false;
  end case;
end;
$$;

revoke execute on function public.has_house_permission(uuid, text) from public, anon;
grant execute on function public.has_house_permission(uuid, text) to authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 3. update_house_settings (parte da 0102): editar_configuracoes; permissions só administradores
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
    permissions = coalesce(p_settings->'permissions', permissions)
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
    'permissions', v_row.permissions
  );
end;
$$;

revoke execute on function public.update_house_settings(uuid, jsonb) from public, anon;
grant execute on function public.update_house_settings(uuid, jsonb) to authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 4. confirm_cycle_settlement (parte da 0044): fechar_ciclo
-- ------------------------------------------------------------------------------
create or replace function public.confirm_cycle_settlement(p_plan jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_house_id uuid := (p_plan->>'house_id')::uuid;
  v_cycle date := (p_plan->>'cycle_start_date')::date;
  v_item jsonb;
  v_sub jsonb;
  v_vault public.savings_vaults%rowtype;
  v_amount bigint;
  v_member uuid;
  v_lender uuid;
  v_loan_id uuid;
  v_settlement_id uuid;
  v_house_received bigint := 0;
  v_cycle_end date := (p_plan->>'cycle_end_date')::date;
begin
  if v_uid is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;
  if v_house_id is null or v_cycle is null then
    raise exception 'Plano de fechamento incompleto.';
  end if;
  if not public.has_house_permission(v_house_id, 'fechar_ciclo') then
    raise exception 'Apenas administradores da casa podem fechar o ciclo.';
  end if;
  -- Fim do ciclo informado pelo app: um ciclo tem de 15 a 46 dias
  if v_cycle_end is not null and (v_cycle_end < v_cycle + 14 or v_cycle_end > v_cycle + 46) then
    raise exception 'O plano de fechamento tem um fim de ciclo inválido.';
  end if;

  -- Um fechamento por vez para o mesmo ciclo
  perform pg_advisory_xact_lock(hashtextextended(v_house_id::text || v_cycle::text, 0));

  if exists (
    select 1 from public.settlements
    where house_id = v_house_id and cycle_start_date = v_cycle and status in ('confirmed', 'completed')
  ) then
    raise exception 'Este ciclo já foi fechado.';
  end if;

  -- Quem lança despesa ou aporte nesta casa espera o fechamento terminar, e o
  -- fechamento espera os lançamentos em andamento
  perform pg_advisory_xact_lock(hashtextextended('house-ledger:' || v_house_id::text, 0));

  -- O plano foi calculado sobre os dados que o app leu: se algo mudou desde
  -- então, o admin revisa antes de fechar
  if p_plan->>'data_version' is null then
    raise exception 'Atualize o aplicativo para fechar o ciclo.';
  end if;
  if p_plan->>'data_version' <> public.settlement_data_version(v_house_id) then
    raise exception 'Os dados da casa mudaram desde o cálculo do fechamento. Revise os valores e confirme de novo.';
  end if;

  -- O plano é calculado no app de quem fecha: confere antes de gravar qualquer coisa
  if coalesce((p_plan->>'total_expenses_cents')::bigint, 0) < 0
     or coalesce((p_plan->>'total_contributions_cents')::bigint, 0) < 0
     or coalesce((p_plan->>'total_cleared_p2p_cents')::bigint, 0) < 0
     or coalesce((p_plan->>'surplus_vaulted_cents')::bigint, 0) < 0
     or coalesce((p_plan->>'deficit_covered_cents')::bigint, 0) < 0
     or coalesce((p_plan->>'surplus_rolled_cents')::bigint, 0) < 0
     or coalesce((p_plan->>'surplus_refunded_cents')::bigint, 0) < 0
     or coalesce((p_plan->>'house_receivable_cents')::bigint, 0) < 0
     or coalesce((p_plan->>'house_forgiven_cents')::bigint, 0) < 0 then
    raise exception 'O plano de fechamento tem um total negativo.';
  end if;

  if exists (
    select 1
    from (
      select value::uuid as id
      from jsonb_array_elements_text(coalesce(p_plan->'expense_ids', '[]'::jsonb))
      union all
      select value::uuid
      from jsonb_array_elements_text(coalesce(p_plan->'settled_expense_ids', '[]'::jsonb))
      union all
      select (value->>'expense_id')::uuid
      from jsonb_array_elements(coalesce(p_plan->'split_snapshots', '[]'::jsonb))
    ) x
    where not exists (
      select 1 from public.house_expenses e
      where e.id = x.id and e.house_id = v_house_id and e.deleted_at is null
    )
  ) then
    raise exception 'O plano de fechamento cita uma despesa que não existe nesta casa. Atualize a tela e tente de novo.';
  end if;

  -- O rateio congelado de cada despesa precisa somar o valor dela, entre moradores da casa
  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_plan->'split_snapshots', '[]'::jsonb)) snap
    join public.house_expenses e on e.id = (snap->>'expense_id')::uuid
    where e.amount_cents <> (
        select coalesce(sum((rule->>'calculated_cents')::bigint), 0)
        from jsonb_array_elements(coalesce(snap->'rules', '[]'::jsonb)) rule
      )
      or exists (
        select 1
        from jsonb_array_elements(coalesce(snap->'rules', '[]'::jsonb)) rule
        where coalesce((rule->>'calculated_cents')::bigint, -1) < 0
          or not exists (
            select 1 from public.house_members hm
            where hm.house_id = v_house_id and hm.user_id = (rule->>'member_id')::uuid
          )
      )
  ) then
    raise exception 'O rateio de uma despesa no plano de fechamento não soma o valor dela. Atualize a tela e tente de novo.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_plan->'transfers', '[]'::jsonb)) t
    where coalesce((t->>'amount_cents')::bigint, 0) <= 0
      or t->>'from_member_id' is null
      or t->>'to_member_id' is null
      or t->>'from_member_id' = t->>'to_member_id'
      or not exists (
        select 1 from public.house_members hm
        where hm.house_id = v_house_id and hm.user_id = (t->>'from_member_id')::uuid
      )
      or not exists (
        select 1 from public.house_members hm
        where hm.house_id = v_house_id and hm.user_id = (t->>'to_member_id')::uuid
      )
  ) then
    raise exception 'O plano de fechamento tem uma transferência inválida.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_plan->'new_loans', '[]'::jsonb)) l
    where (l->>'total_amount_cents')::bigint is distinct from (
      select sum((i->>'amount_cents')::bigint)
      from jsonb_array_elements(coalesce(l->'installments', '[]'::jsonb)) i
    )
  ) then
    raise exception 'O plano de fechamento tem um acordo cujas parcelas não somam o total.';
  end if;

  -- O que ficou a receber pelo Caixa precisa estar coberto por acordos com o Lar
  if coalesce((p_plan->>'house_receivable_cents')::bigint, 0) > (
       select coalesce(sum((l->>'total_amount_cents')::bigint), 0)
       from jsonb_array_elements(coalesce(p_plan->'new_loans', '[]'::jsonb)) l
       where l->>'lender_id' is null
     ) then
    raise exception 'O plano de fechamento diz ter a receber mais do que os acordos com o Lar somam.';
  end if;

  -- Aportes e devoluções do fechamento: valores positivos, para moradores da casa
  if exists (
    select 1
    from (
      select value from jsonb_array_elements(coalesce(p_plan->'contributions', '[]'::jsonb))
      union all
      select value from jsonb_array_elements(coalesce(p_plan->'contribution_refunds', '[]'::jsonb))
    ) c
    where coalesce((c.value->>'amount_cents')::bigint, 0) <= 0
      or not exists (
        select 1 from public.house_members hm
        where hm.house_id = v_house_id and hm.user_id = (c.value->>'member_id')::uuid
      )
  ) then
    raise exception 'O plano de fechamento tem um aporte ou uma devolução inválida.';
  end if;

  -- O que o fechamento diz ter movido nas caixinhas precisa bater com as movimentações
  if coalesce((p_plan->>'surplus_vaulted_cents')::bigint, 0) <> (
       select coalesce(sum((op->>'amount_cents')::bigint), 0)
       from jsonb_array_elements(coalesce(p_plan->'vault_operations', '[]'::jsonb)) op
       where op->>'type' = 'deposit'
     )
     or coalesce((p_plan->>'deficit_covered_cents')::bigint, 0) > (
       select coalesce(sum((op->>'amount_cents')::bigint), 0)
       from jsonb_array_elements(coalesce(p_plan->'vault_operations', '[]'::jsonb)) op
       where op->>'type' = 'withdraw'
     ) then
    raise exception 'O plano de fechamento não bate com as movimentações de caixinha.';
  end if;

  -- 1. Caixinhas (sobra do Caixa guardada / cobertura de quem pagou a menos)
  for v_item in select * from jsonb_array_elements(coalesce(p_plan->'vault_operations', '[]'::jsonb))
  loop
    v_amount := (v_item->>'amount_cents')::bigint;
    v_member := coalesce((v_item->>'member_id')::uuid, v_uid);

    select * into v_vault
    from public.savings_vaults
    where id = (v_item->>'vault_id')::uuid and house_id = v_house_id and deleted_at is null
    for update;
    if not found then
      raise exception 'Caixinha não encontrada nesta casa.';
    end if;
    if not exists (
      select 1 from public.house_members
      where house_id = v_house_id and user_id = v_member and left_at is null
    ) then
      raise exception 'Movimentação de caixinha para quem não mora na casa.';
    end if;

    if v_item->>'type' = 'deposit' then
      update public.savings_vaults
      set current_balance_cents = current_balance_cents + v_amount
      where id = v_vault.id;
    elsif v_item->>'type' = 'withdraw' then
      if v_vault.current_balance_cents < v_amount then
        raise exception 'Saldo insuficiente na caixinha "%".', v_vault.name;
      end if;
      update public.savings_vaults
      set current_balance_cents = current_balance_cents - v_amount
      where id = v_vault.id;
    else
      raise exception 'Tipo de movimentação de caixinha inválido.';
    end if;

    insert into public.savings_transactions (vault_id, house_id, member_id, amount_cents, type, description)
    values (v_vault.id, v_house_id, v_member, v_amount, v_item->>'type', v_item->>'description');
  end loop;

  -- 2. Aportes compensatórios no Caixa da Casa
  for v_item in select * from jsonb_array_elements(coalesce(p_plan->'contributions', '[]'::jsonb))
  loop
    v_member := (v_item->>'member_id')::uuid;
    if not exists (
      select 1 from public.house_members
      where house_id = v_house_id and user_id = v_member and left_at is null
    ) then
      raise exception 'Aporte para quem não mora na casa.';
    end if;

    insert into public.contributions (house_id, member_id, amount_cents, cycle_start_date, notes, created_by)
    values (v_house_id, v_member, (v_item->>'amount_cents')::bigint, v_cycle, 'Aporte do fechamento do ciclo', v_uid);
  end loop;

  -- Quem já tinha aportado mais do que deve recebe a diferença de volta do Caixa:
  -- fica registrada como aporte negativo no ciclo
  for v_item in select * from jsonb_array_elements(coalesce(p_plan->'contribution_refunds', '[]'::jsonb))
  loop
    insert into public.contributions (house_id, member_id, amount_cents, cycle_start_date, notes, created_by)
    values (v_house_id, (v_item->>'member_id')::uuid, -((v_item->>'amount_cents')::bigint), v_cycle,
            'Devolução de aporte no fechamento do ciclo', v_uid);
  end loop;

  -- 3. Baixa das contas pendentes do ciclo
  update public.house_expenses
  set status = 'paid',
      paid_at = coalesce((p_plan->>'expenses_paid_at')::timestamptz, now())
  where house_id = v_house_id
    and status = 'pending'
    and deleted_at is null
    and id in (
      select value::uuid
      from jsonb_array_elements_text(coalesce(p_plan->'expense_ids', '[]'::jsonb))
    );

  -- Despesas que entram neste acerto: se o ciclo for reaberto, quem pagou do
  -- bolso não é reembolsado de novo por elas
  update public.house_expenses
  set settled_at = now()
  where house_id = v_house_id
    and deleted_at is null
    and settled_at is null
    and id in (
      select value::uuid
      from jsonb_array_elements_text(coalesce(p_plan->'settled_expense_ids', '[]'::jsonb))
    );

  -- Congela o rateio: despesas que usaram o padrão da casa passam a carregar os
  -- percentuais deste fechamento. Mudar o padrão ou entrar um morador novo depois
  -- não altera o que já foi acertado.
  for v_item in select * from jsonb_array_elements(coalesce(p_plan->'split_snapshots', '[]'::jsonb))
  loop
    if exists (
      select 1 from public.house_expenses e
      where e.id = (v_item->>'expense_id')::uuid and e.house_id = v_house_id
    ) and not exists (
      select 1 from public.split_rules s
      where s.expense_id = (v_item->>'expense_id')::uuid
    ) then
      insert into public.split_rules (expense_id, member_id, percentage_basis_points, calculated_cents)
      select
        (v_item->>'expense_id')::uuid,
        (rule->>'member_id')::uuid,
        (rule->>'percentage_basis_points')::integer,
        (rule->>'calculated_cents')::bigint
      from jsonb_array_elements(coalesce(v_item->'rules', '[]'::jsonb)) as rule;
    end if;
  end loop;

  -- 4. Parcelas P2P cobradas neste fechamento (antes de criar os acordos novos,
  --    que só começam a vencer nos próximos ciclos)
  for v_item in select * from jsonb_array_elements(coalesce(p_plan->'installment_payments', '[]'::jsonb))
  loop
    if not exists (
      select 1
      from public.p2p_installments i
      join public.p2p_loans l on l.id = i.loan_id
      where i.id = (v_item->>'installment_id')::uuid and l.house_id = v_house_id
    ) then
      raise exception 'Parcela não pertence a esta casa.';
    end if;

    perform public.apply_p2p_installment_payment(
      (v_item->>'installment_id')::uuid,
      (v_item->>'amount_cents')::bigint,
      null,
      'Fechamento do ciclo'
    );

    -- Parcela de acordo com o Lar: o dinheiro entra no Caixa neste ciclo
    if exists (
      select 1
      from public.p2p_installments i
      join public.p2p_loans l on l.id = i.loan_id
      where i.id = (v_item->>'installment_id')::uuid and l.lender_is_house
        -- Reposição de caixinha volta para a caixinha, não para o Caixa
        and public.p2p_loan_repay_vault(l.id) is null
    ) then
      v_house_received := v_house_received + (v_item->>'amount_cents')::bigint;
    end if;
  end loop;

  -- 5. Acordos P2P do saldo que ficou em aberto
  for v_item in select * from jsonb_array_elements(coalesce(p_plan->'new_loans', '[]'::jsonb))
  loop
    v_lender := (v_item->>'lender_id')::uuid;
    v_member := (v_item->>'borrower_id')::uuid;

    if not exists (
      select 1 from public.house_members
      where house_id = v_house_id and user_id = v_member and left_at is null
    ) or (
      v_lender is not null and not exists (
        select 1 from public.house_members
        where house_id = v_house_id and user_id = v_lender and left_at is null
      )
    ) then
      raise exception 'Acordo envolvendo quem não mora na casa.';
    end if;

    insert into public.p2p_loans (
      house_id, lender_id, lender_is_house, borrower_id, title, description,
      total_amount_cents, installments_count, repayment_mode, status, created_by,
      repay_to_vault_id
    ) values (
      v_house_id,
      v_lender,
      v_lender is null,
      v_member,
      v_item->>'title',
      v_item->>'description',
      (v_item->>'total_amount_cents')::bigint,
      greatest(jsonb_array_length(coalesce(v_item->'installments', '[]'::jsonb)), 1),
      coalesce(v_item->>'repayment_mode', 'installments'),
      'active',
      v_uid,
      -- Só acordo com o Lar pode devolver a uma caixinha, e só a uma desta casa
      case when v_lender is null then (
        select v.id from public.savings_vaults v
        where v.id = (v_item->>'repay_to_vault_id')::uuid
          and v.house_id = v_house_id
          and v.deleted_at is null
      ) end
    ) returning id into v_loan_id;

    for v_sub in select * from jsonb_array_elements(coalesce(v_item->'installments', '[]'::jsonb))
    loop
      insert into public.p2p_installments (loan_id, installment_number, amount_cents, paid_cents, due_date, status)
      values (
        v_loan_id,
        (v_sub->>'number')::integer,
        (v_sub->>'amount_cents')::bigint,
        0,
        (v_sub->>'due_date')::date,
        'pending'
      );
    end loop;
  end loop;

  -- 6. Registro do fechamento e do Super Pix
  insert into public.settlements (
    house_id, cycle_start_date, status,
    total_expenses_cents, total_contributions_cents, total_cleared_p2p_cents,
    surplus_vaulted_cents, deficit_covered_cents,
    surplus_rolled_cents, surplus_refunded_cents,
    house_receivable_cents, house_forgiven_cents, house_loans_received_cents,
    cycle_end_date,
    settled_at, settled_by
  ) values (
    v_house_id, v_cycle, 'confirmed',
    coalesce((p_plan->>'total_expenses_cents')::bigint, 0),
    coalesce((p_plan->>'total_contributions_cents')::bigint, 0),
    coalesce((p_plan->>'total_cleared_p2p_cents')::bigint, 0),
    coalesce((p_plan->>'surplus_vaulted_cents')::bigint, 0),
    coalesce((p_plan->>'deficit_covered_cents')::bigint, 0),
    coalesce((p_plan->>'surplus_rolled_cents')::bigint, 0),
    coalesce((p_plan->>'surplus_refunded_cents')::bigint, 0),
    coalesce((p_plan->>'house_receivable_cents')::bigint, 0),
    coalesce((p_plan->>'house_forgiven_cents')::bigint, 0),
    v_house_received,
    v_cycle_end,
    now(), v_uid
  )
  on conflict (house_id, cycle_start_date) do update
    set status = 'confirmed',
        total_expenses_cents = excluded.total_expenses_cents,
        total_contributions_cents = excluded.total_contributions_cents,
        total_cleared_p2p_cents = excluded.total_cleared_p2p_cents,
        -- Ciclo reaberto: soma ao que o fechamento anterior já movimentou nas caixinhas
        surplus_vaulted_cents = public.settlements.surplus_vaulted_cents + excluded.surplus_vaulted_cents,
        deficit_covered_cents = public.settlements.deficit_covered_cents + excluded.deficit_covered_cents,
        surplus_rolled_cents = public.settlements.surplus_rolled_cents + excluded.surplus_rolled_cents,
        surplus_refunded_cents = public.settlements.surplus_refunded_cents + excluded.surplus_refunded_cents,
        house_receivable_cents = public.settlements.house_receivable_cents + excluded.house_receivable_cents,
        house_forgiven_cents = public.settlements.house_forgiven_cents + excluded.house_forgiven_cents,
        house_loans_received_cents = public.settlements.house_loans_received_cents + excluded.house_loans_received_cents,
        cycle_end_date = coalesce(excluded.cycle_end_date, public.settlements.cycle_end_date),
        settled_at = excluded.settled_at,
        settled_by = excluded.settled_by
  returning id into v_settlement_id;

  -- As transferências de um fechamento anterior (ciclo reaberto) ficam no histórico;
  -- as novas são somadas a elas.
  for v_item in select * from jsonb_array_elements(coalesce(p_plan->'transfers', '[]'::jsonb))
  loop
    insert into public.settlement_transfers (settlement_id, from_member_id, to_member_id, amount_cents, status, paid_at)
    values (
      v_settlement_id,
      (v_item->>'from_member_id')::uuid,
      (v_item->>'to_member_id')::uuid,
      (v_item->>'amount_cents')::bigint,
      'confirmed',
      now()
    );
  end loop;

  return v_settlement_id;
end;
$$;


-- ------------------------------------------------------------------------------
-- 5. save_settlement_snapshot (0035): fechar_ciclo
-- ------------------------------------------------------------------------------
create or replace function public.save_settlement_snapshot(
  p_house_id uuid,
  p_cycle_start_date date,
  p_snapshot jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_house_permission(p_house_id, 'fechar_ciclo') then
    raise exception 'Só administradores da casa podem gravar o fechamento.';
  end if;

  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' then
    raise exception 'Retrato do fechamento inválido.';
  end if;

  if pg_column_size(p_snapshot) > 2000000 then
    raise exception 'Retrato do fechamento grande demais.';
  end if;

  update public.settlements
  set summary_snapshot = p_snapshot
  where house_id = p_house_id
    and cycle_start_date = p_cycle_start_date
    and status in ('confirmed', 'completed');

  if not found then
    raise exception 'Não há fechamento confirmado para este ciclo.';
  end if;
end;
$$;

revoke execute on function public.save_settlement_snapshot(uuid, date, jsonb) from public, anon;
grant execute on function public.save_settlement_snapshot(uuid, date, jsonb) to authenticated;

-- ------------------------------------------------------------------------------
-- 6. reopen_cycle_settlement (0026): reabrir_ciclo
-- ------------------------------------------------------------------------------
create or replace function public.reopen_cycle_settlement(p_house_id uuid, p_cycle_start_date date)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated integer;
begin
  if not public.has_house_permission(p_house_id, 'reabrir_ciclo') then
    raise exception 'Apenas administradores da casa podem reabrir o ciclo.';
  end if;

  update public.settlements
  set status = 'draft', reopened_at = now()
  where house_id = p_house_id
    and cycle_start_date = p_cycle_start_date
    and status in ('confirmed', 'completed');
  get diagnostics v_updated = row_count;

  return v_updated > 0;
end;
$$;


-- ------------------------------------------------------------------------------
-- 7. change_house_cycle_start_day (0044): mudar_dia_do_ciclo
-- ------------------------------------------------------------------------------
create or replace function public.change_house_cycle_start_day(
  p_house_id uuid,
  p_new_day integer,
  p_from date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_house public.houses%rowtype;
  v_schedule jsonb;
  v_last jsonb;
  v_previous_day integer;
begin
  if not public.has_house_permission(p_house_id, 'mudar_dia_do_ciclo') then
    raise exception 'Só o dono ou um administrador da casa pode alterar o dia de início do ciclo.';
  end if;
  if p_new_day is null or p_new_day < 1 or p_new_day > 31 then
    raise exception 'O dia de início do ciclo deve ficar entre 1 e 31.';
  end if;
  if p_from is null or p_from <= current_date or p_from > current_date + 46 then
    raise exception 'A troca do dia de início deve valer a partir do próximo ciclo.';
  end if;

  select * into v_house from public.houses where id = p_house_id for update;
  if not found then
    raise exception 'Casa não encontrada.';
  end if;

  v_schedule := coalesce(v_house.cycle_day_schedule, '[]'::jsonb);
  v_previous_day := v_house.cycle_start_day;

  -- Uma troca que ainda não começou a valer é substituída (mantém o dia anterior dela)
  if jsonb_array_length(v_schedule) > 0 then
    v_last := v_schedule -> (jsonb_array_length(v_schedule) - 1);
    if (v_last->>'from')::date > current_date then
      v_previous_day := (v_last->>'previous_day')::integer;
      v_schedule := v_schedule - (jsonb_array_length(v_schedule) - 1);
    end if;
  end if;

  if v_previous_day <> p_new_day then
    v_schedule := v_schedule || jsonb_build_array(jsonb_build_object(
      'from', p_from, 'day', p_new_day, 'previous_day', v_previous_day
    ));
  end if;

  update public.houses
  set cycle_start_day = p_new_day,
      cycle_day_schedule = v_schedule
  where id = p_house_id;

  return v_schedule;
end;
$$;

revoke execute on function public.change_house_cycle_start_day(uuid, integer, date) from public, anon;
grant execute on function public.change_house_cycle_start_day(uuid, integer, date) to authenticated;

-- ------------------------------------------------------------------------------
-- 8. delete_category_moving_expenses (0072): gerenciar_categorias
-- ------------------------------------------------------------------------------
create or replace function public.delete_category_moving_expenses(
  p_category_id uuid,
  p_target_category_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_house_id uuid;
  v_moved integer;
  v_items integer;
  v_deleted integer;
begin
  if p_target_category_id is null or p_target_category_id = p_category_id then
    raise exception 'Escolha outra categoria para receber os lançamentos.';
  end if;

  select house_id into v_house_id from public.categories where id = p_category_id;
  if v_house_id is null then
    raise exception 'Categoria não encontrada.';
  end if;

  if not exists (
    select 1 from public.categories
    where id = p_target_category_id and house_id = v_house_id
  ) then
    raise exception 'A categoria que recebe os lançamentos precisa ser da mesma casa.';
  end if;

  if not public.has_house_permission(v_house_id, 'gerenciar_categorias') then
    raise exception 'Só o dono da casa ou um administrador pode excluir categorias.';
  end if;

  update public.house_expenses
     set category_id = p_target_category_id
   where house_id = v_house_id and category_id = p_category_id;
  get diagnostics v_moved = row_count;

  update public.house_expense_items i
     set category_id = p_target_category_id
    from public.house_expenses e
   where e.id = i.expense_id and e.house_id = v_house_id and i.category_id = p_category_id;
  get diagnostics v_items = row_count;

  update public.shopping_items
     set category_id = p_target_category_id
   where house_id = v_house_id and category_id = p_category_id;

  update public.import_lines
     set category_id = p_target_category_id
   where house_id = v_house_id and category_id = p_category_id;

  update public.import_rules
     set category_id = p_target_category_id
   where house_id = v_house_id and category_id = p_category_id;

  delete from public.categories where id = p_category_id and house_id = v_house_id;
  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then
    raise exception 'Não foi possível excluir a categoria.';
  end if;

  return v_moved + v_items;
end;
$$;

revoke execute on function public.delete_category_moving_expenses(uuid, uuid) from public, anon;
grant execute on function public.delete_category_moving_expenses(uuid, uuid) to authenticated;

-- ------------------------------------------------------------------------------
-- 9. create_house_loan (0086): emprestimos_da_casa
-- ------------------------------------------------------------------------------
create or replace function public.create_house_loan(p_loan jsonb, p_funding text, p_vault_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_house uuid := (p_loan->>'house_id')::uuid;
  v_borrower uuid := (p_loan->>'borrower_id')::uuid;
  v_amount bigint := (p_loan->>'total_amount_cents')::bigint;
  v_today date;
  v_vault public.savings_vaults%rowtype;
  v_tx uuid;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;
  if not public.has_house_permission(v_house, 'emprestimos_da_casa') then
    raise exception 'Só um administrador empresta dinheiro da Casa.';
  end if;
  if p_funding is null or p_funding not in ('cycle', 'vault') then
    raise exception 'Escolha de onde sai o dinheiro: do ciclo ou de uma caixinha.';
  end if;
  if v_amount is null or v_amount <= 0 then
    raise exception 'O valor deve ser maior que zero.';
  end if;
  if not exists (
    select 1 from public.house_members m
    where m.house_id = v_house and m.user_id = v_borrower and m.left_at is null
  ) then
    raise exception 'Quem pega o empréstimo precisa ser morador da casa.';
  end if;

  -- O fechamento não corre ao mesmo tempo
  perform pg_advisory_xact_lock_shared(hashtextextended('house-ledger:' || v_house::text, 0));

  select (now() at time zone coalesce(h.timezone, 'America/Sao_Paulo'))::date
  into v_today
  from public.houses h
  where h.id = v_house;

  if p_funding = 'cycle' and public.is_date_in_closed_cycle(v_house, v_today) then
    raise exception 'Este ciclo já foi fechado. Reabra o ciclo no Fechamento para tirar dinheiro do Caixa dele.';
  end if;

  if p_funding = 'vault' then
    select * into v_vault
    from public.savings_vaults
    where id = p_vault_id and house_id = v_house and deleted_at is null
    for update;
    if not found then
      raise exception 'Caixinha não encontrada nesta casa.';
    end if;
    if v_vault.current_balance_cents < v_amount then
      raise exception 'Saldo insuficiente na caixinha "%".', v_vault.name;
    end if;
  end if;

  -- Criado aqui (dono das tabelas), nasceria aceito: o aceite é decidido abaixo
  v_id := public.create_p2p_loan(
    (p_loan - 'house_funding' - 'funded_on' - 'lender_id') || jsonb_build_object('lender_is_house', true)
  );

  update public.p2p_loans
  set created_by = v_uid,
      house_funding = p_funding,
      funded_on = v_today,
      repay_to_vault_id = case when p_funding = 'vault' then v_vault.id end,
      awaiting_acceptance = v_uid is distinct from v_borrower,
      accepted_at = case when v_uid is distinct from v_borrower then null else now() end
  where id = v_id;

  if p_funding = 'vault' then
    update public.savings_vaults
    set current_balance_cents = current_balance_cents - v_amount
    where id = v_vault.id;

    insert into public.savings_transactions (vault_id, house_id, member_id, amount_cents, type, description)
    values (
      v_vault.id, v_house, v_uid, v_amount, 'withdraw',
      'Empréstimo para ' || public.notification_first_name(v_borrower) || ': ' || (p_loan->>'title')
    )
    returning id into v_tx;

    perform public.notify_vault_movement(
      v_house, v_vault.id, v_tx,
      public.notification_first_name(v_uid) || ' emprestou ' || public.notification_brl(v_amount)
        || ' de ' || v_vault.name || ' para ' || public.notification_first_name(v_borrower)
    );
  end if;

  return v_id;
end;
$$;

revoke execute on function public.create_house_loan(jsonb, text, uuid) from public, anon;
grant execute on function public.create_house_loan(jsonb, text, uuid) to authenticated;

-- ------------------------------------------------------------------------------
-- 10. set_house_initial_balance (0093): saldo_inicial
-- ------------------------------------------------------------------------------
create or replace function public.set_house_initial_balance(
  p_house_id uuid,
  p_reserve_cents bigint,
  p_cash_cents bigint,
  p_cycle_start date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_house public.houses%rowtype;
  v_reserve bigint := coalesce(p_reserve_cents, 0);
  v_cash bigint := coalesce(p_cash_cents, 0);
  v_cycle_start date;
  v_tx public.savings_transactions%rowtype;
  v_vault public.savings_vaults%rowtype;
  v_old bigint := 0;
  v_tx_id uuid;
begin
  if v_uid is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;
  if not public.has_house_permission(p_house_id, 'saldo_inicial') then
    raise exception 'Só administradores mudam o saldo inicial da casa.';
  end if;
  if v_reserve < 0 or v_cash < 0 then
    raise exception 'O saldo inicial não pode ser negativo.';
  end if;
  if v_cash > 0 and p_cycle_start is null then
    raise exception 'Informe o ciclo em que o saldo da conta entra.';
  end if;
  -- Sem saldo na conta, o ciclo não importa
  v_cycle_start := case when v_cash > 0 then p_cycle_start end;

  -- Uma gravação por vez na casa
  select * into v_house
  from public.houses
  where id = p_house_id
  for update;
  if not found then
    raise exception 'Casa não encontrada.';
  end if;

  -- 1. Saldo na conta: o fechamento do primeiro ciclo já usou o valor antigo
  if v_cash <> v_house.initial_cash_cents
      or v_cycle_start is distinct from v_house.initial_cash_cycle_start then
    if (v_house.initial_cash_cycle_start is not null
          and public.is_date_in_closed_cycle(p_house_id, v_house.initial_cash_cycle_start))
        or (v_cycle_start is not null and public.is_date_in_closed_cycle(p_house_id, v_cycle_start)) then
      raise exception 'O primeiro ciclo já foi fechado. Reabra o ciclo no Fechamento para mudar o saldo da conta.';
    end if;
  end if;

  -- 2. Reserva guardada: corrige o lançamento anterior em vez de somar outro
  v_tx_id := v_house.initial_reserve_transaction_id;
  if v_tx_id is not null then
    select * into v_tx from public.savings_transactions where id = v_tx_id;
    if found then
      select * into v_vault
      from public.savings_vaults
      where id = v_tx.vault_id and deleted_at is null
      for update;
      if found then
        v_old := v_tx.amount_cents;
      else
        -- A caixinha foi excluída (com saldo zerado): o lançamento fica no histórico dela
        v_tx_id := null;
      end if;
    else
      v_tx_id := null;
    end if;
  end if;

  if v_reserve <> v_old then
    if v_tx_id is null then
      select * into v_vault
      from public.savings_vaults
      where house_id = p_house_id and deleted_at is null
      order by (name = 'Reserva da Casa') desc, created_at
      limit 1
      for update;
      if not found then
        insert into public.savings_vaults (house_id, name, icon, color_hex)
        values (p_house_id, 'Reserva da Casa', 'savings', '#10B981')
        returning * into v_vault;
      end if;
    end if;

    if v_vault.current_balance_cents + v_reserve - v_old < 0 then
      raise exception 'A caixinha "%" já usou parte do saldo inicial e ficaria negativa.', v_vault.name;
    end if;

    update public.savings_vaults
    set current_balance_cents = current_balance_cents + v_reserve - v_old
    where id = v_vault.id;

    perform set_config('omnilar.initial_balance', 'on', true);
    if v_tx_id is not null and v_reserve > 0 then
      update public.savings_transactions set amount_cents = v_reserve where id = v_tx_id;
    elsif v_tx_id is not null then
      delete from public.savings_transactions where id = v_tx_id;
      v_tx_id := null;
    else
      insert into public.savings_transactions (vault_id, house_id, member_id, amount_cents, type, description)
      values (v_vault.id, p_house_id, v_uid, v_reserve, 'deposit', 'Saldo inicial da casa')
      returning id into v_tx_id;
    end if;
    perform set_config('omnilar.initial_balance', 'off', true);
  end if;

  update public.houses set
    initial_reserve_cents = v_reserve,
    initial_reserve_transaction_id = v_tx_id,
    initial_cash_cents = v_cash,
    initial_cash_cycle_start = v_cycle_start
  where id = p_house_id
  returning * into v_house;

  return jsonb_build_object(
    'initial_reserve_cents', v_house.initial_reserve_cents,
    'initial_cash_cents', v_house.initial_cash_cents,
    'initial_cash_cycle_start', v_house.initial_cash_cycle_start
  );
end;
$$;

revoke execute on function public.set_house_initial_balance(uuid, bigint, bigint, date) from public, anon;
grant execute on function public.set_house_initial_balance(uuid, bigint, bigint, date) to authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 11. guard_savings_vault_quota (0102): ajustar_aportes
-- ------------------------------------------------------------------------------
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
    if not public.has_house_permission(new.house_id, 'ajustar_aportes') then
      raise exception 'Só administradores mudam a meta mensal da caixinha na cota.';
    end if;
  end if;
  return new;
end;
$$;


notify pgrst, 'reload schema';
