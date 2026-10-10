-- ==============================================================================
-- Migration: 20261007030000_0004_intelligence_schema.sql
-- Module: Inteligência (Captura Inteligente, Conciliação/Importação e Assistente IA)
-- Specification: novoSite/arquitetura_tecnica.md seções 8, 17 e módulos correspondentes
-- Rules Enforced: RLS em todas as tabelas, house_scoped, auditabilidade, confirmação humana
-- ==============================================================================

-- 1. TABELA AI_USAGE (Controle de Quota Diária e Auditoria de Tokens - LGPD/Limites)
create table if not exists public.ai_usage (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  member_id uuid not null references auth.users(id) on delete cascade,
  feature text not null check (feature in ('capture', 'import', 'assistant')),
  model text not null,
  tokens_in integer not null default 0,
  tokens_out integer not null default 0,
  status text not null check (status in ('success', 'rate_limited', 'error')),
  created_at timestamptz not null default now()
);

create index if not exists idx_ai_usage_house_date on public.ai_usage (house_id, created_at);
create index if not exists idx_ai_usage_member_date on public.ai_usage (member_id, created_at);

alter table public.ai_usage enable row level security;

create policy "ai_usage_select_house_member" on public.ai_usage
  for select using (public.is_house_member(house_id));

create policy "ai_usage_insert_house_member" on public.ai_usage
  for insert with check (public.is_house_member(house_id) and member_id = auth.uid());

-- 2. TABELA CAPTURES (Propostas de Captura Inteligente: Boletos, Notas NFC-e, Recibos)
create table if not exists public.captures (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  file_hash text not null,
  file_url text,
  document_type text not null check (document_type in ('nfce', 'boleto', 'receipt', 'unknown')),
  raw_payload_masked jsonb,
  status text not null default 'proposed' check (status in ('proposed', 'confirmed', 'rejected', 'expired')),
  confidence numeric(4, 3) not null default 1.000 check (confidence >= 0 and confidence <= 1),
  confirmed_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_captures_house_status on public.captures (house_id, status);
create index if not exists idx_captures_hash on public.captures (file_hash);

alter table public.captures enable row level security;

create trigger trg_captures_updated_at
  before update on public.captures
  for each row execute function public.touch_updated_at();

create policy "captures_select_house_member" on public.captures
  for select using (public.is_house_member(house_id));

create policy "captures_insert_house_member" on public.captures
  for insert with check (public.is_house_member(house_id) and created_by = auth.uid());

create policy "captures_update_house_member" on public.captures
  for update using (public.is_house_member(house_id));

-- 3. TABELA IMPORT_BATCHES & IMPORT_LINES (Reconciliação e Rachar a Fatura)
create table if not exists public.import_batches (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  source_type text not null check (source_type in ('credit_card', 'bank_statement', 'manual_csv')),
  account_name text not null,
  cycle_id uuid, -- referência ao ciclo ou período correspondente
  total_cents bigint not null default 0 check (total_cents >= 0),
  lines_count integer not null default 0,
  is_reconciled boolean not null default false,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_import_batches_house on public.import_batches (house_id);

alter table public.import_batches enable row level security;

create policy "import_batches_select_house_member" on public.import_batches
  for select using (public.is_house_member(house_id));

create policy "import_batches_insert_house_member" on public.import_batches
  for insert with check (public.is_house_member(house_id) and created_by = auth.uid());

create table if not exists public.import_lines (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.import_batches(id) on delete cascade,
  house_id uuid not null references public.houses(id) on delete cascade,
  line_date date not null,
  description text not null,
  amount_cents bigint not null check (amount_cents > 0),
  split_destination text not null default 'house' check (split_destination in ('house', 'p2p_loan', 'personal_ignored')),
  category_id uuid references public.categories(id) on delete set null,
  assigned_member_id uuid references auth.users(id) on delete set null, -- Devedor P2P se for p2p_loan
  is_confirmed boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_import_lines_batch on public.import_lines (batch_id);
create index if not exists idx_import_lines_house on public.import_lines (house_id);

alter table public.import_lines enable row level security;

create policy "import_lines_select_house_member" on public.import_lines
  for select using (public.is_house_member(house_id));

create policy "import_lines_all_house_member" on public.import_lines
  for all using (public.is_house_member(house_id));

-- 4. TABELA ASSISTANT_CONVERSATIONS & MESSAGES (Conversas do Assistente IA - Privado do Membro)
create table if not exists public.assistant_conversations (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  member_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_assistant_conversations_member on public.assistant_conversations (member_id);

alter table public.assistant_conversations enable row level security;

create trigger trg_assistant_conversations_updated_at
  before update on public.assistant_conversations
  for each row execute function public.touch_updated_at();

-- Apenas o próprio membro vê suas conversas com o assistente (RN11)
create policy "assistant_conversations_owner_only" on public.assistant_conversations
  for all using (member_id = auth.uid());

create table if not exists public.assistant_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.assistant_conversations(id) on delete cascade,
  role text not null check (role in ('user', 'assistant', 'system')),
  content text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_assistant_messages_conversation on public.assistant_messages (conversation_id, created_at);

alter table public.assistant_messages enable row level security;

create policy "assistant_messages_owner_only" on public.assistant_messages
  for all using (
    exists (
      select 1 from public.assistant_conversations c
      where c.id = conversation_id and c.member_id = auth.uid()
    )
  );

-- 5. TABELA ASSISTANT_ACTIONS (Propostas do Assistente com Confirmação Obrigatória - RN01, RN07)
create table if not exists public.assistant_actions (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.assistant_conversations(id) on delete cascade,
  tool_name text not null,
  arguments_json jsonb not null default '{}'::jsonb,
  status text not null default 'proposed' check (status in ('proposed', 'confirmed', 'edited', 'cancelled', 'failed')),
  is_high_risk boolean not null default false,
  confirmed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_assistant_actions_conversation on public.assistant_actions (conversation_id, status);

alter table public.assistant_actions enable row level security;

create policy "assistant_actions_owner_only" on public.assistant_actions
  for all using (
    exists (
      select 1 from public.assistant_conversations c
      where c.id = conversation_id and c.member_id = auth.uid()
    )
  );

-- 6. TABELA ASSISTANT_PREFERENCES (Preferências, Horários Silenciosos e Consentimento LGPD)
create table if not exists public.assistant_preferences (
  member_id uuid primary key references auth.users(id) on delete cascade,
  house_id uuid not null references public.houses(id) on delete cascade,
  is_enabled boolean not null default true,
  voice_enabled boolean not null default false,
  proactive_summaries boolean not null default true,
  quiet_hours_start time default '22:00:00',
  quiet_hours_end time default '08:00:00',
  privacy_consent_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.assistant_preferences enable row level security;

create trigger trg_assistant_preferences_updated_at
  before update on public.assistant_preferences
  for each row execute function public.touch_updated_at();

create policy "assistant_preferences_owner_only" on public.assistant_preferences
  for all using (member_id = auth.uid());
