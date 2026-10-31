-- ==============================================================================
-- 0120: Empréstimo do Caixa respeita o aceite da casa
-- Descrição:
--   A 0116 deixou a casa dispensar o aceite do devedor por origem
--   (`houses.loan_acceptance`). O empréstimo do Caixa, porém, é criado por
--   `create_house_loan`, que roda como dona das tabelas e decidia o aceite à
--   parte, sempre pedindo quando quem lança não é o devedor. Agora ele lê a
--   chave `house`: desligada, o empréstimo do Caixa já nasce aceito.
--   Chave ausente continua valendo true (pede aceite), então nada muda para
--   quem não mexeu na configuração.
-- ==============================================================================

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
  v_required boolean := true;
begin
  if v_uid is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;
  if not public.has_house_permission(v_house, 'emprestimos_da_casa') then
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

  -- A casa pode dispensar o aceite do empréstimo do Caixa (0116, chave house)
  select coalesce((h.loan_acceptance->>'house')::boolean, true)
  into v_required
  from public.houses h
  where h.id = v_house;
  v_required := coalesce(v_required, true) and v_uid is distinct from v_borrower;

  -- Criado aqui (dono das tabelas), nasceria aceito: o aceite é decidido abaixo
  v_id := public.create_p2p_loan(
    (p_loan - 'house_funding' - 'funded_on' - 'lender_id') || jsonb_build_object('lender_is_house', true)
  );

  update public.p2p_loans
  set created_by = v_uid,
      house_funding = p_funding,
      funded_on = v_today,
      repay_to_vault_id = case when p_funding = 'vault' then v_vault.id end,
      awaiting_acceptance = v_required,
      accepted_at = case when v_required then null else now() end
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
