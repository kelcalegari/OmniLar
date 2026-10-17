-- ==============================================================================
-- 0086: Empréstimo do Caixa da Casa com origem do dinheiro
-- Descrição:
--   Um administrador pode emprestar dinheiro da Casa a um morador, escolhendo
--   de onde ele sai:
--   - cycle: do Caixa do ciclo em andamento. O valor sai da sobra do ciclo em
--     que foi liberado (funded_on) e as parcelas voltam ao Caixa nos
--     fechamentos, como qualquer acordo com o Lar.
--   - vault: de uma caixinha. O saque acontece na mesma transação e cada
--     pagamento volta para ela (repay_to_vault_id, 0037).
--   O empréstimo da fatura paga pelo Caixa (importação) também é do ciclo:
--   create_p2p_loan aceita house_funding = 'cycle' para acordo com o Lar.
--   Recusado (0082) ou apagado, o que a caixinha ainda não recebeu de volta
--   retorna a ela. Empréstimo do ciclo liberado em ciclo fechado não é apagado.
-- ==============================================================================

alter table public.p2p_loans
  add column if not exists house_funding text check (house_funding in ('cycle', 'vault')),
  add column if not exists funded_on date;

alter table public.p2p_loans drop constraint if exists p2p_loans_house_funding_check;
alter table public.p2p_loans add constraint p2p_loans_house_funding_check
  check (house_funding is null or (lender_is_house and funded_on is not null));

create index if not exists idx_p2p_loans_house_funding
  on public.p2p_loans (house_id, funded_on) where house_funding = 'cycle';

-- 1. create_p2p_loan grava a origem "ciclo" (caixinha só por create_house_loan)
create or replace function public.create_p2p_loan(p_loan jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id uuid;
  v_house uuid := (p_loan->>'house_id')::uuid;
  v_funding text := nullif(p_loan->>'house_funding', '');
  v_funded_on date := (p_loan->>'funded_on')::date;
begin
  if jsonb_array_length(coalesce(p_loan->'installments', '[]'::jsonb)) = 0 then
    raise exception 'O empréstimo precisa de ao menos uma parcela.';
  end if;
  if v_funding is not null then
    if v_funding <> 'cycle' then
      raise exception 'Empréstimo de caixinha é criado por create_house_loan.';
    end if;
    if not coalesce((p_loan->>'lender_is_house')::boolean, false) then
      raise exception 'Só o Caixa da Casa empresta dinheiro do ciclo.';
    end if;
    if v_funded_on is null then
      raise exception 'Informe o dia em que o dinheiro saiu do Caixa.';
    end if;
    if public.is_date_in_closed_cycle(v_house, v_funded_on) then
      raise exception 'Este ciclo já foi fechado. Reabra o ciclo no Fechamento para tirar dinheiro do Caixa dele.';
    end if;
  end if;

  insert into public.p2p_loans (
    id, house_id, lender_id, lender_is_house, repayment_mode, settle_in_cycle,
    borrower_id, title, description, total_amount_cents, installments_count,
    status, created_by, created_at, house_funding, funded_on
  ) values (
    coalesce((p_loan->>'id')::uuid, gen_random_uuid()),
    v_house,
    (p_loan->>'lender_id')::uuid,
    coalesce((p_loan->>'lender_is_house')::boolean, false),
    coalesce(p_loan->>'repayment_mode', 'installments'),
    coalesce((p_loan->>'settle_in_cycle')::boolean, true),
    (p_loan->>'borrower_id')::uuid,
    p_loan->>'title',
    p_loan->>'description',
    (p_loan->>'total_amount_cents')::bigint,
    coalesce((p_loan->>'installments_count')::integer, 1),
    coalesce(p_loan->>'status', 'active'),
    auth.uid(),
    coalesce((p_loan->>'created_at')::timestamptz, now()),
    v_funding,
    case when v_funding is not null then v_funded_on end
  )
  returning id into v_id;

  insert into public.p2p_installments (
    id, loan_id, installment_number, amount_cents, paid_cents, due_date, status, paid_at
  )
  select
    coalesce((inst->>'id')::uuid, gen_random_uuid()),
    v_id,
    (inst->>'installment_number')::integer,
    (inst->>'amount_cents')::bigint,
    coalesce((inst->>'paid_cents')::bigint, 0),
    (inst->>'due_date')::date,
    coalesce(inst->>'status', 'pending'),
    (inst->>'paid_at')::timestamptz
  from jsonb_array_elements(p_loan->'installments') as inst;

  return v_id;
end;
$$;
revoke execute on function public.create_p2p_loan(jsonb) from public, anon;
grant execute on function public.create_p2p_loan(jsonb) to authenticated;

-- 2. Empréstimo do Caixa da Casa, do ciclo ou de uma caixinha
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
  if not public.is_house_admin(v_house) then
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

-- 3. Recusado ou apagado: o que a caixinha ainda não recebeu volta para ela
create or replace function public.refund_house_loan_vault()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.p2p_loans%rowtype := case when TG_OP = 'DELETE' then old else new end;
  v_vault public.savings_vaults%rowtype;
  v_open bigint;
  v_tx uuid;
begin
  if TG_OP = 'UPDATE' and not (new.status = 'cancelled' and old.status is distinct from 'cancelled') then
    return new;
  end if;

  -- Liberação de ciclo fechado já entrou na sobra daquele fechamento
  if TG_OP = 'DELETE' and old.house_funding = 'cycle' and old.status <> 'cancelled'
     and public.is_date_in_closed_cycle(old.house_id, old.funded_on) then
    raise exception 'Este empréstimo saiu do Caixa de um ciclo já fechado. Reabra o ciclo no Fechamento para apagá-lo.';
  end if;

  if v_loan.house_funding is distinct from 'vault' or v_loan.repay_to_vault_id is null
     or (TG_OP = 'DELETE' and old.status = 'cancelled') then
    return v_loan;
  end if;

  select coalesce(sum(greatest(i.amount_cents - i.paid_cents, 0)), 0)
  into v_open
  from public.p2p_installments i
  where i.loan_id = v_loan.id
    and i.status not in ('paid', 'forgiven', 'renegotiated');

  select * into v_vault from public.savings_vaults where id = v_loan.repay_to_vault_id for update;
  if v_open <= 0 or not found or v_vault.deleted_at is not null then
    return v_loan;
  end if;

  update public.savings_vaults
  set current_balance_cents = current_balance_cents + v_open
  where id = v_vault.id;

  insert into public.savings_transactions (vault_id, house_id, member_id, amount_cents, type, description)
  values (
    v_vault.id, v_vault.house_id, coalesce(auth.uid(), v_loan.created_by), v_open, 'deposit',
    'Empréstimo desfeito: ' || v_loan.title
  )
  returning id into v_tx;

  perform public.notify_vault_movement(
    v_vault.house_id, v_vault.id, v_tx,
    public.notification_brl(v_open) || ' voltaram para ' || v_vault.name
      || ': o empréstimo ' || v_loan.title || ' foi desfeito'
  );
  return v_loan;
end;
$$;
revoke execute on function public.refund_house_loan_vault() from public, anon, authenticated;

drop trigger if exists trg_refund_house_loan_vault_update on public.p2p_loans;
create trigger trg_refund_house_loan_vault_update
  before update of status on public.p2p_loans
  for each row execute function public.refund_house_loan_vault();

drop trigger if exists trg_refund_house_loan_vault_delete on public.p2p_loans;
create trigger trg_refund_house_loan_vault_delete
  before delete on public.p2p_loans
  for each row execute function public.refund_house_loan_vault();

notify pgrst, 'reload schema';
