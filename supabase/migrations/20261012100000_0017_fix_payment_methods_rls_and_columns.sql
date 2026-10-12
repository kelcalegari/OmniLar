-- ==============================================================================
-- 0017: Fix Payment Methods RLS, Owner Columns Synchronization and Duplicate Cleanup
-- Description:
--   1. Permite que membros da casa atualizem (soft-delete ou edição) e excluam formas de pagamento da sua casa.
--   2. Garante existência e sincronização bidirecional entre owner_id e owner_member_id via trigger.
--   3. Desativa duplicatas órfãs padrão da casa para limpar a listagem.
-- ==============================================================================

-- 1. POLÍTICAS RLS PARA UPDATE E DELETE EM PAYMENT_METHODS
drop policy if exists "payment_methods_update_owner_or_admin" on public.payment_methods;
drop policy if exists "payment_methods_update_member" on public.payment_methods;
create policy "payment_methods_update_member" on public.payment_methods for update
  using (public.is_house_member(house_id))
  with check (public.is_house_member(house_id));

drop policy if exists "payment_methods_delete_owner_or_admin" on public.payment_methods;
drop policy if exists "payment_methods_delete_member" on public.payment_methods;
create policy "payment_methods_delete_member" on public.payment_methods for delete
  using (public.is_house_member(house_id));

-- 2. GARANTIA DE COLUNA E SINCRONIZAÇÃO BIDIRECIONAL OWNER_ID <-> OWNER_MEMBER_ID
do $$
begin
  if not exists (
    select 1 from information_schema.columns 
    where table_schema = 'public' and table_name = 'payment_methods' and column_name = 'owner_member_id'
  ) then
    alter table public.payment_methods add column owner_member_id uuid references auth.users(id) on delete set null;
  end if;

  -- Sincroniza dados existentes em ambas as direções
  update public.payment_methods set owner_member_id = owner_id where owner_member_id is null and owner_id is not null;
  update public.payment_methods set owner_id = owner_member_id where owner_id is null and owner_member_id is not null;
end $$;

create or replace function public.sync_payment_methods_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.owner_id is not null and new.owner_member_id is null then
    new.owner_member_id := new.owner_id;
  elsif new.owner_member_id is not null and new.owner_id is null then
    new.owner_id := new.owner_member_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_payment_methods_owner on public.payment_methods;
create trigger trg_sync_payment_methods_owner
  before insert or update on public.payment_methods
  for each row execute function public.sync_payment_methods_owner();

-- 3. LIMPEZA DE FORMAS DE PAGAMENTO PADRÃO DUPLICADAS
with duplicates as (
  select id, row_number() over (partition by house_id, lower(trim(name)) order by created_at asc) as rn
  from public.payment_methods
  where owner_id is null and owner_member_id is null
)
update public.payment_methods
set is_active = false
where id in (select id from duplicates where rn > 1);

-- 4. RECARREGA SCHEMA CACHE DO POSTGREST
NOTIFY pgrst, 'reload schema';
