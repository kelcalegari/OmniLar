-- ==============================================================================
-- 0021: Abatimento livre em empréstimos parcelados + opção "fora do ciclo"
-- Descrição:
--   1. settle_in_cycle: define se as parcelas de um empréstimo parcelado são
--      cobradas automaticamente no Fechamento do Ciclo (padrão) ou se as datas
--      servem só de lembrete e o pagamento é sempre manual.
--   2. pay_p2p_loan: abate um valor livre do empréstimo, distribuindo das
--      parcelas mais antigas para as mais novas em uma única transação
--      (um pagamento no ledger, uma alocação por parcela atingida).
-- ==============================================================================

-- 1. Cobrança no Fechamento do Ciclo
alter table public.p2p_loans
  add column if not exists settle_in_cycle boolean not null default true;

-- 2. Abatimento livre (mais antigas primeiro)
create or replace function public.pay_p2p_loan(
  p_loan_id uuid,
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
  v_total_remaining bigint;
  v_left bigint;
  v_part bigint;
begin
  select * into v_loan from public.p2p_loans where id = p_loan_id for update;
  if not found then
    raise exception 'Empréstimo não encontrado.';
  end if;

  -- Devedor ou credor podem pagar/baixar; no Caixa da Casa, também o admin
  if auth.uid() is distinct from v_loan.borrower_id
     and auth.uid() is distinct from v_loan.lender_id
     and not (v_loan.lender_is_house and public.is_house_admin(v_loan.house_id)) then
    raise exception 'Permissão negada para abater este empréstimo.';
  end if;

  select coalesce(sum(amount_cents - paid_cents), 0) into v_total_remaining
  from public.p2p_installments
  where loan_id = p_loan_id and status in ('pending', 'partial');

  if p_amount_cents <= 0 or p_amount_cents > v_total_remaining then
    raise exception 'Valor inválido. Saldo devedor: % centavos.', v_total_remaining;
  end if;

  -- 1. Ledger imutável (receiver_id null = pagamento para a Casa)
  insert into public.payments (
    house_id, payer_id, receiver_id, amount_cents, type, notes, payment_method_id, created_by
  ) values (
    v_loan.house_id, v_loan.borrower_id, v_loan.lender_id, p_amount_cents, 'p2p_installment', p_notes, p_payment_method_id, auth.uid()
  ) returning id into v_payment_id;

  -- 2. Distribui das parcelas mais antigas para as mais novas
  v_left := p_amount_cents;
  for v_installment in
    select * from public.p2p_installments
    where loan_id = p_loan_id and status in ('pending', 'partial')
    order by due_date, installment_number
    for update
  loop
    exit when v_left <= 0;
    v_part := least(v_left, v_installment.amount_cents - v_installment.paid_cents);
    continue when v_part <= 0;

    insert into public.payment_allocations (
      payment_id, installment_id, allocated_cents
    ) values (
      v_payment_id, v_installment.id, v_part
    );

    update public.p2p_installments
    set
      paid_cents = paid_cents + v_part,
      status = case
        when (paid_cents + v_part) >= amount_cents then 'paid'
        else 'partial'
      end,
      paid_at = now()
    where id = v_installment.id;

    v_left := v_left - v_part;
  end loop;

  -- 3. Saldo zerado: empréstimo quitado
  if p_amount_cents = v_total_remaining then
    update public.p2p_loans set status = 'completed' where id = p_loan_id;
  end if;

  return v_payment_id;
end;
$$;

-- Recarrega o cache de schema do PostgREST
notify pgrst, 'reload schema';
