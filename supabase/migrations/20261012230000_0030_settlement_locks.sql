-- ==============================================================================
-- 0030: Travas do fechamento
-- Descrição:
--   O fechamento é calculado no app e gravado pelo banco. Duas travas fecham
--   as janelas em que os dados podiam mudar sem o fechamento perceber:
--   1. "Nada mudou desde o cálculo": o app pede ao banco a versão dos dados da
--      casa antes de ler, e envia essa versão com o plano. O fechamento recusa
--      se a versão atual for outra.
--   2. Ciclo fechado não aceita lançamento: despesa paga ou aporte cuja data
--      cai em um ciclo fechado é recusado, assim como alterar valor, datas,
--      situação, pagador ou forma de pagamento de uma despesa desse ciclo.
--      Conta pendente fica de fora: ela pesa no ciclo aberto até receber baixa.
--   Um bloqueio por casa faz lançamentos e fechamento esperarem um pelo outro.
-- ==============================================================================

-- Resumo de tudo o que entra no cálculo do fechamento de uma casa
create or replace function public.settlement_data_version(p_house_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version text;
begin
  if not public.is_house_member(p_house_id) then
    raise exception 'Acesso negado: você não é membro desta casa';
  end if;

  select md5(concat_ws('|',
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select e.id, e.updated_at, e.deleted_at
             from public.house_expenses e where e.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select s.id, s.expense_id, s.member_id, s.percentage_basis_points, s.fixed_amount_cents, s.calculated_cents
             from public.split_rules s
             join public.house_expenses e on e.id = s.expense_id
             where e.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select i.id, i.expense_id, i.amount_cents, i.responsible_member_id, i.split_type
             from public.house_expense_items i
             join public.house_expenses e on e.id = i.expense_id
             where e.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select c.id, c.member_id, c.amount_cents, c.cycle_start_date, c.date
             from public.contributions c where c.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.user_id), ''))
       from (select hm.user_id, hm.role, hm.left_at, hm.default_split_percent, hm.default_fixed_amount_cents
             from public.house_members hm where hm.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select l.id, l.updated_at
             from public.p2p_loans l where l.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select i.id, i.updated_at
             from public.p2p_installments i
             join public.p2p_loans l on l.id = i.loan_id
             where l.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select v.id, v.current_balance_cents, v.deleted_at
             from public.savings_vaults v where v.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select pm.id, pm.type
             from public.payment_methods pm where pm.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select st.id, st.cycle_start_date, st.status, st.surplus_vaulted_cents, st.deficit_covered_cents
             from public.settlements st where st.house_id = p_house_id) x)
  )) into v_version;

  return v_version;
end;
$$;

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

-- A data cai em um ciclo fechado da casa? (para quem mora nela)
create or replace function public.house_date_is_closed(p_house_id uuid, p_date date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_house_member(p_house_id) and public.is_date_in_closed_cycle(p_house_id, p_date);
$$;

-- A despesa conta em um ciclo já fechado? Mesma regra de competência do app:
-- compra no cartão pelo pagamento da fatura (ou vencimento), despesa paga pela
-- baixa (ou data do lançamento). Conta pendente e despesa de projeto não contam.
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
begin
  if e.project_id is not null or e.deleted_at is not null or e.status <> 'paid' then
    return false;
  end if;
  if not public.is_house_member(e.house_id) then
    return false;
  end if;

  select timezone into v_timezone from public.houses where id = e.house_id;

  if exists (
    select 1 from public.payment_methods pm
    where pm.id = e.payment_method_id and pm.type = 'card'
  ) then
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

create or replace function public.guard_closed_cycle_expense()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- As funções do banco aplicam as próprias regras
  if current_user not in ('authenticated', 'anon') or pg_trigger_depth() > 1 then
    return new;
  end if;

  -- Espera um fechamento em andamento nesta casa
  perform pg_advisory_xact_lock_shared(hashtextextended('house-ledger:' || new.house_id::text, 0));

  if tg_op = 'UPDATE' then
    -- Título, categoria e observações podem mudar a qualquer momento
    if not (
      new.amount_cents is distinct from old.amount_cents
      or new.date is distinct from old.date
      or new.due_date is distinct from old.due_date
      or new.paid_at is distinct from old.paid_at
      or new.status is distinct from old.status
      or new.paid_by_id is distinct from old.paid_by_id
      or new.paid_out_of_pocket is distinct from old.paid_out_of_pocket
      or new.payment_method_id is distinct from old.payment_method_id
      or new.split_type is distinct from old.split_type
      or new.project_id is distinct from old.project_id
      or new.deleted_at is distinct from old.deleted_at
    ) then
      return new;
    end if;

    if public.expense_counts_in_closed_cycle(old) then
      raise exception 'Esta despesa conta em um ciclo que já foi fechado. Reabra o ciclo no Fechamento para alterá-la.';
    end if;
  end if;

  if public.expense_counts_in_closed_cycle(new) then
    raise exception 'O ciclo desta data já foi fechado. Reabra o ciclo no Fechamento para lançar ou mover uma despesa para ele.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_house_expenses_guard_closed_cycle on public.house_expenses;
create trigger trg_house_expenses_guard_closed_cycle
  before insert or update on public.house_expenses
  for each row execute function public.guard_closed_cycle_expense();

create or replace function public.guard_closed_cycle_contribution()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') or pg_trigger_depth() > 1 then
    return new;
  end if;

  perform pg_advisory_xact_lock_shared(hashtextextended('house-ledger:' || new.house_id::text, 0));

  if public.house_date_is_closed(new.house_id, new.cycle_start_date) then
    raise exception 'O ciclo desta data já foi fechado. Reabra o ciclo no Fechamento para lançar um aporte nele.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_contributions_guard_closed_cycle on public.contributions;
create trigger trg_contributions_guard_closed_cycle
  before insert on public.contributions
  for each row execute function public.guard_closed_cycle_contribution();

revoke execute on function public.settlement_data_version(uuid) from public, anon;
revoke execute on function public.house_date_is_closed(uuid, date) from public, anon;
revoke execute on function public.expense_counts_in_closed_cycle(public.house_expenses) from public, anon;
grant execute on function public.settlement_data_version(uuid) to authenticated;
grant execute on function public.house_date_is_closed(uuid, date) to authenticated;
grant execute on function public.expense_counts_in_closed_cycle(public.house_expenses) to authenticated;

-- Recarrega o cache de schema do PostgREST
notify pgrst, 'reload schema';
