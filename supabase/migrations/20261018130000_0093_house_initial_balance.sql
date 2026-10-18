-- ==============================================================================
-- 0093: Saldo inicial da casa
-- Descrição:
--   A casa nascia com a Reserva da Casa zerada (0033) e sem dinheiro no Caixa.
--   Quem já tinha dinheiro guardado ou na conta da casa não tinha onde dizer.
--   1. Reserva guardada: entra na Reserva da Casa como um depósito com o motivo
--      "Saldo inicial da casa" e sem ciclo (cycle_start_date nulo), então não
--      é dinheiro trocado com o Caixa do ciclo e não muda o saldo de abertura.
--      houses.initial_reserve_transaction_id liga a casa a esse lançamento.
--   2. Saldo na conta da casa: houses.initial_cash_cents vale como a sobra do
--      ciclo que começa em houses.initial_cash_cycle_start (o primeiro da
--      casa), quando não há fechamento anterior. Segue a regra da sobra do
--      ciclo anterior (0092) como qualquer sobra; o cálculo é do app.
--   3. set_house_initial_balance: só administradores. Gravar de novo troca os
--      valores: o lançamento da Reserva é corrigido (ou apagado, com zero) em
--      vez de ganhar outro. O ledger das caixinhas continua imutável para todo
--      o resto; só esta função mexe nesse lançamento.
--   4. O saldo da conta não muda com o primeiro ciclo já fechado: é preciso
--      reabrir o ciclo antes.
-- ==============================================================================

alter table public.houses
  add column if not exists initial_cash_cents bigint not null default 0
    check (initial_cash_cents >= 0),
  add column if not exists initial_cash_cycle_start date,
  add column if not exists initial_reserve_cents bigint not null default 0
    check (initial_reserve_cents >= 0),
  add column if not exists initial_reserve_transaction_id uuid;

-- Ledger das caixinhas: imutável, menos o lançamento do saldo inicial quando
-- set_house_initial_balance liga a marca omnilar.initial_balance
create or replace function public.prevent_savings_ledger_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'DELETE' and current_setting('omnilar.deleting_house', true) = 'on' then
    return OLD;
  end if;
  if current_setting('omnilar.initial_balance', true) = 'on'
      and exists (
        select 1 from public.houses h
        where h.id = OLD.house_id and h.initial_reserve_transaction_id = OLD.id
      ) then
    if TG_OP = 'DELETE' then
      return OLD;
    end if;
    return NEW;
  end if;
  raise exception 'Operação não permitida: registros do ledger financeiro são imutáveis.';
end;
$$;

revoke execute on function public.prevent_savings_ledger_mutation() from public, anon, authenticated;

drop trigger if exists trg_savings_transactions_immutable on public.savings_transactions;
create trigger trg_savings_transactions_immutable
  before update or delete on public.savings_transactions
  for each row execute function public.prevent_savings_ledger_mutation();

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
  if not public.is_house_admin(p_house_id) then
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

notify pgrst, 'reload schema';
