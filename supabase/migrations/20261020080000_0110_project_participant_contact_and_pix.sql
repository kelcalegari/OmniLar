-- ==============================================================================
-- Migration: 0110_project_participant_contact_and_pix.sql
-- Description: Adiciona campos de contato e chave Pix aos participantes do projeto
--              e suporte a despesas pagas por participante externo.
-- ==============================================================================

-- 1. Colunas pix_key e phone na tabela project_participants
alter table public.project_participants
  add column if not exists pix_key text,
  add column if not exists phone text;

-- 2. Coluna paid_by_participant_id na tabela house_expenses
alter table public.house_expenses
  add column if not exists paid_by_participant_id uuid references public.project_participants(id) on delete set null;

create index if not exists idx_house_expenses_paid_by_participant
  on public.house_expenses (paid_by_participant_id);

-- 2.1 Coluna vault_id na tabela shared_projects (vínculo com Caixinhas / Cofres)
alter table public.shared_projects
  add column if not exists vault_id uuid references public.savings_vaults(id) on delete set null;

create index if not exists idx_shared_projects_vault
  on public.shared_projects (vault_id);

-- 3. Atualiza set_project_participants para gravar pix_key e phone
create or replace function public.set_project_participants(p_project_id uuid, p_participants jsonb)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_count integer;
begin
  if jsonb_typeof(p_participants) <> 'array' or jsonb_array_length(p_participants) = 0 then
    raise exception 'O projeto precisa de ao menos um participante.';
  end if;

  if not exists (select 1 from public.shared_projects where id = p_project_id) then
    raise exception 'Projeto não encontrado.';
  end if;

  delete from public.project_participants where project_id = p_project_id;

  insert into public.project_participants (
    id, project_id, user_id, external_name, default_split_percent, pix_key, phone
  )
  select
    case when item->>'id' is not null and item->>'id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then (item->>'id')::uuid
      else gen_random_uuid()
    end,
    p_project_id,
    (item->>'user_id')::uuid,
    nullif(trim(item->>'external_name'), ''),
    (item->>'default_split_percent')::numeric,
    nullif(trim(item->>'pix_key'), ''),
    nullif(trim(item->>'phone'), '')
  from jsonb_array_elements(p_participants) as item;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.set_project_participants(uuid, jsonb) from public, anon;
grant execute on function public.set_project_participants(uuid, jsonb) to authenticated;

-- 4. Atualiza create_house_expense para aceitar paid_by_participant_id
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
    recurring_series_id, project_id, notes, created_by, barcode,
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
