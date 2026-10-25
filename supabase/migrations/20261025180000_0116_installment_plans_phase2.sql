-- ==============================================================================
-- 0116: Compras parceladas, fase 2
-- Descrição:
--   A 0115 ligou as parcelas de uma fatura às da seguinte. Esta migration:
--   - dá situação ao plano (`status`): em curso, quitado por antecipação ou
--     cancelado por estorno. Plano que não está em curso não é mais projetado;
--   - aceite único do parcelamento de um morador: o devedor aceita uma vez e os
--     empréstimos mensais das parcelas seguintes já nascem aceitos.
--     `installment_plans.accepted_by` guarda quem aceitou; o plano conta como
--     aceito enquanto quem deve (`assigned_member_id`) for essa pessoa, então
--     trocar o devedor desfaz o aceite sem apagar nada. Só uma função do banco
--     grava o aceite (`accept_installment_plan` e `accept_p2p_loan`);
--   - `p2p_loans.installment_plan_ids`: as compras parceladas que formam o
--     empréstimo. O guarda da 0082 deixa o empréstimo nascer aceito quando
--     todas elas já foram aceitas pelo devedor e o valor cabe nas parcelas;
--   - aceitar o empréstimo do mês aceita também os parcelamentos dele;
--   - `confirm_import` grava a situação do plano e `undo_import` a devolve;
--   - `houses.loan_acceptance`: a casa diz, por origem, se o empréstimo
--     lançado por outra pessoa espera o aceite do devedor: lançado à mão
--     (`manual`), criado pela importação da fatura (`import`) ou do Caixa da
--     Casa lançado à mão (`house`). Chave ausente vale true (pede aceite, como
--     na 0082). A importação vale pela origem, mesmo no cartão da Casa.
-- ==============================================================================

-- 0. Aceite por origem, na casa
create or replace function public.loan_acceptance_valid(p jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p) = 'object'
    and not exists (
      select 1 from jsonb_each(p) e
      where e.key not in ('manual', 'import', 'house') or jsonb_typeof(e.value) <> 'boolean'
    )
$$;

alter table public.houses
  add column if not exists loan_acceptance jsonb not null default '{}'::jsonb
    check (public.loan_acceptance_valid(loan_acceptance));

comment on column public.houses.loan_acceptance is
  'Por origem (manual, import, house), se o empréstimo lançado por outra pessoa espera o aceite do devedor; chave ausente = true (0116).';

-- 1. Situação e aceite do plano
alter table public.installment_plans
  add column if not exists status text not null default 'active'
    check (status in ('active', 'finished', 'cancelled')),
  add column if not exists accepted_by uuid references auth.users(id) on delete set null,
  add column if not exists accepted_at timestamptz;

create index if not exists idx_installment_plans_accepted_by
  on public.installment_plans (accepted_by);

-- O aceite só é gravado pelas funções do banco (dona das tabelas). Roda com as
-- permissões de quem grava: current_user diz se veio do app.
create or replace function public.guard_installment_plan_acceptance()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user <> 'authenticated' then
    return new;
  end if;
  if TG_OP = 'INSERT' then
    new.accepted_by := null;
    new.accepted_at := null;
  elsif new.accepted_by is distinct from old.accepted_by
     or new.accepted_at is distinct from old.accepted_at then
    raise exception 'Só quem deve aceita o parcelamento.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_installment_plan_acceptance on public.installment_plans;
create trigger trg_guard_installment_plan_acceptance
  before insert or update on public.installment_plans
  for each row execute function public.guard_installment_plan_acceptance();

-- 2. Compras parceladas que formam o empréstimo do mês
alter table public.p2p_loans
  add column if not exists installment_plan_ids uuid[] not null default '{}';

-- 3. Quem lança e quem aceita (0082), com o aceite único do parcelamento
create or replace function public.guard_p2p_loan_acceptance()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_by_app boolean := current_user = 'authenticated';
  v_plans_accepted boolean := false;
  v_required boolean := true;
begin
  if TG_OP = 'INSERT' then
    -- A casa pode dispensar o aceite conforme a origem. A importação se
    -- identifica pela variável da transação que só o confirm_import liga.
    if v_by_app then
      select coalesce((h.loan_acceptance->>(
               case
                 when current_setting('omnilar.loan_origin', true) = 'import' then 'import'
                 when new.lender_is_house then 'house'
                 else 'manual'
               end))::boolean, true)
        into v_required
      from public.houses h
      where h.id = new.house_id;
    end if;

    -- Parcelas de compras que o devedor já aceitou: o empréstimo nasce aceito,
    -- desde que o valor caiba nelas (com a folga de centavos e IOF da importação)
    if v_by_app and coalesce(cardinality(new.installment_plan_ids), 0) > 0 then
      select count(*) = cardinality(new.installment_plan_ids)
             and new.total_amount_cents <= coalesce(sum(p.installment_cents * 102 / 100 + 100), 0)
        into v_plans_accepted
      from public.installment_plans p
      where p.id = any(new.installment_plan_ids)
        and p.house_id = new.house_id
        and p.status = 'active'
        and p.assigned_member_id = new.borrower_id
        and p.accepted_by = new.borrower_id;
    end if;

    if v_by_app and v_user is not null and v_user is distinct from new.borrower_id
       and coalesce(v_required, true)
       and not coalesce(v_plans_accepted, false) then
      new.awaiting_acceptance := true;
      new.accepted_at := null;
    else
      new.awaiting_acceptance := false;
      new.accepted_at := coalesce(new.accepted_at, now());
    end if;
    return new;
  end if;

  -- Ninguém além do devedor tira o empréstimo da espera pelo app
  if old.awaiting_acceptance and not new.awaiting_acceptance
     and v_by_app and v_user is distinct from new.borrower_id then
    raise exception 'Só quem deve pode aceitar o empréstimo.';
  end if;
  -- Nem volta para a espera depois de aceito
  if not old.awaiting_acceptance and new.awaiting_acceptance and v_by_app then
    raise exception 'O empréstimo já foi aceito.';
  end if;
  if old.awaiting_acceptance and not new.awaiting_acceptance then
    new.accepted_at := coalesce(new.accepted_at, now());
  end if;
  return new;
end;
$$;

-- 4. Aceitar o parcelamento (só o devedor)
create or replace function public.accept_installment_plan(p_plan_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan public.installment_plans%rowtype;
  v_user uuid := auth.uid();
begin
  select * into v_plan from public.installment_plans where id = p_plan_id for update;
  if not found or not public.is_house_member(v_plan.house_id) then
    raise exception 'Compra parcelada não encontrada.';
  end if;
  if v_plan.assigned_member_id is distinct from v_user then
    raise exception 'Só quem deve aceita o parcelamento.';
  end if;
  if v_plan.accepted_by = v_user then
    return;
  end if;

  update public.installment_plans
     set accepted_by = v_user, accepted_at = now(), updated_at = now()
   where id = p_plan_id;
end;
$$;

revoke execute on function public.accept_installment_plan(uuid) from public, anon;
grant execute on function public.accept_installment_plan(uuid) to authenticated, service_role;

-- 5. Aceitar o empréstimo (0082) aceita também as compras parceladas dele
create or replace function public.accept_p2p_loan(p_loan_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.p2p_loans%rowtype;
  v_user uuid := auth.uid();
begin
  select * into v_loan from public.p2p_loans where id = p_loan_id for update;
  if not found or not public.is_house_member(v_loan.house_id) then
    raise exception 'Empréstimo não encontrado.';
  end if;
  if v_loan.borrower_id is distinct from v_user then
    raise exception 'Só quem deve pode aceitar o empréstimo.';
  end if;

  -- As próximas parcelas destas compras já nascem aceitas
  update public.installment_plans
     set accepted_by = v_user, accepted_at = now(), updated_at = now()
   where id = any(v_loan.installment_plan_ids)
     and house_id = v_loan.house_id
     and assigned_member_id = v_user
     and accepted_by is distinct from v_user;

  if not v_loan.awaiting_acceptance then
    return;
  end if;

  update public.p2p_loans set awaiting_acceptance = false, accepted_at = now() where id = p_loan_id;

  perform public.enqueue_notification(
    v_loan.house_id,
    case when v_loan.lender_is_house then public.notification_house_admin_ids(v_loan.house_id)
         else array[v_loan.lender_id] end,
    'loan_accepted', 'emprestimos',
    'Empréstimo aceito',
    public.notification_first_name(v_user) || ' aceitou o empréstimo ' || v_loan.title || ': '
      || public.notification_brl(v_loan.total_amount_cents),
    '/pessoal/emprestimo/' || p_loan_id, 'p2p_loan', p_loan_id,
    'loan_accepted:' || p_loan_id, false
  );
end;
$$;

revoke execute on function public.accept_p2p_loan(uuid) from public, anon;
grant execute on function public.accept_p2p_loan(uuid) to authenticated, service_role;

-- 6. create_p2p_loan (0087) grava as compras parceladas do empréstimo
create or replace function public.create_p2p_loan(p_loan jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id uuid;
  v_house uuid := (p_loan->>'house_id')::uuid;
  v_funding text := nullif(p_loan->>'house_funding', '');
  v_funded_on date := (p_loan->>'funded_on')::date;
begin
  if jsonb_array_length(coalesce(p_loan->'installments', '[]'::jsonb)) = 0 then
    raise exception 'O empréstimo precisa de ao menos uma parcela.';
  end if;
  if v_funding is not null then
    if v_funding <> 'cycle' then
      raise exception 'Empréstimo de caixinha é criado por create_house_loan.';
    end if;
    if not coalesce((p_loan->>'lender_is_house')::boolean, false) then
      raise exception 'Só o Caixa da Casa empresta dinheiro do ciclo.';
    end if;
    if v_funded_on is null then
      raise exception 'Informe o dia em que o dinheiro saiu do Caixa.';
    end if;
    if public.house_date_is_closed(v_house, v_funded_on) then
      raise exception 'Este ciclo já foi fechado. Reabra o ciclo no Fechamento para tirar dinheiro do Caixa dele.';
    end if;
  end if;

  insert into public.p2p_loans (
    id, house_id, lender_id, lender_is_house, repayment_mode, settle_in_cycle,
    borrower_id, title, description, total_amount_cents, installments_count,
    status, created_by, created_at, house_funding, funded_on, installment_plan_ids
  ) values (
    coalesce((p_loan->>'id')::uuid, gen_random_uuid()),
    v_house,
    (p_loan->>'lender_id')::uuid,
    coalesce((p_loan->>'lender_is_house')::boolean, false),
    coalesce(p_loan->>'repayment_mode', 'installments'),
    coalesce((p_loan->>'settle_in_cycle')::boolean, true),
    (p_loan->>'borrower_id')::uuid,
    p_loan->>'title',
    p_loan->>'description',
    (p_loan->>'total_amount_cents')::bigint,
    coalesce((p_loan->>'installments_count')::integer, 1),
    coalesce(p_loan->>'status', 'active'),
    auth.uid(),
    coalesce((p_loan->>'created_at')::timestamptz, now()),
    v_funding,
    case when v_funding is not null then v_funded_on end,
    coalesce(
      array(
        select (value #>> '{}')::uuid
        from jsonb_array_elements(coalesce(p_loan->'installment_plan_ids', '[]'::jsonb))
      ),
      '{}'::uuid[]
    )
  )
  returning id into v_id;

  insert into public.p2p_installments (
    id, loan_id, installment_number, amount_cents, paid_cents, due_date, status, paid_at
  )
  select
    coalesce((inst->>'id')::uuid, gen_random_uuid()),
    v_id,
    (inst->>'installment_number')::integer,
    (inst->>'amount_cents')::bigint,
    coalesce((inst->>'paid_cents')::bigint, 0),
    (inst->>'due_date')::date,
    coalesce(inst->>'status', 'pending'),
    (inst->>'paid_at')::timestamptz
  from jsonb_array_elements(p_loan->'installments') as inst;

  return v_id;
end;
$$;
revoke execute on function public.create_p2p_loan(jsonb) from public, anon;
grant execute on function public.create_p2p_loan(jsonb) to authenticated;

-- 7. Confirma a importação (0115), gravando também a situação do plano
--    "installment_plans": [{..., "status"?: "active" | "finished" | "cancelled"}]
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
      'assigned_member_id', assigned_member_id, 'status', status
    ) into v_old
    from public.installment_plans
    where id = (v_item->>'id')::uuid and house_id = v_house_id;
    if v_old is not null then
      v_previous := v_previous || jsonb_build_array(v_old);
    end if;

    insert into public.installment_plans (
      id, house_id, payment_method_id, merchant_key, title, installments_total,
      installment_cents, anchor_number, anchor_line_date, anchor_due_date, destination,
      category_id, assigned_member_id, created_batch_id, status
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
      v_batch_id,
      coalesce(v_item->>'status', 'active')
    )
    on conflict (id) do update
      set destination = excluded.destination,
          category_id = excluded.category_id,
          assigned_member_id = excluded.assigned_member_id,
          status = excluded.status,
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

  -- Os empréstimos daqui contam como vindos da importação (aceite por origem)
  perform set_config('omnilar.loan_origin', 'import', true);
  for v_item in select * from jsonb_array_elements(coalesce(p_import->'loans', '[]'::jsonb)) loop
    if (v_item->>'house_id')::uuid is distinct from v_house_id then
      raise exception 'A importação tem um empréstimo de outra casa.';
    end if;
    perform public.create_p2p_loan(v_item);
  end loop;
  perform set_config('omnilar.loan_origin', '', true);

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

  -- Prevista que a fatura trouxe com outro destino, quitou ou cancelou:
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

-- 8. Desfaz uma importação (0115), devolvendo também a situação do plano
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

  -- Os planos voltam ao destino, categoria, devedor e situação de antes
  update public.installment_plans p
  set destination = x.destination,
      category_id = x.category_id,
      assigned_member_id = x.assigned_member_id,
      status = coalesce(x.status, p.status),
      updated_at = now()
  from jsonb_to_recordset(coalesce(v_previous, '[]'::jsonb))
    as x(id uuid, destination text, category_id uuid, assigned_member_id uuid, status text)
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

-- 9. update_house_settings (0104) com o aceite por origem
create or replace function public.update_house_settings(p_house_id uuid, p_settings jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.houses%rowtype;
begin
  if auth.uid() is null or not public.is_house_member(p_house_id) then
    raise exception 'Você não faz parte desta casa.';
  end if;
  if (p_settings ? 'opening_balance_rule' or p_settings ? 'opening_inflow_rules')
      and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam como a sobra entra no rateio.';
  end if;
  if p_settings ? 'opening_inflow_rules'
      and not public.opening_inflow_rules_valid(p_settings->'opening_inflow_rules') then
    raise exception 'Regra das entradas no Caixa inválida.';
  end if;
  if p_settings ? 'closing_defaults' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam os padrões do fechamento.';
  end if;
  if p_settings ? 'closing_defaults'
      and not public.closing_defaults_valid(p_settings->'closing_defaults') then
    raise exception 'Padrões do fechamento inválidos.';
  end if;
  if p_settings ? 'new_member_split_policy' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam a divisão para quem entra na casa.';
  end if;
  if p_settings ? 'new_member_split_policy'
      and coalesce(p_settings->>'new_member_split_policy', '') not in ('equal', 'keep_current', 'ask') then
    raise exception 'Política de divisão para novo morador inválida.';
  end if;

  if p_settings ? 'folego_params' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam os parâmetros do Fôlego.';
  end if;
  if p_settings ? 'folego_params' and not public.folego_params_valid(p_settings->'folego_params') then
    raise exception 'Parâmetros do Fôlego inválidos.';
  end if;

  if p_settings ? 'budget_alert_stages' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam os estágios do alerta de orçamento.';
  end if;
  if p_settings ? 'budget_alert_stages'
      and not public.budget_alert_stages_valid(p_settings->'budget_alert_stages') then
    raise exception 'Estágios do alerta de orçamento inválidos.';
  end if;

  if p_settings ? 'import_matching' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam as janelas de casamento da importação.';
  end if;
  if p_settings ? 'import_matching' and not public.import_matching_valid(p_settings->'import_matching') then
    raise exception 'Janelas de casamento da importação inválidas.';
  end if;

  if p_settings ? 'import_defaults' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam o destino padrão da importação.';
  end if;
  if p_settings ? 'import_defaults' and not public.import_defaults_valid(p_settings->'import_defaults') then
    raise exception 'Destino padrão da importação inválido.';
  end if;

  if p_settings ? 'cash_label' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam o nome do Caixa.';
  end if;
  if p_settings ? 'cash_label' and not public.cash_label_valid(p_settings->'cash_label') then
    raise exception 'Nome do Caixa inválido.';
  end if;

  if p_settings ? 'shopping_units' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam as unidades de compra.';
  end if;
  if p_settings ? 'shopping_units' and not public.shopping_units_valid(p_settings->'shopping_units') then
    raise exception 'Unidades de compra inválidas.';
  end if;

  if p_settings ? 'income_visibility' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam quem vê a renda dos moradores.';
  end if;
  if p_settings ? 'income_visibility'
      and coalesce(p_settings->>'income_visibility', '') not in ('all', 'admins', 'self') then
    raise exception 'Visibilidade da renda inválida.';
  end if;

  if p_settings ? 'split_basis' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam a base da divisão padrão.';
  end if;
  if p_settings ? 'split_basis'
      and coalesce(p_settings->>'split_basis', '') not in ('manual', 'income') then
    raise exception 'Base da divisão padrão inválida.';
  end if;

  if p_settings ? 'permissions' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam quem pode fazer cada ação.';
  end if;
  if p_settings ? 'permissions' and not public.house_permissions_valid(p_settings->'permissions') then
    raise exception 'Permissões inválidas.';
  end if;

  if p_settings ? 'approval_threshold_cents' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam o limite de aprovação por valor.';
  end if;
  if p_settings ? 'approval_threshold_cents'
      and jsonb_typeof(p_settings->'approval_threshold_cents') <> 'null'
      and (
        jsonb_typeof(p_settings->'approval_threshold_cents') <> 'number'
        or (p_settings->>'approval_threshold_cents')::numeric <= 0
        or (p_settings->>'approval_threshold_cents')::numeric > 100000000000
        or (p_settings->>'approval_threshold_cents')::numeric <> trunc((p_settings->>'approval_threshold_cents')::numeric)
      ) then
    raise exception 'Limite de aprovação por valor inválido.';
  end if;

  if p_settings ? 'loan_acceptance' and not public.has_house_permission(p_house_id, 'editar_configuracoes') then
    raise exception 'Só administradores mudam quando o empréstimo pede aceite.';
  end if;
  if p_settings ? 'loan_acceptance' and not public.loan_acceptance_valid(p_settings->'loan_acceptance') then
    raise exception 'Aceite dos empréstimos inválido.';
  end if;

  update public.houses set
    opening_balance_rule = case when p_settings ? 'opening_balance_rule'
      then nullif(p_settings->>'opening_balance_rule', '') else opening_balance_rule end,
    opening_inflow_rules = coalesce(p_settings->'opening_inflow_rules', opening_inflow_rules),
    closing_defaults = coalesce(p_settings->'closing_defaults', closing_defaults),
    new_member_split_policy = coalesce(p_settings->>'new_member_split_policy', new_member_split_policy),
    folego_params = coalesce(p_settings->'folego_params', folego_params),
    budget_alert_stages = coalesce(p_settings->'budget_alert_stages', budget_alert_stages),
    import_matching = coalesce(p_settings->'import_matching', import_matching),
    import_defaults = coalesce(p_settings->'import_defaults', import_defaults),
    cash_label = case when p_settings ? 'cash_label'
      then nullif(btrim(p_settings->>'cash_label'), '') else cash_label end,
    shopping_units = coalesce(p_settings->'shopping_units', shopping_units),
    income_visibility = coalesce(p_settings->>'income_visibility', income_visibility),
    split_basis = coalesce(p_settings->>'split_basis', split_basis),
    planner_history_cycles = coalesce((p_settings->>'planner_history_cycles')::smallint, planner_history_cycles),
    planner_mode = coalesce(p_settings->>'planner_mode', planner_mode),
    planner_adjust_percent = coalesce((p_settings->>'planner_adjust_percent')::smallint, planner_adjust_percent),
    planner_category_overrides = coalesce(p_settings->'planner_category_overrides', planner_category_overrides),
    permissions = coalesce(p_settings->'permissions', permissions),
    approval_threshold_cents = case when p_settings ? 'approval_threshold_cents'
      then (p_settings->>'approval_threshold_cents')::bigint else approval_threshold_cents end,
    loan_acceptance = coalesce(p_settings->'loan_acceptance', loan_acceptance)
  where id = p_house_id
  returning * into v_row;

  -- Base "renda": recalcula o rateio padrão já com as rendas informadas
  if p_settings ? 'split_basis' and v_row.split_basis = 'income' then
    perform public.apply_income_split(p_house_id);
  end if;

  return jsonb_build_object(
    'opening_balance_rule', v_row.opening_balance_rule,
    'opening_inflow_rules', v_row.opening_inflow_rules,
    'closing_defaults', v_row.closing_defaults,
    'new_member_split_policy', v_row.new_member_split_policy,
    'folego_params', v_row.folego_params,
    'budget_alert_stages', v_row.budget_alert_stages,
    'import_matching', v_row.import_matching,
    'import_defaults', v_row.import_defaults,
    'cash_label', v_row.cash_label,
    'shopping_units', v_row.shopping_units,
    'income_visibility', v_row.income_visibility,
    'split_basis', v_row.split_basis,
    'planner_history_cycles', v_row.planner_history_cycles,
    'planner_mode', v_row.planner_mode,
    'planner_adjust_percent', v_row.planner_adjust_percent,
    'planner_category_overrides', v_row.planner_category_overrides,
    'permissions', v_row.permissions,
    'approval_threshold_cents', v_row.approval_threshold_cents,
    'loan_acceptance', v_row.loan_acceptance
  );
end;
$$;

revoke execute on function public.update_house_settings(uuid, jsonb) from public, anon;
grant execute on function public.update_house_settings(uuid, jsonb) to authenticated, service_role;

notify pgrst, 'reload schema';
