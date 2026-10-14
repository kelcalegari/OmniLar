-- ==============================================================================
-- 0056: Código de barras do boleto na despesa
-- Descrição:
--   O boleto escaneado ou digitado no app virava despesa sem o código, e quem
--   ia pagar depois precisava do papel ou do PDF de novo. A despesa passa a
--   guardar a linha digitável, para copiar e colar no app do banco.
-- ==============================================================================

alter table public.house_expenses
  add column if not exists barcode text;

-- Mesma função da 0042, agora gravando também o código do boleto
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
    notes, created_by, barcode
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
    auth.uid(),
    nullif(p_expense->>'barcode', '')
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

revoke execute on function public.create_house_expense(jsonb) from public, anon;
grant execute on function public.create_house_expense(jsonb) to authenticated;
