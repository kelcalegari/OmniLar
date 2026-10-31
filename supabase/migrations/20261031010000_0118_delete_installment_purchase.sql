-- ==============================================================================
-- 0118: Excluir compra parcelada lançada à mão
-- Descrição:
--   Quem lançou a compra parcelada (0117) para o destino errado (ex.: da Casa
--   em vez de um morador) não tinha como desfazer: apagar parcela por parcela
--   deixava o plano para trás, e a próxima fatura casava a linha com ele.
--   `delete_installment_purchase` apaga, de uma vez, as parcelas previstas da
--   Casa, os empréstimos da compra e o plano. Só enquanto nenhuma fatura
--   importada usou a compra e nenhum empréstimo dela teve pagamento.
-- ==============================================================================

create or replace function public.delete_installment_purchase(p_plan_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_plan public.installment_plans%rowtype;
  v_expense_id uuid;
  v_loans uuid[];
  v_deleted integer;
begin
  select * into v_plan from public.installment_plans where id = p_plan_id for update;
  if not found or not public.is_house_member(v_plan.house_id) then
    raise exception 'Compra parcelada não encontrada.';
  end if;
  if v_plan.origin <> 'manual' then
    raise exception 'Esta compra parcelada veio de uma fatura importada. Para desfazer, desfaça a importação no histórico.';
  end if;
  if v_plan.created_by is distinct from auth.uid() and not public.is_house_admin(v_plan.house_id) then
    raise exception 'Só quem lançou a compra parcelada (ou um administrador) pode excluí-la.';
  end if;

  -- Uma fatura já usou a compra: apagar desmancharia a importação dela
  if exists (
    select 1 from public.house_expenses
    where installment_plan_id = p_plan_id and deleted_at is null and not is_forecast
  ) or exists (
    select 1
    from public.import_lines l
    join public.import_batches b on b.id = l.batch_id
    where l.installment_plan_id = p_plan_id and b.status = 'confirmed'
  ) then
    raise exception 'Uma fatura importada já confirmou parcela desta compra. Desfaça antes a importação dessa fatura.';
  end if;

  -- Parcelas previstas da Casa (a função recusa a que já entrou num fechamento)
  for v_expense_id in
    select id from public.house_expenses
    where installment_plan_id = p_plan_id and deleted_at is null
  loop
    perform public.delete_house_expense(v_expense_id, 'thisInstanceOnly');
  end loop;

  -- Empréstimos da compra (só dela: os de fatura juntam várias compras)
  select array_agg(id) into v_loans
  from public.p2p_loans
  where house_id = v_plan.house_id and installment_plan_ids = array[p_plan_id];

  if v_loans is not null then
    with deleted as (
      delete from public.p2p_loans where id = any(v_loans) returning id
    )
    select count(*) into v_deleted from deleted;

    -- A regra de acesso não dá erro: só deixa de apagar
    if v_deleted <> array_length(v_loans, 1) then
      raise exception 'Um empréstimo desta compra já teve pagamento ou não é seu. Só quem emprestou (ou um administrador) exclui, e apenas enquanto nada foi pago.';
    end if;
  end if;

  delete from public.installment_plans where id = p_plan_id;
end;
$$;

revoke execute on function public.delete_installment_purchase(uuid) from public, anon;
grant execute on function public.delete_installment_purchase(uuid) to authenticated;
