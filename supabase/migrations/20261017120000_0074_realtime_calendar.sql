-- ==============================================================================
-- 0074: Tempo real para a agenda
-- Descrição:
--   A agenda é compartilhada pela casa, mas só atualizava ao recarregar. Agora
--   eventos e participantes entram no tempo real: quando alguém cria, edita,
--   exclui ou responde a um evento, os aparelhos abertos releem a agenda.
--   REPLICA IDENTITY FULL permite ao Realtime conferir o RLS e filtrar por
--   house_id também em UPDATE e DELETE (evento privado só chega a quem o vê).
-- ==============================================================================

alter table public.events replica identity full;
alter table public.event_participants replica identity full;

do $$
declare
  v_table text;
begin
  foreach v_table in array array['events', 'event_participants'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = v_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', v_table);
    end if;
  end loop;
end $$;
