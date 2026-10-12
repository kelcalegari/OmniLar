-- ==============================================================================
-- 0025: Data da baixa das despesas (paid_at)
-- Descrição:
--   Uma conta pendente é arrastada para os ciclos seguintes até receber baixa.
--   Sem guardar quando a baixa aconteceu, ela voltava a contar no ciclo do
--   lançamento e podia ser cobrada de novo se os ciclos fossem fechados fora de
--   ordem. paid_at registra a baixa e define o ciclo em que a despesa conta.
--   Despesas lançadas já pagas ficam com paid_at nulo e contam pela data do
--   lançamento, como antes.
-- ==============================================================================

alter table public.house_expenses add column if not exists paid_at timestamptz;

-- O fechamento do ciclo registra a baixa das contas pendentes dentro do ciclo
-- fechado ("expenses_paid_at" no plano), e não no momento em que foi executado.
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
    settled_at, settled_by
  ) values (
    v_house_id, v_cycle, 'confirmed',
    coalesce((p_plan->>'total_expenses_cents')::bigint, 0),
    coalesce((p_plan->>'total_contributions_cents')::bigint, 0),
    coalesce((p_plan->>'total_cleared_p2p_cents')::bigint, 0),
    now(), v_uid
  )
  on conflict (house_id, cycle_start_date) do update
    set status = 'confirmed',
        total_expenses_cents = excluded.total_expenses_cents,
        total_contributions_cents = excluded.total_contributions_cents,
        total_cleared_p2p_cents = excluded.total_cleared_p2p_cents,
        settled_at = excluded.settled_at,
        settled_by = excluded.settled_by
  returning id into v_settlement_id;

  delete from public.settlement_transfers where settlement_id = v_settlement_id;

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

-- Recarrega o cache de schema do PostgREST
notify pgrst, 'reload schema';
