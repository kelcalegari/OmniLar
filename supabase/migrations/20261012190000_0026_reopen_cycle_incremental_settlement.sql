-- ==============================================================================
-- 0026: Reabrir um ciclo, lançar e fechar de novo
-- Descrição:
--   Reabrir deixava de registrar o que já tinha sido acertado: o fechamento
--   seguinte reembolsava de novo quem pagou do bolso e repetia depósitos e
--   saques em caixinha. Agora:
--   - reabrir mantém o fechamento como rascunho, com o histórico do Super Pix;
--   - cada despesa guarda quando entrou em um acerto (settled_at);
--   - o fechamento guarda quanto já moveu nas caixinhas;
--   - o rateio usado em cada despesa fica gravado nela (não muda se o padrão da
--     casa mudar ou se entrar um morador novo);
--   - fechar de novo cobra só a diferença dos novos lançamentos.
-- ==============================================================================

alter table public.house_expenses add column if not exists settled_at timestamptz;

alter table public.settlements
  add column if not exists surplus_vaulted_cents bigint not null default 0,
  add column if not exists deficit_covered_cents bigint not null default 0,
  add column if not exists reopened_at timestamptz;

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

-- Reabrir mantém o registro (como rascunho) e as transferências já feitas
create or replace function public.reopen_cycle_settlement(p_house_id uuid, p_cycle_start_date date)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated integer;
begin
  if not public.is_house_admin(p_house_id) then
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

-- Recarrega o cache de schema do PostgREST
notify pgrst, 'reload schema';
