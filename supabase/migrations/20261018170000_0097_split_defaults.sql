-- ==============================================================================
-- 0097: Divisão padrão por categoria e política de divisão para novo morador
-- Descrição:
--   1. categories.default_split: divisão que o lançamento de despesa da
--      categoria já abre marcada (sugestão; quem lança ainda escolhe outra).
--      Mesmo formato da divisão de despesas (split_type), em jsonb:
--        {"type": "percentage", "percentages": {"<morador>": 60, "<morador>": 40}}
--        {"type": "category_owner", "member_id": "<morador>"}
--      Os percentuais somam 100. Valor fixo não entra: o valor da despesa muda
--      a cada lançamento. Nulo = a categoria não tem padrão e vale o padrão de
--      cada morador (member_settings, 0095) e, sem ele, o rateio da casa.
--      Morador que saiu da casa depois de escolhido é ignorado pelo app (não há
--      chave estrangeira dentro do jsonb). Quem pode alterar segue a regra de
--      categories_update_admin_or_owner.
--   2. houses.new_member_split_policy: o que acontece com o rateio padrão
--      (house_members.default_split_percent) quando alguém entra por convite:
--        equal        - fatia igual para quem chega, os demais encolhem (como
--                       na 0023; continua sendo o padrão);
--        keep_current - ninguém muda: quem chega começa com 0% e os
--                       administradores ajustam depois;
--        ask          - igual a keep_current, e o app avisa nos Ajustes que
--                       há morador sem parte na divisão.
--   3. join_house_with_invite lê a política (resto como na 0068).
--   4. update_house_settings grava e devolve new_member_split_policy (só
--      administradores). O resto segue como na 0094.
-- ==============================================================================

create or replace function public.category_default_split_valid(p_split jsonb)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  v_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  v_total numeric;
begin
  if p_split is null then
    return true;
  end if;
  if jsonb_typeof(p_split) <> 'object' or jsonb_typeof(p_split->'type') <> 'string' then
    return false;
  end if;

  if p_split->>'type' = 'category_owner' then
    return not exists (select 1 from jsonb_object_keys(p_split) k where k not in ('type', 'member_id'))
      and jsonb_typeof(p_split->'member_id') = 'string'
      and p_split->>'member_id' ~* v_uuid;
  end if;

  if p_split->>'type' = 'percentage' then
    if exists (select 1 from jsonb_object_keys(p_split) k where k not in ('type', 'percentages'))
        or jsonb_typeof(p_split->'percentages') <> 'object' then
      return false;
    end if;
    if exists (
      select 1 from jsonb_each(p_split->'percentages') e
      where e.key !~* v_uuid
         or jsonb_typeof(e.value) <> 'number'
         or (e.value #>> '{}')::numeric < 0
         or (e.value #>> '{}')::numeric > 100
    ) then
      return false;
    end if;
    select coalesce(sum((e.value #>> '{}')::numeric), 0) into v_total
    from jsonb_each(p_split->'percentages') e;
    return abs(v_total - 100) <= 0.01;
  end if;

  return false;
end;
$$;

alter table public.categories
  add column if not exists default_split jsonb
    check (public.category_default_split_valid(default_split));

comment on column public.categories.default_split is
  'Divisão que o lançamento da categoria já abre marcada (percentage ou category_owner). Nulo: sem padrão.';

alter table public.houses
  add column if not exists new_member_split_policy text not null default 'equal'
    check (new_member_split_policy in ('equal', 'keep_current', 'ask'));

comment on column public.houses.new_member_split_policy is
  'Rateio padrão ao entrar um morador: equal (fatia igual), keep_current (quem chega começa com 0%) ou ask (igual, com aviso aos administradores).';

-- ------------------------------------------------------------------------------
-- Entrada por convite: respeita a política da casa
-- ------------------------------------------------------------------------------
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

    select * into v_house from public.houses where id = v_invite.house_id;

    select count(*), coalesce(sum(coalesce(default_split_percent, 0)), 0)
    into v_members, v_total
    from public.house_members
    where house_id = v_invite.house_id and left_at is null;

    if v_members = 0 then
      v_new_percent := 100;
    elsif v_house.new_member_split_policy in ('keep_current', 'ask') then
      -- Ninguém muda: quem chega começa sem parte até os administradores ajustarem
      v_new_percent := 0;
    else
      -- Fatia igual para quem chega; os demais encolhem na mesma proporção
      v_new_percent := round(100.0 / (v_members + 1), 2);

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

revoke execute on function public.join_house_with_invite(text) from public, anon;
grant execute on function public.join_house_with_invite(text) to authenticated;

-- ------------------------------------------------------------------------------
-- update_house_settings: aceita new_member_split_policy
-- ------------------------------------------------------------------------------
create or replace function public.update_house_settings(p_house_id uuid, p_settings jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.houses%rowtype;
begin
  if auth.uid() is null or not public.is_house_member(p_house_id) then
    raise exception 'Você não faz parte desta casa.';
  end if;
  if (p_settings ? 'opening_balance_rule' or p_settings ? 'opening_inflow_rules')
      and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam como a sobra entra no rateio.';
  end if;
  if p_settings ? 'opening_inflow_rules'
      and not public.opening_inflow_rules_valid(p_settings->'opening_inflow_rules') then
    raise exception 'Regra das entradas no Caixa inválida.';
  end if;
  if p_settings ? 'closing_defaults' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam os padrões do fechamento.';
  end if;
  if p_settings ? 'closing_defaults'
      and not public.closing_defaults_valid(p_settings->'closing_defaults') then
    raise exception 'Padrões do fechamento inválidos.';
  end if;
  if p_settings ? 'new_member_split_policy' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam a divisão para quem entra na casa.';
  end if;
  if p_settings ? 'new_member_split_policy'
      and coalesce(p_settings->>'new_member_split_policy', '') not in ('equal', 'keep_current', 'ask') then
    raise exception 'Política de divisão para novo morador inválida.';
  end if;

  update public.houses set
    opening_balance_rule = case when p_settings ? 'opening_balance_rule'
      then nullif(p_settings->>'opening_balance_rule', '') else opening_balance_rule end,
    opening_inflow_rules = coalesce(p_settings->'opening_inflow_rules', opening_inflow_rules),
    closing_defaults = coalesce(p_settings->'closing_defaults', closing_defaults),
    new_member_split_policy = coalesce(p_settings->>'new_member_split_policy', new_member_split_policy),
    planner_history_cycles = coalesce((p_settings->>'planner_history_cycles')::smallint, planner_history_cycles),
    planner_mode = coalesce(p_settings->>'planner_mode', planner_mode),
    planner_adjust_percent = coalesce((p_settings->>'planner_adjust_percent')::smallint, planner_adjust_percent),
    planner_category_overrides = coalesce(p_settings->'planner_category_overrides', planner_category_overrides)
  where id = p_house_id
  returning * into v_row;

  return jsonb_build_object(
    'opening_balance_rule', v_row.opening_balance_rule,
    'opening_inflow_rules', v_row.opening_inflow_rules,
    'closing_defaults', v_row.closing_defaults,
    'new_member_split_policy', v_row.new_member_split_policy,
    'planner_history_cycles', v_row.planner_history_cycles,
    'planner_mode', v_row.planner_mode,
    'planner_adjust_percent', v_row.planner_adjust_percent,
    'planner_category_overrides', v_row.planner_category_overrides
  );
end;
$$;

revoke execute on function public.update_house_settings(uuid, jsonb) from public, anon;
grant execute on function public.update_house_settings(uuid, jsonb) to authenticated, service_role;

notify pgrst, 'reload schema';
