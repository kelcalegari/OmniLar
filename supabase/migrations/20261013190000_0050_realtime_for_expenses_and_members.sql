-- ==============================================================================
-- 0050: Tempo real para despesas e moradores da casa
-- Descrição:
--   Só tarefas e itens de compra avisavam os outros aparelhos (0015). Agora
--   despesas e moradores também: quando alguém lança uma despesa ou entra na
--   casa, os aparelhos abertos recarregam o ciclo sozinhos.
--   REPLICA IDENTITY FULL permite ao Realtime conferir o RLS e filtrar por
--   house_id também em UPDATE e DELETE.
-- ==============================================================================

alter table public.house_expenses replica identity full;
alter table public.house_members replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'house_expenses'
  ) then
    alter publication supabase_realtime add table public.house_expenses;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'house_members'
  ) then
    alter publication supabase_realtime add table public.house_members;
  end if;
end $$;
