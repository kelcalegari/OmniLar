-- ==============================================================================
-- 0042: Lançar despesa, criar empréstimo e fechar compra em uma transação
-- Descrição:
--   O app gravava cada parte em uma chamada separada: despesa, sub-itens e
--   rateio; empréstimo e parcelas; e, ao fechar a compra do mercado, despesa,
--   empréstimo, viagem e limpeza da lista. Uma falha no meio deixava a ação
--   pela metade (despesa lançada com a lista ainda cheia, empréstimo sem
--   parcelas). Agora cada ação é uma função: ou grava tudo, ou nada.
--
--   As funções rodam com as permissões de quem chama (security invoker): as
--   regras de acesso das tabelas continuam valendo exatamente como antes.
-- ==============================================================================

-- Despesa da casa com sub-itens e rateio. Devolve o id da despesa.
create or replace function public.create_house_expense(p_expense jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.house_expenses (
    id, house_id, title, amount_cents, category_id, payment_method_id, paid_by_id,
    paid_out_of_pocket, due_date, date, cycle_start_date, split_type, status, paid_at,
    is_recurring, is_variable, due_day, is_active, recurring_series_id, project_id,
    notes, created_by
  ) values (
    coalesce((p_expense->>'id')::uuid, gen_random_uuid()),
    (p_expense->>'house_id')::uuid,
    p_expense->>'title',
    (p_expense->>'amount_cents')::bigint,
    (p_expense->>'category_id')::uuid,
    (p_expense->>'payment_method_id')::uuid,
    (p_expense->>'paid_by_id')::uuid,
    coalesce((p_expense->>'paid_out_of_pocket')::boolean, false),
    (p_expense->>'due_date')::date,
    coalesce((p_expense->>'date')::timestamptz, now()),
    coalesce((p_expense->>'cycle_start_date')::date, (p_expense->>'due_date')::date),
    coalesce(p_expense->>'split_type', 'percentage'),
    coalesce(p_expense->>'status', 'pending'),
    (p_expense->>'paid_at')::timestamptz,
    coalesce((p_expense->>'is_recurring')::boolean, false),
    coalesce((p_expense->>'is_variable')::boolean, false),
    (p_expense->>'due_day')::smallint,
    coalesce((p_expense->>'is_active')::boolean, true),
    (p_expense->>'recurring_series_id')::uuid,
    (p_expense->>'project_id')::uuid,
    p_expense->>'notes',
    auth.uid()
  )
  returning id into v_id;

  insert into public.house_expense_items (
    id, expense_id, title, amount_cents, category_id, responsible_member_id, split_type
  )
  select
    coalesce((item->>'id')::uuid, gen_random_uuid()),
    v_id,
    item->>'title',
    (item->>'amount_cents')::bigint,
    (item->>'category_id')::uuid,
    (item->>'responsible_member_id')::uuid,
    item->>'split_type'
  from jsonb_array_elements(coalesce(p_expense->'items', '[]'::jsonb)) as item;

  insert into public.split_rules (
    expense_id, member_id, percentage_basis_points, fixed_amount_cents, calculated_cents
  )
  select
    v_id,
    (rule->>'member_id')::uuid,
    (rule->>'percentage_basis_points')::integer,
    (rule->>'fixed_amount_cents')::bigint,
    (rule->>'calculated_cents')::bigint
  from jsonb_array_elements(coalesce(p_expense->'split_rules', '[]'::jsonb)) as rule;

  return v_id;
end;
$$;

-- Empréstimo com as parcelas. Devolve o id do empréstimo.
create or replace function public.create_p2p_loan(p_loan jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id uuid;
begin
  if jsonb_array_length(coalesce(p_loan->'installments', '[]'::jsonb)) = 0 then
    raise exception 'O empréstimo precisa de ao menos uma parcela.';
  end if;

  insert into public.p2p_loans (
    id, house_id, lender_id, lender_is_house, repayment_mode, settle_in_cycle,
    borrower_id, title, description, total_amount_cents, installments_count,
    status, created_by, created_at
  ) values (
    coalesce((p_loan->>'id')::uuid, gen_random_uuid()),
    (p_loan->>'house_id')::uuid,
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
    coalesce((p_loan->>'created_at')::timestamptz, now())
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

-- Fecha a compra do mercado: despesa da casa (se houver), empréstimo dos itens
-- pessoais (se houver), registro da viagem e limpeza dos itens comprados.
-- Devolve {"trip_id", "expense_id", "loan_id"}.
create or replace function public.complete_shopping_trip(p_plan jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_expense_id uuid;
  v_loan_id uuid;
  v_trip_id uuid;
begin
  if jsonb_typeof(p_plan->'expense') = 'object' then
    v_expense_id := public.create_house_expense(p_plan->'expense');
  end if;

  if jsonb_typeof(p_plan->'loan') = 'object' then
    v_loan_id := public.create_p2p_loan(p_plan->'loan');
  end if;

  insert into public.shopping_trips (
    house_id, list_id, total_spent_cents, expense_id, created_by, completed_at
  ) values (
    (p_plan->>'house_id')::uuid,
    (p_plan->>'list_id')::uuid,
    (p_plan->>'total_spent_cents')::bigint,
    v_expense_id,
    auth.uid(),
    coalesce((p_plan->>'completed_at')::timestamptz, now())
  )
  returning id into v_trip_id;

  delete from public.shopping_items
  where list_id = (p_plan->>'list_id')::uuid and is_bought;

  return jsonb_build_object('trip_id', v_trip_id, 'expense_id', v_expense_id, 'loan_id', v_loan_id);
end;
$$;

revoke execute on function public.create_house_expense(jsonb) from public, anon;
revoke execute on function public.create_p2p_loan(jsonb) from public, anon;
revoke execute on function public.complete_shopping_trip(jsonb) from public, anon;
grant execute on function public.create_house_expense(jsonb) to authenticated;
grant execute on function public.create_p2p_loan(jsonb) to authenticated;
grant execute on function public.complete_shopping_trip(jsonb) to authenticated;
