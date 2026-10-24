-- ==============================================================================
-- 0115: Compras parceladas na importação de fatura
-- Descrição:
--   A fatura traz a parcela da compra ("MAGALU 03/10"), mas a importação só
--   punha "(3/10)" no título: cada fatura lançava a parcela do mês e nada
--   ligava uma parcela à outra. Agora:
--   - `installment_plans` guarda cada compra parcelada de um cartão: o lugar,
--     o número de parcelas, o valor da parcela e o que a casa decidiu sobre ela
--     (destino, categoria e devedor), para a fatura seguinte já vir assim;
--   - a despesa de cada parcela aponta para o plano e diz qual parcela é
--     (`installment_number`). Na primeira fatura a importação cria a parcela
--     do mês e as seguintes como previstas (`is_forecast`); as faturas
--     seguintes só confirmam as previstas;
--   - o índice único por plano e parcela impede a mesma parcela de ser
--     lançada duas vezes, mesmo se o app errar o casamento;
--   - `confirm_import` grava planos, vínculos e as previstas que deixam de
--     existir, na mesma transação;
--   - `undo_import` apaga as previstas e o plano que a importação criou, volta
--     a prever as parcelas que ela tinha confirmado e traz de volta as previstas
--     que ela tirou da casa. Só desfaz a importação mais recente de cada
--     compra parcelada, para uma fatura não desmanchar a seguinte.
-- ==============================================================================

-- 1. Plano de parcelamento
create table if not exists public.installment_plans (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  payment_method_id uuid not null references public.payment_methods(id) on delete cascade,
  -- Nome do estabelecimento sem acento, número de loja nem parcela
  merchant_key text not null check (length(merchant_key) > 0),
  title text not null,
  installments_total integer not null check (installments_total between 2 and 99),
  installment_cents bigint not null check (installment_cents > 0),
  -- Parcela e datas da fatura em que o plano nasceu: a partir delas o app
  -- sabe em que fatura cai cada parcela
  anchor_number integer not null check (anchor_number between 1 and 99),
  anchor_line_date date not null,
  anchor_due_date date,
  destination text not null default 'house'
    check (destination in ('house', 'p2p_loan', 'personal', 'ignored', 'third_party')),
  category_id uuid references public.categories(id) on delete set null,
  assigned_member_id uuid references auth.users(id) on delete set null,
  created_batch_id uuid references public.import_batches(id) on delete set null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (anchor_number <= installments_total)
);

create index if not exists idx_installment_plans_payment_method
  on public.installment_plans (payment_method_id);
create index if not exists idx_installment_plans_house
  on public.installment_plans (house_id);
create index if not exists idx_installment_plans_created_batch
  on public.installment_plans (created_batch_id);
create index if not exists idx_installment_plans_category
  on public.installment_plans (category_id);
create index if not exists idx_installment_plans_assigned_member
  on public.installment_plans (assigned_member_id);
create index if not exists idx_installment_plans_created_by
  on public.installment_plans (created_by);

alter table public.installment_plans enable row level security;

drop policy if exists "installment_plans_select_house_member" on public.installment_plans;
create policy "installment_plans_select_house_member" on public.installment_plans
  for select using (public.is_house_member(house_id));

drop policy if exists "installment_plans_insert_house_member" on public.installment_plans;
create policy "installment_plans_insert_house_member" on public.installment_plans
  for insert with check (public.is_house_member(house_id));

drop policy if exists "installment_plans_update_house_member" on public.installment_plans;
create policy "installment_plans_update_house_member" on public.installment_plans
  for update using (public.is_house_member(house_id))
  with check (public.is_house_member(house_id));

drop policy if exists "installment_plans_delete_house_member" on public.installment_plans;
create policy "installment_plans_delete_house_member" on public.installment_plans
  for delete using (public.is_house_member(house_id));

revoke all on public.installment_plans from anon;
grant select, insert, update, delete on public.installment_plans to authenticated;

-- 2. Parcela na despesa e na linha importada
alter table public.house_expenses
  add column if not exists installment_plan_id uuid references public.installment_plans(id) on delete set null,
  add column if not exists installment_number integer check (installment_number between 1 and 99),
  add column if not exists is_forecast boolean not null default false;

-- Uma despesa por parcela de cada plano
create unique index if not exists uq_house_expenses_installment
  on public.house_expenses (installment_plan_id, installment_number)
  where installment_plan_id is not null and deleted_at is null;

alter table public.import_lines
  add column if not exists installment_plan_id uuid references public.installment_plans(id) on delete set null,
  add column if not exists installment_number integer;

create index if not exists idx_import_lines_installment_plan
  on public.import_lines (installment_plan_id);

-- Previstas que a importação tirou da casa, para o desfazer trazê-las de volta
alter table public.import_batches
  add column if not exists replaced_forecast_ids uuid[] not null default '{}',
  -- O que a casa tinha decidido nos planos antes desta importação
  add column if not exists previous_plan_states jsonb not null default '[]'::jsonb;

-- 3. Confirma a importação. Devolve o id do lote.
--    p_import = {
--      "batch": {...}, "lines": [...],
--      "expenses": [payload de create_house_expense],
--      "loans": [payload de create_p2p_loan],
--      "expense_updates": [{"id", "amount_cents"?, "payment_method_id"?, "paid_by_id"?,
--                           "paid_out_of_pocket"?, "due_date"?, "split_rules"?}],
--      "installment_plans": [{"id", "payment_method_id", "merchant_key", "title",
--                             "installments_total", "installment_cents", "anchor_number",
--                             "anchor_line_date", "anchor_due_date"?, "destination",
--                             "category_id"?, "assigned_member_id"?}],
--      "installment_links": [{"expense_id", "plan_id", "number", "is_forecast"}],
--      "forecast_deletions": [id da despesa prevista que a fatura substituiu]
--    }
create or replace function public.confirm_import(p_import jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_batch jsonb := p_import->'batch';
  v_house_id uuid := (p_import->'batch'->>'house_id')::uuid;
  v_batch_id uuid := coalesce((p_import->'batch'->>'id')::uuid, gen_random_uuid());
  v_item jsonb;
  v_expense_id uuid;
  v_previous jsonb := '[]'::jsonb;
  v_old jsonb;
begin
  if v_house_id is null or not public.is_house_member(v_house_id) then
    raise exception 'Acesso negado: você não é membro desta casa.';
  end if;

  -- O lote vem antes: o plano de parcelamento aponta para a importação que o criou
  insert into public.import_batches (
    id, house_id, source_type, account_name, payment_method_id, file_name, invoice_due_date,
    payer_id, total_cents, lines_count, is_reconciled, status, created_by, replaced_forecast_ids
  ) values (
    v_batch_id,
    v_house_id,
    v_batch->>'source_type',
    v_batch->>'account_name',
    (v_batch->>'payment_method_id')::uuid,
    v_batch->>'file_name',
    (v_batch->>'invoice_due_date')::date,
    (v_batch->>'payer_id')::uuid,
    coalesce((v_batch->>'total_cents')::bigint, 0),
    jsonb_array_length(coalesce(p_import->'lines', '[]'::jsonb)),
    true,
    'confirmed',
    auth.uid(),
    coalesce(
      array(
        select (value #>> '{}')::uuid
        from jsonb_array_elements(coalesce(p_import->'forecast_deletions', '[]'::jsonb))
      ),
      '{}'::uuid[]
    )
  );

  -- Planos novos nascem; nos que já existiam só muda o que a casa decidiu
  for v_item in select * from jsonb_array_elements(coalesce(p_import->'installment_plans', '[]'::jsonb)) loop
    select jsonb_build_object(
      'id', id, 'destination', destination, 'category_id', category_id,
      'assigned_member_id', assigned_member_id
    ) into v_old
    from public.installment_plans
    where id = (v_item->>'id')::uuid and house_id = v_house_id;
    if v_old is not null then
      v_previous := v_previous || jsonb_build_array(v_old);
    end if;

    insert into public.installment_plans (
      id, house_id, payment_method_id, merchant_key, title, installments_total,
      installment_cents, anchor_number, anchor_line_date, anchor_due_date, destination,
      category_id, assigned_member_id, created_batch_id
    ) values (
      (v_item->>'id')::uuid,
      v_house_id,
      (v_item->>'payment_method_id')::uuid,
      v_item->>'merchant_key',
      v_item->>'title',
      (v_item->>'installments_total')::integer,
      (v_item->>'installment_cents')::bigint,
      (v_item->>'anchor_number')::integer,
      (v_item->>'anchor_line_date')::date,
      (v_item->>'anchor_due_date')::date,
      coalesce(v_item->>'destination', 'house'),
      (v_item->>'category_id')::uuid,
      (v_item->>'assigned_member_id')::uuid,
      v_batch_id
    )
    on conflict (id) do update
      set destination = excluded.destination,
          category_id = excluded.category_id,
          assigned_member_id = excluded.assigned_member_id,
          updated_at = now()
      where public.installment_plans.house_id = v_house_id;
  end loop;

  update public.import_batches set previous_plan_states = v_previous where id = v_batch_id;

  for v_item in select * from jsonb_array_elements(coalesce(p_import->'expenses', '[]'::jsonb)) loop
    if (v_item->>'house_id')::uuid is distinct from v_house_id then
      raise exception 'A importação tem uma despesa de outra casa.';
    end if;
    perform public.create_house_expense(v_item);
  end loop;

  for v_item in select * from jsonb_array_elements(coalesce(p_import->'loans', '[]'::jsonb)) loop
    if (v_item->>'house_id')::uuid is distinct from v_house_id then
      raise exception 'A importação tem um empréstimo de outra casa.';
    end if;
    perform public.create_p2p_loan(v_item);
  end loop;

  -- Despesa que já existia e a fatura corrige (valor real, cartão, vencimento)
  for v_item in select * from jsonb_array_elements(coalesce(p_import->'expense_updates', '[]'::jsonb)) loop
    update public.house_expenses
    set amount_cents = coalesce((v_item->>'amount_cents')::bigint, amount_cents),
        payment_method_id = coalesce((v_item->>'payment_method_id')::uuid, payment_method_id),
        paid_by_id = coalesce((v_item->>'paid_by_id')::uuid, paid_by_id),
        paid_out_of_pocket = coalesce((v_item->>'paid_out_of_pocket')::boolean, paid_out_of_pocket),
        due_date = coalesce((v_item->>'due_date')::date, due_date)
    where id = (v_item->>'id')::uuid and house_id = v_house_id;

    if not found then
      raise exception 'Uma despesa que a importação ia corrigir não existe mais. Abra a importação de novo.';
    end if;

    -- Valor novo: o rateio gravado é recalculado pelo app
    if jsonb_typeof(v_item->'split_rules') = 'array' then
      delete from public.split_rules where expense_id = (v_item->>'id')::uuid;
      insert into public.split_rules (
        expense_id, member_id, percentage_basis_points, fixed_amount_cents, calculated_cents
      )
      select
        (v_item->>'id')::uuid,
        (rule->>'member_id')::uuid,
        (rule->>'percentage_basis_points')::integer,
        (rule->>'fixed_amount_cents')::bigint,
        (rule->>'calculated_cents')::bigint
      from jsonb_array_elements(v_item->'split_rules') as rule;
    end if;
  end loop;

  -- Prevista que a fatura trouxe com outro destino (empréstimo, pessoal):
  -- deixa de ser despesa da casa
  for v_expense_id in
    select (value #>> '{}')::uuid
    from jsonb_array_elements(coalesce(p_import->'forecast_deletions', '[]'::jsonb))
  loop
    if not exists (
      select 1 from public.house_expenses
      where id = v_expense_id and house_id = v_house_id and is_forecast and deleted_at is null
    ) then
      raise exception 'Uma parcela prevista que a importação ia substituir não existe mais. Abra a importação de novo.';
    end if;
    perform public.delete_house_expense(v_expense_id, 'thisInstanceOnly');
  end loop;

  -- Cada despesa de parcela aponta para o plano; a confirmada deixa de ser prevista
  begin
    for v_item in select * from jsonb_array_elements(coalesce(p_import->'installment_links', '[]'::jsonb)) loop
      update public.house_expenses
      set installment_plan_id = (v_item->>'plan_id')::uuid,
          installment_number = (v_item->>'number')::integer,
          is_forecast = coalesce((v_item->>'is_forecast')::boolean, false)
      where id = (v_item->>'expense_id')::uuid and house_id = v_house_id and deleted_at is null;

      if not found then
        raise exception 'Uma parcela que a importação ia confirmar não existe mais. Abra a importação de novo.';
      end if;
    end loop;
  exception when unique_violation then
    raise exception 'Uma parcela desta fatura já está lançada no app. Abra a importação de novo.';
  end;

  insert into public.import_lines (
    batch_id, house_id, line_date, description, amount_cents, kind, external_id, signature,
    title, split_destination, category_id, assigned_member_id, decision, expense_id, loan_id,
    installment_plan_id, installment_number, is_confirmed
  )
  select
    v_batch_id,
    v_house_id,
    (line->>'line_date')::date,
    line->>'description',
    (line->>'amount_cents')::bigint,
    coalesce(line->>'kind', 'purchase'),
    line->>'external_id',
    line->>'signature',
    line->>'title',
    coalesce(line->>'split_destination', 'ignored'),
    (line->>'category_id')::uuid,
    (line->>'assigned_member_id')::uuid,
    coalesce(line->>'decision', 'ignored'),
    (line->>'expense_id')::uuid,
    (line->>'loan_id')::uuid,
    (line->>'installment_plan_id')::uuid,
    (line->>'installment_number')::integer,
    true
  from jsonb_array_elements(coalesce(p_import->'lines', '[]'::jsonb)) as line;

  return v_batch_id;
end;
$$;

-- 4. Traz de volta as previstas que uma importação desfeita tinha tirado da
--    casa. A despesa excluída some para o RLS de quem chama, então isto roda
--    como dona das tabelas: só para lote já desfeito, e uma vez só.
create or replace function public.restore_replaced_forecasts(p_batch_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_house_id uuid;
  v_status text;
  v_ids uuid[];
begin
  select house_id, status, replaced_forecast_ids into v_house_id, v_status, v_ids
  from public.import_batches
  where id = p_batch_id
  for update;

  if v_house_id is null or not public.is_house_member(v_house_id) then
    raise exception 'Importação não encontrada.';
  end if;
  if v_status <> 'undone' or coalesce(cardinality(v_ids), 0) = 0 then
    return;
  end if;

  update public.house_expenses
  set deleted_at = null
  where id = any(v_ids)
    and house_id = v_house_id
    and is_forecast
    and deleted_at is not null
    and settled_at is null;

  update public.import_batches set replaced_forecast_ids = '{}' where id = p_batch_id;
end;
$$;

revoke execute on function public.restore_replaced_forecasts(uuid) from public, anon;
grant execute on function public.restore_replaced_forecasts(uuid) to authenticated;

-- 5. Desfaz uma importação (a da 0055, mais as parcelas)
create or replace function public.undo_import(p_batch_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_house_id uuid;
  v_status text;
  v_house_paid_at timestamptz;
  v_expense_id uuid;
  v_loans uuid[];
  v_plans uuid[];
  v_touched uuid[];
  v_previous jsonb;
  v_created_at timestamptz;
  v_deleted integer;
begin
  select house_id, status, house_paid_at, created_at, previous_plan_states
    into v_house_id, v_status, v_house_paid_at, v_created_at, v_previous
  from public.import_batches
  where id = p_batch_id
  for update;

  if v_house_id is null then
    raise exception 'Importação não encontrada.';
  end if;
  if v_status = 'undone' then
    raise exception 'Esta importação já foi desfeita.';
  end if;
  if v_house_paid_at is not null then
    raise exception 'Esta fatura foi paga pelo Caixa da Casa. Desfaça antes o pagamento da fatura.';
  end if;

  select array_agg(id) into v_plans
  from public.installment_plans
  where created_batch_id = p_batch_id;

  select array_agg(distinct installment_plan_id) into v_touched
  from public.import_lines
  where batch_id = p_batch_id and installment_plan_id is not null;

  -- Compra parcelada que uma fatura importada depois já usou: desfazer esta
  -- desmancharia as parcelas daquela
  if v_touched is not null and exists (
    select 1
    from public.import_lines l
    join public.import_batches b on b.id = l.batch_id
    where l.installment_plan_id = any(v_touched)
      and l.batch_id <> p_batch_id
      and b.status = 'confirmed'
      and b.created_at >= v_created_at
  ) then
    raise exception 'Uma fatura importada depois desta já usa uma das compras parceladas dela. Desfaça antes a importação mais recente.';
  end if;

  -- Parcela que esta fatura confirmou num plano mais antigo volta a ser prevista
  update public.house_expenses e
  set is_forecast = true
  from public.import_lines l
  where l.batch_id = p_batch_id
    and l.decision = 'linked'
    and l.installment_plan_id is not null
    and l.expense_id = e.id
    and e.installment_plan_id = l.installment_plan_id
    and not (l.installment_plan_id = any(coalesce(v_plans, '{}'::uuid[])));

  -- Os planos voltam ao destino, categoria e devedor de antes
  update public.installment_plans p
  set destination = x.destination,
      category_id = x.category_id,
      assigned_member_id = x.assigned_member_id,
      updated_at = now()
  from jsonb_to_recordset(coalesce(v_previous, '[]'::jsonb))
    as x(id uuid, destination text, category_id uuid, assigned_member_id uuid)
  where p.id = x.id and p.house_id = v_house_id;

  -- Previstas dos planos que esta importação criou
  if v_plans is not null then
    for v_expense_id in
      select id from public.house_expenses
      where installment_plan_id = any(v_plans) and is_forecast and deleted_at is null
    loop
      perform public.delete_house_expense(v_expense_id, 'thisInstanceOnly');
    end loop;
  end if;

  -- Recusa despesa já acertada em um fechamento (a mensagem vem da função)
  for v_expense_id in
    select l.expense_id
    from public.import_lines l
    join public.house_expenses e on e.id = l.expense_id
    where l.batch_id = p_batch_id and l.decision = 'created' and e.deleted_at is null
  loop
    perform public.delete_house_expense(v_expense_id, 'thisInstanceOnly');
  end loop;

  select array_agg(distinct l.loan_id) into v_loans
  from public.import_lines l
  join public.p2p_loans p on p.id = l.loan_id
  where l.batch_id = p_batch_id and l.decision = 'created';

  if v_loans is not null then
    with deleted as (
      delete from public.p2p_loans where id = any(v_loans) returning id
    )
    select count(*) into v_deleted from deleted;

    -- A regra de acesso não dá erro: só deixa de apagar
    if v_deleted <> array_length(v_loans, 1) then
      raise exception 'Um empréstimo desta importação já teve pagamento ou não é seu. Só quem emprestou (ou um administrador) desfaz, e apenas enquanto nada foi pago.';
    end if;
  end if;

  if v_plans is not null then
    delete from public.installment_plans where id = any(v_plans);
  end if;

  update public.import_batches
  set status = 'undone', undone_at = now(), undone_by = auth.uid()
  where id = p_batch_id;

  -- Previstas que esta importação tirou da casa voltam a existir
  perform public.restore_replaced_forecasts(p_batch_id);
end;
$$;

revoke execute on function public.confirm_import(jsonb) from public, anon;
revoke execute on function public.undo_import(uuid) from public, anon;
grant execute on function public.confirm_import(jsonb) to authenticated;
grant execute on function public.undo_import(uuid) to authenticated;
