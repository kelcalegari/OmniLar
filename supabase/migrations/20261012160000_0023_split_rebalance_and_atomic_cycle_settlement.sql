-- ==============================================================================
-- 0023: Rateio que soma 100% + fechamento de ciclo atômico
-- Descrição:
--   1. Rateio padrão: quem entra na casa recebe uma fatia igual (100/n) e os
--      percentuais dos demais são reduzidos na mesma proporção, somando 100%.
--      Casas cujo rateio já não soma 100% são normalizadas uma vez.
--   2. Fechamento do ciclo: o app envia o plano apurado e o banco grava tudo em
--      uma única transação (caixinhas, aportes, contas, acordos P2P, parcelas e
--      Super Pix). Só administradores fecham ou reabrem um ciclo.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. RATEIO PADRÃO DA CASA
-- ------------------------------------------------------------------------------

-- 1.1 Normaliza as casas cujo rateio não soma 100%, preservando as proporções
do $$
declare
  h record;
  v_diff numeric;
begin
  for h in
    select house_id, sum(coalesce(default_split_percent, 0)) as total, count(*) as members
    from public.house_members
    where left_at is null
    group by house_id
    having sum(coalesce(default_split_percent, 0)) <> 100
  loop
    if h.total > 0 then
      update public.house_members
      set default_split_percent = round(coalesce(default_split_percent, 0) * 100 / h.total, 2)
      where house_id = h.house_id and left_at is null;
    else
      update public.house_members
      set default_split_percent = round(100.0 / h.members, 2)
      where house_id = h.house_id and left_at is null;
    end if;

    -- Centésimos que sobram do arredondamento vão para a maior fatia
    select 100 - sum(default_split_percent) into v_diff
    from public.house_members
    where house_id = h.house_id and left_at is null;

    if v_diff <> 0 then
      update public.house_members
      set default_split_percent = default_split_percent + v_diff
      where id = (
        select id from public.house_members
        where house_id = h.house_id and left_at is null
        order by default_split_percent desc, joined_at
        limit 1
      );
    end if;
  end loop;
end;
$$;

-- 1.2 Entrada por convite redistribui o rateio
create or replace function public.join_house_with_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_invite public.house_invites%rowtype;
  v_house public.houses%rowtype;
  v_members integer;
  v_total numeric;
  v_new_percent numeric;
begin
  if v_uid is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;

  select * into v_invite
  from public.house_invites
  where code = upper(trim(p_code))
  for update;

  if not found or v_invite.used_at is not null or v_invite.expires_at <= now() then
    raise exception 'Código de convite inválido ou expirado.';
  end if;

  -- Quem já mora na casa não consome o convite
  if not exists (
    select 1 from public.house_members
    where house_id = v_invite.house_id and user_id = v_uid and left_at is null
  ) then
    perform 1 from public.house_members
    where house_id = v_invite.house_id and left_at is null
    for update;

    select count(*), coalesce(sum(coalesce(default_split_percent, 0)), 0)
    into v_members, v_total
    from public.house_members
    where house_id = v_invite.house_id and left_at is null;

    -- Fatia igual para quem chega; os demais encolhem na mesma proporção
    v_new_percent := round(100.0 / (v_members + 1), 2);

    if v_members > 0 then
      if v_total > 0 then
        update public.house_members
        set default_split_percent = round(coalesce(default_split_percent, 0) * (100 - v_new_percent) / v_total, 2)
        where house_id = v_invite.house_id and left_at is null;
      else
        update public.house_members
        set default_split_percent = round((100 - v_new_percent) / v_members, 2)
        where house_id = v_invite.house_id and left_at is null;
      end if;

      -- Quem chega absorve os centésimos do arredondamento
      select 100 - sum(default_split_percent) into v_new_percent
      from public.house_members
      where house_id = v_invite.house_id and left_at is null;
    end if;

    insert into public.house_members (house_id, user_id, role, default_split_percent)
    values (v_invite.house_id, v_uid, v_invite.role, v_new_percent)
    on conflict (house_id, user_id) do update
      set left_at = null,
          role = excluded.role,
          joined_at = now(),
          default_split_percent = excluded.default_split_percent;

    update public.house_invites
    set used_at = now(), used_by = v_uid
    where id = v_invite.id;
  end if;

  select * into v_house from public.houses where id = v_invite.house_id;
  return to_jsonb(v_house);
end;
$$;

-- 1.3 Casa nova: quem cria começa com 100% do rateio
create or replace function public.create_house_with_owner(
  p_name text,
  p_cycle_start_day integer default 5,
  p_timezone text default 'America/Sao_Paulo'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_house_id uuid;
  v_house public.houses%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;

  -- 1. Insere a casa
  insert into public.houses (
    name, cycle_start_day, timezone, created_by
  ) values (
    trim(p_name), p_cycle_start_day, p_timezone, auth.uid()
  ) returning * into v_house;

  v_house_id := v_house.id;

  -- 2. Insere o criador como membro owner
  insert into public.house_members (
    house_id, user_id, role, default_split_percent
  ) values (
    v_house_id, auth.uid(), 'owner', 100.0
  );

  -- 3. Cria lista de compras padrão
  insert into public.shopping_lists (
    house_id, name, icon, is_default, created_by
  ) values (
    v_house_id, 'Supermercado & Feira', 'shopping_cart_outlined', true, auth.uid()
  );

  -- 4. Cria formas de pagamento padrão da casa
  insert into public.payment_methods (
    house_id, name, type, is_active, created_by
  ) values
    (v_house_id, 'Caixa da Casa', 'account', true, auth.uid()),
    (v_house_id, 'Pix', 'pix', true, auth.uid()),
    (v_house_id, 'Dinheiro em Espécie', 'cash', true, auth.uid());

  -- 5. Cria categorias essenciais da casa
  insert into public.categories (
    house_id, name, icon, color_hex, is_active, created_by
  ) values
    (v_house_id, 'Supermercado', 'shopping_cart_outlined', '#10B981', true, auth.uid()),
    (v_house_id, 'Moradia & Aluguel', 'home_outlined', '#3B82F6', true, auth.uid()),
    (v_house_id, 'Contas (Luz, Água, Internet)', 'bolt_outlined', '#F59E0B', true, auth.uid()),
    (v_house_id, 'Transporte & Carro', 'directions_car_outlined', '#EC4899', true, auth.uid()),
    (v_house_id, 'Lazer & Restaurantes', 'restaurant_outlined', '#8B5CF6', true, auth.uid()),
    (v_house_id, 'Saúde & Farmácia', 'local_hospital_outlined', '#EF4444', true, auth.uid());

  return to_jsonb(v_house);
end;
$$;

-- ------------------------------------------------------------------------------
-- 2. PAGAMENTO DE PARCELA: núcleo interno reutilizado pelo fechamento
-- ------------------------------------------------------------------------------

-- Grava ledger, alocação e baixa da parcela. NÃO checa quem está chamando:
-- só é executável por outras funções do banco.
create or replace function public.apply_p2p_installment_payment(
  p_installment_id uuid,
  p_amount_cents bigint,
  p_payment_method_id uuid default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.p2p_loans%rowtype;
  v_installment public.p2p_installments%rowtype;
  v_payment_id uuid;
  v_remaining_cents bigint;
begin
  select * into v_installment from public.p2p_installments where id = p_installment_id for update;
  if not found then
    raise exception 'Parcela não encontrada.';
  end if;

  select * into v_loan from public.p2p_loans where id = v_installment.loan_id;
  if not found then
    raise exception 'Empréstimo não encontrado.';
  end if;

  if v_installment.status not in ('pending', 'partial') then
    raise exception 'Esta parcela não está em aberto.';
  end if;

  v_remaining_cents := v_installment.amount_cents - v_installment.paid_cents;
  if p_amount_cents <= 0 or p_amount_cents > v_remaining_cents then
    raise exception 'Valor inválido. Restante devido: % centavos.', v_remaining_cents;
  end if;

  -- 1. Ledger imutável (receiver_id null = pagamento para a Casa)
  insert into public.payments (
    house_id, payer_id, receiver_id, amount_cents, type, notes, payment_method_id, created_by
  ) values (
    v_loan.house_id, v_loan.borrower_id, v_loan.lender_id, p_amount_cents, 'p2p_installment', p_notes, p_payment_method_id, auth.uid()
  ) returning id into v_payment_id;

  -- 2. Alocação
  insert into public.payment_allocations (
    payment_id, installment_id, allocated_cents
  ) values (
    v_payment_id, v_installment.id, p_amount_cents
  );

  -- 3. Atualiza parcela
  update public.p2p_installments
  set
    paid_cents = paid_cents + p_amount_cents,
    status = case
      when (paid_cents + p_amount_cents) >= amount_cents then 'paid'
      else 'partial'
    end,
    paid_at = now()
  where id = v_installment.id;

  -- 4. Nada mais em aberto: empréstimo quitado
  if not exists (
    select 1 from public.p2p_installments
    where loan_id = v_loan.id and status in ('pending', 'partial')
  ) then
    update public.p2p_loans set status = 'completed' where id = v_loan.id;
  end if;

  return v_payment_id;
end;
$$;

revoke execute on function public.apply_p2p_installment_payment(uuid, bigint, uuid, text) from public, anon, authenticated;

create or replace function public.pay_p2p_installment(
  p_installment_id uuid,
  p_amount_cents bigint,
  p_payment_method_id uuid default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.p2p_loans%rowtype;
begin
  select l.* into v_loan
  from public.p2p_installments i
  join public.p2p_loans l on l.id = i.loan_id
  where i.id = p_installment_id;

  if not found then
    raise exception 'Parcela não encontrada.';
  end if;

  -- Devedor ou credor podem pagar/baixar; no Caixa da Casa, também o admin
  if auth.uid() is distinct from v_loan.borrower_id
     and auth.uid() is distinct from v_loan.lender_id
     and not (v_loan.lender_is_house and public.is_house_admin(v_loan.house_id)) then
    raise exception 'Permissão negada para quitar esta parcela.';
  end if;

  return public.apply_p2p_installment_payment(p_installment_id, p_amount_cents, p_payment_method_id, p_notes);
end;
$$;

-- ------------------------------------------------------------------------------
-- 3. FECHAMENTO DE CICLO ATÔMICO
-- ------------------------------------------------------------------------------

-- p_plan (apurado pelo app a partir do Motor de Compensação):
-- {
--   "house_id": uuid, "cycle_start_date": "YYYY-MM-DD",
--   "total_expenses_cents": int, "total_contributions_cents": int, "total_cleared_p2p_cents": int,
--   "vault_operations": [{"vault_id", "member_id", "type": "deposit"|"withdraw", "amount_cents", "description"}],
--   "contributions":    [{"member_id", "amount_cents"}],
--   "expense_ids":      [uuid],
--   "new_loans":        [{"lender_id"|null, "borrower_id", "title", "description", "total_amount_cents",
--                         "repayment_mode", "installments": [{"number", "amount_cents", "due_date"}]}],
--   "installment_payments": [{"installment_id", "amount_cents"}],
--   "transfers":        [{"from_member_id", "to_member_id", "amount_cents"}]
-- }
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
  set status = 'paid'
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

-- Reabrir remove o registro do fechamento para permitir nova apuração.
-- Pagamentos, aportes e acordos já gravados permanecem (o ledger é imutável).
create or replace function public.reopen_cycle_settlement(p_house_id uuid, p_cycle_start_date date)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer;
begin
  if not public.is_house_admin(p_house_id) then
    raise exception 'Apenas administradores da casa podem reabrir o ciclo.';
  end if;

  delete from public.settlements
  where house_id = p_house_id and cycle_start_date = p_cycle_start_date;
  get diagnostics v_deleted = row_count;

  return v_deleted > 0;
end;
$$;

-- O cliente não grava mais fechamentos nem transferências diretamente
drop policy if exists "settlements_insert_admin" on public.settlements;
drop policy if exists "settlements_update_member" on public.settlements;
drop policy if exists "settlement_transfers_insert_member" on public.settlement_transfers;
revoke insert, update, delete on public.settlements from anon, authenticated;
revoke insert, update, delete on public.settlement_transfers from anon, authenticated;

revoke execute on function public.confirm_cycle_settlement(jsonb) from public, anon;
revoke execute on function public.reopen_cycle_settlement(uuid, date) from public, anon;
revoke execute on function public.pay_p2p_installment(uuid, bigint, uuid, text) from public, anon;
revoke execute on function public.join_house_with_invite(text) from public, anon;
grant execute on function public.confirm_cycle_settlement(jsonb) to authenticated;
grant execute on function public.reopen_cycle_settlement(uuid, date) to authenticated;
grant execute on function public.pay_p2p_installment(uuid, bigint, uuid, text) to authenticated;
grant execute on function public.join_house_with_invite(text) to authenticated;

-- Recarrega o cache de schema do PostgREST
notify pgrst, 'reload schema';
