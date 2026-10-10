-- ==============================================================================
-- Migration: 0002_finance_ledger_schema.sql
-- Module: Financeiro, Dívidas P2P, Ledger Imutável e Motor de Compensação
-- Description: Tabelas de Despesas, Aportes, Rateio, Empréstimos, Parcelas,
--              Pagamentos (Ledger), Liquidações e Funções do Motor de Compensação.
-- ==============================================================================

-- 1. TABELA HOUSE_EXPENSES
create table if not exists public.house_expenses (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  title text not null,
  amount_cents bigint not null check (amount_cents > 0),
  category_id uuid references public.categories(id) on delete set null,
  payment_method_id uuid references public.payment_methods(id) on delete set null,
  paid_by_id uuid not null references auth.users(id),
  paid_out_of_pocket boolean not null default false,
  due_date date not null,
  cycle_start_date date not null,
  split_type text not null default 'percentage' check (split_type in ('percentage', 'fixed', 'category_owner')),
  notes text,
  status text not null default 'pending' check (status in ('pending', 'paid', 'reimbursed', 'cancelled')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_house_expenses_house_cycle on public.house_expenses (house_id, cycle_start_date);
create index if not exists idx_house_expenses_due_date on public.house_expenses (house_id, due_date);

alter table public.house_expenses enable row level security;

create trigger trg_house_expenses_updated_at
  before update on public.house_expenses
  for each row execute function public.touch_updated_at();

-- 2. TABELA SPLIT_RULES
create table if not exists public.split_rules (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.house_expenses(id) on delete cascade,
  member_id uuid not null references auth.users(id) on delete cascade,
  percentage_basis_points integer check (percentage_basis_points between 0 and 10000), -- 10000 = 100.00%
  fixed_amount_cents bigint check (fixed_amount_cents >= 0),
  calculated_cents bigint not null check (calculated_cents >= 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_split_rules_expense on public.split_rules (expense_id);
create index if not exists idx_split_rules_member on public.split_rules (member_id);

alter table public.split_rules enable row level security;

-- 3. TABELA CONTRIBUTIONS (Aportes no Caixa da Casa)
create table if not exists public.contributions (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  member_id uuid not null references auth.users(id) on delete cascade,
  amount_cents bigint not null check (amount_cents > 0),
  cycle_start_date date not null,
  paid_at timestamptz not null default now(),
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_contributions_house_cycle on public.contributions (house_id, cycle_start_date);
create index if not exists idx_contributions_member on public.contributions (member_id);

alter table public.contributions enable row level security;

-- 4. TABELA P2P_LOANS (Empréstimos Diretos)
create table if not exists public.p2p_loans (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  lender_id uuid not null references auth.users(id),
  borrower_id uuid not null references auth.users(id),
  title text not null,
  description text,
  total_amount_cents bigint not null check (total_amount_cents > 0),
  installments_count integer not null default 1 check (installments_count > 0),
  status text not null default 'active' check (status in ('active', 'completed', 'forgiven', 'renegotiated', 'cancelled')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint check_distinct_members check (lender_id <> borrower_id)
);

create index if not exists idx_p2p_loans_house on public.p2p_loans (house_id);
create index if not exists idx_p2p_loans_members on public.p2p_loans (lender_id, borrower_id);

alter table public.p2p_loans enable row level security;

create trigger trg_p2p_loans_updated_at
  before update on public.p2p_loans
  for each row execute function public.touch_updated_at();

-- 5. TABELA P2P_INSTALLMENTS (Parcelas de Empréstimos)
create table if not exists public.p2p_installments (
  id uuid primary key default gen_random_uuid(),
  loan_id uuid not null references public.p2p_loans(id) on delete cascade,
  installment_number integer not null check (installment_number > 0),
  amount_cents bigint not null check (amount_cents > 0),
  paid_cents bigint not null default 0 check (paid_cents >= 0 and paid_cents <= amount_cents),
  due_date date not null,
  status text not null default 'pending' check (status in ('pending', 'partial', 'paid', 'forgiven', 'renegotiated')),
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(loan_id, installment_number)
);

create index if not exists idx_p2p_installments_loan on public.p2p_installments (loan_id);
create index if not exists idx_p2p_installments_due_date on public.p2p_installments (due_date);

alter table public.p2p_installments enable row level security;

create trigger trg_p2p_installments_updated_at
  before update on public.p2p_installments
  for each row execute function public.touch_updated_at();

-- 6. TABELA PAYMENTS (Ledger Imutável para Pagamentos)
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  payer_id uuid not null references auth.users(id),
  receiver_id uuid references auth.users(id), -- null quando for pagamento para a Casa
  amount_cents bigint not null check (amount_cents > 0),
  type text not null check (type in ('p2p_installment', 'house_contribution', 'settlement_clearing', 'reimbursement')),
  notes text,
  payment_method_id uuid references public.payment_methods(id) on delete set null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_payments_house on public.payments (house_id, created_at);

alter table public.payments enable row level security;

-- 7. TABELA PAYMENT_ALLOCATIONS (Alocação Imutável de Pagamentos a Parcelas)
create table if not exists public.payment_allocations (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments(id) on delete cascade,
  installment_id uuid references public.p2p_installments(id) on delete cascade,
  allocated_cents bigint not null check (allocated_cents > 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_payment_allocations_payment on public.payment_allocations (payment_id);
create index if not exists idx_payment_allocations_installment on public.payment_allocations (installment_id);

alter table public.payment_allocations enable row level security;

-- 8. TRIGGER DE IMUTABILIDADE DO LEDGER
create or replace function public.prevent_ledger_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Operação não permitida: registros do ledger financeiro são imutáveis.';
end;
$$;

create trigger trg_payments_immutable
  before update or delete on public.payments
  for each row execute function public.prevent_ledger_mutation();

create trigger trg_payment_allocations_immutable
  before update or delete on public.payment_allocations
  for each row execute function public.prevent_ledger_mutation();

-- 9. TABELA SETTLEMENTS (Fechamento / Liquidação de Ciclo)
create table if not exists public.settlements (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  cycle_start_date date not null,
  status text not null default 'draft' check (status in ('draft', 'confirmed', 'completed', 'cancelled')),
  total_expenses_cents bigint not null default 0,
  total_contributions_cents bigint not null default 0,
  total_cleared_p2p_cents bigint not null default 0,
  settled_at timestamptz,
  settled_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(house_id, cycle_start_date)
);

create index if not exists idx_settlements_house_cycle on public.settlements (house_id, cycle_start_date);

alter table public.settlements enable row level security;

-- 10. TABELA SETTLEMENT_TRANSFERS (As Transferências do Super Pix)
create table if not exists public.settlement_transfers (
  id uuid primary key default gen_random_uuid(),
  settlement_id uuid not null references public.settlements(id) on delete cascade,
  from_member_id uuid not null references auth.users(id),
  to_member_id uuid not null references auth.users(id),
  amount_cents bigint not null check (amount_cents > 0),
  status text not null default 'pending' check (status in ('pending', 'paid', 'confirmed')),
  paid_at timestamptz,
  proof_attachment_id uuid references public.attachments(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_settlement_transfers_settlement on public.settlement_transfers (settlement_id);

alter table public.settlement_transfers enable row level security;

-- ==============================================================================
-- RLS POLICIES
-- ==============================================================================

-- House Expenses:
create policy "house_expenses_select_member" on public.house_expenses for select
  using (public.is_house_member(house_id) and deleted_at is null);

create policy "house_expenses_insert_member" on public.house_expenses for insert
  with check (public.is_house_member(house_id) and created_by = auth.uid());

create policy "house_expenses_update_member" on public.house_expenses for update
  using (public.is_house_member(house_id) and (created_by = auth.uid() or public.is_house_admin(house_id)))
  with check (public.is_house_member(house_id));

-- Split Rules:
create policy "split_rules_select_member" on public.split_rules for select
  using (exists (
    select 1 from public.house_expenses e
    where e.id = expense_id and public.is_house_member(e.house_id)
  ));

create policy "split_rules_insert_member" on public.split_rules for insert
  with check (exists (
    select 1 from public.house_expenses e
    where e.id = expense_id and public.is_house_member(e.house_id)
  ));

-- Contributions:
create policy "contributions_select_member" on public.contributions for select
  using (public.is_house_member(house_id));

create policy "contributions_insert_member" on public.contributions for insert
  with check (public.is_house_member(house_id) and created_by = auth.uid());

-- P2P Loans: (Apenas credor e devedor podem ver e interagir)
create policy "p2p_loans_select_parties" on public.p2p_loans for select
  using (public.is_house_member(house_id) and (lender_id = auth.uid() or borrower_id = auth.uid()));

create policy "p2p_loans_insert_member" on public.p2p_loans for insert
  with check (public.is_house_member(house_id) and created_by = auth.uid() and (lender_id = auth.uid() or borrower_id = auth.uid()));

create policy "p2p_loans_update_parties" on public.p2p_loans for update
  using (lender_id = auth.uid() or borrower_id = auth.uid())
  with check (lender_id = auth.uid() or borrower_id = auth.uid());

-- P2P Installments:
create policy "p2p_installments_select_parties" on public.p2p_installments for select
  using (exists (
    select 1 from public.p2p_loans l
    where l.id = loan_id and (l.lender_id = auth.uid() or l.borrower_id = auth.uid())
  ));

create policy "p2p_installments_insert_parties" on public.p2p_installments for insert
  with check (exists (
    select 1 from public.p2p_loans l
    where l.id = loan_id and (l.lender_id = auth.uid() or l.borrower_id = auth.uid())
  ));

create policy "p2p_installments_update_parties" on public.p2p_installments for update
  using (exists (
    select 1 from public.p2p_loans l
    where l.id = loan_id and (l.lender_id = auth.uid() or l.borrower_id = auth.uid())
  ));

-- Payments (Ledger):
create policy "payments_select_member" on public.payments for select
  using (public.is_house_member(house_id));

create policy "payments_insert_member" on public.payments for insert
  with check (public.is_house_member(house_id) and created_by = auth.uid());

-- Payment Allocations:
create policy "payment_allocations_select_member" on public.payment_allocations for select
  using (exists (
    select 1 from public.payments p
    where p.id = payment_id and public.is_house_member(p.house_id)
  ));

create policy "payment_allocations_insert_member" on public.payment_allocations for insert
  with check (exists (
    select 1 from public.payments p
    where p.id = payment_id and public.is_house_member(p.house_id)
  ));

-- Settlements:
create policy "settlements_select_member" on public.settlements for select
  using (public.is_house_member(house_id));

create policy "settlements_insert_admin" on public.settlements for insert
  with check (public.is_house_member(house_id));

create policy "settlements_update_member" on public.settlements for update
  using (public.is_house_member(house_id))
  with check (public.is_house_member(house_id));

-- Settlement Transfers:
create policy "settlement_transfers_select_member" on public.settlement_transfers for select
  using (exists (
    select 1 from public.settlements s
    where s.id = settlement_id and public.is_house_member(s.house_id)
  ));

create policy "settlement_transfers_insert_member" on public.settlement_transfers for insert
  with check (exists (
    select 1 from public.settlements s
    where s.id = settlement_id and public.is_house_member(s.house_id)
  ));

create policy "settlement_transfers_update_party" on public.settlement_transfers for update
  using (from_member_id = auth.uid() or to_member_id = auth.uid())
  with check (from_member_id = auth.uid() or to_member_id = auth.uid());

-- ==============================================================================
-- VIEWS DERIVADAS
-- ==============================================================================

-- View: Resumo do Ciclo Financeiro
create or replace view public.v_cycle_summary as
select
  h.id as house_id,
  c.cycle_start_date,
  coalesce(sum(c.amount_cents), 0) as total_contributions_cents,
  coalesce((
    select sum(e.amount_cents)
    from public.house_expenses e
    where e.house_id = h.id and e.cycle_start_date = c.cycle_start_date and e.deleted_at is null
  ), 0) as total_expenses_cents
from public.houses h
cross join (
  select distinct cycle_start_date from public.contributions
  union
  select distinct cycle_start_date from public.house_expenses
) c
left join public.contributions con on con.house_id = h.id and con.cycle_start_date = c.cycle_start_date
group by h.id, c.cycle_start_date;

-- View: Status Atualizado de Parcelas
create or replace view public.v_installment_status as
select
  i.id as installment_id,
  i.loan_id,
  i.installment_number,
  i.amount_cents,
  i.paid_cents,
  (i.amount_cents - i.paid_cents) as remaining_cents,
  i.due_date,
  case
    when i.status in ('forgiven', 'renegotiated') then i.status
    when i.paid_cents >= i.amount_cents then 'paid'
    when i.paid_cents > 0 then 'partial'
    when current_date > i.due_date then 'overdue'
    else 'pending'
  end as computed_status
from public.p2p_installments i;
