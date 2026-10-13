-- ==============================================================================
-- 0041: Unifica categorias e formas de pagamento duplicadas
-- Descrição:
--   O app criava os padrões quando a lista vinha vazia, e duas leituras ao
--   mesmo tempo criaram tudo em dobro. Casas novas já recebem os padrões pela
--   RPC de criação da casa, e o app deixou de criá-los.
--   Para cada nome repetido na mesma casa fica uma cópia (a ativa; entre
--   iguais, a mais antiga). O que apontava para as outras é repontado para
--   ela, e as outras são apagadas. Nenhuma despesa perde categoria ou forma
--   de pagamento.
-- ==============================================================================

do $$
declare
  r record;
  c record;
begin
  for r in
    select id, keep_id from (
      select id,
             first_value(id) over (
               partition by house_id, lower(name)
               order by is_active desc, created_at, id
             ) as keep_id
      from public.categories
    ) x
    where id <> keep_id
  loop
    for c in
      select col.table_name, col.column_name
      from information_schema.columns col
      join information_schema.tables t
        on t.table_schema = col.table_schema
       and t.table_name = col.table_name
       and t.table_type = 'BASE TABLE'
      where col.table_schema = 'public'
        and col.column_name = 'category_id'
        and col.data_type = 'uuid'
    loop
      execute format('update public.%I set %I = $1 where %I = $2', c.table_name, c.column_name, c.column_name)
        using r.keep_id, r.id;
    end loop;
    delete from public.categories where id = r.id;
  end loop;

  for r in
    select id, keep_id from (
      select id,
             first_value(id) over (
               partition by house_id, lower(name)
               order by is_active desc, created_at, id
             ) as keep_id
      from public.payment_methods
    ) x
    where id <> keep_id
  loop
    for c in
      select col.table_name, col.column_name
      from information_schema.columns col
      join information_schema.tables t
        on t.table_schema = col.table_schema
       and t.table_name = col.table_name
       and t.table_type = 'BASE TABLE'
      where col.table_schema = 'public'
        and col.column_name = 'payment_method_id'
        and col.data_type = 'uuid'
    loop
      execute format('update public.%I set %I = $1 where %I = $2', c.table_name, c.column_name, c.column_name)
        using r.keep_id, r.id;
    end loop;
    delete from public.payment_methods where id = r.id;
  end loop;
end;
$$;
