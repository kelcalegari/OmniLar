-- ==============================================================================
-- 0072: Excluir categoria move também as despesas excluídas
-- Descrição:
--   A 0059 rodava com as permissões de quem chama, e o RLS esconde as despesas
--   com deleted_at. Elas ficavam de fora da troca e, ao excluir a categoria, a
--   chave estrangeira deixava category_id nulo nelas. Agora a função roda como
--   dona das tabelas (security definer) e move tudo; a checagem de dono ou
--   administrador (is_house_admin, que olha auth.uid()) continua igual.
-- ==============================================================================

create or replace function public.delete_category_moving_expenses(
  p_category_id uuid,
  p_target_category_id uuid
)
returns integer
language plpgsql
security definer
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
