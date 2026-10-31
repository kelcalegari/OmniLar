-- ==============================================================================
-- 0122: Forma de pagamento que não consome aportes (saldo próprio, como o VA)
-- Descrição:
--   payment_methods.consumes_contributions: falso para formas com saldo próprio,
--   como o vale-alimentação. A despesa paga com ela continua sendo despesa da
--   casa (totais e relatórios do ciclo), mas o app a deixa fora do rateio, do
--   reembolso de "pago do bolso", do Caixa, do Fôlego e do planejador.
--   Padrão verdadeiro: nada muda até alguém desligar a opção nos Ajustes.
--   O cálculo é todo do app; nenhuma função do banco precisa mudar. Quem edita:
--   quem edita formas de pagamento (policy da 0017).
-- ==============================================================================

alter table public.payment_methods
  add column if not exists consumes_contributions boolean not null default true;

comment on column public.payment_methods.consumes_contributions is
  'Falso = saldo próprio (ex.: VA): a despesa conta na casa mas não consome aportes nem o Caixa.';
