-- ==============================================================================
-- 0053: Regras aprendidas da importação de fatura
-- Descrição:
--   A cada fatura o usuário repetia as mesmas decisões: "Posto Ipiranga é do
--   Cristiano", "Enel é Contas". Agora o que foi decidido para um
--   estabelecimento fica guardado e é aplicado nas próximas importações.
--
--   A regra vale para um cartão ou conta: a mesma loja pode ser empréstimo no
--   cartão de um morador e gasto pessoal no cartão do outro.
-- ==============================================================================

create table if not exists public.import_rules (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  payment_method_id uuid not null references public.payment_methods(id) on delete cascade,
  -- Nome do estabelecimento sem acento, número de loja nem parcela
  match_key text not null check (length(match_key) > 0),
  merchant_name text not null,
  destination text not null check (destination in ('house', 'p2p_loan', 'personal', 'ignored')),
  category_id uuid references public.categories(id) on delete set null,
  assigned_member_id uuid references auth.users(id) on delete set null, -- Devedor, se for p2p_loan
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (house_id, payment_method_id, match_key)
);

create index if not exists idx_import_rules_payment_method
  on public.import_rules (payment_method_id);

alter table public.import_rules enable row level security;

drop policy if exists "import_rules_select_house_member" on public.import_rules;
create policy "import_rules_select_house_member" on public.import_rules
  for select using (public.is_house_member(house_id));

drop policy if exists "import_rules_insert_house_member" on public.import_rules;
create policy "import_rules_insert_house_member" on public.import_rules
  for insert with check (public.is_house_member(house_id));

drop policy if exists "import_rules_update_house_member" on public.import_rules;
create policy "import_rules_update_house_member" on public.import_rules
  for update using (public.is_house_member(house_id))
  with check (public.is_house_member(house_id));

drop policy if exists "import_rules_delete_house_member" on public.import_rules;
create policy "import_rules_delete_house_member" on public.import_rules
  for delete using (public.is_house_member(house_id));

grant select, insert, update, delete on public.import_rules to authenticated;
