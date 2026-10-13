-- ==============================================================================
-- 0029: Conferência do plano de fechamento e proteção de despesa já acertada
-- Descrição:
--   - confirm_cycle_settlement gravava o plano calculado pelo app sem conferir.
--     Agora recusa plano com despesa de outra casa ou já excluída, rateio
--     congelado que não soma o valor da despesa, transferência inválida,
--     acordo cujas parcelas não somam o total e totais de caixinha que não
--     batem com as movimentações. O cálculo do rateio continua sendo do app.
--   - Excluir uma despesa que já entrou em um fechamento não devolvia nada a
--     ninguém. A exclusão passa a ser recusada, pela função de exclusão e por
--     um gatilho para quem grava direto na tabela. A correção é um lançamento
--     de ajuste.
--   - Remove a versão antiga de delete_house_expense, de um parâmetro só.
-- ==============================================================================

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
begin
  if v_uid is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;
  if v_house_id is null or v_cycle is null then
    raise exception 'Plano de fechamento incompleto.';
  end if;
  if not public.is_house_admin(v_house_id) then
    raise exception 'Apenas administradores da casa podem fechar o ciclo.';
  end if;

  -- Um fechamento por vez para o mesmo ciclo
  perform pg_advisory_xact_lock(hashtextextended(v_house_id::text || v_cycle::text, 0));

  if exists (
    select 1 from public.settlements
    where house_id = v_house_id and cycle_start_date = v_cycle and status in ('confirmed', 'completed')
  ) then
    raise exception 'Este ciclo já foi fechado.';
  end if;

  -- O plano é calculado no app de quem fecha: confere antes de gravar qualquer coisa
  if coalesce((p_plan->>'total_expenses_cents')::bigint, 0) < 0
     or coalesce((p_plan->>'total_contributions_cents')::bigint, 0) < 0
     or coalesce((p_plan->>'total_cleared_p2p_cents')::bigint, 0) < 0
     or coalesce((p_plan->>'surplus_vaulted_cents')::bigint, 0) < 0
     or coalesce((p_plan->>'deficit_covered_cents')::bigint, 0) < 0 then
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
      total_amount_cents, installments_count, repayment_mode, status, created_by
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
      v_uid
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
    settled_at, settled_by
  ) values (
    v_house_id, v_cycle, 'confirmed',
    coalesce((p_plan->>'total_expenses_cents')::bigint, 0),
    coalesce((p_plan->>'total_contributions_cents')::bigint, 0),
    coalesce((p_plan->>'total_cleared_p2p_cents')::bigint, 0),
    coalesce((p_plan->>'surplus_vaulted_cents')::bigint, 0),
    coalesce((p_plan->>'deficit_covered_cents')::bigint, 0),
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

-- A versão antiga, de um parâmetro, excluía sem esta conferência e deixava
-- ambígua a chamada sem escopo
drop function if exists public.delete_house_expense(uuid);

create or replace function public.delete_house_expense(
  p_expense_id uuid,
  p_scope text default 'thisInstanceOnly'
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_house_id uuid;
  v_series_id uuid;
  v_is_recurring boolean;
  v_due_date date;
  v_settled_at timestamptz;
begin
  select house_id, recurring_series_id, is_recurring, due_date, settled_at
  into v_house_id, v_series_id, v_is_recurring, v_due_date, v_settled_at
  from public.house_expenses
  where id = p_expense_id;

  if v_house_id is null then
    return false;
  end if;

  -- Valida se o usuário pertence à casa
  if not public.is_house_member(v_house_id) then
    raise exception 'Acesso negado: você não é membro desta casa';
  end if;

  if v_settled_at is not null then
    raise exception 'Esta despesa já entrou em um fechamento de ciclo e não pode ser excluída. Lance um ajuste para corrigir o valor.';
  end if;

  v_series_id := coalesce(v_series_id, case when v_is_recurring then p_expense_id else null end);

  -- Nos escopos de série, as ocorrências já acertadas ficam como histórico
  if p_scope = 'allInstances' then
    update public.house_expenses
    set deleted_at = now(), is_active = false
    where house_id = v_house_id
      and settled_at is null
      and (
        id = p_expense_id
        or (v_series_id is not null and (id = v_series_id or recurring_series_id = v_series_id))
      );

  elsif p_scope = 'thisAndFuture' then
    if v_series_id is not null then
      update public.house_expenses
      set is_active = false
      where id = v_series_id;
    end if;

    update public.house_expenses
    set deleted_at = now()
    where house_id = v_house_id
      and settled_at is null
      and (
        id = p_expense_id
        or (v_series_id is not null and (id = v_series_id or recurring_series_id = v_series_id))
      )
      and (v_due_date is null or due_date >= v_due_date);

  else
    -- Apenas esta ocorrência pontual
    update public.house_expenses
    set deleted_at = now()
    where id = p_expense_id;
  end if;

  return true;
end;
$$;

-- Mesma regra para quem grava direto na tabela
create or replace function public.protect_settled_expense()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- As funções do banco aplicam a regra por conta própria, e exclusões em
  -- cascata (ex: a casa inteira) não passam por aqui
  if current_user not in ('authenticated', 'anon') or pg_trigger_depth() > 1 then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if old.settled_at is not null then
    if tg_op = 'DELETE' then
      raise exception 'Esta despesa já entrou em um fechamento de ciclo e não pode ser excluída. Lance um ajuste para corrigir o valor.';
    elsif new.deleted_at is not null and old.deleted_at is null then
      raise exception 'Esta despesa já entrou em um fechamento de ciclo e não pode ser excluída. Lance um ajuste para corrigir o valor.';
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_house_expenses_protect_settled on public.house_expenses;
create trigger trg_house_expenses_protect_settled
  before update or delete on public.house_expenses
  for each row execute function public.protect_settled_expense();

-- Recarrega o cache de schema do PostgREST
notify pgrst, 'reload schema';
