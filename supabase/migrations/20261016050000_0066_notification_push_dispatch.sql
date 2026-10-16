-- ==============================================================================
-- 0066: Envio do push das notificações
-- Descrição:
--   Fase 4 do plano_notificacoes.md. Notificação com push pendente (o morador
--   tem aparelho registrado, migration 0064) chama a Edge Function notify pelo
--   pg_net, que envia pelo FCM. A chamada não leva dados: a função busca as
--   pendentes com claim_pending_notifications, que as reserva para duas
--   chamadas ao mesmo tempo não mandarem o mesmo aviso.
--   Horário silencioso: a função devolve o aviso como pendente com push_after
--   no fim do horário; ele sai na próxima chamada depois disso (o agendador da
--   fase 5 garante uma chamada por hora).
--   O pg_net só faz a chamada depois do commit; transação desfeita não chama.
-- ==============================================================================

create extension if not exists pg_net;

alter table public.notifications
  add column if not exists push_after timestamptz;

alter table public.notifications
  drop constraint if exists notifications_push_status_check,
  add constraint notifications_push_status_check check (push_status in (
    'pending', 'sending', 'sent', 'skipped', 'failed'
  ));

drop index if exists public.idx_notifications_push_pending;
create index if not exists idx_notifications_push_pending
  on public.notifications (created_at)
  where push_status in ('pending', 'sending');

-- Reserva as pendentes para envio. Aviso com mais de 2 dias não vai mais para
-- o aparelho (continua no sino). Reserva presa há mais de 10 minutos (função
-- que caiu no meio) volta a valer.
create or replace function public.claim_pending_notifications(p_limit integer default 200)
returns setof public.notifications
language sql
security definer
set search_path = public
as $$
  update public.notifications n
  set push_status = 'sending', pushed_at = now()
  where n.id in (
    select id from public.notifications
    where created_at > now() - interval '2 days'
      and (
        (push_status = 'pending' and (push_after is null or push_after <= now()))
        or (push_status = 'sending' and pushed_at < now() - interval '10 minutes')
      )
    order by created_at
    limit greatest(coalesce(p_limit, 200), 1)
    for update skip locked
  )
  returning n.*;
$$;

revoke execute on function public.claim_pending_notifications(integer) from public, anon, authenticated;
grant execute on function public.claim_pending_notifications(integer) to service_role;

-- Chama a função notify (sem corpo: ela mesma busca o que está pendente)
create or replace function public.dispatch_push_notifications()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://rygxmpwzofgieodvhpcy.supabase.co/functions/v1/notify',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json'),
    timeout_milliseconds := 10000
  );
end;
$$;

revoke execute on function public.dispatch_push_notifications() from public, anon, authenticated;

-- Notificações novas: uma chamada por comando (um fechamento grava várias)
create or replace function public.notify_push_on_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from inserted where push_status = 'pending') then
    perform public.dispatch_push_notifications();
  end if;
  return null;
end;
$$;

drop trigger if exists trg_notify_push_on_insert on public.notifications;
create trigger trg_notify_push_on_insert
  after insert on public.notifications
  referencing new table as inserted
  for each statement execute function public.notify_push_on_insert();

-- Aviso agrupado que voltou a ficar pendente (0064): manda o texto novo
create or replace function public.notify_push_on_regroup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.dispatch_push_notifications();
  return null;
end;
$$;

drop trigger if exists trg_notify_push_on_regroup on public.notifications;
create trigger trg_notify_push_on_regroup
  after update of body on public.notifications
  for each row
  when (new.push_status = 'pending' and new.group_key is not null)
  execute function public.notify_push_on_regroup();

revoke execute on function public.notify_push_on_insert() from public, anon, authenticated;
revoke execute on function public.notify_push_on_regroup() from public, anon, authenticated;
