-- ==============================================================================
-- 0096: Entrada de fora no Caixa da Casa
-- Descrição:
--   Até aqui todo dinheiro que entrava no Caixa do ciclo era aporte de um
--   morador (contributions). Um Pix de quem não mora na casa, um reembolso ou
--   uma devolução de loja tinham de virar aporte de alguém (crédito falso no
--   fechamento) ou ficar de fora do saldo.
--
--   - house_inflows: a entrada de fora, com valor, dia, descrição, origem
--     (third_party_pix, refund, store_return, other) e, opcional, a despesa que
--     ela reembolsa. Entra no Caixa do ciclo em que cai received_on e segue a
--     regra third_party de opening_inflow_rules (0092); o cálculo é do app.
--   - Diferente dos repasses de terceiros (0090): o repasse fica guardado numa
--     caixinha, fora do Caixa do ciclo, até pagar uma fatura. A entrada de fora
--     é dinheiro livre do ciclo. O mesmo Pix não deve ser lançado nos dois.
--   - Qualquer morador lança; quem lançou ou um administrador corrige e exclui.
--     Ciclo fechado não aceita entrada nova nem mudança (house_date_is_closed,
--     0030, que o authenticated pode chamar).
--   - settlement_data_version (0032) passa a incluir as entradas de fora: o
--     fechamento recusa se uma entrada mudou desde o cálculo.
-- ==============================================================================

create table if not exists public.house_inflows (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  amount_cents bigint not null check (amount_cents > 0),
  received_on date not null,
  description text not null check (length(btrim(description)) > 0),
  source text not null default 'other'
    check (source in ('third_party_pix', 'refund', 'store_return', 'other')),
  -- Despesa que a entrada reembolsa (nulo: nenhuma em especial)
  expense_id uuid references public.house_expenses(id) on delete set null,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_house_inflows_house_day
  on public.house_inflows (house_id, received_on desc);
create index if not exists idx_house_inflows_expense
  on public.house_inflows (expense_id);
create index if not exists idx_house_inflows_created_by
  on public.house_inflows (created_by);

drop trigger if exists trg_house_inflows_touch_updated_at on public.house_inflows;
create trigger trg_house_inflows_touch_updated_at
  before update on public.house_inflows
  for each row execute function public.touch_updated_at();

alter table public.house_inflows enable row level security;

-- Leitura por morador
drop policy if exists "house_inflows_select_house_member" on public.house_inflows;
create policy "house_inflows_select_house_member" on public.house_inflows
  for select using (public.is_house_member(house_id));

-- Lançar: morador, em nome próprio, em ciclo aberto e com despesa da mesma casa
drop policy if exists "house_inflows_insert_house_member" on public.house_inflows;
create policy "house_inflows_insert_house_member" on public.house_inflows
  for insert with check (
    public.is_house_member(house_id)
    and created_by = auth.uid()
    and not public.house_date_is_closed(house_id, received_on)
    and (
      expense_id is null
      or exists (
        select 1 from public.house_expenses e
        where e.id = expense_id and e.house_id = house_inflows.house_id
      )
    )
  );

-- Corrigir: quem lançou ou administrador, com o dia antigo e o novo em ciclo aberto
drop policy if exists "house_inflows_update_creator_or_admin" on public.house_inflows;
create policy "house_inflows_update_creator_or_admin" on public.house_inflows
  for update
  using (
    public.is_house_member(house_id)
    and (created_by = auth.uid() or public.is_house_admin(house_id))
    and not public.house_date_is_closed(house_id, received_on)
  )
  with check (
    public.is_house_member(house_id)
    and (created_by = auth.uid() or public.is_house_admin(house_id))
    and not public.house_date_is_closed(house_id, received_on)
    and (
      expense_id is null
      or exists (
        select 1 from public.house_expenses e
        where e.id = expense_id and e.house_id = house_inflows.house_id
      )
    )
  );

-- Excluir: quem lançou ou administrador, em ciclo aberto
drop policy if exists "house_inflows_delete_creator_or_admin" on public.house_inflows;
create policy "house_inflows_delete_creator_or_admin" on public.house_inflows
  for delete using (
    public.is_house_member(house_id)
    and (created_by = auth.uid() or public.is_house_admin(house_id))
    and not public.house_date_is_closed(house_id, received_on)
  );

grant select, insert, update, delete on public.house_inflows to authenticated;

-- A casa e quem lançou não mudam depois
create or replace function public.house_inflows_keep_owner()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.house_id <> old.house_id or new.created_by <> old.created_by then
    raise exception 'A entrada de fora não muda de casa nem de quem lançou.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_house_inflows_keep_owner on public.house_inflows;
create trigger trg_house_inflows_keep_owner
  before update on public.house_inflows
  for each row execute function public.house_inflows_keep_owner();

-- Tempo real, como os aportes (0061)
alter table public.house_inflows replica identity full;
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'house_inflows'
  ) then
    alter publication supabase_realtime add table public.house_inflows;
  end if;
end $$;

-- Versão dos dados do fechamento (0032) com as entradas de fora
create or replace function public.settlement_data_version(p_house_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version text;
begin
  if not public.is_house_member(p_house_id) then
    raise exception 'Acesso negado: você não é membro desta casa';
  end if;

  select md5(concat_ws('|',
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select e.id, e.updated_at, e.deleted_at
             from public.house_expenses e where e.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select s.id, s.expense_id, s.member_id, s.percentage_basis_points, s.fixed_amount_cents, s.calculated_cents
             from public.split_rules s
             join public.house_expenses e on e.id = s.expense_id
             where e.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select i.id, i.expense_id, i.amount_cents, i.responsible_member_id, i.split_type
             from public.house_expense_items i
             join public.house_expenses e on e.id = i.expense_id
             where e.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select c.id, c.member_id, c.amount_cents, c.cycle_start_date, c.date
             from public.contributions c where c.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.user_id), ''))
       from (select hm.user_id, hm.role, hm.left_at, hm.default_split_percent, hm.default_fixed_amount_cents
             from public.house_members hm where hm.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select l.id, l.updated_at
             from public.p2p_loans l where l.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select i.id, i.updated_at
             from public.p2p_installments i
             join public.p2p_loans l on l.id = i.loan_id
             where l.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select v.id, v.current_balance_cents, v.deleted_at
             from public.savings_vaults v where v.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select pm.id, pm.type
             from public.payment_methods pm where pm.house_id = p_house_id) x),
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select st.id, st.cycle_start_date, st.status, st.surplus_vaulted_cents, st.deficit_covered_cents,
                    st.surplus_rolled_cents, st.surplus_refunded_cents,
                    st.house_receivable_cents, st.house_forgiven_cents, st.house_loans_received_cents
             from public.settlements st where st.house_id = p_house_id) x),
    -- Entradas de fora (0096)
    (select md5(coalesce(string_agg(x::text, ',' order by x.id), ''))
       from (select hi.id, hi.amount_cents, hi.received_on, hi.updated_at
             from public.house_inflows hi where hi.house_id = p_house_id) x)
  )) into v_version;

  return v_version;
end;
$$;
