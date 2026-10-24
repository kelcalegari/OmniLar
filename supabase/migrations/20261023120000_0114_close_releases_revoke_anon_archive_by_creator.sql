-- 0114_close_releases_revoke_anon_archive_by_creator.sql
--
-- 1. Bucket 'releases': a 0109 deu FOR ALL para anon, então qualquer um com a
--    chave publicável podia trocar ou apagar o APK. O bucket é público, então
--    o download por /object/public/ continua sem política nenhuma; o upload
--    passa a ser só pela service_role (CI), que ignora o RLS.
-- 2. A 0108 voltou a dar execute de is_house_member e house_plan para anon, e
--    as RPCs da 0112 ficaram com o grant padrão de PUBLIC. Volta ao padrão da 0076.
-- 3. Arquivar e desarquivar a casa: só quem criou a casa (houses.created_by),
--    e o arquivamento vale para todos os moradores. Quando o dono sai, a
--    leave_house já passa created_by para o herdeiro.

-- 1. Releases
drop policy if exists "Releases access" on storage.objects;
drop policy if exists "Upload releases" on storage.objects;
drop policy if exists "Update releases" on storage.objects;
drop policy if exists "Public read releases" on storage.objects;
drop policy if exists "Public Access Releases" on storage.objects;

-- 2. Sem execute para anon
revoke execute on function public.is_house_member(uuid) from public, anon;
grant execute on function public.is_house_member(uuid) to authenticated, service_role;

revoke execute on function public.house_plan(uuid) from public, anon;
grant execute on function public.house_plan(uuid) to authenticated, service_role;

-- 3. Arquivar: só quem criou a casa
create or replace function public.archive_house(p_house_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_created_by uuid;
  v_active_count integer;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado.';
  end if;

  select created_by into v_created_by
  from public.houses
  where id = p_house_id;

  if not found then
    raise exception 'Casa não encontrada.';
  end if;

  if v_created_by is distinct from auth.uid() or not public.is_house_member(p_house_id) then
    raise exception 'Apenas quem criou a casa pode arquivá-la.';
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

create or replace function public.unarchive_house(p_house_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_created_by uuid;
  v_plan text;
  v_limit integer;
  v_owned integer;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado.';
  end if;

  select created_by into v_created_by
  from public.houses
  where id = p_house_id;

  if not found then
    raise exception 'Casa não encontrada.';
  end if;

  if v_created_by is distinct from auth.uid() or not public.is_house_member(p_house_id) then
    raise exception 'Apenas quem criou a casa pode desarquivá-la.';
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

revoke execute on function public.archive_house(uuid) from public, anon;
revoke execute on function public.unarchive_house(uuid) from public, anon;
revoke execute on function public.delete_house(uuid) from public, anon;
revoke execute on function public.leave_house(uuid) from public, anon;
grant execute on function public.archive_house(uuid) to authenticated, service_role;
grant execute on function public.unarchive_house(uuid) to authenticated, service_role;
grant execute on function public.delete_house(uuid) to authenticated, service_role;
grant execute on function public.leave_house(uuid) to authenticated, service_role;

notify pgrst, 'reload schema';
