-- ==============================================================================
-- 0043: Quem pode excluir um empréstimo
-- Descrição:
--   O devedor (e quem cadastrou) podia apagar o empréstimo inteiro, ou seja, a
--   própria dívida, sem o credor concordar. Decisão do dono:
--   1. só quem emprestou ou um administrador da casa exclui; no acordo com o
--      Caixa da Casa, só o administrador;
--   2. empréstimo que já teve pagamento não é excluído: o caminho é perdoar o
--      restante, que mantém o histórico.
-- ==============================================================================

drop policy if exists "p2p_loans_delete_parties" on public.p2p_loans;
create policy "p2p_loans_delete_parties" on public.p2p_loans for delete
  using (
    public.is_house_member(house_id)
    and (
      (lender_id = auth.uid() and not coalesce(lender_is_house, false))
      or public.is_house_admin(house_id)
    )
    and not exists (
      select 1 from public.p2p_installments i
      where i.loan_id = p2p_loans.id and i.paid_cents > 0
    )
  );
