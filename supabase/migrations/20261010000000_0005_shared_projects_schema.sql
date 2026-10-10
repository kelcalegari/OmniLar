-- ==============================================================================
-- Migration: 0005_shared_projects_schema.sql
-- Module: Projetos e Eventos Compartilhados (Viagens, Compra de Imóveis, Reformas, Investimentos)
-- Description: Criação de tabelas de projetos compartilhados, participantes
--              e vínculo com despesas da casa (house_expenses).
-- ==============================================================================

-- 1. TABELA SHARED_PROJECTS
create table if not exists public.shared_projects (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  title text not null,
  description text,
  type text not null default 'generic' check (type in ('trip', 'asset_purchase', 'investment', 'event', 'generic')),
  target_budget_cents bigint check (target_budget_cents is null or target_budget_cents >= 0),
  status text not null default 'active' check (status in ('planning', 'active', 'settled', 'archived')),
  start_date date,
  end_date date,
  currency text not null default 'BRL',
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_shared_projects_house on public.shared_projects (house_id);
create index if not exists idx_shared_projects_status on public.shared_projects (house_id, status);

alter table public.shared_projects enable row level security;

create trigger trg_shared_projects_updated_at
  before update on public.shared_projects
  for each row execute function public.touch_updated_at();

-- 2. TABELA PROJECT_PARTICIPANTS
create table if not exists public.project_participants (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.shared_projects(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  external_name text,
  default_split_percent numeric(5,2) check (default_split_percent is null or (default_split_percent >= 0 and default_split_percent <= 100)),
  created_at timestamptz not null default now(),
  constraint check_participant_identity check (user_id is not null or external_name is not null)
);

create index if not exists idx_project_participants_project on public.project_participants (project_id);
create index if not exists idx_project_participants_user on public.project_participants (user_id);

alter table public.project_participants enable row level security;

-- 3. ADIÇÃO DO PROJECT_ID EM HOUSE_EXPENSES
do $$
begin
  if not exists (
    select 1 from information_schema.columns 
    where table_schema = 'public' and table_name = 'house_expenses' and column_name = 'project_id'
  ) then
    alter table public.house_expenses add column project_id uuid references public.shared_projects(id) on delete set null;
    create index if not exists idx_house_expenses_project on public.house_expenses (project_id);
  end if;
end $$;

-- ==============================================================================
-- RLS POLICIES
-- ==============================================================================

-- Shared Projects:
create policy "shared_projects_select_member" on public.shared_projects for select
  using (public.is_house_member(house_id) and deleted_at is null);

create policy "shared_projects_insert_member" on public.shared_projects for insert
  with check (public.is_house_member(house_id) and created_by = auth.uid());

create policy "shared_projects_update_member" on public.shared_projects for update
  using (public.is_house_member(house_id))
  with check (public.is_house_member(house_id));

create policy "shared_projects_delete_member" on public.shared_projects for delete
  using (public.is_house_member(house_id) and (created_by = auth.uid() or public.is_house_admin(house_id)));

-- Project Participants:
create policy "project_participants_select_member" on public.project_participants for select
  using (exists (
    select 1 from public.shared_projects sp
    where sp.id = project_id and public.is_house_member(sp.house_id)
  ));

create policy "project_participants_insert_member" on public.project_participants for insert
  with check (exists (
    select 1 from public.shared_projects sp
    where sp.id = project_id and public.is_house_member(sp.house_id)
  ));

create policy "project_participants_update_member" on public.project_participants for update
  using (exists (
    select 1 from public.shared_projects sp
    where sp.id = project_id and public.is_house_member(sp.house_id)
  ))
  with check (exists (
    select 1 from public.shared_projects sp
    where sp.id = project_id and public.is_house_member(sp.house_id)
  ));

create policy "project_participants_delete_member" on public.project_participants for delete
  using (exists (
    select 1 from public.shared_projects sp
    where sp.id = project_id and public.is_house_member(sp.house_id)
  ));
