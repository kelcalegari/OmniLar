-- ==============================================================================
-- 0084: Marca "Pix enviado" no Super Pix (decisão 11 de plano_proximas_frentes.md)
-- Descrição:
--   O fechamento continua gravando cada transferência como confirmada (o que
--   não é marcado como parcial conta como pago). O que faltava era saber se o
--   Pix foi mandado de verdade:
--   - settlement_transfers ganha pix_sent_at e pix_sent_by;
--   - mark_settlement_transfer_sent: quem paga ("Já mandei") ou quem recebe
--     ("Recebi") marca; a primeira marca vale. Quando quem paga marca, quem
--     recebe ganha um aviso (transfer_sent);
--   - o lembrete transfer_pending (2, 5 e 8 dias depois do fechamento) passa a
--     sair para quem paga enquanto não houver a marca.
--   A conta do fechamento não muda.
-- ==============================================================================

alter table public.settlement_transfers
  add column if not exists pix_sent_at timestamptz,
  add column if not exists pix_sent_by uuid references auth.users(id) on delete set null;

-- Fechamentos antigos: o lembrete não volta para eles
update public.settlement_transfers set pix_sent_at = coalesce(paid_at, created_at)
where pix_sent_at is null;

create or replace function public.mark_settlement_transfer_sent(p_transfer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_transfer record;
begin
  select tr.*, s.house_id, s.cycle_start_date into v_transfer
  from public.settlement_transfers tr
  join public.settlements s on s.id = tr.settlement_id
  where tr.id = p_transfer_id
  for update of tr;
  if not found or not public.is_house_member(v_transfer.house_id) then
    raise exception 'Transferência não encontrada.';
  end if;
  if v_user is distinct from v_transfer.from_member_id and v_user is distinct from v_transfer.to_member_id then
    raise exception 'Só quem paga ou quem recebe pode marcar o Pix.';
  end if;
  if v_transfer.pix_sent_at is not null then
    return;
  end if;

  update public.settlement_transfers set pix_sent_at = now(), pix_sent_by = v_user
  where id = p_transfer_id;

  if v_user = v_transfer.from_member_id then
    perform public.enqueue_notification(
      v_transfer.house_id, array[v_transfer.to_member_id],
      'transfer_sent', 'fechamento',
      'Pix enviado',
      public.notification_first_name(v_user) || ' mandou o Pix de '
        || public.notification_brl(v_transfer.amount_cents) || ' do ciclo de '
        || public.notification_month_name(v_transfer.cycle_start_date) || '.',
      '/fechamento?ciclo=' || to_char(v_transfer.cycle_start_date, 'YYYY-MM-DD'),
      'settlement_transfer', p_transfer_id,
      'transfer_sent:' || p_transfer_id, false, '{}'::jsonb,
      null, null, null, v_transfer.amount_cents
    );
  end if;
end;
$$;

revoke execute on function public.mark_settlement_transfer_sent(uuid) from public, anon;
grant execute on function public.mark_settlement_transfer_sent(uuid) to authenticated, service_role;

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

  -- Super Pix sem a marca "Pix enviado" (0084): 2 dias depois do fechamento e a cada 3 dias
  for t in
    select tr.id, tr.from_member_id, tr.to_member_id, tr.amount_cents,
           s.cycle_start_date, (s.settled_at at time zone p_tz)::date as settled_on
    from public.settlement_transfers tr
    join public.settlements s on s.id = tr.settlement_id
    where s.house_id = p_house_id and tr.pix_sent_at is null
      and s.status in ('confirmed', 'completed') and s.settled_at is not null
      and p_today - (s.settled_at at time zone p_tz)::date in (2, 5, 8)
  loop
    r := public.notification_bump(r, 'transfer_pending', public.enqueue_notification(
      p_house_id, array[t.from_member_id], 'transfer_pending', 'fechamento',
      'Falta mandar o Super Pix',
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
