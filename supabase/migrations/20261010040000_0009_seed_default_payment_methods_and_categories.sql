-- ==============================================================================
-- Migration: 0009_seed_default_payment_methods_and_categories.sql
-- Description: Adiciona criação automática de formas de pagamento padrão
--              (Caixa da Casa, Pix, Dinheiro) e categorias essenciais ao criar
--              uma casa, além de backfill resiliente para casas existentes.
-- ==============================================================================

-- 1. DEFAULTS E POLÍTICAS RLS RESILIENTES
alter table public.payment_methods alter column created_by set default auth.uid();
alter table public.categories alter column created_by set default auth.uid();

-- Garante que o criador da casa consiga inserir formas de pagamento e categorias
drop policy if exists "payment_methods_insert_member" on public.payment_methods;
create policy "payment_methods_insert_member" on public.payment_methods for insert
  with check (
    public.is_house_member(house_id) or
    exists (select 1 from public.houses h where h.id = house_id and h.created_by = auth.uid())
  );

drop policy if exists "categories_insert_member" on public.categories;
create policy "categories_insert_member" on public.categories for insert
  with check (
    public.is_house_member(house_id) or
    exists (select 1 from public.houses h where h.id = house_id and h.created_by = auth.uid())
  );

-- 2. ATUALIZAÇÃO DA RPC create_house_with_owner
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

  -- 4. Cria formas de pagamento padrão da casa
  insert into public.payment_methods (
    house_id, name, type, is_active, created_by
  ) values 
    (v_house_id, 'Caixa da Casa', 'account', true, auth.uid()),
    (v_house_id, 'Pix', 'pix', true, auth.uid()),
    (v_house_id, 'Dinheiro em Espécie', 'cash', true, auth.uid());

  -- 5. Cria categorias essenciais da casa
  insert into public.categories (
    house_id, name, icon, color_hex, is_active, created_by
  ) values
    (v_house_id, 'Supermercado', 'shopping_cart_outlined', '#10B981', true, auth.uid()),
    (v_house_id, 'Moradia & Aluguel', 'home_outlined', '#3B82F6', true, auth.uid()),
    (v_house_id, 'Contas (Luz, Água, Internet)', 'bolt_outlined', '#F59E0B', true, auth.uid()),
    (v_house_id, 'Transporte & Carro', 'directions_car_outlined', '#EC4899', true, auth.uid()),
    (v_house_id, 'Lazer & Restaurantes', 'restaurant_outlined', '#8B5CF6', true, auth.uid()),
    (v_house_id, 'Saúde & Farmácia', 'local_hospital_outlined', '#EF4444', true, auth.uid());

  return to_jsonb(v_house);
end;
$$;

-- 3. BACKFILL PARA CASAS JÁ EXISTENTES SEM FORMAS DE PAGAMENTO OU CATEGORIAS
-- 3.1 Formas de pagamento
insert into public.payment_methods (house_id, name, type, is_active, created_by)
select h.id, pm.name, pm.type, true, h.created_by
from public.houses h
cross join (values 
  ('Caixa da Casa', 'account'),
  ('Pix', 'pix'),
  ('Dinheiro em Espécie', 'cash')
) as pm(name, type)
where not exists (
  select 1 from public.payment_methods existing 
  where existing.house_id = h.id
);

-- 3.2 Categorias essenciais
insert into public.categories (house_id, name, icon, color_hex, is_active, created_by)
select h.id, cat.name, cat.icon, cat.color_hex, true, h.created_by
from public.houses h
cross join (values 
  ('Supermercado', 'shopping_cart_outlined', '#10B981'),
  ('Moradia & Aluguel', 'home_outlined', '#3B82F6'),
  ('Contas (Luz, Água, Internet)', 'bolt_outlined', '#F59E0B'),
  ('Transporte & Carro', 'directions_car_outlined', '#EC4899'),
  ('Lazer & Restaurantes', 'restaurant_outlined', '#8B5CF6'),
  ('Saúde & Farmácia', 'local_hospital_outlined', '#EF4444')
) as cat(name, icon, color_hex)
where not exists (
  select 1 from public.categories existing 
  where existing.house_id = h.id
);

-- 4. RECARREGA O SCHEMA CACHE DO POSTGREST IMEDIATAMENTE
NOTIFY pgrst, 'reload schema';
