-- ==============================================================================
-- 0064: Base das notificações
-- Descrição:
--   Primeira fase do plano_notificacoes.md. A tabela notifications (0001)
--   ganha o que falta para servir de histórico do sino: chave de repetição,
--   grupo, item de origem, autor, peso, agrupamento de rajadas e situação do
--   push. Entram também os tokens de aparelho, as preferências por grupo, as
--   configurações gerais (horário silencioso único, esconder valores, resumo
--   semanal) e a função enqueue_notification, que só os gatilhos do banco
--   chamam: quem gera a notificação é o banco, nunca o app.
--   O morador lê as dele e só consegue marcar como lida (coluna read_at).
--   A tabela entra no tempo real, para o sino atualizar sozinho.
-- ==============================================================================

-- 1. Colunas novas
alter table public.notifications
  add column if not exists category text not null default 'casa',
  add column if not exists dedupe_key text,
  add column if not exists group_key text,
  add column if not exists entity_type text,
  add column if not exists entity_id uuid,
  add column if not exists actor_id uuid references auth.users(id) on delete set null,
  add column if not exists is_essential boolean not null default false,
  add column if not exists push_status text not null default 'skipped',
  add column if not exists pushed_at timestamptz;

alter table public.notifications
  drop constraint if exists notifications_category_check,
  add constraint notifications_category_check check (category in (
    'casa', 'despesas', 'fechamento', 'emprestimos', 'caixinhas',
    'compras', 'tarefas', 'agenda', 'projetos', 'assistente'
  )),
  drop constraint if exists notifications_push_status_check,
  add constraint notifications_push_status_check check (push_status in (
    'pending', 'sent', 'skipped', 'failed'
  ));

-- Uma vez só: a mesma chave não cria outra notificação para o mesmo morador
create unique index if not exists uq_notifications_user_dedupe
  on public.notifications (user_id, dedupe_key)
  where dedupe_key is not null;

create index if not exists idx_notifications_user_created
  on public.notifications (user_id, created_at desc);

create index if not exists idx_notifications_group
  on public.notifications (user_id, group_key, created_at desc)
  where group_key is not null and read_at is null;

create index if not exists idx_notifications_push_pending
  on public.notifications (created_at)
  where push_status = 'pending';

-- 2. Só marcar como lida: as demais colunas não mudam pelo app
revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;

-- 3. Tokens de aparelho (push, fase 4)
create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android', 'web', 'ios_pwa')),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index if not exists idx_device_tokens_user on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

drop policy if exists "device_tokens_own" on public.device_tokens;
create policy "device_tokens_own" on public.device_tokens for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- 4. Preferências por grupo
create table if not exists public.notification_preferences (
  user_id uuid not null references auth.users(id) on delete cascade,
  house_id uuid not null references public.houses(id) on delete cascade,
  category text not null check (category in (
    'casa', 'despesas', 'fechamento', 'emprestimos', 'caixinhas',
    'compras', 'tarefas', 'agenda', 'projetos', 'assistente'
  )),
  in_app boolean not null default true,
  push boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (user_id, house_id, category)
);

alter table public.notification_preferences enable row level security;

drop policy if exists "notification_preferences_own" on public.notification_preferences;
create policy "notification_preferences_own" on public.notification_preferences for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and public.is_house_member(house_id));

-- 5. Configurações gerais (decisões 2a, 4a e 8a do plano)
create table if not exists public.notification_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  quiet_hours_start time,
  quiet_hours_end time,
  hide_amounts boolean not null default false,
  weekly_summary boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.notification_settings enable row level security;

drop policy if exists "notification_settings_own" on public.notification_settings;
create policy "notification_settings_own" on public.notification_settings for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- 6. Auxiliares de texto
create or replace function public.notification_brl(p_cents bigint)
returns text
language sql
immutable
set search_path = public
as $$
  select 'R$ ' || replace(replace(replace(
    to_char(coalesce(p_cents, 0) / 100.0, 'FM999,999,999,990.00'),
    ',', 'X'), '.', ','), 'X', '.');
$$;

create or replace function public.notification_first_name(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(split_part(trim((select full_name from public.profiles where id = p_user_id)), ' ', 1), ''),
    'Alguém'
  );
$$;

create or replace function public.notification_month_name(p_date date)
returns text
language sql
immutable
set search_path = public
as $$
  select (array['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho',
                'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'])[extract(month from p_date)::int];
$$;

-- 7. Gravação das notificações (só os gatilhos chamam)
--   p_user_ids: destinatários candidatos. Saem o autor (auth.uid()), quem não
--   mora na casa e quem desligou o grupo no app (a não ser que seja essencial).
--   p_dedupe_key: chave de repetição; gravar de novo não cria outra.
--   p_group_key: agrupa rajadas. Se o morador tem uma não lida com a mesma
--   chave nos últimos 10 minutos, ela é atualizada em vez de criar outra:
--   {n} vira a contagem e {total} a soma de p_amount_cents em p_group_title e
--   p_group_body, e o deeplink passa a p_group_deeplink (a lista, em vez do
--   item).
--   Devolve quantas notificações foram criadas ou atualizadas.
create or replace function public.enqueue_notification(
  p_house_id uuid,
  p_user_ids uuid[],
  p_type text,
  p_category text,
  p_title text,
  p_body text,
  p_deeplink text default null,
  p_entity_type text default null,
  p_entity_id uuid default null,
  p_dedupe_key text default null,
  p_is_essential boolean default false,
  p_payload jsonb default '{}'::jsonb,
  p_group_key text default null,
  p_group_title text default null,
  p_group_body text default null,
  p_amount_cents bigint default null,
  p_group_deeplink text default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_user uuid;
  v_existing public.notifications%rowtype;
  v_count integer;
  v_total bigint;
  v_done integer := 0;
  v_rows integer;
begin
  for v_user in
    select distinct u
    from unnest(coalesce(p_user_ids, '{}'::uuid[])) as u
    where u is not null
      and u is distinct from v_actor
      and exists (
        select 1 from public.house_members m
        where m.house_id = p_house_id and m.user_id = u and m.left_at is null
      )
      and (
        p_is_essential
        or not exists (
          select 1 from public.notification_preferences np
          where np.user_id = u and np.house_id = p_house_id
            and np.category = p_category and not np.in_app
        )
      )
  loop
    if p_group_key is not null then
      select * into v_existing
      from public.notifications
      where user_id = v_user
        and group_key = p_group_key
        and read_at is null
        and created_at > now() - interval '10 minutes'
      order by created_at desc
      limit 1
      for update;

      if found then
        v_count := coalesce((v_existing.payload->>'count')::int, 1) + 1;
        v_total := coalesce((v_existing.payload->>'total_cents')::bigint, 0) + coalesce(p_amount_cents, 0);
        update public.notifications
        set title = replace(replace(coalesce(p_group_title, p_title), '{n}', v_count::text),
                            '{total}', public.notification_brl(v_total)),
            body = replace(replace(coalesce(p_group_body, p_body), '{n}', v_count::text),
                           '{total}', public.notification_brl(v_total)),
            payload = v_existing.payload
              || jsonb_build_object('count', v_count, 'total_cents', v_total),
            deeplink = coalesce(p_group_deeplink, deeplink),
            entity_id = null,
            created_at = now(),
            -- O push sai de novo com o texto do grupo (substitui o anterior no aparelho)
            push_status = case when exists (select 1 from public.device_tokens t where t.user_id = v_user)
                               then 'pending' else push_status end
        where id = v_existing.id;
        v_done := v_done + 1;
        continue;
      end if;
    end if;

    insert into public.notifications (
      house_id, user_id, type, category, title, body, payload, deeplink,
      entity_type, entity_id, actor_id, is_essential, dedupe_key, group_key,
      push_status
    ) values (
      p_house_id, v_user, p_type, p_category, p_title, p_body,
      coalesce(p_payload, '{}'::jsonb)
        || case when p_group_key is not null
             then jsonb_build_object('count', 1, 'total_cents', coalesce(p_amount_cents, 0))
             else '{}'::jsonb end,
      p_deeplink, p_entity_type, p_entity_id, v_actor, p_is_essential,
      p_dedupe_key, p_group_key,
      case when exists (select 1 from public.device_tokens t where t.user_id = v_user)
           then 'pending' else 'skipped' end
    )
    on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
    get diagnostics v_rows = row_count;
    v_done := v_done + v_rows;
  end loop;

  return v_done;
end;
$$;

revoke execute on function public.enqueue_notification(
  uuid, uuid[], text, text, text, text, text, text, uuid, text, boolean, jsonb, text, text, text, bigint, text
) from public, anon, authenticated;
revoke execute on function public.notification_first_name(uuid) from public, anon, authenticated;

-- 8. Tempo real do sino (o app assina filtrando por user_id)
alter table public.notifications replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
