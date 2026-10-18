-- ==============================================================================
-- 0094: Padrões do fechamento
-- Descrição:
--   1. closing_defaults: as escolhas que o fechamento já abre marcadas (quem
--      fecha ainda pode mudar cada uma naquele ciclo):
--      - surplus_action: destino da sobra (to_vault, rollover, refund);
--      - surplus_vault_id: caixinha que recebe a sobra;
--      - deficit_split: rateio do que passou do balde (proportional, equal);
--      - deficit_vault_id: caixinha que cobre o excedente antes do rateio;
--      - shortfall_action: diferença de quem pagou menos (create_p2p_loan,
--        deduct_from_vault, rollover_pending, forgive_remainder).
--      Sem escolha, vale o de antes. Caixinha que não existe mais é ignorada
--      pelo app (não há chave estrangeira dentro do jsonb).
--   2. update_house_settings passa a gravar e devolver closing_defaults
--      (objeto inteiro, só administradores). O resto segue como na 0092.
-- ==============================================================================

create or replace function public.closing_defaults_valid(p_defaults jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_defaults) = 'object'
    and not exists (
      select 1 from jsonb_each(p_defaults) e
      where e.key not in ('surplus_action', 'surplus_vault_id', 'deficit_split', 'deficit_vault_id', 'shortfall_action')
        or jsonb_typeof(e.value) <> 'string'
        or (e.key = 'surplus_action'
            and e.value #>> '{}' not in ('to_vault', 'rollover', 'refund'))
        or (e.key = 'deficit_split'
            and e.value #>> '{}' not in ('proportional', 'equal'))
        or (e.key = 'shortfall_action'
            and e.value #>> '{}' not in ('create_p2p_loan', 'deduct_from_vault', 'rollover_pending', 'forgive_remainder'))
        or (e.key in ('surplus_vault_id', 'deficit_vault_id')
            and e.value #>> '{}' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
    );
$$;

alter table public.houses
  add column if not exists closing_defaults jsonb not null default '{}'::jsonb
    check (public.closing_defaults_valid(closing_defaults));

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

  update public.houses set
    opening_balance_rule = case when p_settings ? 'opening_balance_rule'
      then nullif(p_settings->>'opening_balance_rule', '') else opening_balance_rule end,
    opening_inflow_rules = coalesce(p_settings->'opening_inflow_rules', opening_inflow_rules),
    closing_defaults = coalesce(p_settings->'closing_defaults', closing_defaults),
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
    'planner_history_cycles', v_row.planner_history_cycles,
    'planner_mode', v_row.planner_mode,
    'planner_adjust_percent', v_row.planner_adjust_percent,
    'planner_category_overrides', v_row.planner_category_overrides
  );
end;
$$;

revoke execute on function public.update_house_settings(uuid, jsonb) from public, anon;
grant execute on function public.update_house_settings(uuid, jsonb) to authenticated, service_role;
