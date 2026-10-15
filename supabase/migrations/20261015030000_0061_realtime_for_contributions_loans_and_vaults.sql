-- ==============================================================================
-- 0061: Tempo real para aportes, empréstimos e caixinhas
-- Descrição:
--   Depois de despesas e moradores (0050), entram no tempo real o que mexe no
--   Fôlego e no fechamento: aportes, empréstimos (e as parcelas deles) e
--   caixinhas. Quando alguém registra um aporte, paga uma parcela ou deposita
--   numa caixinha, os aparelhos abertos recarregam sozinhos.
--   REPLICA IDENTITY FULL permite ao Realtime conferir o RLS e filtrar por
--   house_id também em UPDATE e DELETE. As parcelas não têm house_id: o app
--   assina sem filtro e o RLS entrega só as da casa de quem está vendo.
-- ==============================================================================

alter table public.contributions replica identity full;
alter table public.p2p_loans replica identity full;
alter table public.p2p_installments replica identity full;
alter table public.savings_vaults replica identity full;

do $$
declare
  v_table text;
begin
  foreach v_table in array array['contributions', 'p2p_loans', 'p2p_installments', 'savings_vaults'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = v_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', v_table);
    end if;
  end loop;
end $$;
