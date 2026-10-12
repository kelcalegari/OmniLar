-- ==============================================================================
-- 0018: Allow House Members to View and Delete P2P Loans in their House
-- Description:
--   1. Permite que membros da mesma casa visualizem os empréstimos da casa
--      (necessário para o fechamento de ciclo / compensação e visão transparente).
--   2. Permite deleção de empréstimos pelos envolvidos (credor, devedor, criador ou admin).
--   3. Permite deleção em cascata de parcelas vinculadas.
-- ==============================================================================

-- 1. Leitura de Empréstimos: Todos os membros da casa podem ver
drop policy if exists "p2p_loans_select_parties" on public.p2p_loans;
create policy "p2p_loans_select_parties" on public.p2p_loans for select
  using (public.is_house_member(house_id));

-- 2. Leitura de Parcelas: Qualquer membro da casa correspondente
drop policy if exists "p2p_installments_select_parties" on public.p2p_installments;
create policy "p2p_installments_select_parties" on public.p2p_installments for select
  using (exists (
    select 1 from public.p2p_loans l
    where l.id = loan_id and public.is_house_member(l.house_id)
  ));

-- 3. Exclusão de Empréstimos: Envolvidos na operação ou Admin da Casa
drop policy if exists "p2p_loans_delete_parties" on public.p2p_loans;
create policy "p2p_loans_delete_parties" on public.p2p_loans for delete
  using (
    public.is_house_member(house_id) and (
      lender_id = auth.uid() or
      borrower_id = auth.uid() or
      created_by = auth.uid() or
      public.is_house_admin(house_id)
    )
  );

-- 4. Exclusão de Parcelas (Cascade)
drop policy if exists "p2p_installments_delete_parties" on public.p2p_installments;
create policy "p2p_installments_delete_parties" on public.p2p_installments for delete
  using (exists (
    select 1 from public.p2p_loans l
    where l.id = loan_id and public.is_house_member(l.house_id)
  ));
