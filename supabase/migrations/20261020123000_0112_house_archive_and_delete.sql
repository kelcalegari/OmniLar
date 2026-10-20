-- Migration: 0112_house_archive_and_delete
-- Permite arquivar, desarquivar, excluir e sair de uma casa, garantindo a regra de que o usuário sempre deve ter pelo menos 1 casa ativa.

-- 1. Coluna archived_at na tabela public.houses
alter table public.houses add column if not exists archived_at timestamptz;

-- 2. Atualizar guard_house_creation_account para considerar apenas casas ativas (não arquivadas)
create or replace function public.guard_house_creation_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text;
  v_limit integer;
  v_owned integer;
begin
  if auth.uid() is null then
    return new;
  end if;
  if not public.account_is_active(auth.uid()) then
    raise exception 'Sua conta ainda não foi liberada para criar uma casa.';
  end if;

  v_plan := public.account_plan(auth.uid());
  v_limit := public.plan_limit(v_plan, 'houses_owned');
  if v_limit is not null then
    select count(*) into v_owned
    from public.house_members m join public.houses h on h.id = m.house_id
    where m.user_id = auth.uid() and m.role = 'owner' and m.left_at is null and h.archived_at is null;
    if v_owned >= v_limit then
      raise exception 'No plano % você pode ter até % casa(s) ativa(s) como dono.', public.plan_label(v_plan), v_limit;
    end if;
  end if;
  return new;
end;
$$;

-- 3. RPC para arquivar casa (soft-delete, mantém histórico e ledger intactos)
create or replace function public.archive_house(p_house_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_active_count integer;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado.';
  end if;

  select role into v_role
  from public.house_members
  where house_id = p_house_id and user_id = auth.uid() and left_at is null;

  if v_role is null or v_role <> 'owner' then
    raise exception 'Apenas o proprietário da casa pode arquivá-la.';
  end if;

  -- Conferir se o usuário possui pelo menos outra casa ativa
  select count(*) into v_active_count
  from public.house_members m
  join public.houses h on h.id = m.house_id
  where m.user_id = auth.uid()
    and m.left_at is null
    and h.archived_at is null
    and h.id <> p_house_id;

  if v_active_count < 1 then
    raise exception 'Você precisa ter pelo menos uma casa ativa no Omni Lar.';
  end if;

  update public.houses
  set archived_at = now()
  where id = p_house_id;
end;
$$;

-- 4. RPC para desarquivar casa
create or replace function public.unarchive_house(p_house_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_plan text;
  v_limit integer;
  v_owned integer;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado.';
  end if;

  select role into v_role
  from public.house_members
  where house_id = p_house_id and user_id = auth.uid() and left_at is null;

  if v_role is null or v_role <> 'owner' then
    raise exception 'Apenas o proprietário pode desarquivar a casa.';
  end if;

  v_plan := public.account_plan(auth.uid());
  v_limit := public.plan_limit(v_plan, 'houses_owned');
  if v_limit is not null then
    select count(*) into v_owned
    from public.house_members m join public.houses h on h.id = m.house_id
    where m.user_id = auth.uid() and m.role = 'owner' and m.left_at is null and h.archived_at is null;
    if v_owned >= v_limit then
      raise exception 'No plano % você pode ter até % casa(s) ativa(s) como dono.', public.plan_label(v_plan), v_limit;
    end if;
  end if;

  update public.houses
  set archived_at = null
  where id = p_house_id;
end;
$$;

-- 5. RPC para excluir casa permanentemente (hard-delete em cascata)
create or replace function public.delete_house(p_house_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_active_count integer;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado.';
  end if;

  select role into v_role
  from public.house_members
  where house_id = p_house_id and user_id = auth.uid() and left_at is null;

  if v_role is null or v_role <> 'owner' then
    raise exception 'Apenas o proprietário pode excluir permanentemente a casa.';
  end if;

  -- Conferir se o usuário possui pelo menos outra casa ativa
  select count(*) into v_active_count
  from public.house_members m
  join public.houses h on h.id = m.house_id
  where m.user_id = auth.uid()
    and m.left_at is null
    and h.archived_at is null
    and h.id <> p_house_id;

  if v_active_count < 1 then
    raise exception 'Você precisa ter pelo menos uma casa ativa no Omni Lar.';
  end if;

  -- Desativa temporariamente a barreira de exclusão do ledger financeiro para esta exclusão completa da casa
  perform set_config('omnilar.deleting_house', 'on', true);
  delete from public.houses where id = p_house_id;
  perform set_config('omnilar.deleting_house', 'off', true);
end;
$$;

-- 6. RPC para sair de uma casa (moradores ou proprietários que transferem posse)
create or replace function public.leave_house(p_house_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_active_count integer;
  v_other_members integer;
  v_heir uuid;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado.';
  end if;

  select role into v_role
  from public.house_members
  where house_id = p_house_id and user_id = auth.uid() and left_at is null;

  if v_role is null then
    raise exception 'Você não faz parte desta casa ou já saiu.';
  end if;

  -- Conferir se o usuário possui pelo menos outra casa ativa
  select count(*) into v_active_count
  from public.house_members m
  join public.houses h on h.id = m.house_id
  where m.user_id = auth.uid()
    and m.left_at is null
    and h.archived_at is null
    and h.id <> p_house_id;

  if v_active_count < 1 then
    raise exception 'Você precisa ter pelo menos uma casa ativa no Omni Lar.';
  end if;

  if v_role = 'owner' then
    select count(*) into v_other_members
    from public.house_members
    where house_id = p_house_id and user_id <> auth.uid() and left_at is null;

    if v_other_members > 0 then
      v_heir := public.account_deletion_heir(p_house_id, auth.uid());
      if v_heir is not null then
        update public.house_members set role = 'owner' where house_id = p_house_id and user_id = v_heir;
        update public.houses set created_by = v_heir where id = p_house_id;
      end if;
    else
      raise exception 'Como único morador e proprietário, arquive ou exclua a casa em vez de sair.';
    end if;
  end if;

  update public.house_members
  set left_at = now()
  where house_id = p_house_id and user_id = auth.uid() and left_at is null;
end;
$$;

-- 7. Permissões
grant execute on function public.archive_house(uuid) to authenticated, service_role;
grant execute on function public.unarchive_house(uuid) to authenticated, service_role;
grant execute on function public.delete_house(uuid) to authenticated, service_role;
grant execute on function public.leave_house(uuid) to authenticated, service_role;
