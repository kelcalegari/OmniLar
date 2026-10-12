-- ==============================================================================
-- 0016: Fix House Expenses Soft Delete and Delete RLS Policies
-- Description:
--   Permite que qualquer membro da casa (ou o criador/admin) realize soft-delete
--   (atualizando deleted_at) ou exclusão em house_expenses.
-- ==============================================================================

-- 1. Garante que qualquer membro da casa possa atualizar/soft-deletar despesas da sua casa
drop policy if exists "house_expenses_update_member" on public.house_expenses;
create policy "house_expenses_update_member" on public.house_expenses for update
  using (public.is_house_member(house_id))
  with check (public.is_house_member(house_id));

-- 2. Permite deleção física caso executada por membros da casa
drop policy if exists "house_expenses_delete_member" on public.house_expenses;
create policy "house_expenses_delete_member" on public.house_expenses for delete
  using (public.is_house_member(house_id));

-- 3. Garante que split_rules também possam ser removidas em cascade ou manualmente
drop policy if exists "split_rules_delete_member" on public.split_rules;
create policy "split_rules_delete_member" on public.split_rules for delete
  using (exists (
    select 1 from public.house_expenses e
    where e.id = expense_id and public.is_house_member(e.house_id)
  ));

-- 4. Função RPC segura (security definer) para exclusão/soft-delete com suporte a recorrência
create or replace function public.delete_house_expense(
  p_expense_id uuid,
  p_scope text default 'thisInstanceOnly'
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_house_id uuid;
  v_series_id uuid;
  v_is_recurring boolean;
  v_due_date date;
  v_title text;
begin
  select house_id, recurring_series_id, is_recurring, due_date, title
  into v_house_id, v_series_id, v_is_recurring, v_due_date, v_title
  from public.house_expenses
  where id = p_expense_id;

  if v_house_id is null then
    return false;
  end if;

  -- Valida se o usuário pertence à casa
  if not public.is_house_member(v_house_id) then
    raise exception 'Acesso negado: você não é membro desta casa';
  end if;

  v_series_id := coalesce(v_series_id, case when v_is_recurring then p_expense_id else null end);

  if p_scope = 'allInstances' then
    update public.house_expenses
    set deleted_at = now(), is_active = false
    where house_id = v_house_id
      and (
        id = p_expense_id
        or (v_series_id is not null and (id = v_series_id or recurring_series_id = v_series_id))
        or (v_is_recurring and title = v_title)
      );

  elsif p_scope = 'thisAndFuture' then
    if v_series_id is not null then
      update public.house_expenses
      set is_active = false
      where id = v_series_id;
    end if;

    update public.house_expenses
    set deleted_at = now()
    where house_id = v_house_id
      and (
        id = p_expense_id
        or (
          (v_series_id is not null and (id = v_series_id or recurring_series_id = v_series_id))
          or (v_is_recurring and title = v_title)
        )
      )
      and (v_due_date is null or due_date >= v_due_date);

  else
    -- Apenas esta ocorrência pontual
    update public.house_expenses
    set deleted_at = now()
    where id = p_expense_id;
  end if;

  return true;
end;
$$;


