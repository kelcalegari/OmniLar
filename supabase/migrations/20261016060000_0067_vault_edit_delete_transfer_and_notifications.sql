-- ==============================================================================
-- 0067: Caixinhas: prazo da meta, exclusão segura, transferência e avisos
-- Descrição:
--   - savings_vaults.target_date: prazo opcional da meta. O app mostra quanto
--     guardar por mês e avisa quando o ritmo está abaixo do necessário.
--   - Excluir caixinha (delete_savings_vault) exige saldo zerado e nenhum acordo
--     com o Lar ativo devolvendo para ela: as parcelas iriam para lugar nenhum.
--   - transfer_between_vaults: tira de uma caixinha e põe na outra na mesma
--     transação, com o mesmo motivo nos dois lados. counterpart_vault_id liga
--     os dois lançamentos à outra caixinha.
--   - Todo depósito pelo app também exige o motivo (o resgate já exigia).
--   - Avisos: vault_movement para os outros moradores a cada depósito, resgate
--     ou transferência feito pelo app, com o motivo; vault_goal_reached quando
--     o saldo alcança a meta, venha de onde vier.
-- ==============================================================================

-- 1. Prazo da meta
alter table public.savings_vaults
  add column if not exists target_date date;

grant update (name, target_amount_cents, icon, color_hex, deleted_at, target_date)
  on public.savings_vaults to authenticated;

-- 2. Lançamento ligado à outra caixinha da transferência
alter table public.savings_transactions
  add column if not exists counterpart_vault_id uuid;

-- 3. Exclusão segura
create or replace function public.guard_savings_vault_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.deleted_at is null and new.deleted_at is not null then
    if new.current_balance_cents <> 0 then
      raise exception 'Esvazie a caixinha antes de excluir: resgate ou transfira o saldo.';
    end if;
    if exists (
      select 1 from public.p2p_loans l
      where l.repay_to_vault_id = new.id and l.status = 'active'
    ) then
      raise exception 'Esta caixinha recebe as parcelas de um acordo com o Lar em aberto. Quite o acordo antes de excluir.';
    end if;
  end if;
  if old.deleted_at is not null and new.deleted_at is null then
    raise exception 'Caixinha excluída não volta.';
  end if;
  if nullif(btrim(coalesce(new.name, '')), '') is null then
    raise exception 'Dê um nome à caixinha.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_savings_vault_delete on public.savings_vaults;
create trigger trg_guard_savings_vault_delete
  before update on public.savings_vaults
  for each row execute function public.guard_savings_vault_delete();

-- O update direto de deleted_at não passa no RLS (a caixinha excluída some da
-- leitura): a exclusão vem por esta função, e o gatilho acima confere as regras.
create or replace function public.delete_savings_vault(p_vault_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vault public.savings_vaults%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;

  select * into v_vault
  from public.savings_vaults
  where id = p_vault_id and deleted_at is null
  for update;
  if not found or not public.is_house_member(v_vault.house_id) then
    raise exception 'Caixinha não encontrada nesta casa.';
  end if;

  update public.savings_vaults set deleted_at = now() where id = v_vault.id;
end;
$$;

revoke execute on function public.delete_savings_vault(uuid) from public, anon;
grant execute on function public.delete_savings_vault(uuid) to authenticated;

-- 4. Aviso de movimentação para os outros moradores
create or replace function public.notify_vault_movement(
  p_house_id uuid,
  p_vault_id uuid,
  p_transaction_id uuid,
  p_body text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.enqueue_notification(
    p_house_id,
    array(
      select m.user_id from public.house_members m
      where m.house_id = p_house_id and m.left_at is null
    ),
    'vault_movement', 'caixinhas',
    'Movimentação na caixinha',
    p_body,
    '/caixinhas/' || p_vault_id::text, 'savings_vault', p_vault_id,
    'vault_movement:' || p_transaction_id::text
  );
end;
$$;

revoke execute on function public.notify_vault_movement(uuid, uuid, uuid, text) from public, anon, authenticated;

-- 5. Depósito ou resgate: motivo nos dois e aviso aos outros moradores
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
  v_reason text := nullif(btrim(coalesce(p_description, '')), '');
  v_tx uuid;
  v_body text;
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
  if v_reason is null then
    raise exception '%', case when p_type = 'withdraw' then 'Informe o motivo do resgate.'
                              else 'Informe o motivo do depósito.' end;
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
  values (v_vault.id, v_vault.house_id, v_uid, p_amount_cents, p_type, v_reason, p_cycle_start_date)
  returning id into v_tx;

  v_body := public.notification_first_name(v_uid) || ' '
    || case
         when p_type = 'deposit' and p_cycle_start_date is not null then
           'trouxe ' || public.notification_brl(p_amount_cents) || ' do Caixa do ciclo para ' || v_vault.name
         when p_type = 'deposit' then
           'guardou ' || public.notification_brl(p_amount_cents) || ' em ' || v_vault.name
         when p_cycle_start_date is not null then
           'devolveu ' || public.notification_brl(p_amount_cents) || ' de ' || v_vault.name || ' ao Caixa do ciclo'
         else
           'resgatou ' || public.notification_brl(p_amount_cents) || ' de ' || v_vault.name
       end
    || ': ' || v_reason;
  perform public.notify_vault_movement(v_vault.house_id, v_vault.id, v_tx, v_body);

  return v_balance;
end;
$$;

revoke execute on function public.move_vault_balance(uuid, text, bigint, text, date) from public, anon;
grant execute on function public.move_vault_balance(uuid, text, bigint, text, date) to authenticated;

-- 6. Transferência entre caixinhas
create or replace function public.transfer_between_vaults(
  p_from_vault_id uuid,
  p_to_vault_id uuid,
  p_amount_cents bigint,
  p_description text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_from public.savings_vaults%rowtype;
  v_to public.savings_vaults%rowtype;
  v_reason text := nullif(btrim(coalesce(p_description, '')), '');
  v_tx uuid;
begin
  if v_uid is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'O valor deve ser maior que zero.';
  end if;
  if v_reason is null then
    raise exception 'Informe o motivo da transferência.';
  end if;
  if p_from_vault_id is null or p_to_vault_id is null or p_from_vault_id = p_to_vault_id then
    raise exception 'Escolha outra caixinha para receber o valor.';
  end if;

  -- Trava as duas sempre na mesma ordem: duas transferências cruzadas não se esperam para sempre
  perform 1 from public.savings_vaults
  where id in (p_from_vault_id, p_to_vault_id)
  order by id
  for update;

  select * into v_from from public.savings_vaults where id = p_from_vault_id and deleted_at is null;
  select * into v_to from public.savings_vaults where id = p_to_vault_id and deleted_at is null;
  if v_from.id is null or v_to.id is null
     or v_from.house_id <> v_to.house_id
     or not public.is_house_member(v_from.house_id) then
    raise exception 'Caixinha não encontrada nesta casa.';
  end if;
  if v_from.current_balance_cents < p_amount_cents then
    raise exception 'Saldo insuficiente na caixinha "%".', v_from.name;
  end if;

  update public.savings_vaults
  set current_balance_cents = current_balance_cents - p_amount_cents
  where id = v_from.id;
  update public.savings_vaults
  set current_balance_cents = current_balance_cents + p_amount_cents
  where id = v_to.id;

  insert into public.savings_transactions (vault_id, house_id, member_id, amount_cents, type, description, counterpart_vault_id)
  values (v_from.id, v_from.house_id, v_uid, p_amount_cents, 'withdraw', v_reason, v_to.id)
  returning id into v_tx;
  insert into public.savings_transactions (vault_id, house_id, member_id, amount_cents, type, description, counterpart_vault_id)
  values (v_to.id, v_to.house_id, v_uid, p_amount_cents, 'deposit', v_reason, v_from.id);

  perform public.notify_vault_movement(
    v_from.house_id, v_to.id, v_tx,
    public.notification_first_name(v_uid) || ' transferiu ' || public.notification_brl(p_amount_cents)
      || ' de ' || v_from.name || ' para ' || v_to.name || ': ' || v_reason
  );
end;
$$;

revoke execute on function public.transfer_between_vaults(uuid, uuid, bigint, text) from public, anon;
grant execute on function public.transfer_between_vaults(uuid, uuid, bigint, text) to authenticated;

-- 7. Meta atingida, venha o dinheiro de onde vier (depósito, fechamento, acordo)
create or replace function public.notify_vault_goal_reached()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.deleted_at is null
     and new.target_amount_cents is not null
     and old.current_balance_cents < new.target_amount_cents
     and new.current_balance_cents >= new.target_amount_cents then
    perform public.enqueue_notification(
      new.house_id,
      array(
        select m.user_id from public.house_members m
        where m.house_id = new.house_id and m.left_at is null
      ),
      'vault_goal_reached', 'caixinhas',
      'Meta atingida',
      new.name || ' atingiu a meta de ' || public.notification_brl(new.target_amount_cents),
      '/caixinhas/' || new.id::text, 'savings_vault', new.id,
      'vault_goal:' || new.id::text || ':' || new.target_amount_cents::text || ':' || current_date::text
    );
  end if;
  return null;
end;
$$;

drop trigger if exists trg_notify_vault_goal_reached on public.savings_vaults;
create trigger trg_notify_vault_goal_reached
  after update of current_balance_cents on public.savings_vaults
  for each row execute function public.notify_vault_goal_reached();
