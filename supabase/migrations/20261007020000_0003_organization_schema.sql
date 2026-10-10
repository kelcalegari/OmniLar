-- ==============================================================================
-- Migration: 0003_organization_schema.sql
-- Module: Organização (Listas de Compras, Tarefas, Rotinas, Agenda/Eventos)
-- Description: Estrutura de dados, integridade e políticas RLS para o dia a dia da casa.
-- ==============================================================================

-- 1. TABELA SHOPPING_LISTS (Listas de Compras)
create table if not exists public.shopping_lists (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  name text not null,
  icon text not null default 'shopping_cart_outlined',
  is_default boolean not null default false,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_shopping_lists_house on public.shopping_lists (house_id);

alter table public.shopping_lists enable row level security;

create trigger trg_shopping_lists_updated_at
  before update on public.shopping_lists
  for each row execute function public.touch_updated_at();

-- 2. TABELA SHOPPING_ITEMS (Itens da Lista de Compras)
create table if not exists public.shopping_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.shopping_lists(id) on delete cascade,
  house_id uuid not null references public.houses(id) on delete cascade,
  name text not null,
  quantity numeric(10, 2) not null default 1 check (quantity > 0),
  unit text not null default 'un',
  category_id uuid references public.categories(id) on delete set null,
  is_personal boolean not null default false,
  assigned_member_id uuid references auth.users(id) on delete set null, -- Quem pediu o item pessoal
  estimated_cents bigint check (estimated_cents >= 0),
  actual_cents bigint check (actual_cents >= 0),
  is_bought boolean not null default false,
  bought_by uuid references auth.users(id),
  bought_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_shopping_items_list on public.shopping_items (list_id, is_bought);
create index if not exists idx_shopping_items_house on public.shopping_items (house_id);

alter table public.shopping_items enable row level security;

create trigger trg_shopping_items_updated_at
  before update on public.shopping_items
  for each row execute function public.touch_updated_at();

-- 3. TABELA SHOPPING_TRIPS (Histórico de Compras Finalizadas)
create table if not exists public.shopping_trips (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  list_id uuid not null references public.shopping_lists(id) on delete cascade,
  total_spent_cents bigint not null check (total_spent_cents >= 0),
  expense_id uuid references public.house_expenses(id) on delete set null,
  completed_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id)
);

create index if not exists idx_shopping_trips_house on public.shopping_trips (house_id, completed_at);

alter table public.shopping_trips enable row level security;

-- 4. TABELA TASK_ROUTINES (Rotinas e Revezamentos de Tarefas)
create table if not exists public.task_routines (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  title text not null,
  description text,
  frequency text not null check (frequency in ('daily', 'weekly', 'biweekly', 'monthly')),
  rotation_enabled boolean not null default true,
  members_order jsonb not null default '[]'::jsonb, -- Lista ordenada de user_ids para revezamento
  current_member_index integer not null default 0,
  next_due_date date not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_task_routines_house on public.task_routines (house_id);

alter table public.task_routines enable row level security;

create trigger trg_task_routines_updated_at
  before update on public.task_routines
  for each row execute function public.touch_updated_at();

-- 5. TABELA TASKS (Tarefas Pontuais e Instâncias de Rotinas)
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  title text not null,
  description text,
  due_date date,
  due_time time,
  assigned_to uuid references auth.users(id) on delete set null,
  is_completed boolean not null default false,
  completed_at timestamptz,
  completed_by uuid references auth.users(id),
  priority text not null default 'medium' check (priority in ('low', 'medium', 'high')),
  visibility text not null default 'house' check (visibility in ('house', 'private')),
  routine_id uuid references public.task_routines(id) on delete set null,
  cost_cents bigint check (cost_cents >= 0),
  expense_id uuid references public.house_expenses(id) on delete set null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_tasks_house on public.tasks (house_id, due_date);
create index if not exists idx_tasks_assigned on public.tasks (assigned_to, is_completed);

alter table public.tasks enable row level security;

create trigger trg_tasks_updated_at
  before update on public.tasks
  for each row execute function public.touch_updated_at();

-- 6. TABELA EVENTS (Agenda e Compromissos da Casa)
create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  title text not null,
  description text,
  start_time timestamptz not null,
  end_time timestamptz not null,
  is_all_day boolean not null default false,
  location text,
  visibility text not null default 'house' check (visibility in ('house', 'restricted', 'private')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint check_event_dates check (end_time >= start_time)
);

create index if not exists idx_events_house_time on public.events (house_id, start_time);

alter table public.events enable row level security;

create trigger trg_events_updated_at
  before update on public.events
  for each row execute function public.touch_updated_at();

-- 7. TABELA EVENT_PARTICIPANTS (Participantes e RSVP de Eventos)
create table if not exists public.event_participants (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  is_essential boolean not null default false,
  rsvp_status text not null default 'pending' check (rsvp_status in ('pending', 'accepted', 'declined', 'tentative')),
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  unique(event_id, user_id)
);

create index if not exists idx_event_participants_event on public.event_participants (event_id);
create index if not exists idx_event_participants_user on public.event_participants (user_id);

alter table public.event_participants enable row level security;

-- ==============================================================================
-- VIEWS DERIVADAS
-- ==============================================================================

-- View: Status do Evento (Confirmado, Em Risco, Aguardando)
create or replace view public.v_event_status
with (security_invoker = true) as
select
  e.id as event_id,
  e.title,
  e.start_time,
  e.end_time,
  case
    -- Se algum membro essencial recusou -> Em Risco
    when exists (
      select 1 from public.event_participants p
      where p.event_id = e.id and p.is_essential and p.rsvp_status = 'declined'
    ) then 'at_risk'
    -- Se todos os membros essenciais aceitaram -> Confirmado
    when not exists (
      select 1 from public.event_participants p
      where p.event_id = e.id and p.is_essential and p.rsvp_status <> 'accepted'
    ) and exists (
      select 1 from public.event_participants p
      where p.event_id = e.id and p.is_essential
    ) then 'confirmed'
    else 'pending'
  end as computed_status
from public.events e;

-- View: Tarefas Atrasadas
create or replace view public.v_task_status
with (security_invoker = true) as
select
  t.id as task_id,
  t.title,
  t.due_date,
  t.is_completed,
  case
    when t.is_completed then 'completed'
    when t.due_date is not null and t.due_date < current_date then 'overdue'
    when t.due_date = current_date then 'today'
    else 'upcoming'
  end as computed_status
from public.tasks t;

-- ==============================================================================
-- RLS POLICIES
-- ==============================================================================

-- Shopping Lists:
create policy "shopping_lists_select_member" on public.shopping_lists for select
  using (public.is_house_member(house_id));

create policy "shopping_lists_insert_member" on public.shopping_lists for insert
  with check (public.is_house_member(house_id) and created_by = auth.uid());

create policy "shopping_lists_update_member" on public.shopping_lists for update
  using (public.is_house_member(house_id))
  with check (public.is_house_member(house_id));

create policy "shopping_lists_delete_member" on public.shopping_lists for delete
  using (public.is_house_member(house_id));

-- Shopping Items:
create policy "shopping_items_select_member" on public.shopping_items for select
  using (public.is_house_member(house_id));

create policy "shopping_items_insert_member" on public.shopping_items for insert
  with check (public.is_house_member(house_id) and created_by = auth.uid());

create policy "shopping_items_update_member" on public.shopping_items for update
  using (public.is_house_member(house_id))
  with check (public.is_house_member(house_id));

create policy "shopping_items_delete_member" on public.shopping_items for delete
  using (public.is_house_member(house_id));

-- Shopping Trips:
create policy "shopping_trips_select_member" on public.shopping_trips for select
  using (public.is_house_member(house_id));

create policy "shopping_trips_insert_member" on public.shopping_trips for insert
  with check (public.is_house_member(house_id) and created_by = auth.uid());

-- Task Routines:
create policy "task_routines_select_member" on public.task_routines for select
  using (public.is_house_member(house_id));

create policy "task_routines_insert_member" on public.task_routines for insert
  with check (public.is_house_member(house_id) and created_by = auth.uid());

create policy "task_routines_update_member" on public.task_routines for update
  using (public.is_house_member(house_id))
  with check (public.is_house_member(house_id));

-- Tasks (com suporte a tarefas privadas):
create policy "tasks_select_member" on public.tasks for select
  using (
    public.is_house_member(house_id) and
    (visibility = 'house' or created_by = auth.uid() or assigned_to = auth.uid())
  );

create policy "tasks_insert_member" on public.tasks for insert
  with check (public.is_house_member(house_id) and created_by = auth.uid());

create policy "tasks_update_member" on public.tasks for update
  using (
    public.is_house_member(house_id) and
    (visibility = 'house' or created_by = auth.uid() or assigned_to = auth.uid())
  )
  with check (public.is_house_member(house_id));

create policy "tasks_delete_member" on public.tasks for delete
  using (
    public.is_house_member(house_id) and
    (created_by = auth.uid() or public.is_house_admin(house_id))
  );

-- Events (com suporte a eventos house, restricted e private):
create policy "events_select_visibility" on public.events for select
  using (
    public.is_house_member(house_id) and (
      visibility = 'house' or
      created_by = auth.uid() or
      (visibility = 'restricted' and exists (
        select 1 from public.event_participants ep
        where ep.event_id = id and ep.user_id = auth.uid()
      ))
    )
  );

create policy "events_insert_member" on public.events for insert
  with check (public.is_house_member(house_id) and created_by = auth.uid());

create policy "events_update_creator_or_admin" on public.events for update
  using (public.is_house_member(house_id) and (created_by = auth.uid() or public.is_house_admin(house_id)))
  with check (public.is_house_member(house_id));

create policy "events_delete_creator_or_admin" on public.events for delete
  using (public.is_house_member(house_id) and (created_by = auth.uid() or public.is_house_admin(house_id)));

-- Event Participants:
create policy "event_participants_select_member" on public.event_participants for select
  using (exists (
    select 1 from public.events e
    where e.id = event_id and public.is_house_member(e.house_id)
  ));

create policy "event_participants_insert_member" on public.event_participants for insert
  with check (exists (
    select 1 from public.events e
    where e.id = event_id and public.is_house_member(e.house_id)
  ));

create policy "event_participants_update_self_or_creator" on public.event_participants for update
  using (
    user_id = auth.uid() or exists (
      select 1 from public.events e
      where e.id = event_id and e.created_by = auth.uid()
    )
  )
  with check (
    user_id = auth.uid() or exists (
      select 1 from public.events e
      where e.id = event_id and e.created_by = auth.uid()
    )
  );
