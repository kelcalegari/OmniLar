-- ==============================================================================
-- 0057: Código do boleto da fatura do cartão
-- Descrição:
--   A fatura do cartão não é uma linha própria: é o grupo das compras de um
--   cartão com o mesmo vencimento. Para pagar, era preciso buscar o boleto no
--   app do banco. Agora a fatura (cartão + vencimento) pode guardar a linha
--   digitável do boleto dela, para copiar e colar na hora de pagar.
-- ==============================================================================

create table if not exists public.card_invoice_codes (
  house_id uuid not null references public.houses(id) on delete cascade,
  payment_method_id uuid not null references public.payment_methods(id) on delete cascade,
  due_date date not null,
  barcode text not null check (length(barcode) > 0),
  created_by uuid not null default auth.uid() references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key (payment_method_id, due_date)
);

create index if not exists idx_card_invoice_codes_house
  on public.card_invoice_codes (house_id, due_date);

alter table public.card_invoice_codes enable row level security;

-- Só morador da casa, e só para cartão da própria casa
drop policy if exists "card_invoice_codes_select_house_member" on public.card_invoice_codes;
create policy "card_invoice_codes_select_house_member" on public.card_invoice_codes
  for select using (public.is_house_member(house_id));

drop policy if exists "card_invoice_codes_insert_house_member" on public.card_invoice_codes;
create policy "card_invoice_codes_insert_house_member" on public.card_invoice_codes
  for insert with check (
    public.is_house_member(house_id)
    and exists (
      select 1 from public.payment_methods pm
      where pm.id = payment_method_id and pm.house_id = card_invoice_codes.house_id
    )
  );

drop policy if exists "card_invoice_codes_update_house_member" on public.card_invoice_codes;
create policy "card_invoice_codes_update_house_member" on public.card_invoice_codes
  for update using (public.is_house_member(house_id))
  with check (
    public.is_house_member(house_id)
    and exists (
      select 1 from public.payment_methods pm
      where pm.id = payment_method_id and pm.house_id = card_invoice_codes.house_id
    )
  );

drop policy if exists "card_invoice_codes_delete_house_member" on public.card_invoice_codes;
create policy "card_invoice_codes_delete_house_member" on public.card_invoice_codes
  for delete using (public.is_house_member(house_id));

grant select, insert, update, delete on public.card_invoice_codes to authenticated;
