-- ==============================================================================
-- 0027: Exclusão de série sem casar por título e saldo de caixinha atômico
-- Descrição:
--   - delete_house_expense apagava, nos escopos de série, toda despesa
--     recorrente da casa com o mesmo título, mesmo sem ligação com a série.
--     Agora só a matriz e as ocorrências ligadas por recurring_series_id.
--   - Depósito e resgate em caixinha liam o saldo no aparelho e regravavam o
--     total: dois aparelhos ao mesmo tempo perdiam uma das movimentações, e um
--     resgate acima do saldo zerava a caixinha registrando o valor inteiro no
--     extrato. move_vault_balance faz tudo em uma transação, com a caixinha
--     travada, e recusa resgate acima do saldo.
--   - O saldo e o extrato deixam de ser graváveis direto pelo cliente.
-- ==============================================================================

create or replace function public.delete_house_expense(
  p_expense_id uuid,
  p_scope text default 'thisInstanceOnly'
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_house_id uuid;
  v_series_id uuid;
  v_is_recurring boolean;
  v_due_date date;
begin
  select house_id, recurring_series_id, is_recurring, due_date
  into v_house_id, v_series_id, v_is_recurring, v_due_date
  from public.house_expenses
  where id = p_expense_id;

  if v_house_id is null then
    return false;
  end if;

  -- Valida se o usuário pertence à casa
  if not public.is_house_member(v_house_id) then
    raise exception 'Acesso negado: você não é membro desta casa';
  end if;

  v_series_id := coalesce(v_series_id, case when v_is_recurring then p_expense_id else null end);

  if p_scope = 'allInstances' then
    update public.house_expenses
    set deleted_at = now(), is_active = false
    where house_id = v_house_id
      and (
        id = p_expense_id
        or (v_series_id is not null and (id = v_series_id or recurring_series_id = v_series_id))
      );

  elsif p_scope = 'thisAndFuture' then
    if v_series_id is not null then
      update public.house_expenses
      set is_active = false
      where id = v_series_id;
    end if;

    update public.house_expenses
    set deleted_at = now()
    where house_id = v_house_id
      and (
        id = p_expense_id
        or (v_series_id is not null and (id = v_series_id or recurring_series_id = v_series_id))
      )
      and (v_due_date is null or due_date >= v_due_date);

  else
    -- Apenas esta ocorrência pontual
    update public.house_expenses
    set deleted_at = now()
    where id = p_expense_id;
  end if;

  return true;
end;
$$;

-- Depósito ou resgate em caixinha: devolve o saldo novo
create or replace function public.move_vault_balance(
  p_vault_id uuid,
  p_type text,
  p_amount_cents bigint,
  p_description text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_vault public.savings_vaults%rowtype;
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

  select * into v_vault
  from public.savings_vaults
  where id = p_vault_id and deleted_at is null
  for update;
  if not found or not public.is_house_member(v_vault.house_id) then
    raise exception 'Caixinha não encontrada nesta casa.';
  end if;

  if p_type = 'withdraw' and v_vault.current_balance_cents < p_amount_cents then
    raise exception 'Saldo insuficiente na caixinha "%".', v_vault.name;
  end if;

  update public.savings_vaults
  set current_balance_cents = current_balance_cents
    + case when p_type = 'deposit' then p_amount_cents else -p_amount_cents end
  where id = v_vault.id
  returning current_balance_cents into v_balance;

  insert into public.savings_transactions (vault_id, house_id, member_id, amount_cents, type, description)
  values (v_vault.id, v_vault.house_id, v_uid, p_amount_cents, p_type, p_description);

  return v_balance;
end;
$$;

revoke execute on function public.move_vault_balance(uuid, text, bigint, text) from public, anon;
grant execute on function public.move_vault_balance(uuid, text, bigint, text) to authenticated;

-- Saldo e extrato só mudam pelas funções do banco
revoke update on public.savings_vaults from anon, authenticated;
grant update (name, target_amount_cents, icon, color_hex, deleted_at) on public.savings_vaults to authenticated;
revoke insert, update, delete on public.savings_transactions from anon, authenticated;
