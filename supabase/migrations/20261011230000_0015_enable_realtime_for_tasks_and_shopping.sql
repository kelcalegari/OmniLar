-- ==============================================================================
-- 0015: Enable Supabase Realtime for Tasks and Shopping Items
-- ==============================================================================

-- Define REPLICA IDENTITY FULL para que o Realtime consiga validar RLS
-- e enviar os registros completos em operações de UPDATE/DELETE
alter table public.tasks replica identity full;
alter table public.shopping_items replica identity full;

-- Adiciona as tabelas na publicação supabase_realtime
-- Necessário para que client.from('tasks').stream() e shopping_items.stream() funcionem
do $$
begin
  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and tablename = 'tasks'
  ) then
    alter publication supabase_realtime add table public.tasks;
  end if;

  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and tablename = 'shopping_items'
  ) then
    alter publication supabase_realtime add table public.shopping_items;
  end if;
end $$;
