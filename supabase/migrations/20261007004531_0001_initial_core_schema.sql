-- ==============================================================================
-- Migration: 0001_initial_core_schema.sql
-- Module: Núcleo (Profiles, Houses, House Members, Invites, Payment Methods,
--                 Categories, Attachments, Notifications, Audit Log, AI Usage)
-- Description: Criação da estrutura base e políticas RLS para o Omni Lar.
-- ==============================================================================

-- 1. EXTENSÕES
create extension if not exists "pgcrypto";

-- 2. FUNÇÃO UTILITÁRIA PARA UPDATED_AT
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- 3. TABELA PROFILES (Ligada a auth.users)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  avatar_url text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- 4. TABELA HOUSES
create table if not exists public.houses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  cycle_start_day smallint not null default 5 check (cycle_start_day between 1 and 31),
  timezone text not null default 'America/Sao_Paulo',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.houses enable row level security;

create trigger trg_houses_updated_at
  before update on public.houses
  for each row execute function public.touch_updated_at();

-- 5. TABELA HOUSE_MEMBERS
create table if not exists public.house_members (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  unique(house_id, user_id)
);

create index if index_house_members_house on public.house_members (house_id);
create index if index_house_members_user on public.house_members (user_id);

alter table public.house_members enable row level security;

-- 6. FUNÇÕES DE SEGURANÇA (SECURITY DEFINER)
create or replace function public.is_house_member(h uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.house_members
    where house_id = h and user_id = auth.uid() and left_at is null
  );
$$;

create or replace function public.is_house_admin(h uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.house_members
    where house_id = h and user_id = auth.uid() and role in ('owner', 'admin') and left_at is null
  );
$$;

-- 7. TABELA HOUSE_INVITES
create table if not exists public.house_invites (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  code text not null unique,
  role text not null default 'member' check (role in ('admin', 'member')),
  created_by uuid not null references auth.users(id),
  expires_at timestamptz not null,
  used_at timestamptz,
  used_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if index_house_invites_house on public.house_invites (house_id);
create index if index_house_invites_code on public.house_invites (code);

alter table public.house_invites enable row level security;

-- 8. TABELA PAYMENT_METHODS
create table if not exists public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  owner_id uuid references auth.users(id) on delete set null,
  name text not null,
  type text not null check (type in ('card', 'vr', 'va', 'pix', 'account', 'cash', 'other')),
  closing_day smallint check (closing_day between 1 and 31),
  due_day smallint check (due_day between 1 and 31),
  color_hex text,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if index_payment_methods_house on public.payment_methods (house_id);

alter table public.payment_methods enable row level security;

create trigger trg_payment_methods_updated_at
  before update on public.payment_methods
  for each row execute function public.touch_updated_at();

-- 9. TABELA CATEGORIES
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  name text not null,
  icon text,
  color_hex text,
  owner_member_id uuid references auth.users(id) on delete set null,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if index_categories_house on public.categories (house_id);

alter table public.categories enable row level security;

create trigger trg_categories_updated_at
  before update on public.categories
  for each row execute function public.touch_updated_at();

-- 10. TABELA ATTACHMENTS
create table if not exists public.attachments (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  owner_type text not null,
  owner_id uuid not null,
  file_url text not null,
  file_hash text,
  file_size_bytes bigint,
  mime_type text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if index_attachments_house on public.attachments (house_id);
create index if index_attachments_owner on public.attachments (owner_type, owner_id);

alter table public.attachments enable row level security;

-- 11. TABELA NOTIFICATIONS
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  house_id uuid references public.houses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  payload jsonb not null default '{}'::jsonb,
  deeplink text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if index_notifications_user on public.notifications (user_id, read_at);

alter table public.notifications enable row level security;

-- 12. TABELA AUDIT_LOG
create table if not exists public.audit_log (
  id uuid primary key default gen_random_uuid(),
  house_id uuid references public.houses(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  entity_type text not null,
  entity_id uuid not null,
  action text not null,
  diff jsonb,
  created_at timestamptz not null default now()
);

create index if index_audit_log_house on public.audit_log (house_id, created_at);

alter table public.audit_log enable row level security;

-- 13. TABELA AI_USAGE
create table if not exists public.ai_usage (
  id uuid primary key default gen_random_uuid(),
  house_id uuid references public.houses(id) on delete set null,
  user_id uuid not null references auth.users(id) on delete cascade,
  feature text not null check (feature in ('capture', 'import', 'assistant')),
  model text not null,
  tokens_in integer not null default 0,
  tokens_out integer not null default 0,
  status text not null default 'success',
  created_at timestamptz not null default now()
);

create index if index_ai_usage_house_user on public.ai_usage (house_id, user_id, created_at);

alter table public.ai_usage enable row level security;

-- ==============================================================================
-- RLS POLICIES
-- ==============================================================================

-- Profiles:
create policy "profiles_select_own_or_house_members" on public.profiles for select
  using (
    id = auth.uid() or
    exists (
      select 1 from public.house_members hm1
      join public.house_members hm2 on hm1.house_id = hm2.house_id
      where hm1.user_id = auth.uid() and hm2.user_id = public.profiles.id
        and hm1.left_at is null and hm2.left_at is null
    )
  );

create policy "profiles_update_own" on public.profiles for update
  using (id = auth.uid())
  with check (id = auth.uid());

create policy "profiles_insert_own" on public.profiles for insert
  with check (id = auth.uid());

-- Houses:
create policy "houses_select_member" on public.houses for select
  using (public.is_house_member(id));

create policy "houses_insert_authenticated" on public.houses for insert
  with check (auth.role() = 'authenticated');

create policy "houses_update_admin" on public.houses for update
  using (public.is_house_admin(id))
  with check (public.is_house_admin(id));

-- House Members:
create policy "house_members_select_member" on public.house_members for select
  using (public.is_house_member(house_id));

create policy "house_members_insert_owner_or_admin" on public.house_members for insert
  with check (
    -- Permite inserção se for o criador inicial (primeiro membro / owner) ou admin da casa
    not exists (select 1 from public.house_members where house_id = public.house_members.house_id)
    or public.is_house_admin(house_id)
  );

create policy "house_members_update_admin" on public.house_members for update
  using (public.is_house_admin(house_id))
  with check (public.is_house_admin(house_id));

create policy "house_members_delete_admin_or_self" on public.house_members for delete
  using (public.is_house_admin(house_id) or user_id = auth.uid());

-- House Invites:
create policy "house_invites_select_admin" on public.house_invites for select
  using (public.is_house_admin(house_id));

create policy "house_invites_insert_admin" on public.house_invites for insert
  with check (public.is_house_admin(house_id) and created_by = auth.uid());

create policy "house_invites_update_admin" on public.house_invites for update
  using (public.is_house_admin(house_id));

-- Payment Methods:
create policy "payment_methods_select_member" on public.payment_methods for select
  using (public.is_house_member(house_id));

create policy "payment_methods_insert_member" on public.payment_methods for insert
  with check (public.is_house_member(house_id));

create policy "payment_methods_update_owner_or_admin" on public.payment_methods for update
  using (public.is_house_admin(house_id) or owner_id = auth.uid() or created_by = auth.uid())
  with check (public.is_house_admin(house_id) or owner_id = auth.uid() or created_by = auth.uid());

create policy "payment_methods_delete_owner_or_admin" on public.payment_methods for delete
  using (public.is_house_admin(house_id) or owner_id = auth.uid() or created_by = auth.uid());

-- Categories:
create policy "categories_select_member" on public.categories for select
  using (public.is_house_member(house_id));

create policy "categories_insert_member" on public.categories for insert
  with check (public.is_house_member(house_id));

create policy "categories_update_admin_or_owner" on public.categories for update
  using (public.is_house_admin(house_id) or created_by = auth.uid())
  with check (public.is_house_admin(house_id) or created_by = auth.uid());

create policy "categories_delete_admin" on public.categories for delete
  using (public.is_house_admin(house_id));

-- Attachments:
create policy "attachments_select_member" on public.attachments for select
  using (public.is_house_member(house_id));

create policy "attachments_insert_member" on public.attachments for insert
  with check (public.is_house_member(house_id) and created_by = auth.uid());

-- Notifications:
create policy "notifications_select_own" on public.notifications for select
  using (user_id = auth.uid());

create policy "notifications_update_own" on public.notifications for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Audit Log (Somente leitura para membros da casa):
create policy "audit_log_select_member" on public.audit_log for select
  using (house_id is not null and public.is_house_member(house_id));

-- AI Usage (Somente leitura própria ou admin):
create policy "ai_usage_select_own_or_admin" on public.ai_usage for select
  using (user_id = auth.uid() or (house_id is not null and public.is_house_admin(house_id)));

create policy "ai_usage_insert_service_or_own" on public.ai_usage for insert
  with check (user_id = auth.uid());

-- ==============================================================================
-- TRIGGER PARA NOVO USUÁRIO (CRIAR PROFILE AUTOMATICAMENTE)
-- ==============================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, avatar_url, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email, 'Usuário'),
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'phone'
  );
  return new;
end;
$$;

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
