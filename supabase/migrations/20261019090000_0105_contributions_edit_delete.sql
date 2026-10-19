-- 0105_contributions_edit_delete.sql
-- Permite editar e excluir aportes em ciclos abertos, com auditoria e guarda de ciclo.

-- 1. Garante permissões na tabela
grant select, insert, update, delete on public.contributions to authenticated;

-- 2. Trigger para impedir alteração de casa ou do criador original
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

-- 3. Atualiza a função de guarda para tratar UPDATE e DELETE em ciclos fechados
create or replace function public.guard_closed_cycle_contribution()
returns trigger
language plpgsql
set search_path = public
as $$
begin
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

  perform pg_advisory_xact_lock_shared(hashtextextended('house-ledger:' || new.house_id::text, 0));

  if tg_op = 'UPDATE' then
    if public.house_date_is_closed(old.house_id, old.cycle_start_date) then
      raise exception 'O ciclo original deste aporte já foi fechado. Reabra o ciclo no Fechamento para alterá-lo.';
    end if;
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

-- 4. RLS: Permitir UPDATE para quem criou, morador dono do aporte ou admin, em ciclo aberto
drop policy if exists "contributions_update_member" on public.contributions;
create policy "contributions_update_member" on public.contributions
  for update using (
    public.is_house_member(house_id)
    and (created_by = (select auth.uid()) or member_id = (select auth.uid()) or public.is_house_admin(house_id))
    and not public.house_date_is_closed(house_id, cycle_start_date)
  )
  with check (
    public.is_house_member(house_id)
    and (created_by = (select auth.uid()) or member_id = (select auth.uid()) or public.is_house_admin(house_id))
    and not public.house_date_is_closed(house_id, cycle_start_date)
  );

-- 5. RLS: Permitir DELETE para quem criou, morador dono do aporte ou admin, em ciclo aberto
drop policy if exists "contributions_delete_member" on public.contributions;
create policy "contributions_delete_member" on public.contributions
  for delete using (
    public.is_house_member(house_id)
    and (created_by = (select auth.uid()) or member_id = (select auth.uid()) or public.is_house_admin(house_id))
    and not public.house_date_is_closed(house_id, cycle_start_date)
  );

notify pgrst, 'reload schema';
