-- ==============================================================================
-- 0068: Painel administrativo, fase A: administradores, status da conta e aprovação
-- Descrição (Documentacao/plano_painel_admin.md, decisões de 16/10/2026):
--   - platform_admins: quem administra o app. O primeiro é incluído à mão no
--     SQL Editor; depois, pelo painel. Ser administrador não abre os dados
--     das casas: is_platform_admin() não entra nas regras das tabelas da casa.
--   - account_status: status de cada conta (pending, active, rejected,
--     suspended). O usuário só lê a própria linha; ninguém grava direto.
--     As contas que já existem nascem active.
--   - app_settings: aprovação ligada, convite aprova direto, domínios e
--     e-mails aprovados direto.
--   - admin_audit_log: tudo o que os administradores fazem.
--   - Conta não liberada não cria casa nem entra em casa, por nenhum caminho:
--     gatilhos em houses e house_members valem para as funções e para a
--     inserção direta. Convite válido aprova a conta pendente (decisão 2).
--   - Avisos de conta pelo sino (categoria nova "conta", sempre ativa) e aviso
--     aos administradores quando uma conta nova espera aprovação.
--   - Funções do painel: admin_overview, admin_list_accounts,
--     admin_account_detail, admin_set_account_status, admin_get_settings,
--     admin_update_settings, admin_list_audit e admin_set_platform_admin.
-- ==============================================================================

-- 1. Administradores do app
create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);
alter table public.platform_admins enable row level security;
revoke all on public.platform_admins from anon, authenticated;

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.platform_admins where user_id = auth.uid());
$$;
revoke execute on function public.is_platform_admin() from public, anon;
grant execute on function public.is_platform_admin() to authenticated;

-- 2. Status da conta
create table if not exists public.account_status (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'active', 'rejected', 'suspended')),
  status_reason text,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.account_status enable row level security;
revoke all on public.account_status from anon, authenticated;
grant select on public.account_status to authenticated;

drop policy if exists "account_status_select_own" on public.account_status;
create policy "account_status_select_own" on public.account_status for select
  using (user_id = auth.uid());

-- Quem já usa o app continua usando
insert into public.account_status (user_id, status, approved_at)
select u.id, 'active', now() from auth.users u
on conflict (user_id) do nothing;

-- A tela de espera muda sozinha quando a conta é aprovada
alter table public.account_status replica identity full;
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'account_status'
  ) then
    alter publication supabase_realtime add table public.account_status;
  end if;
end;
$$;

-- Uso interno (gatilhos e funções do banco): não é exposta ao app
create or replace function public.account_is_active(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select s.status = 'active' from public.account_status s where s.user_id = p_user_id), false);
$$;
revoke execute on function public.account_is_active(uuid) from public, anon, authenticated;

-- A conta de quem chama está liberada? (usada pelas Edge Functions)
create or replace function public.is_account_active()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.account_is_active(auth.uid());
$$;
revoke execute on function public.is_account_active() from public, anon;
grant execute on function public.is_account_active() to authenticated;

-- 3. Parâmetros (uma linha só)
create table if not exists public.app_settings (
  id boolean primary key default true check (id),
  require_approval boolean not null default true,
  auto_approve_invited boolean not null default true,
  auto_approve_domains text[] not null default '{}',
  auto_approve_emails text[] not null default '{}',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
alter table public.app_settings enable row level security;
revoke all on public.app_settings from anon, authenticated;
insert into public.app_settings (id) values (true) on conflict (id) do nothing;

-- 4. Histórico do painel
create table if not exists public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_user_id uuid references auth.users(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.admin_audit_log enable row level security;
revoke all on public.admin_audit_log from anon, authenticated;
create index if not exists idx_admin_audit_log_created on public.admin_audit_log (created_at desc);
create index if not exists idx_admin_audit_log_target on public.admin_audit_log (target_user_id, created_at desc);

-- 5. Avisos de conta: categoria nova, sempre ativa, fora de qualquer casa
alter table public.notifications
  drop constraint if exists notifications_category_check,
  add constraint notifications_category_check check (category in (
    'casa', 'despesas', 'fechamento', 'emprestimos', 'caixinhas',
    'compras', 'tarefas', 'agenda', 'projetos', 'assistente', 'conta'
  ));
alter table public.notification_preferences
  drop constraint if exists notification_preferences_category_check,
  add constraint notification_preferences_category_check check (category in (
    'casa', 'despesas', 'fechamento', 'emprestimos', 'caixinhas',
    'compras', 'tarefas', 'agenda', 'projetos', 'assistente', 'conta'
  ));

create or replace function public.notify_account(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_deeplink text,
  p_dedupe_key text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (
    house_id, user_id, type, category, title, body, deeplink,
    entity_type, entity_id, actor_id, is_essential, dedupe_key, push_status
  ) values (
    null, p_user_id, p_type, 'conta', p_title, p_body, p_deeplink,
    'account', p_user_id, auth.uid(), true, p_dedupe_key,
    case when exists (select 1 from public.device_tokens t where t.user_id = p_user_id)
         then 'pending' else 'skipped' end
  )
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
end;
$$;
revoke execute on function public.notify_account(uuid, text, text, text, text, text) from public, anon, authenticated;

-- 6. Status inicial no cadastro
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settings public.app_settings%rowtype;
  v_email text := lower(coalesce(new.email, ''));
  v_status text;
  v_name text := coalesce(new.raw_user_meta_data->>'full_name', new.email, 'Usuário');
  v_admin uuid;
begin
  insert into public.profiles (id, full_name, email, avatar_url, phone)
  values (
    new.id,
    v_name,
    new.email,
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'phone'
  )
  on conflict (id) do update set
    full_name = coalesce(excluded.full_name, public.profiles.full_name),
    email = coalesce(excluded.email, public.profiles.email);

  select * into v_settings from public.app_settings where id;
  v_status := case
    when not coalesce(v_settings.require_approval, true) then 'active'
    when v_email <> '' and v_email = any(coalesce(v_settings.auto_approve_emails, '{}')) then 'active'
    when v_email like '%@%' and split_part(v_email, '@', 2) = any(coalesce(v_settings.auto_approve_domains, '{}')) then 'active'
    else 'pending'
  end;

  insert into public.account_status (user_id, status, approved_at)
  values (new.id, v_status, case when v_status = 'active' then now() end)
  on conflict (user_id) do nothing;

  if v_status = 'pending' then
    for v_admin in select user_id from public.platform_admins loop
      perform public.notify_account(
        v_admin, 'account_pending', 'Conta esperando aprovação',
        v_name || coalesce(' (' || new.email || ')', '') || ' se cadastrou e espera aprovação.',
        '/admin?aba=aprovacoes', 'account_pending:' || new.id::text
      );
    end loop;
  end if;

  return new;
end;
$$;

-- 7. Conta não liberada não cria casa nem entra em casa (vale para as funções e para a inserção direta)
create or replace function public.guard_house_creation_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Sem sessão (manutenção pelo SQL Editor): não há conta a conferir
  if auth.uid() is not null and not public.account_is_active(auth.uid()) then
    raise exception 'Sua conta ainda não foi liberada para criar uma casa.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_house_creation_account on public.houses;
create trigger trg_guard_house_creation_account
  before insert on public.houses
  for each row execute function public.guard_house_creation_account();

create or replace function public.guard_house_member_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and not (old.left_at is not null and new.left_at is null) then
    return new;
  end if;
  if auth.uid() is not null and not public.account_is_active(new.user_id) then
    raise exception '%', case when new.user_id = auth.uid()
      then 'Sua conta ainda não foi liberada para entrar em uma casa.'
      else 'Esta conta ainda não foi liberada para entrar em uma casa.' end;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_house_member_account on public.house_members;
create trigger trg_guard_house_member_account
  before insert or update of left_at on public.house_members
  for each row execute function public.guard_house_member_account();

-- 8. Convite válido aprova a conta pendente (decisão 2)
create or replace function public.join_house_with_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_invite public.house_invites%rowtype;
  v_house public.houses%rowtype;
  v_members integer;
  v_total numeric;
  v_new_percent numeric;
  v_status text;
begin
  if v_uid is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;

  select * into v_invite
  from public.house_invites
  where code = upper(trim(p_code))
  for update;

  if not found or v_invite.used_at is not null or v_invite.expires_at <= now() then
    raise exception 'Código de convite inválido ou expirado.';
  end if;

  select status into v_status from public.account_status where user_id = v_uid for update;
  if v_status = 'pending' and coalesce((select auto_approve_invited from public.app_settings where id), false) then
    update public.account_status
    set status = 'active', status_reason = null, approved_at = now(), approved_by = null, updated_at = now()
    where user_id = v_uid;
    insert into public.admin_audit_log (actor_id, action, target_user_id, details)
    values (v_uid, 'auto_approve_invite', v_uid, jsonb_build_object('house_id', v_invite.house_id));
  elsif v_status is distinct from 'active' then
    raise exception 'Sua conta ainda não foi liberada para entrar em uma casa.';
  end if;

  -- Quem já mora na casa não consome o convite
  if not exists (
    select 1 from public.house_members
    where house_id = v_invite.house_id and user_id = v_uid and left_at is null
  ) then
    perform 1 from public.house_members
    where house_id = v_invite.house_id and left_at is null
    for update;

    select count(*), coalesce(sum(coalesce(default_split_percent, 0)), 0)
    into v_members, v_total
    from public.house_members
    where house_id = v_invite.house_id and left_at is null;

    -- Fatia igual para quem chega; os demais encolhem na mesma proporção
    v_new_percent := round(100.0 / (v_members + 1), 2);

    if v_members > 0 then
      if v_total > 0 then
        update public.house_members
        set default_split_percent = round(coalesce(default_split_percent, 0) * (100 - v_new_percent) / v_total, 2)
        where house_id = v_invite.house_id and left_at is null;
      else
        update public.house_members
        set default_split_percent = round((100 - v_new_percent) / v_members, 2)
        where house_id = v_invite.house_id and left_at is null;
      end if;

      -- Quem chega absorve os centésimos do arredondamento
      select 100 - sum(default_split_percent) into v_new_percent
      from public.house_members
      where house_id = v_invite.house_id and left_at is null;
    end if;

    insert into public.house_members (house_id, user_id, role, default_split_percent)
    values (v_invite.house_id, v_uid, v_invite.role, v_new_percent)
    on conflict (house_id, user_id) do update
      set left_at = null,
          role = excluded.role,
          joined_at = now(),
          default_split_percent = excluded.default_split_percent;

    update public.house_invites
    set used_at = now(), used_by = v_uid
    where id = v_invite.id;
  end if;

  select * into v_house from public.houses where id = v_invite.house_id;
  return to_jsonb(v_house);
end;
$$;

-- 9. O que o app pergunta ao abrir: status da própria conta e se administra o app
create or replace function public.my_account_access()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'status', coalesce((select s.status from public.account_status s where s.user_id = auth.uid()), 'pending'),
    'reason', (select s.status_reason from public.account_status s where s.user_id = auth.uid()),
    'is_admin', public.is_platform_admin()
  );
$$;
revoke execute on function public.my_account_access() from public, anon;
grant execute on function public.my_account_access() to authenticated;

-- 10. Funções do painel (todas conferem o administrador)
create or replace function public.require_platform_admin()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Acesso restrito à administração do Omni Lar.';
  end if;
end;
$$;
revoke execute on function public.require_platform_admin() from public, anon, authenticated;

-- Visão geral: só contagens, nunca dados financeiros das casas
create or replace function public.admin_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz text := 'America/Sao_Paulo';
  v_today timestamptz := date_trunc('day', now() at time zone v_tz) at time zone v_tz;
  v_month timestamptz := date_trunc('month', now() at time zone v_tz) at time zone v_tz;
begin
  perform public.require_platform_admin();
  return jsonb_build_object(
    'accounts_total', (select count(*) from auth.users),
    'accounts_by_status', coalesce((
      select jsonb_object_agg(status, n) from (
        select status, count(*) as n from public.account_status group by status
      ) x), '{}'::jsonb),
    'accounts_new_7d', (select count(*) from auth.users where created_at > now() - interval '7 days'),
    'houses_total', (select count(*) from public.houses),
    'houses_active_30d', (
      select count(distinct e.house_id) from public.house_expenses e
      where e.created_at > now() - interval '30 days'
    ),
    'ai_reads_today', (select count(*) from public.ai_usage where created_at >= v_today),
    'ai_reads_month', (select count(*) from public.ai_usage where created_at >= v_month),
    'admins', (select count(*) from public.platform_admins)
  );
end;
$$;

create or replace function public.admin_list_accounts(
  p_search text default null,
  p_status text default null,
  p_limit integer default 200
)
returns table (
  user_id uuid,
  full_name text,
  email text,
  status text,
  status_reason text,
  created_at timestamptz,
  last_sign_in_at timestamptz,
  approved_at timestamptz,
  houses integer,
  is_admin boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_search text := nullif(lower(btrim(coalesce(p_search, ''))), '');
begin
  perform public.require_platform_admin();
  return query
  select
    u.id,
    coalesce(p.full_name, u.email)::text,
    u.email::text,
    coalesce(s.status, 'pending'),
    s.status_reason,
    u.created_at,
    u.last_sign_in_at,
    s.approved_at,
    (select count(*)::int from public.house_members hm where hm.user_id = u.id and hm.left_at is null),
    exists (select 1 from public.platform_admins a where a.user_id = u.id)
  from auth.users u
  left join public.profiles p on p.id = u.id
  left join public.account_status s on s.user_id = u.id
  where (v_search is null
         or lower(coalesce(p.full_name, '')) like '%' || v_search || '%'
         or lower(coalesce(u.email, '')) like '%' || v_search || '%')
    and (p_status is null or coalesce(s.status, 'pending') = p_status)
  order by (coalesce(s.status, 'pending') = 'pending') desc, u.created_at desc
  limit greatest(1, least(coalesce(p_limit, 200), 1000));
end;
$$;

create or replace function public.admin_account_detail(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz text := 'America/Sao_Paulo';
  v_result jsonb;
begin
  perform public.require_platform_admin();
  select jsonb_build_object(
    'user_id', u.id,
    'full_name', coalesce(p.full_name, u.email),
    'email', u.email,
    'phone', p.phone,
    'status', coalesce(s.status, 'pending'),
    'status_reason', s.status_reason,
    'approved_at', s.approved_at,
    'approved_by_name', (select full_name from public.profiles where id = s.approved_by),
    'created_at', u.created_at,
    'last_sign_in_at', u.last_sign_in_at,
    'is_admin', exists (select 1 from public.platform_admins a where a.user_id = u.id),
    'houses', coalesce((
      select jsonb_agg(jsonb_build_object('name', h.name, 'role', hm.role, 'joined_at', hm.joined_at) order by hm.joined_at)
      from public.house_members hm join public.houses h on h.id = hm.house_id
      where hm.user_id = u.id and hm.left_at is null), '[]'::jsonb),
    'ai_reads_today', (select count(*) from public.ai_usage a
      where a.member_id = u.id and a.created_at >= date_trunc('day', now() at time zone v_tz) at time zone v_tz),
    'ai_reads_month', (select count(*) from public.ai_usage a
      where a.member_id = u.id and a.created_at >= date_trunc('month', now() at time zone v_tz) at time zone v_tz),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'action', l.action,
        'actor_name', (select full_name from public.profiles where id = l.actor_id),
        'details', l.details,
        'created_at', l.created_at) order by l.created_at desc)
      from (select * from public.admin_audit_log where target_user_id = u.id order by created_at desc limit 50) l), '[]'::jsonb)
  ) into v_result
  from auth.users u
  left join public.profiles p on p.id = u.id
  left join public.account_status s on s.user_id = u.id
  where u.id = p_user_id;

  if v_result is null then
    raise exception 'Conta não encontrada.';
  end if;
  return v_result;
end;
$$;

-- Aprovar, recusar, suspender ou reativar (uma ou várias contas)
create or replace function public.admin_set_account_status(
  p_user_ids uuid[],
  p_status text,
  p_reason text default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_target uuid;
  v_old text;
  v_done integer := 0;
  v_stamp text := to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS');
begin
  perform public.require_platform_admin();
  if p_status not in ('active', 'rejected', 'suspended') then
    raise exception 'Status inválido.';
  end if;
  if p_status in ('rejected', 'suspended') and v_reason is null then
    raise exception 'Informe o motivo.';
  end if;
  if v_uid = any(coalesce(p_user_ids, '{}')) then
    raise exception 'Você não pode mudar o status da sua própria conta.';
  end if;

  for v_target in select distinct unnest(coalesce(p_user_ids, '{}')) loop
    if not exists (select 1 from auth.users where id = v_target) then
      continue;
    end if;

    select status into v_old from public.account_status where user_id = v_target for update;
    if v_old is null then
      insert into public.account_status (user_id, status) values (v_target, 'pending');
      v_old := 'pending';
    end if;
    if v_old = p_status then
      continue;
    end if;

    update public.account_status
    set status = p_status,
        status_reason = case when p_status = 'active' then null else v_reason end,
        approved_by = case when p_status = 'active' then v_uid else approved_by end,
        approved_at = case when p_status = 'active' then now() else approved_at end,
        updated_at = now()
    where user_id = v_target;

    insert into public.admin_audit_log (actor_id, action, target_user_id, details)
    values (v_uid, 'set_status', v_target,
            jsonb_build_object('from', v_old, 'to', p_status, 'reason', v_reason));

    if p_status = 'active' and v_old = 'pending' then
      perform public.notify_account(v_target, 'account_approved', 'Conta aprovada',
        'Sua conta foi aprovada. Bem-vindo ao Omni Lar!', '/casa', 'account_status:' || v_target || ':' || v_stamp);
    elsif p_status = 'active' then
      perform public.notify_account(v_target, 'account_reactivated', 'Conta reativada',
        'Sua conta foi reativada. Você já pode usar o Omni Lar.', '/casa', 'account_status:' || v_target || ':' || v_stamp);
    elsif p_status = 'rejected' then
      perform public.notify_account(v_target, 'account_rejected', 'Acesso não aprovado',
        'Seu acesso ao Omni Lar não foi aprovado: ' || v_reason, null, 'account_status:' || v_target || ':' || v_stamp);
    else
      perform public.notify_account(v_target, 'account_suspended', 'Conta suspensa',
        'Sua conta foi suspensa: ' || v_reason, null, 'account_status:' || v_target || ':' || v_stamp);
    end if;

    v_done := v_done + 1;
  end loop;

  return v_done;
end;
$$;

create or replace function public.admin_get_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row public.app_settings%rowtype;
begin
  perform public.require_platform_admin();
  select * into v_row from public.app_settings where id;
  return jsonb_build_object(
    'require_approval', v_row.require_approval,
    'auto_approve_invited', v_row.auto_approve_invited,
    'auto_approve_domains', to_jsonb(v_row.auto_approve_domains),
    'auto_approve_emails', to_jsonb(v_row.auto_approve_emails),
    'updated_at', v_row.updated_at,
    'updated_by_name', (select full_name from public.profiles where id = v_row.updated_by)
  );
end;
$$;

create or replace function public.admin_update_settings(
  p_require_approval boolean,
  p_auto_approve_invited boolean,
  p_auto_approve_domains text[],
  p_auto_approve_emails text[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old public.app_settings%rowtype;
  v_domains text[];
  v_emails text[];
begin
  perform public.require_platform_admin();
  -- Domínio sem "@" e tudo em minúsculas, sem repetição nem vazio
  select coalesce(array_agg(distinct d order by d), '{}') into v_domains
  from (select lower(btrim(ltrim(btrim(x), '@'))) as d from unnest(coalesce(p_auto_approve_domains, '{}')) x) t
  where d <> '';
  select coalesce(array_agg(distinct e order by e), '{}') into v_emails
  from (select lower(btrim(x)) as e from unnest(coalesce(p_auto_approve_emails, '{}')) x) t
  where e <> '';
  if exists (select 1 from unnest(v_emails) e where e not like '%_@_%') then
    raise exception 'Há um e-mail inválido na lista.';
  end if;

  select * into v_old from public.app_settings where id for update;
  update public.app_settings
  set require_approval = coalesce(p_require_approval, v_old.require_approval),
      auto_approve_invited = coalesce(p_auto_approve_invited, v_old.auto_approve_invited),
      auto_approve_domains = v_domains,
      auto_approve_emails = v_emails,
      updated_at = now(),
      updated_by = auth.uid()
  where id;

  insert into public.admin_audit_log (actor_id, action, details)
  values (auth.uid(), 'update_settings', jsonb_build_object(
    'require_approval', coalesce(p_require_approval, v_old.require_approval),
    'auto_approve_invited', coalesce(p_auto_approve_invited, v_old.auto_approve_invited),
    'auto_approve_domains', to_jsonb(v_domains),
    'auto_approve_emails', to_jsonb(v_emails)));
end;
$$;

create or replace function public.admin_list_audit(p_limit integer default 100)
returns table (
  created_at timestamptz,
  action text,
  actor_name text,
  target_user_id uuid,
  target_name text,
  details jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.require_platform_admin();
  return query
  select l.created_at, l.action,
         (select p.full_name from public.profiles p where p.id = l.actor_id)::text,
         l.target_user_id,
         (select p.full_name from public.profiles p where p.id = l.target_user_id)::text,
         l.details
  from public.admin_audit_log l
  order by l.created_at desc
  limit greatest(1, least(coalesce(p_limit, 100), 500));
end;
$$;

-- Incluir ou tirar outro administrador (nunca a si mesmo)
create or replace function public.admin_set_platform_admin(p_user_id uuid, p_is_admin boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_platform_admin();
  if p_user_id = auth.uid() then
    raise exception 'Você não pode mudar o seu próprio acesso de administrador.';
  end if;
  if not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'Conta não encontrada.';
  end if;
  if p_is_admin then
    if not public.account_is_active(p_user_id) then
      raise exception 'Só uma conta liberada pode administrar o app.';
    end if;
    insert into public.platform_admins (user_id, created_by) values (p_user_id, auth.uid())
    on conflict (user_id) do nothing;
  else
    delete from public.platform_admins where user_id = p_user_id;
  end if;
  insert into public.admin_audit_log (actor_id, action, target_user_id, details)
  values (auth.uid(), case when p_is_admin then 'grant_admin' else 'revoke_admin' end, p_user_id, '{}'::jsonb);
end;
$$;

revoke execute on function public.admin_overview() from public, anon;
revoke execute on function public.admin_list_accounts(text, text, integer) from public, anon;
revoke execute on function public.admin_account_detail(uuid) from public, anon;
revoke execute on function public.admin_set_account_status(uuid[], text, text) from public, anon;
revoke execute on function public.admin_get_settings() from public, anon;
revoke execute on function public.admin_update_settings(boolean, boolean, text[], text[]) from public, anon;
revoke execute on function public.admin_list_audit(integer) from public, anon;
revoke execute on function public.admin_set_platform_admin(uuid, boolean) from public, anon;
grant execute on function public.admin_overview() to authenticated;
grant execute on function public.admin_list_accounts(text, text, integer) to authenticated;
grant execute on function public.admin_account_detail(uuid) to authenticated;
grant execute on function public.admin_set_account_status(uuid[], text, text) to authenticated;
grant execute on function public.admin_get_settings() to authenticated;
grant execute on function public.admin_update_settings(boolean, boolean, text[], text[]) to authenticated;
grant execute on function public.admin_list_audit(integer) to authenticated;
grant execute on function public.admin_set_platform_admin(uuid, boolean) to authenticated;
