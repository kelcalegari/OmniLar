-- ==============================================================================
-- Migration: 0006_domain_synchronization_schema.sql
-- Module: Sincronização do Domínio, Sub-itens, Recorrência, Caixinhas e RPCs Seguras
-- Description: Adiciona colunas de recorrência em house_expenses e events,
--              cria house_expense_items, savings_vaults, savings_transactions,
--              atualiza v_cycle_summary com isolamento de projetos e implementa
--              funções RPC seguras (security definer) para transações financeiras.
-- ==============================================================================

-- 1. RECORRÊNCIA EM HOUSE_EXPENSES
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'house_expenses' and column_name = 'is_recurring') then
    alter table public.house_expenses add column is_recurring boolean not null default false;
  end if;

  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'house_expenses' and column_name = 'is_variable') then
    alter table public.house_expenses add column is_variable boolean not null default false;
  end if;

  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'house_expenses' and column_name = 'due_day') then
    alter table public.house_expenses add column due_day smallint check (due_day is null or (due_day between 1 and 31));
  end if;

  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'house_expenses' and column_name = 'is_active') then
    alter table public.house_expenses add column is_active boolean not null default true;
  end if;

  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'house_expenses' and column_name = 'recurring_series_id') then
    alter table public.house_expenses add column recurring_series_id uuid;
    create index if not exists idx_house_expenses_series on public.house_expenses (recurring_series_id);
  end if;
end $$;

-- 2. RECORRÊNCIA EM EVENTS
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'events' and column_name = 'recurrence_frequency') then
    alter table public.events add column recurrence_frequency text not null default 'none'
      check (recurrence_frequency in ('none', 'daily', 'weekly', 'biweekly', 'monthly', 'yearly'));
  end if;

  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'events' and column_name = 'recurring_series_id') then
    alter table public.events add column recurring_series_id uuid;
    create index if not exists idx_events_series on public.events (recurring_series_id);
  end if;
end $$;

-- 3. TABELA HOUSE_EXPENSE_ITEMS (Sub-itens para boletos compostos)
create table if not exists public.house_expense_items (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.house_expenses(id) on delete cascade,
  title text not null,
  amount_cents bigint not null check (amount_cents > 0),
  category_id uuid references public.categories(id) on delete set null,
  responsible_member_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_expense_items_expense on public.house_expense_items (expense_id);
create index if not exists idx_expense_items_category on public.house_expense_items (category_id);
create index if not exists idx_expense_items_responsible on public.house_expense_items (responsible_member_id);

alter table public.house_expense_items enable row level security;

create policy "expense_items_select_member" on public.house_expense_items for select
  using (exists (
    select 1 from public.house_expenses e
    where e.id = expense_id and public.is_house_member(e.house_id)
  ));

create policy "expense_items_insert_member" on public.house_expense_items for insert
  with check (exists (
    select 1 from public.house_expenses e
    where e.id = expense_id and public.is_house_member(e.house_id)
  ));

create policy "expense_items_update_member" on public.house_expense_items for update
  using (exists (
    select 1 from public.house_expenses e
    where e.id = expense_id and public.is_house_member(e.house_id)
  ))
  with check (exists (
    select 1 from public.house_expenses e
    where e.id = expense_id and public.is_house_member(e.house_id)
  ));

create policy "expense_items_delete_member" on public.house_expense_items for delete
  using (exists (
    select 1 from public.house_expenses e
    where e.id = expense_id and public.is_house_member(e.house_id)
  ));

-- 4. TABELAS SAVINGS_VAULTS & SAVINGS_TRANSACTIONS (Caixinhas & Metas da Casa)
create table if not exists public.savings_vaults (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  name text not null,
  target_amount_cents bigint check (target_amount_cents is null or target_amount_cents > 0),
  current_balance_cents bigint not null default 0 check (current_balance_cents >= 0),
  icon text,
  color_hex text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_savings_vaults_house on public.savings_vaults (house_id);

alter table public.savings_vaults enable row level security;

create trigger trg_savings_vaults_updated_at
  before update on public.savings_vaults
  for each row execute function public.touch_updated_at();

create policy "savings_vaults_select_member" on public.savings_vaults for select
  using (public.is_house_member(house_id) and deleted_at is null);

create policy "savings_vaults_insert_member" on public.savings_vaults for insert
  with check (public.is_house_member(house_id));

create policy "savings_vaults_update_member" on public.savings_vaults for update
  using (public.is_house_member(house_id))
  with check (public.is_house_member(house_id));

create policy "savings_vaults_delete_admin" on public.savings_vaults for delete
  using (public.is_house_admin(house_id));

-- Transações das Caixinhas (Ledger Imutável)
create table if not exists public.savings_transactions (
  id uuid primary key default gen_random_uuid(),
  vault_id uuid not null references public.savings_vaults(id) on delete cascade,
  member_id uuid not null references auth.users(id),
  amount_cents bigint not null check (amount_cents > 0),
  type text not null check (type in ('deposit', 'withdraw')),
  description text,
  created_at timestamptz not null default now()
);

create index if not exists idx_savings_transactions_vault on public.savings_transactions (vault_id);

alter table public.savings_transactions enable row level security;

create policy "savings_transactions_select_member" on public.savings_transactions for select
  using (exists (
    select 1 from public.savings_vaults v
    where v.id = vault_id and public.is_house_member(v.house_id)
  ));

create policy "savings_transactions_insert_member" on public.savings_transactions for insert
  with check (exists (
    select 1 from public.savings_vaults v
    where v.id = vault_id and public.is_house_member(v.house_id) and member_id = auth.uid()
  ));

create trigger trg_savings_transactions_immutable
  before update or delete on public.savings_transactions
  for each row execute function public.prevent_ledger_mutation();

-- 5. ATUALIZAÇÃO DA VIEW V_CYCLE_SUMMARY COM ISOLAMENTO DE PROJETOS COMPARTILHADOS
create or replace view public.v_cycle_summary
with (security_invoker = true) as
select
  coalesce(c.house_id, e.house_id) as house_id,
  coalesce(c.cycle_start_date, e.cycle_start_date) as cycle_start_date,
  coalesce(c.total_contributions_cents, 0) as total_contributions_cents,
  coalesce(e.total_expenses_cents, 0) as total_expenses_cents
from (
  select house_id, cycle_start_date, sum(amount_cents) as total_contributions_cents
  from public.contributions
  group by house_id, cycle_start_date
) c
full outer join (
  select house_id, cycle_start_date, sum(amount_cents) as total_expenses_cents
  from public.house_expenses
  where deleted_at is null and project_id is null
  group by house_id, cycle_start_date
) e on c.house_id = e.house_id and c.cycle_start_date = e.cycle_start_date;

-- 6. RPCs DE TRANSAÇÃO SEGURA (SECURITY DEFINER)

-- Pagar parcela P2P garantindo integridade no ledger e atualizando saldo
create or replace function public.pay_p2p_installment(
  p_installment_id uuid,
  p_amount_cents bigint,
  p_payment_method_id uuid default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.p2p_loans%rowtype;
  v_installment public.p2p_installments%rowtype;
  v_payment_id uuid;
  v_remaining_cents bigint;
begin
  select * into v_installment from public.p2p_installments where id = p_installment_id;
  if not found then
    raise exception 'Parcela não encontrada.';
  end if;

  select * into v_loan from public.p2p_loans where id = v_installment.loan_id;
  if not found then
    raise exception 'Empréstimo não encontrado.';
  end if;

  -- Apenas devedor ou credor podem pagar/baixar parcela
  if auth.uid() <> v_loan.borrower_id and auth.uid() <> v_loan.lender_id then
    raise exception 'Permissão negada para quitar esta parcela.';
  end if;

  v_remaining_cents := v_installment.amount_cents - v_installment.paid_cents;
  if p_amount_cents <= 0 or p_amount_cents > v_remaining_cents then
    raise exception 'Valor inválido. Restante devido: % centavos.', v_remaining_cents;
  end if;

  -- 1. Cria registro no ledger imutável de pagamentos
  insert into public.payments (
    house_id, payer_id, receiver_id, amount_cents, type, notes, payment_method_id, created_by
  ) values (
    v_loan.house_id, v_loan.borrower_id, v_loan.lender_id, p_amount_cents, 'p2p_installment', p_notes, p_payment_method_id, auth.uid()
  ) returning id into v_payment_id;

  -- 2. Aloca no ledger de alocações
  insert into public.payment_allocations (
    payment_id, installment_id, allocated_cents
  ) values (
    v_payment_id, v_installment.id, p_amount_cents
  );

  -- 3. Atualiza o status e valor pago da parcela
  update public.p2p_installments
  set
    paid_cents = paid_cents + p_amount_cents,
    status = case
      when (paid_cents + p_amount_cents) >= amount_cents then 'paid'
      else 'partial'
    end,
    paid_at = case
      when (paid_cents + p_amount_cents) >= amount_cents then now()
      else paid_at
    end
  where id = v_installment.id;

  return v_payment_id;
end;
$$;

-- Confirmar transferência do Super Pix (apenas o recebedor pode confirmar)
create or replace function public.confirm_settlement_transfer(
  p_transfer_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transfer public.settlement_transfers%rowtype;
begin
  select * into v_transfer from public.settlement_transfers where id = p_transfer_id;
  if not found then
    raise exception 'Transferência não encontrada.';
  end if;

  -- Regra de Segurança: Apenas quem recebe o dinheiro pode confirmar o recebimento!
  if auth.uid() <> v_transfer.to_member_id then
    raise exception 'Apenas o recebedor da transferência pode confirmar o pagamento.';
  end if;

  update public.settlement_transfers
  set
    status = 'confirmed',
    paid_at = coalesce(paid_at, now())
  where id = p_transfer_id;

  return true;
end;
$$;
