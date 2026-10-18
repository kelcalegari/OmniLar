-- ==============================================================================
-- 0090: Entradas de terceiros (repasses) guardadas em caixinha
-- Descrição:
--   Caso do dono: um morador compra no cartão para várias pessoas (marmitas de
--   R$ 192, sendo R$ 32 dele) e as outras pagam por Pix na conta da Casa
--   (R$ 160). O Pix entra neste ciclo e a fatura só vence no próximo. Como o
--   aporte é sempre de um morador, lançar o Pix como aporte dava a ele um
--   crédito falso no fechamento e mostrava no Fôlego um dinheiro com destino.
--
--   Agora a Casa registra a entrada de terceiros: quem pagou, quanto, quando e
--   o cartão a que ela se refere (opcional). O valor é guardado numa caixinha,
--   fora do Caixa do ciclo e sem virar aporte de ninguém, até ser usado:
--   - a Casa pagou a fatura: o valor sai da caixinha, pelo banco;
--   - o titular pagou a fatura: o valor sai da caixinha e é repassado a ele.
--   Desfazer o uso devolve o valor à caixinha; excluir uma entrada guardada
--   tira o valor da caixinha.
--
--   - third_party_receipts: as entradas, lidas por qualquer morador. Só as
--     funções abaixo gravam, sempre junto com a movimentação da caixinha
--     (move_vault_balance, 0067), que deixa o extrato e o aviso de sempre.
--   - import_lines.split_destination ganha 'third_party' ("Pago por
--     terceiros"): a parte da fatura que outros pagaram fica no histórico da
--     importação sem virar despesa.
-- ==============================================================================

create table if not exists public.third_party_receipts (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  payer_name text not null check (length(btrim(payer_name)) > 0),
  description text,
  amount_cents bigint not null check (amount_cents > 0),
  received_on date not null,
  vault_id uuid not null references public.savings_vaults(id),
  -- Cartão cuja fatura a entrada ajuda a pagar (nulo: ainda não se sabe)
  payment_method_id uuid references public.payment_methods(id) on delete set null,
  status text not null default 'held' check (status in ('held', 'used')),
  used_mode text check (used_mode in ('house_paid', 'passed_to_owner')),
  -- Fatura em que foi usada: o desfazer do pagamento dela devolve a entrada
  used_payment_method_id uuid references public.payment_methods(id) on delete set null,
  used_due_date date,
  used_at timestamptz,
  used_by uuid references auth.users(id),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  constraint third_party_receipts_used_check check (
    (status = 'held' and used_mode is null and used_at is null)
    or (status = 'used' and used_mode is not null and used_at is not null)
  )
);

create index if not exists idx_third_party_receipts_house
  on public.third_party_receipts (house_id, status, received_on desc);
create index if not exists idx_third_party_receipts_vault
  on public.third_party_receipts (vault_id);
create index if not exists idx_third_party_receipts_payment_method
  on public.third_party_receipts (payment_method_id);
create index if not exists idx_third_party_receipts_used_invoice
  on public.third_party_receipts (used_payment_method_id, used_due_date);
create index if not exists idx_third_party_receipts_created_by
  on public.third_party_receipts (created_by);
create index if not exists idx_third_party_receipts_used_by
  on public.third_party_receipts (used_by);

alter table public.third_party_receipts enable row level security;

-- Leitura por morador; gravação só pelas funções (saldo da caixinha junto)
drop policy if exists "third_party_receipts_select_house_member" on public.third_party_receipts;
create policy "third_party_receipts_select_house_member" on public.third_party_receipts
  for select using (public.is_house_member(house_id));

grant select on public.third_party_receipts to authenticated;

-- Tempo real, como as caixinhas (0061)
alter table public.third_party_receipts replica identity full;
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'third_party_receipts'
  ) then
    alter publication supabase_realtime add table public.third_party_receipts;
  end if;
end $$;

-- 1. Registrar a entrada: grava e deposita na caixinha (sem tirar do ciclo)
create or replace function public.register_third_party_receipt(
  p_house_id uuid,
  p_payer_name text,
  p_amount_cents bigint,
  p_received_on date,
  p_vault_id uuid,
  p_payment_method_id uuid default null,
  p_description text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_payer text := nullif(btrim(coalesce(p_payer_name, '')), '');
  v_description text := nullif(btrim(coalesce(p_description, '')), '');
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;
  if p_house_id is null or not public.is_house_member(p_house_id) then
    raise exception 'Casa não encontrada.';
  end if;
  if v_payer is null then
    raise exception 'Informe quem pagou.';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'O valor deve ser maior que zero.';
  end if;
  if p_received_on is null then
    raise exception 'Informe o dia em que o dinheiro entrou.';
  end if;
  if not exists (
    select 1 from public.savings_vaults v
    where v.id = p_vault_id and v.house_id = p_house_id and v.deleted_at is null
  ) then
    raise exception 'Caixinha não encontrada nesta casa.';
  end if;
  if p_payment_method_id is not null and not exists (
    select 1 from public.payment_methods pm
    where pm.id = p_payment_method_id and pm.house_id = p_house_id
  ) then
    raise exception 'Cartão não encontrado nesta casa.';
  end if;

  insert into public.third_party_receipts (
    house_id, payer_name, description, amount_cents, received_on, vault_id, payment_method_id, created_by
  )
  values (p_house_id, v_payer, v_description, p_amount_cents, p_received_on, p_vault_id, p_payment_method_id, v_uid)
  returning id into v_id;

  perform public.move_vault_balance(
    p_vault_id,
    'deposit',
    p_amount_cents,
    'Repasse de ' || v_payer || coalesce(': ' || v_description, '')
  );

  return v_id;
end;
$$;

revoke execute on function public.register_third_party_receipt(uuid, text, bigint, date, uuid, uuid, text) from public, anon;
grant execute on function public.register_third_party_receipt(uuid, text, bigint, date, uuid, uuid, text) to authenticated;

-- 2. Usar entradas guardadas na fatura de um cartão: saem da caixinha (sem
--    voltar ao ciclo). p_mode: 'house_paid' (a Casa pagou a fatura) ou
--    'passed_to_owner' (o valor foi repassado a quem pagou a fatura).
--    Devolve quantas entradas foram usadas.
create or replace function public.use_third_party_receipts(
  p_receipt_ids uuid[],
  p_mode text,
  p_payment_method_id uuid default null,
  p_due_date date default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_receipt public.third_party_receipts%rowtype;
  v_count integer := 0;
  v_card text;
begin
  if v_uid is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;
  if p_mode is null or p_mode not in ('house_paid', 'passed_to_owner') then
    raise exception 'Diga se a Casa pagou a fatura ou se o valor foi repassado ao titular.';
  end if;
  if coalesce(array_length(p_receipt_ids, 1), 0) = 0 then
    return 0;
  end if;

  if p_payment_method_id is not null then
    select pm.name into v_card from public.payment_methods pm where pm.id = p_payment_method_id;
  end if;

  -- Travadas na mesma ordem: dois aparelhos não usam a mesma entrada
  for v_receipt in
    select * from public.third_party_receipts
    where id = any(p_receipt_ids)
    order by id
    for update
  loop
    if not public.is_house_member(v_receipt.house_id) then
      raise exception 'Entrada de terceiros não encontrada nesta casa.';
    end if;
    if v_receipt.status <> 'held' then
      raise exception 'O repasse de % já foi usado.', v_receipt.payer_name;
    end if;
    if p_payment_method_id is not null and not exists (
      select 1 from public.payment_methods pm
      where pm.id = p_payment_method_id and pm.house_id = v_receipt.house_id
    ) then
      raise exception 'Cartão não encontrado nesta casa.';
    end if;

    perform public.move_vault_balance(
      v_receipt.vault_id,
      'withdraw',
      v_receipt.amount_cents,
      'Repasse de ' || v_receipt.payer_name
        || case when p_mode = 'house_paid' then ' usado na fatura' else ' entregue a quem pagou a fatura' end
        || coalesce(' ' || v_card, '')
        || coalesce(' de ' || to_char(p_due_date, 'DD/MM'), '')
    );

    update public.third_party_receipts
    set status = 'used',
        used_mode = p_mode,
        used_payment_method_id = p_payment_method_id,
        used_due_date = p_due_date,
        used_at = now(),
        used_by = v_uid
    where id = v_receipt.id;
    v_count := v_count + 1;
  end loop;

  if v_count <> coalesce(array_length(p_receipt_ids, 1), 0) then
    raise exception 'Entrada de terceiros não encontrada nesta casa.';
  end if;
  return v_count;
end;
$$;

revoke execute on function public.use_third_party_receipts(uuid[], text, uuid, date) from public, anon;
grant execute on function public.use_third_party_receipts(uuid[], text, uuid, date) to authenticated;

-- 3. Desfazer o uso: o valor volta para a caixinha. Com p_receipt_ids nulo,
--    desfaz as entradas usadas na fatura (p_payment_method_id, p_due_date),
--    como no desfazer do pagamento dela. Devolve quantas voltaram.
create or replace function public.reopen_third_party_receipts(
  p_receipt_ids uuid[] default null,
  p_payment_method_id uuid default null,
  p_due_date date default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_receipt public.third_party_receipts%rowtype;
  v_count integer := 0;
begin
  if v_uid is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;
  if p_receipt_ids is null and (p_payment_method_id is null or p_due_date is null) then
    raise exception 'Informe as entradas ou a fatura.';
  end if;

  for v_receipt in
    select * from public.third_party_receipts r
    where r.status = 'used'
      and (
        (p_receipt_ids is not null and r.id = any(p_receipt_ids))
        or (p_receipt_ids is null
            and r.used_payment_method_id = p_payment_method_id
            and r.used_due_date = p_due_date)
      )
    order by r.id
    for update
  loop
    if not public.is_house_member(v_receipt.house_id) then
      raise exception 'Entrada de terceiros não encontrada nesta casa.';
    end if;

    perform public.move_vault_balance(
      v_receipt.vault_id,
      'deposit',
      v_receipt.amount_cents,
      'Repasse de ' || v_receipt.payer_name || ' voltou para a caixinha'
    );

    update public.third_party_receipts
    set status = 'held',
        used_mode = null,
        used_payment_method_id = null,
        used_due_date = null,
        used_at = null,
        used_by = null
    where id = v_receipt.id;
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke execute on function public.reopen_third_party_receipts(uuid[], uuid, date) from public, anon;
grant execute on function public.reopen_third_party_receipts(uuid[], uuid, date) to authenticated;

-- 4. Excluir uma entrada ainda guardada: o valor sai da caixinha
create or replace function public.delete_third_party_receipt(p_receipt_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_receipt public.third_party_receipts%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;

  select * into v_receipt
  from public.third_party_receipts
  where id = p_receipt_id
  for update;
  if not found or not public.is_house_member(v_receipt.house_id) then
    raise exception 'Entrada de terceiros não encontrada nesta casa.';
  end if;
  if v_receipt.status <> 'held' then
    raise exception 'Desfaça o uso do repasse antes de excluí-lo.';
  end if;

  perform public.move_vault_balance(
    v_receipt.vault_id,
    'withdraw',
    v_receipt.amount_cents,
    'Repasse de ' || v_receipt.payer_name || ' excluído'
  );

  delete from public.third_party_receipts where id = v_receipt.id;
end;
$$;

revoke execute on function public.delete_third_party_receipt(uuid) from public, anon;
grant execute on function public.delete_third_party_receipt(uuid) to authenticated;

-- 5. Parte da fatura paga por terceiros, no histórico da importação
alter table public.import_lines drop constraint if exists import_lines_split_destination_check;
alter table public.import_lines
  add constraint import_lines_split_destination_check
  check (split_destination in ('house', 'p2p_loan', 'personal', 'ignored', 'personal_ignored', 'third_party'));
