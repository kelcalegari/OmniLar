-- ==============================================================================
-- Migration: 0113_settle_mercado_pago_invoice_1014
-- Descrição:
--   Dá baixa como quitada na fatura do cartão Mercado Pago com vencimento em
--   14/10/2026 (R$ 1.168,78), composta 100% por compras pessoais que já foram
--   totalmente amortizadas pelos moradores para a titular do cartão.
-- ==============================================================================

do $$
declare
  v_pm_id uuid;
begin
  select id into v_pm_id
  from public.payment_methods
  where name ilike '%Mercado Pago%'
  limit 1;

  if v_pm_id is not null then
    -- 1. Marca a fatura importada como paga pela titular em 10/10/2026
    update public.import_batches
    set invoice_paid_at = '2026-10-10 12:00:00+00'::timestamptz,
        invoice_paid_by_house = false
    where payment_method_id = v_pm_id
      and invoice_due_date = '2026-10-14'
      and status = 'confirmed';

    -- 2. Atualiza despesas associadas a esse vencimento caso existam
    update public.house_expenses
    set status = 'paid',
        paid_at = '2026-10-10 12:00:00+00'::timestamptz,
        paid_out_of_pocket = true
    where payment_method_id = v_pm_id
      and due_date = '2026-10-14'
      and deleted_at is null
      and paid_at is null;
  else
    -- Fallback por data da fatura importada caso o nome varie
    update public.import_batches
    set invoice_paid_at = '2026-10-10 12:00:00+00'::timestamptz,
        invoice_paid_by_house = false
    where invoice_due_date = '2026-10-14'
      and status = 'confirmed'
      and invoice_paid_at is null;
  end if;
end;
$$;
