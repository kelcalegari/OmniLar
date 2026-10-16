-- ==============================================================================
-- 0062: Resgate de caixinha devolvido ao ciclo e motivo obrigatório
-- Descrição:
--   - O resgate só tirava o valor da caixinha: o dinheiro não entrava em lugar
--     nenhum. Agora quem resgata pode devolvê-lo ao Caixa do ciclo em aberto.
--     O valor é da casa, não de um morador: entra como a sobra do ciclo
--     anterior, sem virar aporte nem crédito de ninguém no fechamento.
--   - savings_transactions.cycle_start_date marca o resgate devolvido e diz em
--     qual ciclo ele entrou. Ciclo já fechado recusa, como o aporte.
--   - Todo resgate feito pelo app exige o motivo.
--   - A assinatura antiga de move_vault_balance sai: chamada com os quatro
--     parâmetros de antes cai na nova, com o ciclo vazio (só sacar).
-- ==============================================================================

alter table public.savings_transactions
  add column if not exists cycle_start_date date;

alter table public.savings_transactions
  drop constraint if exists savings_transactions_cycle_return_check;
alter table public.savings_transactions
  add constraint savings_transactions_cycle_return_check
  check (cycle_start_date is null or type = 'withdraw');

create index if not exists idx_savings_transactions_cycle_return
  on public.savings_transactions (house_id, cycle_start_date)
  where cycle_start_date is not null;

drop function if exists public.move_vault_balance(uuid, text, bigint, text);

-- Depósito ou resgate em caixinha: devolve o saldo novo. Com p_cycle_start_date,
-- o resgate volta para o Caixa daquele ciclo.
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
  if p_cycle_start_date is not null and p_type <> 'withdraw' then
    raise exception 'Só o resgate pode ser devolvido ao ciclo.';
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

    select (now() at time zone coalesce(h.timezone, 'America/Sao_Paulo'))::date
    into v_today
    from public.houses h
    where h.id = v_vault.house_id;

    -- Só o ciclo em andamento: ele começou há no máximo um mês
    if p_cycle_start_date > v_today or p_cycle_start_date < v_today - 31 then
      raise exception 'O resgate só pode voltar para o ciclo em andamento.';
    end if;
    if public.house_date_is_closed(v_vault.house_id, p_cycle_start_date) then
      raise exception 'Este ciclo já foi fechado. Reabra o ciclo no Fechamento para devolver o valor a ele.';
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
