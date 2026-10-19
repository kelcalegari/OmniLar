-- 0105_contributions_edit_delete.sql
-- Edição e exclusão de aportes (contributions).
--
-- Por quê: a tabela (0002) só tinha políticas de SELECT e INSERT. Sem política
-- de UPDATE/DELETE, o RLS não dá erro: filtra tudo e altera 0 linhas, então o
-- app parecia salvar e nada mudava. Aqui entram as duas políticas, a trava de
-- ciclo fechado passa a cobrir UPDATE/DELETE (a 0030 só cobria INSERT) e o
-- aporte fica preso à casa e a quem registrou.
--
-- A tabela, os índices, o RLS ligado e o Realtime já existem (0002, 0061).

-- 1. Permissões de tabela para usuários autenticados (o RLS decide as linhas)
grant select, insert, update, delete on public.contributions to authenticated;

-- 2. O aporte não muda de casa nem de quem registrou
create or replace function public.contributions_keep_owner()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.house_id <> old.house_id or new.created_by <> old.created_by then
    raise exception 'O aporte não muda de casa nem de quem registrou.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_contributions_keep_owner on public.contributions;
create trigger trg_contributions_keep_owner
  before update on public.contributions
  for each row execute function public.contributions_keep_owner();

-- 3. Ciclo fechado: substitui a guarda da 0030 (só INSERT) por INSERT/UPDATE/DELETE
create or replace function public.guard_closed_cycle_contribution()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- As funções do banco (fechamento, reabertura) aplicam as próprias regras
  if current_user not in ('authenticated', 'anon') or pg_trigger_depth() > 1 then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    perform pg_advisory_xact_lock_shared(hashtextextended('house-ledger:' || old.house_id::text, 0));
    if public.house_date_is_closed(old.house_id, old.cycle_start_date) then
      raise exception 'O ciclo deste aporte já foi fechado. Reabra o ciclo no Fechamento para excluí-lo.';
    end if;
    return old;
  end if;

  -- Devolução de aporte (negativa) só nasce do fechamento do ciclo (0031)
  if new.amount_cents <= 0 then
    raise exception 'O valor do aporte deve ser maior que zero.';
  end if;

  -- Espera um fechamento em andamento nesta casa
  perform pg_advisory_xact_lock_shared(hashtextextended('house-ledger:' || new.house_id::text, 0));

  if tg_op = 'UPDATE' and public.house_date_is_closed(old.house_id, old.cycle_start_date) then
    raise exception 'O ciclo original deste aporte já foi fechado. Reabra o ciclo no Fechamento para alterá-lo.';
  end if;

  if public.house_date_is_closed(new.house_id, new.cycle_start_date) then
    raise exception 'O ciclo desta data já foi fechado. Reabra o ciclo no Fechamento para lançar ou mover um aporte para ele.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_contributions_guard_closed_cycle on public.contributions;
create trigger trg_contributions_guard_closed_cycle
  before insert or update or delete on public.contributions
  for each row execute function public.guard_closed_cycle_contribution();

-- 4. UPDATE: quem registrou, o morador do aporte ou um admin da casa
drop policy if exists "contributions_update_member" on public.contributions;
create policy "contributions_update_member" on public.contributions
  for update to authenticated
  using (
    public.is_house_member(house_id)
    and (
      created_by = (select auth.uid())
      or member_id = (select auth.uid())
      or public.is_house_admin(house_id)
    )
  )
  with check (
    public.is_house_member(house_id)
    and (
      created_by = (select auth.uid())
      or member_id = (select auth.uid())
      or public.is_house_admin(house_id)
    )
  );

-- 5. DELETE: mesmas pessoas
drop policy if exists "contributions_delete_member" on public.contributions;
create policy "contributions_delete_member" on public.contributions
  for delete to authenticated
  using (
    public.is_house_member(house_id)
    and (
      created_by = (select auth.uid())
      or member_id = (select auth.uid())
      or public.is_house_admin(house_id)
    )
  );

-- 6. Recarrega o cache do PostgREST
notify pgrst, 'reload schema';
