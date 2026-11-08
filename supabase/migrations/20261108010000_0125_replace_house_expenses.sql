-- ==============================================================================
-- 0125: Editar a divisão do pagamento de uma nota
-- Descrição:
--   replace_house_expenses troca, numa transação só, um conjunto de despesas
--   (a nota inteira, ou uma despesa avulsa) pelas partes novas: serve para
--   mudar os meios de pagamento e os valores de uma nota (0124), juntar uma
--   despesa avulsa em vários meios ou desfazer a divisão (uma parte só).
--   Recusa o que não pode ser trocado sem perder histórico: despesa já
--   acertada em fechamento, em ciclo fechado, recorrente, parcelada, de
--   projeto, vinda de importação ou de compra do mercado, e compra de cartão
--   cuja fatura já foi paga. As partes novas também não podem cair em ciclo
--   fechado. O app não avisa os moradores de novo: é uma correção, não uma
--   despesa nova (notify_expense_added respeita a marca da transação).
-- ==============================================================================

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
  -- Troca de despesas por correção (replace_house_expenses): ninguém é avisado
  if coalesce(current_setting('omnilar.skip_expense_notify', true), '') = 'on' then
    return null;
  end if;

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

create or replace function public.replace_house_expenses(p_old_ids uuid[], p_expenses jsonb)
returns uuid[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_house_id uuid;
  v_old public.house_expenses%rowtype;
  v_found integer := 0;
  v_ids uuid[] := '{}';
  v_new public.house_expenses%rowtype;
  v_group_id uuid;
begin
  if p_old_ids is null or coalesce(array_length(p_old_ids, 1), 0) = 0
     or jsonb_typeof(p_expenses) is distinct from 'array' or jsonb_array_length(p_expenses) = 0 then
    raise exception 'Informe as despesas a trocar e as novas partes.';
  end if;

  v_house_id := (p_expenses->0->>'house_id')::uuid;
  if v_house_id is null or not public.is_house_member(v_house_id) then
    raise exception 'Acesso negado: você não é membro desta casa';
  end if;

  -- Espera um fechamento em andamento nesta casa
  perform pg_advisory_xact_lock_shared(hashtextextended('house-ledger:' || v_house_id::text, 0));

  for v_old in
    select * from public.house_expenses
    where id = any(p_old_ids) and deleted_at is null
    for update
  loop
    v_found := v_found + 1;
    if v_old.house_id <> v_house_id then
      raise exception 'Despesa de outra casa.';
    end if;
    if v_old.settled_at is not null or public.expense_counts_in_closed_cycle(v_old) then
      raise exception 'Esta despesa conta em um ciclo já fechado. Reabra o ciclo no Fechamento para alterá-la.';
    end if;
    if v_old.is_recurring or v_old.recurring_series_id is not null
       or v_old.installment_plan_id is not null or v_old.project_id is not null
       or exists (select 1 from public.import_lines where expense_id = v_old.id)
       or exists (select 1 from public.shopping_trips where expense_id = v_old.id) then
      raise exception 'Esta despesa (recorrente, parcelada, de projeto, importada ou de compra do mercado) não pode ter o pagamento dividido.';
    end if;
    if v_old.status = 'paid' and exists (
      select 1 from public.payment_methods pm
      where pm.id = v_old.payment_method_id and pm.type = 'card'
        and pm.closing_day is not null and pm.due_day is not null
    ) then
      raise exception 'A fatura desta compra no cartão já foi paga. Desfaça o pagamento da fatura para alterá-la.';
    end if;
  end loop;

  if v_found <> array_length(p_old_ids, 1) then
    raise exception 'Alguma despesa a trocar não existe mais. Atualize a tela e tente de novo.';
  end if;

  -- O grupo antigo sai inteiro: não pode sobrar parte solta
  if exists (
    select 1 from public.house_expenses o
    join public.house_expenses g on g.payment_group_id = o.payment_group_id and g.deleted_at is null
    where o.id = any(p_old_ids) and o.payment_group_id is not null
      and not (g.id = any(p_old_ids))
  ) then
    raise exception 'A nota tem outras partes: troque a nota inteira.';
  end if;

  perform set_config('omnilar.skip_expense_notify', 'on', true);

  update public.house_expenses set deleted_at = now() where id = any(p_old_ids);

  if jsonb_array_length(p_expenses) = 1 then
    v_ids := array[public.create_house_expense((p_expenses->0) - 'payment_group_id')];
  else
    v_group_id := (p_expenses->0->>'payment_group_id')::uuid;
    if exists (select 1 from public.house_expenses where payment_group_id = v_group_id) then
      raise exception 'Esse grupo de pagamento já existe. Use um novo.';
    end if;
    v_ids := public.create_house_expense_group(p_expenses);
  end if;

  -- As partes novas também não podem cair em ciclo fechado
  for v_new in select * from public.house_expenses where id = any(v_ids)
  loop
    if public.expense_counts_in_closed_cycle(v_new) then
      raise exception 'O ciclo desta data já foi fechado. Reabra o ciclo no Fechamento para lançar ou mover uma despesa para ele.';
    end if;
  end loop;

  return v_ids;
end;
$$;

revoke execute on function public.replace_house_expenses(uuid[], jsonb) from public, anon;
grant execute on function public.replace_house_expenses(uuid[], jsonb) to authenticated;
