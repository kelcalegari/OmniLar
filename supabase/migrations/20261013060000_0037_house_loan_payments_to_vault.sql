-- ==============================================================================
-- 0037: Pagamento de acordo com o Lar vai para uma caixinha
-- Descrição:
--   1. Reposição de caixinha: o acordo criado quando uma caixinha cobre quem
--      pagou a menos no fechamento guarda de qual caixinha saiu
--      (p2p_loans.repay_to_vault_id). Cada pagamento dele volta para ela, em
--      vez de aparecer como sobra do Caixa.
--   2. Acordo com o Lar pago fora do fechamento: quem paga escolhe a caixinha
--      que recebe (RPC pay_house_loan_to_vault). Antes esse dinheiro não entrava
--      na sobra de nenhum ciclo.
--   Parcela de acordo com o Lar cobrada no próprio fechamento (sem ser
--   reposição) continua entrando no Caixa e contando na sobra.
-- ==============================================================================

alter table public.p2p_loans
  add column if not exists repay_to_vault_id uuid references public.savings_vaults(id) on delete set null;

-- Caixinha que recebe os pagamentos do acordo (null se não houver ou se foi excluída)
create or replace function public.p2p_loan_repay_vault(p_loan_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select v.id
  from public.p2p_loans l
  join public.savings_vaults v on v.id = l.repay_to_vault_id
  where l.id = p_loan_id
    and l.lender_is_house
    and v.house_id = l.house_id
    and v.deleted_at is null;
$$;

revoke execute on function public.p2p_loan_repay_vault(uuid) from public, anon, authenticated;

-- Toda baixa de parcela passa por payment_allocations (pagamento avulso,
-- abatimento do empréstimo ou fechamento): o depósito na caixinha acontece aqui,
-- na mesma transação da baixa.
create or replace function public.route_house_loan_payment_to_vault()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.p2p_loans%rowtype;
  v_vault_id uuid;
  v_chosen text;
begin
  select l.* into v_loan
  from public.p2p_installments i
  join public.p2p_loans l on l.id = i.loan_id
  where i.id = new.installment_id;

  if not found or not v_loan.lender_is_house then
    return new;
  end if;

  v_vault_id := public.p2p_loan_repay_vault(v_loan.id);

  -- Sem caixinha de origem: vale a escolhida por quem está pagando
  if v_vault_id is null then
    v_chosen := nullif(current_setting('omnilar.repay_vault_id', true), '');
    if v_chosen is not null then
      select v.id into v_vault_id
      from public.savings_vaults v
      where v.id = v_chosen::uuid and v.house_id = v_loan.house_id and v.deleted_at is null;
      if v_vault_id is null then
        raise exception 'Caixinha não encontrada nesta casa.';
      end if;
    end if;
  end if;

  if v_vault_id is null then
    return new;
  end if;

  update public.savings_vaults
  set current_balance_cents = current_balance_cents + new.allocated_cents
  where id = v_vault_id;

  insert into public.savings_transactions (vault_id, house_id, member_id, amount_cents, type, description)
  values (
    v_vault_id, v_loan.house_id, v_loan.borrower_id, new.allocated_cents, 'deposit',
    'Pagamento de acordo com o Lar: ' || v_loan.title
  );

  return new;
end;
$$;

drop trigger if exists trg_payment_allocations_route_to_vault on public.payment_allocations;
create trigger trg_payment_allocations_route_to_vault
  after insert on public.payment_allocations
  for each row execute function public.route_house_loan_payment_to_vault();

-- Paga uma parcela (p_installment_id) ou abate o empréstimo (p_loan_id) de um
-- acordo com o Lar, guardando o valor na caixinha escolhida. Quem pode pagar é
-- conferido pelas funções de pagamento de sempre.
create or replace function public.pay_house_loan_to_vault(
  p_vault_id uuid,
  p_amount_cents bigint,
  p_installment_id uuid default null,
  p_loan_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.p2p_loans%rowtype;
  v_payment_id uuid;
begin
  if (p_installment_id is null) = (p_loan_id is null) then
    raise exception 'Informe a parcela ou o empréstimo.';
  end if;

  if p_installment_id is not null then
    select l.* into v_loan
    from public.p2p_installments i
    join public.p2p_loans l on l.id = i.loan_id
    where i.id = p_installment_id;
  else
    select * into v_loan from public.p2p_loans where id = p_loan_id;
  end if;

  if not found then
    raise exception 'Empréstimo não encontrado.';
  end if;
  if not v_loan.lender_is_house then
    raise exception 'Só acordos com o Lar podem ser pagos para uma caixinha.';
  end if;
  if not exists (
    select 1 from public.savings_vaults v
    where v.id = p_vault_id and v.house_id = v_loan.house_id and v.deleted_at is null
  ) then
    raise exception 'Caixinha não encontrada nesta casa.';
  end if;

  perform set_config('omnilar.repay_vault_id', p_vault_id::text, true);
  if p_installment_id is not null then
    v_payment_id := public.pay_p2p_installment(p_installment_id, p_amount_cents);
  else
    v_payment_id := public.pay_p2p_loan(p_loan_id, p_amount_cents);
  end if;
  perform set_config('omnilar.repay_vault_id', '', true);

  return v_payment_id;
end;
$$;

revoke execute on function public.pay_house_loan_to_vault(uuid, bigint, uuid, uuid) from public, anon;
grant execute on function public.pay_house_loan_to_vault(uuid, bigint, uuid, uuid) to authenticated;

-- Fechamento do ciclo: igual ao da 0032, com duas diferenças.
--   a) o acordo de reposição nasce ligado à caixinha que cobriu (repay_to_vault_id);
--   b) parcela de reposição paga no fechamento não conta como entrada no Caixa.
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
