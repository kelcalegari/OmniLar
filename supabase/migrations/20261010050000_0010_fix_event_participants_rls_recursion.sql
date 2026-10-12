-- ==============================================================================
-- Migration: 0010_fix_event_participants_rls_recursion.sql
-- Description: Elimina definitivamente a recursão infinita (código 42P17) nas
--              políticas RLS entre events e event_participants adicionando
--              house_id e funções plpgsql com security definer.
-- ==============================================================================

-- 1. ADICIONAR house_id EM event_participants PARA DESACOPLAR A VERIFICAÇÃO DE MEMBRO
alter table public.event_participants 
  add column if not exists house_id uuid references public.houses(id) on delete cascade;

-- Preenche house_id para os registros já existentes a partir da tabela events
update public.event_participants ep
set house_id = e.house_id
from public.events e
where ep.event_id = e.id and ep.house_id is null;

-- Trigger para preencher automaticamente o house_id nas inserções se não vier preenchido
create or replace function public.set_event_participant_house_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.house_id is null then
    select house_id into new.house_id from public.events where id = new.event_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_event_participant_house_id on public.event_participants;
create trigger trg_set_event_participant_house_id
before insert on public.event_participants
for each row execute function public.set_event_participant_house_id();

-- 2. FUNÇÕES AUXILIARES DE SEGURANÇA EM PL/PGSQL (NUNCA INLINADAS PELO PLANNER)
create or replace function public.is_event_participant(p_event_id uuid, p_user_id uuid)
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_exists boolean;
begin
  select exists (
    select 1
    from public.event_participants
    where event_id = p_event_id
      and user_id = p_user_id
  ) into v_exists;
  return v_exists;
end;
$$;

create or replace function public.is_event_creator(p_event_id uuid, p_user_id uuid)
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_exists boolean;
begin
  select exists (
    select 1
    from public.events
    where id = p_event_id
      and created_by = p_user_id
  ) into v_exists;
  return v_exists;
end;
$$;

grant execute on function public.is_event_participant(uuid, uuid) to authenticated;
grant execute on function public.is_event_creator(uuid, uuid) to authenticated;

-- 3. POLÍTICAS RLS ATUALIZADAS
-- events: usa is_event_participant (PL/pgSQL security definer) para evitar recursão
drop policy if exists "events_select_visibility" on public.events;

create policy "events_select_visibility" on public.events for select
  using (
    public.is_house_member(house_id) and (
      visibility = 'house' or
      created_by = auth.uid() or
      (visibility = 'restricted' and public.is_event_participant(id, auth.uid()))
    )
  );

-- event_participants: valida diretamente por house_id ou por vínculo do usuário,
-- eliminando completamente qualquer subconsulta à tabela events!
drop policy if exists "event_participants_select_member" on public.event_participants;
drop policy if exists "event_participants_insert_member" on public.event_participants;
drop policy if exists "event_participants_update_self_or_creator" on public.event_participants;
drop policy if exists "event_participants_delete_creator_or_self" on public.event_participants;

create policy "event_participants_select_member" on public.event_participants for select
  using (
    user_id = auth.uid() or 
    (house_id is not null and public.is_house_member(house_id))
  );

create policy "event_participants_insert_member" on public.event_participants for insert
  with check (
    user_id = auth.uid() or 
    (house_id is not null and public.is_house_member(house_id))
  );

create policy "event_participants_update_self_or_creator" on public.event_participants for update
  using (
    user_id = auth.uid() or public.is_event_creator(event_id, auth.uid())
  )
  with check (
    user_id = auth.uid() or public.is_event_creator(event_id, auth.uid())
  );

create policy "event_participants_delete_creator_or_self" on public.event_participants for delete
  using (
    user_id = auth.uid() or public.is_event_creator(event_id, auth.uid())
  );

-- 4. RECARREGAR CACHE DO POSTGREST
notify pgrst, 'reload schema';
