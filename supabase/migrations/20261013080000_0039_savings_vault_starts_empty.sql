-- ==============================================================================
-- 0039: Caixinha nasce com saldo zero
-- Descrição:
--   O app podia criar uma caixinha já com saldo, gravando o valor direto na
--   tabela, sem lançamento no histórico. Agora o saldo só muda por depósito,
--   resgate, fechamento do ciclo ou pagamento de acordo com o Lar, que sempre
--   deixam lançamento. O app passa a criar a caixinha zerada e a registrar o
--   saldo inicial como um depósito.
--   (A alteração do saldo por UPDATE já tinha sido retirada na 0027.)
-- ==============================================================================

revoke insert on public.savings_vaults from anon, authenticated;
grant insert (id, house_id, name, target_amount_cents, icon, color_hex)
  on public.savings_vaults to authenticated;
