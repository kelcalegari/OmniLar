-- ==============================================================================
-- 0070: Agendador das notificações (fase 5)
-- Descrição:
--   Lembretes que não nascem de uma ação, mas do calendário: vencimentos,
--   atrasos, ciclo terminando, aporte pendente, tarefas, eventos e os avisos
--   da categoria "conta" (Premium vencendo e vencido, contas esperando
--   aprovação). Sai de um job do pg_cron de hora em hora.
--
--   Regras:
--   - Os lembretes de dia saem a partir das 9h no fuso de cada casa
--     (houses.timezone), nunca antes. Quem rodar às 10h (um job atrasado)
--     ainda os envia; a chave de repetição impede o segundo envio.
--   - Os lembretes de evento com horário saem a cada hora (de 30 a 90 minutos
--     antes do início, então cada evento cai numa janela só).
--   - Chave de repetição (dedupe_key) por item e por etapa, por exemplo
--     bill_due_soon:{conta}:{vencimento}:{dias}. Rodar duas vezes não repete.
--   - Preferências por grupo (in_app) e destinatários: enqueue_notification
--     (0064). Avisos essenciais ignoram o grupo desligado.
--   - Horário silencioso: a função notify segura o push (push_after); o job
--     libera o que ficou segurado (release_held_push_notifications).
--
--   O job NÃO é ligado por esta migration: schedule_notification_jobs() cria
--   o job e fica para ser chamada depois, com o aval do dono.
-- ==============================================================================

create extension if not exists pg_cron;

-- ------------------------------------------------------------------------------
-- 1. Calendário do ciclo no banco (espelha CycleSchedule/FinancialCycle do app)
-- ------------------------------------------------------------------------------

-- Dia [p_day] do mês de [p_month_first] (primeiro dia do mês); mês curto usa o último dia
create or replace function public.notification_month_day(p_month_first date, p_day integer)
returns date
language sql
immutable
set search_path = public
as $$
  select p_month_first
    + (least(p_day, extract(day from (p_month_first + interval '1 month - 1 day'))::integer) - 1);
$$;

-- Ciclo regular que contém [p_date] para um dia de início
create or replace function public.notification_regular_cycle(
  p_date date, p_day integer, out cycle_start date, out cycle_end date
)
language plpgsql
immutable
set search_path = public
as $$
declare
  v_first date := date_trunc('month', p_date)::date;
  v_start date;
  v_next date;
begin
  v_start := public.notification_month_day(v_first, p_day);
  if p_date < v_start then
    v_first := (v_first - interval '1 month')::date;
    v_start := public.notification_month_day(v_first, p_day);
  end if;
  v_next := public.notification_month_day((v_first + interval '1 month')::date, p_day);
  cycle_start := v_start;
  cycle_end := v_next - 1;
end;
$$;

-- Ciclo da casa que contém [p_date], com as trocas do dia de início
-- (houses.cycle_day_schedule: [{from, day, previous_day}]). Uma troca cria um
-- ciclo de transição de 15 a 45 dias antes de valer o dia novo.
create or replace function public.notification_cycle_for(
  p_house_id uuid, p_date date, out cycle_start date, out cycle_end date
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_day integer;
  v_schedule jsonb;
  v_change record;
  v_active_from date;
  v_active_day integer;
  v_base integer;
  v_first date;
  v_s date;
  v_first_regular date;
begin
  select h.cycle_start_day, coalesce(h.cycle_day_schedule, '[]'::jsonb)
  into v_day, v_schedule
  from public.houses h where h.id = p_house_id;

  for v_change in
    select (e->>'from')::date as from_date, (e->>'day')::integer as day
    from jsonb_array_elements(v_schedule) e
    where e->>'from' is not null and e->>'day' is not null
    order by (e->>'from')::date
  loop
    if v_change.from_date <= p_date then
      v_active_from := v_change.from_date;
      v_active_day := v_change.day;
    end if;
  end loop;

  if v_active_from is null then
    select (e->>'previous_day')::integer into v_base
    from jsonb_array_elements(v_schedule) e
    where e->>'from' is not null and e->>'previous_day' is not null
    order by (e->>'from')::date
    limit 1;
    select r.cycle_start, r.cycle_end into cycle_start, cycle_end
    from public.notification_regular_cycle(p_date, coalesce(v_base, v_day)) r;
    return;
  end if;

  -- Primeiro início regular no dia novo, 15 dias ou mais depois da troca
  v_first := date_trunc('month', v_active_from + 15)::date;
  v_s := public.notification_month_day(v_first, v_active_day);
  if v_s >= v_active_from + 15 then
    v_first_regular := v_s;
  else
    v_first_regular := public.notification_month_day((v_first + interval '1 month')::date, v_active_day);
  end if;

  if p_date < v_first_regular then
    cycle_start := v_active_from;
    cycle_end := v_first_regular - 1;
  else
    select r.cycle_start, r.cycle_end into cycle_start, cycle_end
    from public.notification_regular_cycle(p_date, v_active_day) r;
  end if;
end;
$$;

-- ------------------------------------------------------------------------------
-- 2. Auxiliares
-- ------------------------------------------------------------------------------
create or replace function public.notification_bump(p_counts jsonb, p_key text, p_n integer)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select case when coalesce(p_n, 0) = 0 then p_counts
              else p_counts || jsonb_build_object(p_key, coalesce((p_counts->>p_key)::integer, 0) + p_n) end;
$$;

create or replace function public.notification_house_member_ids(p_house_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(m.user_id), '{}'::uuid[])
  from public.house_members m
  where m.house_id = p_house_id and m.left_at is null;
$$;

create or replace function public.notification_house_admin_ids(p_house_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(m.user_id), '{}'::uuid[])
  from public.house_members m
  where m.house_id = p_house_id and m.left_at is null and m.role in ('owner', 'admin');
$$;

-- ------------------------------------------------------------------------------
-- 3. Contas e despesas: bill_due_soon, bill_overdue, recurring_generated
-- ------------------------------------------------------------------------------
create or replace function public.notification_sched_bills(p_house_id uuid, p_today date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r jsonb := '{}'::jsonb;
  e record;
  v_users uuid[];
  v_diff integer;
  v_members uuid[] := public.notification_house_member_ids(p_house_id);
begin
  for e in
    select x.id, x.title, x.amount_cents, x.due_date, x.is_variable, x.is_recurring,
           x.split_type, c.owner_member_id as category_owner
    from public.house_expenses x
    left join public.categories c on c.id = x.category_id
    left join public.payment_methods pm on pm.id = x.payment_method_id
    where x.house_id = p_house_id
      and x.status = 'pending'
      and x.deleted_at is null
      and x.paid_at is null
      and x.settled_at is null
      and x.project_id is null
      and x.due_date is not null
      and coalesce(x.is_active, true)
      and coalesce(pm.type, '') <> 'card'  -- compra no cartão entra na fatura
      and x.due_date between p_today - 8 and p_today + 5
  loop
    v_diff := e.due_date - p_today;
    -- Conta com dono da categoria avisa só o dono
    v_users := case when e.split_type = 'category_owner' and e.category_owner is not null
                    then array[e.category_owner] else v_members end;

    if v_diff in (3, 0) then
      r := public.notification_bump(r, 'bill_due_soon', public.enqueue_notification(
        p_house_id, v_users, 'bill_due_soon', 'despesas',
        e.title || case when v_diff = 0 then ' vence hoje' else ' vence em 3 dias' end,
        e.title || case when v_diff = 0 then ' vence hoje: ' else ' vence em 3 dias: ' end
          || public.notification_brl(e.amount_cents),
        '/casa', 'expense', e.id,
        'bill_due_soon:' || e.id || ':' || e.due_date || ':' || v_diff, true));
    elsif v_diff in (-1, -4, -7) then
      r := public.notification_bump(r, 'bill_overdue', public.enqueue_notification(
        p_house_id, v_users, 'bill_overdue', 'despesas',
        e.title || ' está vencida',
        e.title || ' está vencida há ' || (-v_diff) || case when v_diff = -1 then ' dia: ' else ' dias: ' end
          || public.notification_brl(e.amount_cents),
        '/casa', 'expense', e.id,
        'bill_overdue:' || e.id || ':' || e.due_date || ':' || (-v_diff), true));
    end if;

    -- Conta variável recorrente: o valor copiado do mês anterior precisa ser conferido
    if v_diff = 5 and e.is_variable and e.is_recurring then
      r := public.notification_bump(r, 'recurring_generated', public.enqueue_notification(
        p_house_id, v_users, 'recurring_generated', 'despesas',
        e.title || ' precisa do valor',
        e.title || ' de ' || public.notification_month_name(e.due_date)
          || ' precisa do valor. Vence em ' || to_char(e.due_date, 'DD/MM') || '.',
        '/casa', 'expense', e.id,
        'recurring_generated:' || e.id, true));
    end if;
  end loop;
  return r;
end;
$$;

-- ------------------------------------------------------------------------------
-- 4. Faturas: invoice_closing, invoice_due_soon
-- ------------------------------------------------------------------------------
create or replace function public.notification_sched_invoices(p_house_id uuid, p_today date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r jsonb := '{}'::jsonb;
  pm record;
  inv record;
  v_owner uuid;
  v_users uuid[];
  v_month date := date_trunc('month', p_today)::date;
  v_closing date;
  v_due date;
  v_total bigint;
  v_diff integer;
  v_members uuid[] := public.notification_house_member_ids(p_house_id);
begin
  for pm in
    select id, name, closing_day, due_day, coalesce(owner_member_id, owner_id) as owner
    from public.payment_methods
    where house_id = p_house_id and type = 'card' and coalesce(is_active, true)
      and closing_day is not null and due_day is not null
  loop
    -- Cartão sem titular é do Caixa: avisa todos os moradores
    v_users := case when pm.owner is null then v_members else array[pm.owner] end;

    -- Fecha em 2 dias: o fechamento é neste mês ou no próximo
    v_closing := public.notification_month_day(v_month, pm.closing_day);
    if v_closing < p_today then
      v_closing := public.notification_month_day((v_month + interval '1 month')::date, pm.closing_day);
    end if;
    if v_closing - p_today = 2 then
      -- Vencimento da fatura que fecha: o primeiro dia de vencimento depois do fechamento
      v_due := public.notification_month_day(date_trunc('month', v_closing)::date, pm.due_day);
      if v_due <= v_closing then
        v_due := public.notification_month_day((date_trunc('month', v_closing) + interval '1 month')::date, pm.due_day);
      end if;
      select coalesce(sum(x.amount_cents), 0) into v_total
      from public.house_expenses x
      where x.house_id = p_house_id and x.payment_method_id = pm.id and x.due_date = v_due
        and x.status = 'pending' and x.deleted_at is null and x.paid_at is null
        and x.settled_at is null and x.project_id is null and not x.is_recurring;
      if v_total > 0 then
        r := public.notification_bump(r, 'invoice_closing', public.enqueue_notification(
          p_house_id, v_users, 'invoice_closing', 'despesas',
          'Fatura ' || pm.name || ' fecha em 2 dias',
          'Fatura ' || pm.name || ' fecha dia ' || to_char(v_closing, 'DD/MM') || ': '
            || public.notification_brl(v_total) || ' até agora.',
          '/casa', 'card', pm.id,
          'invoice_closing:' || pm.id || ':' || v_closing, false));
      end if;
    end if;

    -- Fatura em aberto vence em 3 dias e no dia
    for inv in
      select x.due_date, sum(x.amount_cents)::bigint as total
      from public.house_expenses x
      where x.house_id = p_house_id and x.payment_method_id = pm.id
        and x.due_date between p_today and p_today + 3
        and x.status = 'pending' and x.deleted_at is null and x.paid_at is null
        and x.settled_at is null and x.project_id is null and not x.is_recurring
      group by x.due_date
    loop
      v_diff := inv.due_date - p_today;
      if v_diff in (3, 0) then
        r := public.notification_bump(r, 'invoice_due_soon', public.enqueue_notification(
          p_house_id, v_users, 'invoice_due_soon', 'despesas',
          'Fatura ' || pm.name || case when v_diff = 0 then ' vence hoje' else ' vence em 3 dias' end,
          'Fatura ' || pm.name || ' vence '
            || case when v_diff = 0 then 'hoje' else 'dia ' || to_char(inv.due_date, 'DD/MM') end
            || ': ' || public.notification_brl(inv.total),
          '/casa', 'card', pm.id,
          'invoice_due_soon:' || pm.id || ':' || inv.due_date || ':' || v_diff, true));
      end if;
    end loop;
  end loop;
  return r;
end;
$$;

-- ------------------------------------------------------------------------------
-- 5. Ciclo: cycle_closing_soon, cycle_ended, transfer_pending, contribution_pending
-- ------------------------------------------------------------------------------
create or replace function public.notification_sched_cycle(p_house_id uuid, p_today date, p_tz text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r jsonb := '{}'::jsonb;
  c record;
  prev record;
  t record;
  m record;
  v_created date;
  v_days integer;
  v_fixed boolean;
begin
  select * into c from public.notification_cycle_for(p_house_id, p_today);
  select (h.created_at at time zone p_tz)::date, h.default_split_model = 'fixed'
  into v_created, v_fixed from public.houses h where h.id = p_house_id;

  -- O ciclo termina em 3 dias (hoje, amanhã e depois: o dia 3 é o penúltimo)
  if c.cycle_end - p_today = 2
     and not exists (select 1 from public.settlements s
                     where s.house_id = p_house_id and s.cycle_start_date = c.cycle_start
                       and s.status in ('confirmed', 'completed')) then
    r := public.notification_bump(r, 'cycle_closing_soon', public.enqueue_notification(
      p_house_id, public.notification_house_member_ids(p_house_id),
      'cycle_closing_soon', 'fechamento',
      'O ciclo fecha em 3 dias',
      'O ciclo de ' || public.notification_month_name(c.cycle_start) || ' fecha em 3 dias. Confira seus lançamentos.',
      '/fechamento?ciclo=' || to_char(c.cycle_start, 'YYYY-MM-DD'), 'cycle', null,
      'cycle_closing_soon:' || p_house_id || ':' || c.cycle_start, false));
  end if;

  -- O ciclo anterior terminou e não foi fechado: no dia seguinte e 3 dias depois
  select * into prev from public.notification_cycle_for(p_house_id, c.cycle_start - 1);
  v_days := p_today - prev.cycle_end;
  if v_days in (1, 4)
     and prev.cycle_end >= v_created
     and not exists (select 1 from public.settlements s
                     where s.house_id = p_house_id and s.cycle_start_date = prev.cycle_start
                       and s.status in ('confirmed', 'completed')) then
    r := public.notification_bump(r, 'cycle_ended', public.enqueue_notification(
      p_house_id, public.notification_house_admin_ids(p_house_id),
      'cycle_ended', 'fechamento',
      'O ciclo terminou',
      'O ciclo de ' || public.notification_month_name(prev.cycle_start) || ' terminou. Faça o fechamento.',
      '/fechamento?ciclo=' || to_char(prev.cycle_start, 'YYYY-MM-DD'), 'cycle', null,
      'cycle_ended:' || p_house_id || ':' || prev.cycle_start || ':' || v_days, true));
  end if;

  -- Super Pix ainda não pago: 2 dias depois do fechamento e a cada 3 dias
  for t in
    select tr.id, tr.from_member_id, tr.to_member_id, tr.amount_cents,
           s.cycle_start_date, (s.settled_at at time zone p_tz)::date as settled_on
    from public.settlement_transfers tr
    join public.settlements s on s.id = tr.settlement_id
    where s.house_id = p_house_id and tr.status = 'pending'
      and s.status in ('confirmed', 'completed') and s.settled_at is not null
      and p_today - (s.settled_at at time zone p_tz)::date in (2, 5, 8)
  loop
    r := public.notification_bump(r, 'transfer_pending', public.enqueue_notification(
      p_house_id, array[t.from_member_id], 'transfer_pending', 'fechamento',
      'Falta pagar o Super Pix',
      'Falta pagar ' || public.notification_brl(t.amount_cents) || ' a '
        || public.notification_first_name(t.to_member_id) || ' do ciclo de '
        || public.notification_month_name(t.cycle_start_date) || '.',
      '/fechamento?ciclo=' || to_char(t.cycle_start_date, 'YYYY-MM-DD'), 'settlement_transfer', t.id,
      'transfer_pending:' || t.id || ':' || (p_today - t.settled_on), true));
  end loop;

  -- Aportes fixos: 5 dias depois do início do ciclo, quem ainda não aportou
  if v_fixed and p_today - c.cycle_start = 5 then
    for m in
      select hm.user_id, hm.default_fixed_amount_cents as amount
      from public.house_members hm
      where hm.house_id = p_house_id and hm.left_at is null
        and coalesce(hm.default_fixed_amount_cents, 0) > 0
        and (hm.joined_at at time zone p_tz)::date <= c.cycle_start
        and not exists (select 1 from public.contributions co
                        where co.house_id = p_house_id and co.member_id = hm.user_id
                          and co.cycle_start_date = c.cycle_start and co.amount_cents > 0)
    loop
      r := public.notification_bump(r, 'contribution_pending', public.enqueue_notification(
        p_house_id, array[m.user_id], 'contribution_pending', 'caixinhas',
        'Seu aporte ainda não entrou',
        'Seu aporte de ' || public.notification_brl(m.amount) || ' do ciclo iniciado em '
          || to_char(c.cycle_start, 'DD/MM') || ' ainda não entrou.',
        '/casa', 'cycle', null,
        'contribution_pending:' || p_house_id || ':' || m.user_id || ':' || c.cycle_start, true));
    end loop;
  end if;
  return r;
end;
$$;

-- ------------------------------------------------------------------------------
-- 6. Empréstimos: installment_due_soon, installment_overdue
--    Só parcelas que NÃO entram no fechamento (sem acerto no ciclo ou sem prazo);
--    as que entram são cobradas pelo próprio fechamento.
-- ------------------------------------------------------------------------------
create or replace function public.notification_sched_loans(p_house_id uuid, p_today date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r jsonb := '{}'::jsonb;
  i record;
  v_loan public.p2p_loans%rowtype;
  v_diff integer;
  v_what text;
  v_lender text;
begin
  for i in
    select ins.id, ins.loan_id, ins.installment_number, ins.due_date,
           ins.amount_cents - ins.paid_cents as remaining
    from public.p2p_installments ins
    join public.p2p_loans l on l.id = ins.loan_id
    where l.house_id = p_house_id
      and l.status in ('active', 'renegotiated')
      and ins.status in ('pending', 'partial')
      and (l.repayment_mode = 'open_ended' or not l.settle_in_cycle)
      and ins.due_date between p_today - 11 and p_today + 3
  loop
    v_diff := i.due_date - p_today;
    select * into v_loan from public.p2p_loans where id = i.loan_id;
    v_lender := case when v_loan.lender_is_house then 'o Caixa da Casa'
                     else public.notification_first_name(v_loan.lender_id) end;
    v_what := 'Parcela ' || i.installment_number || '/' || v_loan.installments_count;

    if v_diff in (3, 0) then
      r := public.notification_bump(r, 'installment_due_soon', public.enqueue_notification(
        p_house_id, array[v_loan.borrower_id], 'installment_due_soon', 'emprestimos',
        v_what || case when v_diff = 0 then ' vence hoje' else ' vence em 3 dias' end,
        v_what || ' a ' || v_lender || case when v_diff = 0 then ' vence hoje: ' else ' vence em 3 dias: ' end
          || public.notification_brl(i.remaining),
        '/pessoal/emprestimo/' || v_loan.id, 'p2p_loan', v_loan.id,
        'installment_due_soon:' || i.id || ':' || i.due_date || ':' || v_diff, true));
    elsif v_diff in (-1, -6, -11) then
      r := public.notification_bump(r, 'installment_overdue', public.enqueue_notification(
        p_house_id, array[v_loan.borrower_id] || public.notification_loan_lender_side(v_loan),
        'installment_overdue', 'emprestimos',
        v_what || ' está vencida',
        v_what || ' de ' || v_loan.title || ' está vencida há ' || (-v_diff)
          || case when v_diff = -1 then ' dia: ' else ' dias: ' end || public.notification_brl(i.remaining),
        '/pessoal/emprestimo/' || v_loan.id, 'p2p_loan', v_loan.id,
        'installment_overdue:' || i.id || ':' || i.due_date || ':' || (-v_diff), true));
    end if;
  end loop;
  return r;
end;
$$;

-- ------------------------------------------------------------------------------
-- 7. Tarefas: task_due_soon, task_overdue
-- ------------------------------------------------------------------------------
create or replace function public.notification_sched_tasks(p_house_id uuid, p_today date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r jsonb := '{}'::jsonb;
  t record;
begin
  for t in
    select id, title, due_date, assigned_to, created_by, visibility
    from public.tasks
    where house_id = p_house_id and not is_completed and assigned_to is not null
      and due_date between p_today - 3 and p_today
  loop
    -- Tarefa particular só vale para quem criou
    continue when t.visibility = 'private' and t.assigned_to is distinct from t.created_by;

    if t.due_date = p_today then
      r := public.notification_bump(r, 'task_due_soon', public.enqueue_notification(
        p_house_id, array[t.assigned_to], 'task_due_soon', 'tarefas',
        t.title || ' vence hoje', t.title || ' vence hoje.',
        '/tarefas/' || t.id, 'task', t.id,
        'task_due_soon:' || t.id || ':' || t.due_date, false));
    else
      -- Uma vez só, mesmo que o job atrase até 3 dias
      r := public.notification_bump(r, 'task_overdue', public.enqueue_notification(
        p_house_id, array[t.assigned_to, t.created_by], 'task_overdue', 'tarefas',
        t.title || ' está atrasada', t.title || ' está atrasada desde ' || to_char(t.due_date, 'DD/MM') || '.',
        '/tarefas/' || t.id, 'task', t.id,
        'task_overdue:' || t.id || ':' || t.due_date, true));
    end if;
  end loop;
  return r;
end;
$$;

-- ------------------------------------------------------------------------------
-- 8. Agenda: event_reminder
--    Com horário: a cada hora, de 30 a 90 minutos antes do início.
--    Dia inteiro: na véspera, junto com os lembretes de dia.
-- ------------------------------------------------------------------------------
create or replace function public.notification_sched_events(
  p_house_id uuid, p_now timestamptz, p_today date, p_tz text, p_daily boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r jsonb := '{}'::jsonb;
  e record;
  v_users uuid[];
begin
  for e in
    select ev.id, ev.title, ev.start_time, ev.is_all_day
    from public.events ev
    where ev.house_id = p_house_id and ev.visibility <> 'private'
      and (
        (not ev.is_all_day and ev.start_time > p_now + interval '30 minutes'
                           and ev.start_time <= p_now + interval '90 minutes')
        or (p_daily and ev.is_all_day and (ev.start_time at time zone p_tz)::date = p_today + 1)
      )
  loop
    select coalesce(array_agg(p.user_id), '{}'::uuid[]) into v_users
    from public.event_participants p
    where p.event_id = e.id and p.rsvp_status <> 'declined';

    r := public.notification_bump(r, 'event_reminder', public.enqueue_notification(
      p_house_id, v_users, 'event_reminder', 'agenda',
      case when e.is_all_day then e.title || ' é amanhã' else e.title || ' começa em 1 hora' end,
      case when e.is_all_day then e.title || ' é amanhã.'
           else e.title || ' começa às ' || to_char(e.start_time at time zone p_tz, 'HH24:MI') || '.' end,
      '/agenda/evento/' || e.id, 'event', e.id,
      'event_reminder:' || e.id || ':' || extract(epoch from e.start_time)::bigint, false));
  end loop;
  return r;
end;
$$;

-- ------------------------------------------------------------------------------
-- 9. Conta (sem casa): premium_expiring, premium_expired, accounts_pending_daily
--    O dia da conta é o de Brasília; os avisos saem a partir das 9h.
-- ------------------------------------------------------------------------------
create or replace function public.notification_sched_accounts(p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r jsonb := '{}'::jsonb;
  a record;
  v_local timestamp := p_now at time zone 'America/Sao_Paulo';
  v_key text;
  v_pending integer;
begin
  if extract(hour from v_local) < 9 then
    return r;
  end if;

  -- Premium vence em até 7 dias (uma vez por validade)
  for a in
    select user_id, plan_expires_at from public.account_status
    where status = 'active' and plan = 'premium'
      and plan_expires_at > p_now and plan_expires_at <= p_now + interval '7 days'
  loop
    v_key := 'premium_expiring:' || extract(epoch from a.plan_expires_at)::bigint;
    if not exists (select 1 from public.notifications n where n.user_id = a.user_id and n.dedupe_key = v_key) then
      perform public.notify_account(
        a.user_id, 'premium_expiring', 'Seu Premium está acabando',
        'Seu Premium vence em ' || to_char(a.plan_expires_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
        '/ajustes', v_key);
      r := public.notification_bump(r, 'premium_expiring', 1);
    end if;
  end loop;

  -- Premium venceu (uma vez por validade; só se venceu nos últimos 14 dias,
  -- para não avisar de um vencimento antigo)
  for a in
    select user_id, plan_expires_at from public.account_status
    where status = 'active' and plan = 'premium'
      and plan_expires_at <= p_now and plan_expires_at > p_now - interval '14 days'
  loop
    v_key := 'premium_expired:' || extract(epoch from a.plan_expires_at)::bigint;
    if not exists (select 1 from public.notifications n where n.user_id = a.user_id and n.dedupe_key = v_key) then
      perform public.notify_account(
        a.user_id, 'premium_expired', 'Seu Premium venceu',
        'Seu Premium venceu. A conta voltou para o Free',
        '/ajustes', v_key);
      r := public.notification_bump(r, 'premium_expired', 1);
    end if;
  end loop;

  -- Administradores: contas esperando aprovação, uma vez por dia
  select count(*) into v_pending from public.account_status where status = 'pending';
  if v_pending > 0 then
    for a in
      select pa.user_id from public.platform_admins pa
      join public.account_status s on s.user_id = pa.user_id and s.status = 'active'
    loop
      v_key := 'accounts_pending:' || v_local::date;
      if not exists (select 1 from public.notifications n where n.user_id = a.user_id and n.dedupe_key = v_key) then
        perform public.notify_account(
          a.user_id, 'accounts_pending_daily', 'Contas esperando aprovação',
          case when v_pending = 1 then '1 conta esperando aprovação'
               else v_pending || ' contas esperando aprovação' end,
          '/admin?aba=aprovacoes', v_key);
        r := public.notification_bump(r, 'accounts_pending_daily', 1);
      end if;
    end loop;
  end if;
  return r;
end;
$$;

-- ------------------------------------------------------------------------------
-- 10. A função do agendador
-- ------------------------------------------------------------------------------
-- p_now permite ensaiar com datas simuladas. Com p_strict, um erro numa casa
-- interrompe tudo (ensaios); sem ele, a casa com erro é pulada com um aviso e
-- as demais seguem.
create or replace function public.run_scheduled_notifications(
  p_now timestamptz default now(),
  p_strict boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_counts jsonb := '{}'::jsonb;
  v_part jsonb;
  v_item record;
  h record;
  v_local timestamp;
  v_today date;
  v_daily boolean;
  v_houses integer := 0;
begin
  for h in
    select id, coalesce(nullif(timezone, ''), 'America/Sao_Paulo') as tz from public.houses
  loop
    begin
      v_local := p_now at time zone h.tz;
      v_today := v_local::date;
      -- Lembretes de dia: a partir das 9h no fuso da casa
      v_daily := extract(hour from v_local) >= 9;
      v_houses := v_houses + 1;

      v_part := public.notification_sched_events(h.id, p_now, v_today, h.tz, v_daily);
      if v_daily then
        v_part := v_part
          || public.notification_sched_bills(h.id, v_today)
          || public.notification_sched_invoices(h.id, v_today)
          || public.notification_sched_cycle(h.id, v_today, h.tz)
          || public.notification_sched_loans(h.id, v_today)
          || public.notification_sched_tasks(h.id, v_today);
      end if;

      for v_item in select key, value::integer as n from jsonb_each_text(v_part) loop
        v_counts := public.notification_bump(v_counts, v_item.key, v_item.n);
      end loop;
    exception when others then
      if p_strict then raise; end if;
      raise warning 'run_scheduled_notifications: casa % ignorada: %', h.id, sqlerrm;
    end;
  end loop;

  begin
    v_part := public.notification_sched_accounts(p_now);
    for v_item in select key, value::integer as n from jsonb_each_text(v_part) loop
      v_counts := public.notification_bump(v_counts, v_item.key, v_item.n);
    end loop;
  exception when others then
    if p_strict then raise; end if;
    raise warning 'run_scheduled_notifications: avisos de conta ignorados: %', sqlerrm;
  end;

  return jsonb_build_object('houses', v_houses, 'created', v_counts);
end;
$$;

-- ------------------------------------------------------------------------------
-- 11. Push segurado pelo horário silencioso
--    A função notify devolve o aviso como pendente com push_after no fim do
--    horário. O job libera o que vence nos próximos 10 minutos (o push_after
--    leva os segundos de quem o gravou) e chama a notify de novo. Também
--    recupera chamadas que se perderam (pendente ou reservado há mais de 10
--    minutos).
-- ------------------------------------------------------------------------------
create or replace function public.release_held_push_notifications()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_released integer;
  v_waiting boolean;
begin
  update public.notifications
  set push_after = now()
  where push_status = 'pending' and push_after is not null
    and push_after > now() and push_after <= now() + interval '10 minutes'
    and created_at > now() - interval '2 days';
  get diagnostics v_released = row_count;

  select exists (
    select 1 from public.notifications n
    where n.created_at > now() - interval '2 days'
      and (
        (n.push_status = 'pending' and (n.push_after is null or n.push_after <= now()))
        or (n.push_status = 'sending' and n.pushed_at < now() - interval '10 minutes')
      )
  ) into v_waiting;

  if v_waiting then
    perform public.dispatch_push_notifications();
  end if;
  return v_waiting;
end;
$$;

-- O que o job chama: lembretes e depois a liberação, mesmo que os lembretes falhem
create or replace function public.run_notification_job()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  begin
    v_result := public.run_scheduled_notifications(now());
  exception when others then
    raise warning 'run_notification_job: lembretes falharam: %', sqlerrm;
    v_result := jsonb_build_object('error', sqlerrm);
  end;
  perform public.release_held_push_notifications();
  return v_result;
end;
$$;

-- Liga o job de hora em hora (minuto 0). Esta migration só cria a função;
-- quem a chama é o dono do projeto, com o aval dele:
--   select public.schedule_notification_jobs();
-- Para desligar: select cron.unschedule('omnilar-notifications-hourly');
create or replace function public.schedule_notification_jobs()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job bigint;
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'omnilar-notifications-hourly';
  select cron.schedule(
    'omnilar-notifications-hourly', '0 * * * *', 'select public.run_notification_job()'
  ) into v_job;
  return v_job;
end;
$$;

-- Nada disto é para o app: só o banco (job) e o dono, pelo painel do Supabase
revoke execute on function public.notification_month_day(date, integer) from public, anon, authenticated;
revoke execute on function public.notification_regular_cycle(date, integer) from public, anon, authenticated;
revoke execute on function public.notification_cycle_for(uuid, date) from public, anon, authenticated;
revoke execute on function public.notification_bump(jsonb, text, integer) from public, anon, authenticated;
revoke execute on function public.notification_house_member_ids(uuid) from public, anon, authenticated;
revoke execute on function public.notification_house_admin_ids(uuid) from public, anon, authenticated;
revoke execute on function public.notification_sched_bills(uuid, date) from public, anon, authenticated;
revoke execute on function public.notification_sched_invoices(uuid, date) from public, anon, authenticated;
revoke execute on function public.notification_sched_cycle(uuid, date, text) from public, anon, authenticated;
revoke execute on function public.notification_sched_loans(uuid, date) from public, anon, authenticated;
revoke execute on function public.notification_sched_tasks(uuid, date) from public, anon, authenticated;
revoke execute on function public.notification_sched_events(uuid, timestamptz, date, text, boolean) from public, anon, authenticated;
revoke execute on function public.notification_sched_accounts(timestamptz) from public, anon, authenticated;
revoke execute on function public.run_scheduled_notifications(timestamptz, boolean) from public, anon, authenticated;
revoke execute on function public.release_held_push_notifications() from public, anon, authenticated;
revoke execute on function public.run_notification_job() from public, anon, authenticated;
revoke execute on function public.schedule_notification_jobs() from public, anon, authenticated;
