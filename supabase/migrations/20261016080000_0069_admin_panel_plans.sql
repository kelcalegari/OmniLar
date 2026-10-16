-- ==============================================================================
-- 0069: Painel administrativo, fase B: planos Free e Premium
-- Descrição (Documentacao/plano_painel_admin.md, decisões de 16/10/2026):
--   - account_status ganha plan (free ou premium), plan_expires_at (vazio =
--     sem validade) e plan_note. Vencida a validade, a conta conta como Free
--     na hora de usar (account_plan); nada é apagado.
--   - As contas que já existem viram Premium sem validade, "conta inicial"
--     (decisão 9): nada muda para quem já usa.
--   - A casa segue o plano de quem é o dono dela no momento (decisão 1).
--   - plan_limits: limite por plano e recurso, editável pelo painel. Vazio =
--     sem limite. Free: 10 leituras de IA por dia, 1 casa, 4 moradores,
--     1 projeto ativo. Premium: 100 leituras, 3 casas, 20 moradores, projetos
--     sem limite. O PDF dos relatórios não é limitado (decisão 3).
--   - Limites aplicados no banco: criar casa, entrar em casa (por qualquer
--     caminho) e criar ou reabrir projeto. A cota de IA vem de
--     house_ai_daily_limit, lida pelas Edge Functions.
--   - Painel: admin_set_plan (com validade e observação, aviso à pessoa),
--     admin_get_plan_limits e admin_set_plan_limit; listas e detalhe mostram o plano.
-- ==============================================================================

-- 1. Plano na conta
alter table public.account_status
  add column if not exists plan text not null default 'free',
  add column if not exists plan_expires_at timestamptz,
  add column if not exists plan_note text;

alter table public.account_status
  drop constraint if exists account_status_plan_check;
alter table public.account_status
  add constraint account_status_plan_check check (plan in ('free', 'premium'));

-- Quem já usa o app fica Premium (decisão 9)
update public.account_status
set plan = 'premium', plan_expires_at = null, plan_note = 'conta inicial'
where plan = 'free' and plan_note is null;

-- 2. Limites por plano
create table if not exists public.plan_limits (
  plan text not null check (plan in ('free', 'premium')),
  resource text not null check (resource in ('ai_reads_per_day', 'houses_owned', 'members_per_house', 'active_projects')),
  max_value integer check (max_value is null or max_value >= 0),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  primary key (plan, resource)
);
alter table public.plan_limits enable row level security;
revoke all on public.plan_limits from anon, authenticated;

insert into public.plan_limits (plan, resource, max_value) values
  ('free', 'ai_reads_per_day', 10),
  ('free', 'houses_owned', 1),
  ('free', 'members_per_house', 4),
  ('free', 'active_projects', 1),
  ('premium', 'ai_reads_per_day', 100),
  ('premium', 'houses_owned', 3),
  ('premium', 'members_per_house', 20),
  ('premium', 'active_projects', null)
on conflict (plan, resource) do nothing;

-- 3. Plano que vale na hora de usar
create or replace function public.account_plan(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select case
      when s.plan = 'premium' and (s.plan_expires_at is null or s.plan_expires_at > now()) then 'premium'
      else 'free'
    end
    from public.account_status s where s.user_id = p_user_id
  ), 'free');
$$;
revoke execute on function public.account_plan(uuid) from public, anon, authenticated;

-- A casa segue o plano de quem é o dono dela no momento (o melhor, se houver mais de um)
create or replace function public.house_plan(p_house_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case when bool_or(public.account_plan(m.user_id) = 'premium') then 'premium' else 'free' end
  from public.house_members m
  where m.house_id = p_house_id and m.role = 'owner' and m.left_at is null;
$$;
revoke execute on function public.house_plan(uuid) from public, anon, authenticated;

-- Limite do recurso no plano (nulo = sem limite)
create or replace function public.plan_limit(p_plan text, p_resource text)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select l.max_value from public.plan_limits l where l.plan = p_plan and l.resource = p_resource;
$$;
revoke execute on function public.plan_limit(text, text) from public, anon, authenticated;

create or replace function public.plan_label(p_plan text)
returns text
language sql
immutable
set search_path = public
as $$
  select case when p_plan = 'premium' then 'Premium' else 'Free' end;
$$;

-- Cota diária de IA da casa (lida pelas Edge Functions; só para quem mora nela)
create or replace function public.house_ai_daily_limit(p_house_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_house_member(p_house_id) then
    raise exception 'Você não participa desta casa.';
  end if;
  return public.plan_limit(public.house_plan(p_house_id), 'ai_reads_per_day');
end;
$$;
revoke execute on function public.house_ai_daily_limit(uuid) from public, anon;
grant execute on function public.house_ai_daily_limit(uuid) to authenticated;

-- 4. Limites aplicados no banco
-- Criar casa: conta liberada (0068) e dentro do limite de casas como dono
create or replace function public.guard_house_creation_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text;
  v_limit integer;
  v_owned integer;
begin
  -- Sem sessão (manutenção pelo SQL Editor): não há conta a conferir
  if auth.uid() is null then
    return new;
  end if;
  if not public.account_is_active(auth.uid()) then
    raise exception 'Sua conta ainda não foi liberada para criar uma casa.';
  end if;

  v_plan := public.account_plan(auth.uid());
  v_limit := public.plan_limit(v_plan, 'houses_owned');
  if v_limit is not null then
    select count(*) into v_owned
    from public.house_members m join public.houses h on h.id = m.house_id
    where m.user_id = auth.uid() and m.role = 'owner' and m.left_at is null;
    if v_owned >= v_limit then
      raise exception 'No plano % você pode ter até % casa(s) como dono.', public.plan_label(v_plan), v_limit;
    end if;
  end if;
  return new;
end;
$$;

-- Entrar em casa: conta liberada (0068) e casa dentro do limite de moradores
create or replace function public.guard_house_member_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text;
  v_limit integer;
  v_members integer;
begin
  if tg_op = 'UPDATE' and not (old.left_at is not null and new.left_at is null) then
    return new;
  end if;
  if auth.uid() is null then
    return new;
  end if;
  if not public.account_is_active(new.user_id) then
    raise exception '%', case when new.user_id = auth.uid()
      then 'Sua conta ainda não foi liberada para entrar em uma casa.'
      else 'Esta conta ainda não foi liberada para entrar em uma casa.' end;
  end if;

  -- O dono que cria a casa ainda não tem plano de casa: conta como o primeiro morador
  v_plan := case when new.role = 'owner' then public.account_plan(new.user_id) else public.house_plan(new.house_id) end;
  v_limit := public.plan_limit(v_plan, 'members_per_house');
  if v_limit is not null then
    select count(*) into v_members
    from public.house_members m
    where m.house_id = new.house_id and m.left_at is null and m.user_id <> new.user_id;
    if v_members >= v_limit then
      raise exception 'No plano % a casa tem até % moradores.', public.plan_label(v_plan), v_limit;
    end if;
  end if;
  return new;
end;
$$;

-- Projeto ativo novo ou reaberto: dentro do limite de projetos ativos da casa
create or replace function public.guard_project_plan_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text;
  v_limit integer;
  v_active integer;
begin
  if auth.uid() is null or new.deleted_at is not null or new.status not in ('planning', 'active') then
    return new;
  end if;
  -- Edição de projeto que já era ativo não conta de novo
  if tg_op = 'UPDATE' and old.deleted_at is null and old.status in ('planning', 'active') then
    return new;
  end if;

  v_plan := public.house_plan(new.house_id);
  v_limit := public.plan_limit(v_plan, 'active_projects');
  if v_limit is not null then
    select count(*) into v_active
    from public.shared_projects p
    where p.house_id = new.house_id and p.id <> new.id
      and p.deleted_at is null and p.status in ('planning', 'active');
    if v_active >= v_limit then
      raise exception 'No plano % a casa tem até % projeto(s) ativo(s). Conclua ou arquive um projeto antes.',
        public.plan_label(v_plan), v_limit;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_project_plan_limit on public.shared_projects;
create trigger trg_guard_project_plan_limit
  before insert or update of status, deleted_at on public.shared_projects
  for each row execute function public.guard_project_plan_limit();

-- 5. O app sabe o próprio plano
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
    'is_admin', public.is_platform_admin(),
    'plan', public.account_plan(auth.uid()),
    'plan_expires_at', (select s.plan_expires_at from public.account_status s
                        where s.user_id = auth.uid() and s.plan = 'premium')
  );
$$;

-- 6. Painel: plano nas listas, no detalhe e na visão geral
drop function if exists public.admin_list_accounts(text, text, integer);
create function public.admin_list_accounts(
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
  is_admin boolean,
  plan text,
  plan_expires_at timestamptz,
  plan_note text
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
    exists (select 1 from public.platform_admins a where a.user_id = u.id),
    public.account_plan(u.id),
    s.plan_expires_at,
    s.plan_note
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
revoke execute on function public.admin_list_accounts(text, text, integer) from public, anon;
grant execute on function public.admin_list_accounts(text, text, integer) to authenticated;

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
    'plan', public.account_plan(u.id),
    'plan_expires_at', s.plan_expires_at,
    'plan_note', s.plan_note,
    'houses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', h.name, 'role', hm.role, 'joined_at', hm.joined_at, 'plan', public.house_plan(h.id)) order by hm.joined_at)
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
    'accounts_by_plan', coalesce((
      select jsonb_object_agg(plan, n) from (
        select public.account_plan(user_id) as plan, count(*) as n from public.account_status group by 1
      ) x), '{}'::jsonb),
    'premium_expiring_30d', (
      select count(*) from public.account_status
      where plan = 'premium' and plan_expires_at between now() and now() + interval '30 days'
    ),
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

-- 7. Trocar o plano (uma ou várias contas), com validade e observação
create or replace function public.admin_set_plan(
  p_user_ids uuid[],
  p_plan text,
  p_expires_at timestamptz default null,
  p_note text default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_target uuid;
  v_old public.account_status%rowtype;
  v_done integer := 0;
  v_stamp text := to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS');
  v_until text;
begin
  perform public.require_platform_admin();
  if p_plan not in ('free', 'premium') then
    raise exception 'Plano inválido.';
  end if;
  if p_plan = 'premium' and p_expires_at is not null and p_expires_at <= now() then
    raise exception 'A validade do Premium precisa ser uma data futura.';
  end if;

  for v_target in select distinct unnest(coalesce(p_user_ids, '{}')) loop
    select * into v_old from public.account_status where user_id = v_target for update;
    if not found then
      continue;
    end if;
    if v_old.plan = p_plan
       and v_old.plan_expires_at is not distinct from (case when p_plan = 'premium' then p_expires_at end)
       and v_old.plan_note is not distinct from v_note then
      continue;
    end if;

    update public.account_status
    set plan = p_plan,
        plan_expires_at = case when p_plan = 'premium' then p_expires_at end,
        plan_note = v_note,
        updated_at = now()
    where user_id = v_target;

    insert into public.admin_audit_log (actor_id, action, target_user_id, details)
    values (v_uid, 'set_plan', v_target, jsonb_build_object(
      'from', v_old.plan, 'to', p_plan,
      'expires_at', case when p_plan = 'premium' then p_expires_at end,
      'note', v_note));

    v_until := case when p_plan = 'premium' and p_expires_at is not null
      then ' até ' || to_char(p_expires_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') else '' end;
    perform public.notify_account(v_target, 'account_plan', 'Plano alterado',
      'Sua conta agora é ' || public.plan_label(p_plan) || v_until || '.',
      '/ajustes', 'account_plan:' || v_target || ':' || v_stamp);

    v_done := v_done + 1;
  end loop;
  return v_done;
end;
$$;

-- 8. Limites editáveis no painel
create or replace function public.admin_get_plan_limits()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.require_platform_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object('plan', plan, 'resource', resource, 'max_value', max_value)
                     order by plan, resource)
    from public.plan_limits), '[]'::jsonb);
end;
$$;

create or replace function public.admin_set_plan_limit(p_plan text, p_resource text, p_max_value integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old integer;
begin
  perform public.require_platform_admin();
  if p_max_value is not null and p_max_value < 0 then
    raise exception 'O limite não pode ser negativo.';
  end if;
  select max_value into v_old from public.plan_limits where plan = p_plan and resource = p_resource for update;
  if not found then
    raise exception 'Limite não encontrado.';
  end if;
  update public.plan_limits
  set max_value = p_max_value, updated_at = now(), updated_by = auth.uid()
  where plan = p_plan and resource = p_resource;
  insert into public.admin_audit_log (actor_id, action, details)
  values (auth.uid(), 'set_plan_limit', jsonb_build_object(
    'plan', p_plan, 'resource', p_resource, 'from', v_old, 'to', p_max_value));
end;
$$;

revoke execute on function public.admin_set_plan(uuid[], text, timestamptz, text) from public, anon;
revoke execute on function public.admin_get_plan_limits() from public, anon;
revoke execute on function public.admin_set_plan_limit(text, text, integer) from public, anon;
grant execute on function public.admin_set_plan(uuid[], text, timestamptz, text) to authenticated;
grant execute on function public.admin_get_plan_limits() to authenticated;
grant execute on function public.admin_set_plan_limit(text, text, integer) to authenticated;
