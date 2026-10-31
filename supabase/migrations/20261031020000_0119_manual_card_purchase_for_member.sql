-- ==============================================================================
-- 0119: Compra à vista no cartão que um morador deve
-- Descrição:
--   A Nova despesa já lançava a compra parcelada de um morador como empréstimo
--   (0117), mas a compra à vista no cartão só entrava como despesa da Casa.
--   Agora ela também vira empréstimo: é a compra lançada à mão em 1 vez, pelo
--   mesmo `create_installment_purchase`. O plano de 1 parcela é o que faz a
--   fatura reconhecer a linha e não lançá-la de novo.
--   Só a compra lançada à mão pode ter 1 parcela: a importação continua
--   criando planos só para as linhas parceladas da fatura (2 a 99).
-- ==============================================================================

alter table public.installment_plans
  drop constraint if exists installment_plans_installments_total_check;

alter table public.installment_plans
  add constraint installment_plans_installments_total_check
    check (
      installments_total between 2 and 99
      or (installments_total = 1 and origin = 'manual')
    );
