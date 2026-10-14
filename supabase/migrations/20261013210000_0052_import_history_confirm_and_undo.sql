-- ==============================================================================
-- 0052: Histórico da importação de fatura, confirmação atômica e desfazer
-- Descrição:
--   A importação de fatura e extrato gravava cada despesa e cada empréstimo em
--   uma chamada separada e não guardava nada sobre o arquivo. Uma falha no meio
--   deixava a fatura lançada pela metade, importar o mesmo arquivo de novo
--   dependia só de comparar valores e não havia como desfazer.
--
--   Agora:
--   - `import_batches` e `import_lines` (criadas na 0004 e nunca usadas) guardam
--     cada importação confirmada, com o que cada linha virou;
--   - `confirm_import` grava despesas, empréstimos, correções e o registro da
--     importação em uma transação: ou tudo, ou nada;
--   - `undo_import` exclui o que a importação criou e marca o lote como desfeito;
--   - cada linha tem uma assinatura, para o app reconhecer o que já foi importado.
--
--   As duas funções rodam com as permissões de quem chama (security invoker):
--   as regras de acesso e as travas de ciclo fechado continuam valendo.
-- ==============================================================================

-- 1. Lote da importação
alter table public.import_batches
  add column if not exists payment_method_id uuid references public.payment_methods(id) on delete set null,
  add column if not exists file_name text,
  add column if not exists invoice_due_date date,
  add column if not exists payer_id uuid references auth.users(id) on delete set null,
  add column if not exists status text not null default 'confirmed',
  add column if not exists undone_at timestamptz,
  add column if not exists undone_by uuid references auth.users(id) on delete set null;

alter table public.import_batches drop constraint if exists import_batches_status_check;
alter table public.import_batches
  add constraint import_batches_status_check check (status in ('confirmed', 'undone'));

create index if not exists idx_import_batches_payment_method
  on public.import_batches (payment_method_id);

-- Desfazer muda o status do lote
drop policy if exists "import_batches_update_house_member" on public.import_batches;
create policy "import_batches_update_house_member" on public.import_batches
  for update using (public.is_house_member(house_id))
  with check (public.is_house_member(house_id));

-- 2. Linhas: o que cada uma é e o que virou
alter table public.import_lines
  add column if not exists kind text not null default 'purchase',
  add column if not exists external_id text,
  add column if not exists signature text,
  add column if not exists title text,
  add column if not exists decision text not null default 'ignored',
  add column if not exists expense_id uuid references public.house_expenses(id) on delete set null,
  add column if not exists loan_id uuid references public.p2p_loans(id) on delete set null;

alter table public.import_lines drop constraint if exists import_lines_kind_check;
alter table public.import_lines
  add constraint import_lines_kind_check check (kind in ('purchase', 'refund', 'payment', 'income'));

-- created: a importação criou a despesa ou o empréstimo; linked: já existia no
-- app; ignored: pessoal, ignorada ou só informativa; skipped: ficou de fora por
-- cair em ciclo fechado (pode ser importada de novo depois de reabrir o ciclo).
alter table public.import_lines drop constraint if exists import_lines_decision_check;
alter table public.import_lines
  add constraint import_lines_decision_check check (decision in ('created', 'linked', 'ignored', 'skipped'));

alter table public.import_lines drop constraint if exists import_lines_split_destination_check;
alter table public.import_lines
  add constraint import_lines_split_destination_check
  check (split_destination in ('house', 'p2p_loan', 'personal', 'ignored', 'personal_ignored'));

create index if not exists idx_import_lines_signature
  on public.import_lines (house_id, signature);

-- 3. Confirma a importação. Devolve o id do lote.
--    p_import = {
--      "batch": {...}, "lines": [...],
--      "expenses": [payload de create_house_expense],
--      "loans": [payload de create_p2p_loan],
--      "expense_updates": [{"id", "amount_cents"?, "payment_method_id"?, "paid_by_id"?,
--                           "paid_out_of_pocket"?, "due_date"?, "split_rules"?}]
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
  v_batch_id uuid;
  v_item jsonb;
begin
  if v_house_id is null or not public.is_house_member(v_house_id) then
    raise exception 'Acesso negado: você não é membro desta casa.';
  end if;

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

  insert into public.import_batches (
    id, house_id, source_type, account_name, payment_method_id, file_name, invoice_due_date,
    payer_id, total_cents, lines_count, is_reconciled, status, created_by
  ) values (
    coalesce((v_batch->>'id')::uuid, gen_random_uuid()),
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
    auth.uid()
  )
  returning id into v_batch_id;

  insert into public.import_lines (
    batch_id, house_id, line_date, description, amount_cents, kind, external_id, signature,
    title, split_destination, category_id, assigned_member_id, decision, expense_id, loan_id,
    is_confirmed
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
    true
  from jsonb_array_elements(coalesce(p_import->'lines', '[]'::jsonb)) as line;

  return v_batch_id;
end;
$$;

-- 4. Desfaz uma importação: exclui as despesas e os empréstimos que ela criou.
--    As correções feitas em despesas que já existiam não são revertidas.
create or replace function public.undo_import(p_batch_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_house_id uuid;
  v_status text;
  v_expense_id uuid;
  v_loans uuid[];
  v_deleted integer;
begin
  select house_id, status into v_house_id, v_status
  from public.import_batches
  where id = p_batch_id
  for update;

  if v_house_id is null then
    raise exception 'Importação não encontrada.';
  end if;
  if v_status = 'undone' then
    raise exception 'Esta importação já foi desfeita.';
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

  update public.import_batches
  set status = 'undone', undone_at = now(), undone_by = auth.uid()
  where id = p_batch_id;
end;
$$;

revoke execute on function public.confirm_import(jsonb) from public, anon;
revoke execute on function public.undo_import(uuid) from public, anon;
grant execute on function public.confirm_import(jsonb) to authenticated;
grant execute on function public.undo_import(uuid) to authenticated;
