-- ==============================================================================
-- MIGRATION: 0033_default_savings_vault_on_house_creation
-- DESCRIPTION: Casa nova já nasce com uma caixinha padrão ("Reserva da Casa"),
--              sem meta e com saldo zero.
-- ==============================================================================

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
    v_house_id, auth.uid(), 'owner', 100.0
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

  -- 6. Cria a caixinha padrão da casa (sem meta, saldo zero)
  insert into public.savings_vaults (
    house_id, name, icon, color_hex
  ) values (
    v_house_id, 'Reserva da Casa', 'savings', '#10B981'
  );

  return to_jsonb(v_house);
end;
$$;

-- Casas que já existiam e não têm nenhuma caixinha ativa recebem a padrão
insert into public.savings_vaults (house_id, name, icon, color_hex)
select h.id, 'Reserva da Casa', 'savings', '#10B981'
from public.houses h
where not exists (
  select 1 from public.savings_vaults v
  where v.house_id = h.id and v.deleted_at is null
);
