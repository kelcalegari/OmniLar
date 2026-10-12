-- ==============================================================================
-- Migration: 0008_fix_schema_cache_and_split_percent.sql
-- Description: Adiciona colunas ausentes, constraints relacionais de perfil,
--              defaults para created_by e recarrega o cache de schema do PostgREST.
-- ==============================================================================

-- 1. COLUNA default_split_percent EM house_members
alter table public.house_members 
  add column if not exists default_split_percent numeric(5,2) default 50.0 
  check (default_split_percent is null or (default_split_percent >= 0 and default_split_percent <= 100));

-- 2. COLUNA email EM profiles (caso não tenha sido adicionada)
alter table public.profiles add column if not exists email text;

-- 3. RELACIONAMENTOS COM PROFILES (Para permitir embeds profile:profiles(*))
do $$
begin
  if not exists (select 1 from information_schema.table_constraints where constraint_name = 'fk_house_members_profile') then
    alter table public.house_members
      add constraint fk_house_members_profile foreign key (user_id) references public.profiles(id) on delete cascade;
  end if;

  if not exists (select 1 from information_schema.table_constraints where constraint_name = 'fk_contributions_profile') then
    alter table public.contributions
      add constraint fk_contributions_profile foreign key (member_id) references public.profiles(id) on delete cascade;
  end if;
end $$;

-- 4. COLUNAS COMPLEMENTARES DE DOMÍNIO
-- 4.1 Coluna date em house_expenses e contributions
alter table public.house_expenses add column if not exists date timestamptz default now();
alter table public.contributions add column if not exists date date default current_date;

-- 4.2 Coluna split_type em house_expense_items
alter table public.house_expense_items add column if not exists split_type text 
  check (split_type is null or split_type in ('percentage', 'fixed', 'category_owner'));

-- 4.3 Colunas complementares em savings_transactions
alter table public.savings_transactions add column if not exists house_id uuid references public.houses(id) on delete cascade;
alter table public.savings_transactions add column if not exists notes text;

-- 4.4 Coluna owner_member_id em payment_methods
alter table public.payment_methods add column if not exists owner_member_id uuid references auth.users(id) on delete set null;
update public.payment_methods set owner_member_id = owner_id where owner_member_id is null and owner_id is not null;

-- 5. DEFAULTS PARA created_by E EXPIRAÇÃO DE CONVITES
alter table public.house_invites alter column created_by set default auth.uid();
alter table public.house_invites alter column expires_at set default (now() + interval '7 days');
alter table public.contributions alter column created_by set default auth.uid();
alter table public.house_expenses alter column created_by set default auth.uid();
alter table public.shopping_lists alter column created_by set default auth.uid();
alter table public.shopping_items alter column created_by set default auth.uid();
alter table public.tasks alter column created_by set default auth.uid();
alter table public.events alter column created_by set default auth.uid();
alter table public.p2p_loans alter column created_by set default auth.uid();

-- Permite que qualquer usuário autenticado valide um código de convite ao tentar entrar
drop policy if exists "house_invites_select_authenticated" on public.house_invites;
create policy "house_invites_select_authenticated" on public.house_invites for select
  using (auth.role() = 'authenticated');

-- 6. RPC ATÔMICA E SEGURA PARA CRIAÇÃO DE CASA COM MEMBRO OWNER
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

-- 7. RECARREGA O SCHEMA CACHE DO POSTGREST IMEDIATAMENTE (Limpa o erro PGRST204)
NOTIFY pgrst, 'reload schema';
