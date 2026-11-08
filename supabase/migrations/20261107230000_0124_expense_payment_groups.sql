-- ==============================================================================
-- 0124: Uma nota paga com mais de um meio de pagamento
-- Descrição:
--   Ex.: nota de R$ 150 paga com R$ 50 no VA e R$ 100 no cartão. A nota vira uma
--   despesa por meio, ligadas por `payment_group_id`. Cada parte segue a regra
--   do próprio meio, sem mudar nada no resto do banco: a do cartão nasce
--   pendente e entra na fatura (0058/0075), a do VA fica fora dos aportes
--   (0122), cada uma no ciclo da sua competência. Fatura, importação,
--   fechamento e travas de ciclo fechado tratam cada parte como despesa comum.
--   - create_house_expense grava `payment_group_id` (o resto é igual à 0121).
--   - create_house_expense_group grava todas as partes numa transação só e
--     confere: ao menos duas partes, todas da mesma casa, com o mesmo grupo,
--     meios diferentes, valor positivo e nem recorrente nem de projeto.
--   - delete_house_expense: excluir uma parte exclui a nota inteira; recusa se
--     alguma parte já entrou em fechamento ou conta em ciclo fechado.
--   - notify_expense_added avisa uma vez por nota, com o total do grupo.
-- ==============================================================================

alter table public.house_expenses
  add column if not exists payment_group_id uuid;

comment on column public.house_expenses.payment_group_id is
  'Partes de uma mesma nota paga com mais de um meio de pagamento (uma despesa por meio).';

create index if not exists idx_house_expenses_payment_group
  on public.house_expenses (payment_group_id)
  where payment_group_id is not null;

-- ------------------------------------------------------------------------------
-- 1. create_house_expense: igual à 0121, gravando também payment_group_id
-- ------------------------------------------------------------------------------
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
    attachment_path, attachment_name, attachment_content_type, attachment_size_bytes,
    payment_group_id
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
    (p_expense->>'attachment_size_bytes')::integer,
    (p_expense->>'payment_group_id')::uuid
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

-- ------------------------------------------------------------------------------
-- 2. create_house_expense_group: todas as partes da nota, ou nenhuma
--   p_expenses: lista no formato de create_house_expense, cada uma com o mesmo
--   payment_group_id. Reenviar o mesmo grupo (fila offline) não duplica: se o
--   grupo já existe, devolve as partes gravadas.
-- ------------------------------------------------------------------------------
create or replace function public.create_house_expense_group(p_expenses jsonb)
returns uuid[]
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_part jsonb;
  v_group_id uuid;
  v_house_id uuid;
  v_ids uuid[] := '{}';
  v_count integer;
begin
  if jsonb_typeof(p_expenses) is distinct from 'array' or jsonb_array_length(p_expenses) < 2 then
    raise exception 'Uma nota com mais de um meio de pagamento precisa de pelo menos duas partes.';
  end if;

  v_group_id := (p_expenses->0->>'payment_group_id')::uuid;
  v_house_id := (p_expenses->0->>'house_id')::uuid;
  if v_group_id is null or v_house_id is null then
    raise exception 'Partes sem grupo ou sem casa.';
  end if;

  if not public.is_house_member(v_house_id) then
    raise exception 'Acesso negado: você não é membro desta casa';
  end if;

  -- Reenvio do mesmo grupo: já gravado
  select array_agg(id order by created_at, id) into v_ids
  from public.house_expenses
  where payment_group_id = v_group_id and house_id = v_house_id;
  if coalesce(array_length(v_ids, 1), 0) > 0 then
    return v_ids;
  end if;
  v_ids := '{}';

  select count(*) into v_count
  from jsonb_array_elements(p_expenses) as p
  where (p->>'payment_group_id')::uuid is distinct from v_group_id
     or (p->>'house_id')::uuid is distinct from v_house_id
     or coalesce((p->>'amount_cents')::bigint, 0) <= 0
     or coalesce((p->>'is_recurring')::boolean, false)
     or (p->>'project_id') is not null
     or (p->>'recurring_series_id') is not null;
  if v_count > 0 then
    raise exception 'Todas as partes precisam ser da mesma nota e casa, com valor positivo, sem recorrência e fora de projeto.';
  end if;

  select count(*) - count(distinct p->>'payment_method_id') into v_count
  from jsonb_array_elements(p_expenses) as p;
  if v_count > 0 or exists (
    select 1 from jsonb_array_elements(p_expenses) as p where (p->>'payment_method_id') is null
  ) then
    raise exception 'Cada parte da nota precisa de uma forma de pagamento diferente.';
  end if;

  for v_part in select value from jsonb_array_elements(p_expenses)
  loop
    v_ids := v_ids || public.create_house_expense(v_part);
  end loop;

  return v_ids;
end;
$$;

revoke execute on function public.create_house_expense_group(jsonb) from public, anon;
grant execute on function public.create_house_expense_group(jsonb) to authenticated;

-- ------------------------------------------------------------------------------
-- 3. delete_house_expense: igual à 0029; parte de uma nota exclui a nota inteira
-- ------------------------------------------------------------------------------
create or replace function public.delete_house_expense(
  p_expense_id uuid,
  p_scope text default 'thisInstanceOnly'
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_house_id uuid;
  v_series_id uuid;
  v_is_recurring boolean;
  v_due_date date;
  v_settled_at timestamptz;
  v_group_id uuid;
begin
  select house_id, recurring_series_id, is_recurring, due_date, settled_at, payment_group_id
  into v_house_id, v_series_id, v_is_recurring, v_due_date, v_settled_at, v_group_id
  from public.house_expenses
  where id = p_expense_id;

  if v_house_id is null then
    return false;
  end if;

  -- Valida se o usuário pertence à casa
  if not public.is_house_member(v_house_id) then
    raise exception 'Acesso negado: você não é membro desta casa';
  end if;

  if v_settled_at is not null then
    raise exception 'Esta despesa já entrou em um fechamento de ciclo e não pode ser excluída. Lance um ajuste para corrigir o valor.';
  end if;

  -- Nota paga com mais de um meio: sai inteira ou não sai
  if v_group_id is not null then
    if exists (
      select 1 from public.house_expenses e
      where e.payment_group_id = v_group_id
        and e.house_id = v_house_id
        and e.deleted_at is null
        and (e.settled_at is not null or public.expense_counts_in_closed_cycle(e))
    ) then
      raise exception 'Uma parte desta nota conta em um ciclo já fechado. Reabra o ciclo no Fechamento para excluí-la.';
    end if;

    update public.house_expenses
    set deleted_at = now()
    where payment_group_id = v_group_id
      and house_id = v_house_id
      and deleted_at is null;
    return true;
  end if;

  v_series_id := coalesce(v_series_id, case when v_is_recurring then p_expense_id else null end);

  -- Nos escopos de série, as ocorrências já acertadas ficam como histórico
  if p_scope = 'allInstances' then
    update public.house_expenses
    set deleted_at = now(), is_active = false
    where house_id = v_house_id
      and settled_at is null
      and (
        id = p_expense_id
        or (v_series_id is not null and (id = v_series_id or recurring_series_id = v_series_id))
      );

  elsif p_scope = 'thisAndFuture' then
    if v_series_id is not null then
      update public.house_expenses
      set is_active = false
      where id = v_series_id;
    end if;

    update public.house_expenses
    set deleted_at = now()
    where house_id = v_house_id
      and settled_at is null
      and (
        id = p_expense_id
        or (v_series_id is not null and (id = v_series_id or recurring_series_id = v_series_id))
      )
      and (v_due_date is null or due_date >= v_due_date);

  else
    -- Apenas esta ocorrência pontual
    update public.house_expenses
    set deleted_at = now()
    where id = p_expense_id;
  end if;

  return true;
end;
$$;

revoke execute on function public.delete_house_expense(uuid, text) from public, anon;
grant execute on function public.delete_house_expense(uuid, text) to authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 4. notify_expense_added: igual à 0080; uma nota com vários meios avisa uma
--    vez só (pela primeira parte), com o total e a parte de cada morador somados
-- ------------------------------------------------------------------------------
create or replace function public.notify_expense_added()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor text;
  s record;
  v_has_split boolean;
  v_ids uuid[];
  v_amount bigint;
begin
  if v_actor_id is null
     or new.project_id is not null
     or new.deleted_at is not null
     or new.recurring_series_id is not null
     or exists (select 1 from public.import_lines where expense_id = new.id)
     or exists (select 1 from public.shopping_trips where expense_id = new.id) then
    return null;
  end if;

  if new.payment_group_id is null then
    v_ids := array[new.id];
    v_amount := new.amount_cents;
  else
    -- O gatilho é adiado: na hora dele todas as partes já estão gravadas
    select array_agg(id order by id), sum(amount_cents)::bigint
    into v_ids, v_amount
    from public.house_expenses
    where payment_group_id = new.payment_group_id and deleted_at is null;
    if v_ids[1] is distinct from new.id then
      return null;
    end if;
  end if;

  v_actor := public.notification_first_name(v_actor_id);
  select exists (
    select 1 from public.split_rules
    where expense_id = any(v_ids) and coalesce(calculated_cents, 0) > 0
  ) into v_has_split;

  if v_has_split then
    for s in
      select member_id, sum(calculated_cents)::bigint as calculated_cents from public.split_rules
      where expense_id = any(v_ids) and coalesce(calculated_cents, 0) > 0 and member_id <> v_actor_id
      group by member_id
    loop
      perform public.enqueue_notification(
        new.house_id, array[s.member_id],
        'expense_added', 'despesas',
        'Nova despesa da casa',
        v_actor || ' lançou ' || new.title || ': ' || public.notification_brl(v_amount)
          || ' (sua parte ' || public.notification_brl(s.calculated_cents) || ')',
        '/casa', 'expense', new.id,
        'expense_added:' || new.id, false, '{}'::jsonb,
        'expense_added:' || v_actor_id || ':' || s.member_id,
        '{n} despesas novas',
        v_actor || ' lançou {n} despesas da casa, somando {total}',
        v_amount, '/casa'
      );
    end loop;
  else
    perform public.enqueue_notification(
      new.house_id, public.notification_house_member_ids(new.house_id),
      'expense_added', 'despesas',
      'Nova despesa da casa',
      v_actor || ' lançou ' || new.title || ': ' || public.notification_brl(v_amount),
      '/casa', 'expense', new.id,
      'expense_added:' || new.id, false, '{}'::jsonb,
      'expense_added:' || v_actor_id,
      '{n} despesas novas',
      v_actor || ' lançou {n} despesas da casa, somando {total}',
      v_amount, '/casa'
    );
  end if;
  return null;
end;
$$;

revoke execute on function public.notify_expense_added() from public, anon, authenticated;
