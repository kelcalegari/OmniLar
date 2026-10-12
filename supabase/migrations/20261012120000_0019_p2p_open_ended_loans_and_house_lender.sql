-- ==============================================================================
-- 0019: Empréstimos P2P sem prazo + Caixa da Casa como credor
-- Descrição:
--   1. Modalidade explícita do empréstimo (repayment_mode):
--        'installments' = parcelado (padrão, comportamento atual)
--        'open_ended'   = livre / sem prazo (o devedor abate quando puder)
--      O empréstimo sem prazo guarda uma única parcela de "saldo aberto" com
--      data técnica 2099-12-31, que nunca é exibida nem cobrada no fechamento.
--   2. Converte empréstimos antigos criados como "Acordo Livre" (parcelas só em
--      2099-12-31) para a nova modalidade.
--   3. Permite o "Caixa da Casa" como credor (reposição de Caixinha):
--      lender_id passa a aceitar null quando lender_is_house = true.
--   4. RLS: qualquer morador pode registrar o empréstimo (necessário quando um
--      terceiro fecha o ciclo e gera o acordo do saldo restante).
--   5. pay_p2p_installment aceita pagamento de empréstimos do Caixa da Casa.
-- ==============================================================================

-- 1. Modalidade de pagamento
alter table public.p2p_loans
  add column if not exists repayment_mode text not null default 'installments';

alter table public.p2p_loans
  drop constraint if exists p2p_loans_repayment_mode_check;
alter table public.p2p_loans
  add constraint p2p_loans_repayment_mode_check
  check (repayment_mode in ('installments', 'open_ended'));

-- 2. Backfill: empréstimos cujas parcelas ativas vencem todas em 2099-12-31
update public.p2p_loans l
set repayment_mode = 'open_ended'
where l.repayment_mode = 'installments'
  and exists (
    select 1 from public.p2p_installments i
    where i.loan_id = l.id and i.status <> 'renegotiated'
  )
  and not exists (
    select 1 from public.p2p_installments i
    where i.loan_id = l.id
      and i.status <> 'renegotiated'
      and i.due_date < date '2099-12-31'
  );

-- 3. Caixa da Casa como credor
alter table public.p2p_loans
  add column if not exists lender_is_house boolean not null default false;

alter table public.p2p_loans
  alter column lender_id drop not null;

alter table public.p2p_loans
  drop constraint if exists p2p_loans_lender_consistency;
alter table public.p2p_loans
  add constraint p2p_loans_lender_consistency
  check (
    (lender_is_house = true and lender_id is null)
    or (lender_is_house = false and lender_id is not null)
  );

-- 4. RLS
-- 4.1 Inserção de empréstimos: qualquer morador da casa, como autor do registro
drop policy if exists "p2p_loans_insert_member" on public.p2p_loans;
create policy "p2p_loans_insert_member" on public.p2p_loans for insert
  with check (public.is_house_member(house_id) and created_by = auth.uid());

-- 4.2 Atualização: partes envolvidas; empréstimos do Caixa da Casa também pelo admin
drop policy if exists "p2p_loans_update_parties" on public.p2p_loans;
create policy "p2p_loans_update_parties" on public.p2p_loans for update
  using (
    lender_id = auth.uid()
    or borrower_id = auth.uid()
    or (lender_is_house and public.is_house_admin(house_id))
  )
  with check (
    lender_id = auth.uid()
    or borrower_id = auth.uid()
    or (lender_is_house and public.is_house_admin(house_id))
  );

-- 4.3 Inserção de parcelas: qualquer morador da casa do empréstimo
drop policy if exists "p2p_installments_insert_parties" on public.p2p_installments;
create policy "p2p_installments_insert_parties" on public.p2p_installments for insert
  with check (exists (
    select 1 from public.p2p_loans l
    where l.id = loan_id and public.is_house_member(l.house_id)
  ));

-- 4.4 Atualização de parcelas: partes envolvidas; Caixa da Casa também pelo admin
drop policy if exists "p2p_installments_update_parties" on public.p2p_installments;
create policy "p2p_installments_update_parties" on public.p2p_installments for update
  using (exists (
    select 1 from public.p2p_loans l
    where l.id = loan_id
      and (
        l.lender_id = auth.uid()
        or l.borrower_id = auth.uid()
        or (l.lender_is_house and public.is_house_admin(l.house_id))
      )
  ));

-- 5. Pagamento de parcela (inclui empréstimos do Caixa da Casa)
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
  select * into v_installment from public.p2p_installments where id = p_installment_id;
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

  return v_payment_id;
end;
$$;

-- Recarrega o cache de schema do PostgREST
notify pgrst, 'reload schema';
