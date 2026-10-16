-- ==============================================================================
-- 0063: Depósito em caixinha tirando do Caixa do ciclo
-- Descrição:
--   - A devolução ao ciclo (0062) não tinha volta: depositar de novo na
--     caixinha não tirava o valor do Caixa do ciclo. Agora o depósito pode sair
--     do Caixa do ciclo em andamento, até o que as caixinhas devolveram a ele
--     (devoluções menos depósitos já tirados do Caixa no mesmo ciclo).
--   - savings_transactions.cycle_start_date passa a valer também no depósito:
--     no resgate o valor entrou no Caixa do ciclo, no depósito saiu dele.
--   - Devoluções e depósitos do mesmo ciclo passam por uma trava da casa, para
--     dois aparelhos não tirarem do Caixa o mesmo valor ao mesmo tempo.
-- ==============================================================================

alter table public.savings_transactions
  drop constraint if exists savings_transactions_cycle_return_check;

-- Depósito ou resgate em caixinha: devolve o saldo novo. Com p_cycle_start_date,
-- o resgate volta para o Caixa daquele ciclo e o depósito sai dele.
create or replace function public.move_vault_balance(
  p_vault_id uuid,
  p_type text,
  p_amount_cents bigint,
  p_description text default null,
  p_cycle_start_date date default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_vault public.savings_vaults%rowtype;
  v_today date;
  v_available bigint;
  v_balance bigint;
begin
  if v_uid is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'O valor deve ser maior que zero.';
  end if;
  if p_type is null or p_type not in ('deposit', 'withdraw') then
    raise exception 'Tipo de movimentação de caixinha inválido.';
  end if;
  if p_type = 'withdraw' and nullif(btrim(coalesce(p_description, '')), '') is null then
    raise exception 'Informe o motivo do resgate.';
  end if;

  select * into v_vault
  from public.savings_vaults
  where id = p_vault_id and deleted_at is null
  for update;
  if not found or not public.is_house_member(v_vault.house_id) then
    raise exception 'Caixinha não encontrada nesta casa.';
  end if;

  if p_cycle_start_date is not null then
    -- Mesma trava do aporte: o fechamento não corre ao mesmo tempo
    perform pg_advisory_xact_lock_shared(hashtextextended('house-ledger:' || v_vault.house_id::text, 0));
    -- Uma movimentação entre caixinha e Caixa do ciclo por vez na casa
    perform pg_advisory_xact_lock(hashtextextended('vault-cycle:' || v_vault.house_id::text, 0));

    select (now() at time zone coalesce(h.timezone, 'America/Sao_Paulo'))::date
    into v_today
    from public.houses h
    where h.id = v_vault.house_id;

    -- Só o ciclo em andamento: ele começou há no máximo um mês
    if p_cycle_start_date > v_today or p_cycle_start_date < v_today - 31 then
      raise exception 'Só o ciclo em andamento troca dinheiro com as caixinhas.';
    end if;
    if public.house_date_is_closed(v_vault.house_id, p_cycle_start_date) then
      raise exception 'Este ciclo já foi fechado. Reabra o ciclo no Fechamento para mexer no Caixa dele.';
    end if;

    if p_type = 'deposit' then
      select coalesce(sum(case when st.type = 'withdraw' then st.amount_cents else -st.amount_cents end), 0)
      into v_available
      from public.savings_transactions st
      where st.house_id = v_vault.house_id
        and st.cycle_start_date = p_cycle_start_date;
      if v_available < p_amount_cents then
        raise exception 'O Caixa do ciclo só tem R$ % vindo das caixinhas para devolver.',
          replace(to_char(greatest(v_available, 0) / 100.0, 'FM999999990.00'), '.', ',');
      end if;
    end if;
  end if;

  if p_type = 'withdraw' and v_vault.current_balance_cents < p_amount_cents then
    raise exception 'Saldo insuficiente na caixinha "%".', v_vault.name;
  end if;

  update public.savings_vaults
  set current_balance_cents = current_balance_cents
    + case when p_type = 'deposit' then p_amount_cents else -p_amount_cents end
  where id = v_vault.id
  returning current_balance_cents into v_balance;

  insert into public.savings_transactions (vault_id, house_id, member_id, amount_cents, type, description, cycle_start_date)
  values (v_vault.id, v_vault.house_id, v_uid, p_amount_cents, p_type, nullif(btrim(coalesce(p_description, '')), ''), p_cycle_start_date);

  return v_balance;
end;
$$;

revoke execute on function public.move_vault_balance(uuid, text, bigint, text, date) from public, anon;
grant execute on function public.move_vault_balance(uuid, text, bigint, text, date) to authenticated;
