-- ==============================================================================
-- 0080: Avisos informativos de pouco barulho (decisão 4.3 de plano_proximas_frentes.md)
-- Descrição:
--   1) expense_added: despesa da casa lançada por outro morador. Quem tem parte
--      no rateio (split_rules) recebe com a sua parte; sem rateio gravado, todos
--      os moradores. Várias seguidas da mesma pessoa viram um aviso só
--      (agrupamento de 10 minutos do enqueue_notification).
--      Fica de fora: despesa de projeto, ocorrência de série recorrente (gerada
--      pelo banco), de importação (tem aviso próprio) e de compra do mercado (idem).
--   2) shopping_completed: compra do mercado fechada.
--   3) import_confirmed: importação de fatura ou extrato confirmada (um aviso
--      por importação). Os devedores dos empréstimos criados já recebem
--      loan_created (0065).
--   Os três são gatilhos adiados (rodam no fim da transação, quando o rateio,
--   as linhas da importação e a compra já estão gravados). Não são essenciais:
--   seguem as preferências de cada grupo.
-- ==============================================================================

-- 1. Despesa lançada por outro morador
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
begin
  if v_actor_id is null
     or new.project_id is not null
     or new.deleted_at is not null
     or new.recurring_series_id is not null
     or exists (select 1 from public.import_lines where expense_id = new.id)
     or exists (select 1 from public.shopping_trips where expense_id = new.id) then
    return null;
  end if;

  v_actor := public.notification_first_name(v_actor_id);
  select exists (select 1 from public.split_rules where expense_id = new.id and coalesce(calculated_cents, 0) > 0)
    into v_has_split;

  if v_has_split then
    for s in
      select member_id, calculated_cents from public.split_rules
      where expense_id = new.id and coalesce(calculated_cents, 0) > 0 and member_id <> v_actor_id
    loop
      perform public.enqueue_notification(
        new.house_id, array[s.member_id],
        'expense_added', 'despesas',
        'Nova despesa da casa',
        v_actor || ' lançou ' || new.title || ': ' || public.notification_brl(new.amount_cents)
          || ' (sua parte ' || public.notification_brl(s.calculated_cents) || ')',
        '/casa', 'expense', new.id,
        'expense_added:' || new.id, false, '{}'::jsonb,
        'expense_added:' || v_actor_id || ':' || s.member_id,
        '{n} despesas novas',
        v_actor || ' lançou {n} despesas da casa, somando {total}',
        new.amount_cents, '/casa'
      );
    end loop;
  else
    perform public.enqueue_notification(
      new.house_id, public.notification_house_member_ids(new.house_id),
      'expense_added', 'despesas',
      'Nova despesa da casa',
      v_actor || ' lançou ' || new.title || ': ' || public.notification_brl(new.amount_cents),
      '/casa', 'expense', new.id,
      'expense_added:' || new.id, false, '{}'::jsonb,
      'expense_added:' || v_actor_id,
      '{n} despesas novas',
      v_actor || ' lançou {n} despesas da casa, somando {total}',
      new.amount_cents, '/casa'
    );
  end if;
  return null;
end;
$$;

drop trigger if exists trg_notify_expense_added on public.house_expenses;
create constraint trigger trg_notify_expense_added
  after insert on public.house_expenses
  deferrable initially deferred
  for each row execute function public.notify_expense_added();

-- 2. Compra do mercado fechada
create or replace function public.notify_shopping_completed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := coalesce(auth.uid(), new.created_by);
begin
  if v_actor_id is null then
    return null;
  end if;
  perform public.enqueue_notification(
    new.house_id, public.notification_house_member_ids(new.house_id),
    'shopping_completed', 'compras',
    'Compra fechada',
    public.notification_first_name(v_actor_id) || ' fechou a compra: '
      || public.notification_brl(new.total_spent_cents),
    '/compras', 'shopping_trip', new.id,
    'shopping_completed:' || new.id, false, '{}'::jsonb,
    null, null, null, new.total_spent_cents
  );
  return null;
end;
$$;

drop trigger if exists trg_notify_shopping_completed on public.shopping_trips;
create constraint trigger trg_notify_shopping_completed
  after insert on public.shopping_trips
  deferrable initially deferred
  for each row execute function public.notify_shopping_completed();

-- 3. Importação confirmada
create or replace function public.notify_import_confirmed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := coalesce(auth.uid(), new.created_by);
  v_expenses integer;
  v_total bigint;
  v_origin text;
begin
  if v_actor_id is null then
    return null;
  end if;

  select count(*), coalesce(sum(x.amount_cents), 0) into v_expenses, v_total
  from public.import_lines l
  join public.house_expenses x on x.id = l.expense_id
  where l.batch_id = new.id and x.deleted_at is null and x.created_at >= new.created_at - interval '1 minute';

  select coalesce(pm.name, new.account_name, new.file_name, 'um arquivo') into v_origin
  from (select 1) one
  left join public.payment_methods pm on pm.id = new.payment_method_id;

  perform public.enqueue_notification(
    new.house_id, public.notification_house_member_ids(new.house_id),
    'import_confirmed', 'despesas',
    'Importação confirmada',
    public.notification_first_name(v_actor_id) || ' importou ' || v_origin || ': '
      || case when v_expenses = 1 then '1 despesa da casa' else v_expenses || ' despesas da casa' end
      || case when v_expenses > 0 then ', somando ' || public.notification_brl(v_total) else '' end,
    '/casa/importar', 'import_batch', new.id,
    'import_confirmed:' || new.id, false, '{}'::jsonb,
    null, null, null, v_total
  );
  return null;
end;
$$;

drop trigger if exists trg_notify_import_confirmed on public.import_batches;
create constraint trigger trg_notify_import_confirmed
  after insert on public.import_batches
  deferrable initially deferred
  for each row execute function public.notify_import_confirmed();

revoke execute on function public.notify_expense_added() from public, anon, authenticated;
revoke execute on function public.notify_shopping_completed() from public, anon, authenticated;
revoke execute on function public.notify_import_confirmed() from public, anon, authenticated;
