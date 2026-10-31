-- ==============================================================================
-- 0121: Descrição livre nos gastos
-- Descrição:
--   O gasto ganha `description`, um texto opcional do morador além do título.
--   `notes` continua com as marcações do sistema ("Importado de ...",
--   "[Câmbio: ...]", "[sem_rateio]"), que regras do app leem; misturar o texto
--   do morador ali quebraria essas regras.
--   - create_house_expense grava a descrição. Lançamento manual, compra
--     parcelada e importação de fatura passam todos por ela.
--   - generate_recurring_expenses copia a descrição do modelo para as
--     próximas ocorrências, como já faz com o título.
-- ==============================================================================

alter table public.house_expenses add column if not exists description text;

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
    paid_by_participant_id, paid_out_of_pocket, due_date, date, cycle_start_date,
    split_type, status, paid_at, is_recurring, is_variable, due_day, is_active,
    recurring_series_id, project_id, description, notes, created_by, barcode,
    attachment_path, attachment_name, attachment_content_type, attachment_size_bytes
  ) values (
    coalesce((p_expense->>'id')::uuid, gen_random_uuid()),
    (p_expense->>'house_id')::uuid,
    p_expense->>'title',
    (p_expense->>'amount_cents')::bigint,
    (p_expense->>'category_id')::uuid,
    (p_expense->>'payment_method_id')::uuid,
    case
      when (p_expense->>'paid_by_participant_id') is not null then coalesce(auth.uid(), (p_expense->>'paid_by_id')::uuid)
      else coalesce((p_expense->>'paid_by_id')::uuid, auth.uid())
    end,
    (p_expense->>'paid_by_participant_id')::uuid,
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
    nullif(btrim(p_expense->>'description'), ''),
    p_expense->>'notes',
    auth.uid(),
    nullif(p_expense->>'barcode', ''),
    nullif(p_expense->>'attachment_path', ''),
    nullif(p_expense->>'attachment_name', ''),
    nullif(p_expense->>'attachment_content_type', ''),
    (p_expense->>'attachment_size_bytes')::integer
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
    coalesce(item->>'split_type', 'percentage')
  from jsonb_array_elements(coalesce(p_expense->'items', '[]'::jsonb)) as item;

  insert into public.split_rules (
    expense_id, member_id, percentage_basis_points, fixed_amount_cents, calculated_cents
  )
  select
    v_id,
    (sr->>'member_id')::uuid,
    (sr->>'percentage_basis_points')::integer,
    (sr->>'fixed_amount_cents')::bigint,
    coalesce((sr->>'calculated_cents')::bigint, 0)
  from jsonb_array_elements(coalesce(p_expense->'split_rules', '[]'::jsonb)) as sr;

  return v_id;
end;
$$;

revoke execute on function public.create_house_expense(jsonb) from public, anon;
grant execute on function public.create_house_expense(jsonb) to authenticated;

create or replace function public.generate_recurring_expenses(p_house_id uuid, p_until date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_timezone text;
  v_until date;
  v_horizon integer;
  v_series public.house_expenses%rowtype;
  v_template public.house_expenses%rowtype;
  v_last_due date;
  v_next_due date;
  v_month date;
  v_due_day integer;
  v_new_id uuid;
  v_created integer := 0;
  v_guard integer;
begin
  if not public.is_house_member(p_house_id) then
    raise exception 'Acesso negado: você não é membro desta casa';
  end if;

  select timezone, public.folego_param_int(folego_params, 'recurring_horizon_months', 3)
  into v_timezone, v_horizon
  from public.houses where id = p_house_id;

  -- Nunca gera além do horizonte da casa (três meses, se ela não mudou), por
  -- mais longe que a tela navegue
  v_until := least(p_until, (current_date + make_interval(months => coalesce(v_horizon, 3)))::date);

  -- Duas telas abertas ao mesmo tempo não geram a mesma conta em dobro
  perform pg_advisory_xact_lock(hashtextextended('recurring-expenses:' || p_house_id::text, 0));

  for v_series in
    select * from public.house_expenses
    where house_id = p_house_id
      and is_recurring
      and is_active
      and recurring_series_id is null
      and project_id is null
  loop
    select max(due_date) into v_last_due
    from public.house_expenses
    where id = v_series.id or recurring_series_id = v_series.id;

    v_guard := 0;
    loop
      v_guard := v_guard + 1;
      exit when v_guard > 12;

      -- Modelo: a ocorrência mais recente ainda existente (carrega edições
      -- feitas com "esta e as próximas"); sem nenhuma, a matriz.
      select * into v_template
      from public.house_expenses
      where (id = v_series.id or recurring_series_id = v_series.id)
        and deleted_at is null
      order by due_date desc
      limit 1;
      if not found then
        v_template := v_series;
      end if;

      -- O dia de vencimento também vem do modelo: mudá-lo com "esta e as
      -- próximas" vale para as contas dos meses seguintes
      v_due_day := coalesce(
        v_template.due_day,
        v_series.due_day,
        extract(day from v_series.due_date)::integer
      );
      v_month := (date_trunc('month', v_last_due) + interval '1 month')::date;
      v_next_due := least(
        v_month + (v_due_day - 1),
        (v_month + interval '1 month - 1 day')::date
      );
      exit when v_next_due > v_until;

      insert into public.house_expenses (
        house_id, title, amount_cents, category_id, payment_method_id, paid_by_id,
        paid_out_of_pocket, due_date, cycle_start_date, split_type, description, notes, status,
        created_by, is_recurring, is_variable, due_day, is_active,
        recurring_series_id, date
      ) values (
        p_house_id, v_template.title, v_template.amount_cents, v_template.category_id,
        v_template.payment_method_id, v_template.paid_by_id,
        v_template.paid_out_of_pocket, v_next_due, v_next_due, v_template.split_type,
        v_template.description, v_template.notes, 'pending',
        coalesce(auth.uid(), v_series.created_by), true, v_template.is_variable, v_due_day, true,
        v_series.id, (v_next_due::timestamp + interval '12 hours') at time zone coalesce(v_timezone, 'America/Sao_Paulo')
      )
      on conflict (recurring_series_id, due_date) where recurring_series_id is not null do nothing
      returning id into v_new_id;

      if v_new_id is not null then
        insert into public.split_rules (
          expense_id, member_id, percentage_basis_points, fixed_amount_cents, calculated_cents
        )
        select v_new_id, member_id, percentage_basis_points, fixed_amount_cents, calculated_cents
        from public.split_rules
        where expense_id = v_template.id;

        insert into public.house_expense_items (
          expense_id, title, amount_cents, category_id, responsible_member_id, split_type
        )
        select v_new_id, title, amount_cents, category_id, responsible_member_id, split_type
        from public.house_expense_items
        where expense_id = v_template.id;

        v_created := v_created + 1;
      end if;

      v_new_id := null;
      v_last_due := v_next_due;
    end loop;
  end loop;

  return v_created;
end;
$$;
