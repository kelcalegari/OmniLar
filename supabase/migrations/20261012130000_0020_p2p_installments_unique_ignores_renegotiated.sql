-- ==============================================================================
-- 0020: Numeração de parcelas P2P ignora parcelas renegociadas
-- Descrição:
--   Ao renegociar (ou "Combinar parcelas" de um empréstimo sem prazo), as
--   parcelas antigas ficam com status 'renegotiated' e as novas reutilizam a
--   numeração. A constraint UNIQUE (loan_id, installment_number) impedia isso.
--   Passa a valer um índice único parcial que só considera parcelas vigentes.
-- ==============================================================================

alter table public.p2p_installments
  drop constraint if exists p2p_installments_loan_id_installment_number_key;

create unique index if not exists idx_p2p_installments_loan_number_active
  on public.p2p_installments (loan_id, installment_number)
  where status <> 'renegotiated';

-- Recarrega o cache de schema do PostgREST
notify pgrst, 'reload schema';
