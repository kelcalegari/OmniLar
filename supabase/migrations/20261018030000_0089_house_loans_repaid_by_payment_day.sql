-- ==============================================================================
-- 0089: O pagamento de empréstimo do ciclo conta no ciclo em que foi pago
-- Descrição:
--   house_loans_repaid_to_cycle (0088) passa a somar pelo dia do pagamento,
--   no fuso da casa: o dinheiro entra no Caixa do ciclo em que voltou, e não
--   no ciclo que emprestou (que pode já estar fechado).
-- ==============================================================================

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
  join public.houses h on h.id = l.house_id
  where public.is_house_member(p_house_id)
    and l.house_id = p_house_id
    and l.lender_is_house
    and l.house_funding = 'cycle'
    and l.status <> 'cancelled'
    and (p.created_at at time zone coalesce(h.timezone, 'America/Sao_Paulo'))::date
        between p_start and p_end
    and p.type = 'p2p_installment'
    and p.notes is distinct from 'Fechamento do ciclo'
    -- Pago para uma Caixinha antes da 0088: voltou como retirada para o ciclo
    and not exists (
      select 1 from public.savings_transactions st
      where st.house_id = p.house_id and st.created_at = p.created_at
        and st.type = 'deposit' and st.amount_cents = pa.allocated_cents
    );
$$;
revoke execute on function public.house_loans_repaid_to_cycle(uuid, date, date) from public, anon;
grant execute on function public.house_loans_repaid_to_cycle(uuid, date, date) to authenticated, service_role;

notify pgrst, 'reload schema';
