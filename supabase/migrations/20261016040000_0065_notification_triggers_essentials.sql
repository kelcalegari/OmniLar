-- ==============================================================================
-- 0065: Gatilhos das notificações na hora (primeiro lote)
-- Descrição:
--   Seção 6 do plano_notificacoes.md, começando pelo que pede ação ou mexe
--   com dinheiro: empréstimos, fechamento do ciclo, tarefa atribuída e agenda.
--   Cada gatilho chama enqueue_notification (0064), que tira o autor da ação,
--   quem não mora na casa e quem desligou o grupo.
--   Rotas abertas pelo sino (seção 5 do plano, decisão 3a):
--     /pessoal/emprestimo/{id}, /fechamento?ciclo={início}, /tarefas/{id},
--     /agenda/evento/{id}.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Empréstimos
-- ------------------------------------------------------------------------------

-- Quem responde pelo lado do credor: o credor ou, no Caixa da Casa, os
-- administradores.
create or replace function public.notification_loan_lender_side(p_loan public.p2p_loans)
returns uuid[]
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_loan.lender_is_house then coalesce((
      select array_agg(m.user_id) from public.house_members m
      where m.house_id = p_loan.house_id and m.left_at is null and m.role in ('owner', 'admin')
    ), '{}'::uuid[])
    else array[p_loan.lender_id]
  end;
$$;

create or replace function public.notify_p2p_loan_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor text := public.notification_first_name(auth.uid());
  v_lender text;
  v_link text;
  v_open bigint;
begin
  if tg_op = 'DELETE' then
    perform public.enqueue_notification(
      old.house_id,
      array[old.borrower_id] || public.notification_loan_lender_side(old),
      'loan_deleted', 'emprestimos',
      'Empréstimo excluído',
      v_actor || ' excluiu o empréstimo ' || old.title || ' (' || public.notification_brl(old.total_amount_cents) || ')',
      '/pessoal', 'p2p_loan', old.id,
      'loan_deleted:' || old.id
    );
    return old;
  end if;

  v_link := '/pessoal/emprestimo/' || new.id;
  v_lender := case when new.lender_is_house then 'o Caixa da Casa'
                   else public.notification_first_name(new.lender_id) end;

  if tg_op = 'INSERT' then
    -- Para o devedor (essencial). Rajada (importação): um aviso só.
    perform public.enqueue_notification(
      new.house_id, array[new.borrower_id],
      'loan_created', 'emprestimos',
      'Novo empréstimo',
      v_actor || ' registrou que você deve ' || public.notification_brl(new.total_amount_cents)
        || ' a ' || v_lender || ': ' || new.title,
      v_link, 'p2p_loan', new.id,
      'loan_created:' || new.id, true, '{}'::jsonb,
      'loan_created:' || coalesce(auth.uid()::text, '-') || ':' || new.borrower_id,
      '{n} empréstimos novos',
      v_actor || ' registrou {n} empréstimos em que você deve, somando {total}',
      new.total_amount_cents, '/pessoal'
    );
    -- Para o credor, quando foi o devedor (ou outro morador) que registrou
    perform public.enqueue_notification(
      new.house_id, public.notification_loan_lender_side(new),
      'loan_created', 'emprestimos',
      'Novo empréstimo',
      v_actor || ' registrou que '
        || case when auth.uid() is not distinct from new.borrower_id then ''
                else public.notification_first_name(new.borrower_id) || ' ' end
        || 'deve ' || public.notification_brl(new.total_amount_cents) || ' a '
        || case when new.lender_is_house then 'o Caixa da Casa' else 'você' end
        || ': ' || new.title,
      v_link, 'p2p_loan', new.id,
      'loan_created_lender:' || new.id
    );
    return new;
  end if;

  if new.status is not distinct from old.status then
    return new;
  end if;

  if new.status = 'forgiven' then
    select coalesce(sum(amount_cents - paid_cents), 0) into v_open
    from public.p2p_installments where loan_id = new.id and status = 'forgiven';
    perform public.enqueue_notification(
      new.house_id, array[new.borrower_id],
      'loan_forgiven', 'emprestimos',
      'Empréstimo perdoado',
      v_actor || ' perdoou os ' || public.notification_brl(v_open) || ' restantes de ' || new.title,
      v_link, 'p2p_loan', new.id,
      'loan_forgiven:' || new.id
    );
  elsif new.status = 'completed' then
    perform public.enqueue_notification(
      new.house_id, array[new.borrower_id] || public.notification_loan_lender_side(new),
      'loan_paid_off', 'emprestimos',
      'Empréstimo quitado',
      'O empréstimo ' || new.title || ' foi quitado',
      v_link, 'p2p_loan', new.id,
      'loan_paid_off:' || new.id
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_p2p_loan_change on public.p2p_loans;
create trigger trg_notify_p2p_loan_change
  after insert or update of status or delete on public.p2p_loans
  for each row execute function public.notify_p2p_loan_change();

-- Renegociação: as parcelas novas entram com o empréstimo já renegociado. O
-- aviso sai de um gatilho adiado nas parcelas (para ver todas) e a chave usa
-- a transação, para a renegociação inteira virar um aviso só.
create or replace function public.notify_p2p_loan_renegotiated()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.p2p_loans%rowtype;
  v_count integer;
  v_amount bigint;
  v_first date;
begin
  select * into v_loan from public.p2p_loans where id = new.loan_id;
  if not found or v_loan.status <> 'renegotiated' then
    return null;
  end if;

  select count(*), max(amount_cents), min(due_date)
  into v_count, v_amount, v_first
  from public.p2p_installments
  where loan_id = v_loan.id and status = 'pending';

  perform public.enqueue_notification(
    v_loan.house_id, array[v_loan.borrower_id] || public.notification_loan_lender_side(v_loan),
    'loan_renegotiated', 'emprestimos',
    'Empréstimo renegociado',
    public.notification_first_name(auth.uid()) || ' renegociou ' || v_loan.title || ': '
      || v_count || 'x de ' || public.notification_brl(v_amount)
      || ' a partir de ' || to_char(v_first, 'DD/MM'),
    '/pessoal/emprestimo/' || v_loan.id, 'p2p_loan', v_loan.id,
    'loan_renegotiated:' || v_loan.id || ':' || txid_current(),
    true
  );
  return null;
end;
$$;

drop trigger if exists trg_notify_p2p_loan_renegotiated on public.p2p_installments;
create constraint trigger trg_notify_p2p_loan_renegotiated
  after insert on public.p2p_installments
  deferrable initially deferred
  for each row execute function public.notify_p2p_loan_renegotiated();

-- Pagamento ou abatimento: avisa a outra parte. Adiado porque as alocações
-- (que ligam o pagamento ao empréstimo) entram depois do pagamento.
create or replace function public.notify_p2p_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.p2p_loans%rowtype;
  v_link text;
  v_amount text := public.notification_brl(new.amount_cents);
begin
  if new.type <> 'p2p_installment' then
    return null;
  end if;

  select l.* into v_loan
  from public.payment_allocations a
  join public.p2p_installments i on i.id = a.installment_id
  join public.p2p_loans l on l.id = i.loan_id
  where a.payment_id = new.id
  limit 1;

  v_link := case when v_loan.id is not null then '/pessoal/emprestimo/' || v_loan.id else '/pessoal' end;

  -- Lado do credor: quem pagou
  perform public.enqueue_notification(
    new.house_id,
    case when v_loan.id is not null then public.notification_loan_lender_side(v_loan)
         else array[new.receiver_id] end,
    'loan_payment', 'emprestimos',
    'Pagamento de empréstimo',
    public.notification_first_name(new.payer_id) || ' pagou ' || v_amount
      || coalesce(' de ' || v_loan.title, ''),
    v_link, 'p2p_loan', v_loan.id,
    'loan_payment:' || new.id
  );
  -- Devedor, quando outra pessoa registrou o pagamento dele
  perform public.enqueue_notification(
    new.house_id, array[new.payer_id],
    'loan_payment', 'emprestimos',
    'Pagamento de empréstimo',
    public.notification_first_name(auth.uid()) || ' registrou seu pagamento de ' || v_amount
      || coalesce(' em ' || v_loan.title, ''),
    v_link, 'p2p_loan', v_loan.id,
    'loan_payment_payer:' || new.id
  );
  return null;
end;
$$;

drop trigger if exists trg_notify_p2p_payment on public.payments;
create constraint trigger trg_notify_p2p_payment
  after insert on public.payments
  deferrable initially deferred
  for each row execute function public.notify_p2p_payment();

-- ------------------------------------------------------------------------------
-- 2. Fechamento do ciclo
-- ------------------------------------------------------------------------------

-- Confirmado: cada morador recebe o resumo das transferências dele. Adiado
-- para ver as transferências gravadas depois do fechamento.
create or replace function public.notify_settlement_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_month text := public.notification_month_name(new.cycle_start_date);
  v_link text := '/fechamento?ciclo=' || to_char(new.cycle_start_date, 'YYYY-MM-DD');
  v_member uuid;
  v_parts text[];
  v_body text;
begin
  if new.status = 'confirmed'
     and (tg_op = 'INSERT' or old.status is distinct from 'confirmed'
          or old.settled_at is distinct from new.settled_at) then
    for v_member in
      select m.user_id from public.house_members m
      where m.house_id = new.house_id and m.left_at is null
    loop
      select array_agg(part order by ord)
      into v_parts
      from (
        select 1 as ord, 'você paga ' || public.notification_brl(t.amount_cents)
               || ' a ' || public.notification_first_name(t.to_member_id) as part
        from public.settlement_transfers t
        where t.settlement_id = new.id and t.from_member_id = v_member
          and t.created_at >= coalesce(new.settled_at, now()) - interval '1 minute'
        union all
        select 2, 'você recebe ' || public.notification_brl(t.amount_cents)
               || ' de ' || public.notification_first_name(t.from_member_id)
        from public.settlement_transfers t
        where t.settlement_id = new.id and t.to_member_id = v_member
          and t.created_at >= coalesce(new.settled_at, now()) - interval '1 minute'
      ) s;

      v_body := 'Ciclo de ' || v_month || ' fechado. '
        || coalesce(upper(left(array_to_string(v_parts, ', '), 1))
                    || substr(array_to_string(v_parts, ', '), 2) || '.',
                    'Nenhuma transferência para você.');

      perform public.enqueue_notification(
        new.house_id, array[v_member],
        'settlement_confirmed', 'fechamento',
        'Ciclo de ' || v_month || ' fechado',
        v_body,
        v_link, 'settlement', new.id,
        'settlement_confirmed:' || new.id || ':' || extract(epoch from new.settled_at)::bigint,
        true
      );
    end loop;
  elsif tg_op = 'UPDATE' and new.status = 'draft'
        and new.reopened_at is distinct from old.reopened_at then
    perform public.enqueue_notification(
      new.house_id,
      (select array_agg(m.user_id) from public.house_members m
       where m.house_id = new.house_id and m.left_at is null),
      'settlement_reopened', 'fechamento',
      'Ciclo de ' || v_month || ' reaberto',
      public.notification_first_name(auth.uid()) || ' reabriu o ciclo de ' || v_month,
      v_link, 'settlement', new.id,
      'settlement_reopened:' || new.id || ':' || extract(epoch from new.reopened_at)::bigint,
      true
    );
  end if;
  return null;
end;
$$;

drop trigger if exists trg_notify_settlement_change on public.settlements;
create constraint trigger trg_notify_settlement_change
  after insert or update on public.settlements
  deferrable initially deferred
  for each row execute function public.notify_settlement_change();

-- ------------------------------------------------------------------------------
-- 3. Tarefa atribuída
-- ------------------------------------------------------------------------------
create or replace function public.notify_task_assigned()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.assigned_to is null or new.is_completed then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.assigned_to is not distinct from old.assigned_to then
    return new;
  end if;
  -- Tarefa particular só é vista por quem criou
  if new.visibility = 'private' and new.assigned_to is distinct from new.created_by then
    return new;
  end if;

  perform public.enqueue_notification(
    new.house_id, array[new.assigned_to],
    'task_assigned', 'tarefas',
    'Nova tarefa',
    new.title || coalesce(', até ' || to_char(new.due_date, 'DD/MM'), ''),
    '/tarefas/' || new.id, 'task', new.id,
    'task_assigned:' || new.id || ':' || new.assigned_to,
    true, '{}'::jsonb,
    'task_assigned:' || coalesce(auth.uid()::text, '-'),
    '{n} tarefas novas',
    public.notification_first_name(auth.uid()) || ' atribuiu {n} tarefas a você',
    null, '/tarefas'
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_task_assigned on public.tasks;
create trigger trg_notify_task_assigned
  after insert or update of assigned_to on public.tasks
  for each row execute function public.notify_task_assigned();

-- ------------------------------------------------------------------------------
-- 4. Agenda
-- ------------------------------------------------------------------------------

-- Data no fuso da casa, para o texto
create or replace function public.notification_event_when(p_event public.events)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case when p_event.is_all_day
    then to_char(p_event.start_time at time zone coalesce(h.timezone, 'America/Sao_Paulo'), 'DD/MM')
    else to_char(p_event.start_time at time zone coalesce(h.timezone, 'America/Sao_Paulo'), 'DD/MM "às" HH24:MI')
  end
  from public.houses h where h.id = p_event.house_id;
$$;

-- Convite: participante novo (o upsert da edição não dispara para quem já
-- estava). Ocorrências da mesma série viram um aviso só.
create or replace function public.notify_event_participant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.events%rowtype;
begin
  select * into v_event from public.events where id = new.event_id;
  if not found or v_event.visibility = 'private' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if v_event.end_time < now() then
      return new;
    end if;
    perform public.enqueue_notification(
      v_event.house_id, array[new.user_id],
      'event_invite', 'agenda',
      'Convite: ' || v_event.title,
      v_event.title || ', ' || public.notification_event_when(v_event)
        || case when new.is_essential then '. Você foi marcado como necessário' else '' end,
      '/agenda/evento/' || v_event.id, 'event', v_event.id,
      'event_invite:' || coalesce(v_event.recurring_series_id, v_event.id) || ':' || new.user_id,
      true
    );
    return new;
  end if;

  -- Resposta: avisa quem criou; recusa de quem é necessário põe o evento em risco
  if new.rsvp_status is distinct from old.rsvp_status and new.rsvp_status <> 'pending' then
    if new.rsvp_status = 'declined' and new.is_essential then
      perform public.enqueue_notification(
        v_event.house_id, array[v_event.created_by],
        'event_at_risk', 'agenda',
        v_event.title || ' está em risco',
        public.notification_first_name(new.user_id) || ' não pode ir a ' || v_event.title
          || ', ' || public.notification_event_when(v_event),
        '/agenda/evento/' || v_event.id, 'event', v_event.id,
        'event_rsvp:' || new.id || ':' || extract(epoch from coalesce(new.responded_at, now()))::bigint,
        true
      );
    else
      perform public.enqueue_notification(
        v_event.house_id, array[v_event.created_by],
        'event_rsvp', 'agenda',
        'Resposta: ' || v_event.title,
        public.notification_first_name(new.user_id) || case new.rsvp_status
          when 'accepted' then ' confirmou presença em '
          when 'declined' then ' não vai a '
          else ' talvez vá a ' end || v_event.title,
        '/agenda/evento/' || v_event.id, 'event', v_event.id,
        'event_rsvp:' || new.id || ':' || extract(epoch from coalesce(new.responded_at, now()))::bigint
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_event_participant on public.event_participants;
create trigger trg_notify_event_participant
  after insert or update of rsvp_status on public.event_participants
  for each row execute function public.notify_event_participant();

-- Alterado ou cancelado: avisa os participantes que não recusaram
create or replace function public.notify_event_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.events%rowtype;
  v_users uuid[];
  v_group text;
begin
  v_event := case when tg_op = 'DELETE' then old else new end;
  if v_event.visibility = 'private' or v_event.end_time < now() then
    return v_event;
  end if;

  select array_agg(p.user_id) into v_users
  from public.event_participants p
  where p.event_id = v_event.id and p.rsvp_status <> 'declined';
  if v_users is null then
    return v_event;
  end if;

  v_group := coalesce(v_event.recurring_series_id, v_event.id)::text;

  if tg_op = 'DELETE' then
    perform public.enqueue_notification(
      v_event.house_id, v_users,
      'event_cancelled', 'agenda',
      v_event.title || ' foi cancelado',
      public.notification_first_name(auth.uid()) || ' cancelou ' || v_event.title
        || ', ' || public.notification_event_when(v_event),
      '/agenda', 'event', v_event.id,
      'event_cancelled:' || v_group,
      true
    );
    return old;
  end if;

  if new.start_time is not distinct from old.start_time
     and new.end_time is not distinct from old.end_time
     and new.location is not distinct from old.location
     and new.is_all_day is not distinct from old.is_all_day then
    return new;
  end if;

  perform public.enqueue_notification(
    new.house_id, v_users,
    'event_changed', 'agenda',
    new.title || ' mudou',
    new.title || ' agora é ' || public.notification_event_when(new)
      || coalesce(' em ' || nullif(new.location, ''), ''),
    '/agenda/evento/' || new.id, 'event', new.id,
    'event_changed:' || v_group || ':' || to_char(now(), 'YYYYMMDDHH24MI'),
    true
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_event_change on public.events;
create trigger trg_notify_event_change
  after update of start_time, end_time, location, is_all_day on public.events
  for each row execute function public.notify_event_change();

drop trigger if exists trg_notify_event_cancelled on public.events;
create trigger trg_notify_event_cancelled
  before delete on public.events
  for each row execute function public.notify_event_change();

-- Funções internas: só os gatilhos usam
revoke execute on function public.notification_loan_lender_side(public.p2p_loans) from public, anon, authenticated;
revoke execute on function public.notification_event_when(public.events) from public, anon, authenticated;
revoke execute on function public.notify_p2p_loan_change() from public, anon, authenticated;
revoke execute on function public.notify_p2p_loan_renegotiated() from public, anon, authenticated;
revoke execute on function public.notify_p2p_payment() from public, anon, authenticated;
revoke execute on function public.notify_settlement_change() from public, anon, authenticated;
revoke execute on function public.notify_task_assigned() from public, anon, authenticated;
revoke execute on function public.notify_event_participant() from public, anon, authenticated;
revoke execute on function public.notify_event_change() from public, anon, authenticated;
