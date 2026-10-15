-- ==============================================================================
-- 0059: Excluir uma categoria com lançamentos, movendo-os para outra
-- Descrição:
--   Até aqui a exclusão era recusada quando a categoria tinha lançamentos. Agora
--   quem exclui escolhe para qual categoria da mesma casa vão as despesas, os
--   sub-itens, os itens de compra, as linhas de importação e as regras
--   aprendidas da importação; depois a categoria sai. Tudo na mesma transação:
--   se a exclusão for recusada, nada é movido.
--   Trocar a categoria de uma despesa é permitido mesmo em ciclo fechado ou em
--   despesa já acertada (as travas olham valor, datas, pagador e rateio, não a
--   categoria), e o rateio de cada despesa não muda.
--   Roda com as permissões de quem chama (security invoker): só o dono da casa
--   ou um administrador exclui categoria (regra categories_delete_admin).
-- ==============================================================================

create or replace function public.delete_category_moving_expenses(
  p_category_id uuid,
  p_target_category_id uuid
)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_house_id uuid;
  v_moved integer;
  v_items integer;
  v_deleted integer;
begin
  if p_target_category_id is null or p_target_category_id = p_category_id then
    raise exception 'Escolha outra categoria para receber os lançamentos.';
  end if;

  select house_id into v_house_id from public.categories where id = p_category_id;
  if v_house_id is null then
    raise exception 'Categoria não encontrada.';
  end if;

  if not exists (
    select 1 from public.categories
    where id = p_target_category_id and house_id = v_house_id
  ) then
    raise exception 'A categoria que recebe os lançamentos precisa ser da mesma casa.';
  end if;

  if not public.is_house_admin(v_house_id) then
    raise exception 'Só o dono da casa ou um administrador pode excluir categorias.';
  end if;

  update public.house_expenses
     set category_id = p_target_category_id
   where house_id = v_house_id and category_id = p_category_id;
  get diagnostics v_moved = row_count;

  update public.house_expense_items i
     set category_id = p_target_category_id
    from public.house_expenses e
   where e.id = i.expense_id and e.house_id = v_house_id and i.category_id = p_category_id;
  get diagnostics v_items = row_count;

  update public.shopping_items
     set category_id = p_target_category_id
   where house_id = v_house_id and category_id = p_category_id;

  update public.import_lines
     set category_id = p_target_category_id
   where house_id = v_house_id and category_id = p_category_id;

  update public.import_rules
     set category_id = p_target_category_id
   where house_id = v_house_id and category_id = p_category_id;

  delete from public.categories where id = p_category_id and house_id = v_house_id;
  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then
    raise exception 'Não foi possível excluir a categoria.';
  end if;

  return v_moved + v_items;
end;
$$;

revoke execute on function public.delete_category_moving_expenses(uuid, uuid) from public, anon;
grant execute on function public.delete_category_moving_expenses(uuid, uuid) to authenticated;
