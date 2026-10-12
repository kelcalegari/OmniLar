-- ==============================================================================
-- 0022: Endurecimento de segurança (membros, convites, P2P e Super Pix)
-- Descrição:
--   1. house_members: só entra em uma casa quem a criou, um admin adicionando
--      alguém, ou quem apresenta um convite válido (via RPC join_house_with_invite).
--   2. house_invites: deixa de ser listável por qualquer usuário autenticado;
--      o convite é validado (validade e uso único) dentro da RPC.
--   3. P2P: perdão e renegociação passam a ser RPCs com checagem de papel; o
--      cliente não altera mais parcelas nem o status do empréstimo diretamente.
--   4. settlement_transfers: confirmação só pela RPC confirm_settlement_transfer
--      (apenas quem recebe confirma).
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. HOUSE_MEMBERS: entrada controlada
-- ------------------------------------------------------------------------------
drop policy if exists "house_members_insert_owner_or_admin" on public.house_members;
create policy "house_members_insert_owner_or_admin" on public.house_members for insert
  with check (
    public.is_house_admin(house_id)
    or (
      -- Criador da casa se registrando como primeiro membro
      user_id = auth.uid()
      and exists (
        select 1 from public.houses h
        where h.id = house_members.house_id and h.created_by = auth.uid()
      )
    )
  );

-- ------------------------------------------------------------------------------
-- 2. HOUSE_INVITES: sem listagem aberta + entrada por RPC
-- ------------------------------------------------------------------------------
drop policy if exists "house_invites_select_authenticated" on public.house_invites;

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
    insert into public.house_members (house_id, user_id, role, default_split_percent)
    values (v_invite.house_id, v_uid, v_invite.role, 50.0)
    on conflict (house_id, user_id) do update
      set left_at = null, role = excluded.role, joined_at = now();

    update public.house_invites
    set used_at = now(), used_by = v_uid
    where id = v_invite.id;
  end if;

  select * into v_house from public.houses where id = v_invite.house_id;
  return to_jsonb(v_house);
end;
$$;

-- ------------------------------------------------------------------------------
-- 3. P2P: mutações de parcelas e status apenas por RPC
-- ------------------------------------------------------------------------------

-- 3.1 Pagamento de parcela: trava a linha, recusa parcela que não está em aberto
--     e marca o empréstimo como quitado quando não sobra nada em aberto.
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

  -- Devedor ou credor podem pagar/baixar; no Caixa da Casa, também o admin
  if auth.uid() is distinct from v_loan.borrower_id
     and auth.uid() is distinct from v_loan.lender_id
     and not (v_loan.lender_is_house and public.is_house_admin(v_loan.house_id)) then
    raise exception 'Permissão negada para quitar esta parcela.';
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

-- 3.2 Perdão: apenas o credor (ou o admin, quando o credor é o Caixa da Casa)
create or replace function public.forgive_p2p_loan(p_loan_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.p2p_loans%rowtype;
begin
  select * into v_loan from public.p2p_loans where id = p_loan_id for update;
  if not found then
    raise exception 'Empréstimo não encontrado.';
  end if;

  if not (
    coalesce(auth.uid() = v_loan.lender_id, false)
    or (v_loan.lender_is_house and public.is_house_admin(v_loan.house_id))
  ) then
    raise exception 'Apenas o credor pode perdoar este empréstimo.';
  end if;

  if v_loan.status not in ('active', 'renegotiated') then
    raise exception 'Este empréstimo não está em aberto.';
  end if;

  update public.p2p_installments
  set status = 'forgiven'
  where loan_id = p_loan_id and status in ('pending', 'partial');

  update public.p2p_loans set status = 'forgiven' where id = p_loan_id;

  return true;
end;
$$;

-- 3.3 Renegociação: reparcela o saldo em aberto em uma única transação
create or replace function public.renegotiate_p2p_loan(
  p_loan_id uuid,
  p_installments_count integer,
  p_first_due_date date
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.p2p_loans%rowtype;
  v_remaining bigint;
  v_paid_count integer;
  v_kept integer[];
  v_quotient bigint;
  v_remainder bigint;
  v_next integer := 0;
begin
  select * into v_loan from public.p2p_loans where id = p_loan_id for update;
  if not found then
    raise exception 'Empréstimo não encontrado.';
  end if;

  -- Devedor ou credor podem renegociar; no Caixa da Casa, também o admin
  if auth.uid() is distinct from v_loan.borrower_id
     and auth.uid() is distinct from v_loan.lender_id
     and not (v_loan.lender_is_house and public.is_house_admin(v_loan.house_id)) then
    raise exception 'Permissão negada para renegociar este empréstimo.';
  end if;

  if p_installments_count is null or p_installments_count < 1 or p_installments_count > 120 then
    raise exception 'Número de parcelas inválido.';
  end if;
  if p_first_due_date is null then
    raise exception 'Data do primeiro vencimento é obrigatória.';
  end if;

  perform 1 from public.p2p_installments where loan_id = p_loan_id for update;

  select
    coalesce(sum(amount_cents - paid_cents) filter (where status in ('pending', 'partial')), 0),
    count(*) filter (where status = 'paid'),
    coalesce(array_agg(installment_number) filter (where status in ('paid', 'forgiven')), '{}')
  into v_remaining, v_paid_count, v_kept
  from public.p2p_installments
  where loan_id = p_loan_id;

  if v_remaining <= 0 then
    raise exception 'Não há saldo remanescente a ser renegociado.';
  end if;
  if v_remaining < p_installments_count then
    raise exception 'Saldo pequeno demais para esse número de parcelas.';
  end if;

  -- Parcelas em aberto saem de cena; pagas e perdoadas continuam valendo
  update public.p2p_installments
  set status = 'renegotiated'
  where loan_id = p_loan_id and status in ('pending', 'partial');

  v_quotient := v_remaining / p_installments_count;
  v_remainder := v_remaining % p_installments_count;

  for i in 0..(p_installments_count - 1) loop
    -- Números de parcelas pagas/perdoadas não são reutilizados
    loop
      v_next := v_next + 1;
      exit when not (v_next = any (v_kept));
    end loop;

    insert into public.p2p_installments (
      loan_id, installment_number, amount_cents, paid_cents, due_date, status
    ) values (
      p_loan_id,
      v_next,
      v_quotient + case when i < v_remainder then 1 else 0 end,
      0,
      (p_first_due_date + make_interval(months => i))::date,
      'pending'
    );
  end loop;

  -- Ao definir um parcelamento, um empréstimo sem prazo passa a ser parcelado
  update public.p2p_loans
  set
    status = 'renegotiated',
    installments_count = v_paid_count + p_installments_count,
    repayment_mode = 'installments'
  where id = p_loan_id;

  return true;
end;
$$;

-- 3.4 O cliente não escreve mais direto em parcelas nem no status do empréstimo.
--     Resta apenas a opção "cobrar no fechamento do ciclo" (settle_in_cycle).
drop policy if exists "p2p_installments_update_parties" on public.p2p_installments;
revoke update on public.p2p_installments from anon, authenticated;

revoke update on public.p2p_loans from anon, authenticated;
grant update (settle_in_cycle) on public.p2p_loans to authenticated;

-- Excluir parcelas avulsas apagaria dívida sem rastro: só credor, criador ou admin
-- (a exclusão do empréstimo segue removendo as parcelas em cascata).
drop policy if exists "p2p_installments_delete_parties" on public.p2p_installments;
create policy "p2p_installments_delete_parties" on public.p2p_installments for delete
  using (exists (
    select 1 from public.p2p_loans l
    where l.id = loan_id
      and public.is_house_member(l.house_id)
      and (
        l.lender_id = auth.uid()
        or l.created_by = auth.uid()
        or public.is_house_admin(l.house_id)
      )
  ));

-- ------------------------------------------------------------------------------
-- 4. SETTLEMENT_TRANSFERS: confirmação só pela RPC (quem recebe confirma)
-- ------------------------------------------------------------------------------
drop policy if exists "settlement_transfers_update_party" on public.settlement_transfers;
revoke update on public.settlement_transfers from anon, authenticated;

-- ------------------------------------------------------------------------------
-- 5. Execução das RPCs apenas por usuários autenticados
-- ------------------------------------------------------------------------------
revoke execute on function public.join_house_with_invite(text) from public, anon;
revoke execute on function public.forgive_p2p_loan(uuid) from public, anon;
revoke execute on function public.renegotiate_p2p_loan(uuid, integer, date) from public, anon;
revoke execute on function public.pay_p2p_installment(uuid, bigint, uuid, text) from public, anon;
revoke execute on function public.pay_p2p_loan(uuid, bigint, uuid, text) from public, anon;
revoke execute on function public.confirm_settlement_transfer(uuid) from public, anon;

grant execute on function public.join_house_with_invite(text) to authenticated;
grant execute on function public.forgive_p2p_loan(uuid) to authenticated;
grant execute on function public.renegotiate_p2p_loan(uuid, integer, date) to authenticated;
grant execute on function public.pay_p2p_installment(uuid, bigint, uuid, text) to authenticated;
grant execute on function public.pay_p2p_loan(uuid, bigint, uuid, text) to authenticated;
grant execute on function public.confirm_settlement_transfer(uuid) to authenticated;

-- Recarrega o cache de schema do PostgREST
notify pgrst, 'reload schema';
