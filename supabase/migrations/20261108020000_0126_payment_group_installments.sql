-- ==============================================================================
-- 0126: Nota com vários meios em que o cartão é parcelado
-- Descrição:
--   Ex.: nota de R$ 300 paga com R$ 90 no VA e R$ 210 no cartão em 3 vezes.
--   - house_expenses.payment_group_total_cents: valor da nota inteira em cada
--     parte. A lista mostra o total da nota mesmo quando só algumas partes
--     (ou só a primeira parcela) caem no ciclo aberto.
--   - create_installment_purchase aceita `extra_parts`: as partes de outros
--     meios da mesma nota, gravadas na mesma transação. As parcelas e as
--     partes levam o mesmo `payment_group_id`. Só a compra da Casa (o
--     empréstimo de morador não entra) e só com meios diferentes do cartão.
--   - delete_house_expense recusa excluir só uma parcela de uma nota assim: a
--     nota sai pela compra parcelada inteira (delete_installment_purchase),
--     que leva junto as outras partes.
-- ==============================================================================

alter table public.house_expenses
  add column if not exists payment_group_total_cents bigint
    check (payment_group_total_cents is null or payment_group_total_cents > 0);

comment on column public.house_expenses.payment_group_total_cents is
  'Valor da nota inteira paga com mais de um meio (igual em todas as partes).';

-- ------------------------------------------------------------------------------
-- 1. create_house_expense: igual à 0124, gravando também o total da nota
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
    payment_group_id, payment_group_total_cents
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
    (p_expense->>'payment_group_id')::uuid,
    (p_expense->>'payment_group_total_cents')::bigint
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
-- 2. create_installment_purchase: igual à 0117, com as partes de outros meios
-- ------------------------------------------------------------------------------
create or replace function public.create_installment_purchase(p_purchase jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_plan jsonb := p_purchase->'plan';
  v_house_id uuid := (p_purchase->'plan'->>'house_id')::uuid;
  v_plan_id uuid := coalesce((p_purchase->'plan'->>'id')::uuid, gen_random_uuid());
  v_destination text := coalesce(p_purchase->'plan'->>'destination', 'house');
  v_card_id uuid := (p_purchase->'plan'->>'payment_method_id')::uuid;
  v_extras jsonb := coalesce(p_purchase->'extra_parts', '[]'::jsonb);
  v_group_id uuid;
  v_item jsonb;
  v_expense_id uuid;
begin
  if v_house_id is null or not public.is_house_member(v_house_id) then
    raise exception 'Acesso negado: você não é membro desta casa.';
  end if;
  if v_destination not in ('house', 'p2p_loan') then
    raise exception 'A compra parcelada lançada à mão é da Casa ou de um morador.';
  end if;
  if v_destination = 'p2p_loan' and (v_plan->>'assigned_member_id') is null then
    raise exception 'Diga qual morador deve a compra parcelada.';
  end if;

  if jsonb_array_length(v_extras) > 0 then
    if v_destination <> 'house' then
      raise exception 'A compra parcelada de um morador não pode ser dividida com outros meios de pagamento.';
    end if;
    v_group_id := (v_extras->0->>'payment_group_id')::uuid;
    if v_group_id is null then
      raise exception 'As partes da nota precisam do mesmo grupo de pagamento.';
    end if;
    if exists (
      select 1 from jsonb_array_elements(v_extras) as p
      where (p->>'payment_group_id')::uuid is distinct from v_group_id
         or (p->>'house_id')::uuid is distinct from v_house_id
         or (p->>'payment_method_id')::uuid is null
         or (p->>'payment_method_id')::uuid = v_card_id
         or coalesce((p->>'amount_cents')::bigint, 0) <= 0
         or coalesce((p->>'is_recurring')::boolean, false)
         or (p->>'project_id') is not null
    ) then
      raise exception 'As outras partes da nota precisam ser da mesma casa, com valor positivo e meio diferente do cartão.';
    end if;
    if (select count(distinct p->>'payment_method_id') from jsonb_array_elements(v_extras) as p)
       <> jsonb_array_length(v_extras) then
      raise exception 'Cada parte da nota precisa de uma forma de pagamento diferente.';
    end if;
    if exists (select 1 from public.house_expenses where payment_group_id = v_group_id) then
      raise exception 'Esse grupo de pagamento já existe. Use um novo.';
    end if;
    -- Cada parcela leva o grupo e o total da nota
    if exists (
      select 1 from jsonb_array_elements(coalesce(p_purchase->'expenses', '[]'::jsonb)) as e
      where (e->>'payment_group_id')::uuid is distinct from v_group_id
    ) then
      raise exception 'As parcelas e as outras partes da nota precisam do mesmo grupo de pagamento.';
    end if;
  end if;

  insert into public.installment_plans (
    id, house_id, payment_method_id, merchant_key, title, installments_total,
    installment_cents, anchor_number, anchor_line_date, anchor_due_date, destination,
    category_id, assigned_member_id, origin
  ) values (
    v_plan_id,
    v_house_id,
    (v_plan->>'payment_method_id')::uuid,
    v_plan->>'merchant_key',
    v_plan->>'title',
    (v_plan->>'installments_total')::integer,
    (v_plan->>'installment_cents')::bigint,
    coalesce((v_plan->>'anchor_number')::integer, 1),
    (v_plan->>'anchor_line_date')::date,
    (v_plan->>'anchor_due_date')::date,
    v_destination,
    (v_plan->>'category_id')::uuid,
    case when v_destination = 'p2p_loan' then (v_plan->>'assigned_member_id')::uuid end,
    'manual'
  );

  -- Parcelas da Casa: todas previstas, cada fatura confirma a sua
  for v_item in select * from jsonb_array_elements(coalesce(p_purchase->'expenses', '[]'::jsonb)) loop
    if (v_item->>'house_id')::uuid is distinct from v_house_id then
      raise exception 'A compra parcelada tem uma despesa de outra casa.';
    end if;
    v_expense_id := public.create_house_expense(v_item);
    update public.house_expenses
    set installment_plan_id = v_plan_id,
        installment_number = (v_item->>'installment_number')::integer,
        is_forecast = true
    where id = v_expense_id and house_id = v_house_id;
  end loop;

  -- Partes da mesma nota em outros meios (VA, Pix...): despesas comuns
  for v_item in select * from jsonb_array_elements(v_extras) loop
    perform public.create_house_expense(v_item);
  end loop;

  -- Empréstimos do morador, ligados ao plano para o aceite único
  for v_item in select * from jsonb_array_elements(coalesce(p_purchase->'loans', '[]'::jsonb)) loop
    if (v_item->>'house_id')::uuid is distinct from v_house_id then
      raise exception 'A compra parcelada tem um empréstimo de outra casa.';
    end if;
    perform public.create_p2p_loan(
      v_item || jsonb_build_object('installment_plan_ids', jsonb_build_array(v_plan_id))
    );
  end loop;

  return v_plan_id;
end;
$$;

revoke execute on function public.create_installment_purchase(jsonb) from public, anon;
grant execute on function public.create_installment_purchase(jsonb) to authenticated;

-- ------------------------------------------------------------------------------
-- 3. delete_house_expense: igual à 0124; parcela de nota com vários meios só
--    sai pela compra parcelada inteira
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
    if coalesce(current_setting('omnilar.deleting_installment_plan', true), '') <> 'on'
       and exists (
         select 1 from public.house_expenses e
         where e.payment_group_id = v_group_id and e.house_id = v_house_id
           and e.deleted_at is null and e.installment_plan_id is not null
       ) then
      raise exception 'Esta nota tem uma compra parcelada no cartão. Exclua a compra parcelada inteira, que leva junto as outras partes da nota.';
    end if;

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
-- 4. delete_installment_purchase: igual à 0118; a nota com vários meios sai
--    junto (a primeira parcela excluída leva o grupo todo)
-- ------------------------------------------------------------------------------
create or replace function public.delete_installment_purchase(p_plan_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_plan public.installment_plans%rowtype;
  v_expense_id uuid;
  v_loans uuid[];
  v_deleted integer;
begin
  select * into v_plan from public.installment_plans where id = p_plan_id for update;
  if not found or not public.is_house_member(v_plan.house_id) then
    raise exception 'Compra parcelada não encontrada.';
  end if;
  if v_plan.origin <> 'manual' then
    raise exception 'Esta compra parcelada veio de uma fatura importada. Para desfazer, desfaça a importação no histórico.';
  end if;
  if v_plan.created_by is distinct from auth.uid() and not public.is_house_admin(v_plan.house_id) then
    raise exception 'Só quem lançou a compra parcelada (ou um administrador) pode excluí-la.';
  end if;

  -- Uma fatura já usou a compra: apagar desmancharia a importação dela
  if exists (
    select 1 from public.house_expenses
    where installment_plan_id = p_plan_id and deleted_at is null and not is_forecast
  ) or exists (
    select 1
    from public.import_lines l
    join public.import_batches b on b.id = l.batch_id
    where l.installment_plan_id = p_plan_id and b.status = 'confirmed'
  ) then
    raise exception 'Uma fatura importada já confirmou parcela desta compra. Desfaça antes a importação dessa fatura.';
  end if;

  -- Parcelas previstas da Casa (a função recusa a que já entrou num fechamento).
  -- Numa nota com vários meios, a exclusão leva o grupo inteiro.
  perform set_config('omnilar.deleting_installment_plan', 'on', true);
  for v_expense_id in
    select id from public.house_expenses
    where installment_plan_id = p_plan_id and deleted_at is null
  loop
    perform public.delete_house_expense(v_expense_id, 'thisInstanceOnly');
  end loop;
  perform set_config('omnilar.deleting_installment_plan', 'off', true);

  -- Empréstimos da compra (só dela: os de fatura juntam várias compras)
  select array_agg(id) into v_loans
  from public.p2p_loans
  where house_id = v_plan.house_id and installment_plan_ids = array[p_plan_id];

  if v_loans is not null then
    with deleted as (
      delete from public.p2p_loans where id = any(v_loans) returning id
    )
    select count(*) into v_deleted from deleted;

    -- A regra de acesso não dá erro: só deixa de apagar
    if v_deleted <> array_length(v_loans, 1) then
      raise exception 'Um empréstimo desta compra já teve pagamento ou não é seu. Só quem emprestou (ou um administrador) exclui, e apenas enquanto nada foi pago.';
    end if;
  end if;

  delete from public.installment_plans where id = p_plan_id;
end;
$$;

revoke execute on function public.delete_installment_purchase(uuid) from public, anon;
grant execute on function public.delete_installment_purchase(uuid) to authenticated;
