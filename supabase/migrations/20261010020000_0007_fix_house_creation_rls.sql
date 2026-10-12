-- ==============================================================================
-- Migration: 0007_fix_house_creation_rls.sql
-- Description: Corrige as políticas RLS para criação de casa e adiciona RPC atômica
-- ==============================================================================

-- 1. Permitir que o criador da casa veja a casa que acabou de criar (evita erro no RETURNING *)
drop policy if exists "houses_select_member" on public.houses;
create policy "houses_select_member" on public.houses for select
  using (public.is_house_member(id) or created_by = auth.uid());

-- 2. Garantir inserção segura para qualquer usuário autenticado
drop policy if exists "houses_insert_authenticated" on public.houses;
create policy "houses_insert_authenticated" on public.houses for insert
  with check (auth.role() = 'authenticated' and (created_by = auth.uid() or created_by is null));

-- 3. Permitir que o usuário consulte seus próprios registros de membro
drop policy if exists "house_members_select_member" on public.house_members;
create policy "house_members_select_member" on public.house_members for select
  using (public.is_house_member(house_id) or user_id = auth.uid());

-- 4. Permitir que o criador da casa se insira como primeiro membro (owner)
drop policy if exists "house_members_insert_owner_or_admin" on public.house_members;
create policy "house_members_insert_owner_or_admin" on public.house_members for insert
  with check (
    user_id = auth.uid() or
    public.is_house_admin(house_id) or
    exists (select 1 from public.houses h where h.id = house_id and h.created_by = auth.uid())
  );

-- 5. Adiciona coluna de e-mail na tabela profiles caso não exista
alter table public.profiles add column if not exists email text;

-- 5.1 Adiciona coluna default_split_percent na tabela house_members caso não exista
alter table public.house_members add column if not exists default_split_percent numeric(5,2) default 50.0
  check (default_split_percent is null or (default_split_percent >= 0 and default_split_percent <= 100));

-- 6. Atualiza o trigger de cadastro automático de perfil
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, avatar_url, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email, 'Usuário'),
    new.email,
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'phone'
  )
  on conflict (id) do update set
    full_name = coalesce(excluded.full_name, public.profiles.full_name),
    email = coalesce(excluded.email, public.profiles.email);
  return new;
end;
$$;

-- 7. RPC atômica e segura para criação de casa com membro owner
create or replace function public.create_house_with_owner(
  p_name text,
  p_cycle_start_day integer default 5,
  p_timezone text default 'America/Sao_Paulo'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_house_id uuid;
  v_house public.houses%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;

  -- 1. Insere a casa
  insert into public.houses (
    name, cycle_start_day, timezone, created_by
  ) values (
    trim(p_name), p_cycle_start_day, p_timezone, auth.uid()
  ) returning * into v_house;

  v_house_id := v_house.id;

  -- 2. Insere o criador como membro owner
  insert into public.house_members (
    house_id, user_id, role, default_split_percent
  ) values (
    v_house_id, auth.uid(), 'owner', 50.0
  );

  -- 3. Cria lista de compras padrão
  insert into public.shopping_lists (
    house_id, name, icon, is_default, created_by
  ) values (
    v_house_id, 'Supermercado & Feira', 'shopping_cart_outlined', true, auth.uid()
  );

  return to_jsonb(v_house);
end;
$$;

-- 8. Recarrega o schema cache do PostgREST imediatamente
NOTIFY pgrst, 'reload schema';
