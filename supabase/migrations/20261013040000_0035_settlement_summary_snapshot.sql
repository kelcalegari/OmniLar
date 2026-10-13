-- ==============================================================================
-- 0035: Retrato do fechamento do ciclo
-- Descrição:
--   Um ciclo fechado só guardava os totais e as transferências entre moradores:
--   ao reabrir a tela, saldos por morador, transferências com o Caixa e a
--   memória de cálculo vinham vazios. O app passa a gravar, logo depois de
--   fechar, o retrato do que foi mostrado a quem fechou.
--   O retrato é só para exibição: nenhuma regra do banco lê este campo.
-- ==============================================================================

alter table public.settlements
  add column if not exists summary_snapshot jsonb;

-- Grava o retrato de um ciclo já fechado. Só administradores da casa.
create or replace function public.save_settlement_snapshot(
  p_house_id uuid,
  p_cycle_start_date date,
  p_snapshot jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores da casa podem gravar o fechamento.';
  end if;

  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' then
    raise exception 'Retrato do fechamento inválido.';
  end if;

  if pg_column_size(p_snapshot) > 2000000 then
    raise exception 'Retrato do fechamento grande demais.';
  end if;

  update public.settlements
  set summary_snapshot = p_snapshot
  where house_id = p_house_id
    and cycle_start_date = p_cycle_start_date
    and status in ('confirmed', 'completed');

  if not found then
    raise exception 'Não há fechamento confirmado para este ciclo.';
  end if;
end;
$$;

revoke execute on function public.save_settlement_snapshot(uuid, date, jsonb) from public, anon;
grant execute on function public.save_settlement_snapshot(uuid, date, jsonb) to authenticated;
