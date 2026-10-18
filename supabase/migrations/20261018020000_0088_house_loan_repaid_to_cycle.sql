-- ==============================================================================
-- 0088: Pagamento de empréstimo do ciclo volta para o Caixa do ciclo
-- Descrição:
--   Empréstimo com house_funding = 'cycle' (0086) tirou dinheiro do Caixa do
--   ciclo. Pago fora do fechamento, o app pedia uma Caixinha e o valor ficava
--   nela, então o Fôlego do Caixa continuava descontando o empréstimo inteiro.
--   - route_house_loan_payment_to_vault ignora a Caixinha escolhida quando o
--     empréstimo é do ciclo: o pagamento volta para o Caixa.
--   - house_loans_repaid_to_cycle soma o que já voltou ao Caixa, fora do
--     fechamento, dos empréstimos liberados em um período. O app desconta isso
--     do que o ciclo emprestou.
--   - Os pagamentos que já tinham caído em uma Caixinha saem dela e voltam
--     ao Caixa do ciclo como retirada para o ciclo (0062), que o app já soma.
--     house_loans_repaid_to_cycle não os conta de novo.
-- ==============================================================================

create or replace function public.route_house_loan_payment_to_vault()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.p2p_loans%rowtype;
  v_vault_id uuid;
  v_chosen text;
begin
  select l.* into v_loan
  from public.p2p_installments i
  join public.p2p_loans l on l.id = i.loan_id
  where i.id = new.installment_id;

  -- Empréstimo do ciclo: o pagamento volta para o Caixa, nunca para uma Caixinha
  if not found or not v_loan.lender_is_house or v_loan.house_funding = 'cycle' then
    return new;
  end if;

  v_vault_id := public.p2p_loan_repay_vault(v_loan.id);

  -- Sem caixinha de origem: vale a escolhida por quem está pagando
  if v_vault_id is null then
    v_chosen := nullif(current_setting('omnilar.repay_vault_id', true), '');
    if v_chosen is not null then
      select v.id into v_vault_id
      from public.savings_vaults v
      where v.id = v_chosen::uuid and v.house_id = v_loan.house_id and v.deleted_at is null;
      if v_vault_id is null then
        raise exception 'Caixinha não encontrada nesta casa.';
      end if;
    end if;
  end if;

  if v_vault_id is null then
    return new;
  end if;

  update public.savings_vaults
  set current_balance_cents = current_balance_cents + new.allocated_cents
  where id = v_vault_id;

  insert into public.savings_transactions (vault_id, house_id, member_id, amount_cents, type, description)
  values (
    v_vault_id, v_loan.house_id, v_loan.borrower_id, new.allocated_cents, 'deposit',
    'Pagamento de acordo com o Lar: ' || v_loan.title
  );

  return new;
end;
$$;
revoke execute on function public.route_house_loan_payment_to_vault() from public, anon, authenticated;

-- Quanto dos empréstimos do ciclo liberados entre p_start e p_end já voltou ao
-- Caixa fora do fechamento (o fechamento conta as parcelas que cobra).
create or replace function public.house_loans_repaid_to_cycle(p_house_id uuid, p_start date, p_end date)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(pa.allocated_cents), 0)::bigint
  from public.payment_allocations pa
  join public.payments p on p.id = pa.payment_id
  join public.p2p_installments i on i.id = pa.installment_id
  join public.p2p_loans l on l.id = i.loan_id
  where public.is_house_member(p_house_id)
    and l.house_id = p_house_id
    and l.lender_is_house
    and l.house_funding = 'cycle'
    and l.status <> 'cancelled'
    and l.funded_on between p_start and p_end
    and p.type = 'p2p_installment'
    and p.notes is distinct from 'Fechamento do ciclo'
    -- Pago para uma Caixinha antes desta migration: voltou como retirada para o ciclo
    and not exists (
      select 1 from public.savings_transactions st
      where st.house_id = p.house_id and st.created_at = p.created_at
        and st.type = 'deposit' and st.amount_cents = pa.allocated_cents
    );
$$;
revoke execute on function public.house_loans_repaid_to_cycle(uuid, date, date) from public, anon;
grant execute on function public.house_loans_repaid_to_cycle(uuid, date, date) to authenticated, service_role;

-- Pagamentos de empréstimo do ciclo que já tinham caído em uma Caixinha (o
-- depósito e o pagamento foram gravados na mesma transação): saem dela para o
-- ciclo que emprestou o dinheiro
with wrong as (
  select st.vault_id, st.house_id, st.member_id, st.amount_cents, l.title, l.funded_on
  from public.savings_transactions st
  join public.payments p
    on p.house_id = st.house_id and p.created_at = st.created_at and p.type = 'p2p_installment'
  join public.payment_allocations pa
    on pa.payment_id = p.id and pa.allocated_cents = st.amount_cents
  join public.p2p_installments i on i.id = pa.installment_id
  join public.p2p_loans l on l.id = i.loan_id
  where st.type = 'deposit'
    and l.house_funding = 'cycle'
    and l.repay_to_vault_id is null
    and st.description = 'Pagamento de acordo com o Lar: ' || l.title
),
moved as (
  insert into public.savings_transactions (
    vault_id, house_id, member_id, amount_cents, type, description, cycle_start_date
  )
  select vault_id, house_id, member_id, amount_cents, 'withdraw',
         'Volta ao Caixa do ciclo: ' || title, funded_on
  from wrong
  returning vault_id, amount_cents
)
update public.savings_vaults v
set current_balance_cents = v.current_balance_cents - m.total
from (select vault_id, sum(amount_cents) as total from moved group by vault_id) m
where v.id = m.vault_id;

notify pgrst, 'reload schema';
