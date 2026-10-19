-- 0107_receipt_attachments.sql
-- Adiciona suporte a comprovantes/anexos nas despesas da casa (house_expenses),
-- atualiza a RPC create_house_expense e configura o bucket 'receipts' no Supabase Storage.

-- 1. Colunas na tabela house_expenses
alter table public.house_expenses
  add column if not exists attachment_path text,
  add column if not exists attachment_name text,
  add column if not exists attachment_content_type text,
  add column if not exists attachment_size_bytes integer,
  add column if not exists attachment_purged_at timestamptz;

-- 2. Atualiza a função create_house_expense para gravar os dados do anexo
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
    notes, created_by, barcode, attachment_path, attachment_name, attachment_content_type, attachment_size_bytes
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

-- 3. Configuração do bucket privado 'receipts' no Storage
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'receipts',
  'receipts',
  false,
  10485760, -- 10 MB
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do update set
  public = false,
  file_size_limit = 10485760,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];

-- 4. Políticas RLS no storage.objects para o bucket 'receipts'
-- Estrutura do path: {house_id}/expenses/{file_name}

drop policy if exists "Members read house receipts" on storage.objects;
create policy "Members read house receipts" on storage.objects
  for select
  using (
    bucket_id = 'receipts'
    and auth.uid() is not null
    and public.is_house_member((storage.foldername(name))[1]::uuid)
  );

drop policy if exists "Premium members upload house receipts" on storage.objects;
create policy "Premium members upload house receipts" on storage.objects
  for insert
  with check (
    bucket_id = 'receipts'
    and auth.uid() is not null
    and public.is_house_member((storage.foldername(name))[1]::uuid)
    and public.house_plan((storage.foldername(name))[1]::uuid) = 'premium'
  );

drop policy if exists "Members delete house receipts" on storage.objects;
create policy "Members delete house receipts" on storage.objects
  for delete
  using (
    bucket_id = 'receipts'
    and auth.uid() is not null
    and public.is_house_member((storage.foldername(name))[1]::uuid)
  );
